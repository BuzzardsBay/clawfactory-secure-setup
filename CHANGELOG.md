# Changelog

All notable changes to ClawFactory Secure Setup are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [1.0.0] — 2026-05-03

First public release. 7/7 smoke test passing on real hardware.

### Added

- **Bundled Ubuntu rootfs for offline install** ([`a702b2d`](../../commit/a702b2d)). 341 MB rootfs ships with the installer; `wsl --import` is the primary path with `wsl --install` (network) as fallback. Eliminates Microsoft Store dependency and works on machines with no internet after the `.exe` is downloaded.
- **OpenClaw version pin to 2026.4.27** ([`826fe74`](../../commit/826fe74)). `OPENCLAW_VERSION=2026.4.27` passed to `install.sh` so customers receive a tested, deterministic install rather than tracking upstream `@latest`. Bump only after manually re-validating the four bundled bug-workarounds against the new version.
- **Diagnostic reference pack** ([`32c594c`](../../commit/32c594c)). Sections 13–18 of `CLAUDE_ClawFactory.md` capture the install execution map, code interconnect map, diagnostic quick reference, Inno Setup script, OpenClaw 2026.4.27 config schema, and a healthy install state baseline. Plus a `v1.1_backlog.md` tracking deferred items.
- **Health-poll on gateway install** ([`cf38a65`](../../commit/cf38a65)). Step 8b polls `http://127.0.0.1:8787/status` for up to 60 s after `openclaw gateway install --force` returns. The HTTP probe is the source of truth for health, not the install command's exit code.
- **`Install-WslDistroWithFallback`** with two-tier strategy: bundled `wsl --import --version 2` first, network `wsl --install` fallback (which retains its own `HCS_E_HYPERV_NOT_INSTALLED` → WSL1 fallback).
- **Smoke test script** at `smoke-test.ps1`. Seven checks, exit 0 only on full pass. Runs from admin PowerShell on the install target.
- **Defense-in-depth bonjour disable** — systemd drop-in setting `OPENCLAW_DISABLE_BONJOUR=1`. Harmless on 2026.4.27 (env var ignored); documented protection against future version-bump regressions of the bonjour SIGTERM bug.
- **Per-agent `auth-profiles.json` fan-out** in `bootstrap.ps1`. Five agents (main, orchestrator, publisher, skill-builder, skill-scout) each get the legacy `~/.openclaw/auth-profiles.json` copied to their canonical per-agent path at mode 600.

### Fixed

- **CR line-ending corruption in `Invoke-WslBash`** ([`17172d5`](../../commit/17172d5), [`93c0bf7`](../../commit/93c0bf7)). PowerShell here-strings on Windows have CRLF endings; when base64-decoded inside bash, `\r` was being parsed as part of the option name (`set -e\r` → "set: invalid option"). All three `Invoke-WslBash` sites (one in `setup.ps1`, two in `bootstrap.ps1`) now strip CRLF→LF before encoding.
- **Gateway config order** ([`3da92fa`](../../commit/3da92fa)). `openclaw config set gateway.{mode,bind,port}` now runs before `openclaw gateway install --force` instead of after. The install command starts the service immediately and the service exits 78/CONFIG if `gateway.mode` isn't already set in `openclaw.json`.
- **`tee -a` permission-denied trapping install success** ([`42869d8`](../../commit/42869d8)). Step 8 created `/tmp/openclaw-install.log` as root; Step 8b ran as clawuser and couldn't append, but the pipeline exit code was tee's (1), masking openclaw's (0). Dropped the tee from the gateway-install line; output is captured via `Invoke-WslBash`'s stdout routing.
- **Throw-on-exit-1 from `gateway install --force`** ([`cf38a65`](../../commit/cf38a65)). Non-zero exit from the install command is now WARN-only; only a non-responsive gateway after the 60 s `/status` poll throws.
- **`openclaw doctor` blocking on interactive prompts** ([`93c0bf7`](../../commit/93c0bf7)). Added `--non-interactive --no-workspace-suggestions`. Safe in this architecture because Step 8b's `gateway install --force` already handles the systemd unit install that `--non-interactive` skips.
- **`post-install.ps1` aborting on first stderr line** ([`93c0bf7`](../../commit/93c0bf7)). With `$ErrorActionPreference = 'Stop'`, raw `wsl -- … 2>&1 | ForEach-Object` calls were terminating the script when wsl.exe printed `wsl: Failed to translate '<path>'` warnings (which fire reliably on every wsl invocation from a Windows shell). Refactored four sites to use a `Process.Start`-based `Invoke-WslBash` that filters those lines.
- **Silent failure on `openclaw models set`** ([`93c0bf7`](../../commit/93c0bf7)). Exit code is now captured and a WARN logged on non-zero with a manual-recovery hint.
- **Stale doctor comment block** ([`93c0bf7`](../../commit/93c0bf7)). Comment in `post-install.ps1` warning against `--non-interactive` was from the pre-Step-8b architecture; rewritten to match the current state where doctor is a final health check.
- **Stale "What to do next" instructions in `bootstrap.ps1`** ([`93c0bf7`](../../commit/93c0bf7)). Removed the misleading "Start the gateway" step (already started by Step 8b); fixed the log paths from `/tmp/openclaw/` to `~/.openclaw/logs/gateway.log`.

[1.0.0]: ../../releases/tag/v1.0.0
