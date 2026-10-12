# Step 9 - Observability: hub resource logs + metrics in Log Analytics, alerts on the usual IoT failure modes.

locals {
  # Daily message quota per unit (4 KB messages); used to alert before the hub starts rejecting messages.
  iothub_daily_quota = {
    F1 = 8000
    S1 = 400000
    S2 = 6000000
    S3 = 300000000
  }[var.iothub_sku] * azurerm_iothub.hub.sku[0].capacity
}

# IoT Hub resource logs only support the AzureDiagnostics table (no resource-specific tables).
resource "azurerm_monitor_diagnostic_setting" "iothub" {
  name                       = "iothub-to-log-analytics"
  target_resource_id         = azurerm_iothub.hub.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.poc.id

  # Connections logs every connect/disconnect; the other categories mostly log failures.
  dynamic "enabled_log" {
    for_each = ["Connections", "DeviceTelemetry", "Routes", "C2DCommands", "DirectMethods", "C2DTwinOperations", "D2CTwinOperations"]
    content {
      category = enabled_log.value
    }
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

resource "azurerm_monitor_action_group" "ops" {
  name                = "ag-iot-poc-ops"
  resource_group_name = azurerm_resource_group.poc.name
  short_name          = "iotpocops"

  # No receiver by default: alerts are still visible in Azure Monitor. Set alert_email to get notified.
  dynamic "email_receiver" {
    for_each = var.alert_email == "" ? [] : [var.alert_email]
    content {
      name          = "operator"
      email_address = email_receiver.value
    }
  }
}

resource "azurerm_monitor_metric_alert" "throttling" {
  name                = "iothub-d2c-throttling"
  resource_group_name = azurerm_resource_group.poc.name
  scopes              = [azurerm_iothub.hub.id]
  description         = "Devices are being throttled (per-unit send rate exceeded): messages are delayed or rejected."
  severity            = 2
  frequency           = "PT5M"
  window_size         = "PT5M"

  criteria {
    metric_namespace = "Microsoft.Devices/IotHubs"
    metric_name      = "d2c.telemetry.ingress.sendThrottle"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = 0
  }

  action {
    action_group_id = azurerm_monitor_action_group.ops.id
  }
}

resource "azurerm_monitor_metric_alert" "daily_quota" {
  name                = "iothub-daily-quota-80pct"
  resource_group_name = azurerm_resource_group.poc.name
  scopes              = [azurerm_iothub.hub.id]
  description         = "Over 80% of the daily message quota used; at 100% the hub rejects telemetry until midnight UTC."
  severity            = 2
  frequency           = "PT15M"
  window_size         = "PT1H"

  criteria {
    metric_namespace = "Microsoft.Devices/IotHubs"
    metric_name      = "dailyMessageQuotaUsed"
    aggregation      = "Maximum"
    operator         = "GreaterThan"
    threshold        = local.iothub_daily_quota * 0.8
  }

  action {
    action_group_id = azurerm_monitor_action_group.ops.id
  }
}

# No metric exists for failed connections: query the Connections logs instead.
resource "azurerm_monitor_scheduled_query_rules_alert_v2" "connection_errors" {
  name                 = "iothub-connection-errors"
  resource_group_name  = azurerm_resource_group.poc.name
  location             = azurerm_resource_group.poc.location
  scopes               = [azurerm_log_analytics_workspace.poc.id]
  description          = "Devices failing to connect (bad credentials, expired certificates, disabled devices...)."
  severity             = 2
  evaluation_frequency = "PT15M"
  window_duration      = "PT15M"

  criteria {
    query                   = <<-KQL
      AzureDiagnostics
      | where ResourceProvider == "MICROSOFT.DEVICES" and Category == "Connections" and Level == "Error"
    KQL
    time_aggregation_method = "Count"
    operator                = "GreaterThan"
    threshold               = 0
  }

  action {
    action_groups = [azurerm_monitor_action_group.ops.id]
  }
}

# --- Saved KQL queries (Log Analytics > Logs > Queries > "IoT PoC") ---

resource "azurerm_log_analytics_saved_search" "connection_errors_by_device" {
  name                       = "connection-errors-by-device"
  log_analytics_workspace_id = azurerm_log_analytics_workspace.poc.id
  category                   = "IoT PoC"
  display_name               = "Devices with connection errors"
  query                      = <<-KQL
    AzureDiagnostics
    | where ResourceProvider == "MICROSOFT.DEVICES" and Category == "Connections" and Level == "Error"
    | extend props = parse_json(properties_s)
    | summarize errors = count(), lastError = max(TimeGenerated), reasons = make_set(ResultDescription, 5)
        by deviceId = tostring(props.deviceId)
    | order by errors desc
  KQL
}

resource "azurerm_log_analytics_saved_search" "connection_events_by_device" {
  name                       = "connection-events-by-device"
  log_analytics_workspace_id = azurerm_log_analytics_workspace.poc.id
  category                   = "IoT PoC"
  display_name               = "Connects / disconnects per device"
  query                      = <<-KQL
    AzureDiagnostics
    | where ResourceProvider == "MICROSOFT.DEVICES" and Category == "Connections"
    | extend props = parse_json(properties_s)
    | summarize count() by deviceId = tostring(props.deviceId), OperationName, bin(TimeGenerated, 1h)
    | order by TimeGenerated desc
  KQL
}

# Hub logs don't record successful sends per device, so the rate comes from hub-wide metrics.
resource "azurerm_log_analytics_saved_search" "message_rate" {
  name                       = "message-rate"
  log_analytics_workspace_id = azurerm_log_analytics_workspace.poc.id
  category                   = "IoT PoC"
  display_name               = "D2C message rate (hub-wide, per 5 min)"
  query                      = <<-KQL
    AzureMetrics
    | where ResourceProvider == "MICROSOFT.DEVICES" and MetricName in ("d2c.telemetry.ingress.success", "d2c.telemetry.ingress.sendThrottle")
    | summarize messages = sum(Total) by MetricName, bin(TimeGenerated, 5m)
    | render timechart
  KQL
}
