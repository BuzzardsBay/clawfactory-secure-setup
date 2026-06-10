# ClawFactory — Azure baseline rebake report (clawfactory-win11-baseline-v2)

**Date (UTC):** 2026-06-10
**Bake VM:** cfv-133 — westus2 — public IP `20.230.130.107` (deleted after capture)
**Source image:** `clawfactory-win11-baseline` (managed image, Gen V2) — **KEPT, untouched**
**New image:** `clawfactory-win11-baseline-v2` (managed image, Gen V2, Generalized)
**Purpose:** unblock v1.0.33 validation — the prior baseline's WSL engine was too old to
complete a headless install (see `REPORT_v1.0.32.md`, cfv-132).

## Overall: PASS

The WSL engine is now current (2.7.8.0) and baked into `clawfactory-win11-baseline-v2`.
Sysprep generalized cleanly on the first attempt with no appx remediation. The new image
is captured and ready for v1.0.33 validation — **subject to one downstream prerequisite
(DSv5 vCPU quota) called out below.**

## Results by task

| Task | Result | Notes |
|---|---|---|
| T0 RG cleanup | PASS (no-op) | RG already clean from cfv-132 teardown. Nothing to delete. |
| T1 Provision cfv-133 | PASS | From baseline image, Security `Standard`, non-zonal, subnet `bake-vmSubnet`, `--nsg-rule NONE` + Standard public IP. **Sized `Standard_D2s_v4`, not `D2s_v5`** — see "Deviations". |
| T2 WSL update | PASS | Fallback (a): MSI `wsl.2.7.8.0.x64.msi` via `msiexec /quiet /norestart` under run-command SYSTEM. |
| T3 Sysprep + capture | PASS | Original May pre-sysprep cleanup recipe; sysprep `/generalize /shutdown /oobe /quiet /mode:vm` succeeded first try. No appx remediation needed. |
| T4 Cleanup + report | PASS | cfv-133 + OS disk + NIC + public IP deleted. RG clean (2 images remain). This file. |

## WSL versions — before / after

**Before (baseline `clawfactory-win11-baseline`, on cfv-133, SYSTEM context):**
- `wsl --version` → error: *"Windows Subsystem for Linux must be updated to the latest version to proceed."* (inbox System32 stub only)
- `wsl --status` → *"The Windows Subsystem for Linux is not installed."*
- No `Microsoft.WSL` / WSL MSI product installed; no WSL/Linux appx package present.
- Optional features `Microsoft-Windows-Subsystem-Linux` and `VirtualMachinePlatform` = **Enabled**.

**After (on cfv-133, post-MSI):**
```
WSL version: 2.7.8.0
Kernel version: 6.18.33.1-1
WSLg version: 1.0.73.2
MSRDC version: 1.2.6676
Direct3D version: 1.611.1-81528511
DXCore version: 10.0.26100.1-240331-1435.ge-release
Windows version: 10.0.26100.8246
```
- `wsl --update` → *"The most recent version of Windows Subsystem for Linux is already installed."* (exit 0) — **acceptance test met.**

## Which TASK 2 path was used

**Fallback (a) — MSI install, run-command direct (SYSTEM context).** Per instruction, plain
`wsl --update` under SYSTEM was **not** re-attempted (REPORT_v1.0.32.md already proved it
fails with `The requested operation requires elevation. | The handle is invalid.`).

Exact path:
1. Downloaded `https://github.com/microsoft/WSL/releases/download/2.7.8/wsl.2.7.8.0.x64.msi`
   (258,678,784 bytes) to `C:\Windows\Temp` via `Invoke-WebRequest` (outbound over the VM's
   Standard public IP).
2. `msiexec /i wsl.2.7.8.0.x64.msi /quiet /norestart` → **exit code 0** (no reboot required).
3. Verified: product "Windows Subsystem for Linux 2.7.8.0" registered; `C:\Program Files\WSL\wsl.exe`
   present; `wsl --version` = 2.7.8.0; `wsl --update` reports up to date.

The MSI path works under SYSTEM exactly where `wsl --update` does not, because it installs
the engine machine-wide via Windows Installer rather than routing through the interactive
Store/elevation path that `wsl --update` requires.

## Sysprep remediation performed

**None required.** The original May bake recipe was used verbatim
(`validation-runs/phase1-bake-20260506-144034/pre-sysprep-cleanup.ps1` + `sysprep.ps1`):
remove `C:\Windows\Panther`, disable `wuauserv`, then
`Get-AppxPackage -AllUsers | where NonRemovable=$false | Remove-AppxPackage -AllUsers`.

**Key finding (new vs. the original bake):** the WSL 2.7.8 MSI *does* register a Store-style
appx, `MicrosoftCorporationII.WindowsSubsystemForLinux_2.7.8.0_x64__8wekyb3d8bbwe` — present
both as an installed package **and** a provisioned package. This is exactly the class of
package the task warned could break sysprep. However:
- The pre-sysprep cleanup's `Remove-AppxPackage -AllUsers` removed **both** the installed and
  the provisioned WSL appx (post-cleanup: zero WSL appx, installed or provisioned).
- The **WSL engine survived** as an MSI product in `C:\Program Files\WSL`; `wsl --version`
  still returned 2.7.8.0 after the appx was gone. The engine does not depend on the appx.
- Sysprep `/generalize` then ran with **no WSL appx to conflict on** and completed first try:
  `SYSPRP FCreateTagFile:Successfully created tag file ...\Sysprep_succeeded.tag`,
  `Provisioning packages are removed successfully`, shutdown initiated. VM reached
  `PowerState/stopped`.

So the Task 3 dilemma resolved in the **good** direction: sysprep succeeded **and** the WSL
update is preserved in the image (engine is MSI-backed in Program Files, independent of the
removed appx). No deprovision-vs-fallback-(b) decision was needed.

## Deviations from the prompt (both immaterial to the image)

1. **Bake VM sized `Standard_D2s_v4`, not `Standard_D2s_v5`.** After the Free Trial → PAYG
   upgrade, the `standardDSv5Family` vCPU quota in westus2 is **0** (`az vm create` on D2s_v5
   fails `QuotaExceeded`, Current Limit: 0). `standardDSv4Family` has limit 10. The bake VM's
   size does **not** affect the captured image — a generalized Gen V2 managed image is
   identical regardless of the family it was generalized on, and deploys on D2s_v5 later. The
   v2 image is fully valid for D2s_v5 validation.
2. **TASK 0 was a no-op** — RG was already clean (cfv-132 teardown was complete). No FAIL VMs
   or disks existed to delete.

## ⚠️ Downstream prerequisite for v1.0.33 validation (Prompt 3)

**DSv5 vCPU quota in westus2 is 0.** Prompt 3 provisions a cfv VM on `Standard_D2s_v5` from
this v2 image and will hit the same `QuotaExceeded` wall the bake did. I submitted a
programmatic quota increase (standardDSv5Family → 10) via the Microsoft.Quota API
(request `25b9dadf-49b4-4ec9-85f7-d62487d1f931`); it **Failed** auto-approval (`Request failed.`),
so a manual request is required. Two options for Prompt 3, either is fine:
- **(A)** Request the DSv5 quota increase in the portal (Subscriptions → Usage + quotas →
  `Standard DSv5 Family vCPUs`, westus2, ≥ 2) and run validation on `D2s_v5` as specified, **or**
- **(B)** Run validation on `Standard_D2s_v4` (quota available now, limit 10). The image and
  installer behavior are identical; only the validation-VM family differs from the historical spec.

This quota item does **not** affect this rebake's PASS — the v2 image is captured and correct.

## Exact image reference for Prompt 3

Use this as the validation VM source image:

```
/subscriptions/43010359-5b4c-4d16-af11-10f6544b2978/resourceGroups/clawfactory-validation/providers/Microsoft.Compute/images/clawfactory-win11-baseline-v2
```

- Name: `clawfactory-win11-baseline-v2`
- HyperVGeneration: **V2**
- osState: Generalized
- Location: westus2
- Provision with `--security-type Standard`, **non-zonal** (no `--zone`; `standardDSv5Family`
  carries a Zone restriction in westus2), subnet `bake-vmSubnet`.

## Cleanup

cfv-133 + OS disk (`cfv-133-osdisk`) + NIC + public IP (`cfv-133PublicIP`) deleted. Final RG
state: VMs none, disks none, NICs none, public IPs none. Images: `clawfactory-win11-baseline`
(original, **kept**) and `clawfactory-win11-baseline-v2` (new) — both Gen V2. Storage account
`clawfactoryvalc467` and `bake-vmVNET/bake-vmSubnet` unchanged.

## Verdict

**PASS.** `clawfactory-win11-baseline-v2` carries a current WSL engine (2.7.8.0) and is ready
for v1.0.33 validation. Resolve the DSv5 quota (or run validation on D2s_v4) before Prompt 3.
