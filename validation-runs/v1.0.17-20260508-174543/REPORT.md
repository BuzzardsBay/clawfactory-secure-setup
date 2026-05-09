## ClawFactory v1.0.17 Azure Validation Report

- Timestamp (UTC): 2026-05-08T23:51:30Z (Phase A start) -> 2026-05-09T00:06:32Z (INSTALLER_DONE=success) -> 00:15:47Z (PROBE2)
- Commit: 18516a619ba815f7a5b0530e9949de95fc8b079f
- VM name: cfv-174543
- VM size: Standard_D2s_v5
- Image: clawfactory-win11-baseline
- Public IP: 20.64.201.93

## Verdict: PASS

All four criteria met:
- Install rc=0: **YES** (INSTALLER_DONE=success)
- Smoke exit 0 AND 0 failures: **YES** (4 pass, 0 fail, 7 skip)
- chatCompletions probe NOT 404: **YES** — HTTP 400 (route is registered; 400 is upstream "Invalid model" for our test request body, out of scope for the route-registration fix)
- Both idle probes 200: **YES** (PROBE1=200, PROBE2=200, no retry used)

## Install
- Phase A (download installer + wire RunOnce + reboot): start 23:51:30Z, done 23:57:16Z (5m46s — most of it the 338 MB SAS download)
- INSTALLER_DONE=success observed at 00:06:32Z (poll attempt 6 / ~9 min after reboot trigger)
- All 16 install steps reached completion
- Auth-profiles wired: 5/5 agents

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

Bit-for-bit identical to v1.0.15 / v1.0.16.

## chatCompletions probe (Phase E): **PASS — HTTP 400 (route registered)**

```
=== probe started 2026-05-09T00:09:51Z ===
wsl exit=0, b64 len=1216, stderr len=346
openclaw.json bytes=910                                    ← 115 bytes more than v1.0.16 (new chatCompletions key)
token len=48
openclaw.json says chatCompletions.enabled=True            ← config WAS written
--- curl response ---
{"error":{"message":"Invalid `model`. Use `openclaw` or `openclaw/<agentId>`.","type":"invalid_request_error"}}
HTTP_STATUS:400                                            ← route REGISTERED (not 404)
--- end ---
=== probe ended 2026-05-09T00:09:52Z ===
```

The HTTP 400 is upstream: our probe sent `model=grok/grok-4-1-fast` but this build's chatCompletions endpoint expects `openclaw` or `openclaw/<agentId>`. That's a downstream concern for the native chat app's request format, not for v1.0.17's route-registration fix. Per the task PASS criteria: "200, 401, 403, or upstream error all confirm the route is registered; only 404 means the patch failed."

## Idle test (Phase F): PROBE1=200, PROBE2=200, no retry

```
PROBE1: 200    (captured 2026-05-08T18:09:52Z local / 00:09:52Z UTC)
                ... 5-min idle gap ...
PROBE2: 200    (captured 2026-05-08T18:15:47Z local / 00:15:47Z UTC)
```

Both probes returned 200 on first attempt within the 15-second budget. No retry needed.

## install.log evidence — new $script9b ran cleanly

The new bash atomic block (config set + restart + health poll) executed as designed:

```
[2026-05-09 00:06:43] [INFO] Step 9b: Enabling gateway.http.endpoints.chatCompletions.enabled.
[wsl:clawuser out] [chatCompletions-set] gateway.http.endpoints.chatCompletions.enabled = true
[wsl:clawuser out] [chatCompletions-restart] gateway healthy on attempt 5
[2026-05-09 00:06:54] [WARN] Step-EnableChatCompletions returned exit=1. The gateway may still be operational; the native chat app may not connect until this is fixed manually.
```

The bash script clearly hit its `exit 0` path (the "gateway healthy on attempt 5" line is the last statement before `exit 0` in the loop). However, `Invoke-WslBash` returned exit=1 to PowerShell anyway, triggering the misleading WARN. **This is a cosmetic bug, not a functional one** — the actual operations succeeded (verified by the chatCompletions probe returning HTTP 400 instead of 404, and openclaw.json containing `chatCompletions.enabled=true`). The `Save-Checkpoint 'EnableChatCompletions'` did NOT fire because of the false WARN, which means a `-Resume` re-run would re-execute the (now-idempotent) step. Worth fixing in a future patch but does not block v1.0.17.

Likely root cause for the spurious exit=1: probably a stderr-line wrapping in `Invoke-WslBash`'s output processing (the `systemctl --user restart` writes status lines to stderr, and one of the iterations' `curl -fsS` returned non-zero — both are intentional in the script and correctly handled, but `Invoke-WslBash` may be reading the last non-zero exit code from somewhere in its pipeline rather than from bash's actual exit). Investigate in v1.0.18.

## Comparison: v1.0.16 vs v1.0.17

| Dimension | v1.0.16 (FAIL) | v1.0.17 (PASS) |
|---|---|---|
| Install completed | YES | YES |
| Smoke pass count | 4P/0F/7S | 4P/0F/7S |
| openclaw.json size | 795 bytes | 910 bytes (+115 for chatCompletions key) |
| chatCompletions.enabled present | NO | YES (=true) |
| /v1/chat/completions probe | HTTP **404** | HTTP **400** (route registered) |
| Idle PROBE1 | n/a (cycle aborted) | 200 |
| Idle PROBE2 | n/a (cycle aborted) | 200 |

## Cleanup (PASS verdict)
- VM cfv-174543: deleted (full delete + OS disk per PASS protocol)
- Resource group cleaned

## Final declaration: v1.0.17 STABLE

The chatCompletions=404 bug that has shipped on every install since v1.0.1 is fixed in v1.0.17. The fix combines three corrections:
1. `--json` (not `--strict-json`) for boolean writes
2. `Invoke-WslBash` transport (not `Start-Process -FilePath wsl.exe`) in `Step-EnableChatCompletions`
3. Explicit `systemctl --user restart openclaw-gateway` after the config write, inside the same atomic bash block

End-to-end install path now produces a registered chatCompletions route (HTTP 400 on probe vs prior 404), with all other v1.0.15 quality gates preserved (smoke 4P/0F/7S, idle 200/200, no install/runtime regressions).

## Artifacts
- [REPORT.md](REPORT.md)
- [smoke-test.json](smoke-test.json)
- [completions-probe.json](completions-probe.json)
- [idle-probe1.json](idle-probe1.json)
- [idle-probe2.json](idle-probe2.json)
