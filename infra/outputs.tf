output "resource_group_name" {
  value = azurerm_resource_group.poc.name
}

output "iothub_name" {
  value = azurerm_iothub.hub.name
}

output "iothub_hostname" {
  value = azurerm_iothub.hub.hostname
}
