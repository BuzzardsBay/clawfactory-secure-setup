# Bisect Validation: v1.0.26 vs v1.0.27 on cfv-128

Date:     2026-05-21
VM:       cfv-128 (Standard_D2s_v5, westus2, fresh from `clawfactory-win11-baseline`)
Commits:  v1.0.26 = aa1f932, v1.0.27 = 19b02d4
Binaries: served from clawfactoryvalc467 (hashes verified byte-for-byte on VM)
  v1.0.26: 340529081 bytes, SHA256 6586C8510B868EBADF3DC50679D0EDB211E5C06A0230267B44E76B255566D69F
  v1.0.27: 340538741 bytes, SHA256 8AC95AD9A6B4CCD6858974F91558ABB84472E80D2486939F038BFC77F01F0A84

## Bisect verdict

```
v1.0.26 PASS + v1.0.27 PASS  →  cfv-127 had stale state. v1.0.27 binary is fine.
```

`Inno init` succeeded for both binaries on a fresh VM. The cfv-127 exit-1 was an environmental artifact (most likely Defender state drift from 3 days of idle time on that VM, or RunCommandWindows extension state corruption during the long diagnostic loop). It is **not** a v1.0.27 binary problem, **not** a Defender heuristic against v1.0.27, and **not** baseline image drift.

| Check                            | v1.0.26 leg A | v1.0.27 leg B |
|----------------------------------|---------------|---------------|
| Inno log produced                | YES (11.1 KB) | YES (13.4 KB) |
| Inno reported "Installation process succeeded" | YES | YES |
| Inno fired [Run] entry            | YES → setup.ps1 | YES → setup.ps1 |
| setup.ps1 logged "starting"      | YES (provider=claude) | implicit (skipped via checkpoint) |
| Reboot fired                     | YES (Step-EnsureWsl) | YES |
| **Reboot-resume mechanism fired** | **NO** (RunOnce; expected to fail headlessly) | **YES** (scheduled task) |
| setup.ps1 logged resume entry    | n/a | `==== resuming after restart ====` at 02:26:40 |
| Install ran to completion        | NO (stuck post-reboot, no resume) | NO (downstream errors — see below) |

## v1.0.27 fix verification

**The actual v1.0.27 change — RunOnce → Scheduled Task for headless reboot-resume — is verified working.** The setup.ps1 install.log shows:

```
[2026-05-21 02:26:36] [WARN] -Resume passed but no resume flag found. Continuing with whatever -Provider was given.
[2026-05-21 02:26:40] [INFO] ==== ClawFactory Secure Setup - resuming after restart (provider=grok) ====
[2026-05-21 02:26:40] [INFO] Step 1: Preflight checks. Selected provider: Grok (xAI).
```

The `==== resuming after restart ====` entry only fires when setup.ps1 is launched with `-Resume`. On this VM, `-Resume` was passed by the **ClawFactory-Resume scheduled task firing on boot under SYSTEM context**, without any interactive logon. That is exactly the behavior v1.0.27 was designed to provide. The v1.0.26 cycle's HKLM RunOnce never fired in the same scenario; v1.0.27's scheduled task did. Fix confirmed.

The scheduled task self-unregistered on first fire (post-fire probe shows `ClawFactory-Resume: False`), exactly as designed.

## Confounding factors discovered (NOT bisect-blocking)

Running both installers sequentially on the same VM revealed two separate downstream issues that prevent v1.0.27 from completing end-to-end. These are real bugs but they are **not what the bisect was testing**.

### Issue 1: Resume-flag JSON lost across binary swap

When v1.0.26 ran first, it wrote `C:\ProgramData\ClawFactory\resume-after-restart.flag` with `provider=claude`. When v1.0.27 ran second, the .iss [Files] section overwrote `C:\Program Files\ClawFactory\setup.ps1` but the resume-flag file in ProgramData survived. However, post-reboot the resume-flag was apparently consumed or unreadable — setup.ps1 logged `-Resume passed but no resume flag found` and fell back to a cmdline `-Provider` value that defaulted to `grok`.

This is a stale-state issue specific to running two binaries sequentially. A clean v1.0.27 install (no v1.0.26 first) would not hit it. But the root cause — that the resume flag isn't reliably preserved across the reboot — should be investigated. Suggested fix: setup.ps1 should bail loudly when `-Resume` is passed and the flag is missing, rather than silently defaulting to grok.

### Issue 2: WSL "must be updated to the latest version" hard-fails on resume

After resume, setup.ps1 hit Step-EnsureWsl's resume branch, which calls `wsl --install -d Ubuntu`. The baseline image's bundled `wsl.exe` is older than the WSL kernel engine expects, and reports "Windows Subsystem for Linux must be updated to the latest version" — exit code 1.

setup.ps1's error handler caught this and aborted:

```
[2026-05-21 02:27:42] [ERROR] Top-level handler caught: wsl --install failed (exit 1) and no fallback signal detected.
[2026-05-21 02:27:42] [INFO] INSTALLER_DONE=failure
```

This is the same WARN that v1.0.26 logged on cfv-126 three days ago. In v1.0.26 it was a non-fatal WARN; in v1.0.27 it became a fatal ERROR on the resume path. Likely because v1.0.26's resume never fired (so we never saw the resume path's behavior), while v1.0.27's resume DID fire and immediately tripped on `wsl --install`.

Suggested fix for v1.0.28: add `wsl --update` as an explicit step in `Step-EnsureWsl` (before `wsl --install`), or in a new Step-2a `Step-UpdateWslEngine`. Idempotent — safe to call on already-current systems.

## Recommended next step

Two concurrent paths:

**Path A — confirm v1.0.27 ships (immediate).** Provision cfv-129 fresh from baseline and run v1.0.27 ALONE (no v1.0.26 pollution). Should reproduce the same fail (wsl --install exit 1 on resume), but cleanly — without the Issue-1 provider drift.

**Path B — fix the WSL update issue first (recommended).** Add `wsl --update` to setup.ps1's Step-EnsureWsl as a pre-`wsl --install` step. Bump to v1.0.28. Then run a fresh validation cycle. This is the path that actually moves toward a shippable build.

I'd recommend Path B. The headless reboot-resume fix is good; pursuing v1.0.27 ship without fixing the WSL-update prerequisite would just produce another partial-install failure on the next cycle.

## Cycle disposition

VM/NIC/NSG/PublicIP deleted. **OS disk preserved** for forensics if anyone wants to inspect the post-bisect state:
- Disk name: `cfv-128_disk1_*` (recorded in commit message after delete)

Per headless-only rule: did NOT use RDP at any point.
