# Shared observability backend: Function logs (Step 5) and hub diagnostics (Step 9).

resource "azurerm_log_analytics_workspace" "poc" {
  name                = "log-iot-poc"
  resource_group_name = azurerm_resource_group.poc.name
  location            = azurerm_resource_group.poc.location
  sku                 = "PerGB2018"
  retention_in_days   = 30
  daily_quota_gb      = 1 # cost guardrail for the PoC
}

# Workspace-based Application Insights: Function traces land in the AppTraces table.
resource "azurerm_application_insights" "poc" {
  name                = "appi-iot-poc"
  resource_group_name = azurerm_resource_group.poc.name
  location            = azurerm_resource_group.poc.location
  workspace_id        = azurerm_log_analytics_workspace.poc.id
  application_type    = "other"
}
