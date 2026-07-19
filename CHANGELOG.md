# Changelog

All notable changes to ClawFactory are documented here.

Format: [Keep a Changelog](https://keepachangelog.com/en/1.0.0/). This project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [1.0.46] - 2026-07-19

### Added

- **In-installer API Key Wizard (interactive installs only).** A non-technical buyer can now go from purchase to a working agent without guessing where to get a key or touching a terminal:
  - A new **"Get your <Provider> API key"** guidance page walks the user through obtaining a key in plain numbered steps, with a button that opens the correct provider console, the exact key prefix to expect (e.g. `sk-ant-`), a plain statement that the key is theirs / bills to their own provider account / is never sent anywhere except to that provider, and a calibrated note about the configurable gateway-path spend cap (not overstated — see `SECURITY.md`).
  - The key-entry page gains a **show/hide toggle**, **paste trimming** (strips the trailing newline that is the most common failure), **provider-specific format validation** with a named error, and an **optional live authentication check** (a free, no-token model-list call) that never blocks the install — any network/timeout/rate-limit offers "continue anyway", and even a rejected key can be forced through.
  - Deferral ("I'll add my API key later") completes the install cleanly and points to the Start-Menu **Switch AI Provider** helper rather than a terminal command.
- The key is still stored only through the existing mechanism (Windows Credential Manager → `Step-WireProviderKey`); it is never written to the install log, the Inno log, or a temp file.

### Unchanged (verified)

- `/SILENT` behavior is untouched: the wizard never displays, the key is read from Credential Manager exactly as before, and the `/PROVIDER=`, `/LICENSE=`, and credential-target contracts the Azure validation harness depends on are unchanged.

## [1.0.37] - 2026-06-30

### Fixed

- Final gateway health gate now polls in-WSL via `Invoke-WslBash` (mirroring the pre-install gate) instead of a Windows-side `Invoke-WebRequest`. The old poll held no WSL session open, so the distro shut down mid-gate (WSL's last-session-exit teardown) and the gateway was killed before it could respond. First build to pass a full install -> smoke -> 5-minute idle -> chatCompletions -> uninstall cycle in a single Azure validation run (cfv-137).

## [1.0.36] - 2026-06-29

### Changed

- Widened the final gateway health gate to ~120 s. Necessary but not sufficient; 1.0.37 identified the real cause as WSL session teardown, not timing.

## [1.0.35] - 2026-06-23

### Changed

- Widened the pre-install gateway health gate to >= 120 s to cover the gateway's cold-start time on 2-vCPU machines. Proved the pre-install gate passes end-to-end for the first time.

## [1.0.34] - 2026-06-11

### Fixed

- Install-time crash "Cannot call UninstallSilent function during Setup." The uninstaller is now invoked from `CurUninstallStepChanged(usUninstall)` instead of an `[UninstallRun]` `{code:}` constant, which Inno evaluates at install time. See `ClawFactory_Install_Lessons_Learned.md` L1.
- Smoke check for the nftables `clawfactory` chain now runs as root.

## [1.0.33] - 2026-06-10

### Added

- Complete uninstaller: 9-step reversal (stop gateway + terminate WSL, unregister scheduled tasks, remove firewall rule, remove DPAPI credentials, revert `.wslconfig`, unregister the Ubuntu distro, license deactivation, remove `HKLM\SOFTWARE\ClawFactory`, remove `ProgramData\ClawFactory`).
- Hidden `ClawFactory WSL Host` keep-alive scheduled task so the gateway survives idle.

## [1.0.32] - 2026-06-10

### Fixed

- Resume flag missing at the second reboot path.

## [1.0.30] - 2026-05-23

### Added

- License-key wizard page and activation gate.

## [1.0.29] - 2026-05-22

### Added

- Post-install smoke scheduled task and WSL console-window suppression during install.

## [1.0.28] - 2026-05-21

### Added

- `wsl --update` preflight and resume-flag hardening. First Azure-validated install of the reboot-and-resume path.

## [1.0.26 - 1.0.27] - 2026-05-21

### Added

- `/PROVIDER` silent flag for headless validation.

### Changed

- Replaced the RunOnce mechanism with a scheduled task for headless reboot-resume.

## [1.0.22 - 1.0.24] - 2026-05

### Changed

- Iterated the gateway health-poll window (12 s -> 60 s) while diagnosing cold-start timing on loaded 2-vCPU VMs. Fully resolved in 1.0.35 - 1.0.37.

## [1.0.21] - 2026-05-11

### Changed

- Bundled ClawChat upgraded to v1.1: settings tab, provider switching, gateway auto-start on launch.

## [1.0.20] - 2026-05-10

### Security

- Bundle `openclaw-install.sh` into the installer, SHA-256-verified on Windows before use. Removes the upstream-URL hash-drift attack surface entirely (previously `openclaw.ai/install.sh` tracked "latest" and changed under us).

## [1.0.18] - 2026-05-09

### Added

- Bundled ClawChat desktop app (Tauri + React) into both installers as `resources\ClawChat.exe`; desktop and Start Menu shortcuts launch it directly.

---

## [1.0.17] — 2026-05-08

### Fixed

- `/v1/chat/completions` returned HTTP 404 on every install since v1.0.1 — the chatCompletions route was never registered. v1.0.16 attempted to fix this with `--strict-json` but the patch did not work; live VM investigation pinned three independent issues, all resolved here:
  1. The boolean-writing flag is `--json`, not `--strict-json`. Replaced at three sites (`gateway.port` x2, `plugins.entries.bonjour.enabled`, `gateway.http.endpoints.chatCompletions.enabled`).
  2. openclaw caches gateway config at startup. Added `systemctl --user restart openclaw-gateway` + `/status` health poll inside the new `$script9b` so the route is registered before the install completes.
  3. `Step-EnableChatCompletions`'s `Start-Process -FilePath wsl.exe` direct call returned exit 1 with no openclaw stdout under the wrapper.cmd auto-logon context. Refactored to use `Invoke-WslBash` (the proven base64-script transport that `$script8c` / `$script9a` use), which works reliably in the same install context.

## [1.0.16] — 2026-05-08

### Fixed (attempt — superseded by v1.0.17)

- Tried to fix the v1.0.1+ chatCompletions=404 bug by adding `--strict-json` to four `openclaw config set` calls. The Azure validation cycle on commit `14b0001` showed install completed and smoke passed, but the chatCompletions probe still returned HTTP 404 and the openclaw.json had no `chatCompletions.enabled` key. The fix was incorrect on multiple counts; v1.0.17 supersedes it. See `validation-runs/v1.0.16-20260508-165245/REPORT.md` for the live-VM diagnosis that drove v1.0.17.

## [1.0.15] — 2026-05-08

### Fixed

- `smoke-test.ps1` produced 7 false-failures when invoked via `az vm run-command`, which runs scripts as `NT AUTHORITY\SYSTEM`. WSL refuses to run as LocalSystem (`WSL_E_LOCAL_SYSTEM_NOT_SUPPORTED`), so every `wsl ... bash -lc ...` call returned an error string instead of expected output. Added SYSTEM-context detection; WSL-dependent checks now SKIP cleanly under SYSTEM rather than failing.
- An `[int]$result -ge 4` cast in smoke-test crashed with "Cannot convert Object[] to Int32" when wsl returned multi-line error text. Replaced with defensive regex parse.

### Added

- `smoke-test.ps1` is now bundled in the installer at `{app}\resources\smoke-test.ps1` (was previously not shipped).

## [1.0.14] — 2026-05-07

### Fixed

- `Test-WslFunctional` always returned false on fresh installs because `Invoke-WslExe` decoded `wsl.exe`'s UTF-16-LE output as CP1252, leaving embedded NULs that blocked `Trim` from removing the trailing `\r`. Set explicit Unicode encoding for wsl.exe-native output paths.
- `Invoke-WithRollback` crashed with "the property 'Count' cannot be found" under StrictMode 3 when only one checkpoint had been saved, because PowerShell 5.1 unrolls single-element array returns to scalar strings. Wrapped the call sites in `@(...)` to force array context.

## [1.0.13] — 2026-05-07

### Changed

- Bumped `OpenClawNpmVersion` pin from `2026.4.23` to `2026.4.27`. The 2026.4.23 release had a known bonjour mDNS crash loop that wedged the gateway event loop after systemd reported the unit active; 2026.4.27 fixes it (issues #72355, #64928).

### Fixed

- Silent-mode auto-rollback default flipped from `'y'` to `'n'`. A failed silent install was wiping its own forensics by auto-unregistering the WSL distro before logs could be collected.
- `/tmp/openclaw-install.log` is now pre-created with `chown clawuser:clawuser` AND `chmod 0666` (was chown only). Defends against an internal `sudo'd tee` re-creating the file as root.
- `$InstallerVersion` constant in `setup.ps1` was stale at `1.0.4`; now matches the release version.

## [1.0.12] — 2026-05-07

### Added

- New `Confirm-Or-Default` helper gating every interactive primitive on a `$Silent` flag. The `$Silent` switch is propagated from Inno's `WizardSilent()` via the `.iss` `[Run]` block, so `/SILENT` installs no longer hang on `Read-Host` or `MessageBox.Show`.
- New `Invoke-WslExe` helper for direct `wsl.exe` calls, paired with the existing `Invoke-WslBash` for bash-via-wsl.
- Top-level `try/catch/finally` in `setup.ps1` writes `INSTALLER_DONE=success` or `INSTALLER_DONE=failure reason=<msg>` to `install.log`, `C:\install-result.txt`, and `C:\ProgramData\ClawFactory\install-result.txt` on every exit path. The Azure validation harness was previously treating all clean failures as TIMEOUT because no marker was emitted.
- Gateway-failure path now collects `journalctl --user -u openclaw-gateway`, `systemctl status`, and `ss -tlnp` before throwing, so post-mortem has the data it needs.

### Fixed

- `timeout 300` added to all `Step-InstallDocker` apt-get calls; `timeout 1800` on `ollama pull`. Previous lack of timeouts could hang silent installs indefinitely.
- Ten more `& wsl.exe ... 2>&1` calls (in `Test-WslFunctional`, `Install-WslDistroWithFallback`, `Step-ConfigureWslConfig`, and rollback `--unregister`) converted to use `Invoke-WslExe`. PowerShell 5.1's `2>&1` interaction wraps native stderr as terminating ErrorRecords under `$ErrorActionPreference = 'Stop'`.

## [1.0.11] — 2026-05-07

### Fixed

- `nft` token corrupted to `ft` again — a different mechanism this time (a backtick inside a PowerShell here-string ate the leading `n`). Rewrote the affected lines so `nft` is never adjacent to a backtick.
- `tee -a /tmp/openclaw-install.log` failing with permission denied on rootfs that ships `/tmp` mode 0755 root:root. Added `chmod 1777 /tmp && chmod 1777 /var/tmp` immediately after WSL distro import.

## [1.0.10] — 2026-05-07

### Fixed

- Non-ASCII characters (em-dash, arrow, multiplication sign) in `setup.ps1` caused PS 5.1 parse-time terminating errors. Without a UTF-8 BOM, PS 5.1 reads `.ps1` files as Windows-1252 and the multi-byte UTF-8 sequences decode as garbage tokens. Replaced every non-ASCII byte; added a pre-build scan that fails the build on any byte > 0x7F.

## [1.0.9] — 2026-05-07

### Fixed

- `Step-EnsureWsl` exit-code routing was wrong: `wsl --install` exit 1 ("elevation required, reboot pending") was being caught by `Invoke-WithRollback` as a fatal failure instead of routing to the RunOnce + reboot path. Reworked the branches so any non-zero from `wsl --install` (including the documented exit 1) routes to reboot-and-resume; only genuine install failures throw.

## [1.0.8] — 2026-05-07

### Fixed

- Three `& wsl.exe ... 2>&1` calls in `Step-EnsureWsl` were turning native-command stderr into `ErrorRecord`s under `$ErrorActionPreference = 'Stop'`, throwing on harmless WSL warnings before the exit code could be checked. The reboot-and-resume code from v1.0.6 had been unreachable as a result. Replaced all three with `[System.Diagnostics.Process]::Start($psi)` invocations that capture stdout/stderr separately.

## [1.0.7] — 2026-05-06

### Fixed

- `iptables` was missing from `Step-PreInstallOpenClawDeps` — required for nftables fallback (`iptables-legacy`) on kernels that don't expose nft hooks. Added it to the build-deps list.
- 60-second `apt-get` timeout was too tight on slow mirrors. Extended to 300 seconds.

## [1.0.6] — 2026-05-06

### Added

- RunOnce registry key + `Restart-Computer -Force` in `Step-EnsureWsl` so fresh Win11 VMs without WSL features pre-enabled reboot, auto-log back in, and continue from the same install step. Note: this code path was unreachable on real first-install hardware until v1.0.8 (exit-code routing) and v1.0.9 (elevation-exit) fixed the surrounding flow.

## [1.0.5] — 2026-05-06

### Fixed

- Inno wizard pages (API key, Ack, Provider) prompted the user even when `/SILENT` was passed — silent installs blocked on what was supposed to be wizard UI. Added `WizardSilent()` bypass to all three pages.

## [1.0.4] — 2026-05-04

### Added

- New `Step-PreInstallOpenClawDeps` runs `apt-get install -y --no-install-recommends make g++ cmake python3` BEFORE `Step-EgressFirewall`, so `install.sh` finds the build tools already present and skips its own apt phase. Eliminates a 15-minute timeout that was firing on laptops with slow apt mirrors. `nodejs` is intentionally excluded — install.sh owns NodeSource setup.

## [1.0.3] — 2026-05-04

### Fixed

- Egress firewall never activated on any install. `nft` was being mangled to `ft` at runtime somewhere in the PowerShell -> base64 -> bash transport chain. Rewrote `Step-EgressFirewall` to use full path `/usr/sbin/nft` throughout the embedded script; added an assertion guard that throws if the literal `/usr/sbin/nft` token is missing before transport.
- `Step-EgressFirewall` always saved its checkpoint, even on exit 127 from the mangled `nft` call, so every install since v1.0.0 marked the firewall as installed when it had never run. Exit non-zero now logs ERROR and returns from the function before `Save-Checkpoint`; `-Resume` re-runs will retry the firewall step.
- `Step-InstallOpenClaw` error strings claimed "5 minutes" timeout when the actual `timeout` argument was 900s (15 min). Updated all three stale strings and replaced the canned blame on `openclaw-onboard` with a list of real candidate causes.

### Added

- Egress firewall allowlist now includes Ubuntu apt mirrors (`archive.ubuntu.com`, `security.ubuntu.com`, `ports.ubuntu.com`, `esm.ubuntu.com`, `ppa.launchpad.net`) as defense-in-depth.

## [1.0.2] — 2026-05-04

### Added

- New `Step-RegisterWslHostTask` registers a hidden Windows scheduled task that runs `wsl.exe -d Ubuntu -u clawuser -- sleep infinity` at user logon, holding one session alive permanently. Prevents the wsl.exe last-session-exit trigger from firing a full systemd shutdown inside the distro (which would tear down `user@1000`, docker, containerd, and the gateway regardless of linger or `vmIdleTimeout` settings).

### Changed

- Moved `Step-EnableChatCompletions` to run AFTER `Step-PreinstallGatewayRuntime`. `openclaw config set` requires the runtime to be present; previously it was printing `--help` instead of writing config.

## [1.0.1] — 2026-05-04

### Added

- New `Step-ConfigureWslConfig` writes `[wsl2] vmIdleTimeout=-1` into `%USERPROFILE%\.wslconfig` (creates or merges) so the WSL VM stays alive while Windows is up. Fixes the gateway flapping every 60-180s on idle (WSL2's default `vmIdleTimeout` is 60000 ms).
- New `Step-EnableChatCompletions` enables `gateway.http.endpoints.chatCompletions.enabled` for the future native chat app. (Note: the underlying `openclaw config set` call was missing `--strict-json` until v1.0.16, so this flag was silently dropped on every install in the v1.0.1 -> v1.0.15 range.)

## [1.0.0] — 2026-05-03

### Added

- Initial release. 7/7 smoke test passing on real hardware.
- Bundled Ubuntu rootfs (~341 MB) for offline install via `wsl --import`, with `wsl --install` (network) as fallback.
- OpenClaw version pin to `2026.4.27` passed via `OPENCLAW_VERSION` env var to `install.sh`.
- Health-poll on gateway install: Step 8b polls `http://127.0.0.1:8787/status` for up to 60s after `openclaw gateway install --force` returns. The HTTP probe is the source of truth, not the install command's exit code.
- `smoke-test.ps1` health check (7 checks, exit 0 only on full pass).
- Defense-in-depth bonjour disable via systemd drop-in setting `OPENCLAW_DISABLE_BONJOUR=1`.
- Per-agent `auth-profiles.json` fan-out in `bootstrap.ps1` (5 agents: main, orchestrator, publisher, skill-builder, skill-scout) at mode 600.

### Fixed

- CR line-ending corruption in `Invoke-WslBash` (CRLF in PowerShell here-strings turned `set -e` into `set -e\r` after base64 decode in bash). All three call sites now strip CRLF -> LF before encoding.
- Gateway config order: `openclaw config set gateway.{mode,bind,port}` now runs BEFORE `openclaw gateway install --force`. The install command starts the service immediately and the service exits 78/CONFIG if `gateway.mode` isn't already set.
- Tee-pipe trapping the install command's success exit code as tee's permission-denied failure. Dropped the `tee` from Step 8b's gateway-install line; output captured via `Invoke-WslBash`'s stdout routing.
- `openclaw gateway install --force` exit 1 is now WARN-only; only a non-responsive gateway after the 60s `/status` poll throws.
- `openclaw doctor` blocking on interactive prompts. Added `--non-interactive --no-workspace-suggestions`.
- `post-install.ps1` aborting on first stderr line under `$ErrorActionPreference = 'Stop'`. Refactored four sites to use `Process.Start`-based `Invoke-WslBash`.
