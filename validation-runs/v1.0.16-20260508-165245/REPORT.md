## ClawFactory v1.0.16 Azure Validation Report

- Timestamp (UTC): 2026-05-08T22:59:10Z (Phase A start) -> 23:16:25Z (INSTALLER_DONE=success) -> 23:29:39Z (live remediation probe)
- Commit: 14b00011c815fc3c7edec273d1073f683877c13b
- VM name: cfv-165245
- VM size: Standard_D2s_v5
- Image: clawfactory-win11-baseline
- Public IP: 20.98.64.56

## Verdict: FAIL

PASS criteria scoreboard:
- Install rc=0: **YES** (INSTALLER_DONE=success)
- Smoke exit 0 AND 0 failures: **YES** (4 pass, 0 fail, 7 skip)
- chatCompletions probe NOT 404: **NO** — HTTP 404
- Both idle probes 200: skipped (cycle failed before idle test)

## Install
- Phase A (download installer + wire RunOnce + reboot): start 22:59:10Z, done 23:07:24Z (8m14s — most of it the 338 MB SAS download)
- INSTALLER_DONE=success observed at 23:16:25Z (poll attempt 6 / ~9 min after reboot trigger)
- VM auto-logon as clawadmin → wrapper.cmd → setup.ps1 ran, exited cleanly

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

Bit-for-bit consistent with all v1.0.15 cycles.

## chatCompletions probe (Phase E): **FAIL — HTTP 404**

Final probe (v3, base64-round-trip + ProcessStartInfo with Arguments string):
```
=== probe started 2026-05-08T23:24:53Z ===
wsl exit=0, b64 len=1060, stderr len=346
openclaw.json bytes=795
token len=48
openclaw.json says chatCompletions.enabled=                  ← EMPTY
--- curl response ---
Not Found
HTTP_STATUS:404                                              ← FAIL
--- end ---
=== probe ended 2026-05-08T23:24:53Z ===
```

The route is unregistered AND the config flag was never written to openclaw.json. The v1.0.16 patch (`--strict-json` on the four `openclaw config set` calls) **did not work** as designed.

## Live root-cause investigation (on the failing VM)

Ran `openclaw --help`, `openclaw config set --help`, and the actual config-set commands directly on the VM as clawuser via scheduled task. Two findings:

### Finding 1: `--strict-json` is the wrong flag name
The actual flag is **`--json`**. `--strict-json` is silently ignored by openclaw 2026.4.27 (unknown flag → call falls through to plain `openclaw config set X true`, and the bare `true` token fails schema validation as a string when the schema expects a boolean → silent drop, exit 0).

Evidence:
```
CMD: openclaw config set gateway.http.endpoints.chatCompletions.enabled true --json
EXIT: 0
STDOUT:
Config overwrite: /home/clawuser/.openclaw/openclaw.json (sha256 ...5e3f7a -> ...fcaace, backup=...)
Updated gateway.http.endpoints.chatCompletions.enabled. Restart the gateway to apply.

CMD: openclaw config get gateway.http.endpoints.chatCompletions.enabled
EXIT: 0
STDOUT:
true
```

After the live `--json` write, openclaw.json contained `"chatCompletions": { "enabled": true }`.

### Finding 2: gateway needs an explicit restart after config change
openclaw's CLI itself says "Restart the gateway to apply" after a successful config set. The existing install path starts the gateway in Step 8b (PreinstallGatewayRuntime) and never restarts it again. Step 9 (ConfigureOpenClaw) and Step 9b (EnableChatCompletions) both write config AFTER startup, so even with the right flag the route registration would still depend on a restart.

Live remediation test (after manual `--json` write + `systemctl --user restart openclaw-gateway`):
```
===== restart openclaw-gateway =====
EXIT: 0
STDOUT: active

token len=48
chatCompletions.enabled per openclaw.json: True
--- curl response post-restart ---
{"error":{"message":"Invalid `model`. Use `openclaw` or `openclaw/<agentId>`.","type":"invalid_request_error"}}
HTTP_STATUS:400                                              ← route is REGISTERED
--- /status post-restart ---
HTTP_STATUS:200
```

HTTP 400 instead of 404 confirms the chatCompletions route is now registered. The 400 is a valid-route, wrong-model-name error from our test request body (we sent `model=grok/grok-4-1-fast`; this build's chatCompletions endpoint expects `openclaw` or `openclaw/<agentId>` — that's a downstream concern for the native chat app, not for v1.0.16/17 route-registration).

## Required fixes for v1.0.17

1. Replace `--strict-json` with `--json` at four sites in setup.ps1:
   - Line ~1575 — `gateway.port 8787 --json`
   - Line ~1708 — `gateway.port 8787 --json`
   - Line ~1710 — `plugins.entries.bonjour.enabled false --json`
   - Line ~1760 — `gateway.http.endpoints.chatCompletions.enabled true --json`
2. Add `systemctl --user restart openclaw-gateway` at the end of `Step-EnableChatCompletions` (last config writer), with a brief `/status` re-poll.

Both fixes are required: the flag fix alone leaves the route unregistered until next reboot; the restart alone (with `--strict-json` retained) accomplishes nothing because the flag never wrote the value.

## Cleanup
- VM cfv-165245 was retained for the live investigation (3 scheduled-task probes ran on it).
- Will be deleted before v1.0.17 cycle so we provision a clean baseline.

## Probe harness lessons (will land in v1.0.17 validation harness)
- `wsl.exe ... 2>&1 | Out-String` mixed PowerShell native-stderr-as-ErrorRecord wrapping with the actual JSON, breaking ConvertFrom-Json. Switched to `[System.Diagnostics.Process]::Start($psi)` with explicit `StandardOutputEncoding`.
- WSL `automount=off` (set by setup.ps1 Step-ConfigureWslConf) means `/mnt/c` is unavailable — writeback approach failed silently. Switched to `base64 -w0 ... | stdout` which is ASCII-safe and round-trips through Process.Start cleanly.
- `ProcessStartInfo.ArgumentList` is .NET 6+; PS 5.1 ships with .NET Framework which only has `.Arguments` (string). Use the string form with proper backtick-escaping for inner quotes.
