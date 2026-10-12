# Step 5 - Hot path: telemetry with temperature > 30 is routed to Event Hubs and handled by a Function.

resource "azurerm_eventhub_namespace" "alerts" {
  name                = var.eventhub_namespace_name
  resource_group_name = azurerm_resource_group.poc.name
  location            = azurerm_resource_group.poc.location
  sku                 = "Basic" # cheapest; only the $Default consumer group, 1 day retention
  capacity            = 1
  minimum_tls_version = "1.2"
  # Entra ID only: the hub sends and the Function receives with managed identities.
  local_authentication_enabled = false
}

resource "azurerm_eventhub" "alerts" {
  name              = "telemetry-alerts"
  namespace_id      = azurerm_eventhub_namespace.alerts.id
  partition_count   = 2
  message_retention = 1
}

resource "azurerm_role_assignment" "hub_to_alerts" {
  scope                = azurerm_eventhub.alerts.id
  role_definition_name = "Azure Event Hubs Data Sender"
  principal_id         = azurerm_iothub.hub.identity[0].principal_id
}

resource "azurerm_iothub_endpoint_eventhub" "alerts" {
  name                = "telemetry-alerts"
  resource_group_name = azurerm_resource_group.poc.name
  iothub_id           = azurerm_iothub.hub.id

  authentication_type = "identityBased"
  endpoint_uri        = "sb://${azurerm_eventhub_namespace.alerts.name}.servicebus.windows.net"
  entity_path         = azurerm_eventhub.alerts.name

  depends_on = [azurerm_role_assignment.hub_to_alerts]
}

# Body queries ($body.x) only work because the device sends contentType=application/json + utf-8.
resource "azurerm_iothub_route" "telemetry_alerts" {
  name                = "telemetry-alerts"
  resource_group_name = azurerm_resource_group.poc.name
  iothub_name         = azurerm_iothub.hub.name
  source              = "DeviceMessages"
  condition           = "$body.temperature > 30"
  endpoint_names      = [azurerm_iothub_endpoint_eventhub.alerts.name]
  enabled             = true
}

# --- Consumer: Python Function on the Flex Consumption plan (scale to zero, pay per execution) ---

resource "azurerm_storage_account" "functions" {
  name                            = var.functions_storage_account_name
  resource_group_name             = azurerm_resource_group.poc.name
  location                        = azurerm_resource_group.poc.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
  shared_access_key_enabled       = false
}

# Holds the deployed code package.
resource "azurerm_storage_container" "functions_deploy" {
  name                  = "deployment"
  storage_account_id    = azurerm_storage_account.functions.id
  container_access_type = "private"
}

# User-assigned (not system-assigned) so its roles exist before the app is created and deployed.
resource "azurerm_user_assigned_identity" "functions" {
  name                = "id-func-iot-poc"
  resource_group_name = azurerm_resource_group.poc.name
  location            = azurerm_resource_group.poc.location
}

# Code package + runtime state (Event Hubs checkpoints and partition leases are blobs).
resource "azurerm_role_assignment" "functions_storage" {
  scope                = azurerm_storage_account.functions.id
  role_definition_name = "Storage Blob Data Owner"
  principal_id         = azurerm_user_assigned_identity.functions.principal_id
}

resource "azurerm_role_assignment" "functions_read_alerts" {
  scope                = azurerm_eventhub.alerts.id
  role_definition_name = "Azure Event Hubs Data Receiver"
  principal_id         = azurerm_user_assigned_identity.functions.principal_id
}

resource "azurerm_service_plan" "functions" {
  name                = "asp-iot-poc-fn"
  resource_group_name = azurerm_resource_group.poc.name
  location            = azurerm_resource_group.poc.location
  os_type             = "Linux"
  sku_name            = "FC1"
}

# Code is deployed separately (scripts/deploy-function.sh), like an app pipeline on top of the infra.
resource "azurerm_function_app_flex_consumption" "alerts" {
  name                = var.function_app_name
  resource_group_name = azurerm_resource_group.poc.name
  location            = azurerm_resource_group.poc.location
  service_plan_id     = azurerm_service_plan.functions.id

  runtime_name           = "python"
  runtime_version        = "3.12"
  maximum_instance_count = 40
  instance_memory_in_mb  = 2048

  storage_container_type            = "blobContainer"
  storage_container_endpoint        = "${azurerm_storage_account.functions.primary_blob_endpoint}${azurerm_storage_container.functions_deploy.name}"
  storage_authentication_type       = "UserAssignedIdentity"
  storage_user_assigned_identity_id = azurerm_user_assigned_identity.functions.id

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.functions.id]
  }

  # Identity-based connections: <name>__fullyQualifiedNamespace / __blobServiceUri + managed identity, no keys.
  app_settings = {
    # blobServiceUri rather than accountName: the Event Hubs checkpoint store only accepts a service URI.
    AzureWebJobsStorage__blobServiceUri         = azurerm_storage_account.functions.primary_blob_endpoint
    AzureWebJobsStorage__credential             = "managedidentity"
    AzureWebJobsStorage__clientId               = azurerm_user_assigned_identity.functions.client_id
    EventHubConnection__fullyQualifiedNamespace = "${azurerm_eventhub_namespace.alerts.name}.servicebus.windows.net"
    EventHubConnection__credential              = "managedidentity"
    EventHubConnection__clientId                = azurerm_user_assigned_identity.functions.client_id
    ALERTS_EVENTHUB_NAME                        = azurerm_eventhub.alerts.name
  }

  site_config {
    application_insights_connection_string = azurerm_application_insights.poc.connection_string
  }

  depends_on = [
    azurerm_role_assignment.functions_storage,
    azurerm_role_assignment.functions_read_alerts,
  ]
}

# Provider workaround: on every create/update azurerm injects a key-based AzureWebJobsStorage (with an
# empty key, since shared keys are disabled). It overrides the identity-based settings and the host fails
# to start, so remove it and re-sync triggers (the scale controller only wakes the app for synced triggers).
resource "terraform_data" "functions_fix_storage_setting" {
  triggers_replace = [
    azurerm_function_app_flex_consumption.alerts.id,
    sha1(jsonencode(azurerm_function_app_flex_consumption.alerts.app_settings)),
    azurerm_function_app_flex_consumption.alerts.site_config[0].application_insights_connection_string,
  ]

  provisioner "local-exec" {
    command = <<-EOT
      az functionapp config appsettings delete -g ${azurerm_resource_group.poc.name} -n ${azurerm_function_app_flex_consumption.alerts.name} --setting-names AzureWebJobsStorage -o none
      az rest --method post --url "https://management.azure.com${azurerm_function_app_flex_consumption.alerts.id}/syncfunctiontriggers?api-version=2023-12-01" -o none
    EOT
  }
}
