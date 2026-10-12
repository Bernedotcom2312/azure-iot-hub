# Step 8 - Security hardening: X.509 device auth and Entra ID (RBAC) for service-side access.

# --- X.509 CA: devices whose certificate chains to this CA can authenticate, no per-device secret in the hub ---

# PoC shortcut: the CA private key lives in the Terraform state (Entra-only, versioned backend).
# In production the CA sits in an offline/HSM-backed PKI and device keys are generated in a secure element.
resource "tls_private_key" "device_ca" {
  algorithm   = "ECDSA"
  ecdsa_curve = "P256"
}

resource "tls_self_signed_cert" "device_ca" {
  private_key_pem       = tls_private_key.device_ca.private_key_pem
  is_ca_certificate     = true
  validity_period_hours = 24 * 365
  allowed_uses          = ["cert_signing", "crl_signing"]

  subject {
    common_name  = "iot-poc-device-ca"
    organization = "IoT PoC"
  }
}

# is_verified skips the proof-of-possession step, acceptable because Terraform itself holds the CA key.
resource "azurerm_iothub_certificate" "device_ca" {
  name                = "iot-poc-device-ca"
  resource_group_name = azurerm_resource_group.poc.name
  iothub_name         = azurerm_iothub.hub.name
  is_verified         = true
  certificate_content = base64encode(tls_self_signed_cert.device_ca.cert_pem)
}

# --- Service-side access through Entra ID instead of shared access policies (`az ... --auth-type login`) ---

resource "azurerm_role_assignment" "operator_iothub_data" {
  scope                = azurerm_iothub.hub.id
  role_definition_name = "IoT Hub Data Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "azurerm_role_assignment" "operator_dps_data" {
  scope                = azurerm_iothub_dps.poc.id
  role_definition_name = "Device Provisioning Service Data Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
}
