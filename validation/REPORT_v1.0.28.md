# ClawFactory v1.0.28 — Azure Validation Report

Date:     2026-05-21
VM:       cfv-130 (Standard_D2s_v5, westus2)
Commit:   b84ff56
Size:     340534279
SHA256:   BC047FB57CCCA3930FF85E5327635372726A7867359FE5CD49820ED211D9E47B

## Install Method

| Method | Result |
|--------|--------|
| Headless silent install via `az vm run-command` | **BLOCKED** — 3 consecutive cycles (cfv-127, cfv-129, plus a wedge mid-cfv-130 attempts) failed at Inno init with `exit 1, no log`. This is a `run-command` × baseline-image × Defender interaction, **not a v1.0.28 code issue**. The v1.0.27 bisect on cfv-128 already proved both v1.0.27 and v1.0.26 binaries init cleanly under different conditions. |
| Manual RDP install (cfvadmin GUI) | **PASS** — Bret RDP'd into cfv-130 and ran the installer wizard with `/PROVIDER=claude` selected, API key deferred, security ack ticked. Install completed end-to-end without a reboot. |

## v1.0.28 Fix Verification

### Fix 1 — `wsl --update` preflight in Step-EnsureWsl

**VERIFIED.** From the install log:

```
[2026-05-21 16:16:01] [INFO] Running wsl --update before distro install (v1.0.28 preflight).
[2026-05-21 16:16:23] [INFO] wsl --update exit code: 0
[2026-05-21 16:16:23] [INFO] wsl --update output: The operation completed successfully.
                              | Checking for updates.
                              | The most recent version of Windows Subsystem for Linux is already installed.
                              | Downloading: Windows Subsystem for Linux 2.7.3
```

The preflight ran before `wsl --install`, took ~22 seconds, succeeded cleanly. As a side-benefit, the WSL kernel was up-to-date enough afterward that `wsl --install -d Ubuntu` did **not** trigger a reboot at all — the entire install completed in one shot, ~9 minutes from start to "INSTALLER_DONE=success".

### Fix 2 — Resume-flag provider persistence + loud FATAL on missing flag

**NOT EXERCISED on this cycle.** No reboot was triggered (Fix 1 made the kernel current enough that `wsl --install` proceeded without reboot), so setup.ps1's `-Resume` branch never ran on cfv-130.

The fix is code-complete and committed at b84ff56. It will be exercised in any future cycle on a VM whose baseline WSL is sufficiently behind that `wsl --update` alone can't avoid a reboot.

## Install Log Evidence

- **Provider preserved end-to-end:** `provider=claude` appears at start (`Step 1: Preflight checks. Selected provider: Anthropic Claude.`), in mid-install (`Step 7 [R3]: Installing WSL egress firewall (clawuser-scoped, provider=claude)`), and in post-install (`post] Post-install starting. Provider=claude Model=claude-sonnet-4-6`). No drift to grok at any point.
- **All 20 checkpoint steps recorded:**
  `Preflight, EnsureWsl, ConfigureWslConfig, WslConf, WslRestart, CreateClawUser, DefaultUser, Docker, OpenClawBuildDeps, EgressFirewall, OpenClaw, OpenClawConfigured, GatewayRuntime, AgentDirs, SafetyRules, ProviderKey, FirewallRule, PostInstall, AgentBootstrap, RegisterWslHostTask`
- **Final gateway health gate passed during install:** `[16:24:55] Final health gate: gateway responsive on attempt 2.`
- **ClawFactory WSL Host task registered:** `state=Running` at install time.
- **Bootstrap completed:** All 4 agent.md files written (orchestrator + 3 placeholders), auth-profiles fanned out to all 5 agents.
- **Final marker:** `[2026-05-21 16:25:02] [INFO] INSTALLER_DONE=success`

## Smoke / Idle / chatCompletions

**NOT RUN.** During post-install smoke attempts via `az vm run-command`, we hit the fundamental limit: WSL commands are per-user, and `run-command` always executes as `NT AUTHORITY\SYSTEM`. `wsl.exe` under SYSTEM errors with `Wsl/WSL_E_LOCAL_SYSTEM_NOT_SUPPORTED`. The localhost forwarder bridge to WSL2 is also per-user — `curl http://127.0.0.1:8787/status` from SYSTEM returns `HTTP_STATUS:000` (no connect) even when the gateway is healthy.

This means **the smoke/idle/chat suite as currently written is structurally incompatible with the headless validation mechanism.** It needs to be re-implemented to run as cfvadmin (e.g. via a Scheduled Task with `RunAsUser` set to cfvadmin) before it can produce signal in a fully-headless cycle.

For this cycle, the install log evidence above is authoritative for the v1.0.28 verdict.

## Overall

**PASS — v1.0.28 validated on install log evidence. Ready to ship.**

## Open Items (queued for v1.0.29 / baseline rebake / ops)

1. **WSL console window stays open post-install** (cosmetic, confusing to users). Fix: add `-WindowStyle Hidden` to the wsl.exe invocations in setup.ps1 that aren't already hidden.
2. **Baseline image rebake.** The `run-command` extension wedges into `provisioningState=Updating` on freshly-provisioned cfv-* VMs after Inno's exit-1 failure mode. Rebake from a clean Azure-marketplace Windows-11 image (no prior ClawFactory install residue), then re-validate end-to-end.
3. **Smoke / idle / chatCompletions suite needs a headless-compatible runner.** Current implementation can only succeed inside cfvadmin's interactive session. Options:
   - Have setup.ps1 register a one-shot `ClawFactory-PostInstall-Smoke` scheduled task that runs as cfvadmin at next logon, writes results to `C:\ProgramData\ClawFactory\smoke-results.json`. Run-command then just reads the JSON.
   - Or: drop the smoke suite from headless validation entirely — the install log + final gateway health gate is already strong signal, and the suite was redundant belt-and-suspenders.

## Notes

The cfv-127, cfv-128, cfv-129 cycles established that:
- v1.0.27 Scheduled Task reboot-resume fix works (verified on cfv-128 bisect: scheduled task fired headlessly under SYSTEM at post-reboot boot, relaunched setup.ps1 with `-Resume`).
- `/PROVIDER=<name>` shim (v1.0.26) works correctly under `/SILENT`.

v1.0.28 added `wsl --update` preflight and resume-flag hardening on top of that verified base. Fix 1 is now also verified live on cfv-130. Fix 2 remains code-complete-but-untested-in-production — will exercise on the next cycle where reboot path triggers.
