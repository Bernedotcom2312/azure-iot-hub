#!/usr/bin/env bash
# Step 6 - Exercise the three cloud-to-device channels against a running simulator.
# Usage: scripts/control-demo.sh [device-id]   (HUB is read from the environment or .env)
# Auth: Entra ID (--auth-type login, IoT Hub Data Contributor), no shared access policy key.
set -euo pipefail

[[ -f .env ]] && source .env
DEVICE=${1:-sim-device-01}
: "${HUB:?set HUB (IoT Hub name)}"

echo "== Direct method setInterval(10): synchronous, fails if the device is offline"
az iot hub invoke-device-method -n "$HUB" -d "$DEVICE" --method-name setInterval --method-payload 10 --auth-type login

echo "== Twin desired.sendInterval=7: device applies it and acknowledges in reported"
az iot hub device-twin update -n "$HUB" -d "$DEVICE" --desired '{"sendInterval": 7}' --auth-type login -o none
sleep 3
az iot hub device-twin show -n "$HUB" -d "$DEVICE" --auth-type login \
  --query "{desired: properties.desired.sendInterval, reported: properties.reported.sendInterval}"

echo "== C2D message: queued by the hub, delivered when the device is connected"
az iot device c2d-message send -n "$HUB" -d "$DEVICE" --data "firmware update available" --props "kind=notice" --auth-type login

echo "== Direct method reboot"
az iot hub invoke-device-method -n "$HUB" -d "$DEVICE" --method-name reboot --auth-type login
