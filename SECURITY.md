# Security Policy

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| 1.0.x   | :white_check_mark: |
| < 1.0   | :x:                |

Security fixes land on the latest minor of the current major. Older releases do not receive backports.

## Security Model

ClawFactory Secure Setup is built on **defense in depth**: multiple independent layers, each scoped to a different attack surface, so no single failure is catastrophic. A bad prompt, a compromised model, a misconfigured agent, or a leaked credential should each be stopped by something the next layer doesn't depend on. The controls below describe each layer with its concrete implementation site.

## What We Protect Against

### 1. API key theft via `.env` grep or process enumeration

**Attack:** A malicious skill, a leaked container, or a compromised agent reads `.env` files, environment variables, or the process list looking for API keys.

**Control:** The provider key is read from Windows Credential Manager (DPAPI, tied to your Windows user) into a `SecureString`-equivalent in PowerShell, then base64-piped via `wsl.exe` stdin to a script that writes it directly to `~/.openclaw/auth-profiles.json` mode 600. The key never appears on a command line, never lands in `.env`, never enters the WSL process environment.

**Implementation:** `Step-WireProviderKey`, [`setup.ps1` line 806](setup.ps1#L806).

**Limitations:** Once an agent makes a real LLM call, the key is in memory. Anyone with `clawuser`-level access to that process at the moment it makes a call could read it from the process heap. The egress firewall (#2) still caps where it could be exfiltrated to.

### 2. Agent exfiltration to arbitrary endpoints

**Attack:** A prompt injection or compromised skill instructs the agent to POST sensitive data (the user's prompts, the API key, contents of an attached file) to an attacker-controlled URL.

**Control:** An nftables firewall in the WSL kernel scoped to `meta skuid != clawuser return` (clawuser only) drops every outbound packet except: DNS, loopback (lo), `ct state established,related`, and `ip daddr @allowed_ipv4 tcp dport 443` where `allowed_ipv4` is a dynamic set populated from `getent ahostsv4` against a static base hostlist (GitHub, npm, Docker Hub, OpenClaw, ClawHub) plus the chosen provider's host. Everything else is `counter drop`.

**Implementation:** `Step-EgressFirewall`, [`setup.ps1` line 347](setup.ps1#L347). The base allowlist is in lines 351–360. The set has a 6h timeout.

**Limitations:** The 6h timeout means provider IPs that rotate behind a CDN can drop out of the set; switching providers via `switch-provider.ps1` re-resolves and re-adds. If the provider you picked is itself the attacker's proxy (compromised LLM endpoint), this firewall trusts that endpoint by definition.

### 3. Prompt injection to lateral movement

**Attack:** A document the agent reads contains adversarial instructions ("then run `cat /mnt/c/Users/.../.aws/credentials`"). The agent obeys.

**Control:** Multiple. `automount=false` in `/etc/wsl.conf` means the agent runtime cannot see `/mnt/c/` at all — it has no path to your Windows files. The agent runs as `clawuser` (non-root, no sudo membership — the `gpasswd -d clawuser sudo` is explicit). Docker is rootless. `SOUL.md` is mode 444 and its SHA-256 is pinned into the orchestrator's `agent.md`; on first turn the agent computes the live hash, compares to the pin, and refuses every tool call on mismatch.

**Implementation:** `Step-ConfigureWslConf`, [`setup.ps1` line 243](setup.ps1#L243); `Step-CreateClawUser`, [line 274](setup.ps1#L274); `Step-InstallDocker`, [line 317](setup.ps1#L317); `Step-ApplySafetyRules`, [line 764](setup.ps1#L764). Hash substitution into orchestrator prompt: `bootstrap.ps1` `Get-SoulSha256()`.

**Limitations:** The agent can still write to its workspace folder (`~/.openclaw/factory/`) and the egress firewall allowlist (#2). An attacker who controls the prompt and accepts being limited to those destinations can still cause damage within scope. The integrity check assumes the user hasn't rotated `SOUL.md` without re-pinning the orchestrator prompt — `bootstrap.ps1` handles this on installer-driven changes; manual edits do not.

### 4. LAN-side agent hijacking

**Attack:** Another machine on the same LAN connects to the OpenClaw gateway and issues commands as if they were the local user.

**Control:** The gateway is configured with `gateway.bind=loopback` (binds `127.0.0.1` only). A Windows Firewall inbound-deny rule on TCP/8787 (`Direction=Inbound, Action=Block, Profile=Any`) is added during install — belt-and-suspenders against any future misconfiguration that flips the bind to `0.0.0.0`.

**Implementation:** `Step-ConfigureOpenClaw`, [`setup.ps1` line 685](setup.ps1#L685); `Step-WindowsFirewallDeny`, [line 790](setup.ps1#L790).

**Limitations:** None within the threat model. A user who explicitly disables the firewall rule and rebinds the gateway to `0.0.0.0` is outside scope.

### 5. Supply chain attack on the upstream installer

**Attack:** `openclaw.ai/install.sh` is replaced (DNS hijack, CDN compromise, malicious upstream commit) with a script that backdoors the install.

**Control:** SHA-256 pin at [`setup.ps1` line 26](setup.ps1#L26). The fetcher in `Step-InstallOpenClaw` ([line 446](setup.ps1#L446)) computes `sha256sum` after `curl`, compares to the pin, and aborts with exit 43 on mismatch (or exit 42 if the pin is the placeholder string).

**Implementation:** `Step-InstallOpenClaw`, [`setup.ps1` line 446](setup.ps1#L446).

**Limitations:** The pin protects against a runtime swap of `install.sh` but **not** against a compromised upstream that publishes a malicious `install.sh` with a new hash that we then update. Pin rotation requires us to verify each new upstream version. Below the `install.sh` layer, the npm packages and apt repos it pulls are not pinned by us — that trust bottoms out at OpenClaw, npmjs.org, and download.docker.com.

### 6. Filesystem snooping (agent reading Windows files)

**Attack:** The agent uses standard filesystem tools to read `C:\Users\<you>\Documents\`, browser cookies, SSH keys, AWS credentials.

**Control:** WSL `automount=false` ([`setup.ps1` line 250](setup.ps1#L250)). `/mnt/c/` is not mounted inside the WSL distro. From `clawuser`'s perspective, `C:\` does not exist as a path.

**Implementation:** `Step-ConfigureWslConf`, [`setup.ps1` line 243](setup.ps1#L243).

**Limitations:** A user who manually `wsl --mount` or edits `/etc/wsl.conf` after install gives back this access — both require admin and are outside the default threat model. Files the user explicitly copies into `/home/clawuser/` ARE accessible to the agent (intentionally — that's how you give it data).

### 7. Session hijacking

**Attack:** A malicious local process tries to attach to or replay the operator's gateway session, impersonating the user.

**Control:** The gateway requires Ed25519 device-identity-signed connect for any operator-scoped action. A token alone grants zero scopes; an unsigned connect is rejected with `CONTROL_UI_DEVICE_IDENTITY_REQUIRED`. The signing key is per-machine, persisted by Studio (or any compatible client) in DPAPI-protected storage.

**Implementation:** OpenClaw gateway protocol, enforced by the runtime fetched in step 8.

**Limitations:** A process running as the same Windows user that already paired its device can sign valid connect requests — the model is "trust the local user," not "trust no one." Cross-user isolation is provided by Windows DPAPI tying the device key to the account.

### 8. Social engineering / jailbreak attempts

**Attack:** A user (or an attacker who tricks the user) types a prompt designed to override the agent's safety boundaries.

**Control:** `SOUL.md` (mode 444, hash-pinned in the orchestrator prompt) hard-codes refusal patterns: no `git push`, `clawhub publish`, file writes outside the workspace, or any tool not on the allowlist without an explicit `GO` from the user in the same thread. The agent's prompt instructs it to refuse with a fixed template if SOUL.md would be violated.

**Implementation:** [`resources/safety-rules.md`](resources/safety-rules.md), staged into `~/.openclaw/SOUL.md` mode 444 by `Step-ApplySafetyRules` ([`setup.ps1` line 764](setup.ps1#L764)).

**Limitations:** This is prompt-level enforcement. A model that ignores its system prompt or that's been finetuned to bypass safety rules is outside scope — the runtime-level controls (#1, #2, #3, #6) are what catch this. SOUL.md is the policy layer; the firewall and filesystem isolation are the enforcement layer.

## What We Cannot Protect Against

- **In-context prompt injection that stays within allowed behavior.** If the agent is permitted to write to `~/.openclaw/factory/` and a prompt tells it to write garbage there, the firewall and filesystem isolation don't object.
- **Model-level jailbreaks that don't require network or filesystem access.** A model that says something harmful in a chat reply is a model-vendor problem, not an installer problem.
- **User intentionally expanding permissions via Settings.** The Permissions page in Studio exists so users can opt into broader access. We don't override their stated intent.
- **A compromised upstream `openclaw.ai/install.sh` between releases.** If a malicious upstream ships and we update the pin without catching it, users who upgrade get the malicious version. Mitigation: verify each pin rotation against a trusted source.
- **Physical access to the machine.** BitLocker/FileVault is the appropriate layer. The installer cannot encrypt for you.
- **A malicious provider endpoint.** If you point the firewall allowlist at `evil-llm-vendor.com`, your prompts go to `evil-llm-vendor.com`. Your provider choice is your trust decision.

## Scope

This installer hardens the OpenClaw runtime environment on Windows. It does not audit or take responsibility for:

- **OpenClaw's own codebase** — the runtime is fetched from `openclaw.ai/install.sh` (SHA-256-pinned but its internal correctness is OpenClaw's domain).
- **The chosen LLM provider's data handling** — what xAI, OpenAI, Anthropic, or Google do with prompts you send them is governed by their terms.
- **Third-party skills installed after setup.** ClawHub skills are user-installed; we do not pre-validate them.

## Reporting a Vulnerability

**Do not open a public GitHub issue for security vulnerabilities.** Email **hello@avitalresearch.com** with:

- A description of the vulnerability.
- Steps to reproduce.
- Potential impact.
- Optional: a suggested fix or mitigation.

We will respond within 72 hours. We treat responsible disclosure as the default and will credit reporters in release notes unless asked not to.
