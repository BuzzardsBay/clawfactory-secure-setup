## SHIP STATUS: v1.0.21 / v1.0.4 — 2026-05-11 — STABLE (ClawChat v1.1 bundled, Azure validated)

**Current heads:** ClawFactory v1.0.21 ([2997bdf](https://github.com/BuzzardsBay/clawfactory-secure-setup/commit/2997bdf)) + ClawAgent v1.0.4 ([278e2e0](https://github.com/BuzzardsBay/clawagent-setup/commit/278e2e0)). Both Azure-validated on cfv-121 / cfa-104 (Cycle 1+2 PASS, 2026-05-11): INSTALLER_DONE=success, smoke 4P/0F/7S, chatCompletions HTTP 500 (route registered), ClawChat v1.1 launches under clawadmin, idle 200/200. v1.0.21 / v1.0.4 swap the bundled ClawChat.exe from v1.0.0 (10.88 MB) to v1.1 (11.16 MB, sha256 `a16006ff…1bec8`) — adds settings tab with provider switching, security tier selector, gateway auto-start on launch (C1 fix). Underlying install machinery unchanged from v1.0.20 / v1.0.3: bundled `openclaw-install.sh` hash-pinned at install time, no upstream URL drift surface.

---

## Current state (May 2026)

| Product | Repo | Version | Price | Status |
|---------|------|---------|-------|--------|
| ClawFactory-Secure-Setup.exe | clawfactory-secure-setup | v1.0.20 | $149 | STABLE — Azure validated |
| ClawAgent-Setup.exe | clawagent-setup | v1.0.3 | $49 | STABLE — Azure validated |
| ClawChat.exe | ClawChat (`C:\Users\bmcki\ClawChat\`) | v1.0.0 | bundled | STABLE — bundled in both installers |

**Website:** https://clawfactory.app
**Support email:** support@clawfactory.app

---

## Resolved bugs (v1.0.0 ship cycle + v1.0.1 → v1.0.15 patches)

| Bug | Resolved in | Commit |
|---|---|---|
| Gateway restart loop on first install (exit code 1 from `openclaw gateway install --force` aborted Step 8b before the gateway actually came up healthy) | Step 8b now polls `/status` for 60 s after install; non-zero exit is WARN, only a non-responsive gateway throws | [`cf38a65`](https://github.com/BuzzardsBay/clawfactory-secure-setup/commit/cf38a65) |
| `openclaw doctor` interactive prompts blocking install | Added `--non-interactive --no-workspace-suggestions`, kept `yes \|` and 180 s timeout as belt-and-suspenders. Architecture changed (Step 8b handles systemd unit install now) so `--non-interactive` is safe — the operations it skips are already done | [`93c0bf7`](https://github.com/BuzzardsBay/clawfactory-secure-setup/commit/93c0bf7) |
| CR line-ending corruption when bash here-strings are base64-encoded from PowerShell (CRLF turns `set -e` into `set -e\r`, bash prints `set: invalid option`) | `Invoke-WslBash` in `setup.ps1` now strips CRLF→LF before encoding | [`17172d5`](https://github.com/BuzzardsBay/clawfactory-secure-setup/commit/17172d5) |
| Same CR bug, two more sites in `bootstrap.ps1` (`Invoke-WslBash` + `Get-SoulSha256`) | CRLF→LF strip applied to both | [`93c0bf7`](https://github.com/BuzzardsBay/clawfactory-secure-setup/commit/93c0bf7) |
| `post-install.ps1` raw `wsl -- … 2>&1 \| ForEach-Object` calls aborting on the first stderr line because `$ErrorActionPreference = 'Stop'` wraps stderr as `ErrorRecord` | Refactored 4 sites to use a `Process.Start`-based `Invoke-WslBash` ported from `bootstrap.ps1` | [`93c0bf7`](https://github.com/BuzzardsBay/clawfactory-secure-setup/commit/93c0bf7) |
| Tee-pipe trapping the install command's success exit code as tee's permission-denied failure (`/tmp/openclaw-install.log` was created by the prior root-context step and `tee -a` from clawuser failed) | Dropped the `tee` from Step 8b's gateway-install line; output captured via `Invoke-WslBash`'s stdout routing | [`42869d8`](https://github.com/BuzzardsBay/clawfactory-secure-setup/commit/42869d8) |
| Gateway flapping every 60-180 s on idle WSL VM (systemd reports `Active=running` but port 8787 not listening; browser dashboard disconnects with code 1012 reason=service restart) | New `Step-ConfigureWslConfig` writes `[wsl2] vmIdleTimeout=-1` into `%USERPROFILE%\.wslconfig` (creates or merges) so the WSL VM stays alive while Windows is up. Also: new `Step-EnableChatCompletions` enables `gateway.http.endpoints.chatCompletions.enabled` for the future native chat app. | v1.0.1 — [`1a81a40`](https://github.com/BuzzardsBay/clawfactory-secure-setup/commit/1a81a40) |
| Gateway goes dark during idle even with vmIdleTimeout=-1 (wsl.exe session teardown triggers a full systemd shutdown inside the distro, killing user@1000, docker, containerd, and the gateway) | New `Step-RegisterWslHostTask` registers a hidden Windows scheduled task that runs `wsl.exe -d Ubuntu -u clawuser -- sleep infinity` at user logon, holding one session alive permanently so the last-session-exit trigger never fires. Also: moved `Step-EnableChatCompletions` to run AFTER `Step-PreinstallGatewayRuntime` because `openclaw config set` requires the runtime to be present (was previously printing `--help` instead of writing config). | v1.0.2 — [`c6476d6`](https://github.com/BuzzardsBay/clawfactory-secure-setup/commit/c6476d6) |
| `nft` mangled to `ft` at runtime — egress firewall never activated on any install (`bash: line 41: ft: command not found` in install.log; static analysis showed source intact, so something in the PowerShell→base64→bash transport chain was eating the leading `n`) | `Step-EgressFirewall` rewritten to use full path `/usr/sbin/nft` throughout the embedded script; assertion guard added that throws if the literal `/usr/sbin/nft` token is missing from the script before transport. | v1.0.3 — [`d234a5f`](https://github.com/BuzzardsBay/clawfactory-secure-setup/commit/d234a5f) |
| `Step-InstallOpenClaw` error strings claimed "5 minutes" timeout; the actual `timeout` argument was already 900 s (15 min). Misleading users into thinking the timeout was too short when the real issue was a 15-minute hang. | All three stale strings (comment, bash echo, PowerShell throw) updated to "15 minutes" and the canned blame on `openclaw-onboard` replaced with a list of real candidate causes (apt mirror outage, npm registry latency, DNS, interactive prompt). | v1.0.3 — [`d234a5f`](https://github.com/BuzzardsBay/clawfactory-secure-setup/commit/d234a5f) |
| Egress firewall allowlist missing Ubuntu apt mirrors. Latent — apt-as-root currently bypasses the firewall via `meta skuid != clawuser return` — but a regression in privilege handling inside `install.sh` or a future skill running apt as `clawuser` would silently fail. | Added `archive.ubuntu.com`, `security.ubuntu.com`, `ports.ubuntu.com`, `esm.ubuntu.com`, `ppa.launchpad.net` to `$baseHosts` as defense-in-depth. | v1.0.3 — [`d234a5f`](https://github.com/BuzzardsBay/clawfactory-secure-setup/commit/d234a5f) |
| `Step-EgressFirewall` always saved its checkpoint, even on exit 127 from the mangled `nft` call. Combined with the nft mangling above, this meant every install marked the firewall as installed when it had never run. A `-Resume` re-run would skip the step instead of retrying. | Exit non-zero now logs ERROR (was WARN) and `return`s from the function before `Save-Checkpoint`. Resume re-runs will retry the firewall step. | v1.0.3 — [`d234a5f`](https://github.com/BuzzardsBay/clawfactory-secure-setup/commit/d234a5f) |
| `Step-InstallOpenClaw` 15-min timeout firing on laptops with slow apt mirrors. install.sh's `[1/3] Preparing environment` reaches "Installing Linux build tools (make/g++/cmake/python3)" then produces no output until the wrapper kills it; earlier in the run apt had logged `W: Failed to fetch http://archive.ubuntu.com/ubuntu/dists/jammy/InRelease  Connection failed`. install.sh's apt fetch was the actual stalled command. | New `Step-PreInstallOpenClawDeps` runs `apt-get install -y --no-install-recommends make g++ cmake python3` BEFORE Step-EgressFirewall (no allowlist dependency), so install.sh finds the build tools already present and skips its own apt phase. `nodejs` is intentionally excluded — install.sh owns NodeSource setup. | v1.0.4 — [`7a59e99`](https://github.com/BuzzardsBay/clawfactory-secure-setup/commit/7a59e99) |
| Inno wizard pages (API key, Ack, Provider) prompted the user even when `/SILENT` was passed — silent installs blocked on what was supposed to be wizard UI. | Added `WizardSilent()` bypass to all three pages so `/SILENT -AcknowledgedOpenClawUrl -Provider grok` skips them cleanly and the install proceeds without interaction. | v1.0.5 — [`fe8aa4b`](https://github.com/BuzzardsBay/clawfactory-secure-setup/commit/fe8aa4b) |
| Fresh Win11 VMs without WSL features pre-enabled needed a manual reboot mid-install with no automated resume — installer just ended at the reboot point. | Added RunOnce registry key + `Restart-Computer -Force` in `Step-EnsureWsl` so the installer reboots the VM, auto-logs back in, and continues from the same step. NOTE: the reboot path was unreachable on real first-install hardware until v1.0.8 (exit-code routing) and v1.0.9 (elevation-exit) fixed the surrounding flow. | v1.0.6 — [`fa05a9b`](https://github.com/BuzzardsBay/clawfactory-secure-setup/commit/fa05a9b) |
| `iptables` was missing from `Step-PreInstallOpenClawDeps` — required for nftables fallback (`iptables-legacy`) on kernels that don't expose nft hooks. Also: 60-second `apt-get` timeout was too tight on slow mirrors. | Added `iptables` to the build-deps `apt-get install` list. Extended timeout to 300s. | v1.0.7 — [`9cad445`](https://github.com/BuzzardsBay/clawfactory-secure-setup/commit/9cad445) |
| Three `& wsl.exe ... 2>&1` calls in `Step-EnsureWsl` were turning native-command stderr into ErrorRecords under `$ErrorActionPreference = 'Stop'`, throwing on harmless WSL warnings before the exit code could be checked. The reboot-and-resume code from v1.0.6 was never being reached because the script terminated upstream. | Replaced all three calls with `[System.Diagnostics.Process]::Start($psi)` invocations that capture stdout/stderr separately and don't propagate native stderr as terminating errors. | v1.0.8 — [`ea95179`](https://github.com/BuzzardsBay/clawfactory-secure-setup/commit/ea95179) |
| `Step-EnsureWsl` exit-code routing was wrong: `wsl --install` exit 1 ("elevation required, reboot pending") was being caught by `Invoke-WithRollback` as a fatal failure instead of routing to the RunOnce + reboot path. | Reworked the exit-code branches so any non-zero from `wsl --install` (including the documented `1` for "needs reboot") routes to the reboot-and-resume path; only genuine install failures throw. | v1.0.9 — [`bc14fd5`](https://github.com/BuzzardsBay/clawfactory-secure-setup/commit/bc14fd5) |
| Non-ASCII characters (em-dashes, arrows, multiplication sign) in `setup.ps1` caused PS 5.1 parse-time terminating errors. Without a UTF-8 BOM, PS 5.1 reads scripts as Windows-1252; non-ASCII bytes (e.g., 0xE2 0x80 0x94 for em-dash) decoded as garbage tokens before any code ran. | Removed every non-ASCII byte from `setup.ps1`. Replaced `—` with ` - `, `→` with `->`, `×` with `x`. Added a non-ASCII byte scan as a pre-build check. | v1.0.10 — [`5ced33b`](https://github.com/BuzzardsBay/clawfactory-secure-setup/commit/5ced33b) |
| Egress firewall `nft` token was being corrupted to `ft` again — different mechanism this time (backtick inside PowerShell here-string ate the leading `n` during transport). | Rewrote the affected lines so the `nft` token is never adjacent to a backtick. Also: added `chmod 1777 /tmp` and `chmod 1777 /var/tmp` inside WSL after distro import, defending against `tee: Permission denied` later in Step 8b. | v1.0.11 — [`c71da9a`](https://github.com/BuzzardsBay/clawfactory-secure-setup/commit/c71da9a) |
| Multiple production-blocking issues in the unattended-install path: `Read-Host` prompts hung silent installs forever (rollback prompt at line 431 burned 36 of 45 minutes in the v1.0.11 Azure validation); `MessageBox.Show` calls did the same on the WSL-restart-required path; ten `& wsl.exe ... 2>&1` calls survived from earlier sweeps; Docker `apt-get install` had no timeout; `INSTALLER_DONE` marker was never written, so clean failures looked like TIMEOUT to the validation harness; gateway-not-binding failures had no diagnostic capture. | New `Confirm-Or-Default` helper gates every interactive primitive on a `$Silent` flag (added to `setup.ps1` param block; propagated from `.iss` via `WizardSilent()`). New `Invoke-WslExe` helper for `wsl.exe` direct calls. `timeout 300` added to all `Step-InstallDocker` apt-get calls; `timeout 1800` on `ollama pull`. `/tmp/openclaw-install.log` pre-created owned by `clawuser`. Gateway-failure path now collects `journalctl --user -u openclaw-gateway`, `systemctl status`, `ss -tlnp` before throwing. Top-level `try/catch/finally` ensures `INSTALLER_DONE=success` or `INSTALLER_DONE=failure reason=<msg>` is written to `install.log`, `C:\install-result.txt`, and `C:\ProgramData\ClawFactory\install-result.txt` on every exit path. | v1.0.12 — [`0c208ba`](https://github.com/BuzzardsBay/clawfactory-secure-setup/commit/0c208ba) |
| Gateway service reported `Active=running` but never bound port 8787 — curl `/status` returned exit 7 (connection refused), then exit 28 (timeout) for ~60s, then `Step-PreinstallGatewayRuntime` threw "Gateway did not respond after 60 seconds." Root cause: OpenClaw 2026.4.23 had a known bonjour mDNS crash loop (issues #72355, #64928) that wedged the gateway event loop after the systemd unit reported active. The pinned version was four patch releases behind the version listed as "validated" in our own comments. Also: silent-mode auto-rollback was wiping the WSL distro before forensics could be collected. Also: the v1.0.11 chmod 1777 /tmp was insufficient — needed a pre-created log file with mode 0666 to defend against sudo'd tee re-creating the file as root. | Bumped `OpenClawNpmVersion` from `2026.4.23` to `2026.4.27` (install.sh hash unchanged — install.sh is version-agnostic, version is passed via `OPENCLAW_VERSION` env var). Changed silent rollback default from `'y'` to `'n'`. Pre-create `/tmp/openclaw-install.log` with `chown clawuser:clawuser` AND `chmod 0666` so any user context (root or clawuser) can append. `$InstallerVersion` bumped to `1.0.13` (was stale at `1.0.4`). | v1.0.13 — [`e3c0b3a`](https://github.com/BuzzardsBay/clawfactory-secure-setup/commit/e3c0b3a) |
| `Test-WslFunctional` always returned false on fresh installs because `Invoke-WslExe` (added v1.0.12) used the default `Console.OutputEncoding` (CP1252) to read `wsl.exe --list --quiet` output. wsl.exe writes UTF-16-LE; decoding `Ubuntu\r\n` (16 bytes) as CP1252 produced `U\0b\0u\0n\0t\0u\0\r\0\n\0` (16 chars with embedded NULs). The `-replace "\0", ''` happened AFTER `.Trim()` — `\0` blocked Trim from reaching the trailing `\r`, leaving `'Ubuntu\r'` after replace. The `-contains 'Ubuntu'` check then failed. Step-EnsureWsl threw "WSL could not be configured." Separate latent bug: `Invoke-WithRollback`'s `$done = Get-CompletedSteps; if ($done.Count ...)` crashed under `Set-StrictMode -Version 3.0` when only one checkpoint had been saved — PS 5.1 unrolls single-element array returns to scalar strings, and StrictMode 3 forbids `.Count` on String. Hidden until v1.0.13 made the install fail this early. | Set `$psi.StandardOutputEncoding = [System.Text.Encoding]::Unicode` and same for stderr in `Invoke-WslExe`. Wrapped both `Get-CompletedSteps` call sites with `@(...)` to force array context across the function-return boundary. Routed `Step-RestartWsl`'s remaining bare `wsl --shutdown` and `wsl -d Ubuntu -- true` calls through `Invoke-WslExe` for consistency. | v1.0.14 — [`028f0c7`](https://github.com/BuzzardsBay/clawfactory-secure-setup/commit/028f0c7) |
| `smoke-test.ps1` produced 7 false-failures when invoked via `az vm run-command` because the run-command service runs scripts as `NT AUTHORITY\SYSTEM` and WSL refuses to run as LocalSystem (`WSL_E_LOCAL_SYSTEM_NOT_SUPPORTED`). Every `wsl ... -- bash -lc ...` returned the SYSTEM error message, breaking every regex/equality check that depended on WSL output. Also: an `[int]$result -ge 4` coercion crashed with "Cannot convert Object[] to Int32" when wsl returned multi-line error text. Also: smoke-test.ps1 wasn't bundled in `.iss` — couldn't be located at the validation harness's first lookup path. | Added `[Security.Principal.WindowsIdentity]::GetCurrent().IsSystem` detection. Tagged WSL-dependent checks with `-RequiresWsl`; under SYSTEM they SKIP cleanly instead of failing. Defensive parse `[regex]::Match($first, '\d+')` replaces the brittle `[int]$var` cast. New `Invoke-WslCapture` helper uses Process.Start with explicit UTF-8 encoding (correct for bash/cat-forwarded stdout, unlike setup.ps1's UTF-16-LE which is correct for wsl.exe-native output). Added `Source: "smoke-test.ps1"; DestDir: "{app}\resources"; Flags: ignoreversion` to `.iss` [Files]. | v1.0.15 — [`82ef187`](https://github.com/BuzzardsBay/clawfactory-secure-setup/commit/82ef187) |
| `/v1/chat/completions` returned HTTP 404 on every install since v1.0.1 — chatCompletions route never registered. v1.0.16 attempted `--strict-json`; live VM testing showed three things: (1) the boolean-writing flag is `--json`, not `--strict-json`; (2) openclaw caches gateway config at startup so the route stays unregistered until an explicit gateway restart, even if the config write succeeds; (3) Step-EnableChatCompletions's `Start-Process -FilePath wsl.exe` direct call returned exit 1 with no openclaw stdout under the wrapper.cmd auto-logon context, while identical commands run fine via scheduled task or `Invoke-WslBash`. | Three-part fix in v1.0.17: (1) replaced `--strict-json` with `--json` at three boolean/integer sites (gateway.port x2, plugins.entries.bonjour.enabled, gateway.http.endpoints.chatCompletions.enabled); (2) refactored Step-EnableChatCompletions to use `Invoke-WslBash` (the proven base64-script transport that $script8c / $script9a use), which also lets us add the gateway restart inside the same bash atomic block; (3) added `systemctl --user restart openclaw-gateway` + `/status` health poll inside the new `$script9b` so the route is registered before the install completes. | v1.0.17 — [`18516a6`](https://github.com/BuzzardsBay/clawfactory-secure-setup/commit/18516a6) |
| ClawChat desktop app not bundled. Validation focused on backend gateway only; no end-user UX shipped. | New Tauri+React desktop app (`C:\Users\bmcki\ClawChat\`) built and bundled into both installers as `resources\ClawChat.exe` (10.88 MB). Desktop shortcut + Start Menu entry now launch ClawChat directly. setup.ps1's `launcher.ps1` still starts the gateway as a fallback path; ClawChat handles its own gateway-status polling. | v1.0.18 (ClawFactory) / v1.0.1 (ClawAgent) — [`501821a`](https://github.com/BuzzardsBay/clawfactory-secure-setup/commit/501821a) / [`af60e6d`](https://github.com/BuzzardsBay/clawagent-setup/commit/af60e6d) |
| OpenClaw install.sh hash drift: `openclaw.ai/install.sh` tracks "latest" and changed twice in 24 hours on 2026-05-09/10 (`57f025ba…` → `85fab092…` → `3a617b73…`). Every v1.0.x cycle that fetched install.sh at install time was a coin flip against the upstream-change cadence. v1.0.18 Azure validation FAILED at [R2] hash mismatch as a direct consequence. | Bundle install.sh into the installer as `resources\openclaw-install.sh`. Hash-verified on Windows via `Get-FileHash` before any WSL invocation; mismatch throws. File streamed into WSL `/tmp/openclaw-install.sh` via stdin pipe (sidesteps the 32K Windows argv limit for Invoke-WslBash transport). `$OpenClawInstallUrl` constant removed entirely. v1.0.20 / v1.0.3 Azure cycles both PASS with `Bundled openclaw-install.sh hash verified.` confirmed in install.log. | v1.0.20 / v1.0.3 — [`86dfd36`](https://github.com/BuzzardsBay/clawfactory-secure-setup/commit/86dfd36) / [`65d5a10`](https://github.com/BuzzardsBay/clawagent-setup/commit/65d5a10) |

**v1.0.1 diagnosis lineage — vmIdleTimeout / VM idle bug.** Symptom was a gateway that systemd marked Active=running while port 8787 was not listening; the WSL VM cycled boot/shutdown approximately every 60-180 seconds. Root cause was the Windows-side `.wslconfig` — either missing entirely or present without a `vmIdleTimeout` key. WSL2's default vmIdleTimeout is 60000 ms, so the VM (and the gateway running inside it) shuts down 60 seconds after the last activity. `loginctl enable-linger clawuser` does **not** prevent this: linger keeps user services alive across logout, but the WSL VM itself is governed by Windows-side `.wslconfig`. Diagnosed in a CC session on May 4, 2026. Ruled out: SIGTERM from a supervisor process, watchdog kill, hot-reload watcher, `openclaw-control-ui` issuing a restart RPC, linger not enabled, crash + restart loop. Confirmed via: missing `.wslconfig`, `journalctl --list-boots` showing 13 boots in 12 hours with several under 30 s, kernel `boot_id` changing per cycle, explicit `Reached target Shutdown` markers in journal, and a live test where continuous external WSL activity kept the gateway stable for 9+ minutes. Secondary finding (NOT fixed in v1.0.1, low priority): the systemd unit is `Type=simple` (default), so `systemctl` marks the unit "active" the instant `node` is exec'd — before the gateway binds port 8787. There is a 3-14 second window where `systemctl` says `active` but `curl` says `connection-refused`. Fixing it would require an OpenClaw code change to call `sd_notify(READY=1)` after `server.listen()` plus `Type=notify` in the unit file. Not pursued in v1.0.1 because the primary fix (vmIdleTimeout=-1) keeps the VM alive long enough that this window is invisible to users in practice.

**v1.0.2 diagnosis lineage — wsl.exe session-exit shutdown.** Root cause: every time the last `wsl.exe` session exits, WSL triggers a full systemd shutdown sequence inside the distro — not just a logout, a shutdown. This tears down `user@1000`, docker, containerd, and the gateway regardless of linger or `vmIdleTimeout` settings. `vmIdleTimeout=-1` (v1.0.1) correctly prevents VM-level kernel reboots, but is necessary-not-sufficient: the distro-level shutdown is a separate mechanism running INSIDE the live VM. Fix: a hidden Windows scheduled task runs `wsl.exe -d Ubuntu -u clawuser -- sleep infinity` at user logon, keeping one session alive so the trigger never fires. Confirmed via the **system** journal (not the user journal): explicit `System is powering down` from `logind` immediately following Plan9 channel close (`p9io.cpp:258 AcceptAsync Operation canceled`), with 12 shutdown cycles observed in a single 47-minute kernel boot window. Ruled out: linger misconfiguration (correctly set, verified via `loginctl show-user clawuser`); `pam_systemd` / `KillUserProcesses` (defaults, not implicated); system-unit migration (system units are also torn down in the shutdown sequence, so moving the unit out of `--user` doesn't help); a boot-trigger keepalive (doesn't prevent the session-exit trigger because the trigger fires when the LAST session exits, not on cold start). CC diagnostic session May 4, 2026.

**v1.0.3 diagnosis lineage — egress firewall never activated.** Confirmed via the laptop's runtime `install.log` from the v1.0.2 validation run on May 4, 2026: `bash: line 41: ft: command not found` proved that bash was receiving the token `ft` instead of `nft` at execution time, even though static analysis of the PowerShell `@"..."@` here-string and a parser-test reproduction both showed `nft` intact. The mangling happens somewhere between PowerShell parsing and bash interpretation — base64 transport in `Invoke-WslBash` should preserve bytes exactly, so the failure mode remains unexplained at the byte level. Workaround chosen over root-cause debug: switch every bare `nft` invocation in the embedded firewall script to full path `/usr/sbin/nft`. Full path bypasses any PATH-resolution issue and would survive even if the leading `n` is lost (worst case, `/usr/sbin/ft` is still a clean "file not found" rather than the silent fallthrough that bare `nft` exhibited). A regression-prevention assertion guards against future edits dropping the full path. Two latent bugs surfaced during the same investigation and were fixed in the same patch: (a) the `Step-InstallOpenClaw` timeout had already been bumped to 900 s in code but three human-readable error strings still said "5 minutes" — fixed to "15 minutes" with more accurate cause hints; (b) the firewall allowlist did not include Ubuntu apt repos — added as defense-in-depth even though apt-as-root currently bypasses the firewall via `meta skuid != clawuser return`. Bug #4 (firewall checkpoint saved on exit 127) was the proximate reason the first three bugs were silent — without it, every laptop install since v1.0.0 would have surfaced the `nft` mangling. CC diagnostic session May 4, 2026.

**v1.0.4 diagnosis lineage — install.sh apt timeout on slow networks.** Confirmed via the laptop's runtime install.log from the v1.0.2 validation run (May 4, 2026): install.sh got through `[1/3] Preparing environment` → `Installing Linux build tools (make/g++/cmake/python3)` and then went silent until the 15-minute timeout fired. Earlier in the same install.log, apt had already logged `W: Failed to fetch http://archive.ubuntu.com/ubuntu/dists/jammy/InRelease  Connection failed [IP: 91.189.92.23 80]` during Step-InstallDocker — the laptop's link to archive.ubuntu.com was flaky. Setup.ps1's own apt steps (Step-InstallDocker) tolerate the blip because each `apt-get install` retries internally; install.sh's apt invocation does not. Fix: pre-install the four build tools (`make g++ cmake python3`) in setup.ps1 itself, **before** Step-EgressFirewall runs, so the apt fetch happens with no firewall in the way and is logged separately from install.sh's output. install.sh's idempotency check then sees the packages already installed and skips its own apt phase entirely. `nodejs` is intentionally excluded from the pre-install — install.sh owns the NodeSource setup, and dragging that out of install.sh would break the contract boundary. The new step also creates a useful invariant: any future install.sh that adds new build deps will fail loudly during install.sh's own phase rather than silently stalling on apt fetch. CC diagnostic session May 4, 2026.

**v1.0.6–v1.0.9 diagnosis lineage — reboot-and-resume path on fresh Win11 hardware.** v1.0.6 added the RunOnce + `Restart-Computer -Force` reboot/resume code in `Step-EnsureWsl`, but the path was unreachable on every actual fresh Win11 VM until v1.0.8 because three `& wsl.exe ... 2>&1` calls upstream were hitting PowerShell 5.1's `$ErrorActionPreference = 'Stop'` + `2>&1` interaction (native command stderr lines wrapped as `ErrorRecord`s, terminating the script before any exit code could be checked). v1.0.8 replaced the three calls with `[System.Diagnostics.Process]::Start($psi)` invocations, exposing the still-broken exit-code routing in v1.0.9 — `wsl --install` exits `1` ("elevation required, reboot pending") on a fresh-VM first call, but the routing was treating any non-zero as a fatal failure for `Invoke-WithRollback`. v1.0.9 fixed the branches so any non-zero from `wsl --install` (especially `1`) routes to the reboot path; only genuine install failures throw. Three releases to land one feature; the lesson is that reboot-and-resume is the kind of code you can't unit-test on a bring-your-own dev box — it only proves itself on a clean baseline image. v1.0.6 commit `fa05a9b` ships the code; the path is verified working only at v1.0.9 commit `bc14fd5`.

**v1.0.10 diagnosis lineage — non-ASCII bytes in setup.ps1.** PowerShell 5.1 reads `.ps1` files using `Console.InputEncoding` when no UTF-8 BOM is present. On Win11 with default settings, that's Windows-1252. An em-dash (U+2014) in a comment string encodes to UTF-8 as `0xE2 0x80 0x94` — three bytes that decode under CP1252 as `âEUR"`, producing parse-time terminating errors before any runtime code executes. The em-dash had been added in a prior cleanup pass without realizing the file lacked a BOM. Fix was mechanical (replace `—` with ` - `, `→` with `->`, `×` with `x` throughout), but the durable fix is the new pre-flight check that scans for any byte > 0x7F in setup.ps1 and fails the build if any are found. Discovered when v1.0.9 wouldn't even start — install.log was empty because PowerShell errored out before opening the file.

**v1.0.11 diagnosis lineage — egress firewall typo and /tmp permissions.** Two unrelated issues bundled in one patch. (1) The v1.0.3 fix for `nft` mangling had regressed: a backtick-in-here-string interaction in PowerShell ate the leading `n` again, in a different code path. Resolved by ensuring `nft` is never adjacent to a backtick in the embedded script. (2) Step 8b's `tee -a /tmp/openclaw-install.log` was failing with permission denied on the laptop. The rootfs ships with `/tmp` mode 0755 root:root; clawuser couldn't write to it. Added `chmod 1777 /tmp && chmod 1777 /var/tmp` immediately after WSL distro import. The `/tmp` part is incomplete — see v1.0.13 for the full story (the file ALSO needs to be pre-created with mode 0666 because openclaw's install.sh re-creates it in a sudo'd context). The v1.0.11 Azure validation surfaced both this and the much-bigger Read-Host-hangs-on-/SILENT issue that v1.0.12 addressed, plus the bonjour-loop blocker that v1.0.13 addressed.

**v1.0.12 diagnosis lineage — comprehensive hardening of unattended-install path.** v1.0.11's Azure validation hit a 45-minute TIMEOUT not because the install actually took 45 minutes, but because the install crashed in the gateway-not-binding code path (a v1.0.13 issue, not addressed here), then `Invoke-WithRollback`'s `Read-Host 'Installation failed. Run automatic rollback? (y/N)'` blocked indefinitely under `/SILENT /SUPPRESSMSGBOXES` waiting for a stdin that would never come. The Inno flags suppress Inno's wizard, not PowerShell's stdin reads. Audit found ten more `& wsl.exe ... 2>&1` calls that survived the v1.0.7/.8 fix (in `Test-WslFunctional`, `Install-WslDistroWithFallback`, `Step-ConfigureWslConfig`'s shutdown call, and the rollback's `--unregister`), plus three `MessageBox.Show` calls with no silent-mode guard (one in `Show-RestartNotice`, one in `Step-EnsureWsl` reboot dialog, two more in the `.wslconfig` conflict path). Plus: `INSTALLER_DONE` marker had never been written by setup.ps1 — the Azure validation harness had been treating clean failures as TIMEOUT for the entire v1.0.4 → v1.0.11 cycle because it was waiting for a marker the installer never emitted. Fix: a single `Confirm-Or-Default` helper gating every interactive primitive, a `$Silent` switch propagated from `WizardSilent()` via the `.iss` `[Run]` block, an `Invoke-WslExe` helper for direct wsl calls (paired with the existing `Invoke-WslBash` for bash-via-wsl calls), `timeout 300` on every `apt-get install`, gateway-failure diagnostic capture, and a top-level `try/catch/finally` that writes `INSTALLER_DONE` on every exit path. Pre-flight checks added: grep for `Read-Host` outside the helper, grep for `wsl ... 2>&1` in code, parser check, non-ASCII byte scan. Net effect: the v1.0.12 Azure validation produced an architectural-shape PASS (install completes cleanly OR fails with `INSTALLER_DONE=failure reason=<msg>` in seconds), even though the gateway-not-binding bug was still present. CC validation cycles May 7, 2026.

**v1.0.13 diagnosis lineage — gateway not binding and OpenClaw version drift.** The v1.0.11 / v1.0.12 Azure runs both failed at `Step-PreinstallGatewayRuntime` with "Gateway did not respond after 60 seconds." `systemctl --user status openclaw-gateway.service` reported `Active=running` while `ss -tlnp | grep 8787` was empty. Diagnostic block added in v1.0.12 surfaced the smoking gun: bonjour mDNS was wedging the gateway event loop after systemd reported the unit active. The CLAUDE_ClawFactory.md comment claimed "ClawFactory v1.0 ships with OpenClaw 2026.4.27 — manually validated 2026-04-30 with the four bundled bug-workarounds intact"; the actual constant `$OpenClawNpmVersion` was `'2026.4.23'`, four patch releases behind the validated version. Issues #72355 and #64928 (bonjour mDNS crash loop) were fixed in 2026.4.27. Bumped the pin and confirmed via independent verification that the install.sh hash didn't need to change — install.sh is version-agnostic on `openclaw.ai/install.sh` and reads `OPENCLAW_VERSION` from the environment. Side fixes in the same patch: silent-mode rollback default flipped from `'y'` to `'n'` (a failed silent install was wiping its own forensics by auto-unregistering the WSL distro), and `/tmp/openclaw-install.log` pre-creation upgraded from chown-only to chown + `chmod 0666` to defend against an internal openclaw `sudo'd tee` re-creating the file as root. CC validation cycle May 7, 2026.

**v1.0.14 diagnosis lineage — encoding and PS 5.1 array unrolling.** v1.0.13's Azure run failed in `Step-EnsureWsl` with "WSL could not be configured" — the WSL distro had imported successfully and clawuser had been created (visible in install.log), but `Test-WslFunctional` returned false 5 seconds later. Trace: `Test-WslFunctional` calls `Invoke-WslExe -Arguments @('--list','--quiet')`. The new helper used the default `Console.OutputEncoding` (CP1252 on Win11) to decode wsl.exe's output. wsl.exe writes its OWN output (status, list, etc.) as UTF-16-LE on Windows. Decoding `Ubuntu\r\n` (16 UTF-16-LE bytes) as CP1252 gives 16 chars with embedded NULs: `U\0b\0u\0n\0t\0u\0\r\0\n\0`. The parsing loop did `$_.Trim() -replace "\0", ''`. Trim runs first; `\0` is not whitespace, so it blocks Trim from reaching the trailing `\r`. After the replace, the result is `'Ubuntu\r'`, not `'Ubuntu'`. The `-contains 'Ubuntu'` check fails. Step-EnsureWsl throws. Fix: set `$psi.StandardOutputEncoding = [System.Text.Encoding]::Unicode` in `Invoke-WslExe`. This is correct for wsl.exe-native commands but would be WRONG for bash-via-wsl output (which is UTF-8 pass-through) — the helper has different encoding policies for different use cases by design. Smoke-test.ps1's similar helper (added v1.0.15) uses UTF-8 for the same reason in reverse. Separately: `Invoke-WithRollback`'s catch handler called `$done = Get-CompletedSteps; if ($done.Count -gt 0) { ... }`. PS 5.1 unrolls single-element array returns to a bare scalar at the function-return boundary. With only the `Preflight` checkpoint saved (v1.0.13 failed early), `$done` came back as the bare string `'Preflight'`, and `.Count` access on String under `Set-StrictMode -Version 3.0` throws "the property 'Count' cannot be found." Bug had existed since the rollback feature was added but never fired in earlier runs because failures occurred AFTER 2+ checkpoints, and multi-element arrays don't unroll. Fix: wrap both call sites with `@(...)` to force array context. CC validation cycle May 7, 2026.

**v1.0.15 diagnosis lineage — smoke-test.ps1 SYSTEM context.** v1.0.14 was the first true PASS for the install itself (gateway bound, idle survived 5-minute test, INSTALLER_DONE=success). But `smoke-test.ps1` reported 7 of 11 checks failing. Initial diagnosis (in the v1.0.14 report) blamed UTF-16 encoding on the smoke test's bare `wsl ...` calls — but that diagnosis was wrong, and the user pushed back. The actual root cause: `az vm run-command` always runs scripts as `NT AUTHORITY\SYSTEM` on Windows VMs, and WSL refuses to run as LocalSystem (returns `WSL_E_LOCAL_SYSTEM_NOT_SUPPORTED`). Every `wsl ... -- bash -lc ...` in smoke-test was returning the SYSTEM error message instead of the expected output, breaking every regex/equality check. Fix: `[Security.Principal.WindowsIdentity]::GetCurrent().IsSystem` detection at the top of smoke-test; checks tagged `-RequiresWsl` SKIP (not FAIL) when running as SYSTEM. The exit code counts only `$fail`, not `$skip`. Side fix: an `[int]$result -ge 4` cast was crashing with "Cannot convert Object[] to Int32" because wsl-as-SYSTEM returned multi-line error text — defensive parse `[regex]::Match($first, '\d+')` replaces the brittle cast. Also: smoke-test.ps1 wasn't even bundled in `.iss` — the validation harness was uploading its own copy. Added to `.iss [Files]`. Validation-harness side: the run-as-clawadmin scheduled-task pattern I'd recommended for v1.0.16+ doesn't actually work on Win11 (batch-logon-rights restriction); the working substitute is a `wrapper.cmd` referenced from RunOnce that runs as clawadmin post-autologon (proven for credential pre-seed). Three full PASS cycles + one harness-flake (PROBE2 `-TimeoutSec 5` timed out on a loaded 2-core VM while gateway was demonstrably alive; remediated by raising to `-TimeoutSec 15` with single retry). CC validation cycles May 7-8, 2026.

**v1.0.16 diagnosis lineage (superseded by v1.0.17 lineage below).** v1.0.16 added `--strict-json` to four `openclaw config set` calls based on a Phase 3 RDP investigation that concluded the boolean-writing flag was `--strict-json`. The Azure validation cycle on commit 14b0001 surfaced that this was wrong: install completed cleanly, smoke passed 4P/0F/7S, but `/v1/chat/completions` still returned 404 and openclaw.json had no `chatCompletions.enabled` key. Live VM testing on the same image showed `--strict-json` was not the issue per se (the same flag works for object/array values, which is why the auth.profiles writes have shipped fine since v1.0.0); the real failure was a combination of three things, untangled in v1.0.17.

**v1.0.17 diagnosis lineage — chatCompletions actual fix.** Live root-cause investigation on the failing v1.0.16 VM (`cfv-165245`, scheduled-task probes as clawadmin) found three independent issues, all of which had to be fixed for the route to come up:

1. **Wrong flag for boolean writes.** Across many flag/value combinations, `openclaw config set gateway.http.endpoints.chatCompletions.enabled true --json` was the only invocation that consistently wrote the boolean. `--strict-json` works for JSON-object values (e.g., the auth.profiles dictionary written at line 1735) but for bare scalar `true` the boolean-write semantics differ between flags — and the install-time call wasn't writing the value despite returning exit 1, suggesting openclaw silently rejected the call entirely. `--json true` writes correctly every time.

2. **Gateway caches config at startup.** openclaw's CLI itself prints "Restart the gateway to apply" after a successful config write. Step-EnableChatCompletions previously had no restart, so the gateway loaded its endpoint registration when Step-PreinstallGatewayRuntime started it (BEFORE chatCompletions was enabled) and never re-read the config. Verified live: after manually setting the flag with `--json` AND running `systemctl --user restart openclaw-gateway`, the same probe that returned 404 returned HTTP 400 ("Invalid model" — proves route is registered; the model-name format issue is downstream and out of scope for the route-registration fix).

3. **`Start-Process -FilePath wsl.exe` returned exit 1 with no openclaw stdout during install** under the wrapper.cmd post-autologon context, while identical bash commands ran fine via scheduled task or `Invoke-WslBash` from the same install. Root cause not pinned down — possibly a stdin/handle inheritance issue with the `-NoNewWindow -Wait -PassThru -RedirectStandard*` combination when invoked from cmd.exe → setup.ps1 chain — but the fix is to switch the function to the same `Invoke-WslBash` base64-script transport that $script8c (Step-PreinstallGatewayRuntime) and $script9a (Step-ConfigureOpenClaw) use, both of which work reliably in the same install context.

The v1.0.17 fix folds all three: $script9b in Step-EnableChatCompletions writes the flag with `--json`, runs `systemctl --user restart openclaw-gateway`, and polls `/status` for ~12s, all inside one Invoke-WslBash call. Verdict: chatCompletions route registered (HTTP 400 instead of 404 on probe POST). CC validation cycle May 8, 2026.

---

## Active known issues (v1.0.20)

The Resolved bugs table above documents everything that's been fixed in the v1.0.x series. The following are NOT resolved — carry forward into v1.1 planning (see [v1.1_backlog.md](v1.1_backlog.md)).

| ID | Component | Issue |
|----|-----------|-------|
| M4 | `resources/switch-provider.ps1:79` | Wrong JSON path (`~/skills-factory/openclaw.json`); should write via `openclaw config set` against `~/.openclaw/openclaw.json`. Uses `python3` (not guaranteed in WSL). |
| M5 | `resources/switch-provider.ps1:60` | Auxiliary hosts not re-added to nftables allowlist after provider switch — egress firewall blocks the new provider. |
| M6 | `resources/switch-provider.ps1` | No iptables-legacy fallback for kernels that don't expose nft hooks. |
| C1 | ClawChat (desktop shortcut path) | Desktop shortcut launches `ClawChat.exe` directly, bypassing `launcher.ps1`. If the WSL Host scheduled task hasn't fired yet, gateway is offline and ClawChat shows offline state until the next poll cycle. |
| C2 | ClawChat (UI scope) | No settings tab — users cannot switch providers, manage API keys, or modify security controls from the UI. FAQ on clawfactory.app currently says "coming soon." |

M4/M5/M6 block honest user-facing answers about provider switching. C1/C2 block honest user-facing answers about settings management. Both are v1.1 priorities. See backlog items 5, 18, 19.

### Resolved in v1.0.x (no longer blocking)
- Gateway restart loop on first install → v1.0.1 (systemd fallback + `openclaw config set --json` fixes)
- chatCompletions HTTP 404 → v1.0.17 (`Step-EnableChatCompletions` refactor with `--json` + gateway restart inside `$script9b`)
- OpenClaw install.sh URL drift → v1.0.20 (bundled install.sh; no URL fetch)

---

## Product roadmap

| Product | Price | Status |
|---------|-------|--------|
| ClawFactory | $149 | LIVE — clawfactory.app |
| ClawAgent | $49 | LIVE — clawfactory.app |
| ClawChat | bundled | LIVE — bundled in ClawFactory + ClawAgent |
| ClawResearch | $79 | Roadmap — next after ClawChat v1.2 |
| ClawScribe | $29 | Roadmap |
| ClawVault | $49 | Roadmap |
| ClawCode | $49 | Roadmap |
| ClawDesk | $29 | Roadmap |
| ClawStudy | $19 | Roadmap |
| ClawCanvas | $39 | Roadmap |
| ClawMed | $29 | Roadmap |
| ClawWatch | $49 | Roadmap |
| ClawSight | $49 | Roadmap |

**Code signing cert (Sectigo OV ~$200/yr):** pending first revenue. Required before SmartScreen "Windows protected your PC" warning is resolved — currently the FAQ on clawfactory.app instructs users to click "More info → Run anyway."

### ClawResearch — spec summary

A local AI agent that searches the web, reads pages, and synthesizes sourced answers. All queries and results stay on the user's machine. Only outbound traffic: search API calls to Tavily + LLM provider.

**Price:** $79 (one-time)
**Target users:** researchers, analysts, lawyers, journalists, students, investors, hobbyists — anyone who wants private, sourced web research.

**Technical delta from ClawAgent:**
- Tavily API key added to installer wizard
- `api.tavily.com` added to nftables egress allowlist
- System prompt pre-configured for research behavior: cite sources, verify claims, summarize with links
- ClawChat Sources panel: every answer shows retrieved URLs

**Three-layer verification system:**

1. **Source gating** — configurable tiers:
   - Tier 1: primary sources only (`.gov`, `.edu`, peer-reviewed, official filings, Reuters/AP)
   - Tier 2: Tier 1 + major publications (WSJ, NYT, FT, established trade press)
   - Tier 3: open web (default)
2. **Claim verification** — confidence scoring per claim:
   - **High:** 3+ independent sources agree
   - **Medium:** 1-2 sources, no conflicts
   - **Low:** single source or conflicting sources
   - Uses `[VERIFIED]` / `[INFERRED]` / `[GENERAL]` tagging (same pattern as FrontierAI CalibrationAgent)
3. **Conflict flagging** — surfaces source disagreements explicitly rather than picking one answer.

**ClawChat additions for ClawResearch:**
- Sources panel: clickable links to every retrieved URL
- Confidence badge per response (High / Medium / Low)
- Claim-level tagging: ✓ (verified), ~ (inferred), ! (conflicting)
- "Dig deeper" button: sends agent back for more sources on flagged claims
- Source tier selector in settings

**FAQ disclaimer (honest limitation):**
> ClawResearch reduces hallucination risk significantly but cannot eliminate it. Tavily retrieves what exists on the web. If the web is wrong, the agent can be wrong. The verification layer catches conflicts and low-confidence claims — it does not manufacture ground truth.

**Build order (after ClawChat v1.2):**
1. ClawResearch installer (fork ClawAgent, add Tavily wizard step + firewall rule)
2. ClawChat Sources panel + confidence UI
3. Verification agent (reads Tavily results, scores claims)
4. Azure validation + release

---

## Smoke test history

| Date | Build | Result | Notes |
|---|---|---|---|
| 2026-05-03 | `93c0bf7` (v1.0.0) | **7/7 PASS on real hardware** | Final ship validation. |
| 2026-04-30 | `a702b2d` | 6/7 (doctor blocked on prompt) | Drove diagnosis of the doctor-non-interactive issue resolved in `93c0bf7`. |
| 2026-04-30 | `cf38a65` | 6/7 (Step 8b threw on install --force exit=1) | Drove diagnosis of the throw-on-exit-1 issue resolved in `cf38a65` itself. |
| 2026-05-04 | `1a81a40` (v1.0.1) | **8/8 PASS expected on real hardware** | Adds check #8: `.wslconfig` has `vmIdleTimeout=-1`. Re-run before tagging v1.0.1. |
| 2026-05-04 | `c6476d6` (v1.0.2) | **9/9 PASS expected on real hardware** | Adds check #9: `ClawFactory WSL Host` scheduled task registered and enabled. 5-minute idle test mandatory before tagging. |
| 2026-05-04 | `d234a5f` (v1.0.3) | **10/10 PASS expected on real hardware** | Adds check #10: `nft list ruleset` shows `clawfactory` chain. Will FAIL on every v1.0.2 and earlier install (firewall was never active there). Mandatory before tagging. |
| 2026-05-04 | `7a59e99` (v1.0.4) | **11/11 PASS expected on real hardware** | Adds check #11: `dpkg -l make g++ cmake python3` shows all four installed. Also exercises the slow-apt path. |
| 2026-05-06 | `fe8aa4b` (v1.0.5) | not run on real hardware | WizardSilent() bypass — affects wizard pages only, no smoke-observable change. |
| 2026-05-06 | `fa05a9b` (v1.0.6) | not run on real hardware | Reboot-and-resume code added but unreachable until v1.0.8. No smoke check change. |
| 2026-05-06 | `9cad445` (v1.0.7) | not run on real hardware | Build-deps + apt timeout. No smoke check change. |
| 2026-05-07 | `ea95179` (v1.0.8) | first Azure run | Reboot-and-resume path now reachable. Azure validation harness introduced; first cycle FAIL on a downstream issue. |
| 2026-05-07 | `bc14fd5` (v1.0.9) | Azure FAIL | Step-EnsureWsl exit-code routing. Azure validation: TIMEOUT (downstream Read-Host hang in v1.0.11 era). |
| 2026-05-07 | `5ced33b` (v1.0.10) | Azure FAIL | Non-ASCII byte purge. Azure validation: TIMEOUT. |
| 2026-05-07 | `c71da9a` (v1.0.11) | Azure TIMEOUT | nft typo + /tmp 1777. Azure validation hit Read-Host hang in rollback path; verdict TIMEOUT after 45 min. Diagnosed as architectural — drove v1.0.12. |
| 2026-05-07 | `0c208ba` (v1.0.12) | Azure FAIL (clean) | Comprehensive hardening. Now fails fast (sub-2-minute FAIL with diagnostic data) on the gateway-not-binding bug instead of TIMEOUT. |
| 2026-05-07 | `e3c0b3a` (v1.0.13) | Azure FAIL | OpenClaw 2026.4.27 + /tmp 0666 + silent-rollback default. Surfaces Test-WslFunctional encoding bug + .Count unrolling bug. |
| 2026-05-07 | `028f0c7` (v1.0.14) | **Azure PASS** (first install pass; smoke FAIL) | Invoke-WslExe UTF-16-LE + .Count unrolling fix. Install + gateway both green. Smoke 7/11 fail (cause: SYSTEM-context, not source). |
| 2026-05-07 | `82ef187` (v1.0.15) | **Azure PASS, 4 cycles (3 first-try + 1 retry)** | Smoke SYSTEM detection + bundle in .iss. Stability cycles 1, 2, 3-retry all PASS. Cycle 3-original FAIL was a 5-second probe timeout while gateway alive (harness flake). |
| 2026-05-08 | `14b0001` (v1.0.16) | **Azure FAIL** (install/smoke pass, chatCompletions=404) | --strict-json patch attempted; Step-EnableChatCompletions returned exit 1 silently and no flag was written. Live VM RDP investigation pinpointed correct fix path (--json + Invoke-WslBash + gateway restart). Drove v1.0.17. |
| 2026-05-08 | `18516a6` (v1.0.17) | **Azure PASS** | First green chatCompletions probe ever. --json + Invoke-WslBash + gateway restart in $script9b. Probe HTTP 400 (route registered, model-format error downstream). Smoke 4P/0F/7S, idle 200/200 first-try. Cosmetic: Invoke-WslBash returns exit=1 even when bash hits exit 0 — false WARN, no functional impact, fix in v1.0.18. |
| 2026-05-09 | `501821a` (v1.0.18) | **Azure FAIL** | ClawChat bundle landed but upstream `openclaw.ai/install.sh` had changed hash (`57f025ba…` → `85fab092…`). [R2] correctly aborted at Step 8 — guard worked as designed. Drove v1.0.19 (pin bump) + v1.0.20 (bundled install.sh). |
| 2026-05-10 | `bee3f12` (v1.0.19) | **Azure PASS** | Hash bumped to `3a617b73…` after security review of upstream diff. cfv-119 / cfa-102 both PASS all six criteria (install + smoke + bundled-line + completions + ClawChat + idle). |
| 2026-05-10 | `86dfd36` (v1.0.20) | **Azure PASS** | install.sh now bundled as `resources\openclaw-install.sh`. Hash-verified on Windows via `Get-FileHash` before any WSL invocation; file streamed into WSL via stdin pipe (sidesteps argv limit). cfv-120 / cfa-103 both PASS. `Bundled openclaw-install.sh hash verified.` confirmed in install.log. Hash drift class eliminated. |

The smoke test script lives at [`smoke-test.ps1`](smoke-test.ps1). Re-run it on every clean-VM rebuild before tagging.

---

## Quick navigation index (read this first when debugging)

| Symptom | First check | Then |
|---|---|---|
| Install fails mid-step | Section 15.2 (`install.log` tail) | Cross-ref Section 13.1 to identify which user context and which step |
| Gateway not responding on 8787 | Section 15.7 (service unit exists?) → Section 15.9 (journalctl) | Section 18.1 for healthy unit baseline |
| Smoke test fails 7th check (auth-profiles) | Section 15.5 (per-agent auth-profiles.json) | Section 14.3 (bootstrap.ps1 fan-out) |
| `openclaw config set` fails with "path not found" | Section 17.2/17.3 (schema for 2026.4.27) | Confirm path actually exists on pinned version |
| First-launch SIGTERM / restart loop | Section 15.9 (journalctl for SIGTERM) | Section 13.4 pattern hazard list |
| Step 8b `[gateway-install] FATAL` | Section 13.3 sub-block inventory | Section 15.2 for full context |
| Drop-in conf appears missing | Section 15.8 | Section 18.5 for healthy drop-in directory contents |
| Token absent / gateway refuses connections | Section 15.4 (openclaw.json) | Section 18.2 for healthy openclaw.json shape |

---

## 13. Install Execution Map

This section maps the 15-step install flow onto user contexts, log destinations, sub-blocks, and known pattern hazards. Use it when diagnosing a failed install: figure out which user owned the failing operation, which log captured its output, and whether the failure mode matches a known hazard pattern.

### 13.1 User context per step

The installer flow lives in `setup.ps1`'s `Invoke-MainFlow` (around line 1495). Most steps run as Windows admin (PowerShell native) and shell out to WSL via `Invoke-WslBash` for Linux-side work. The `-User` parameter to `Invoke-WslBash` selects between `root` (privileged installs) and `clawuser` (per-user state).

| # | Step | Top-level context | WSL inner user | Why |
|---|---|---|---|---|
| 1 | Step-Preflight | Windows admin | n/a | Validates Windows version, admin token, internet |
| 2 | Step-EnsureWsl | Windows admin | mixed (creates clawuser as root) | Installs WSL2 + Ubuntu, may schedule reboot |
| 3 | Step-ConfigureWslConf | Windows admin | root | Writes `/etc/wsl.conf` (automount off, systemd on) |
| 4 | Step-RestartWsl | Windows admin | n/a | `wsl --shutdown` so the new wsl.conf takes effect |
| 5 | Step-CreateClawUser | Windows admin | root | Creates `clawuser`, locks the account, writes `/etc/sudoers.d/...` |
| 5b | Step-SetDefaultUser | Windows admin | root | Sets `[user] default=clawuser` in `/etc/wsl.conf` |
| 6 | Step-InstallDocker | Windows admin | root → clawuser (rootless docker) | apt-installs docker + iptables/nftables, enables rootless for clawuser |
| 7 | Step-EgressFirewall | Windows admin | root | Writes nftables config + iptables-legacy fallback, systemd unit, IP allowlist |
| 7b | Step-InstallOllama | Windows admin | root, then clawuser | Only runs when Provider=ollama; pulls llama3.1:8b |
| 8 | Step-InstallOpenClaw | Windows admin | root (`OPENCLAW_VERSION=2026.4.27 install.sh`) | SHA-256-pinned fetch of openclaw.ai/install.sh, runs as root with `HOME=/home/clawuser` so artifacts land in clawuser's dirs |
| 8b | Step-PreinstallGatewayRuntime | Windows admin | root for `$script` (sub-blocks a-i), **clawuser** for `$gatewayInstall` | Splits across two `Invoke-WslBash` calls (see 13.3). **Context switch hazard zone** — see 13.4. |
| 9 | Step-ConfigureOpenClaw | Windows admin | clawuser | `openclaw config set` for gateway.bind/port/mode + per-provider auth profile |
| 10 | Step-CreateAgentDirectories | Windows admin | clawuser | Pre-creates 4 agent workspace dirs |
| 11 | Step-ApplySafetyRules | Windows admin | clawuser | Writes `~/.openclaw/SOUL.md` + sha256 sidecar (mode 444) |
| 12 | Step-WireProviderKey | Windows admin | clawuser | Writes `~/.openclaw/auth-profiles.json` (mode 600) with API key from DPAPI |
| 13 | Step-WindowsFirewallDeny | Windows admin | n/a | `Get/New-NetFirewallRule` — Windows-only |
| 14 | Step-PostInstall | Windows admin | clawuser | Runs `resources/post-install.ps1`: doctor health check + bonjour drop-in + restart |
| 15 | Step-ConfigureAgents | Windows admin | clawuser | Runs `resources/bootstrap.ps1`: writes 4 agent.md files + auth-profiles fan-out |

### 13.2 Logs and their owners

| Path | Owner / mode | Writer | When created | Purpose |
|---|---|---|---|---|
| `C:\ProgramData\ClawFactory\install.log` | Windows: SYSTEM (admin-readable) | `Write-Log` in setup.ps1; `Log` in post-install.ps1 / bootstrap.ps1 | Step 1 | Master install log. Captures all PowerShell `Log`/`Write-Log` calls AND all stdout/stderr from `Invoke-WslBash` (via `ForEach-Object { Log $_ }`). **Source of truth** for diagnosing Linux-side WSL output too. |
| `C:\ProgramData\ClawFactory\checkpoint.json` | Windows: SYSTEM | `Save-Checkpoint` | Step 1 | JSON `{"completedSteps": [...]}`. Each step appends its name on success. Used by `-Resume` to skip completed steps after WSL reboot. |
| `C:\ProgramData\ClawFactory\provider.json` | Windows: SYSTEM | setup.ps1 main flow | Step 1 | Records selected provider + timestamp. Read by switch-provider.ps1 / post-install.ps1. |
| `C:\ProgramData\ClawFactory\launcher.log` | Windows: user-writable | launcher.ps1 | First desktop-shortcut click | One-line-per-launch log: `STARTED` / `ALREADY_RUNNING` / `TIMEOUT`. |
| `C:\ProgramData\ClawFactory\resume-after-restart.flag` | Windows: SYSTEM | setup.ps1 if WSL install needed reboot | Pre-restart only | JSON `{"provider": "...", ...}`. Deleted on completion. Read by Inno Setup `[Code]` `ReadResumeProvider` if `/resume`. |
| `/tmp/openclaw-install.log` (Linux) | root:root, mode 644 (created by Step 8 install.sh as root) | install.sh | Step 8 | **Stale post-tee-fix.** Was used as install.sh tee target. Output now flows only through Windows install.log. May still receive failed tee writes from sub-block daemon-reload/enable/restart (with `\|\| true` masking the failures). |
| `/home/clawuser/.openclaw/logs/` (Linux) | clawuser:clawuser, mode 700 | openclaw runtime | Step 8b | Reserved for openclaw's own runtime logs. The canonical install command does not write here directly. |
| `journalctl --user -u openclaw-gateway` (Linux) | systemd-journald | systemd | Step 8b once unit installed | **Authoritative log** for gateway service lifecycle (start, restart, crash, exit codes). First place to look for runtime issues post-install. |

### 13.3 Step 8b sub-block inventory

Step 8b (`Step-PreinstallGatewayRuntime`) splits into two `Invoke-WslBash` calls:

| Sub-block | Purpose | User | Exit-code-critical? |
|---|---|---|---|
| `$script` (a) — Core runtime npm pre-install | `npm install` core deps in `~/.openclaw/plugin-runtime-deps/openclaw-*/` | root | No — failures logged, install continues |
| `$script` (b) — Bundled plugin npm pre-install | `npm install` per-plugin deps in `dist/extensions/<n>/.openclaw-install-stage/` | root | No — `tail -2 \|\| echo "(warn) ..."` swallows |
| `$script` (c) — `clawfactory-tunables.conf` drop-in | Writes `TimeoutStartSec=infinity` to `~/.config/systemd/user/openclaw-gateway.service.d/` | root | No — file write only |
| `$script` (d) — Per-agent auth-profiles seeding | Copies `~/.openclaw/auth-profiles.json` → `~/.openclaw/agents/<n>/agent/auth-profiles.json` (no-op since the source file isn't written until Step 12) | root | No — guarded by `[ -f ... ]` |
| `$script` (e) — `loginctl enable-linger clawuser` | Allows user-systemd to survive WSL session close | root | No — `\|\| true` |
| `$script` (f) — Auxiliary IPs into firewall allowlist | nft / iptables-legacy `add element` for provider auth/registry hosts | root | No — graceful per backend |
| `$script` (g) — Allow-providers refresh systemd timer | Writes `clawfactory-allow-providers.{service,timer}` + script | root | No — `\|\| true` on enable |
| `$script` (h) — Default `main` agent.md | Writes provider-aware `agent.md` for the main agent if dir exists and file missing | root | No — guarded |
| `$script` (i) — chown back to clawuser | Recursive chown of `~/.openclaw`, drop-in dir, extensions dir | root | No |
| `$gatewayInstall` (1) — `openclaw gateway install --force --port 8787` | Canonical install; auto-generates token, writes systemd unit | **clawuser** | **YES** — `rc=$?` captured, hard-fail on non-zero (PowerShell `throw`) |
| `$gatewayInstall` (2) — daemon-reload + enable + restart + sleep 5 + is-active poll | Per #65184 race-condition fix; gives unit ~17s to bind | clawuser | No — `\|\| true` masks each step; final exit 0 even if poll never sees `active` |

**Context-switch hazard**: anything `$script` (root) writes to a Linux path used by `$gatewayInstall` (clawuser) needs explicit chown. Sub-block (i) handles this for the directories listed; **`/tmp/*` files written as root in Step 8 do not get chowned** — that's the bug class fixed in the May 1 tee-removal commit.

### 13.4 Pattern hazard list

| Pattern | Where in current code | Status | Defense-in-depth |
|---|---|---|---|
| **tee-as-pipe-tail trap** (`cmd \| tee file` → `$?` is tee's exit, not cmd's; PIPESTATUS or process substitution required) | Fixed for the install command at setup.ps1:1180-1182. Three remaining instances at setup.ps1:1189/1192/1195 are wrapped in `\|\| true`, so exit code masking is intentional. | Fixed (load-bearing case) | Use `cmd 2>&1 > >(tee file) 2>&1` or `set -o pipefail` + `${PIPESTATUS[0]}` when exit code matters. |
| **Permission asymmetry on /tmp** (file created by root in Step N can't be appended-to by clawuser in Step N+1) | Source of the May 1 tee bug. Remaining `\|\| true`-wrapped tees at setup.ps1:1189/1192/1195 silently fail; their output is captured by Windows-side install.log instead. | Mitigated | Either `chown` /tmp files at end of root-context blocks, or write logs to clawuser-owned dirs (`~/.openclaw/logs/`), or rely entirely on the Windows-side capture. |
| **`--non-interactive` skip-on-prompt** (openclaw doctor `--non-interactive` skips operations needing confirmation, including systemd unit install — exits 1 in ~1s on fresh state) | Replaced in commit 5777d1c by `yes \| timeout … openclaw doctor --fix --yes` | Fixed | If a future doctor variant adds new prompts, the `yes` pipe still answers all of them. |
| **doctor-as-installer** (relying on `openclaw doctor` to install the systemd unit; doctor only repairs existing state, doesn't bootstrap) | Replaced in commit a10a4a6 by `openclaw gateway install --force --port 8787` as the canonical entry point | Fixed | Use the documented install command, treat doctor purely as a final health check. |
| **Step-name churn** (sub-blocks within a function evolve over time, but the function name and Step-NN comment header drift apart) | Step 8b currently has 9 sub-blocks (a-i + the two-phase gateway install) | Acceptable | Section 13.3 above is the source of truth. |
| **Stale comments after refactor** | Mostly cleaned in commit a10a4a6; minor stale strings (`config-set`, `fix bundle`) noted in v1.1 backlog | Acceptable | This document is the canonical reference; treat in-source comments as advisory. |

---

## 14. Code Interconnect Map

Each PowerShell script in the installer flow + post-install + ongoing-operations scripts. Read this when changing a script to understand who depends on its outputs (and on what state) and who changes the state it later reads.

### 14.1 setup.ps1

**Preconditions**: Windows 11 22H2+, admin token, internet, ≥8 GB free on `%SystemDrive%`. Run with `-AcknowledgedOpenClawUrl -Provider <name> -SourceExe <path> [-Resume]`. Inno Setup `[Run]` provides these; standalone invocation possible for re-runs.

**User context**: Windows admin throughout. Each step that touches Linux state shells out via `Invoke-WslBash -User <root|clawuser>`.

**Outputs / side effects**:
- WSL2 + Ubuntu installed and configured (steps 2-5b)
- `clawuser` Linux account, locked, default WSL user (steps 5-5b)
- Docker rootless for clawuser (step 6)
- nftables / iptables-legacy egress firewall (step 7)
- Optional Ollama (step 7b)
- OpenClaw npm package pinned to 2026.4.27 (step 8)
- OpenClaw gateway systemd user service + token + drop-ins (step 8b)
- `~/.openclaw/openclaw.json` populated with gateway.bind/port/mode + auth profile metadata (step 9)
- 4 empty agent workspace dirs (step 10)
- `~/.openclaw/SOUL.md` (mode 444) + sha256 (step 11)
- `~/.openclaw/auth-profiles.json` (mode 600) with API key from DPAPI (step 12)
- Windows Firewall inbound-deny rule on TCP/8787 (step 13)
- `%ProgramData%\ClawFactory\install.log`, `checkpoint.json`, `provider.json` (continuous)

**Downstream consumers**:
- `resources/post-install.ps1` (run by step 14)
- `resources/bootstrap.ps1` (run by step 15)
- `resources/launcher.ps1` (desktop shortcut, post-install)
- `resources/clawfactory-stop.ps1` (Start Menu, post-install)
- `resources/switch-provider.ps1` (Start Menu, post-install)

**State files**: writes/reads `checkpoint.json`, `provider.json`, `resume-after-restart.flag`; writes `install.log`; writes Linux `~/.openclaw/openclaw.json`, `~/.openclaw/auth-profiles.json`, `~/.openclaw/SOUL.md`, `~/.config/systemd/user/openclaw-gateway.service.d/clawfactory-tunables.conf`.

### 14.2 resources/post-install.ps1

**Preconditions**: All of setup.ps1 steps 1-13 completed. `~/.openclaw/auth-profiles.json` already exists for non-`ollama`/`later` providers (written by step 12). systemd-user available OR fallback path (3-tier) usable.

**User context**: Windows admin top-level. WSL operations as `clawuser`.

**Outputs / side effects**:
1. Reads provider key from Windows Credential Manager (DPAPI) to verify presence — does NOT re-wire it (step 12 already did).
2. `openclaw models set "<prefix>/<model>"` — writes default model id into `~/.openclaw/openclaw.json`.
3. **FIX 3 (doctor)**: `yes | timeout … openclaw doctor --fix --yes` — health check; non-zero exit logs WARN, install continues.
4. **FIX 1 (bonjour drop-in)**: writes `~/.config/systemd/user/openclaw-gateway.service.d/clawfactory-disable-bonjour.conf` with `Environment=OPENCLAW_DISABLE_BONJOUR=1`. Defense-in-depth.
5. avahi-daemon restart (no-op if avahi not installed).
6. **Restart and verify**: 3-tier gateway start (systemd → `openclaw gateway start` → `nohup setsid openclaw gateway run`), polls `127.0.0.1:8787/status` for ≤60s.

**Downstream consumers**: bootstrap.ps1 reads `~/.openclaw/auth-profiles.json` to fan out per-agent; smoke-test.ps1 verifies gateway responds.

**State files**: reads `Credential Manager`, `~/.openclaw/openclaw.json`; writes `~/.config/systemd/user/openclaw-gateway.service.d/clawfactory-disable-bonjour.conf`, restarts `openclaw-gateway.service`.

### 14.3 resources/bootstrap.ps1

**Preconditions**: setup.ps1 step 14 has completed; gateway is or recently was running; `~/.openclaw/agents/<id>/` directories exist (created by step 10); `~/.openclaw/SOUL.md.sha256` exists (step 11).

**User context**: Windows admin top-level. WSL operations as `clawuser` via its own `Invoke-WslBash`.

**Outputs / side effects**:
1. `Write-DefaultAgentName` — writes `%ProgramData%\ClawFactory\agent-name.txt` with default `Claw` (only if file absent).
2. `Get-SoulSha256` — reads `~/.openclaw/SOUL.md.sha256` to substitute into orchestrator prompt.
3. For each of `orchestrator`, `skill-scout`, `skill-builder`, `publisher`: writes `~/.openclaw/agents/<n>/agent.md` (mode 644) atomically (tmp + mv).
4. **FIX 4 — auth-profiles fan-out**: for each of `main`, `orchestrator`, `publisher`, `skill-builder`, `skill-scout`: copies `~/.openclaw/auth-profiles.json` → `~/.openclaw/agents/<id>/agent/auth-profiles.json` (mode 600). Graceful skip when source absent (Provider=later).
5. Appends `AgentBootstrap` to `checkpoint.json`.
6. Prints next-steps banner.

**Downstream consumers**: openclaw runtime reads per-agent auth-profiles.json; smoke-test.ps1's 7th check verifies all 5 fan-out targets exist with mode 600.

**State files**: reads `SOUL.md.sha256`, `auth-profiles.json`; writes 4× `agent.md`, 5× per-agent `auth-profiles.json`, `agent-name.txt`, `checkpoint.json`.

### 14.4 resources/launcher.ps1

**Preconditions**: install completed, gateway service unit exists. Run by desktop shortcut as Windows user (not admin).

**User context**: Windows user (no admin). WSL operations as `clawuser`.

**Outputs / side effects**:
1. HTTP-probes `127.0.0.1:8787/status`. If 200, opens chat in Windows Terminal (or PowerShell fallback) and exits.
2. If not responding, calls `Start-Gateway` (3-tier fallback: systemd → `openclaw gateway start` → `nohup setsid openclaw gateway run`).
3. Polls `/status` for `$TimeoutSec` seconds (default 15s). On 200, opens chat. On timeout, shows failure dialog.
4. Logs `STARTED` / `ALREADY_RUNNING` / `TIMEOUT` to `%ProgramData%\ClawFactory\launcher.log`.

**State files**: writes `launcher.log`. No state changes to openclaw config.

### 14.5 resources/switch-provider.ps1

**Preconditions**: install completed, run as admin (it modifies firewall rules). Provider name passed as parameter.

**User context**: Windows admin. WSL operations as `clawuser` and `root`.

**Outputs / side effects**:
1. Stores new API key in Credential Manager via `cmdkey`.
2. For Ollama: ensures Ollama is installed and pulls the default model.
3. Updates nftables allowlist (flush + re-resolve provider hosts).
4. Updates `~/skills-factory/openclaw.json` via python3 — **see known issues note in v1.1 backlog (M4-M6)**.

**State files**: writes Credential Manager, nftables ruleset, openclaw.json (currently to wrong path).

### 14.6 resources/clawfactory-stop.ps1

**Preconditions**: openclaw runtime exists in WSL. Optional admin (kill-only operations).

**User context**: Windows user. WSL operations as `clawuser`.

**Outputs / side effects**:
1. `docker kill` all containers labeled `clawfactory=1`.
2. `openclaw gateway stop` (graceful).

**State files**: none — stops processes only.

### 14.7 resources/rename-agent.ps1

**Preconditions**: install completed.

**User context**: Windows user. No WSL ops.

**Outputs / side effects**: shows an explanation MessageBox; performs no rename in factory variant. Full rename ships in the planned single-agent variant.

**State files**: none.

### 14.8 smoke-test.ps1

**Preconditions**: install completed on a clean VM.

**User context**: Windows admin. WSL operations as `clawuser`.

**Outputs / side effects**: 19 checks. Original 11: WSL automount disabled, four agent.md files present, AgentBootstrap checkpoint, gateway 200, firewall inbound-deny, SOUL hash substituted, all-5-agents auth-profiles, `.wslconfig` vmIdleTimeout=-1, WSL Host scheduled task, egress-firewall nft chain, OpenClaw build deps. Plus 8 added in v1.1 (Phase 1 Grants): grants library present, workspace mount-after-grant, deny-list rejects `C:\`, Kill Switch unmounts but keeps grant active, replay remounts after loss, mount gone after revoke, governor meter numeric+state≠unknown, governor turn-gate blocks at cap=0. (Count history: 7 at v1.0.x → 11 by v1.0.15 → 19 at v1.1.) Exits with `$fail` count; `-RequiresWsl` checks SKIP (not FAIL) under SYSTEM.

**State files**: read-only verification; layered gateway-start helper may start the gateway as a side effect.

### 14.9 Pipeline summary

```
Inno Setup .iss
   └─ runs setup.ps1
       ├─ checkpoint.json (continuous)
       ├─ install.log (continuous)
       ├─ Linux state under /home/clawuser/.openclaw/
       └─ runs (step 14) post-install.ps1 → doctor health check + bonjour drop-in + restart
           └─ runs (step 15) bootstrap.ps1 → 4 agent.md + 5 auth-profiles fan-out + AgentBootstrap checkpoint
              ↓
           ────────────────────────────────────
           Post-install operational scripts:
              • launcher.ps1   (desktop shortcut)
              • clawfactory-stop.ps1   (kill switch)
              • switch-provider.ps1    (provider change)
              • rename-agent.ps1   (rename UX)
           ────────────────────────────────────
              ↓
           smoke-test.ps1 (verification on a clean VM)
```

---

## 15. Diagnostic Quick Reference

For each location: where it lives, who owns it, what it should look like when healthy, what failure looks like, and how to inspect it. Order: file paths first, then runtime introspection commands, then OpenClaw source navigation.

### 15.1 /tmp/openclaw-install.log

- **Path**: `/tmp/openclaw-install.log` (inside WSL Ubuntu)
- **Owner**: root:root, mode 644 (created by Step 8 install.sh as root). Post-tee-fix, may not be created at all on fresh installs that skip the install.sh tee.
- **Contains**: tee-output of install.sh (when populated by Step 8). May also receive failed tee writes from setup.ps1 Step 8b sub-blocks (silently swallowed via `|| true`).
- **Healthy state**: present after Step 8 with install.sh output; final lines say `[gateway-preinstall] complete`. Post-fix, install.sh tee is the only writer.
- **Unhealthy**: absent (Step 8 never ran), or contains permission errors from Step 8b's downstream tees (cosmetic; output is in Windows install.log).
- **Inspect**: `wsl -d Ubuntu -u clawuser -- bash -lc 'tail -100 /tmp/openclaw-install.log'`
- **Common failure modes**:
  - File owned by root, clawuser appends fail with "Permission denied" (load-bearing case fixed May 1; remaining cases mitigated by `|| true`)
  - File doesn't exist (Step 8 skipped)
  - SHA-256 mismatch error visible from install.sh

### 15.2 C:\ProgramData\ClawFactory\install.log

- **Path**: `C:\ProgramData\ClawFactory\install.log`
- **Owner**: SYSTEM-writable, admin-readable (Windows ACLs)
- **Contains**: master log of the entire install. Every PowerShell `Log` / `Write-Log` call AND every line of stdout/stderr from `Invoke-WslBash` (via `ForEach-Object { Log $_ }`). Captures all WSL output even when Linux-side log files aren't accessible.
- **Healthy state**: ends with `[INFO] ==== ClawFactory Secure Setup - completed successfully ====`.
- **Unhealthy**: ends mid-step (script aborted), or shows `[ERROR]` lines, or has long gaps between timestamps.
- **Inspect**: `Get-Content "$env:ProgramData\ClawFactory\install.log" -Tail 100`
- **Common failure modes**:
  - Step 8 OpenClaw install timed out (check for "exit 124" or "exit 137")
  - Step 8b gateway install failed (check for FATAL openclaw gateway install)
  - WSL not ready post-resume (check Step 2 / Step 4 region)

### 15.3 C:\ProgramData\ClawFactory\checkpoint.json

- **Path**: `C:\ProgramData\ClawFactory\checkpoint.json`
- **Owner**: SYSTEM
- **Contains**: `{"completedSteps": ["Preflight", "EnsureWsl", ..., "AgentBootstrap"]}` — 16 entries on a clean full run.
- **Healthy state**: contains all of: `Preflight`, `EnsureWsl`, `WslConf`, `RestartWsl`, `ClawUser`, `DefaultUser`, `Docker`, `EgressFirewall`, `Ollama` (only if Provider=ollama), `OpenClaw`, `GatewayRuntime`, `OpenClawConfig`, `AgentDirs`, `SafetyRules`, `ProviderKey`, `WindowsFirewall`, `PostInstall`, `AgentBootstrap`.
- **Unhealthy**: missing `AgentBootstrap` (smoke-test will fail this check); missing `GatewayRuntime` (Step 8b never finished).
- **Inspect**: `Get-Content "$env:ProgramData\ClawFactory\checkpoint.json" | ConvertFrom-Json | Select-Object -ExpandProperty completedSteps`
- **Common failure modes**:
  - Stale from a partial install (`-Resume` will skip already-completed steps)
  - Missing checkpoint dir (step 1 didn't run)

### 15.4 ~/.openclaw/openclaw.json

- **Path**: `/home/clawuser/.openclaw/openclaw.json`
- **Owner**: clawuser:clawuser, mode 600
- **Contains**: gateway config (bind/port/mode/auth.token), auth profiles, default model, plugin entries.
- **Healthy state**: `gateway.bind = "loopback"`, `gateway.port = 8787`, `gateway.mode = "local"`, `gateway.auth.mode = "token"`, `gateway.auth.token` populated, `agents.defaults.model.primary` set to selected provider's default.
- **Unhealthy**: missing `gateway.auth.token` (gateway install didn't run); missing `agents.defaults.model.primary` (post-install didn't run); plugin `tavily.enabled = true` with placeholder API key (likely from a manual test — replace before shipping).
- **Inspect**: `wsl -d Ubuntu -u clawuser -- bash -lc 'cat ~/.openclaw/openclaw.json | head -40'`
- **Common failure modes**:
  - Token absent → gateway never started
  - `config-set "path not found"` errors during install (FIX 2 removed addresses this — schema paths absent on 2026.4.27)

### 15.5 ~/.openclaw/auth-profiles.json (and per-agent variants)

- **Path**: `/home/clawuser/.openclaw/auth-profiles.json` (legacy/global), `/home/clawuser/.openclaw/agents/<n>/agent/auth-profiles.json` (per-agent canonical)
- **Owner**: clawuser:clawuser, mode 600
- **Contains**: provider auth metadata (provider name, mode=`api_key`, displayName, key reference).
- **Healthy state**: global file exists (written Step 12); 5 per-agent copies exist post-bootstrap.ps1 fan-out.
- **Unhealthy**: only global exists, not per-agent → openclaw runtime can't find keys (FIX 4 fan-out failed).
- **Inspect**: `wsl -d Ubuntu -u clawuser -- bash -lc 'ls -la ~/.openclaw/auth-profiles.json ~/.openclaw/agents/*/agent/auth-profiles.json'`
- **Common failure modes**:
  - Mode 644 instead of 600 (smoke-test 7th check fails)
  - Source missing for Provider=later case (graceful skip in bootstrap.ps1)

### 15.6 ~/.openclaw/agents/<name>/agent.md

- **Path**: `/home/clawuser/.openclaw/agents/{orchestrator,skill-scout,skill-builder,publisher}/agent.md` (4 files)
- **Owner**: clawuser:clawuser, mode 644
- **Contains**: per-agent role prompt with `{{SOUL_SHA256}}` substituted (orchestrator only). Body is the role's responsibilities + safety boundaries.
- **Healthy state**: 4 files, ≥1 KB each. Orchestrator's SOUL hash substituted (literal `{{SOUL_SHA256}}` token absent).
- **Unhealthy**: any of the 4 missing or 0 bytes; orchestrator still contains `{{SOUL_SHA256}}` placeholder.
- **Inspect**: `wsl -d Ubuntu -u clawuser -- bash -lc 'wc -c ~/.openclaw/agents/*/agent.md && grep -l "{{SOUL_SHA256}}" ~/.openclaw/agents/orchestrator/agent.md && echo BAD || echo OK'`
- **Common failure modes**:
  - Step 11 didn't write SOUL.md.sha256 → bootstrap can't substitute (intentional fail-loudly)
  - Resource file missing in installer build → bootstrap.ps1 writes a placeholder.

### 15.7 ~/.config/systemd/user/openclaw-gateway.service

- **Path**: `/home/clawuser/.config/systemd/user/openclaw-gateway.service`
- **Owner**: clawuser:clawuser, mode 644
- **Contains**: systemd user unit. `ExecStart=/usr/bin/node /usr/lib/node_modules/openclaw/dist/index.js gateway --port 8787`. Default `TimeoutStartSec=30`, `Restart=always`, env vars including `OPENCLAW_GATEWAY_PORT=8787`.
- **Healthy state**: file present, ≈900-1100 bytes, `systemctl --user is-enabled openclaw-gateway.service` returns `enabled`.
- **Unhealthy**: file absent → `openclaw gateway install --force` never ran or failed.
- **Inspect**: `wsl -d Ubuntu -u clawuser -- bash -lc 'cat ~/.config/systemd/user/openclaw-gateway.service'`
- **Common failure modes**:
  - File absent (Step 8b failed)
  - Stale ExecStart pointing to an old openclaw version (re-run `openclaw gateway install --force`)

### 15.8 ~/.config/systemd/user/openclaw-gateway.service.d/clawfactory-tunables.conf

- **Path**: `/home/clawuser/.config/systemd/user/openclaw-gateway.service.d/clawfactory-tunables.conf`
- **Owner**: clawuser:clawuser, mode 644
- **Contains**: `[Service] / TimeoutStartSec=infinity` — drop-in override for the parent unit's 30s timeout.
- **Healthy state**: file present, drop-in dir contains both `clawfactory-tunables.conf` (TimeoutStartSec) and `clawfactory-disable-bonjour.conf` (Environment=OPENCLAW_DISABLE_BONJOUR=1).
- **Unhealthy**: drop-in dir absent or empty → first-boot may SIGTERM mid-init.
- **Inspect**: `wsl -d Ubuntu -u clawuser -- bash -lc 'ls -la ~/.config/systemd/user/openclaw-gateway.service.d/ && cat ~/.config/systemd/user/openclaw-gateway.service.d/*.conf'`
- **Common failure modes**:
  - openclaw upgrade re-creates the unit; drop-ins still apply (systemd auto-merges).
  - Manual `openclaw gateway install --force` may write its own drop-in (e.g. `insecure-loopback.conf`); coexists with ours.

### 15.9 journalctl --user -u openclaw-gateway

- **Owner**: systemd-journald
- **Contains**: gateway service stdout, stderr, lifecycle events (start, stop, restart, exit codes).
- **Healthy state**: most recent entries show `Started ... gateway on port 8787` and no `Main process exited` records since.
- **Unhealthy**: repeated `Main process exited, code=killed, status=15/TERM` followed by restart cycles → bonjour SIGTERM bug fired (FIX 1's drop-in should prevent on 2026.4.27, but verify).
- **Inspect**: `wsl -d Ubuntu -u clawuser -- bash -lc 'journalctl --user -u openclaw-gateway -n 100 --no-pager'`
- **Common failure modes**:
  - `failed to bind 0.0.0.0:8787` — another process on the port
  - `No API key found for provider 'openai'` — FIX 4 auth-profiles fan-out missed an agent

### 15.10 Windows Firewall rule "ClawFactory-Block-Inbound-8787"

- **Owner**: Windows Defender Firewall
- **Contains**: inbound-deny rule for TCP/8787, scope=any, action=Block.
- **Healthy state**: `(Get-NetFirewallRule -DisplayName 'ClawFactory-Block-Inbound-8787').Enabled = 'True'` and `.Action = 'Block'`.
- **Unhealthy**: rule missing → LAN can reach the gateway. Rule disabled → same.
- **Inspect**: `Get-NetFirewallRule -DisplayName 'ClawFactory-Block-Inbound-8787' | Format-List`
- **Common failure modes**:
  - Rule deleted by manual cleanup
  - Antivirus / endpoint-protection product overwriting Windows Firewall rules

### 15.11 OpenClaw source navigation

OpenClaw lives at `/usr/lib/node_modules/openclaw/` inside WSL (installed by `install.sh` as a global npm package). Key directories:

| Path | Contents |
|---|---|
| `/usr/lib/node_modules/openclaw/dist/index.js` | CLI entry point. `ExecStart` of the gateway unit. |
| `/usr/lib/node_modules/openclaw/dist/cli/` | Per-command implementations (`config.js`, `gateway.js`, `agents.js`, `doctor.js`, ...) |
| `/usr/lib/node_modules/openclaw/dist/extensions/<plugin>/` | Bundled plugins (anthropic, openai, browser, codex, ...). Each has `index.js` and `openclaw.plugin.json`. |
| `/usr/lib/node_modules/openclaw/dist/bonjour-discovery-*.js` | Bonjour mDNS code (the bug source — disabled via env var on 2026.4.27). |
| `/usr/lib/node_modules/openclaw/openclaw.mjs` | Symlinked from `/usr/bin/openclaw`. |
| `/usr/lib/node_modules/openclaw/package.json` | Pinned version: 2026.4.27. |

Grep recipes (run inside WSL as clawuser):

```bash
# Find which file implements a subcommand, e.g. `openclaw gateway install`:
grep -rl "gateway install" /usr/lib/node_modules/openclaw/dist/cli/

# Find a config schema path's implementation:
grep -rn "discovery.mdns" /usr/lib/node_modules/openclaw/dist/

# List all subcommands defined in dist/cli/:
ls /usr/lib/node_modules/openclaw/dist/cli/

# Find env-var consumers (e.g. who reads OPENCLAW_DISABLE_BONJOUR):
grep -rn "OPENCLAW_DISABLE_BONJOUR" /usr/lib/node_modules/openclaw/dist/
```

Re-read after every `OPENCLAW_VERSION` pin bump — paths and command names can shift between minor versions.

---

## 16. Inno Setup Script Reference

`ClawFactory-Secure-Setup.iss` is the Inno Setup 6 script that compiles the installer `.exe`. It bundles all source files into a single executable, defines the wizard pages (welcome, provider radio, API key prompt, security acknowledgement), shells out to `setup.ps1` to do the actual work, and registers Start Menu / desktop shortcuts. The `[Code]` section is Pascal-like Inno script that handles the `/resume` flag (post-WSL-reboot relaunch), the per-provider "Get your API key" button, API-key capture into Windows Credential Manager via `cmdkey`, and conditional page-skipping for non-key-requiring providers.

```ini
; ClawFactory Secure Setup - Inno Setup 6 script
; Builds a hardened OpenClaw Skills Factory on Windows 11.
; Compile with: "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" ClawFactory-Secure-Setup.iss

#define MyAppName      "ClawFactory Secure Setup"
#define MyAppVersion   "1.0.0"
#define MyAppPublisher "Frontier Automation Systems LLC"
#define MyAppURL       "https://openclaw.ai"

[Setup]
; [R1] Fixed AppId for stable upgrade/uninstall identity. Do not regenerate.
AppId={{8D7C4B2A-4F1E-4B5C-9D3E-CF7A6B2E1A90}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
PrivilegesRequired=admin
ArchitecturesInstallIn64BitMode=x64compatible
ArchitecturesAllowed=x64compatible
DefaultDirName={autopf}\ClawFactory
DefaultGroupName=ClawFactory
OutputBaseFilename=ClawFactory-Secure-Setup
OutputDir=Output
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
DisableProgramGroupPage=yes
DisableReadyPage=no
UninstallDisplayIcon={app}\resources\lobster.ico
; [R1] Uncomment after configuring a SignTool via Tools > Configure Sign Tools in the IDE.
; SignTool=signtool

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Files]
Source: "setup.ps1";                         DestDir: "{app}";            Flags: ignoreversion
Source: "README.md";                         DestDir: "{app}";            Flags: ignoreversion
Source: "LICENSE";                           DestDir: "{app}";            Flags: ignoreversion
Source: "resources\safety-rules.md";         DestDir: "{app}\resources";  Flags: ignoreversion
Source: "resources\orchestrator-prompt.md";  DestDir: "{app}\resources";  Flags: ignoreversion
Source: "resources\post-install.ps1";        DestDir: "{app}\resources";  Flags: ignoreversion
Source: "resources\bootstrap.ps1";           DestDir: "{app}\resources";  Flags: ignoreversion
Source: "resources\rename-agent.ps1";        DestDir: "{app}\resources";  Flags: ignoreversion
Source: "resources\launcher.ps1";            DestDir: "{app}\resources";  Flags: ignoreversion
Source: "resources\clawfactory-stop.ps1";    DestDir: "{app}\resources";  Flags: ignoreversion
Source: "resources\switch-provider.ps1";     DestDir: "{app}\resources";  Flags: ignoreversion
Source: "resources\logo.png";                DestDir: "{app}\resources";  Flags: ignoreversion
Source: "resources\logo.README.txt";         DestDir: "{app}\resources";  Flags: ignoreversion
Source: "resources\lobster.ico";             DestDir: "{app}\resources";  Flags: ignoreversion

[Run]
; [R5] No API key on the command line - setup.ps1 reads from Windows Credential Manager.
Filename: "powershell.exe"; \
  Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\setup.ps1"" -AcknowledgedOpenClawUrl -Provider {code:GetProviderLabel} -SourceExe ""{srcexe}""{code:GetResumeFlag}"; \
  WorkingDir: "{app}"; \
  StatusMsg: "{code:GetStatusMsg}"; \
  Flags: waituntilterminated

[UninstallRun]
Filename: "powershell.exe"; \
  Parameters: "-NoProfile -ExecutionPolicy Bypass -Command ""if ((Read-Host 'Remove Ubuntu WSL distro, skills-factory workspace, and all provider credentials? [y/N]') -eq 'y') {{ wsl --unregister Ubuntu; cmdkey /delete:ClawFactory/GrokApiKey 2>$null; cmdkey /delete:ClawFactory/OpenAIApiKey 2>$null; cmdkey /delete:ClawFactory/AnthropicApiKey 2>$null; cmdkey /delete:ClawFactory/GeminiApiKey 2>$null; Remove-NetFirewallRule -DisplayName 'ClawFactory-Block-Inbound-8787' -ErrorAction SilentlyContinue }}"""; \
  RunOnceId: "ClawFactoryCleanup"; \
  Flags: runhidden

[Icons]
Name: "{commondesktop}\ClawFactory"; Filename: "powershell.exe"; \
  Parameters: "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""{app}\resources\launcher.ps1"""; \
  WorkingDir: "{app}"; IconFilename: "{app}\resources\lobster.ico"; Comment: "Open ClawFactory"
Name: "{group}\ClawFactory Kill Switch"; Filename: "powershell.exe"; \
  Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\resources\clawfactory-stop.ps1"""; \
  WorkingDir: "{app}"; Comment: "Emergency stop: kills all ClawFactory agent containers"
Name: "{group}\ClawFactory Dashboard"; Filename: "{sys}\cmd.exe"; \
  Parameters: "/c start http://127.0.0.1:8787"; WorkingDir: "{app}"; \
  Comment: "Open ClawFactory dashboard in browser (gateway must be running)"
Name: "{group}\Rename Your Assistant"; Filename: "powershell.exe"; \
  Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\resources\rename-agent.ps1"""; \
  WorkingDir: "{app}"; Comment: "Rename your assistant (factory mode shows an explanation; full rename ships in the single-agent variant)"
Name: "{group}\Switch AI Provider"; Filename: "powershell.exe"; \
  Parameters: "-NoProfile -ExecutionPolicy Bypass -NoExit -File ""{app}\resources\switch-provider.ps1"""; \
  WorkingDir: "{app}"; Comment: "Change provider (Grok / OpenAI / Claude / Gemini / Ollama) after install"
Name: "{group}\ClawFactory README"; Filename: "{app}\README.md"
Name: "{group}\Uninstall ClawFactory"; Filename: "{uninstallexe}"

[Code]
var
  WelcomePage:    TOutputMsgWizardPage;
  ProviderPage:   TInputOptionWizardPage;
  ApiKeyPage:     TInputQueryWizardPage;
  ApiKeyLaterChk: TNewCheckBox;
  GetKeyButton:   TNewButton;
  AckPage:        TInputOptionWizardPage;
  IsResumeRun:    Boolean;
  ResumeProvider: string;

function ResumeFlagPath: string;
begin
  Result := ExpandConstant('{commonappdata}\ClawFactory\resume-after-restart.flag');
end;

function HasCmdLineSwitch(const SwitchName: string): Boolean;
var i: Integer;
begin
  Result := False;
  for i := 1 to ParamCount do
    if CompareText(ParamStr(i), SwitchName) = 0 then begin Result := True; exit; end;
end;

{ Naive scan for "provider": "<value>" in the JSON resume flag (no JSON parser
  available in Inno's [Code] dialect; the flag has a known shape so a scan is safe). }
function ReadResumeProvider: string;
var Content: AnsiString; Tail: string; P, Q: Integer;
begin
  Result := 'grok';
  if not LoadStringFromFile(ResumeFlagPath, Content) then exit;
  Tail := string(Content);
  P := Pos('"provider"', Tail); if P = 0 then exit;
  Tail := Copy(Tail, P + Length('"provider"'), MaxInt);
  P := Pos(':', Tail); if P = 0 then exit;
  Tail := Copy(Tail, P + 1, MaxInt);
  P := Pos('"', Tail); if P = 0 then exit;
  Tail := Copy(Tail, P + 1, MaxInt);
  Q := Pos('"', Tail); if Q = 0 then exit;
  Result := Copy(Tail, 1, Q - 1);
end;

function GetProviderLabel(Param: string): string;
begin
  if IsResumeRun then begin Result := ResumeProvider; exit; end;
  case ProviderPage.SelectedValueIndex of
    0: Result := 'grok'; 1: Result := 'openai'; 2: Result := 'claude';
    3: Result := 'gemini'; 4: Result := 'ollama'; 5: Result := 'later';
  else Result := 'grok';
  end;
end;

function GetResumeFlag(Param: string): string;
begin if IsResumeRun then Result := ' -Resume' else Result := ''; end;

function GetStatusMsg(Param: string): string;
begin
  if IsResumeRun then Result := 'Resuming installation after restart...'
  else Result := 'Building your hardened OpenClaw Skills Factory (10-20 minutes)...';
end;

function ProviderNeedsApiKey: Boolean;
begin Result := (ProviderPage.SelectedValueIndex <= 3); end;

function ProviderCredentialTarget: string;
begin
  case ProviderPage.SelectedValueIndex of
    0: Result := 'ClawFactory/GrokApiKey'; 1: Result := 'ClawFactory/OpenAIApiKey';
    2: Result := 'ClawFactory/AnthropicApiKey'; 3: Result := 'ClawFactory/GeminiApiKey';
  else Result := 'ClawFactory/GrokApiKey';
  end;
end;

function ProviderApiKeyUrl: string;
begin
  case ProviderPage.SelectedValueIndex of
    0: Result := 'https://console.x.ai/';
    1: Result := 'https://platform.openai.com/api-keys';
    2: Result := 'https://console.anthropic.com/settings/keys';
    3: Result := 'https://aistudio.google.com/app/apikey';
  else Result := '';
  end;
end;

function ProviderShortName: string;
begin
  case ProviderPage.SelectedValueIndex of
    0: Result := 'Grok'; 1: Result := 'OpenAI';
    2: Result := 'Anthropic'; 3: Result := 'Gemini';
  else Result := '';
  end;
end;

procedure GetKeyButtonClick(Sender: TObject);
var URL: string; ResultCode: Integer;
begin
  URL := ProviderApiKeyUrl; if URL = '' then exit;
  ShellExec('open', URL, '', '', SW_SHOWNORMAL, ewNoWait, ResultCode);
end;

procedure InitializeWizard;
begin
  IsResumeRun := HasCmdLineSwitch('/resume');
  if IsResumeRun then ResumeProvider := ReadResumeProvider;

  WelcomePage := CreateOutputMsgPage(wpWelcome,
    'Hardened OpenClaw Skills Factory',
    'This installer builds a sandboxed environment for AI agents.',
    'ClawFactory Secure Setup configures WSL2, Docker, and OpenClaw with strict' + #13#10 +
    'security guardrails:' + #13#10 + #13#10 +
    '  - Four agents run in Docker sandbox (network=none, sandbox=all).' + #13#10 +
    '  - OpenClaw gateway binds to 127.0.0.1 only.' + #13#10 +
    '  - Tool allowlist blocks shell/sudo/rm/system.run/browser.' + #13#10 +
    '  - WSL automount is disabled (no access to your Windows files).' + #13#10 +
    '  - All agents require explicit human "GO" for any risky action.' + #13#10 + #13#10 +
    'WARNING: AI agents will execute code inside these containers.' + #13#10 +
    'You must personally review every skill before publishing.' + #13#10 +
    'Install takes 10-20 minutes and needs admin rights + internet.');

  ProviderPage := CreateInputOptionPage(WelcomePage.ID,
    'Choose your AI provider', 'Which LLM should power your agents?',
    'You can switch providers later by re-running the installer or using the included' + #13#10 +
    'switch-provider.ps1 helper script. Ollama runs entirely on this machine - no' + #13#10 +
    'account, no API key, no cloud calls (needs ~8 GB RAM).',
    True, False);
  ProviderPage.Add('Grok (xAI) - default model: grok-4-1-fast');
  ProviderPage.Add('OpenAI (ChatGPT) - default model: gpt-5');
  ProviderPage.Add('Anthropic Claude - default model: claude-sonnet-4-6');
  ProviderPage.Add('Google Gemini - default model: gemini-2.5-pro');
  ProviderPage.Add('Ollama (local, free, offline-capable) - default model: llama3.1:8b');
  ProviderPage.Add('I''ll configure a provider later');
  ProviderPage.SelectedValueIndex := 0;

  ApiKeyPage := CreateInputQueryPage(ProviderPage.ID,
    'API Key', 'Paste the API key for your selected provider.',
    'The key is stored in Windows Credential Manager (DPAPI-protected, tied to your' + #13#10 +
    'Windows user). It is NEVER written to a file inside WSL.' + #13#10 + #13#10 +
    'Rotate later from a terminal with cmdkey (see README).');
  ApiKeyPage.Add('API key:', True);

  GetKeyButton := TNewButton.Create(ApiKeyPage);
  GetKeyButton.Parent := ApiKeyPage.Surface;
  GetKeyButton.Top    := ApiKeyPage.Edits[0].Top + ApiKeyPage.Edits[0].Height + ScaleY(12);
  GetKeyButton.Left   := ApiKeyPage.Edits[0].Left;
  GetKeyButton.Width  := ScaleX(220);
  GetKeyButton.Height := ScaleY(24);
  GetKeyButton.Caption := 'Get your API key →';
  GetKeyButton.OnClick := @GetKeyButtonClick;

  ApiKeyLaterChk := TNewCheckBox.Create(ApiKeyPage);
  ApiKeyLaterChk.Parent  := ApiKeyPage.Surface;
  ApiKeyLaterChk.Top     := GetKeyButton.Top + GetKeyButton.Height + ScaleY(12);
  ApiKeyLaterChk.Left    := ApiKeyPage.Edits[0].Left;
  ApiKeyLaterChk.Width   := ApiKeyPage.SurfaceWidth - ApiKeyLaterChk.Left;
  ApiKeyLaterChk.Height  := ScaleY(20);
  ApiKeyLaterChk.Caption := 'I''ll add my API key later (agents will not run until I do)';

  AckPage := CreateInputOptionPage(ApiKeyPage.ID,
    'Security Acknowledgement', 'Please confirm you understand what you are about to install.',
    'Tick the box below to continue. Installation is blocked until you do.',
    False, False);
  AckPage.Add('I understand agents execute code in isolated containers and I will ' +
              'personally review every skill before publishing.');
end;

procedure CurPageChanged(CurPageID: Integer);
var ShortName: string;
begin
  if CurPageID = ApiKeyPage.ID then
  begin
    ShortName := ProviderShortName;
    if ShortName = '' then GetKeyButton.Visible := False
    else begin
      GetKeyButton.Caption := 'Get your ' + ShortName + ' API key →';
      GetKeyButton.Visible := True;
    end;
  end;
end;

function ShouldSkipPage(PageID: Integer): Boolean;
begin
  Result := False;
  if IsResumeRun then
  begin
    if (PageID = WelcomePage.ID) or (PageID = ProviderPage.ID) or
       (PageID = ApiKeyPage.ID) or (PageID = AckPage.ID) then
    begin Result := True; exit; end;
  end;
  if PageID = ApiKeyPage.ID then Result := not ProviderNeedsApiKey;
end;

function NextButtonClick(CurPageID: Integer): Boolean;
var Key: string; ResultCode: Integer; CredTarget: string;
begin
  Result := True;
  if CurPageID = ApiKeyPage.ID then
  begin
    Key := Trim(ApiKeyPage.Values[0]);
    if (Key = '') and (not ApiKeyLaterChk.Checked) then
    begin
      MsgBox('Enter your API key, or tick "I''ll add my API key later".', mbError, MB_OK);
      Result := False; exit;
    end;
    if Key <> '' then
    begin
      CredTarget := ProviderCredentialTarget;
      Exec('cmdkey.exe', '/generic:' + CredTarget + ' /user:clawuser /pass:' + Key,
           '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
      ApiKeyPage.Values[0] := '';
    end;
  end
  else if CurPageID = AckPage.ID then
  begin
    if not AckPage.Values[0] then
    begin
      MsgBox('You must acknowledge the security notice before installation can continue.', mbError, MB_OK);
      Result := False;
    end;
  end;
end;
```

---

## 17. OpenClaw Config Schema (2026.4.27)

> Version-pinned to 2026.4.27. Re-capture on version bumps — paths, schema branches, and command syntax can shift between minor versions.

### 17.1 `openclaw config --help`

```
🦞 OpenClaw 2026.4.27 (cbc2ba0)

Usage: openclaw config [options] [command]

Non-interactive config helpers (get/set/unset/file/schema/validate). Run without
subcommand for guided setup.

Options:
  -h, --help           Display help for command
  --section <section>  Configuration sections for guided setup (repeatable). Use
                       with no subcommand. (default: [])

Commands:
  file                 Print the active config file path
  get                  Get a config value by dot path
  schema               Print the JSON schema for openclaw.json
  set                  Set config values by path (value mode, ref/provider
                       builder mode, or batch JSON mode).
                       Examples:
                       openclaw config set gateway.port 19001 --strict-json
                       openclaw config set channels.discord.token --ref-provider
                       default --ref-source env --ref-id DISCORD_BOT_TOKEN
                       openclaw config set secrets.providers.vault
                       --provider-source file --provider-path
                       /etc/openclaw/secrets.json --provider-mode json
                       openclaw config set --batch-file ./config-set.batch.json
                       --dry-run
  unset                Remove a config value by dot path
  validate             Validate the current config against the schema without
                       starting the gateway

Docs: https://docs.openclaw.ai/cli/config
```

Note: `openclaw config get` requires a `<path>` argument (e.g. `openclaw config get gateway.port`). Calling it without an argument errors with `error: missing required argument 'path'`.

### 17.2 `openclaw config schema` (top-level structure)

Run `openclaw config schema 2>&1 > openclaw-schema.json` for the full ~2000+ line output. Top-level structure:

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "type": "object",
  "properties": {
    "$schema": { "type": "string" },
    "meta": {
      "type": "object",
      "properties": {
        "lastTouchedVersion": { "type": "string" },
        "lastTouchedAt": { "anyOf": [ { "type": "string" }, {} ] }
      },
      "additionalProperties": false
    },
    "env": { "type": "object", "properties": { "shellEnv": {...}, "vars": {...} } },
    "wizard": { "type": "object", "properties": { "lastRunAt": {...}, "lastRunVersion": {...} } },
    "diagnostics": { "type": "object", "properties": { "enabled": {...}, "otel": {...} } }
    // gateway, agents, plugins, auth, channels, tools, update, secrets, discovery sub-schemas continue
  }
}
```

### 17.3 Notable observations

**Schema paths that exist on 2026.4.27** (confirmed via `cat ~/.openclaw/openclaw.json` from the live laptop):

- `gateway.bind`, `gateway.port`, `gateway.mode`, `gateway.auth.{mode,token}` ✓
- `meta.lastTouchedVersion`, `meta.lastTouchedAt` ✓
- `auth.profiles.<id>.{provider,mode,displayName}`, `auth.order.<provider>` ✓
- `agents.defaults.model.primary`, `agents.defaults.models.<id>`, `agents.list[]` ✓
- `wizard.lastRunAt` ✓
- `plugins.entries.<name>.{enabled,config}` ✓ — confirmed entries: `anthropic`, `openai`, `browser`, `acpx`, `tavily`
- `update.{checkOnStart,auto.enabled}` ✓
- `tools.web.search.provider` ✓
- `discovery.mdns` exists as a parent object but is empty (`{}`) on a healthy install.

**Schema paths the installer used to write but that no longer exist on 2026.4.27** (FIX 2 removed):

- `discovery.mdns.mode` — `openclaw config set discovery.mdns.mode off` returns `Config path not found`. The bonjour SIGTERM bug it was meant to suppress doesn't fire on this version (validated via clean journalctl over multiple installs). Forward-compatible protection comes from the env var drop-in (`OPENCLAW_DISABLE_BONJOUR=1`) instead.
- `skills.entries.coding-agent.enabled` — Same reason. The codex/coding-agent silent-default bug doesn't fire on 2026.4.27.

**Schema structure highlights**:

- Most leaf properties have human-readable `title` and `description` fields, useful for UI generation or `openclaw config validate`-style error messages.
- Many enum-like fields are encoded as `anyOf` with `const` branches rather than `enum` — supports forward-compatible string extension.
- `additionalProperties: false` is enforced on most well-defined parent objects (e.g. `meta`, `wizard`), so schema-set-then-validate is strict.
- Secrets / tokens (`gateway.auth.token`, `plugins.tavily.config.webSearch.apiKey`) are stored inline in `openclaw.json` (mode 600). For long-lived deployments, prefer the `--ref-provider` / `--ref-source env --ref-id ...` form documented in `openclaw config set --help` so secrets stay in env or external secret stores.

Re-run `openclaw config schema 2>&1 > openclaw-schema.json` after every `OPENCLAW_VERSION` pin bump and diff against this file's previous capture to spot schema drift.

---

## 18. Reference Healthy Install State (2026.4.27)

> Captured after manual `openclaw gateway install --force --port 8787` succeeded on laptop, May 1 2026. Use as baseline for diagnosing future installs that produce subtly different state. Re-capture after every `OPENCLAW_VERSION` pin bump.

### 18.1 systemd unit file

`~/.config/systemd/user/openclaw-gateway.service`:

```ini
[Unit]
Description=OpenClaw Gateway (v2026.4.27)
After=network-online.target
Wants=network-online.target
StartLimitBurst=5
StartLimitIntervalSec=60

[Service]
ExecStart=/usr/bin/node /usr/lib/node_modules/openclaw/dist/index.js gateway --port 8787
Restart=always
RestartSec=5
RestartPreventExitStatus=78
TimeoutStopSec=30
TimeoutStartSec=30
SuccessExitStatus=0 143
KillMode=control-group
Environment=HOME=/home/clawuser
Environment=TMPDIR=/tmp
Environment=PATH=/usr/bin:/home/clawuser/.local/bin:/home/clawuser/.npm-global/bin:/home/clawuser/bin:/home/clawuser/.volta/bin:/home/clawuser/.asdf/shims:/home/clawuser/.bun/bin:/home/clawuser/.nvm/current/bin:/home/clawuser/.fnm/current/bin:/home/clawuser/.local/share/pnpm:/usr/local/bin:/bin
Environment=OPENCLAW_GATEWAY_PORT=8787
Environment=OPENCLAW_SYSTEMD_UNIT=openclaw-gateway.service
Environment="OPENCLAW_WINDOWS_TASK_NAME=OpenClaw Gateway"
Environment=OPENCLAW_SERVICE_MARKER=openclaw
Environment=OPENCLAW_SERVICE_KIND=gateway
Environment=OPENCLAW_SERVICE_VERSION=2026.4.27

[Install]
WantedBy=default.target
```

Confirms: gateway runs as a node process bound to port 8787, restarts on most failures, has `TimeoutStartSec=30` (overridden to `infinity` by drop-in — see 18.5).

### 18.2 ~/.openclaw/openclaw.json (token redacted)

```json
{
  "gateway": {
    "bind": "loopback",
    "port": 8787,
    "mode": "local",
    "auth": {
      "mode": "token",
      "token": "<REDACTED>"
    }
  },
  "meta": {
    "lastTouchedVersion": "2026.4.27",
    "lastTouchedAt": "2026-05-01T09:42:57.938Z"
  },
  "auth": {
    "profiles": {
      "anthropic:default": {
        "provider": "anthropic",
        "mode": "api_key",
        "displayName": "Anthropic (default)"
      }
    },
    "order": { "anthropic": [ "anthropic:default" ] }
  },
  "agents": {
    "defaults": {
      "model": { "primary": "anthropic/claude-sonnet-4-6" },
      "models": {
        "openai/claude-sonnet-4-6": {},
        "anthropic/claude-sonnet-4-6": {}
      }
    },
    "list": [
      { "id": "main" },
      { "id": "orchestrator", "name": "orchestrator", "workspace": "/home/clawuser/.openclaw/agents/orchestrator", "agentDir": "/home/clawuser/.openclaw/agents/orchestrator/agent", "identity": { "name": "orchestrator" } },
      { "id": "skill-scout", "name": "skill-scout", "workspace": "/home/clawuser/.openclaw/agents/skill-scout", "identity": { "name": "skill-scout" }, "agentDir": "/home/clawuser/.openclaw/agents/skill-scout/agent" }
    ]
  },
  "wizard": { "lastRunAt": "2026-04-24T18:48:44-06:00" },
  "plugins": {
    "entries": {
      "anthropic": { "enabled": true },
      "openai":    { "enabled": true },
      "browser":   { "enabled": false },
      "acpx":      { "enabled": false },
      "tavily":    { "enabled": true, "config": { "webSearch": { "apiKey": "<REDACTED>" } } }
    }
  },
  "update": { "checkOnStart": false, "auto": { "enabled": false } },
  "tools":  { "web": { "search": { "provider": "tavily" } } },
  "discovery": { "mdns": {} }
}
```

Confirms: token-auth gateway bound loopback on 8787, default model is `anthropic/claude-sonnet-4-6`, 3 agents enumerated (main + orchestrator + skill-scout), 5 plugins configured, `discovery.mdns` exists as empty object (no schema path to set `mode` on this version).

### 18.3 ~/.openclaw/ directory listing

```
total 100
drwx------ 12 clawuser clawuser 4096 May  1 09:42 .
drwx------ 10 clawuser clawuser 4096 Apr 26 07:53 ..
-r--r--r--  1 clawuser clawuser  873 Apr 24 19:37 SOUL.md
-r--r--r--  1 clawuser clawuser   64 Apr 24 19:37 SOUL.md.sha256
drwxr-xr-x  7 clawuser clawuser 4096 Apr 26 07:54 agents
-rw-------  1 clawuser clawuser  205 Apr 24 18:47 auth-profiles.json
drwxr-xr-x  2 clawuser clawuser 4096 Apr 25 05:38 canvas
drwx------  2 clawuser clawuser 4096 Apr 26 09:26 cron
drwxrwxr-x  2 clawuser clawuser 4096 Apr 26 10:06 devices
-rw-------  1 clawuser clawuser  180 Apr 26 10:01 exec-approvals.json
-rw-------  1 clawuser clawuser  135 Apr 26 09:30 external-keys.json
drwxr-xr-x  9 clawuser clawuser 4096 Apr 26 07:53 factory
drwxr-xr-x  2 clawuser clawuser 4096 Apr 26 07:40 identity
drwx------  2 clawuser clawuser 4096 Apr 24 18:28 logs
-rw-------  1 clawuser clawuser 2131 May  1 09:42 openclaw.json
-rw-------  1 clawuser clawuser 2156 May  1 09:42 openclaw.json.bak
-rw-------  1 clawuser clawuser 2094 May  1 09:42 openclaw.json.bak.1
-rw-------  1 clawuser clawuser 2002 Apr 26 10:05 openclaw.json.bak.2
-rw-------  1 clawuser clawuser 1720 Apr 26 09:39 openclaw.json.bak.3
-rw-------  1 clawuser clawuser 1679 Apr 26 09:30 openclaw.json.bak.4
-rw-------  1 clawuser clawuser 2131 May  1 09:43 openclaw.json.last-good
drwxr-xr-x  3 clawuser clawuser 4096 Apr 24 17:37 plugin-runtime-deps
drwx------  2 clawuser clawuser 4096 Apr 25 05:38 tasks
-rw-------  1 clawuser clawuser   49 Apr 25 18:45 update-check.json
drwxr-xr-x  5 clawuser clawuser 4096 Apr 25 20:07 workspace
```

Confirms: `SOUL.md` is mode 444 (read-only — installed in Step 11 and `chattr +i`-equivalent via mode bits), 5 `openclaw.json.bak*` rolling backups (openclaw auto-rotates on every config write), `auth-profiles.json` is mode 600, `plugin-runtime-deps/` exists from Step 8b npm pre-install.

### 18.4 ~/.openclaw/agents/ directory listing

```
drwxr-xr-x  7 clawuser clawuser 4096 Apr 26 07:54 .
drwx------ 12 clawuser clawuser 4096 May  1 09:42 ..
drwx------  4 clawuser clawuser 4096 Apr 26 07:44 main
drwxr-xr-x  6 clawuser clawuser 4096 Apr 26 08:08 orchestrator
drwxr-xr-x  3 clawuser clawuser 4096 Apr 26 08:07 publisher
drwxr-xr-x  3 clawuser clawuser 4096 Apr 26 08:07 skill-builder
drwxr-xr-x  5 clawuser clawuser 4096 Apr 26 10:06 skill-scout
```

Confirms: 5 agent directories (main + 4 factory agents).

### 18.5 ~/.config/systemd/user/ directory listing

```
total 24
drwxrwxr-x 4 clawuser clawuser 4096 Apr 25 18:45 .
drwxrwxr-x 3 clawuser clawuser 4096 Apr 24 16:50 ..
drwxr-xr-x 2 clawuser clawuser 4096 Apr 25 05:32 default.target.wants
-rw-rw-r-- 1 clawuser clawuser  619 Apr 24 16:50 docker.service
-rw-r--r-- 1 clawuser clawuser 1065 Apr 25 05:32 openclaw-gateway.service
drwxr-xr-x 2 clawuser clawuser 4096 Apr 25 19:53 openclaw-gateway.service.d
```

Drop-in directory contents (`openclaw-gateway.service.d/`) on this snapshot:

```
total 12
drwxr-xr-x 2 clawuser clawuser 4096 Apr 25 19:53 .
drwxrwxr-x 4 clawuser clawuser 4096 Apr 25 18:45 ..
-rw-r--r-- 1 clawuser clawuser   84 Apr 25 20:04 insecure-loopback.conf
```

`insecure-loopback.conf` contents (auto-written by `openclaw gateway install --force` itself):

```ini
[Service]
Environment=OPENCLAW_ALLOW_INSECURE_PRIVATE_WS=1
TimeoutStartSec=infinity
```

> **Note**: this snapshot is from a manual `openclaw gateway install --force` run, not a full setup.ps1 run. A full installer run also writes `clawfactory-tunables.conf` (TimeoutStartSec=infinity from sub-block c) and `clawfactory-disable-bonjour.conf` (Environment=OPENCLAW_DISABLE_BONJOUR=1 from post-install FIX 1). Both coexist with `insecure-loopback.conf` because systemd merges all `*.conf` drop-ins on `daemon-reload`.

---

## 19. CLAWCHAT

Tauri + React desktop app bundled into both installers.
- **Source:** `C:\Users\bmcki\ClawChat\`
- **GitHub:** https://github.com/BuzzardsBay/clawchat (private)
- **Binary:** `resources\ClawChat.exe` in both installer repos (10.88 MB, SHA-256 `0bb56c62e70a5af6153db8fd9a3b8b0c4a69682f54ae703e87952c18facb6d45`)

**Version:** 1.0.0

**Build command:**
```powershell
cd C:\Users\bmcki\ClawChat\
npm run tauri build
```
Output: `src-tauri\target\release\ClawChat.exe`

### 19.1 Features shipped

- Conversation threads with persistent history (`%APPDATA%\ClawChat\conversations\{uuid}.json`)
- Streaming SSE against `/v1/chat/completions` on the loopback gateway
- Dark (warm charcoal) + light (warm off-white) theme toggle (bottom-left button)
- Mascot illustration in empty / offline / connecting states
- Gateway status indicator (green / red / grey dot) with 10-second poll
- Token read via WSL base64-over-stdout pattern (`wsl.exe -d Ubuntu -u clawuser -- bash -lc "cat /home/clawuser/.openclaw/openclaw.json | base64 -w0"`)

### 19.2 Known gaps (active)

- **C1:** No gateway auto-start on launch. Desktop shortcut launches `ClawChat.exe` directly, bypassing `launcher.ps1`. If the WSL Host scheduled task hasn't fired yet, gateway is offline and ClawChat shows the offline mascot state until the user manually restarts via Kill Switch. **Fix queued as backlog item 18.**
- **C2:** No settings tab. Provider switching, API key management, and security control toggles are all install-time only — no UI access. **Fix queued as backlog item 19.**

### 19.3 Security posture

- Conversation storage: `%APPDATA%\ClawChat\conversations\{uuid}.json` — Windows user profile, normal NTFS ACLs apply.
- Token storage: read from openclaw.json via WSL at runtime only — never persisted by ClawChat to disk.
- Network: only reaches `127.0.0.1:8787` (the loopback gateway). No outbound HTTPS from ClawChat itself.
- CSP: intentionally null (local app loading only IBM Plex Mono from Google Fonts; no remote JS, no untrusted iframes).

---

## 20. INFRASTRUCTURE AND DISTRIBUTION

### 20.1 Landing page — clawfactory.app

- **Source:** `docs/index.html` in `clawfactory-secure-setup` repo
- **Hosted:** GitHub Pages, custom domain
- **DNS:** Namecheap (clawfactory.app)
- **HTTPS:** enforced
- **Download buttons:** point at `releases/latest` URLs for both repos (auto-resolves; no version-specific links to keep in sync)

### 20.2 Personal site — bretmckinney.com

- **Source:** `C:\Users\bmcki\BretMcKinney-Site\` (verify local clone path before editing)
- **GitHub:** https://github.com/BuzzardsBay/bretmckinney-site (public)
- **Hosted:** GitHub Pages, custom domain
- **DNS:** Namecheap (bretmckinney.com)

### 20.3 Payment — Stripe (Frontier Trading LLC)

- ClawFactory: $149 one-time
- ClawAgent: $49 one-time
- Payouts: Mercury bank account

### 20.4 Email

- Support: `support@clawfactory.app` (Namecheap forwarder → `hello@avitalresearch.com`)
- Personal: `bret@bretmckinney.com` (Namecheap forwarder → `hello@avitalresearch.com`)

### 20.5 GitHub releases

- ClawFactory: https://github.com/BuzzardsBay/clawfactory-secure-setup/releases
- ClawAgent: https://github.com/BuzzardsBay/clawagent-setup/releases
- Landing page download buttons use `/releases/latest` (auto-resolves to whichever tag was published most recently)

### 20.6 Azure validation

- **Resource group:** `clawfactory-validation` (westus2)
- **Baseline image:** `clawfactory-win11-baseline` — **DO NOT DELETE**
- **Storage account:** `clawfactoryvalc467` (StorageV2, westus2)
- **Subscription:** `43010359-5b4c-4d16-af11-10f6544b2978`
- **Creds:** `C:\Users\bmcki\.azure-clawfactory-creds` (clawadmin / ClawFactory2026!Secure)
- **Public IP quota:** 3 (limit), typically 0 in use between cycles
- **VM pattern:** Standard_D2s_v5, `--security-type Standard` (mandatory; Trusted Launch breaks the baseline image)

**SHA-256 handling (setup.ps1, Step 8):**
Hash is computed at install time from the bundled resources\openclaw-install.sh
using Get-FileHash. Logged to console and written to checkpoint.json under key
installShHash. No pinned hash -- the bundled script is the version of record.
Checkpoint entry provides audit trail.

### 18.6 systemctl unit-files inventory

```
openclaw-gateway.service                         enabled   enabled
```

Confirms: unit is enabled at user scope, will start on next user-systemd boot.

### 18.7 systemctl is-active

```
active
```

Confirms: gateway is running.

### 18.8 What this baseline confirms

- `openclaw gateway install --force --port 8787` (the canonical install used in setup.ps1 Step 8b after commit a10a4a6) does in fact:
  - auto-generate the gateway token,
  - write a 1065-byte systemd user unit at the documented path,
  - write its own `insecure-loopback.conf` drop-in setting `TimeoutStartSec=infinity` (which means our Step 8b sub-block c `clawfactory-tunables.conf` is now redundant on this version — both set the same thing),
  - leave the unit in `enabled` + `active` state immediately after install.
- Schema paths that 2026.4.27 actually has are exactly the ones listed in section 17.3.
- The 5-rolling-`.bak` backup pattern openclaw uses on `openclaw.json` writes is intentional — useful for rollback diagnosis.
- `discovery.mdns` exists as `{}`, not as `{"mode": "off"}`. Consistent with FIX 2's removal rationale.
