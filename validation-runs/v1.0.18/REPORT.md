## ClawFactory v1.0.18 Azure Validation Report

- Timestamp (UTC): 2026-05-10T02:21:54Z (Phase A start) -> 03:30:40Z (INSTALLER_DONE=failure)
- Commit: 501821ae5fecaeaaed5fb07a6b0e32ca298c8479
- VM name: cfv-118
- VM size: Standard_D2s_v5
- Image: clawfactory-win11-baseline
- Public IP: 20.83.121.61
- Installer SHA-256 (uploaded): same bytes as `Output\ClawFactory-Secure-Setup.exe` (340,470,727 bytes downloaded on VM, matches local 324.7 MB on-disk)
- Preserved OS disk: `cfv-118_disk1_89637741e2dc48fe927ddbfaf090a56d` (state=Reserved)
- VM kept (deallocated, not deleted) per FAIL protocol

## Verdict: FAIL (upstream OpenClaw install.sh hash drift; not a v1.0.18 regression)

Failure occurred at **Step 8 [R2] Install-OpenClaw** in `setup.ps1:1280`. The OpenClaw install.sh fetched from `openclaw.ai/install.sh` did not match the pinned SHA-256, so [R2] correctly aborted the install. This is the [R2] safety guard working as designed — the v1.0.18 codebase did not introduce this failure; the upstream file changed between v1.0.17's PASS (2026-05-08) and v1.0.18's run (2026-05-10).

## Hash drift evidence

```
[wsl:root out] OpenClaw install.sh SHA-256: 85fab09263b74b260157f785dd64ba2115f404fc85b1bb5fb4ceb1e45b8132ff
[wsl:root out] !! SHA-256 mismatch. expected=57f025ba0272e2da3238984360e37fad5230bc7cea81854d154a362ea989d49d got=85fab09263b74b260157f785dd64ba2115f404fc85b1bb5fb4ceb1e45b8132ff
[wsl:root exit] 43
```

Independent verification fetched the file directly from openclaw.ai during the same VM session (not via the install path):

| | Value |
|---|---|
| Pinned in `setup.ps1` | `57f025ba0272e2da3238984360e37fad5230bc7cea81854d154a362ea989d49d` |
| Live `openclaw.ai/install.sh` (2026-05-10T03:32Z) | `85fab09263b74b260157f785dd64ba2115f404fc85b1bb5fb4ceb1e45b8132ff` |
| File size live | 92,380 bytes |
| Last validated PASS | v1.0.17, 2026-05-09T00:06Z, hash `57f025ba…d49d` |

## Phase A — Install download + RunOnce wiring

Phase A failed on the **first** restart due to a harness bug in `download-and-run.ps1`: it called `Out-File -LiteralPath C:\install\wrapper.log -Append` while `cmd.exe` was already redirecting `>> C:\install\wrapper.log 2>&1` from the parent wrapper. PowerShell's `Out-File` got `FileOpenFailure` from the file-lock conflict; installer never started. Confirmed in wrapper.log tail:

```
FullyQualifiedErrorId : FileOpenFailure,Microsoft.PowerShell.Commands.OutFileCommand
[wrapper] end Sun 05/10/2026  2:24:27.40 rc=1
```

Fixed inline: rewrote `download-and-run.ps1` to use `Write-Host` (cmd's redirect captures stdout/stderr cleanly without the script competing for the file). RunOnce + auto-logon re-armed; second restart at 2026-05-10T03:24:21Z.

This was a validation-harness bug, not a v1.0.18 issue. Worth carrying forward into the next harness invocation: cmd's `>> file 2>&1` and PS `Out-File file -Append` to the same path do not coexist.

## Phase A (retry) — install proceeded, then aborted at Step 8

```
attempt 1 / 45 : downloaded 340,470,727 bytes; install.log shows Step 1: Preflight checks. Selected provider: Grok (xAI).
attempt 2 / 45 : install.log latest line "[wsl:root exit] 0"  (Steps 2-7 progressing through WSL setup)
attempt 3 / 45 : MARKER_CONTENT=INSTALLER_DONE=failure reason=OpenClaw install blocked: SHA-256 mismatch. The install.sh on the server does not match the pinned hash.
```

Steps 1-7 completed without error: Preflight, EnsureWsl (no reboot needed, baseline image had WSL pre-enabled), ConfigureWslConf, RestartWsl, CreateClawUser, SetDefaultUser, InstallDocker, EgressFirewall (active backend: nftables, full provider=grok allowlist applied).

Step 8 failed clean. Silent-mode rollback default flipped to 'n' (per v1.0.13 fix) preserved forensics — no `wsl --unregister` ran.

```
[2026-05-10 03:30:40] [INFO] Silent mode: auto-answering 'Installation failed. Run automatic rollback? (y/N)' with default 'n'
```

INSTALLER_DONE marker written to both expected paths (`C:\install-result.txt` and `C:\ProgramData\ClawFactory\install-result.txt`) confirming the v1.0.12 INSTALLER_DONE-on-every-exit-path machinery is working.

## Tasks 4-7 (smoke, chatCompletions probe, ClawChat launch, idle): NOT RUN

Cycle blocked at install. Smoke test, /v1/chat/completions probe, ClawChat verification, and 5-minute idle test all skipped per FAIL-then-stop rule.

## Task 6 (ClawChat launch verification) — secondary observation

ClawChat.exe **was bundled correctly** by the installer's [Files] section. Step 8 (OpenClaw install) is the step that throws; the prior steps (Inno copy phase, Step 1 preflight, Steps 2-7) all completed, which means file extraction completed. ClawChat.exe would be at `C:\Program Files\ClawFactory\ClawChat.exe` on the preserved disk if needed for direct verification — though the install hadn't yet completed `Step-PostInstall` etc.

## Recommended next actions (out of validation scope, but blocking)

1. Fetch `https://openclaw.ai/install.sh`, manually review the diff vs. the version that hashed to `57f025ba…d49d`.
2. If the changes are acceptable, bump `$OpenClawInstallSha256` in **both** repos' `setup.ps1` to `85fab09263b74b260157f785dd64ba2115f404fc85b1bb5fb4ceb1e45b8132ff`.
3. Bump installer versions: ClawFactory 1.0.18 → 1.0.19, ClawAgent 1.0.1 → 1.0.2.
4. Re-run Azure validation cycle on both.

## Cleanup (FAIL verdict)

- VM cfv-118: deallocated (state=Reserved), not deleted
- OS disk `cfv-118_disk1_89637741e2dc48fe927ddbfaf090a56d`: preserved (state=Reserved)
- All other resources (NIC, NSG, public IP, vNET) untouched

## Cycle 2 (ClawAgent v1.0.1): SKIPPED

Per task spec ("Only run if Cycle 1 PASSES"). ClawAgent v1.0.1 pins the same OpenClaw install.sh SHA-256 (verified by inspection: `setup.ps1` line 48 = `57f025ba0272e2da3238984360e37fad5230bc7cea81854d154a362ea989d49d`), so it would fail with the identical error. A separate validation cycle should run for ClawAgent v1.0.2 once the hash is bumped.
