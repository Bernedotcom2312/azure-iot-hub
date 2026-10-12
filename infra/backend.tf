terraform {
  backend "azurerm" {
    resource_group_name  = "rg-iot-tfstate"
    storage_account_name = "stiotpoctf5cd634"
    container_name       = "tfstate"
    key                  = "iot-poc.tfstate"
    use_azuread_auth     = true
  }
}
