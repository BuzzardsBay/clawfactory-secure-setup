# ClawFactory Secure Setup

[![v1.0.37](https://img.shields.io/badge/release-v1.0.37-green)](../../releases/tag/v1.0.37) [![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE) [![Windows 11](https://img.shields.io/badge/Windows-10%202004%2B%20%2F%2011-0078D6?logo=windows)](#system-requirements)

A Windows installer that drops a hardened OpenClaw runtime onto a fresh Windows machine in 10–20 minutes, with every default flipped to the secure side. WSL2 with Windows automount disabled, a non-sudo `clawuser`, rootless Docker, an nftables egress firewall scoped to that user's UID, the OpenClaw gateway bound only to `127.0.0.1`, a Windows Firewall inbound-deny on port 8787, the API key stored in DPAPI Credential Manager, and a `SOUL.md` safety policy hash-pinned at file mode 444. One installer, fifteen steps, no telemetry, fully auditable PowerShell.

## What's inside

- **WSL2 + Ubuntu** — bundled rootfs imported offline via `wsl --import` (no Microsoft Store dependency).
- **`clawuser`** — non-root, no sudo group membership, locked password.
- **Docker** in rootless mode under `clawuser`.
- **Egress firewall (nftables)** — drops everything from `clawuser`'s UID except DNS, loopback, and the IPv4 addresses of your chosen LLM provider host plus a small base allowlist (GitHub, npm, Docker Hub, OpenClaw, ClawHub). 6 h refresh timer for IP rotation.
- **OpenClaw 2026.4.27** — version-pinned, fetched from a SHA-256-pinned `install.sh`, configured `gateway.bind=loopback gateway.port=8787 gateway.mode=local`.
- **Provider key in DPAPI** — read from Windows Credential Manager, written via `wsl.exe` stdin to `~/.openclaw/auth-profiles.json` mode 600. Never on a command line, never in `.env`.
- **`SOUL.md`** — safety policy at mode 444 with SHA-256 substituted into the orchestrator prompt; the agent's first turn fails closed if the live hash doesn't match.
- **Windows Firewall inbound-deny on TCP/8787** — belt-and-suspenders against any future misconfiguration that flips the gateway bind to `0.0.0.0`.
- **Kill Switch** — Start Menu shortcut that stops the gateway and any agent containers.
- **Four pre-staged agents** — orchestrator, skill-scout, skill-builder, publisher. Each gets a role-specific `agent.md` with its own auth-profile fan-out.

## System requirements

- Windows 10 (version 2004+) or Windows 11
- Administrator privileges for install
- 16 GB RAM recommended (8 GB minimum)
- 50 GB free disk (Ubuntu rootfs + Docker images + OpenClaw runtime)
- Hardware virtualization enabled in BIOS (VT-x / AMD-V) for WSL2; falls back to WSL1 automatically if unavailable

## Installation

1. Download `ClawFactory-Secure-Setup.exe` from the [Releases](../../releases) page (~325 MB — carries the bundled Ubuntu rootfs).
2. Right-click → **Run as administrator**.
3. Walk the wizard: provider → API key → security acknowledgement → Install.
4. Wait 10–20 minutes. The installer reboots once if WSL2 features need DISM enable, then auto-resumes.
5. Done. Desktop icon launches a chat session in Windows Terminal.

## Security

Defense in depth — multiple independent layers, each scoped to a different attack surface:

| Attack | Control |
|---|---|
| API key theft via `.env` grep / process enumeration | Key in DPAPI, piped via stdin to `auth-profiles.json` mode 600. Never on disk in WSL. |
| Agent exfiltration to arbitrary endpoints | nftables egress firewall on `clawuser`'s UID. Provider host + small base allowlist only. |
| Prompt injection → lateral movement | WSL `automount=false`, no `/mnt/c/` access. Non-root, no sudo. Rootless Docker. `SOUL.md` hash-pinned. |
| LAN-side gateway hijack | `gateway.bind=loopback` + Windows Firewall inbound-deny on TCP/8787. |
| Supply chain on `install.sh` | SHA-256 pin in `setup.ps1`; install aborts on mismatch. |

Full threat model in [SECURITY.md](SECURITY.md).

## Smoke test

After install, on the same machine, in an admin PowerShell:

```powershell
powershell -ExecutionPolicy Bypass -File "C:\Program Files\ClawFactory\smoke-test.ps1"
```

The script runs 19 checks and exits 0 only if all pass:

1. WSL automount disabled
2. Four `agent.md` files present (orchestrator, skill-scout, skill-builder, publisher)
3. `AgentBootstrap` recorded in `%ProgramData%\ClawFactory\checkpoint.json`
4. Gateway returns HTTP 200 on `http://127.0.0.1:8787/status`
5. Windows Firewall inbound-deny rule active on TCP/8787
6. Orchestrator's `agent.md` has the live SOUL.md SHA-256 substituted (no `{{SOUL_SHA256}}` placeholder)
7. Per-agent `auth-profiles.json` (mode 600) present for all 5 agents
8. `.wslconfig` has `vmIdleTimeout=-1` (keeps the WSL VM alive while Windows is up)
9. `ClawFactory WSL Host` scheduled task registered and enabled (gateway keep-alive)
10. Egress firewall `clawfactory` chain present in the nftables ruleset
11. OpenClaw build dependencies present (make, g++, cmake, python3)
12. Grants library (`resources\clawfactory-grants.ps1`) present
13. Workspace grant mounts a folder into `/workspaces/<slug>` (drvfs)
14. Grant deny-list rejects a drive root (`C:\`)
15. Kill Switch unmounts a granted folder but keeps the grant active in the ledger
16. Replay remounts an active grant after mount loss (post-restart path)
17. Revoke unmounts a granted folder
18. Spend governor meter returns a numeric spend with a state that is not `unknown`
19. Spend governor turn-gate blocks a turn when the cap is set to 0

> Checks 12–19 are the v1.1 Grants + spend-governor substrate. Like the other
> WSL-dependent checks they SKIP (not FAIL) when the smoke test runs as
> `NT AUTHORITY\SYSTEM`.

## Known limitations

- **SmartScreen "Unknown publisher" warning on unsigned builds.** Releases built via `scripts\build_release.ps1` are Authenticode-signed (Azure Artifact Signing, individual identity, Bret Mckinney) and timestamped. A build compiled directly with `ISCC.exe` (skipping the signing step) is still unsigned — click "More info -> Run anyway" for those.
- **WSL1 fallback on hardware without nested virtualization.** If `HCS_E_HYPERV_NOT_INSTALLED` fires (common in nested VMs and some older laptops), the installer falls back to WSL1 automatically. Some features (systemd, networking) behave differently — egress firewall uses iptables-legacy instead of nftables.
- **Provider model IDs are forward-looking** (`grok-4-1-fast`, `gpt-5`, `claude-sonnet-4-6`, `gemini-2.5-pro`). If your provider's catalog uses a different name when you install, change it via `Switch AI Provider` from the Start Menu.

## Pricing

One-time purchase, free updates forever. No subscription, no telemetry.

| Product | Price | What it is |
|---|---|---|
| **ClawFactory** | **$149** | The full hardened OpenClaw Skills Factory installer (this repo). |
| **ClawAgent** | **$49** | The lighter single-agent variant. |
| **ClawChat** | bundled | Desktop chat app, included with both. |

Buy at [clawfactory.app](https://clawfactory.app).

## Building from source

```cmd
"C:\Program Files (x86)\Inno Setup 6\ISCC.exe" ClawFactory-Secure-Setup.iss
```

Output: `Output\ClawFactory-Secure-Setup.exe`. Requires the bundled rootfs at `resources\ubuntu-rootfs.tar.gz` (gitignored — sourced separately at build time). The `.iss` and `setup.ps1` are the only sources of truth — every line is auditable before you trust a build.

### Producing a signed release build

Any installer uploaded to a GitHub Release must be Authenticode-signed via Azure
Artifact Signing. Use `scripts\build_release.ps1` instead of calling `ISCC.exe`
directly — it compiles with Inno Setup and then signs the resulting `.exe`
(`scripts\sign_installer.ps1`) before it's ready to upload:

```powershell
.\scripts\build_release.ps1
```

Requires `AZURE_SIGNING_*` values in a repo-root `.env` (see `signing\metadata.json.template`
for the fields) and the service principal to hold the **Artifact Signing Certificate
Profile Signer** role on the `clawfactory-signing` account. Signing fails loudly
(non-zero exit) on any error — never proceed with an unsigned `.exe`.

## License

[MIT](LICENSE). Copyright © 2026 Frontier Automation Systems LLC.

## Security disclosure

Email **support@clawfactory.app** with details. Please **do not** open a public issue for security vulnerabilities. We respond within 72 hours. See [SECURITY.md](SECURITY.md) for the full policy.
