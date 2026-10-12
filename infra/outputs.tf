output "resource_group_name" {
  value = azurerm_resource_group.poc.name
}

output "iothub_name" {
  value = azurerm_iothub.hub.name
}

output "iothub_hostname" {
  value = azurerm_iothub.hub.hostname
}

output "telemetry_storage_account_name" {
  value = azurerm_storage_account.telemetry.name
}

output "telemetry_container_name" {
  value = azurerm_storage_container.telemetry.name
}

output "function_app_name" {
  value = azurerm_function_app_flex_consumption.alerts.name
}

output "log_analytics_workspace_id" {
  description = "Workspace (customer) id, used by `az monitor log-analytics query -w`."
  value       = azurerm_log_analytics_workspace.poc.workspace_id
}

output "dps_name" {
  value = azurerm_iothub_dps.poc.name
}

output "dps_id_scope" {
  description = "Not a secret: identifies the DPS instance to devices (they connect to global.azure-devices-provisioning.net)."
  value       = azurerm_iothub_dps.poc.id_scope
}
