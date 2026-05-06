# Phase 1 Bake — STOPPED at Task 1 (preflight)

STORAGE ACCOUNT NAME: NOT CREATED (preflight failed before Task 2)
IMAGE NAME: NOT CREATED (preflight failed before Task 8)

Result: **FAIL — preflight**
Run dir: validation-runs/phase1-bake-20260506T185022Z/
Run start (UTC): 2026-05-06T18:50:22Z
Stopped at (UTC): 2026-05-06T18:5x:xxZ (Task 1)

## Preflight findings

- (a) `az account show` — PASS. Active subscription
  43010359-5b4c-4d16-af11-10f6544b2978, state Enabled.
- (b) `az group show -n clawfactory-validation` — PASS.
  Location westus2, provisioningState Succeeded.
- (c) Creds file `C:\Users\bmcki\.azure-clawfactory-creds` — PASS.
  Both lines present (admin_user len=9, admin_password len=22).
- (d) DSv5 quota — **FAIL**.
  `az vm list-usage --location westus2 -o json` returned `[]`
  (zero entries). Cannot confirm 2 vCPU headroom because no usage
  data is returned.

## Root cause (diagnostic, not a fix)

`az provider show -n Microsoft.Compute --query registrationState -o tsv`
returns `NotRegistered`.

- The Microsoft.Compute resource provider is not registered on
  subscription 43010359-5b4c-4d16-af11-10f6544b2978.
- This causes the vm-usage quota API to return an empty array
  (no SKU family quota visibility) and is a hard prerequisite for
  any `az vm create` / image / managed-disk operation.
- Cross-check: `az vm list-skus -l westus2 --size Standard_D2s_v5
  --resource-type virtualMachines` returns one entry with
  `restrictions = [NotAvailableForSubscription]`. That restriction
  is typically a downstream consequence of the unregistered
  provider, but is not guaranteed to clear automatically — it may
  also reflect a region-capacity or subscription-tier restriction
  that persists even after registration.

## Stopped per spec

Spec HARD RULE: "On any failure: write what failed to log, stop,
do not attempt fixes." Provider registration would be a fix.
Tasks 2–9 not attempted. No Azure resources created in this run.

## What unblocks Task 1

Out-of-band (operator action), not by this run:

1. Register the provider:
   `az provider register --namespace Microsoft.Compute`
   then poll `az provider show -n Microsoft.Compute
   --query registrationState -o tsv` until it returns `Registered`
   (typically <2 min).
2. Re-run `az vm list-skus -l westus2 --size Standard_D2s_v5
   --resource-type virtualMachines` and confirm `restrictions` is
   `[]`. If it still shows `NotAvailableForSubscription`, the
   restriction is region/tier — pick another westus2 SKU
   (e.g. Standard_D2s_v3) or another region (e.g. eastus2,
   centralus) and update the spec accordingly.
3. Re-run `az vm list-usage --location westus2` and confirm at
   least 2 vCPU headroom on the chosen SKU family.

## Files

- log.md           (this file)
- host-driver.log  (full stdout/stderr of preflight calls)
- quota.json       (= `[]`)
- run-start.epoch
