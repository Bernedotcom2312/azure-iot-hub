# CLAUDE.md

## Project
Azure IoT Hub learning PoC with simulated devices. The step-by-step plan lives in `README.md`; follow it in order and tick the checkboxes as steps complete.

## User context
The user is an experienced cloud architect with no IoT background. For each step, briefly explain what is being built and why (IoT concepts mapped to cloud analogies), keep it concise.

## Conventions
- Write everything in English (docs, code, comments, commits).
- Prefer `az` CLI for exploration and Terraform (`azurerm` provider, `infra/`) for IaC; device code in Python (`device/`) using `azure-iot-device`.
- Python tooling is `uv` only (`uv add`, `uv run`, `uv sync`); never use `pip` or manual venvs.
- Never commit secrets (connection strings, keys, certs). Use env vars or a git-ignored `.env`.
- Resource names: `rg-iot-poc`, region `westeurope`, hub name must be globally unique.
- Use the cheapest SKU (F1 or S1) and remind the user to delete the resource group when done.
- Ask before creating or deleting Azure resources.
- Commit messages follow Conventional Commits (`feat:`, `fix:`, `docs:`, `chore:`, `refactor:`, `ci:`, with an optional scope, e.g. `feat(device): add twin handler`).