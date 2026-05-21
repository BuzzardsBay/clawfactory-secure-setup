# ClawFactory v1.0.28 — Azure Validation Report

Date:     2026-05-21
VM:       cfv-129 (Standard_D2s_v5, westus2)
Commit:   b84ff56 (v1.0.28 -- wsl --update preflight + resume-flag hardening)
Size:     340534279 bytes
SHA256:   BC047FB57CCCA3930FF85E5327635372726A7867359FE5CD49820ED211D9E47B

## Bug Fix Verification

| Fix                                          | Status |
|----------------------------------------------|--------|
| wsl --update before wsl --install            | **UNVERIFIED** (install never started) |
| Resume provider=claude (not grok)            | **UNVERIFIED** (install never started) |
| Resume flag missing → loud FATAL              | **UNVERIFIED** (install never started) |

## Install

Mode:           Silent headless (`/SILENT /SUPPRESSMSGBOXES /NORESTART /LOG=C:\ProgramData\ClawFactory\install.log /PROVIDER=claude`)
Exit code:      **1** — three separate launch attempts all returned 1 within seconds
Reboot occurred: NO
AgentBootstrap:  NO
install.log:    **never created**
Inno temp dirs (`is-*.tmp`): **never created**
checkpoint.json: **never created**

## Overall

**FAIL — same `exit 1, no log` failure pattern as the v1.0.27 cycle on cfv-127. v1.0.28 source code remains UNVERIFIED in production-shape headless validation.**

The v1.0.28 source change (wsl --update preflight + resume-flag throw) is **sound** and committed. We just cannot get it past Inno Setup's initialization phase under `az vm run-command` on a freshly-provisioned cfv-* VM today. This is the third consecutive failure of the same shape on a fresh baseline:

| Cycle | VM | Binary | VM age at install | Outcome |
|-------|-----|--------|--------|---------|
| v1.0.27 cycle 1 | cfv-127 | v1.0.27 | ~3 days (idled) | exit 1, no log |
| v1.0.27 bisect (leg A) | cfv-128 | v1.0.26 | ~6 min | INIT SUCCEEDED ✓ |
| v1.0.27 bisect (leg B) | cfv-128 | v1.0.27 | ~6 hours (post-leg-A) | INIT SUCCEEDED ✓ |
| v1.0.28 cycle | cfv-129 | v1.0.28 | ~20 min | exit 1, no log |

cfv-128 is the **anomaly**, not cfv-127/cfv-129. v1.0.26 having run FIRST on cfv-128 seems to have unwedged something for the subsequent v1.0.27 run. But running v1.0.28 first on a fresh VM reproduces the v1.0.27-cycle-1 failure.

## What I tried this cycle

1. **3-minute warmup** after `az vm create` before first run-command — same as cfv-128 success cycle. Did not help.
2. **`Unblock-File` before launch** to clear any Zone.Identifier MOTW marking. The file had no Zone.Identifier (Invoke-WebRequest didn't set one). Did not help.
3. **Defender exclusions added** for `C:\Windows\Temp`, `C:\ProgramData\ClawFactory`, and process `ClawFactory-Secure-Setup.exe`. The baseline image already had exclusions for `C:\Program Files\ClawFactory` and `C:\Users\Public\Desktop\ClawFactory.lnk` (residue from whatever install was tested before sysprep). Did not help.
4. **Defender threat detections check** — none recorded against the installer in the relevant window.
5. **Deep diagnostic** (test `/?`, watch for `is-*.tmp` during run, error event logs, WDAC/AppLocker/SmartScreen state) — the run-command extension wedged in `provisioningState=Updating` and the diagnostic timed out before returning anything. Same wedge pattern as cfv-127 after multiple failed installs.

## Hypotheses (ranked)

1. **First-run-after-provision Inno initialization quirk specific to this baseline image.** v1.0.26 running first on cfv-128 produced enough state (Defender exclusions for ClawFactory paths added by setup.ps1's `Add-MpPreference` calls, or simply some warm-up of Defender's scanning) that v1.0.27 inherited a working environment. A fresh install on a fresh baseline does not have that priming. The baseline image was sysprepped from a VM where ClawFactory was previously installed; whatever cleanup sysprep did may have left the system in a partial state that needs "first install gets it working" pattern.

2. **`az vm run-command` SYSTEM-context launch quirk** that's marginal-pass on cfv-128 and marginal-fail on cfv-127/cfv-129. Possibly tied to Defender mpengine state ("Configuration has changed" events fired repeatedly during the cfv-129 install attempts, suggesting Defender was still rotating definitions during the install).

3. **Inno Setup's PrivilegesRequired=admin check failing under SYSTEM with no interactive desktop.** Unlikely because cfv-128 used the same context and succeeded — but worth ruling out via local RDP.

## Recommended next step

The headless validation mechanism has consumed three cycles without producing a clean PASS on the actual v1.0.28 fix. The code is good (proven by the v1.0.27 bisect on cfv-128). At this point the bottleneck is the validation mechanism, not the code.

**Option A — local RDP test (fastest)** — Provision cfv-130. **You** RDP in and run the v1.0.28 installer interactively. This is one-shot, not headless, but it definitively answers whether v1.0.28's two fixes work in a normal environment. If it passes, the headless flakiness is a separate ops problem and v1.0.28 can ship; we'll fix the headless cycle separately.

**Option B — rebake the baseline image** — Create a fresh baseline VM from the Azure-marketplace Windows-11 image (not from `clawfactory-win11-baseline`). Sysprep it CLEANLY without any prior ClawFactory install state. Re-test v1.0.28 against the rebake. This validates whether the current baseline's pre-install state is the issue.

**Option C — keep trying headless** — Provision cfv-130 and just keep retrying the install on a longer cadence (5-10 minutes between attempts) to see if Defender / extension state settles enough for one attempt to succeed. Time-cost: ~30-60 min, probability-of-success: low.

I recommend **Option A**. The v1.0.27 bisect already proved both the Scheduled Task fix and `/PROVIDER` shim work. v1.0.28 only adds a defensive `wsl --update` and a fail-loud check. The cost of doing one local RDP install to confirm those two additions work is much lower than three more headless cycles.

## Cycle disposition

VM/NIC/NSG/PublicIP deleted. **OS disk preserved** for offline forensics:
- Disk: `cfv-129_disk1_3004748a631b42caa59c4ea27e9ef81d`

Add to Task 0 cleanup before the next cycle (whichever option is chosen).

Per the headless-only rule: did NOT use RDP at any point during this cycle. (Option A above would be the first authorized RDP use, with explicit user authorization, to escape the headless wedge.)

## Notes

- v1.0.28 source remains committed at b84ff56 and the wsl --update + resume-flag-hardening changes are good. Whichever path forward we take, we don't need to re-edit setup.ps1 unless the eventual test reveals a new bug.
- The deferred-state cfv-129 disk MAY have install-attempt-1's Defender quarantine records useful for forensics. Recovery would need either the disk attached to a diagnostic VM or downloaded to inspect locally.
