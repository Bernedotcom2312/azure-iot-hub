# Step 7 - Device Provisioning Service: devices get their hub assignment and identity on first boot.

# DPS creates device identities in the hub, so it needs a hub-level policy with registry write access.
resource "azurerm_iothub_shared_access_policy" "dps" {
  name                = "dps-link"
  resource_group_name = azurerm_resource_group.poc.name
  iothub_name         = azurerm_iothub.hub.name
  registry_read       = true
  registry_write      = true
  service_connect     = true
  device_connect      = true
}

resource "azurerm_iothub_dps" "poc" {
  name                = var.dps_name
  resource_group_name = azurerm_resource_group.poc.name
  location            = azurerm_resource_group.poc.location
  # With several linked hubs, Hashed spreads devices evenly (alternatives: GeoLatency, Static).
  allocation_policy = "Hashed"

  sku {
    name     = "S1"
    capacity = 1
  }

  linked_hub {
    connection_string = azurerm_iothub_shared_access_policy.dps.primary_connection_string
    location          = azurerm_iothub.hub.location
  }
}

# Service-side policy for managing enrollments (scripts/dps-enroll.sh); devices never get it.
resource "azurerm_iothub_dps_shared_access_policy" "enrollment_admin" {
  name                = "enrollment-admin"
  resource_group_name = azurerm_resource_group.poc.name
  iothub_dps_name     = azurerm_iothub_dps.poc.name
  enrollment_read     = true
  enrollment_write    = true
  registration_read   = true
  registration_write  = true
}
