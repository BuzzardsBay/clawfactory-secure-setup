# ClawFactory v1.0.24 Azure validation — FAIL

**Date:** 2026-05-12 (Azure UTC)
**VM:** cfv-124 (Standard_D2s_v5, --security-type Standard, westus2, public IP 20.230.162.61)
**Status:** **FAIL** (Task 6 Step A & E exit codes ≠ 0)
**Preserved disk:** `cfv-124_disk1_225c9f3c06684094b2e9cfe6f5ee972f` (VM deallocated)

## Headline

**The 60s gateway-health window in v1.0.24 is still not enough.** Step A took 97s wall time and exited 1 (gateway didn't return 200 within the 60s curl loop). Step E exited 1 after only 38s — even shorter than the 60s window — for reasons that aren't fully explained by the script logic (see "Open question" below). The gateway IS healthy both during and after the switches when probed independently (Step D + E.D both PASS).

**The apiKeyRef fix (v1.0.23) remains verified:** Step B and Step E.B both confirm `auth.profiles.<id>` is written with `{provider, mode, displayName}` only — no apiKeyRef — matching `setup.ps1` Step-ConfigureOpenClaw exactly.

## Task results

| # | Task | Result | Notes |
|---|------|--------|-------|
| 0 | Preflight cleanup | PASS | cfv-123 + disk `cfv-123_disk1_f594aee47b7147cbb3d42084ac129920` deleted. RG: 0 VMs, 0 disks, 1 image, 1 storage. |
| 1 | Upload installer | PASS | `ClawFactory-Secure-Setup-v1.0.24.exe` (340,534,872 B) → clawfactoryvalc467/installers, SAS until 22:58Z |
| 2 | Provision cfv-124 | PASS | Public IP 20.230.162.61, Standard security type |
| 3 | Install via auto-logon/RunOnce | PASS | INSTALLER_DONE=success at T+1051s (~17.5 min) |
| 4 | **Smoke test** | **EFFECTIVE PASS** (10 real PASS + 1 known false positive) | See below |
| 5 | Bundled install.sh hash | PASS | `[INFO] Bundled openclaw-install.sh hash verified.` at install.log line 744 |
| 6 | **Provider switch round-trip** | **FAIL on exit codes; PASS on all data-layer checks** | See detailed breakdown |
| 7 | chatCompletions probe | PASS | HTTP 400 (invalid model param, expects `openclaw/<agentId>`) ≠ 404 — endpoint reachable + auth working |
| 8 | ClawChat launch | PASS | `ClawChat.exe` present (11,702,272 B). Started (pid captured), killed cleanly. |
| 9 | 5-minute idle test | PASS | probe1=200 @ 23:41:27Z, probe2=200 @ 23:46:27Z (exactly 5 min apart) |
| 10 | Cleanup | DONE (FAIL path) | cfv-124 deallocated, disk preserved |

## Task 4 — Smoke test detail (full WSL coverage achieved)

Run as clawadmin via scheduled task (not SYSTEM run-command), so all WSL checks executed instead of skipping. Result: **10 PASS, 1 FAIL, 0 SKIP** (exit code 1).

```
  PASS  WSL automount disabled
  PASS  Four agent.md files present
  PASS  AgentBootstrap checkpoint recorded
  PASS  Gateway responds 200 on loopback
  PASS  Firewall inbound-deny rule on 8787
  PASS  Orchestrator SOUL hash substituted
  PASS  auth-profiles.json present for all 5 agents
  PASS  .wslconfig has vmIdleTimeout=-1
  PASS  WSL Host scheduled task registered and enabled
  FAIL  Egress firewall clawfactory chain present in nft ruleset
  PASS  OpenClaw build deps present (make g++ cmake python3)
```

The 1 FAIL is the **same known false positive as v1.0.23**: `smoke-test.ps1:172` runs `nft list ruleset` as `clawuser`, which fails (lacks CAP_NET_ADMIN). Direct root inspection confirmed the firewall is correctly configured:

```
=== fw-backend ===
nftables
=== nft chain head ===
table inet clawfactory {
    set allowed_ipv4 {
        type ipv4_addr
        flags dynamic,timeout
        timeout 6h
        elements = { 3.90.170.8 expires 5h51m53s960ms, ...
=== ip count ===
62 /etc/clawfactory/allowed-ips.txt
```

Per the user-provided rule for this cycle: not counted as a blocking failure. Effective Task 4: PASS.

## Task 6 — Provider switch detailed breakdown

| Step | What it verifies | Result | Detail |
|------|------------------|--------|--------|
| A | `switch-provider.ps1 -Provider claude` exit 0 | **FAIL** | exit=1, 97s wall time (20:29:57 → 20:31:34). 60s gateway-health window timed out. |
| B | openclaw.json correct after claude switch | **PASS** | `auth.profiles.anthropic:default = {"provider":"anthropic","mode":"api_key","displayName":"Anthropic Claude"}`, `auth.order.anthropic = ["anthropic:default"]`, model `anthropic/claude-sonnet-4-6`. **No apiKeyRef. Fix verified.** |
| C | api.anthropic.com IP in allowed-ips.txt | **PASS** | 160.79.104.10 present (checked via grep -F after the fact) |
| D | Gateway 200 after claude switch | **PASS** | HTTP 200 confirmed (post-recovery check; gateway eventually responsive) |
| E | `switch-provider.ps1 -Provider grok` exit 0 | **FAIL** | exit=1, 38s wall time (23:29:33 → 23:30:11). Notably shorter than 60s — see "Open question" below. |
| E.B | openclaw.json correct after grok switch | **PASS** | `auth.profiles.grok:default = {"provider":"grok","displayName":"Grok (xAI)","mode":"api_key"}`, model `grok/grok-4-1-fast`. No apiKeyRef. |
| E.C | api.x.ai IP in allowed-ips.txt | **PASS** | 104.18.18.80 present |
| E.D | Gateway 200 after grok switch | **PASS** | HTTP 200 confirmed 1 second after Step E exit |

### Open question — Step E exit timing

Step E exited in 38s wall, which is **less than the 60s health-loop window alone**. With `set -euo pipefail` in the bash, the only ways the script can exit before the loop completes are: (1) one of the openclaw config commands failed, or (2) `openclaw models set` failed. But the openclaw.json verification (Step E.B) shows the profile, order, and model field were all written correctly — so those commands clearly succeeded. The gateway became healthy ~1s after the script exited, suggesting the curl loop was very close to succeeding but the script exited prematurely. Worth investigating in a follow-up — perhaps the bash is exiting on a non-fatal warning that `set -e` is treating as fatal.

## Task 6 — Full switch-provider-test.log

```
[2026-05-12T20:29:57.5477211+00:00] === Step A: switch grok -> claude ===
[2026-05-12T20:31:34.5455620+00:00] Step A exit=1
[2026-05-12T20:31:34.5475761+00:00] === Step B: verify openclaw.json shows anthropic:default ===
[2026-05-12T20:31:34.8311348+00:00] Step B: profile=True order=True modelContainsAnthropic=True (model=anthropic/claude-sonnet-4-6)
[2026-05-12T20:31:34.8331752+00:00]   profile content: {"provider":"anthropic","mode":"api_key","displayName":"Anthropic Claude"}
[2026-05-12T20:31:34.8351990+00:00]   order content:   "anthropic:default"
[2026-05-12T20:31:34.8372194+00:00] Step B result=True
[2026-05-12T20:31:34.8389141+00:00] === Step C: anth IP in allowed-ips ===
    (Step C hung in original run -- bash quoting issue in my test harness, NOT a switch-provider issue; re-ran standalone and PASSED)
[2026-05-12T23:29:33.5983730+00:00] === Step C (re-run via simpler bash): anth IP check ===
[2026-05-12T23:29:33.7811427+00:00] Step C: ANTHROPIC_IP_FOUND
[2026-05-12T23:29:33.7811427+00:00] === Step D: gateway 200 after claude switch (post-recovery) ===
[2026-05-12T23:29:33.9586309+00:00] Step D status=200
[2026-05-12T23:29:33.9586309+00:00] === Step E: switch claude -> grok ===
[2026-05-12T23:30:11.7441194+00:00] Step E exit=1
[2026-05-12T23:30:11.7471526+00:00] === Step E.B: verify openclaw.json shows grok:default ===
[2026-05-12T23:30:12.0763249+00:00]   grok profile content: {"provider":"grok","displayName":"Grok (xAI)","mode":"api_key"} (model=grok/grok-4-1-fast)
[2026-05-12T23:30:12.0798633+00:00] Step E.B grokProfile=True modelGrok=True
[2026-05-12T23:30:12.0813829+00:00] === Step E.C: x.ai IP in allowed-ips ===
[2026-05-12T23:30:12.3200246+00:00] Resolved x.ai IP: 104.18.18.80
[2026-05-12T23:30:12.5151579+00:00] Step E.C: XAI_IP_FOUND
[2026-05-12T23:30:12.5171784+00:00] === Step E.D: gateway 200 after grok switch ===
[2026-05-12T23:30:12.7949643+00:00] Step E.D status=200
[2026-05-12T23:30:12.8005095+00:00] === SUMMARY ===
[2026-05-12T23:30:12.8026713+00:00] C(anth-ip)=ANTHROPIC_IP_FOUND D(gw-claude)=200 E(exit)=1 E.B(grok-profile)=True E.C(xai)=XAI_IP_FOUND E.D(gw-grok)=200 -> E_overall=False
```

## PASS criteria scorecard

| Criterion | Result |
|-----------|--------|
| INSTALLER_DONE=success | ✓ |
| Smoke: exit 0, 0 failures | ✗ (1 known false positive — does not affect actual install) |
| Bundled install.sh confirmed | ✓ |
| switch grok→claude exit 0 | **✗** (exit=1, 60s window timeout) |
| openclaw.json shows anthropic:default + auth.order.anthropic + model contains anthropic | ✓ |
| allowed-ips.txt contains anthropic IP | ✓ |
| Gateway 200 after claude switch | ✓ |
| switch claude→grok exit 0 + gateway 200 | **✗ on exit** (✓ on gateway 200) |
| chatCompletions NOT 404 | ✓ (400) |
| ClawChat present and launches | ✓ |
| Idle: both probes 200 | ✓ |

**Overall: FAIL** on switch-provider.ps1 exit codes. All other criteria PASS.

## Root cause analysis & follow-up

The bash gateway-health loop in `switch-provider.ps1` is:
```bash
for i in 1 2 3 ... 19 20; do
    if curl -fsS --max-time 5 http://127.0.0.1:8787/status >/dev/null 2>&1; then
        echo "[switch-provider] gateway healthy on attempt $i"
        exit 0
    fi
    sleep 3
done
echo "[switch-provider] WARNING: gateway did not respond within 60s after restart" >&2
exit 1
```

Two distinct issues observed:

1. **Step A 60s timeout** — the gateway took >60s to return 200 after restart on a fresh cold cycle. (In v1.0.23 it took ~16s. In v1.0.24 it took 60s+. Possibly more plugin runtime deps to stage on first restart, or warmup work taking longer. Worth measuring directly.)

2. **Step E early exit at 38s** — the script exited 1 before the 60s loop could complete, but all openclaw config writes clearly succeeded. The `2>/dev/null` on the curl redirects the curl errors, so it's unclear what triggered an early exit. Possible cause: `set -euo pipefail` catching an unexpected non-zero from `systemctl --user restart openclaw-gateway 2>&1 || true` (the `|| true` should protect, but maybe `set -o pipefail` interacts oddly with `2>&1`).

### Recommended fixes for v1.0.25

1. **Switch the gateway-health check from curl-only to systemctl-then-curl**, e.g.:
   ```bash
   systemctl --user restart openclaw-gateway
   # Wait for systemd to report active, then poll /status
   for i in $(seq 1 60); do
       if systemctl --user is-active --quiet openclaw-gateway && \
          curl -fsS --max-time 5 http://127.0.0.1:8787/status >/dev/null 2>&1; then
           echo "[switch-provider] gateway healthy on attempt $i"
           exit 0
       fi
       sleep 2
   done
   ```
   Longer total window (120s) and decoupled checks (service running ≠ /status responding).

2. **Audit the bash for `set -e` interactions** — particularly the systemctl line and any pipelines under `pipefail`. Consider running the bash with `set -uo pipefail` (drop `-e`) and explicit exit-code checks at the points that matter.

3. **(Optional) Separate the success path** — even on exit 1, the openclaw config writes have already happened. Print a clear "switch completed; gateway warmup may be ongoing" message so users don't think the whole switch failed.

The validation-script behavior also has artifacts unrelated to switch-provider: WSL automount disabled (intentional hardening) causes `wsl.exe` to print `wsl: Failed to translate '<windows-path>'` for every PATH entry. Caller pipelines using `*>&1` would convert those to PS error records and trip `$ErrorActionPreference='Stop'`. Avoided by not merging streams when invoking `switch-provider.ps1`.

## Cycle 2 (ClawAgent)

**SKIPPED** per "Only run Cycle 2 if Cycle 1 PASSES". Same reason as v1.0.5 prior cycle.
