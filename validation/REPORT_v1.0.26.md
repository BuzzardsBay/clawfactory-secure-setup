# ClawFactory v1.0.26 — Azure Validation Report

Date:     2026-05-17
VM:       cfv-126 (Standard_D2s_v5, westus2)
Commit:   aa1f932 (compiled from); validation per spec at session start
Size:     340529081 bytes (diff vs v1.0.25: +239 bytes, matches the /PROVIDER shim)
SHA256:   6586C8510B868EBADF3DC50679D0EDB211E5C06A0230267B44E76B255566D69F

## Install

Mode:             Silent headless (`/SILENT /SUPPRESSMSGBOXES /NORESTART /LOG=C:\ProgramData\ClawFactory\install.log /PROVIDER=claude`)
Exit code:        not observed — `az vm run-command invoke` response window closed before installer exited, and installer never reached completion (see Root Cause)
Provider picked:  **claude — confirmed** in install.log line 1: `==== ClawFactory Secure Setup - starting (provider=claude) ====` and line 2: `Selected provider: Anthropic Claude.`
ERRORs in log:    none labelled ERROR
WARNs in log:
  - L3: `Virtualization may be disabled in BIOS. WSL2 may fail to start.` (this is a preflight noise warning — Standard_D2s_v5 does support nested virt, but the heuristic mis-fires)
  - L12: `Step-ConfigureWslConfig hit an error and is continuing: "Windows Subsystem for Linux must be updated to the latest version. You can update by running 'wsl.exe --update'."` (the baseline image's bundled WSL kernel is older than the WSL feature engine expects)
Gateway 120s poll window observed: **no — installer never reached Step 8 (gateway).**

## Smoke Test

**Not run.** Blocked by install failure (Steps 4–10 never executed).

## 5-Minute Idle Test

**Not run.** Blocked by install failure (gateway never started).

## chatCompletions Endpoint

**Not run.** Blocked by install failure (gateway never started, openclaw.json doesn't exist).

## Overall

**FAIL — v1.0.26 install does not complete headlessly. Blocking issue identified; fix required before next cycle.**

The `/PROVIDER=claude` shim itself works correctly — install log proves the silent override took effect. The failure is a **separate, pre-existing reboot-resume flow that is incompatible with `az vm run-command invoke`'s execution model.**

## Root Cause

Sequence of events on cfv-126:

1. `13:17:00` — Installer starts under SYSTEM context via run-command. `provider=claude` resolved correctly from the v1.0.26 shim.
2. `13:17:00` — Step 1 (preflight) passes.
3. `13:17:04` — Step 2 runs `wsl --install --no-distribution`. **Returns exit code 1** ("elevation required or reboot pending"). setup.ps1 treats this as the "needs reboot to resume" path.
4. `13:17:04` — setup.ps1 registers an HKLM RunOnce key:
   ```
   HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce\ClawFactoryResume =
     "C:\Windows\Temp\ClawFactory-Secure-Setup.exe" /SILENT /SUPPRESSMSGBOXES /NORESTART /resume
   ```
5. `13:17:05` — Silent-mode branch: skip the user-facing "restart required" dialog and reboot the box immediately.
6. `13:17:47` — VM finishes reboot. Post-boot uptime confirmed 4 minutes when diagnosed.
7. **The RunOnce key never fires** because `RunOnce` (both HKLM `\RunOnce` and `\Run`) executes during the **interactive Winlogon session for the first user that logs in**. Under `az vm run-command invoke`, scripts execute as `NT AUTHORITY\SYSTEM` without any user logon — diagnosis confirmed `cfvadmin hive not loaded (no interactive login since boot)`.
8. Net result: WSL is not installed (`wsl --status` reports "The Windows Subsystem for Linux is not installed"), no OpenClaw, no gateway, install stuck mid-Step-3 forever.

### Why the v1.0.25 cycle "passed" in session 3
The v1.0.25 cycle ran via RDP — the test operator (me, in error) was logged in interactively as cfvadmin, so the post-reboot RunOnce **did** fire. That cycle's PASS was an artifact of the validation mechanism, not a property of the installer. The headless requirement exposes a real install-flow bug that's been latent since reboot-resume was added.

### Secondary issue — WSL needs update
The baseline image's `wsl.exe` reports it needs `wsl.exe --update` to proceed. This caused the `Step-ConfigureWslConfig` warning at 13:17:05. It is **not** the root cause of the failure — even if WSL were current, the reboot-resume gap would still block headless install. But it is an additional warning that should be addressed (probably with `wsl --update` in the baseline image, or a setup.ps1 pre-step that runs `wsl --update` headlessly before `wsl --install`).

## Recommended fix (v1.0.27)

Replace the `RunOnce`-based resume with a **Scheduled Task** that runs at system startup as `NT AUTHORITY\SYSTEM` and self-deletes after one successful run:

```powershell
# In setup.ps1, replace the RunOnce registration with:
$action = New-ScheduledTaskAction `
    -Execute "C:\Windows\Temp\ClawFactory-Secure-Setup.exe" `
    -Argument "/SILENT /SUPPRESSMSGBOXES /NORESTART /resume"
$trigger = New-ScheduledTaskTrigger -AtStartup
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -Priority 5
Register-ScheduledTask -TaskName "ClawFactoryResume" `
    -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force

# At top of setup.ps1's /resume branch, immediately unregister itself:
Unregister-ScheduledTask -TaskName "ClawFactoryResume" -Confirm:$false -ErrorAction SilentlyContinue
```

This makes the resume path independent of any user logon — fires on the next boot regardless of who (or whether anyone) logs in. Compatible with both the interactive install path (user is logged in already, task fires before they see anything) and headless (`az vm run-command invoke`) validation.

Suggested companion changes:
1. Add `wsl --update` step (idempotent, runs early in Step 2) so the WSL-feature engine is current before `wsl --install` runs.
2. Optionally retry `wsl --install --no-distribution` once before falling into reboot-resume — Windows 11 builds where Hyper-V/VirtualMachinePlatform are already enabled often complete WSL install without needing a reboot at all, which would skip the whole reboot-resume hazard for that subset.

## Notes

- **The v1.0.26 `/PROVIDER` shim is verified working.** The fix shipped in aa1f932 is correct; the validation failure here is downstream and unrelated.
- This is the first cycle run fully via `az vm run-command invoke` per the new "no local desktop" rule. The new validation mechanism uncovered the latent reboot-resume hole that interactive RDP cycles masked.
- Per spec block ("If any run-command step fails to complete headlessly, STOP and report the blocking issue — do not fall back to RDP"), the cycle stops here. Did NOT fall back to RDP.
- VM disposition: deallocated, OS disk preserved for diagnosis. Disk name: `cfv-126_disk1_b6efa2650f514089b3d6ed7c43ccd1f2`. Add to next session Task 0 cleanup before provisioning cfv-127.
