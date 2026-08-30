# ClawFactory Secure Setup

[![v1.4.5](https://img.shields.io/badge/release-v1.4.5-green)](../../releases) [![License: Apache 2.0](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE) [![Windows 11](https://img.shields.io/badge/Windows-10%202004%2B%20%2F%2011-0078D6?logo=windows)](#system-requirements)

> The public site (clawfactory.app) is published from [BuzzardsBay/clawfactory-site](https://github.com/BuzzardsBay/clawfactory-site). `docs/` in this repo is no longer the published source.

A Windows installer that drops a hardened OpenClaw runtime onto a fresh Windows machine in 10–20 minutes, with every default flipped to the secure side. WSL2 with Windows automount disabled, a non-sudo `clawuser`, an nftables egress firewall scoped to that user's UID, the OpenClaw gateway bound only to `127.0.0.1`, a Windows Firewall inbound-deny on port 8787, the API key stored in DPAPI Credential Manager, and a `SOUL.md` safety policy hash-pinned at file mode 444. One installer, no telemetry, no licence server, no account, fully auditable PowerShell.

ClawFactory is free. There is nothing to buy, no key to enter, and the installer makes no call to any ClawFactory server at any point.

## The three things it promises

These sentences are the product. They are worded to be exactly as strong as the mechanism behind them and no stronger, and each is traceable to a passing test. See [SECURITY_FINDINGS.md](SECURITY_FINDINGS.md) for the evidence and the residuals.

**Web access is denied by default.** Your agent can reach the AI provider, the software sources ClawFactory needs, and the network addresses of the sites you have allowed. Nothing else.

**Your agent can write an email. It cannot send one.** Every message waits for you, and approving it sends exactly that message, once.

**When your agent deletes a file in a folder you granted it, the file is held for 30 days and you can put it back.** This covers deletion by name, which is how deletion is ordinarily expressed; it does not cover every possible way a program can destroy a file.

And the boundary that travels with all of them: **this covers email. It is not a claim that no data can leave your machine.** Your agent talks to a hosted AI model, and anything it can read it can send there.

## What's inside

- **WSL2 + Ubuntu**: bundled rootfs imported offline via `wsl --import` (no Microsoft Store dependency), pinned to a published Canonical digest.
- **`clawuser`**: non-root, no sudo group membership, locked password.
- **Egress firewall (nftables)**: drops everything from `clawuser`'s UID except DNS to the WSL resolver, loopback, and the resolved IPv4 addresses of a small host set: your chosen provider, ClawFactory's own site, the Node and Ubuntu package sources, and, behind a switch you control, GitHub, npm and the skill hub. Matching is by address, not by name. Periodic refresh for IP rotation.
- **OpenClaw 2026.4.27**: version-pinned, fetched from a SHA-256-pinned `install.sh`, configured `gateway.bind=loopback gateway.port=8787 gateway.mode=local`.
- **Provider key in DPAPI**: read from Windows Credential Manager, written via `wsl.exe` stdin to `~/.openclaw/auth-profiles.json` mode 600. Never on a command line, never in `.env`.
- **`SOUL.md`**: safety policy at mode 444, root-owned and `chattr +i`, with its SHA-256 re-checked in code before every gated turn.
- **Windows Firewall inbound-deny on TCP/8787**: belt-and-suspenders against any future misconfiguration that flips the gateway bind to `0.0.0.0`.
- **Kill Switch**: Start Menu shortcut that unmounts every granted folder, stops the gateway and the agent processes, then counts the agent's processes inside the sandbox and reports per claim what it actually managed to stop. Fixed in v1.4.4; on every release up to v1.4.3 both of its sandbox commands failed on a quoting fault and it reported success anyway.
- **Guard 1, quarantine delete**: the `rm` on the agent's PATH moves files under `/workspaces` into a root-owned hold for 30 days; restore from Studio.
- **Guard 2, approval-gated send**: the agent queues a message with a root-owned broker; nothing leaves until you approve that exact message.
- **Guard 3, the web access switch**: deny-by-default read-fetch allowlist, plus an opt-out for the software sources, both driven from Studio.
- **ClawFactory Studio**: a local control panel for grants, web access, approvals and recently-deleted, installed alongside the sandbox.
- **Four pre-staged agent workspaces**: orchestrator, skill-scout, skill-builder, publisher. Each gets a role-specific `agent.md` and its own auth-profile. Only the orchestrator carries a real working prompt; the other three are scaffolding for the factory model, not finished agents.

## System requirements

- Windows 10 (version 2004+) or Windows 11
- Administrator privileges for install
- 16 GB RAM recommended (8 GB minimum)
- 50 GB free disk (Ubuntu rootfs + OpenClaw runtime + Studio)
- Hardware virtualization enabled in BIOS (VT-x / AMD-V). WSL2 is required and there is no WSL1 fallback: if virtualization is unavailable the installer stops with a named message rather than installing something that cannot run ClawFactory's controls

## Installation

1. Download `ClawFactory-Secure-Setup.exe` from the [Releases](../../releases) page (~440 MB, which carries the bundled Ubuntu rootfs and Studio).
2. Right-click → **Run as administrator**.
3. Walk the wizard: provider → API key → security acknowledgement → Install.
4. Wait 10–20 minutes. The installer reboots once if WSL2 features need DISM enable, then auto-resumes.
5. Done. The desktop icon and the Start Menu **ClawChat** entry both open ClawChat, the chat window. ClawFactory Studio, the control panel, is a separate window.

## Security

Defense in depth: multiple independent layers, each scoped to a different attack surface:

| Attack | Control | Class |
|---|---|---|
| API key theft via `.env` grep / process enumeration | Key in DPAPI, piped via stdin to `auth-profiles.json` mode 600. Never on a command line or in `.env`. | Structural |
| Agent exfiltration to arbitrary endpoints | nftables egress firewall on `clawuser`'s UID. Provider, ClawFactory's own site, package sources, and the addresses you allow. | Structural, address-scoped |
| Agent sending mail | Root-owned broker; no send path runs at the agent's UID; SMTP blocked for that UID at the firewall. | Structural |
| Prompt injection to lateral movement | WSL `automount=false`; Windows folders reachable only through grants. Non-root, no sudo. `SOUL.md` root-owned, mode 444, immutable. | Structural |
| Accidental or hostile deletion in a granted folder | `rm` on the agent's PATH hands deletes to a root-owned 30-day quarantine. | Structural for deletion by name |
| LAN-side gateway hijack | `gateway.bind=loopback` + Windows Firewall inbound-deny on TCP/8787. | Structural |
| Supply chain on `install.sh` and the rootfs | SHA-256 pins in `setup.ps1`; install aborts on mismatch. | Structural |
| Runaway spend, tampered safety rules at turn time | Turn gate reads the spend meter and re-checks the SOUL digest before each turn. | **Gateway path, not structural** |

The last row is a different kind of promise from the ones above it, and that difference is the whole reason [SECURITY_FINDINGS.md](SECURITY_FINDINGS.md) exists. Read it before you rely on any of this. It states which controls the operating system enforces, which depend on the agent's own uid boundary, and every residual we know about, including the ones that make the table above narrower than it looks.

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
7. Per-agent `auth-profiles.json` (mode 600) present for all 5 agent identities: the four named agents plus `main`, which has a profile but no `agent.md`
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

> Checks 12–19 are the Grants + spend-governor substrate. Like the other
> WSL-dependent checks they SKIP (not FAIL) when the smoke test runs as
> `NT AUTHORITY\SYSTEM`.
>
> Seven further checks, numbered 20 to 26, run only with `-AgentChecks`. They
> drive real agent turns to verify the grant boundary from the agent's own point
> of view. They need a working provider key and a running gateway, they are slow,
> and they are opt-in for that reason. The 19 above are what the command shown
> here runs.

Note what the smoke test is and is not: it confirms the controls are installed and wired. It is not the evidence that they hold against a hostile agent. That evidence is consumer-side, asking the agent itself to cross each boundary on a clean machine, and it lives in `docs/session_reports/`.

## Known limitations

- **SmartScreen "Unknown publisher" warning on unsigned builds.** Releases built via `scripts\build_release.ps1` are Authenticode-signed (Azure Artifact Signing, individual identity, Bret Mckinney) and timestamped. A local dev build compiled directly with `ISCC.exe` is unsigned and cannot be signed; click "More info -> Run anyway" for those.
- **No WSL1 fallback (changed in v1.4.5).** Earlier releases downgraded to WSL1 when `HCS_E_HYPERV_NOT_INSTALLED` fired. That path was removed: eleven of ClawFactory's controls are systemd units, WSL1 has no systemd, and the install could not complete on it — it ran for roughly twenty minutes and then failed on a gateway health probe, telling the user nothing about the real cause. The installer now stops immediately with a message naming the two things a person can act on (restart; BIOS/UEFI virtualization). On hardware without nested virtualization ClawFactory does not install.
- **Provider model IDs are forward-looking** (`grok-4-1-fast`, `gpt-5`, `claude-sonnet-4-6`, `gemini-2.5-pro`). If your provider's catalog uses a different name when you install, change it via `Switch AI Provider` from the Start Menu.
- **The egress allowlist matches on address, not hostname.** Anything served from an address ClawFactory already allows is reachable. This is permanent for v1 and is stated in full in [SECURITY_FINDINGS.md](SECURITY_FINDINGS.md).

## Building from source

```powershell
.\scripts\build_release.ps1
```

This is the build command. It runs nine pre-build gates, compiles with Inno Setup, and signs the result. The nine, in the order the script runs them, are: SOUL, bundle, interpolation, worktree, Studio, version, persona, workspace SOUL, rootfs. They check that the SOUL, persona and composed-workspace-SOUL digests pinned in `setup.ps1` match the files on disk, that every preflight-required resource is actually bundled, that no shipped `.ps1` interpolates a variable the file never defines, that the bundled bytes are the committed bytes, that the embedded Studio payload and the bundled Ubuntu rootfs are the pinned ones, and that the two version literals agree. Each one fails the build on drift and none of them auto-correct. The version gate has a second half that cannot run until after compilation: the compiled digest must not contradict a version already recorded in `released-versions.tsv`.

Output: `Output\ClawFactory-Secure-Setup.exe`. Requires the bundled rootfs at `resources\ubuntu-rootfs.tar.gz` (gitignored; see [Build prerequisites in CONTRIBUTING.md](CONTRIBUTING.md#build-prerequisites) for the source URL and digest). The `.iss` and `setup.ps1` are the only sources of truth: every line is auditable before you trust a build.

### Local dev compiles

For a quick local check that the `.iss` still compiles, `ISCC.exe` on its own is fine:

```cmd
"C:\Program Files (x86)\Inno Setup 6\ISCC.exe" ClawFactory-Secure-Setup.iss
```

Its output is a legitimate dev build and **cannot be signed**: `scripts\sign_installer.ps1` refuses any binary that `build_release.ps1` did not produce, so a compile that skipped the gates cannot become a release. Nothing stops you compiling; it just doesn't get you a shippable artifact.

### Producing a signed release build

Any installer uploaded to a GitHub Release must be Authenticode-signed via Azure
Artifact Signing. `scripts\build_release.ps1` is the whole path: it runs the gates,
compiles with Inno Setup, records a build stamp over the compiled bytes, and then
signs the `.exe` via `scripts\sign_installer.ps1`.

```powershell
.\scripts\build_release.ps1
```

Requires `AZURE_SIGNING_*` values in a repo-root `.env` (see `signing\metadata.json.template`
for the fields) and the service principal to hold the **Artifact Signing Certificate
Profile Signer** role on the `clawfactory-signing` account. Signing fails loudly
(non-zero exit) on any error. Never proceed with an unsigned `.exe`.

`sign_installer.ps1` refuses to sign a binary carrying no build stamp, or one whose
bytes do not match the stamp beside it. To re-sign an existing binary in an emergency,
pass `-SignWithoutBuildStamp`; it prints a banner saying the gates were not enforced.
Be honest about what that check is worth: the stamp is an ordinary file, so anyone who
can run the signer can write one. It is a guard against the documented shortcut being
taken under time pressure, not against an attacker who already has local execution.

## License

[Apache License 2.0](LICENSE). Copyright 2026 Frontier Automation Systems LLC. See [NOTICE](NOTICE).

Apache-2.0 was chosen deliberately over a source-available licence: attribution is the mechanism by which a free release builds a reputation, Apache-2.0 requires it, and its patent grant makes organisations comfortable evaluating the code.

## Security disclosure

Email **support@clawfactory.app** with details. Please **do not** open a public issue for security vulnerabilities. We respond within 72 hours. See [SECURITY.md](SECURITY.md) for the full policy.
