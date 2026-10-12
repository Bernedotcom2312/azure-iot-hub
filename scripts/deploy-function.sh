#!/usr/bin/env bash
# Deploy the hot-path Function code (functions/) to the Function App created by Terraform.
# Remote build: the platform installs requirements.txt, so nothing is pip-installed locally.
set -euo pipefail

cd "$(dirname "$0")/.."
APP=$(terraform -chdir=infra output -raw function_app_name)
RG=$(terraform -chdir=infra output -raw resource_group_name)

ZIP=$(mktemp -d)/functions.zip
(cd functions && zip -qr "$ZIP" . -x '__pycache__/*' '.venv/*' 'local.settings.json')

az functionapp deployment source config-zip -g "$RG" -n "$APP" --src "$ZIP" --build-remote true -o none
az functionapp function list -g "$RG" -n "$APP" --query "[].name" -o tsv
