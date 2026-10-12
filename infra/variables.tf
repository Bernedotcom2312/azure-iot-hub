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
  description = "IoT Hub SKU: F1 (free, one per subscription) or S1."
  type        = string
  default     = "F1"
}
