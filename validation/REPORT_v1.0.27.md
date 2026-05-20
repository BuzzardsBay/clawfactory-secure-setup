# ClawFactory v1.0.27 — Azure Validation Report

Date:     2026-05-20
VM:       cfv-127 (Standard_D2s_v5, westus2)
Commit:   19b02d4 (v1.0.27 -- replace RunOnce with Scheduled Task)
Size:     340538741 bytes (+9660 vs v1.0.26 — matches scope of helper rewrite)
SHA256:   8AC95AD9A6B4CCD6858974F91558ABB84472E80D2486939F038BFC77F01F0A84

## Reboot-Resume Fix Verification

Scheduled Task registered:    **NOT REACHED** — installer never started
Task self-unregistered:       n/a
Resume completed headlessly:  n/a

## Install

Mode:           Silent headless (`/SILENT /SUPPRESSMSGBOXES /NORESTART /LOG=C:\ProgramData\ClawFactory\install.log /PROVIDER=claude`)
Exit code:      **1** (returned within seconds of `Start-Process -Wait`)
Reboot required: n/a — installer exited before reaching Step 2
ERRORs in log:  **no log was ever written**

## Smoke Test

**Not run.** Blocked by installer initialization failure.

## 5-Minute Idle Test

**Not run.** Gateway never started.

## chatCompletions Endpoint

**Not run.** Gateway never started.

## Overall

**FAIL — installer exits 1 immediately under `az vm run-command` on cfv-127, before any Inno Setup initialization output is produced. The v1.0.27 scheduled-task fix could not be verified because the install never reached the WSL2 step.**

## Root Cause — Open Question

The Inno Setup .exe returns exit code 1 ("Setup failed to initialize") within seconds of being launched via `Start-Process -Wait -PassThru` from a run-command SYSTEM-context PowerShell session. **Crucially, this is the same launch mechanism that produced the v1.0.26 cycle's partial install** (setup.ps1 ran to Step 3 before reboot). The .iss [Code] section between v1.0.26 and v1.0.27 differs only in the version-define string, so the Inno init logic is byte-equivalent.

Diagnostic data confirms nothing happened post-launch:
| Check                             | cfv-127 state |
|-----------------------------------|---------------|
| `C:\Windows\Temp\…Secure-Setup.exe` | exists, size 340538741 (correct) |
| `C:\Windows\Temp\is-*.tmp`         | **none** (Inno never created its work dir) |
| `C:\Windows\Temp\Setup Log*.txt`   | **none** |
| `C:\ProgramData\ClawFactory\`      | **does not exist** |
| `C:\Program Files\ClawFactory\`    | not installed |
| `ClawFactory-Resume` scheduled task | never registered |
| `HKLM:…\RunOnce`                  | empty (no fallback path either) |
| `wsl.exe --status`                | "not installed" (Step 2 never ran) |
| VM uptime                         | 4h+ continuous, no reboot |

Inno Setup exit 1 = "Setup failed to initialize" — failure happens *before* the wizard or log is opened. The most likely candidates:

1. **Windows Defender heuristic drift on the baseline image.** Between when cfv-126 successfully ran v1.0.26 (2026-05-17 13:17) and when cfv-127 attempted v1.0.27 (2026-05-20), Defender on the baseline-derived VM had ~3 days to receive updated signatures. An unsigned freshly-built installer with a new SHA-256 may trip a heuristic that v1.0.26 didn't — Defender silently blocks process creation and the launch returns 1.

2. **Stale environment on cfv-127 specifically.** cfv-127 was provisioned 2026-05-17 evening and sat idle for ~3 days before the install attempt. Auto-applied Windows Updates, Defender platform/engine updates, or attack-surface-reduction policy changes during that window could have changed the binary-execution gate. A freshly-provisioned cfv-128 may behave differently.

3. **Run-command extension drift.** During this session, the `RunCommandWindows` extension on cfv-127 entered a degraded state — multiple invocations timed out with `VMExtensionProvisioningTimeout`, and the VM briefly showed `provisioningState=Updating`. This is an Azure platform-level issue, not a binary issue, but it consumed enough investigation time that further on-VM diagnosis became impractical.

I could not get clean signal from either Defender event-log queries or `Get-AuthenticodeSignature` because every diagnostic run-command attempt either timed out or got swallowed by the same extension-provisioning queue.

## Cycle did NOT exercise the v1.0.27 fix

The whole point of v1.0.27 was the RunOnce → Scheduled Task swap. That code path is reached only if setup.ps1 runs (Inno [Run] step), and setup.ps1 never ran. **So v1.0.27's headless-resume fix remains unvalidated.** It may be correct — there's no evidence either way.

## Recommended next step

Provision **cfv-128 fresh from `clawfactory-win11-baseline`** and run BOTH:

1. The v1.0.26 installer (known to have worked previously) — regression test. If this also fails to initialize on a fresh VM, the baseline image has drifted and needs rebake.
2. The v1.0.27 installer — actual validation.

This bisects (binary problem) vs (environment problem) cleanly:

| v1.0.26 on cfv-128 | v1.0.27 on cfv-128 | Conclusion |
|--------------------|--------------------|------------|
| PASS | PASS | cfv-127 had stale state; v1.0.27 is good |
| PASS | FAIL | v1.0.27 binary itself has a problem (likely tripping a Defender heuristic the v1.0.26 binary doesn't) |
| FAIL | FAIL | Baseline image has drifted (Defender def updates) — needs rebake before any further cycles |
| FAIL | PASS | Vanishingly unlikely — would warrant manual inspection |

A useful side investigation while on the fresh VM: capture
`Get-WinEvent -LogName 'Microsoft-Windows-Windows Defender/Operational' -MaxEvents 50`
*immediately after* the install attempt, before any other run-command call clouds the picture. That should surface any AV block events.

## Cycle disposition

VM/NIC/NSG/PublicIP deleted. **OS disk preserved** for offline forensics:
- Disk name: `cfv-127_disk1_1619077f265548aba2a4eb06babcb297`
- Contains: the v1.0.27 installer .exe (verified hash), no install log (so nothing useful on the disk itself — but the disk is preserved in case Defender quarantine artifacts can be recovered from it)

Add to next session's Task 0 cleanup before provisioning cfv-128.

## Notes

- Per the headless-only rule, **did NOT fall back to RDP** at any point. Cycle stopped at the binary-initialization failure rather than RDP-debugging.
- This is the second cycle (after v1.0.26) where the headless mechanism uncovered an issue, but the issue this time may be the headless mechanism itself (Defender + run-command interaction), not the installer code.
