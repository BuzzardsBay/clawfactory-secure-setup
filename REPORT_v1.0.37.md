# ClawFactory v1.0.37 — Azure validation report (final-gate in-WSL poll conversion)

**Headline:** **PASS — first-ever full single-run cycle.** The install reached `INSTALLER_DONE=success`,
the final gateway health gate passed, and the suite ran end-to-end: install → smoke → 5-min idle →
chatCompletions → uninstall, all in one run. The v1.0.37 fix (poll the final gate in-WSL like gate #1)
resolved the gate #2 keepalive defect that blocked v1.0.36.

**Date (UTC):** 2026-06-30
**VM:** cfv-137 — Standard_D2s_v4 — westus2 — public IP `20.230.232.205`
**Image:** `clawfactory-win11-baseline-v2` (Gen V2, Generalized; WSL engine self-updated to 2.7.10 during install)
**Installer:** `ClawFactory-Secure-Setup.exe` v1.0.37, source commit `890940a`
  - size `340,544,239` bytes
  - sha256 `7CABCDF4DA2DAE07562D8F5F0554F89FB51461A23A4632D0FE38090A8196F173`
  - on-VM SHA-256 after download: **exact match** (`HASH_MATCH=TRUE`, no transit corruption)
**License key:** `CF-TEST-TEST-TEST-TEST` (test license; **no real API key wired** — see caveats)
**Install flags:** `/SILENT /SUPPRESSMSGBOXES /NORESTART /LOG /PROVIDER=claude /LICENSE=CF-TEST-TEST-TEST-TEST`

## The fix and why it worked

v1.0.36 proved gate #2's failure was **not timing**: the Windows-side `Invoke-WebRequest` poll held no WSL
session, so after bootstrap's last WSL session exited, the distro shut down (last-session-exit teardown,
v1.0.2 lineage) and the gateway was SIGTERM'd mid-gate. v1.0.37 converts the final gate to poll **in-WSL via
`Invoke-WslBash` `curl /status` as clawuser**, mirroring gate #1 — each poll opens a `user@1000` session that
holds the distro (and the gateway's user service) alive for the gate window.

**Journal proof (final-gate window):**
```
13:11:05  Stopping OpenClaw Gateway        <- EnableChatCompletions restart (expected, pre-gate)
13:11:15  Started OpenClaw Gateway
   --- final gate begins polling in-WSL at 13:11:24 ---
13:11:49  [gateway] http server listening (...; 6.3s)   <- bound :8787, stayed up
13:11:51  [gateway] ready
13:11:56  [INFO] Final health gate: gateway responsive on attempt 4   <- PASS
13:12:09  INSTALLER_DONE=success
```
No `Stopping`/SIGTERM occurs during the gate window — the exact teardown v1.0.36 showed is gone. The 5-minute
idle test later (HTTP 200 at both ends, 5 min apart) independently confirms the gateway now persists.

## Suite results

| Stage | Result | Evidence |
|---|---|---|
| 0 Teardown-first + RG audit | PASS | RG already clean (no cfv VMs); held only storage + VNet + 2 images. Nothing billing. |
| 1 Comprehension gate | PASS | Confirmed old gate (Invoke-WebRequest 60×2s) vs gate #1 (Invoke-WslBash curl, 13×10s); conversion mirrors gate #1; no reorder; rationale stated. |
| 2 Fix (in-WSL poll) | PASS | Final gate → `Invoke-WslBash 'curl -fsS --max-time 5 http://127.0.0.1:8787/status' -User 'clawuser'`, 13×10s; message updated. Only change besides version. |
| 3 Compile | PASS | ISCC exit 0 (46.9 s); exe ProductVersion **1.0.37**; size/sha256 above. |
| 4 Git | PASS | Staged only `setup.ps1` + `.iss`; commit `890940a`, pushed. No scratch in repo. |
| 5 Pre-simulation | PASS | Traced: in-WSL poll holds session → no teardown; ~67s cold start clears 120s; message matches; no reorder. |
| 6 Provision cfv-137 | PASS | D2s_v4, baseline-v2, Security Standard, non-zonal, `bake-vmSubnet`, `--nsg-rule NONE` + Standard PIP. `az vm create` via PowerShell (no path mangling); harness via `@file`. Auto-logon + `CFV-Install-Wrapper`. On-VM hash exact. |
| 7 **Install** | **PASS (first-ever success)** | `INSTALLER_DONE=success`; checkpoint shows all **21** steps incl. `RegisterWslHostTask` + `PostInstallSmokeTask`. **Final gate passed in-WSL on attempt 4 (~32 s).** |
| 7 Smoke (11 checks) | **10 PASS / 1 FAIL / 0 SKIP** | Only FAIL = `auth-profiles.json present for all 5 agents` — expected: no real API key in this test install (install log: "No API key … skipping fan-out"). **nft check #9 PASSED natively** (`Egress firewall clawfactory chain present`). |
| 7 Idle (5-min) | **PASS** | `PROBE1=200` (13:15:49) → `PROBE2=200` (13:20:49). Gateway survived the idle window — first time this stage was reachable. |
| 7 chatCompletions | Route reachable (no ACK — no key) | HTTP **401 Unauthorized** from the upstream auth — proves the route is registered and the gateway is alive (vs v1.0.36's 404/refused on a dead gateway). A true ACK needs a real Anthropic key, intentionally absent here. |
| 7 **Uninstall (9-step)** | **PASS** | Clean reversal; this run actually **Unregistered** `ClawFactory WSL Host` + `ClawFactory-PostInstall-Smoke` (first exercise of the task-removal path). License deactivation HTTP 200. Post-state: InstallDir / ProgramData / FW rule / HKLM key **all absent**. |
| 8 Report + teardown | PASS (this file) | cfv-137 VM+NIC+PIP+disk+NSG deleted; RG holds only storage + VNet + 2 images; nothing billing. |

State files: `wslconfig-state.txt=created`, `wsl-state.txt=false` — as specified.

## Two caveats, both API-key-dependent (NOT code defects, NOT fixed here per one-iteration rule)

The single smoke FAIL and the chatCompletions non-ACK have the **same root cause**: this validation install
uses a test license with **no real Anthropic API key** in Credential Manager, so:
- `auth-profiles.json` is never written/fanned-out (smoke check fails),
- the chatCompletions upstream call returns 401 (route works; auth doesn't).

A real user who enters their API key in the wizard gets both. Neither is a regression or a gate/keepalive
issue — the install machinery, gateway persistence, smoke, idle, and uninstall are all proven.

## Release status

**v1.0.37 is NOT tagged or NOT released in this prompt (by instruction).** This is the milestone build:
the first to pass install-through-uninstall in a single run, which is what unblocks the release decision.
**Recommended next step: the release/tag decision** (separate prompt). Code signing — Sectigo OV (~$200/yr) —
remains deferred until first revenue (resolves the SmartScreen "Windows protected your PC" warning).

## Recommendation for the next session (no fix required to ship the gate work)

Not a defect fix — a **validation-coverage** item to reach a clean 11/11 smoke + a real chatCompletions ACK:
- Wire a real (or scoped/throwaway) Anthropic API key into Credential Manager
  (`ClawFactory/AnthropicApiKey`) **before** install on the next cfv VM, so `auth-profiles.json` is created
  (smoke 11/11) and `POST /v1/chat/completions` returns HTTP 200 with an ACK.
- **Pre-sim note:** with a valid key, expect Step-WireProviderKey to write `auth-profiles.json`, the bootstrap
  fan-out to succeed (no "skipping fan-out" warning), smoke check "auth-profiles.json present for all 5 agents"
  to pass, and the chatCompletions probe to return `ACK`. Everything else is already green on cfv-137.

## Cleanup

cfv-137 VM + NIC + PIP + OS disk (`cfv-137_disk1_88edfc3d6e4f4b02bb21c7c31469e1f2`) + NSG (`cfv-137NSG`)
deleted (disk deletion verified 404). RG `clawfactory-validation`: `clawfactoryvalc467` (storage),
`bake-vmVNET/bake-vmSubnet`, `clawfactory-win11-baseline` + `clawfactory-win11-baseline-v2` (both images
**kept**). No VMs/NICs/PIPs/NSGs/disks — nothing billing. Blob `ClawFactory-Secure-Setup-1.0.37.exe` retained
in `installers`. Diagnostic artifacts (install progress, journal, checkpoint, state files, uninstall log,
harness scripts) kept locally under `C:\Users\bmcki\AppData\Local\Temp\cfv137\` (not in repo).
