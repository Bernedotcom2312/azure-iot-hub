#!/usr/bin/env bash
# Step 10 - Tear down the PoC. Shows the destroy plan and asks before deleting anything.
# Usage: scripts/cleanup.sh [--with-state]   (--with-state also deletes rg-iot-tfstate: state history is lost)
set -euo pipefail

cd "$(dirname "$0")/.."

# Device identities, twins and DPS enrollments are data-plane objects: they disappear with the hub/DPS.
terraform -chdir=infra plan -destroy -out=destroy.tfplan
read -r -p "Destroy everything above (rg-iot-poc)? Type 'yes': " answer
[[ "$answer" == "yes" ]] || { echo "Aborted."; exit 1; }
terraform -chdir=infra apply destroy.tfplan
rm -f infra/destroy.tfplan

# Local secrets that no longer point to anything.
rm -rf certs
echo "Remove DEVICE_CONNECTION_STRING and DPS_* from .env if you keep the file."

if [[ "${1:-}" == "--with-state" ]]; then
  read -r -p "Also delete rg-iot-tfstate (Terraform state and its versions)? Type 'yes': " answer
  [[ "$answer" == "yes" ]] && az group delete -n rg-iot-tfstate --yes --no-wait
fi
