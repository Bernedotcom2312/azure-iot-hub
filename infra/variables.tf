variable "location" {
  description = "Azure region for all PoC resources."
  type        = string
  default     = "westeurope"
}

variable "resource_group_name" {
  description = "Resource group holding the PoC (state lives elsewhere, in rg-iot-tfstate)."
  type        = string
  default     = "rg-iot-poc"
}

variable "iothub_name" {
  description = "IoT Hub name, globally unique (it becomes <name>.azure-devices.net)."
  type        = string
  default     = "iothub-poc-121026"
}

variable "iothub_sku" {
  description = "IoT Hub SKU: F1 (free, one per subscription, 1 custom endpoint max, cannot be upgraded) or S1."
  type        = string
  default     = "S1"
}

variable "telemetry_storage_account_name" {
  description = "Storage account for routed telemetry (cold path), globally unique, 3-24 lowercase alphanumerics."
  type        = string
  default     = "stiotpoc121026"
}

variable "eventhub_namespace_name" {
  description = "Event Hubs namespace for the hot path, globally unique."
  type        = string
  default     = "evhns-iot-poc-121026"
}

variable "function_app_name" {
  description = "Hot-path Function App, globally unique (<name>.azurewebsites.net)."
  type        = string
  default     = "func-iot-poc-121026"
}

variable "functions_storage_account_name" {
  description = "Storage account backing the Function App, globally unique, 3-24 lowercase alphanumerics."
  type        = string
  default     = "stiotpocfn121026"
}

variable "dps_name" {
  description = "Device Provisioning Service name, globally unique."
  type        = string
  default     = "provs-iot-poc-121026"
}

variable "alert_email" {
  description = "Optional email notified by Azure Monitor alerts (empty: alerts are only visible in the portal)."
  type        = string
  default     = ""
}
