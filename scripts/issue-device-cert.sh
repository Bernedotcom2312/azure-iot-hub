#!/usr/bin/env bash
# Step 8 - Issue an X.509 certificate for a device and register it with CA-based authentication.
# Mimics a factory flow: the device generates its key + CSR (CN = device id), the CA signs it.
# Output: certs/<device-id>.key and certs/<device-id>.pem (git-ignored).
# Usage: scripts/issue-device-cert.sh [device-id]
set -euo pipefail

cd "$(dirname "$0")/.."
DEVICE=${1:-sim-device-x509}
HUB=$(terraform -chdir=infra output -raw iothub_name)
mkdir -p certs && chmod 700 certs

# The CA key only touches disk in a private temp dir, removed on exit.
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
terraform -chdir=infra output -raw device_ca_cert_pem > "$WORK/ca.pem"
terraform -chdir=infra output -raw device_ca_private_key_pem > "$WORK/ca.key"

# "Device side": private key never leaves the device, only the CSR does.
openssl ecparam -name prime256v1 -genkey -noout -out "certs/$DEVICE.key"
chmod 600 "certs/$DEVICE.key"
openssl req -new -key "certs/$DEVICE.key" -subj "/CN=$DEVICE" -out "$WORK/device.csr"

# "CA side": the hub matches the certificate CN with the device id.
cat > "$WORK/ext.cnf" <<EOF
basicConstraints = CA:FALSE
keyUsage = critical, digitalSignature
extendedKeyUsage = clientAuth
EOF
openssl x509 -req -in "$WORK/device.csr" -CA "$WORK/ca.pem" -CAkey "$WORK/ca.key" -CAcreateserial \
  -days 90 -sha256 -extfile "$WORK/ext.cnf" -out "certs/$DEVICE.pem" 2>/dev/null

# Service side, through Entra ID (IoT Hub Data Contributor) instead of a shared access policy.
if ! az iot hub device-identity show -n "$HUB" -d "$DEVICE" --auth-type login -o none 2>/dev/null; then
  az iot hub device-identity create -n "$HUB" -d "$DEVICE" --am x509_ca --auth-type login -o none
fi

openssl x509 -in "certs/$DEVICE.pem" -noout -subject -issuer -enddate
echo "Run it with: AUTH_MODE=x509 X509_DEVICE_ID=$DEVICE uv run device/simulator.py"
