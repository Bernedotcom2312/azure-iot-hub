resource "azurerm_resource_group" "poc" {
  name     = var.resource_group_name
  location = var.location
}

resource "azurerm_iothub" "hub" {
  name                = var.iothub_name
  resource_group_name = azurerm_resource_group.poc.name
  location            = azurerm_resource_group.poc.location
  min_tls_version     = "1.2"

  # Used to authenticate to custom routing endpoints (no keys in endpoint config).
  identity {
    type = "SystemAssigned"
  }

  sku {
    name     = var.iothub_sku
    capacity = 1
  }

  # Built-in Event Hub-compatible endpoint ("events"). Partition count is fixed at creation.
  event_hub_partition_count   = 2
  event_hub_retention_in_days = 1

  # Messages that match no route go to the built-in endpoint.
  # Custom endpoints and routes are declared as separate azurerm_iothub_* resources (routing.tf).
  fallback_route {
    source         = "DeviceMessages"
    condition      = "true"
    endpoint_names = ["events"]
    enabled        = true
  }

  cloud_to_device {
    max_delivery_count = 10
    default_ttl        = "PT1H"

    feedback {
      time_to_live       = "PT1H"
      max_delivery_count = 10
      lock_duration      = "PT5S"
    }
  }
}
