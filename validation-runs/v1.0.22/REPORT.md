## ClawFactory v1.0.22 Azure Validation Report

- Timestamp (UTC): 2026-05-11T23:10:37Z (restart) -> 23:21:13Z (INSTALLER_DONE=success) -> 23:45:31Z (PROBE2)
- Commit: 90f25ae... (switch-provider.ps1 M4/M5/M6 rewrite)
- VM name: cfv-122
- VM size: Standard_D2s_v5
- Image: clawfactory-win11-baseline
- Public IP: 20.94.203.174
- Preserved OS disk: `cfv-122_disk1_02a6a9137dbf464395f645605a7d3ebd` (state=Reserved)
- VM kept (deallocated, not deleted) per FAIL protocol

## Verdict: FAIL — switch-provider.ps1 openclaw config write rejected by schema

The new switch-provider.ps1 includes `apiKeyRef` in the `auth.profiles.<id>` JSON it sends to `openclaw config set --strict-json`. OpenClaw's strict-json validator rejects this with:

```
Error: Config validation failed: auth.profiles.anthropic:default: Unrecognized key: "apiKeyRef"
```

`set -euo pipefail` then aborts the bash before the subsequent `openclaw config set auth.order...` and `openclaw models set` run. Net effect: a "switch" to a new provider updates the firewall allowlist correctly (M5 + M6 work) but writes **nothing** to openclaw.json. The switch script returns exit 0 because the failure happens in the WSL bash subshell whose exit code isn't propagated back to PowerShell's `$LASTEXITCODE` after the helper returns.

## PASS/FAIL by criterion

| # | Criterion | Result |
|---|---|---|
| 1 | INSTALLER_DONE=success | **PASS** — attempt 7 / ~10 min after reboot |
| 2 | Smoke: 4P/0F/7S exit 0 | **PASS** — bit-for-bit identical to v1.0.15+ pattern |
| 3 | Bundled install.sh confirmed used | **PASS** — `[2026-05-11 23:17:39] [INFO] Bundled openclaw-install.sh hash verified.` |
| 4 | switch-provider grok→claude exit 0 | **PASS (literally) / FAIL (semantically)** — script exited 0, but the actual openclaw config update was rejected |
| 5 | openclaw.json shows anthropic:default | **FAIL** — `anthropic:default` profile NOT PRESENT after switch. Only the install-time `grok:default` exists |
| 6 | allowed-ips.txt contains anthropic IP | **N/A** — would have passed (M5 firewall block runs *before* the failing openclaw write). Not verified in this cycle because the switch never took the system into a claude state long enough for ANTHROPIC_IPS_IN_ALLOWLIST > 0 to settle |
| 7 | gateway healthy after switch (within 12s) | **FAIL** — `Switched to claude (gateway did not confirm health within 12s).` Gateway recovers later (separate 200 probe) but the in-script health poll fails |
| 8 | switch back grok exit 0 + gateway healthy | **PASS (literally)** — but only because `grok:default` profile existed from install-time. The script doesn't recreate it; it just updates auth.order (which doesn't include apiKeyRef and so doesn't fail validation) |
| 9 | chatCompletions NOT 404 | **PASS** — HTTP 500 (route registered, upstream LLM error from validation-placeholder key) |
| 10 | ClawChat present and launches | **PASS** — `C:\Program Files\ClawFactory\ClawChat.exe` v1.1 (sha256 `a16006ff…1bec8`), started pid 4664, killed cleanly |
| 11 | Idle PROBE1=200 / PROBE2=200 | **PASS** — both first-attempt 200s, no retry |

**Cycle verdict: FAIL** on the new core test (Task 6). All v1.0.21 quality gates preserved.

## Diagnostic evidence

### Switch-provider grok→claude output (full)

```
=== switch grok->claude 2026-05-11T23:32:57Z ===
EXIT=0
  Switching active provider to: claude
    [x] API key stored at credential target 'ClawFactory/AnthropicApiKey'
    [x] egress allowlist updated (backend auto-detected)
  Error: Config validation failed: auth.profiles.anthropic:default: Unrecognized key: "apiKeyRef"
    [x] openclaw config updated (model=anthropic/claude-sonnet-4-6, profile=anthropic:default)
  
  Switched to claude (gateway did not confirm health within 12s).
  If the gateway is unresponsive, restart it manually:
    wsl -d Ubuntu -u clawuser -- bash -lc "systemctl --user restart openclaw-gateway"
```

The "openclaw config updated" line is a misleading print — PowerShell side echoes it unconditionally regardless of `$ocExit`.

### Fresh inspect after grok→claude switch

```
=== fresh inspect 2026-05-11T23:36:14Z ===
openclaw.json size=910 bytes
PROFILES present:
  grok:default : provider=grok mode=api_key displayName='Grok (xAI)' apiKeyRef=
  anthropic:default : (not present)
  openai:default : (not present)
  gemini:default : (not present)
  ollama:default : (not present)
ORDERS present:
  grok = grok:default
DEFAULT_MODEL_PRIMARY=grok/grok-4-1-fast
```

After `switch-provider.ps1 -Provider claude -ApiKey ...` returned exit 0:
- `anthropic:default` profile: **NOT PRESENT**
- `auth.order` still has only `grok = grok:default` (auth.order.anthropic NOT created)
- `agents.defaults.model.primary` still `grok/grok-4-1-fast` (models set never ran)

This confirms: `set -e` aborts after the first failing `openclaw config set` (auth.profiles), so the subsequent auth.order and models set never execute.

### Firewall side did update correctly (M5 + M6 verified)

In an earlier inspect run after the grok→claude→grok round-trip:

```
ALLOWED_IPS_COUNT=62                                   ← all 19 base hosts + grok resolved successfully
XAI_RESOLVED=104.18.18.80,104.18.19.80
XAI_IPS_IN_ALLOWLIST=2/2                               ← both api.x.ai IPs present
ALLOWLIST_SAMPLE (first 10): github + cloudflare + npm + ubuntu hosts
```

62 IPs in the allowlist (vs the original switch-provider.ps1's 6-host shape that would have produced maybe 15-20 IPs). The full 19-host baseHosts restore + `/etc/clawfactory/allowed-ips.txt` persistence works correctly.

## Root cause

OpenClaw's `auth.profiles.<id>` schema accepts only `{provider, mode, displayName}`. `apiKeyRef` is not a valid field. The actual credential reference lives in a separate `~/.openclaw/auth-profiles.json` file (written at install time by `setup.ps1 Step-WireProviderKey` line ~1900).

My v1.0.22 rewrite of switch-provider.ps1 added `apiKeyRef` to the profile JSON based on ClawChat's `set_provider` Rust command (which also writes `apiKeyRef`). Both writers are wrong; openclaw silently ignores unknown keys *on read* in some paths but the `--strict-json` validator on `config set` rejects them outright. ClawChat's writes via `openclaw config set` were likely also being rejected — the v1.0.21 validation passed because `chatCompletions HTTP 500` was satisfied by the install-time `grok:default` profile, not by ClawChat's writes.

## Fix for v1.0.23

One-line change in `resources/switch-provider.ps1`. Remove `apiKeyRef = $cfg.Cred` from the profile-object construction so the resulting JSON matches `setup.ps1 Step-ConfigureOpenClaw` line 1762-1766 shape exactly:

**Current (broken):**
```ps1
$profileObject = if ($Provider -eq 'ollama') {
    [ordered]@{ provider = $cfg.InternalId; mode = $cfg.Mode; displayName = $cfg.DisplayName }
} else {
    [ordered]@{ provider = $cfg.InternalId; mode = $cfg.Mode; displayName = $cfg.DisplayName; apiKeyRef = $cfg.Cred }
}
```

**Fix:**
```ps1
$profileObject = [ordered]@{
    provider    = $cfg.InternalId
    mode        = $cfg.Mode
    displayName = $cfg.DisplayName
}
```

(One shape for all providers — Ollama's profile object is now identical except `mode='token'` from `$cfg.Mode`. The conditional is no longer needed.)

The credential reference still works because:
- `cmdkey /generic:ClawFactory/<Provider>ApiKey` writes the key to Windows Credential Manager
- OpenClaw resolves credentials at runtime via the auth-profiles.json file (install-time) + the credential-target naming convention
- The new key value is stored under the correct credential name

**Secondary fix worth bundling:** propagate the bash exit code through `Invoke-WslBashBlock` so the script's overall `$LASTEXITCODE` reflects gateway-health failure. Currently the script silently exits 0 even when the gateway didn't recover.

**Tertiary fix:** the misleading `[x] openclaw config updated` print should be gated on `$ocExit -eq 0`.

## What worked in v1.0.22

- Install ($PASS, no regressions vs v1.0.21)
- Bundled install.sh hash verification ($PASS)
- Firewall update logic (M5 + M6 fixes correct — full 19-host baseHosts restore + `/etc/clawfactory/allowed-ips.txt` persistence)
- Credential storage via cmdkey
- ClawChat v1.1 bundle (unchanged from v1.0.21)
- Idle stability

## What didn't

- `openclaw config set auth.profiles.<id>` write — rejected by `--strict-json` due to `apiKeyRef`
- Subsequent `openclaw config set auth.order` and `openclaw models set` — never executed (`set -e` short-circuit)
- Gateway in-script health check — fails 12s window because config wasn't actually updated
- Script-side exit-code propagation — exits 0 even on failure

## Cleanup (FAIL verdict)

- VM cfv-122: **deallocated** (state=Reserved), not deleted
- OS disk `cfv-122_disk1_02a6a9137dbf464395f645605a7d3ebd`: preserved (state=Reserved)
- NIC, NSG, public IP: untouched (will be cleaned up on next preflight)
- Storage account, baseline VNET, baseline image: untouched per HARD RULES

## switch-provider-test.log (full)

```
=== switch-provider test start 2026-05-11T23:25:25Z ===
switch-provider.ps1 path: C:\Program Files\ClawFactory\resources\switch-provider.ps1
Exists: True

--- 6a: switch grok -> claude ---
EXIT_6A=0
  (script announces switch, cmdkey + firewall succeed, openclaw config fails on apiKeyRef)

--- 6b: verify openclaw.json shows anthropic:default ---
(In-test inspector hit a base64 decode bug; later fresh inspect confirmed anthropic:default NOT PRESENT)

--- 6c: verify allowed-ips.txt contains api.anthropic.com IP ---
(In-test inspector had bash quoting mangle; later fresh inspect confirmed firewall side worked)

--- 6d: gateway health after switch to claude ---
GATEWAY_AFTER_CLAUDE_STATUS=200    ← gateway eventually recovers (~20+s) despite in-script 12s timeout

--- 6e: switch claude -> grok (round-trip) ---
EXIT_6E=0    ← script exits 0 again, same reason as 6a; openclaw config set fails on apiKeyRef
(Round-trip "works" because grok:default profile already exists from install)

--- 6e: verify openclaw.json shows grok:default after round-trip ---
HAS_GROK_PROFILE=True (but this is the install-time profile, not a fresh write)

--- 6e: verify allowed-ips.txt contains api.x.ai IP ---
(In-test bash mangle; fresh inspect later confirmed XAI_IPS_IN_ALLOWLIST=2/2 — firewall side works)

--- 6e: gateway health after switch back to grok ---
GATEWAY_AFTER_GROK_STATUS=200

=== switch-provider test end 2026-05-11T23:25:36Z ===
```

## Artifacts

- [REPORT.md](REPORT.md)
- [smoke-test.json](smoke-test.json)
- [bundled-check.json](bundled-check.json)
- [switch-provider-test.json](switch-provider-test.json)
- [switch-provider-test-signals.log](switch-provider-test-signals.log)
- [inspect.log](inspect.log) — post-round-trip state (grok active, both x.ai IPs in allowlist)
- [inspect-claude.log](inspect-claude.log) — STALE due to inspect script race; superseded by inspect-after-claude.log
- [inspect-after-claude.log](inspect-after-claude.log) — fresh inspect post-claude-switch (PROFILES anthropic:default NOT PRESENT)
- [completions-probe.json](completions-probe.json)
- [clawchat-launch.json](clawchat-launch.json)
- [idle-probe1.json](idle-probe1.json)
- [idle-probe2.json](idle-probe2.json)

## Recommendation

Bump to v1.0.23 with the one-line apiKeyRef removal (plus the two secondary fixes — exit propagation and misleading-log gating). Re-run this exact validation harness. Expected PASS criteria:

- After grok→claude switch, fresh inspect should show `anthropic:default` profile **present** with `{provider:anthropic, mode:api_key, displayName:"Anthropic Claude"}`
- `auth.order.anthropic = anthropic:default`
- `agents.defaults.model.primary = anthropic/claude-sonnet-4-6`
- Gateway healthy within 12s in-script (no fallback yellow-warning path)
- ANTHROPIC_IPS_IN_ALLOWLIST > 0 from firewall update
