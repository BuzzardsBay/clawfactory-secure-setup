# Security Policy

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| 1.3.x   | :white_check_mark: |
| < 1.3   | :x:                |

Security fixes land on the latest minor of the current major. Older releases do not receive backports.

## Security Model

ClawFactory Secure Setup is built on **defense in depth**: multiple independent layers, each scoped to a different attack surface, so no single failure is catastrophic. A bad prompt, a compromised model, a misconfigured agent, or a leaked credential should each be stopped by something the next layer doesn't depend on. The controls below describe each layer with its concrete implementation site.

> **Two classes of guarantee.** ClawFactory's controls split into two kinds, and
> the distinction matters when you assume the agent itself may be hostile.
> **Structural** controls (file isolation, egress allowlist, inbound deny,
> credential-at-rest, safety-rules *file integrity*) are
> enforced by the OS/kernel and hold against **both** a network attacker **and** a
> hostile agent running as `clawuser`. The user kill switch was in this list until
> v1.4.4 and has been removed from it: it is an action you take, not a boundary
> that holds, and it stopped nothing at all on every release up to v1.4.3. **Gateway-path** controls (spend cap,
> chatCompletions gating, safety-rules *enforcement at turn time*) hold on the
> path through the local gateway but are **advisory** against an agent that
> starts the runtime by another route. The full split, the one accepted residual
> (Door-2), and its committed v2 closure are documented in
> [`SECURITY_FINDINGS.md`](SECURITY_FINDINGS.md).

## What We Protect Against

### 1. API key theft via `.env` grep or process enumeration

**Attack:** A malicious skill, a leaked container, or a compromised agent reads `.env` files, environment variables, or the process list looking for API keys.

**Control:** The provider key is read from Windows Credential Manager (DPAPI, tied to your Windows user) into a `SecureString`-equivalent in PowerShell, then base64-piped via `wsl.exe` stdin to a script that writes it directly to `~/.openclaw/auth-profiles.json` mode 600. The key never appears on a command line, never lands in `.env`, never enters the WSL process environment.

**Implementation:** `Step-WireProviderKey`, `setup.ps1`.

**Limitations:** Once an agent makes a real LLM call, the key is in memory. Anyone with `clawuser`-level access to that process at the moment it makes a call could read it from the process heap. The egress firewall (#2) still caps where it could be exfiltrated to.

### 2. Agent exfiltration to arbitrary endpoints

**Attack:** A prompt injection or compromised skill instructs the agent to POST sensitive data (the user's prompts, the API key, contents of an attached file) to an attacker-controlled URL.

**Control:** An nftables firewall in the WSL kernel scoped to `meta skuid != clawuser return` (clawuser only) drops every outbound packet except: DNS **to the WSL resolver only** (`ip daddr @dns_resolvers udp/tcp dport 53`, so an arbitrary resolver such as `1.1.1.1` is dropped), loopback (lo), `ct state established,related`, and `ip daddr @allowed_ipv4 tcp dport 443`. Everything else is `counter drop`.

`allowed_ipv4` is a dynamic set populated from `getent ahostsv4`. As of v1.4.0 the base hostlist that seeds it and that no user switch can revoke is: `openclaw.ai`, `docs.openclaw.ai`, `nodejs.org`, `deb.nodesource.com`, `archive.ubuntu.com`, `security.ubuntu.com`, `ports.ubuntu.com`, `esm.ubuntu.com`, `ppa.launchpad.net`, plus the chosen provider's hosts, plus the five model-provider endpoints in `AUX_HOSTS` (`api.anthropic.com`, `console.anthropic.com`, `api.openai.com`, `auth.openai.com`, `api.x.ai`) which are added unconditionally regardless of which provider you picked. The GitHub, npm and ClawHub hosts are **not** in that set: they live in a separate `toolchain_ipv4` set that the Web access panel can switch off (v1 Guard 3).

**Implementation:** `Step-EgressFirewall`, `setup.ps1`. The set elements carry a 6h timeout and are refreshed additively by a timer.

**Limitations:** **Matching is by resolved network address, not by hostname.** Anything co-hosted with something already allowed is reachable, and on shared CDN infrastructure that is not a corner case. One measured consequence: a real `openclaw skills install` completes with the software-source switch OFF, because `clawhub.ai` resolves to an address it shares with `openclaw.ai`, a permanent base host. The set-membership refresh means provider IPs that rotate behind a CDN can drop out of the set; switching providers via `switch-provider.ps1` re-resolves and re-adds. If the provider you picked is itself the attacker's proxy (compromised LLM endpoint), this firewall trusts that endpoint by definition. **DNS exfiltration is reduced, not eliminated:** the agent can no longer pick an arbitrary resolver, but a lookup through the permitted WSL resolver still forwards the (attacker-encoded) hostname upstream. Eliminating it needs a local allowlist-only resolver. See `docs/session_reports/SECFIX_DNS_SOUL_2026-07-14.md`.

### 3. Prompt injection to lateral movement

**Attack:** A document the agent reads contains adversarial instructions ("then run `cat /mnt/c/Users/.../.aws/credentials`"). The agent obeys.

**Control:** Multiple. `automount=false` in `/etc/wsl.conf` means the agent runtime cannot see `/mnt/c/` at all — it has no path to your Windows files. The agent runs as `clawuser` (non-root, no sudo membership — the `gpasswd -d clawuser sudo` is explicit). There is **no Docker/container boundary** — Docker was removed in SECFIX_CLOSE_DOORS (decision A) because nothing ever ran a container; the agent is a `clawuser` process. `SOUL.md` is **root-owned, mode 444, and `chattr +i` (immutable)** — the agent's own UID cannot write, chmod, or delete-and-recreate it — and its SHA-256 is checked **in code before every turn** (`Test-SoulIntegrity` / the `openclaw` shim's turn gate); on mismatch the turn is refused before the agent runs. The same applies to the workspace `SOUL.md` that OpenClaw actually injects into the prompt.

**Implementation:** `Step-ConfigureWslConfig`; `Step-CreateClawUser`; `Step-ApplySafetyRules` (root-own + immutable + pin); `Step-FreezeInjectedSoul` (the injected copy); `Step-InstallTurnGate` (the `openclaw` shim + `clawfactory-turn-gate.sh`). Code gate: `Test-SoulIntegrity` in `resources/clawfactory-grants.ps1`, called from `Invoke-GatedAgentTurn`.

**Limitations:** The agent can still write to its workspace folder and reach the egress allowlist (#2). An attacker who controls the prompt and accepts being limited to those destinations can still cause damage within scope. Turn-time enforcement (the SOUL hash check + spend cap) is a **gateway-path** guarantee, not a structural one. It covers turns launched via the `openclaw` CLI (the shim intercepts them) **and**, since v1.0.43, turns driven through the gateway's `chatCompletions` HTTP endpoint — a root-owned proxy now owns `127.0.0.1:8787` and gates that path with the same turn gate, moving the real gateway to private `127.0.0.1:8788` (Door-1, closed and verified). What it does **not** cover: because the agent and the gateway share the `clawuser` UID, a deliberate full-path invocation of the runtime bypasses both the shim and the proxy (**Door-2**, an accepted v1 residual). The `SOUL.md` *file* remains immutable to `clawuser` either way — only its turn-time *enforcement* is bypassable. Actor model, harm ceiling, and the v2 closure: [`SECURITY_FINDINGS.md`](SECURITY_FINDINGS.md).

### 4. LAN-side agent hijacking

**Attack:** Another machine on the same LAN connects to the OpenClaw gateway and issues commands as if they were the local user.

**Control:** The gateway is configured with `gateway.bind=loopback` (binds `127.0.0.1` only). A Windows Firewall inbound-deny rule on TCP/8787 (`Direction=Inbound, Action=Block, Profile=Any`) is added during install — belt-and-suspenders against any future misconfiguration that flips the bind to `0.0.0.0`.

**Implementation:** `Step-ConfigureOpenClaw`, `setup.ps1`; `Step-WindowsFirewallDeny`, `setup.ps1`.

**Limitations:** None within the threat model. A user who explicitly disables the firewall rule and rebinds the gateway to `0.0.0.0` is outside scope.

### 5. Supply chain attack on the upstream installer

**Attack:** `openclaw.ai/install.sh` is replaced (DNS hijack, CDN compromise, malicious upstream commit) with a script that backdoors the install.

**Control:** SHA-256 pin at the top of `setup.ps1`. The fetcher in `Step-InstallOpenClaw` (`setup.ps1`) computes `sha256sum` after `curl`, compares to the pin, and aborts with exit 43 on mismatch (or exit 42 if the pin is the placeholder string).

**Implementation:** `Step-InstallOpenClaw`, `setup.ps1`.

**Limitations:** The pin protects against a runtime swap of `install.sh` but **not** against a compromised upstream that publishes a malicious `install.sh` with a new hash that we then update. Pin rotation requires us to verify each new upstream version. Below the `install.sh` layer, the npm packages and apt repos it pulls are not pinned by us — that trust bottoms out at OpenClaw, npmjs.org, and the Ubuntu apt repos. (download.docker.com is no longer in that set — Docker was removed in SECFIX_CLOSE_DOORS, decision A.)

### 6. Filesystem snooping (agent reading Windows files)

**Attack:** The agent uses standard filesystem tools to read `C:\Users\<you>\Documents\`, browser cookies, SSH keys, AWS credentials.

**Control:** WSL `automount=false` (`setup.ps1`). `/mnt/c/` is not mounted inside the WSL distro. From `clawuser`'s perspective, `C:\` does not exist as a path.

**Implementation:** `Step-ConfigureWslConfig`, `setup.ps1`.

**Limitations:** A user who manually `wsl --mount` or edits `/etc/wsl.conf` after install gives back this access — both require admin and are outside the default threat model. Files the user explicitly copies into `/home/clawuser/` ARE accessible to the agent (intentionally — that's how you give it data).

### 7. Session hijacking

**Attack:** A malicious local process tries to attach to or replay the operator's gateway session, impersonating the user.

**Control:** The gateway requires Ed25519 device-identity-signed connect for any operator-scoped action. A token alone grants zero scopes; an unsigned connect is rejected with `CONTROL_UI_DEVICE_IDENTITY_REQUIRED`. The signing key is per-machine, persisted by Studio (or any compatible client) in DPAPI-protected storage.

**Implementation:** OpenClaw gateway protocol, enforced by the runtime fetched in step 8.

**Limitations:** A process running as the same Windows user that already paired its device can sign valid connect requests — the model is "trust the local user," not "trust no one." Cross-user isolation is provided by Windows DPAPI tying the device key to the account.

### 8. Social engineering / jailbreak attempts

**Attack:** A user (or an attacker who tricks the user) types a prompt designed to override the agent's safety boundaries.

**Control:** `SOUL.md` (mode 444, hash-pinned in the orchestrator prompt) hard-codes refusal patterns: no `git push`, `clawhub publish`, file writes outside the workspace, or any tool not on the allowlist without an explicit `GO` from the user in the same thread. The agent's prompt instructs it to refuse with a fixed template if SOUL.md would be violated.

**Implementation:** [`resources/safety-rules.md`](resources/safety-rules.md), staged into `~/.openclaw/SOUL.md` mode 444 by `Step-ApplySafetyRules` (`setup.ps1`).

**Limitations:** This is prompt-level enforcement. A model that ignores its system prompt or that's been finetuned to bypass safety rules is outside scope — the runtime-level controls (#1, #2, #3, #6) are what catch this. SOUL.md is the policy layer; the firewall and filesystem isolation are the enforcement layer.

### 9. The agent sending email on its own initiative

**Attack:** A prompt injection tells the agent to mail a granted file, or a stolen credential, to an address the attacker controls.

**Control:** The agent has no send capability at all. `clawfactory-send` on its PATH hands the message to a root-owned broker and returns `pending`; it transmits nothing. The message leaves only when the user approves that exact message in Studio, and the approval is single-use and bound to the exact payload: change a recipient, the subject, the body or an attachment and the approval is void. The agent holds no mail credential, SMTP ports are blocked for its UID at the firewall including to a relay on loopback, and attachments are copied into a root-owned staging area at request time so editing a file after approval changes nothing about what is sent.

**Implementation:** `resources/clawfactory-sendd.js` (broker, root), `resources/clawfactory-send.js` (the agent-side stub), `resources/send-smtp.js`; approval UI in Studio's Approvals panel.

**The invariant:** no send path may ever run as uid 1000. The broker runs as root precisely because the agent and the gateway are the same security principal, so any send capability placed at that uid would be one the agent could reach directly.

**Limitations:** This covers **email**. It is not a claim that no data can leave your machine. Your agent talks to a hosted AI model, and anything it can read it can send there. It also does not cover a user who approves a message they did not read.

### 10. Destructive deletion inside a granted folder

**Attack:** The agent, acting on a bad instruction or its own mistake, deletes the user's files in a folder they granted it.

**Control:** The `rm` on the agent's PATH hands deletes under `/workspaces` to a root-owned quarantine. The file is held for 30 days and the user can restore it from Studio. The hold itself is structural: the quarantine is root-owned and the agent's UID cannot reach into it.

**Implementation:** `resources/quarantine-lib.js`, `resources/clawfactory-quarantine-rm.js`, `resources/clawfactory-quarantined.js`; restore UI in Studio's Recently-deleted panel.

**Limitations:** This covers **deletion by name**, which is how deletion is ordinarily expressed. It does not cover every possible way a program can destroy a file: `/bin/rm` by full path, `find -delete`, `unlink()` from a script, or truncating a file to zero bytes all bypass it, and nothing outside `/workspaces` is covered at all. The routing to the quarantine is advisory; the 30-day hold, once a file is in it, is not.

### 11. Unbounded web reach

**Attack:** The agent is told to read an attacker-controlled site, or to fetch from a site the user never intended it to reach.

**Control:** Deny by default. A separate read-fetch allowlist starts empty; the user adds sites one at a time from Studio's Web access panel, and the agent cannot alter the list. A second switch on the same panel controls whether GitHub and npm are reachable at all.

**Implementation:** `resources/clawfactory-fetchctl.js`, `resources/clawfactory-toolchain.sh`; UI in Studio's Web access panel.

**Limitations:** Enforcement is by resolved network address, not by hostname. See #2. Allowing a site allows anything else served from the same address. The model provider route is always open and has no switch, because an agent that cannot reach its model is a bricked product. And the software-source switch does **not** stop skill installation: the skill hub shares an address with `openclaw.ai`, which is a permanent base host.

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

**Do not open a public GitHub issue for security vulnerabilities.** Email **support@clawfactory.app** with:

- A description of the vulnerability.
- Steps to reproduce.
- Potential impact.
- Optional: a suggested fix or mitigation.

We will respond within 72 hours. We treat responsible disclosure as the default and will credit reporters in release notes unless asked not to.
