# ClawFactory Secure Setup

Hardened OpenClaw installer for Windows.

`MIT License` · `Windows 11` · `Free`

## The problem it solves

Running an LLM-powered agent on your own machine sounds great until you read the install instructions: paste your API key into a `.env` file, give the runtime full filesystem access, run a Docker container as your user, and trust that the agent won't curl an attacker-controlled endpoint when a prompt-injected document tells it to. None of those defaults are accidents — they're what `pip install` and a hand-rolled compose file produce. They're also what makes most "local AI" setups one bad prompt away from leaking your provider key, your `~/.aws/`, or your inbox.

ClawFactory Secure Setup is a single signed `.exe` that bootstraps an OpenClaw runtime where every default is the opposite. WSL2 with Windows automount disabled, a non-sudo `clawuser`, rootless Docker, an nftables egress firewall scoped to that user's UID, the OpenClaw gateway bound only to `127.0.0.1`, a Windows Firewall inbound-deny on port 8787, the API key stored in DPAPI Credential Manager (never on disk inside WSL), and a `SOUL.md` safety policy hash-pinned at file mode 444. One installer, fifteen steps, no telemetry, fully auditable PowerShell — every control maps to a real `setup.ps1` line you can read before you trust it.

## What it installs

After you run the wizard, you have: a Windows 11 box with WSL2 + Ubuntu installed and configured so `/etc/wsl.conf` has `automount=false` (no Windows files visible to the agent runtime); a non-root `clawuser` inside that distro with no `sudo` membership; Docker Engine in rootless mode under `clawuser`; an nftables firewall on the WSL kernel that drops every outbound packet from `clawuser` except DNS, loopback, and the IPv4 addresses of the LLM provider host you picked plus a small base list (GitHub, npm, Docker Hub, OpenClaw and ClawHub); the OpenClaw runtime fetched from a SHA-256-pinned `install.sh` and configured with `gateway.bind=loopback`, `gateway.port=8787`, `gateway.mode=local`; four pre-created agent directories at `~/.openclaw/agents/{orchestrator,skill-scout,skill-builder,publisher}/` with role-specific `agent.md` prompts staged by `bootstrap.ps1`; a `~/.openclaw/SOUL.md` hash-pinned at mode 444 with its SHA-256 substituted into the orchestrator's `agent.md` so the agent's startup integrity check is a real check, not a placeholder; the chosen provider's API key written to `~/.openclaw/auth-profiles.json` mode 600 (and never to a `.env`); a Windows Firewall inbound-deny rule blocking TCP/8787 from any LAN; Start Menu shortcuts for Kill Switch, Switch AI Provider, Dashboard, Rename Your Assistant, and README; and a desktop shortcut that runs the launcher to start the gateway and drop you into `openclaw chat`.

## Security controls

Four real attack vectors and the specific control that stops each. Every control number maps to a line in [`setup.ps1`](setup.ps1).

**1. API key theft via `.env` grep or process enumeration.**
The provider key is read from Windows Credential Manager (DPAPI, tied to your Windows user) and written directly to `~/.openclaw/auth-profiles.json` (mode 600) inside WSL. It never lands on a Windows command line, never appears in a `.env` file, and never shows up in `Get-Process`. Implementation in `Step-WireProviderKey` ([`setup.ps1` line 806](setup.ps1#L806)) uses an inline P/Invoke to `CredReadW` and pipes the value via `wsl.exe` stdin to a base64-decode-and-write bash script.

**2. Agent exfiltration to arbitrary endpoints.**
An nftables egress firewall on the WSL kernel scoped to `clawuser`'s UID drops every outbound TCP except DNS, loopback, and the IPv4 addresses of the chosen provider's host plus a small base allowlist. A fully-compromised agent can reach the LLM provider you picked and nothing else — even a successful prompt injection cannot POST your key to an attacker-controlled domain. Implementation in `Step-EgressFirewall` ([`setup.ps1` line 347](setup.ps1#L347)). The base allowlist is the literal set of hosts in lines 351–360.

**3. Prompt injection to lateral movement.**
WSL automount is set to `false`, so the agent's runtime cannot see `C:\Users\<you>\Documents\`, `C:\Users\<you>\.aws\`, or any other Windows path. The agent runs as a non-sudo user inside rootless Docker, so even a successful container escape does not get root in WSL, and the WSL user does not have sudo. `SOUL.md` is mode 444 and its SHA-256 is pinned into the orchestrator's `agent.md` — the agent refuses to execute its first turn if the live hash does not match. Implementation across `Step-ConfigureWslConf` ([`setup.ps1` line 243](setup.ps1#L243)), `Step-CreateClawUser` ([`setup.ps1` line 274](setup.ps1#L274)), `Step-InstallDocker` ([`setup.ps1` line 317](setup.ps1#L317)), and `Step-ApplySafetyRules` ([`setup.ps1` line 764](setup.ps1#L764)).

**4. LAN-side agent hijacking.**
The OpenClaw gateway binds to `127.0.0.1:8787` only (`gateway.bind=loopback`). A Windows Firewall inbound-deny rule blocks TCP/8787 from any other LAN machine even if the gateway is misconfigured. Implementation in `Step-ConfigureOpenClaw` ([`setup.ps1` line 685](setup.ps1#L685)) and `Step-WindowsFirewallDeny` ([`setup.ps1` line 790](setup.ps1#L790)).

## Provider options

The wizard offers six choices:

- **Grok (xAI)** — default model `grok-4-1-fast`, key stored in DPAPI
- **OpenAI (ChatGPT)** — default `gpt-5`, DPAPI
- **Anthropic Claude** — default `claude-sonnet-4-6`, DPAPI
- **Google Gemini** — default `gemini-2.5-pro`, DPAPI (free tier available)
- **Ollama (local)** — default `llama3.1:8b`, **runs entirely on your machine, zero outbound calls**, no key needed
- **Configure later** — finishes the install with no provider; you can run `switch-provider.ps1` from the Start Menu when ready

The egress firewall allowlist is built from the chosen provider's host. Picking Ollama means the firewall never adds an external API host at all — your machine never opens an outbound HTTPS connection for inference.

## Requirements

- Windows 10 (version 2004+) or Windows 11
- Administrator privileges for install
- ~2 GB free disk for WSL2 + Ubuntu + Docker
- Internet connection during install (for WSL2, Docker, OpenClaw, and your chosen provider's package set)

## Installation

1. Download `ClawFactory-Secure-Setup.exe` from the [Releases](../../releases) page.
2. Right-click → **Run as administrator**.
3. Walk the wizard: provider → API key → security acknowledgement → Install.
4. Wait 10–20 minutes (longer if you picked Ollama — it pulls a ~5 GB model).
5. The installer prints a "what to do next" block at the end and adds a desktop icon.

## After install

You have a desktop **ClawFactory** icon (lobster) and a Start Menu **ClawFactory** group with: ClawFactory Studio (browser dashboard), ClawFactory Kill Switch, Rename Your Assistant, Switch AI Provider, ClawFactory README, and Uninstall ClawFactory.

To start chatting:

```powershell
# 1. Start the gateway (one-time after each WSL boot)
wsl -d Ubuntu -u clawuser -- bash -lc "systemctl --user start openclaw-gateway"

# 2. Verify it's reachable
curl http://127.0.0.1:8787/status

# 3. Open a chat session in the terminal
wsl -d Ubuntu -u clawuser -- bash -lc "openclaw chat"
```

Or just double-click the desktop icon — the launcher does steps 1 and 2 for you, then opens the chat in Windows Terminal.

## Building from source

**Prerequisites:**
- [Inno Setup 6](https://jrsoftware.org/isdl.php) (any 6.x build)
- PowerShell 5.1+ (ships with Windows 10/11)

**Build:**

```cmd
"C:\Program Files (x86)\Inno Setup 6\ISCC.exe" ClawFactory-Secure-Setup.iss
```

**Output:** `Output\ClawFactory-Secure-Setup.exe`

The compile is one step; there's no Node, npm, or external toolchain. The `.iss` and `setup.ps1` are the only sources of truth — every line is auditable before you ship a build.

## License

[MIT](LICENSE). Copyright © 2026 Frontier Automation Systems LLC.

## Security disclosure

If you find a security issue, please **do not** open a public issue. Email security@frontierholdingsllc.com with details. We respond within 72 hours.
