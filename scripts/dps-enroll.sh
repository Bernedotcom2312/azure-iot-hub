#!/usr/bin/env bash
# Step 7 - Create DPS enrollments (data-plane objects, not manageable by azurerm). Idempotent.
# - individual enrollment `sim-device-02`: one device, its own symmetric key
# - enrollment group `sim-fleet`: any registration id whose key is derived from the group key
# Writes the ID scope and keys to the git-ignored .env (never printed).
set -euo pipefail

cd "$(dirname "$0")/.."
RG=$(terraform -chdir=infra output -raw resource_group_name)
DPS=$(terraform -chdir=infra output -raw dps_name)
HUB_HOST=$(terraform -chdir=infra output -raw iothub_hostname)
ID_SCOPE=$(terraform -chdir=infra output -raw dps_id_scope)
INDIVIDUAL_ID=sim-device-02
GROUP_ID=sim-fleet

# Upsert KEY=VALUE in .env.
set_env() {
  touch .env
  grep -v "^$1=" .env > .env.tmp || true
  echo "$1=\"$2\"" >> .env.tmp
  mv .env.tmp .env
}

if ! az iot dps enrollment show --dps-name "$DPS" -g "$RG" --enrollment-id "$INDIVIDUAL_ID" -o none 2>/dev/null; then
  az iot dps enrollment create --dps-name "$DPS" -g "$RG" --enrollment-id "$INDIVIDUAL_ID" \
    --attestation-type symmetrickey --iot-hubs "$HUB_HOST" --allocation-policy hashed -o none
fi
INDIVIDUAL_KEY=$(az iot dps enrollment show --dps-name "$DPS" -g "$RG" --enrollment-id "$INDIVIDUAL_ID" \
  --show-keys --query attestation.symmetricKey.primaryKey -o tsv)

# The initial twin is applied to every device provisioned through the group: config from day one.
if ! az iot dps enrollment-group show --dps-name "$DPS" -g "$RG" --enrollment-id "$GROUP_ID" -o none 2>/dev/null; then
  # No certificate given: the group uses symmetric-key attestation.
  az iot dps enrollment-group create --dps-name "$DPS" -g "$RG" --enrollment-id "$GROUP_ID" \
    --iot-hubs "$HUB_HOST" --allocation-policy hashed \
    --initial-twin-tags '{"fleet": "sim-fleet"}' \
    --initial-twin-properties '{"sendInterval": 10}' -o none
fi
GROUP_KEY=$(az iot dps enrollment-group show --dps-name "$DPS" -g "$RG" --enrollment-id "$GROUP_ID" \
  --show-keys --query attestation.symmetricKey.primaryKey -o tsv)

set_env DPS_ID_SCOPE "$ID_SCOPE"
set_env DPS_INDIVIDUAL_ID "$INDIVIDUAL_ID"
set_env DPS_INDIVIDUAL_KEY "$INDIVIDUAL_KEY"
set_env DPS_GROUP_KEY "$GROUP_KEY"

echo "Enrollments ready in $DPS (ID scope $ID_SCOPE). Run a device through DPS with:"
echo "  AUTH_MODE=dps DPS_REGISTRATION_ID=$INDIVIDUAL_ID uv run device/simulator.py"
echo "  AUTH_MODE=dps DPS_REGISTRATION_ID=$GROUP_ID-001 uv run device/simulator.py   # any id: group enrollment"
