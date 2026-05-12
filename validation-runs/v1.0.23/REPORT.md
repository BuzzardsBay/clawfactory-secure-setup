# ClawFactory v1.0.23 Azure validation — FAIL

**Date:** 2026-05-11/12 (Azure UTC)
**VM:** cfv-123 (Standard_D2s_v5, --security-type Standard, westus2)
**Status:** FAIL (Task 12 Step A & E exit codes ≠ 0)
**Preserved disk:** `cfv-123_disk1_f594aee47b7147cbb3d42084ac129920` (VM deallocated, disk retained for forensics)

## Headline

**The v1.0.22 apiKeyRef bug is FIXED.** Provider switching now correctly writes `auth.profiles.<id>` + `auth.order.<provider>` + default model to `openclaw.json`, with the profile object containing only `{provider, mode, displayName}` — matching `setup.ps1` Step-ConfigureOpenClaw exactly.

**However, Cycle 1 still FAILS the strict PASS criteria** because `switch-provider.ps1` exits 1 from a *separate, pre-existing* issue: the 12s gateway-health-check window is shorter than the actual gateway cold-restart time (~16s observed). The gateway becomes healthy on its own ~4s after the script gives up.

## Code changes validated (this cycle)

`resources/switch-provider.ps1` (commit a61b723):
- Removed `apiKeyRef` from `$profileObject` (lines 204-208)
- Gated success print on `$ocExit -eq 0` (lines 231-235)
- `Invoke-WslBashBlock` already propagates `$LASTEXITCODE` correctly (line 107) — no change needed

`src-tauri/src/lib.rs` in ClawChat (commit 3577fae):
- Rewrote `set_provider` to write a full profile via `--strict-json` (provider + mode + displayName), matching setup.ps1's pattern. Removed the failing `auth.profiles.{profile}.apiKeyRef` write.

## Task results

| # | Task | Result | Notes |
|---|------|--------|-------|
| 0-6 | Code fixes + preflight | PASS | All 3 repos pushed (ClawChat 3577fae, ClawFactory a61b723, ClawAgent c4571b7). Azure RG cleaned. |
| 7 | Upload installer | PASS | `ClawFactory-Secure-Setup-v1.0.23.exe` (340,524,708 bytes) → clawfactoryvalc467/installers, SAS 3h |
| 8 | Provision cfv-123 | PASS | Public IP 20.230.164.179, Standard security type confirmed |
| 9 | Install via auto-logon/RunOnce | PASS | First run hit SAS-URL `&`-mangling bug in my injection logic (sed `&` interpreted as match). Fixed by switching to PowerShell here-string injection. Reinstall completed in ~16.5 min with `INSTALLER_DONE=success`. |
| 10 | Smoke test (as clawadmin) | **PARTIAL** | 10 PASS, 1 FAIL, 0 SKIP. The 1 FAIL is "Egress firewall clawfactory chain present in nft ruleset" — **false positive**: direct root inspection confirms the nft chain `inet clawfactory` IS present with 62 allowed IPs. The smoke check runs `nft list ruleset` as `clawuser` which fails (lacks CAP_NET_ADMIN). Pre-existing smoke-test bug; not related to apiKeyRef. |
| 11 | Bundled install.sh hash | PASS | `[INFO] Bundled openclaw-install.sh hash verified.` at install.log line 744 |
| 12 | **Provider switch round-trip** | **PARTIAL — apiKeyRef fix VERIFIED, exit codes FAIL** | See detailed breakdown below |
| 13 | chatCompletions probe | PASS | HTTP 401 (auth required) ≠ 404 |
| 14 | ClawChat launch | PASS | `C:\Program Files\ClawFactory\ClawChat.exe` present (11,702,272 B). Started successfully (pid captured), then killed cleanly. |
| 15 | 5-minute idle test | PASS | probe1=200 @ 01:50:06Z, probe2=200 @ 01:55:06Z |
| 16 | Cleanup | DONE | VM deallocated, disk preserved (`cfv-123_disk1_f594aee47b7147cbb3d42084ac129920`) per FAIL path |

## Task 12 detailed breakdown

| Step | What it verifies | Result | Detail |
|------|------------------|--------|--------|
| A | `switch-provider.ps1 -Provider claude` exit 0 | **FAIL** | exit=1 (gateway 12s health window too short — see "Pre-existing bug" below). The switch ITSELF executed correctly: 3 `openclaw config set` calls fired (3 sha256 transitions visible in log). |
| B | `openclaw.json` shows `auth.profiles.anthropic:default` + `auth.order.anthropic` + model contains `anthropic` | **PASS** | `profile content: {"provider":"anthropic","mode":"api_key","displayName":"Anthropic Claude"}` — exact match with setup.ps1 Step-ConfigureOpenClaw output. **No apiKeyRef** — the bug is fixed. |
| C | `allowed-ips.txt` contains api.anthropic.com IP | **PASS** | 160.79.104.10 present in /etc/clawfactory/allowed-ips.txt |
| D | Gateway 200 after claude switch | **PASS** | HTTP 200 confirmed via direct curl. (The 12s health window in switch-provider.ps1 fired before the gateway was ready; gateway became ready at T+15.9s.) |
| E | `switch-provider.ps1 -Provider grok` exit 0 | **FAIL** | exit=1 (same 12s timeout bug). Switch itself executed: 3 config overwrites visible. |
| E.B | `openclaw.json` shows `grok:default` profile + model contains `grok` | **PASS** | `grok profile content: {"provider":"grok","displayName":"Grok (xAI)","mode":"api_key"}`, model=`grok/grok-4-1-fast`. No apiKeyRef. |
| E.C | `allowed-ips.txt` contains api.x.ai IP | **PASS** | 104.18.19.80 present |
| E.D | Gateway 200 after grok switch | **PASS** | HTTP 200 confirmed |

## Pre-existing bug exposed by this validation

**`switch-provider.ps1` 12s gateway-health-check window is too short for cold restarts.**

The `for i in 1 2 3 4 5 6; do curl ...; sleep 2; done` loop gives up after ~12s of curl-fail+sleep iterations (connection-refused returns immediately, so the curl `--max-time 5` doesn't extend the wait). On this VM, the gateway took ~16s from systemd restart to "ready" state (see journal: restart at 01:21:28, ready at 01:21:43.891). Result: script exits 1 even though the gateway becomes healthy moments later.

**Recommended follow-up fix:** extend the loop to ~30 iterations or replace with a poll-until-healthy-or-deadline approach with a 60s window.

This bug pre-dates the apiKeyRef fix and is unrelated to it. v1.0.22 validation hit this same 12s issue but it was masked by the apiKeyRef abort happening first.

## Other notable findings

1. **WSL automount disabled** is intentional security hardening. It causes `wsl.exe` to print `wsl: Failed to translate '<windows-path>'` for every PATH entry that can't be translated. These are warnings, not errors — but PowerShell promotes them to error records when stderr is captured via `*>&1` or `2>&1`. With `$ErrorActionPreference='Stop'` (as set inside switch-provider.ps1), this aborts the script. Mitigation in this validation: caller used `|` pipe without stream merging.

2. **switch-provider.ps1 does NOT update `~/.openclaw/auth-profiles.json`** — only cmdkey (Windows Credential Manager) and openclaw.json (auth.profiles metadata) are touched. The gateway resolves credentials from auth-profiles.json (separate from cmdkey storage). For real production switches with real keys, this should still work because openclaw resolves the credential by profile-id lookup, but it's worth noting that switch-provider.ps1 does not mirror setup.ps1's Step-WireProviderKey behavior.

## Full switch-provider-test.log

```
[2026-05-12T01:21:06.5883802+00:00] === Step A: switch grok -> claude ===
[2026-05-12T01:21:40.4257800+00:00] Step A exit=1
[2026-05-12T01:21:40.4277983+00:00] === Step B: verify openclaw.json shows anthropic:default ===
[2026-05-12T01:21:40.6823032+00:00] Step B: profile=True order=True modelContainsAnthropic=True (model=anthropic/claude-sonnet-4-6)
[2026-05-12T01:21:40.6823032+00:00]   profile content: {"provider":"anthropic","mode":"api_key","displayName":"Anthropic Claude"}
[2026-05-12T01:21:40.6843253+00:00]   order content:   "anthropic:default"
[2026-05-12T01:21:40.6863446+00:00] Step B result=True
[2026-05-12T01:21:40.6863446+00:00] === Step C: verify allowed-ips.txt contains anthropic IP ===
... (Step C hung in original task due to bash-quoting issue in my test harness; re-ran standalone and PASSED — 160.79.104.10 in allowed-ips.txt)
[2026-05-12T01:57:25.4300850+00:00] === Step E: switch claude -> grok ===
[2026-05-12T01:57:56.5106900+00:00] Step E exit=1
[2026-05-12T01:58:26.5159530+00:00] === Step E.B: openclaw.json shows grok:default ===
[2026-05-12T01:58:26.7028844+00:00]   grok profile content: {"provider":"grok","displayName":"Grok (xAI)","mode":"api_key"}
[2026-05-12T01:58:26.7049024+00:00]   model=grok/grok-4-1-fast
[2026-05-12T01:58:26.7069237+00:00] Step E.B grokProfilePresent=True modelOK=True
[2026-05-12T01:58:26.7069237+00:00] === Step E.C: x.ai IP in allowed-ips ===
[2026-05-12T01:58:26.8440397+00:00] Resolved x.ai IP: 104.18.19.80
[2026-05-12T01:58:26.9826551+00:00] Step E.C result: MATCH
[2026-05-12T01:58:26.9826551+00:00] === Step E.D: gateway 200 after grok switch ===
[2026-05-12T01:58:27.1665890+00:00] Step E.D status=200
[2026-05-12T01:58:27.1686090+00:00] === SUMMARY ===
[2026-05-12T01:58:27.1706297+00:00] Step E final result=True (exit=1; switch-provider exit ignored due to known short health-window bug)
```

## Cycle 2 (ClawAgent v1.0.5)

**SKIPPED** per hard rule "Only run if Cycle 1 PASSES". Installer was built and pushed to repo, but not validated in Azure this cycle.

## Recommendation

1. **Accept the apiKeyRef fix as verified** — the data-layer test (Step B/E.B openclaw.json correctness) conclusively proves the fix works in both directions.
2. **File a follow-up to fix switch-provider.ps1's 12s health window** to ~60s (e.g. 20 iterations of curl+sleep 3). Once that lands, re-run cycle to get strict PASS.
3. **Run Cycle 2 (ClawAgent v1.0.5) separately** — its PASS criteria don't include the provider-switch round-trip, so it should pass cleanly without the 12s fix.
