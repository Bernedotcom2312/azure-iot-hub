# Azure IoT Hub PoC

Goal: learn Azure IoT Hub end to end, coming from a cloud architecture background, using **simulated devices** (no hardware needed).

**Ground rule:** every Azure resource is created with **Terraform** (`infra/`), and its state lives in a **versioned Azure Blob Storage** backend. `az` is used only for read/exploration commands and for data-plane objects Terraform cannot manage (see Step 2).

## Target architecture

```
Simulated device (Python) --MQTT/TLS--> IoT Hub --routing--> Storage (cold path)
        ^                                   |  \-> Event Hub / Function (hot path, alerts)
        |-- direct methods / twin / C2D <---|
                                            \-> Azure Monitor (metrics + logs)

Terraform (local CLI) --state--> Blob Storage (versioning + soft delete + lease locking)
```

## IoT mental model (read first)

| Concept | What it is | Cloud analogy |
|---|---|---|
| **IoT Hub** | Managed, bi-directional messaging gateway for devices + device registry | API Gateway + Event Hub + identity store |
| **Device identity** | Per-device entry in the hub registry with its own credentials (symmetric key or X.509) | Service principal per device |
| **D2C telemetry** | Device-to-cloud messages (MQTT/AMQP/HTTPS) | Event ingestion |
| **C2D messages** | Cloud-to-device queue per device (fire and forget) | Per-device queue |
| **Direct methods** | Synchronous RPC to a device (needs it online) | Request/response call |
| **Device twin** | JSON doc: `desired` (cloud -> device) and `reported` (device -> cloud) properties + tags | Desired state / config management |
| **Message routing** | Rules sending telemetry to endpoints (Storage, Event Hub, Service Bus) | Event routing / EventGrid-like |
| **DPS** | Device Provisioning Service: zero-touch enrollment of devices into a hub | Just-in-time provisioning |

Built-in endpoint is Event Hub compatible: anything that reads Event Hubs can read telemetry.

## Plan

Each step: **What** we do, **Why** it matters. Check the box when done.

### Step 0 - Prerequisites
- [x] Azure subscription, `az` CLI (`az login`), `az extension add --name azure-iot`
- [x] [`uv`](https://docs.astral.sh/uv/) installed (`brew install uv`); then `uv init --bare && uv add azure-iot-device` (uv manages Python, venv and `pyproject.toml`/`uv.lock`)
- [x] Define variables: `RG=rg-iot-poc`, `LOC=westeurope`, `HUB=iothub-poc-<unique>`
- [x] Terraform installed (`brew install terraform`, >= 1.6)

*Why:* the `azure-iot` extension adds `az iot` commands to inspect the hub, send test messages and monitor events. Terraform provisions everything else.

### Step 1 - Terraform state backend (versioned Blob Storage)
- [x] Create a **separate** resource group `rg-iot-tfstate` (so destroying the PoC never deletes its own state) with a Storage account + private container `tfstate`. This is the only bootstrap done outside the main config, with `az` (chicken-and-egg: the backend must exist before Terraform can use it), kept in `scripts/bootstrap-tfstate.sh`
- [x] Enable on the account: **blob versioning**, blob + container **soft delete**, TLS 1.2 min, no public blob access, `--allow-shared-key-access false` (use Entra ID auth, `use_azuread_auth = true`)
- [x] Grant yourself `Storage Blob Data Contributor` on the account
- [x] Configure `infra/backend.tf` (`backend "azurerm"`: resource group, storage account, container, key `iot-poc.tfstate`); `terraform init`

*Why:* Terraform state is the source of truth and can contain secrets (keys, connection strings). Blob storage gives remote state with native lease-based locking; versioning + soft delete let you roll back a corrupted or deleted state file (like S3 versioning for a state bucket).

### Step 2 - Resource group + IoT Hub (Terraform)
- [x] Hub already created with `az` (RG `rg-iot-poc`, SKU F1, 2 partitions) and device `sim-device-01` registered. These were created manually, before the IaC rule
- [x] Write `infra/` (`providers.tf`, `main.tf`, `variables.tf`, `outputs.tf`): `azurerm_resource_group`, `azurerm_iothub` (F1, or S1 if F1 is taken)
- [x] **Adopt the existing resources** with `terraform import` (or `import {}` blocks), then check `terraform plan` shows no diff. Alternative: delete the RG and let Terraform recreate it (asks for confirmation first)
- [x] Always run `terraform plan` and review it before `terraform apply`

*Why:* the hub is the central control + data plane. The SKU sets daily message quota and features (Basic lacks twins/methods/C2D; Standard has them all).

**Exception, data-plane objects:** device identities, twins and DPS enrollments are not ARM resources, so the `azurerm` provider cannot manage them. They are created through `az iot ...` (scripts in `scripts/`) and documented here; everything at ARM level stays in Terraform.

### Step 3 - Register a device identity and send telemetry (D2C)
- [x] `az iot hub device-identity create -n $HUB -d sim-device-01`
- [x] `az iot hub device-identity connection-string show -n $HUB -d sim-device-01`
- [x] Write `device/simulator.py` (run with `uv run device/simulator.py`): connect with the device connection string, send JSON `{temperature, humidity}` every 5 s
- [x] Watch it live: `az iot hub monitor-events -n $HUB -d sim-device-01`

*Why:* each device authenticates individually (SAS key), so revoking one never impacts the others. This is the core IoT flow - device -> hub over MQTT/TLS (port 8883). Note the system properties and custom message properties (used later for routing).

### Step 4 - Message routing (cold path, Terraform)
- [ ] `azurerm_storage_account` + `azurerm_storage_container` for telemetry
- [ ] `azurerm_iothub_endpoint_storage_container`, `azurerm_iothub_route` filtering on a message property (e.g. `level = 'storage'`), `azurerm_iothub_fallback_route` as needed
- [ ] Update the simulator to set the `level` property; verify blobs (Avro/JSON) land in the container

*Why:* the built-in endpoint retains data only 1-7 days. Routing is how you persist and fan out data without writing code.

### Step 5 - Hot path (alerting, Terraform)
- [ ] `azurerm_eventhub_namespace` + `azurerm_eventhub`, `azurerm_iothub_endpoint_eventhub`, and a second route (`temperature > 30`)
- [ ] Consume with an Azure Function (`azurerm_linux_function_app`, code in `functions/`) or Stream Analytics that logs/alerts

*Why:* shows the classic Lambda split: cold path (storage/analytics) vs hot path (near real-time reaction).

### Step 6 - Cloud-to-device control
- [ ] Device handles a **direct method** `reboot`/`setInterval`; invoke with `az iot hub invoke-device-method`
- [ ] Use the **device twin**: set `desired.sendInterval`, device applies it and writes `reported.sendInterval`; check with `az iot hub device-twin show`
- [ ] Send a **C2D message** (`az iot device c2d-message send`)

*Why:* the twin is the recommended way to manage config at scale; methods are for immediate commands; C2D for notifications. No new Azure resource here: this is all data-plane and device code.

### Step 7 - Scale onboarding with DPS (Terraform)
- [ ] `azurerm_iothub_dps` + `azurerm_iothub_dps_shared_access_policy`, linked to the hub
- [ ] Create an individual enrollment, then a group enrollment (X.509 or symmetric-key group) via `az iot dps enrollment create` / `enrollment-group create` (data-plane, scripted)
- [ ] Modify the simulator to provision itself via DPS instead of a hard-coded connection string

*Why:* in production you never pre-register thousands of devices manually; DPS assigns them to a hub on first boot (and can load-balance across hubs).

### Step 8 - Security hardening (Terraform)
- [ ] Move from SAS keys to **X.509** certificates for the device (self-signed CA for the PoC)
- [ ] Use **Entra ID + RBAC** (`azurerm_role_assignment`, `IoT Hub Data Contributor`) for service-side access instead of shared access policies
- [ ] Review and set in Terraform: disable local auth where possible, TLS 1.2 min, private endpoint, Defender for IoT

*Why:* device identity and the service-side access path are the two main attack surfaces.

### Step 9 - Observability (Terraform)
- [ ] `azurerm_log_analytics_workspace` + `azurerm_monitor_diagnostic_setting` on the hub (Connections, DeviceTelemetry, Routes categories)
- [ ] `azurerm_monitor_metric_alert` / `azurerm_monitor_scheduled_query_rules_alert_v2`: throttling, failed connections, quota usage
- [ ] KQL: devices with connection errors, message rate per device

*Why:* most IoT incidents are connectivity/quota issues, visible only through hub metrics and logs.

### Step 10 - Cleanup
- [ ] `terraform destroy` (review the plan first); this removes `rg-iot-poc` and everything in it
- [ ] Optionally delete the state RG afterwards: `az group delete -n rg-iot-tfstate --yes --no-wait` (state versions are lost with it)

## Proposed layout

```
.
├── README.md
├── CLAUDE.md
├── pyproject.toml # uv project (+ uv.lock)
├── device/        # simulator + provisioning client
├── functions/     # hot-path consumer
├── infra/         # Terraform (backend.tf, providers.tf, main.tf, ...)
└── scripts/       # bootstrap-tfstate.sh + az helpers for data-plane objects
```

## Learning notes
Add findings, gotchas and cost observations here as the PoC progresses.
