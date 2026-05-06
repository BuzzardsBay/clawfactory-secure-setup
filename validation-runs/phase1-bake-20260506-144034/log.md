STORAGE ACCOUNT NAME: clawfactoryvalc467
IMAGE NAME: clawfactory-win11-baseline

# Phase 1 Bake Log — 2026-05-06T14:55:19Z

## Preflight (Task 1)
PASS: Subscription 43010359-5b4c-4d16-af11-10f6544b2978 Enabled
PASS: RG clawfactory-validation in westus2
PASS: Creds present (admin_user=clawadmin)
PASS: Standard_D2s_v5 available in westus2 (non-zonal; zone restrictions acceptable)
PASS: UseStandardSecurityType Registered

## Task 2 — SKIPPED (storage account clawfactoryvalc467 exists)

## Task 3 — Provision bake-vm
PASS: powerState=VM running | IP=20.230.163.211 | Size=Standard_D2s_v5
Image: MicrosoftWindowsDesktop:Windows-11:win11-24h2-pro:latest | SecurityType=Standard

## Task 4 — Configure VM
PASS: WSL=Enabled VMP=Enabled
Note: winget not available in RunCommand context (non-fatal; WSL/VMP are the gate)

## Task 5 — Reboot
PASS: VM running confirmed within 15s of restart

## Task 6 — Sysprep (file-based, /mode:vm)
Step A PASS: PRE_SYSPREP_CLEANUP_DONE (Panther cleaned, wuauserv disabled, AppX removed)
Step B/C: stdout empty — VM shut down before echo ran (expected with -Wait + /shutdown)
Step D PASS: powerState=VM stopped at 14:51:55 (confirms sysprep completed)

## Task 7 — Deallocate and Generalize
PASS: VM deallocated at first poll (+15s) | generalized OK

## Task 8 — Capture Image
PASS: clawfactory-win11-baseline created | provisioningState=Succeeded
ID: /subscriptions/43010359-5b4c-4d16-af11-10f6544b2978/resourceGroups/clawfactory-validation/providers/Microsoft.Compute/images/clawfactory-win11-baseline

## Task 9 — Cleanup
Sub-agent A: bake-vm deleted (ResourceNotFound on verify = confirmed gone)
Sub-agent B: 2 OS disks deleted (bake-vm_OsDisk_1_365a... + bake-vm_OsDisk_1_8ba6...; second disk was residue from prior failed run)

## Summary
Total elapsed: ~375 minutes
Storage account: clawfactoryvalc467 (unchanged)
Managed image: clawfactory-win11-baseline (Succeeded)
bake-vm: deleted
OS disks: deleted (2 total)

## VERDICT: PASS
