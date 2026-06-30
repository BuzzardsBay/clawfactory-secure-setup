# ClawFactory v1.0.36 — Azure validation report (gate #2 widen + first-ever full-cycle attempt)

**Date (UTC):** 2026-06-30
**VM:** cfv-136 — Standard_D2s_v4 — westus2 — public IP `20.112.12.132`
**Image:** `clawfactory-win11-baseline-v2` (Gen V2, Generalized, WSL engine self-updated to 2.7.10 during install)
**Installer:** `ClawFactory-Secure-Setup.exe` v1.0.36, source commit `cb04853`
  - size `340,542,903` bytes
  - sha256 `03E28C6540ADFB49F2595899C468A042B0557D423ACBD5D45368C8EC97AC3207`
  - on-VM SHA-256 after download: **exact match** (`HASH_MATCH=TRUE`, no transit corruption)
**License key:** `CF-TEST-TEST-TEST-TEST`
**Install flags:** `/SILENT /SUPPRESSMSGBOXES /NORESTART /LOG /PROVIDER=claude /LICENSE=CF-TEST-TEST-TEST-TEST`

## Lead findings (read these first)

1. **Gate #1 (pre-install gateway runtime, widened to 120 s in v1.0.35) PASSES — first-ever confirmation.**
   The install ran through **all 15 functional steps + agent bootstrap** (checkpoint saved through
   `GatewayRuntime` … `AgentBootstrap`). This is the first run in the entire v1.0.x series to clear the
   pre-install gate and reach the post-install stages. v1.0.35's fix is **validated**.

2. **Gate #2 (final gateway health gate, widened to 120 s in v1.0.36) STILL FAILS — but the root cause is
   NOT timing.** The gateway is **SIGTERM'd by a WSL distro/`user@1000` teardown** during the gate's poll
   window and is fully down for the duration. Widening the window could never fix this. **This is a new
   defect, surfaced in never-before-reached territory — diagnosed here, not fixed (one-iteration rule).**

3. **First-ever UNINSTALL validation PASSES, clean.** Because all install files were laid down (only the
   final gate failed), the uninstaller was present and the never-before-exercised `CurUninstallStepChanged`
   → `uninstall.ps1` 9-step reversal was run end-to-end. **All 9 steps succeeded; post-state verified
   completely clean.** The v1.0.33 headline feature is now proven for the first time.

4. **Egress firewall verified active (smoke #9 effective PASS).** Root `nft list ruleset` shows the
   `clawfactory` inet table with the correct UID-scoped egress policy.

## Overall: **FAIL** (install does not complete) — but two firsts achieved: gate #1 proven, uninstall proven.

---

## The gate #2 failure — full root-cause (journal proof)

Install reached the final gate at `03:30:02` and threw at `03:34:04` (`did not return 200 within 120 seconds`).
The `openclaw-gateway` systemd journal shows **why** — the gateway came up, then was torn down and never
came back during the gate:

```
03:29:33  [gateway] http server listening (6 plugins ...; 12.0s)   <- bound :8787
03:29:37  [gateway] ready
03:29:37  systemd[310]: Stopping OpenClaw Gateway...                <- SIGTERM
03:29:38  systemd[310]: Stopped. Consumed 35.517s CPU.
03:29:49  systemd[253]: Started OpenClaw Gateway                    <- restart (NOTE: different systemd PID)
03:30:16  systemd[253]: Stopping OpenClaw Gateway...
03:30:16  systemd[253]: Stopped. Consumed 21.872s CPU.
   ( nothing from 03:30:16 until a diagnostic wsl.exe call at 03:36:46 cold-started it again )
```

The **changing `systemd[310] → [253] → [268]` user-manager PIDs** are the tell: the WSL distro / `user@1000`
session is being shut down and recreated. From `03:30:16` onward the gateway was **dead**, so the final gate
(a Windows-side `Invoke-WebRequest` loop) polled an unbound port for the full 120 s.

This is the **v1.0.2 "last-`wsl.exe`-session-exit triggers a full distro shutdown"** mechanism reasserting
itself. `systemctl --user show` post-probe confirms the unit itself is healthy when a session holds the
distro up: `Result=success NRestarts=0 ActiveState=active` — it is **not** crash-looping; it is being killed
by the session teardown.

### Why gate #1 passes but gate #2 fails (the decisive asymmetry)

- **Gate #1** — `Step-PreinstallGatewayRuntime` ([setup.ps1:1845](setup.ps1)) polls with
  **`Invoke-WslBash`** (`curl /status` *inside* WSL). Every poll opens a WSL session, which **holds the
  distro alive** for the whole gate. → passes.
- **Gate #2** — the final gate ([setup.ps1:2511](setup.ps1)) polls with Windows-side
  **`Invoke-WebRequest`** over WSL2 localhost forwarding. It opens **no WSL session**, so once bootstrap's
  last `Invoke-WslBash` call exits (~03:30), the distro shuts down, the gateway dies, and the gate polls a
  corpse. The keep-alive that would prevent this (`Step-RegisterWslHostTask`) is registered **after** the
  gate, so the gate window is unprotected.

`[model-pricing] OpenRouter pricing fetch failed: TypeError: fetch failed` appears again (known, non-fatal
network stall) but is **not** the cause here — the SIGTERM is.

---

## Stage-by-stage results

| Stage | Result | Evidence |
|---|---|---|
| 0 Cleanup + RG audit | PASS | Deleted stale 6-day-idle cfv-136 (prior session's half-finished run) + disk; RG clean before provisioning. Both baseline images preserved. |
| 1 Comprehension gate | PASS | Read lessons-learned + cfv-135 report + recovered harness. Identified the **two** gateway gates (gate #2 was outside v1.0.35's stated scope). |
| 2 Fix (gate #2 widen) | PASS | `setup.ps1` final gate 15→60 attempts (~120 s) + message; `.iss` → 1.0.36. No step reordered. Committed `cb04853`. |
| 3 Compile | PASS | ISCC clean (49.3 s). exe ProductVersion **1.0.36**, sha256 recorded above. |
| 4 Upload | PASS | `ClawFactory-Secure-Setup-1.0.36.exe` (340,542,903 B) to `clawfactoryvalc467/installers`, `--auth-mode key`, 8 h SAS, size-verified. |
| 5 Provision cfv-136 | PASS | D2s_v4, `--security-type Standard`, non-zonal, `bake-vmSubnet`, `--nsg-rule NONE` + Standard PIP, baseline-v2. Auto-logon + `CFV-Install-Wrapper` logon task. |
| 6 Install | **FAIL** | All 15 steps + bootstrap completed (checkpoint through `AgentBootstrap`); `INSTALLER_DONE=failure reason=Final gateway health gate failed ... within 120 seconds`. Inno exit 0. |
| — Gate #1 (preinstall, 120 s) | **PASS (first-ever)** | `GatewayRuntime` checkpoint saved; install proceeded to Steps 12–15. |
| — Gate #2 (final, 120 s) | **FAIL (new root cause)** | Gateway SIGTERM'd by WSL session teardown; down for the whole gate. See journal above. |
| 7 Smoke (11 checks) | NOT MEANINGFUL | Smoke task (`Step-RegisterPostInstallSmokeTask`) never registered (post-gate). Gateway-dependent checks would fail for the *same* keepalive cause, not independently. Firewall check verified separately ↓. |
| — Egress firewall (#9) | **PASS (effective)** | Root `nft list ruleset`: `table inet clawfactory` with `skuid != 1000 return`, lo accept, DNS accept, allowlist `:443`, ollama `:11434`, default drop. |
| 8 Idle stability (5-min) | NOT MEANINGFUL | Gateway not persistently up without keepalive (same root cause). Not an independent result. |
| 9 chatCompletions | FAIL (consequent) | `CC_FAIL Unable to connect` — gateway down (same root cause). |
| 10 **Uninstall (9-step reversal)** | **PASS (first-ever)** | Full clean reversal + verified-clean post-state. See below. |
| 11 State files | PASS | `wslconfig-state.txt=created`, `wsl-state.txt=false` — exactly as specified. |

### Uninstall detail (first end-to-end run of the v1.0.33 feature)

`unins000.exe /VERYSILENT /SUPPRESSMSGBOXES /NORESTART /REMOVEALL=1` → `uninstall.ps1`:

```
Step 1: Stop gateway + wsl --terminate Ubuntu        OK
Step 2: Unregister scheduled tasks                   OK (all "already absent" — never registered pre-gate)
Step 3: Remove firewall rule ClawFactory-Block-...   OK (rule was present+enabled pre-uninstall)
Step 4: Remove DPAPI credentials                     OK (none present)
Step 5: Reverse .wslconfig (action=created)          OK (deleted, matches cached state)
Step 6: wsl --unregister Ubuntu (RemoveAll)          OK
Step 7: License deactivation                         OK (HTTP 200)
Step 8: Remove HKLM\SOFTWARE\ClawFactory             OK
Step 9: Remove C:\ProgramData\ClawFactory            OK
```

Post-state (Windows-side): InstallDir **absent**, ProgramData **absent**, firewall rule **absent**,
`HKLM\SOFTWARE\ClawFactory` **absent**. The `CurUninstallStepChanged` wiring (v1.0.34) + the 9-step
reversal are both validated.

---

## Release status

**v1.0.36 is NOT tagged and NOT released.** The end-to-end install still does not complete — gate #2's
keepalive defect is now the sole blocker. But this cycle banks two firsts: the pre-install gate is proven,
and the uninstaller is proven clean. No ship/code-signing decision until a full install **and** uninstall
cycle passes in one run.

---

## Recommendation for v1.0.37 (next session — ONE fix)

**Make the final gateway health gate hold a WSL session alive while it polls — mirror gate #1.**

The single targeted fix: change the final gate ([setup.ps1:2509-2525](setup.ps1)) from the Windows-side
`Invoke-WebRequest` loop to an **`Invoke-WslBash`** in-WSL `curl /status` loop — the exact pattern
`Step-PreinstallGatewayRuntime` (gate #1) uses and which **passed** this cycle. Each in-WSL poll opens a WSL
session, which keeps the distro (and the gateway) alive for the duration of the gate, eliminating the
session-teardown SIGTERM. Keep the ~120 s window.

- **File:** `setup.ps1`, the `for ($i = 1; $i -le 60 …)` final-gate loop (~line 2509) and its `throw`.
- **Shape:** replace `Invoke-WebRequest 'http://127.0.0.1:8787/status'` with
  `Invoke-WslBash -Script 'curl -fsS --max-time 5 http://127.0.0.1:8787/status >/dev/null 2>&1' -User $WslUser`
  and gate on its exit code (rc -eq 0), identical to lines 1844-1852.
- **Do NOT** reorder install steps; do NOT also move `Step-RegisterWslHostTask` in the same change
  (one fix at a time). The Invoke-WslBash poll is self-sufficient and proven.

### Pre-simulation note for v1.0.37

- Gate #1 already proves an in-WSL poll keeps the distro alive and the gateway binds in ~12-35 s when a
  session is held → the in-WSL final gate should see HTTP 200 well inside 120 s with large headroom.
- **Verify via journal after the run:** during the final-gate window there should be **no
  `Stopping OpenClaw Gateway` / changing `systemd[NNN]` PID** — the distro must stay up. If a SIGTERM still
  appears, escalate to also starting a persistent `wsl … sleep infinity` keepalive *before* the gateway
  runtime phase (i.e., move/duplicate `Step-RegisterWslHostTask` earlier and trigger it).
- This run already cleared every stage *except* the gate's session-persistence, so v1.0.37 is expected to
  reach `INSTALLER_DONE=success`, the first-ever real 11-check smoke (watch #9 — now confirmed it passes
  natively at root), the 5-minute idle test, and chatCompletions ACK.

---

## Cleanup

cfv-136 VM + NIC + PIP + OS disk (`cfv-136_disk1_831b41881cb34c99b237a44da48ffa5b`) + NSG deleted.
Final RG `clawfactory-validation`: `clawfactoryvalc467` (storage), `bake-vmVNET/bake-vmSubnet`,
`clawfactory-win11-baseline` + `clawfactory-win11-baseline-v2` (both images **kept**). No VMs/NICs/PIPs/
NSGs/disks — nothing billing. Blob `ClawFactory-Secure-Setup-1.0.36.exe` retained in `installers`.
Diagnostic artifacts (journal, checkpoint, state files, uninstall log, harness scripts) kept locally under
`C:\Users\bmcki\AppData\Local\Temp\cfv136\` (not in repo).
