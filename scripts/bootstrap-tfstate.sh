#!/usr/bin/env bash
# Bootstrap the Terraform remote state backend (versioned Blob Storage).
# Idempotent: safe to re-run. Run after `az login`.
set -euo pipefail

LOC=westeurope
RG=rg-iot-tfstate
CONTAINER=tfstate

SUB_ID=$(az account show --query id -o tsv)
USER_ID=$(az ad signed-in-user show --query id -o tsv)
# Storage account names are globally unique: derive a stable suffix from the subscription id.
SUFFIX=$(printf '%s' "$SUB_ID" | md5 | cut -c1-6)
SA="stiotpoctf${SUFFIX}"

# New subscriptions may not have the Storage provider registered
# (az then fails with a misleading "SubscriptionNotFound").
az provider register -n Microsoft.Storage --wait

az group create -n "$RG" -l "$LOC" -o none

az storage account create -n "$SA" -g "$RG" -l "$LOC" \
  --sku Standard_LRS --kind StorageV2 \
  --min-tls-version TLS1_2 \
  --allow-blob-public-access false \
  --allow-shared-key-access false \
  -o none

# Versioning + soft delete (blobs and containers) so a corrupted/deleted state can be rolled back.
az storage account blob-service-properties update --account-name "$SA" -g "$RG" \
  --enable-versioning true \
  --enable-delete-retention true --delete-retention-days 30 \
  --enable-container-delete-retention true --container-delete-retention-days 30 \
  -o none

# Data-plane access through Entra ID (shared keys are disabled).
SA_ID=$(az storage account show -n "$SA" -g "$RG" --query id -o tsv)
az role assignment create --assignee-object-id "$USER_ID" --assignee-principal-type User \
  --role "Storage Blob Data Contributor" --scope "$SA_ID" -o none || true

echo "Waiting for RBAC propagation..."
sleep 30
az storage container create -n "$CONTAINER" --account-name "$SA" --auth-mode login -o none

echo "Backend ready: resource_group=$RG storage_account=$SA container=$CONTAINER"
