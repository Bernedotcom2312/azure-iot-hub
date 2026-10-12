# Step 4 - Message routing, cold path: telemetry tagged level='storage' is persisted to Blob Storage.

data "azurerm_client_config" "current" {}

resource "azurerm_storage_account" "telemetry" {
  name                            = var.telemetry_storage_account_name
  resource_group_name             = azurerm_resource_group.poc.name
  location                        = azurerm_resource_group.poc.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
  # Entra ID only: the hub writes with its managed identity, humans read with RBAC.
  shared_access_key_enabled = false
}

resource "azurerm_storage_container" "telemetry" {
  name                  = "telemetry"
  storage_account_id    = azurerm_storage_account.telemetry.id
  container_access_type = "private"
}

# The hub's system-assigned identity (see main.tf) writes blobs.
resource "azurerm_role_assignment" "hub_to_telemetry" {
  scope                = azurerm_storage_account.telemetry.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_iothub.hub.identity[0].principal_id
}

# Lets the operator running Terraform list/download blobs with `--auth-mode login`.
resource "azurerm_role_assignment" "operator_reads_telemetry" {
  scope                = azurerm_storage_account.telemetry.id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "azurerm_iothub_endpoint_storage_container" "telemetry" {
  name                = "telemetry-storage"
  resource_group_name = azurerm_resource_group.poc.name
  iothub_id           = azurerm_iothub.hub.id

  authentication_type = "identityBased"
  endpoint_uri        = azurerm_storage_account.telemetry.primary_blob_endpoint
  container_name      = azurerm_storage_container.telemetry.name

  # JSON instead of the default Avro, so blobs are human-readable. Immutable after creation.
  encoding                   = "JSON"
  batch_frequency_in_seconds = 60 # minimum; one blob per partition per window
  max_chunk_size_in_bytes    = 10485760
  file_name_format           = "{iothub}/{partition}/{YYYY}/{MM}/{DD}/{HH}/{mm}"

  # The hub checks write access when the endpoint is created.
  depends_on = [azurerm_role_assignment.hub_to_telemetry]
}

resource "azurerm_iothub_route" "telemetry_to_storage" {
  name                = "telemetry-to-storage"
  resource_group_name = azurerm_resource_group.poc.name
  iothub_name         = azurerm_iothub.hub.name
  source              = "DeviceMessages"
  condition           = "level = 'storage'"
  endpoint_names      = [azurerm_iothub_endpoint_storage_container.telemetry.name]
  enabled             = true
}

# A message that matches any route skips the fallback, so without this route
# `az iot hub monitor-events` would stop seeing level='storage' messages.
resource "azurerm_iothub_route" "telemetry_to_builtin" {
  name                = "telemetry-to-builtin"
  resource_group_name = azurerm_resource_group.poc.name
  iothub_name         = azurerm_iothub.hub.name
  source              = "DeviceMessages"
  condition           = "true"
  endpoint_names      = ["events"]
  enabled             = true
}
