## ClawFactory v1.0.21 Azure Validation Report

- Timestamp (UTC): 2026-05-11T20:26:07Z (restart) -> 20:38:16Z (INSTALLER_DONE=success) -> 20:49:20Z (PROBE2)
- Commit: 2997bdf... (HEAD of main at run time, ClawChat v1.1 bundle)
- VM name: cfv-121
- VM size: Standard_D2s_v5
- Image: clawfactory-win11-baseline
- Public IP: 20.3.209.88
- Cleanup: PASS path -- VM, NIC, NSG, public IP, OS disk all deleted

## Verdict: PASS

All six criteria met:

| # | Criterion | Result |
|---|---|---|
| 1 | Install rc=0 (INSTALLER_DONE=success) | **YES** -- attempt 7 / ~12 min after reboot |
| 2 | Smoke: exit 0 AND 0 failures | **YES** -- 4 pass, 0 fail, 7 skip (SYSTEM context) |
| 3 | Bundled install.sh used (log line present) | **YES** -- `[2026-05-11 20:33:01] [INFO] Bundled openclaw-install.sh hash verified.` |
| 4 | chatCompletions probe NOT 404 | **YES** -- HTTP 500 (route registered; upstream LLM error from placeholder API key) |
| 5 | ClawChat present and launches | **YES** -- `C:\Program Files\ClawFactory\ClawChat.exe` SHA-256 `a16006ff…1bec8` (v1.1 build), started under clawadmin (pid 10160), killed cleanly |
| 6 | Both idle probes 200 | **YES** -- PROBE1=200 @ 20:43:34Z, PROBE2=200 @ 20:49:20Z, no retry |

First validation cycle that exercises ClawChat v1.1 (settings tab, security tiers, provider switching, gateway auto-start) end-to-end on Azure.

## Install timeline

| Attempt | UTC | install.log latest |
|---|---|---|
| 1 | 20:28:59 | Phase A download complete (340,535,864 bytes) |
| 2 | 20:30:32 | `[wsl:root exit] 0` (Steps 2-7 progressing) |
| 3 | 20:32:04 | **`Bundled openclaw-install.sh hash verified.`** ← Step 8 [R2] using bundled file |
| 4 | 20:33:37 | `[wsl:clawuser exit] 0` (Step 8 OpenClaw install running) |
| 5 | 20:35:09 | Default main agent model: grok/grok-4-1-fast |
| 6 | 20:36:42 | Step 16: Registering ClawFactory WSL Host task |
| 7 | 20:38:16 | **INSTALLER_DONE=success** |

## Bundled install.sh verification (Task 5): PASS

```
INSTALL_LOG=C:\ProgramData\ClawFactory\install.log
BUNDLED_INSTALL_LINE_FOUND
MATCH: [2026-05-11 20:33:01] [INFO] Bundled openclaw-install.sh hash verified.
MATCH: [wsl:clawuser out] OK: SOUL.md hash verified            ← unrelated; SOUL.md hash check
```

Bundled-install path used cleanly. No `curl`/`Invoke-WebRequest` against `openclaw.ai/install.sh` during install -- hash drift class remains eliminated.

## Smoke test: 4 pass, 0 fail, 7 skip (exit 0)

Bit-for-bit identical to v1.0.15 through v1.0.20 PASSes -- four real checks (AgentBootstrap checkpoint, loopback gateway 200, inbound firewall, WSL Host task), seven WSL-dependent checks SKIP under run-command SYSTEM context.

## chatCompletions probe: PASS -- HTTP 500 (route registered)

```
=== probe started 2026-05-11T20:41:18Z ===
[probe] openclaw.json bytes=910
[probe] token len=48
--- response body ---
{"error":{"message":"internal error","type":"api_error"}}
HTTP_STATUS:500
=== probe ended 2026-05-11T20:41:55Z ===
```

Same upstream-LLM-error 500 pattern as prior cycles. Placeholder API key + valid token + route registered.

## ClawChat launch: PASS

```
path=C:\Program Files\ClawFactory\ClawChat.exe
size=11700736                                                          ← 11.16 MB (v1.1 build, was 10.88 MB in v1.0.0)
sha256=a16006ffd494321ca03b5fe6e16a2a32fee89d9f9149b7a9362adc3ea361bec8 ← matches local v1.1 build hash
RESULT=PRESENT
started=True
pid=10160
killed=true
```

SHA-256 matches the local v1.1 build verified before bundling. First validation that the v1.1 binary (settings tab + tier UI + gateway auto-start) launches under a clawadmin scheduled task without crash.

## Idle test: PROBE1=200, PROBE2=200, no retry

```
PROBE1: 200    @ 2026-05-11T20:43:34Z
                ... 5-min idle gap ...
PROBE2: 200    @ 2026-05-11T20:49:20Z
```

Both first-attempt 200s within the 15-second budget. WSL Host scheduled task + vmIdleTimeout=-1 keeping gateway alive idle.

## Comparison: v1.0.20 (PASS) vs v1.0.21 (PASS)

| Dimension | v1.0.20 | v1.0.21 |
|---|---|---|
| ClawChat bundled binary | v1.0.0 (10.88 MB, sha256 `0bb56c62…b6d45`) | v1.1 (11.16 MB, sha256 `a16006ff…1bec8`) |
| ClawChat features | conversation threads + streaming SSE + theme toggle | + settings tab + provider switching + security tiers + gateway auto-start |
| OpenClaw install.sh | bundled, hash-verified | bundled, hash-verified |
| Step 8 [R2] | PASS | PASS |
| Smoke / completions / ClawChat-launch / idle | all PASS | all PASS (identical numbers) |

## Cleanup (PASS verdict)

- VM cfv-121: deleted
- NIC `cfv-121VMNic`, NSG `cfv-121NSG`, public IP `cfv-121PublicIP`: deleted
- OS disk `cfv-121_disk1_*`: deleted
- Storage account, baseline VNET, baseline image: untouched (per HARD RULES)

## Final declaration: v1.0.21 STABLE

ClawChat v1.1 bundle ships clean. All v1.0.20 quality gates preserved; new settings UI verified launchable. Provider switching + security tier UI ready for end-user testing in the field.

## Artifacts

- [REPORT.md](REPORT.md)
- [smoke-test.json](smoke-test.json)
- [bundled-check.json](bundled-check.json)
- [completions-probe.json](completions-probe.json)
- [clawchat-launch.json](clawchat-launch.json)
- [idle-probe1.json](idle-probe1.json)
- [idle-probe2.json](idle-probe2.json)
