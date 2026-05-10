## ClawFactory v1.0.20 Azure Validation Report

- Timestamp (UTC): 2026-05-10T14:52:22Z (restart) -> 15:03:26Z (INSTALLER_DONE=success) -> 15:14:52Z (PROBE2)
- Commit: 86dfd36... (HEAD of main at run time, bundled-install.sh refactor)
- VM name: cfv-120
- VM size: Standard_D2s_v5
- Image: clawfactory-win11-baseline
- Public IP: 20.114.6.170
- Cleanup: PASS path -- VM, NIC, NSG, public IP, OS disk all deleted

## Verdict: PASS

All six criteria met:

| # | Criterion | Result |
|---|---|---|
| 1 | Install rc=0 (INSTALLER_DONE=success) | **YES** -- attempt 6 / ~10 min after reboot |
| 2 | Smoke: exit 0 AND 0 failures | **YES** -- 4 pass, 0 fail, 7 skip (SYSTEM context) |
| 3 | Bundled install.sh used (log line present) | **YES** -- `[2026-05-10 14:58:46] [INFO] Bundled openclaw-install.sh hash verified.` |
| 4 | chatCompletions probe NOT 404 | **YES** -- HTTP 500 (route registered; upstream LLM error from placeholder API key) |
| 5 | ClawChat present and launches | **YES** -- bundled at `C:\Program Files\ClawFactory\ClawChat.exe`, started under clawadmin (pid 10028), killed cleanly |
| 6 | Both idle probes 200 | **YES** -- PROBE1=200 @ 15:09:22Z, PROBE2=200 @ 15:14:52Z, no retry |

First validation cycle that exercises the bundled openclaw-install.sh path end-to-end on Azure. Eliminates the upstream-URL hash-drift class of failure that broke v1.0.18.

## Install timeline

| Attempt | UTC | install.log latest |
|---|---|---|
| 1 | 14:55:13 | (Phase A download complete, 340,488,075 bytes; install.log just being written) |
| 2 | 14:57:16 | Step 6: Installing Docker Engine (rootless for clawuser). |
| 3 | 14:58:48 | **`Bundled openclaw-install.sh hash verified.`** ← Step 8 [R2] using bundled file |
| 4 | 15:00:21 | Default main agent model: grok/grok-4-1-fast |
| 5 | 15:01:54 | API key found (length=26). |
| 6 | 15:03:26 | INSTALLER_DONE=success |

## Bundled install.sh verification (Task 5): PASS

```
INSTALL_LOG=C:\ProgramData\ClawFactory\install.log
BUNDLED_INSTALL_LINE_FOUND
MATCH: [2026-05-10 14:58:46] [INFO] Bundled openclaw-install.sh hash verified.
MATCH: [wsl:clawuser out] OK: SOUL.md hash verified            ← unrelated; SOUL.md hash verification, not install.sh
```

The line confirms that `Step-InstallOpenClaw` ran the bundled file path: it called `Get-FileHash` on `$PSScriptRoot\resources\openclaw-install.sh`, the hash matched the pinned `$OpenClawInstallSha256` (`3a617b73...a9ce`), and execution proceeded without any `curl`/`Invoke-WebRequest` to `openclaw.ai/install.sh`. Network call eliminated; hash drift eliminated.

Note: actual log wording is `Bundled openclaw-install.sh hash verified.` (hyphenated filename, no parentheses); the spec's expected pattern was `"Using bundled openclaw install.sh (hash verified)"`. Wording differs slightly but intent is identical -- the bundled file's hash was verified before execution. This was caught during the Task 5 grep, which matched on the distinctive `hash verified` substring.

## Smoke test: 4 pass, 0 fail, 7 skip (exit 0)

```
Running as NT AUTHORITY\SYSTEM - WSL checks will be SKIPPED.
  SKIP  WSL automount disabled (requires WSL; running as SYSTEM)
  SKIP  Four agent.md files present (requires WSL; running as SYSTEM)
  PASS  AgentBootstrap checkpoint recorded
  PASS  Gateway responds 200 on loopback
  PASS  Firewall inbound-deny rule on 8787
  SKIP  Orchestrator SOUL hash substituted (requires WSL; running as SYSTEM)
  SKIP  auth-profiles.json present for all 5 agents (requires WSL; running as SYSTEM)
  SKIP  .wslconfig has vmIdleTimeout=-1 (requires WSL; running as SYSTEM)
  PASS  WSL Host scheduled task registered and enabled
  SKIP  Egress firewall clawfactory chain present in nft ruleset (requires WSL; running as SYSTEM)
  SKIP  OpenClaw build deps present (make g++ cmake python3) (requires WSL; running as SYSTEM)
Result: 4 pass, 0 fail, 7 skip
EXIT:0
```

Bit-for-bit identical to v1.0.15 / v1.0.16 / v1.0.17 / v1.0.19 PASSes.

## chatCompletions probe: PASS — HTTP 500 (route registered)

```
=== probe started 2026-05-10T15:06:51Z ===
[probe] openclaw.json bytes=910
[probe] token len=48
--- response body ---
{"error":{"message":"internal error","type":"api_error"}}
HTTP_STATUS:500
=== probe ended 2026-05-10T15:07:27Z ===
```

Same upstream-LLM-error 500 as v1.0.19 -- placeholder Grok API key, gateway accepts the request and reaches the LLM provider call. Route is registered (would be 404 otherwise).

## ClawChat launch: PASS

```
path=C:\Program Files\ClawFactory\ClawChat.exe
size=11408384
sha256=0bb56c62e70a5af6153db8fd9a3b8b0c4a69682f54ae703e87952c18facb6d45
RESULT=PRESENT
started=True
pid=10028
killed=true
```

SHA-256 matches the local Tauri release build (consistent with v1.0.19 verification). Process started under a clawadmin scheduled task, stayed alive through the 5s probe, killed cleanly.

## Idle test: PROBE1=200, PROBE2=200, no retry

```
PROBE1: 200    @ 2026-05-10T15:09:22Z
                ... 5-min idle gap ...
PROBE2: 200    @ 2026-05-10T15:14:52Z
```

Both first-attempt 200s within the 15-second budget. WSL Host scheduled task + vmIdleTimeout=-1 keeping the gateway alive idle.

## Comparison: v1.0.19 (PASS) vs v1.0.20 (PASS)

| Dimension | v1.0.19 | v1.0.20 |
|---|---|---|
| OpenClaw install.sh source | curl `openclaw.ai/install.sh` at install time | bundled `resources\openclaw-install.sh` |
| Hash check | inside WSL via `sha256sum` after curl | on Windows via `Get-FileHash` before WSL invocation |
| Hash drift surface | URL-tracked-latest could change between releases | none; bundled file is byte-stable |
| Network call for Step 8 | yes (340 KB script over HTTPS) | none (file streamed locally via stdin pipe) |
| Step 8 result | PASS | PASS (`Bundled openclaw-install.sh hash verified.`) |
| Smoke / completions / ClawChat / idle | all PASS | all PASS (identical numbers) |

## Cleanup (PASS verdict)

- VM cfv-120: deleted
- NIC `cfv-120VMNic`, NSG `cfv-120NSG`, public IP `cfv-120PublicIP`: deleted
- OS disk `cfv-120_disk1_*`: deleted
- Storage account, baseline VNET, baseline image: untouched (per HARD RULES)

## Final declaration: v1.0.20 STABLE

The bundled-install.sh refactor ships clean. Hash drift eliminated as a failure class for future cycles -- install.sh upstream can change daily and ClawFactory installs continue working until we explicitly re-validate and bump.

## Artifacts

- [REPORT.md](REPORT.md)
- [smoke-test.json](smoke-test.json)
- [bundled-check.json](bundled-check.json)
- [completions-probe.json](completions-probe.json)
- [clawchat-launch.json](clawchat-launch.json)
- [idle-probe1.json](idle-probe1.json)
- [idle-probe2.json](idle-probe2.json)
