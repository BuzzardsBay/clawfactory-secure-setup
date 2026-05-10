## ClawFactory v1.0.19 Azure Validation Report

- Timestamp (UTC): 2026-05-10T13:00:42Z (restart) -> 13:11:17Z (INSTALLER_DONE=success) -> 13:23:29Z (PROBE2)
- Commit: bee3f1212e... (HEAD of main at run time, hash-bump commit)
- VM name: cfv-119
- VM size: Standard_D2s_v5
- Image: clawfactory-win11-baseline
- Public IP: 4.246.120.170
- Cleanup: PASS path — VM, NIC, NSG, public IP, OS disk all deleted

## Verdict: PASS

All five criteria met:

| # | Criterion | Result |
|---|---|---|
| 1 | Install rc=0 (INSTALLER_DONE=success) | **YES** — observed at attempt 6 / ~10 min after reboot |
| 2 | Smoke: exit 0 AND 0 failures | **YES** — 4 pass, 0 fail, 7 skip (SYSTEM context) |
| 3 | chatCompletions probe NOT 404 | **YES** — HTTP 500 (route registered; upstream LLM error from placeholder API key) |
| 4 | ClawChat present and launches | **YES** — bundled at `C:\Program Files\ClawFactory\ClawChat.exe`, started cleanly under clawadmin (pid 7832), killed without error |
| 5 | Both idle probes 200 | **YES** — PROBE1=200 @ 13:17:44Z, PROBE2=200 @ 13:23:29Z, no retry |

This is the first validation cycle that exercises the ClawChat bundle end-to-end on Azure (added in v1.0.18, which FAILed at Step 8 due to upstream install.sh hash drift before reaching ClawChat verification).

## Install timeline

| Attempt | UTC | install.log latest |
|---|---|---|
| 1 | 13:03:33 | Step 1: Preflight checks. Selected provider: Grok (xAI). |
| 2 | 13:05:06 | Step 6: Installing Docker Engine (rootless for clawuser). |
| 3 | 13:06:39 | Step 8 [R2]: Installing OpenClaw with SHA-256 pinning. |
| 4 | 13:08:11 | Default main agent model: grok/grok-4-1-fast |
| 5 | 13:09:44 | (post-OpenClaw, agent setup) |
| 6 | 13:11:17 | INSTALLER_DONE=success |

Step 8 [R2] passed cleanly with the new pin `3a617b73ea35ac23cf856ce9615b69d0ace4090d236e0a57bbc638f01676a9ce`. The diff prior→current was reviewed by an independent security sub-agent (verdict: SAFE TO PROCEED) before the bump.

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

Bit-for-bit identical to v1.0.15 / v1.0.16 / v1.0.17 PASSes.

## chatCompletions probe: PASS — HTTP 500 (route registered)

```
=== probe started 2026-05-10T13:14:28Z ===
[probe] openclaw.json bytes=910            ← chatCompletions.enabled wired in (matches v1.0.17)
[probe] token len=48
--- response body ---
{"error":{"message":"internal error","type":"api_error"}}
HTTP_STATUS:500
=== probe ended 2026-05-10T13:15:04Z ===
```

The HTTP 500 is upstream — the gateway's chatCompletions handler reached the LLM provider call and that errored (placeholder Grok API key). Per PASS rule, only HTTP 404 means the route patch failed; any other code (including 500) confirms the route is registered.

## ClawChat launch verification: PASS — present and launches

```
=== ClawChat probe 2026-05-10T13:16:29Z ===
path=C:\Program Files\ClawFactory\ClawChat.exe
size=11408384
sha256=0bb56c62e70a5af6153db8fd9a3b8b0c4a69682f54ae703e87952c18facb6d45
RESULT=PRESENT
started=True
pid=7832
killed=true
```

SHA-256 `0bb56c62…b6d45` matches the local Tauri release build (verified during the bundle session). Process started under a clawadmin scheduled task (run-command runs as SYSTEM, which can't host a GUI process), stayed alive 5 seconds, killed cleanly. First end-to-end ClawChat verification on a real Azure install.

## Idle test: PROBE1=200, PROBE2=200, no retry

```
PROBE1: 200    @ 2026-05-10T13:17:44Z
                ... 5-min idle gap ...
PROBE2: 200    @ 2026-05-10T13:23:29Z
```

Both probes returned 200 on first attempt within the 15-second budget. WSL Host scheduled task + vmIdleTimeout=-1 keeping the WSL VM alive through idle.

## install.log — Step 8 [R2] hash check passed

The new pin ran cleanly. No mismatch line; OpenClaw install.sh fetched, hashed, matched expected hash, executed.

## Comparison: v1.0.18 (FAIL) vs v1.0.19 (PASS)

| Dimension | v1.0.18 (FAIL) | v1.0.19 (PASS) |
|---|---|---|
| OpenClaw install.sh pin | `57f025ba…d49d` (stale; upstream changed) | `3a617b73…a9ce` (current) |
| Step 8 [R2] | FAIL (hash mismatch, exit 43) | PASS |
| Install completed | NO | YES |
| Smoke pass count | n/a | 4P/0F/7S |
| chatCompletions probe | n/a | HTTP 500 (route registered) |
| ClawChat verification | n/a | PRESENT + started |
| Idle PROBE1 / PROBE2 | n/a | 200 / 200 |

## Cleanup (PASS verdict)

- VM cfv-119: deleted
- NIC `cfv-119VMNic`, NSG `cfv-119NSG`, public IP `cfv-119PublicIP`: deleted
- OS disk `cfv-119_disk1_383fffe814c24ba49c55a9da4822fc7c`: deleted
- Storage account, baseline VNET, baseline image: untouched (per HARD RULES)

## Final declaration: v1.0.19 STABLE

Routine OpenClaw install.sh pin bump (one-line `setup.ps1` change in both repos) plus version increments. All v1.0.17 quality gates preserved (smoke 4P/0F/7S, idle 200/200, chatCompletions route registered) AND the new ClawChat bundle path is verified end-to-end for the first time.

## Artifacts

- [REPORT.md](REPORT.md)
- [smoke-test.json](smoke-test.json)
- [completions-probe.json](completions-probe.json)
- [clawchat-launch.json](clawchat-launch.json)
- [idle-probe1.json](idle-probe1.json)
- [idle-probe2.json](idle-probe2.json)
