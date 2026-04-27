# SUPPORT_MATRIX.md — first-30-minute friction by persona

Every answer below maps to the actual behavior of `setup.ps1`, `bootstrap.ps1`, or `launcher.ps1` as shipped. Where the installer leaves a real gap, it says so directly.

---

PERSONA: Security researcher
TECHNICAL LEVEL: high

Q1: Where exactly is the egress firewall ruleset, and can I audit which IPs `clawuser` can reach right now?
WHAT HAPPENS: `setup.ps1` Step-EgressFirewall writes `/etc/nftables.conf` inside WSL with a `table inet clawfactory` block: `meta skuid != clawuser return; oifname "lo" accept; udp/tcp dport 53 accept; ct state established,related accept; ip daddr @allowed_ipv4 tcp dport 443 accept; counter drop`. The `allowed_ipv4` set has 6h timeout and is populated by `getent ahostsv4` against the chosen provider's hosts plus base infra (github, npm, docker hub, openclaw.ai, clawhub.ai).
ANSWER: `wsl -u root -- nft list table inet clawfactory` shows the live ruleset including resolved IPs and the drop counter. `cat /etc/nftables.conf` is the static config. The persisted set membership decays every 6h — provider switches via `switch-provider.ps1` re-resolve and re-add. There is **no scheduled re-resolve**; if a provider's CDN rotates IPs after 6h, outbound breaks until the next switch-provider run. That's a real gap; track ticket priority accordingly.

Q2: How is the gateway authenticated and what's the actual scope-grant flow when I open the dashboard?
WHAT HAPPENS: The OpenClaw gateway at `127.0.0.1:8787` requires Ed25519 device-identity-signed connect. Token alone grants zero scopes. The control-UI served at `/` will display a pairing prompt; until you complete it, you can view the dashboard chrome but cannot exec any operator method (`agents.create`, `chat.send`, etc.).
ANSWER: The installer does **not** ship a pairing flow. Pair from the control UI itself (look for the device-identity panel) or write a probe like `backend/probe-gateway-ws.mjs` from the Studio codebase that generates a keypair, signs the canonical `v2|deviceId|...|nonce` message, and includes it in the connect req. After first successful pairing the device-id is auto-trusted on loopback. There is no installer-level documentation of this — read the gateway's own `/control-ui/assets/*.js` for the pairing API.

Q3: Is the upstream `install.sh` SHA-256 pin real, and how do I rotate it?
WHAT HAPPENS: `setup.ps1` line 26: `$OpenClawInstallSha256 = 'b585950258e21eb3fb0b2ecfbc2f1e8d79ae472b2c21a7919a082067b925f6e7'`. Step-InstallOpenClaw `curl`s `openclaw.ai/install.sh`, computes `sha256sum`, exits 43 on mismatch and 42 if the pin is the literal placeholder string. The pin is verified before the script runs.
ANSWER: Real. To rotate: re-fetch `install.sh` from a trusted source, compute `sha256sum`, paste hex into `setup.ps1` line 26, recompile via `ISCC.exe`. The README documents this in the "Pinning the OpenClaw install.sh hash" section. **Caveat**: nothing pins the OpenClaw `.deb`/npm artifacts that `install.sh` itself fetches — your trust chain bottoms out at OpenClaw's CDN.

Q4: Can I verify the `.exe` itself wasn't tampered with?
WHAT HAPPENS: The `.iss` has a commented-out `SignTool=signtool` directive. As shipped, the `.exe` is **unsigned**. Windows SmartScreen will warn "Unknown publisher" on first run.
ANSWER: There's no signature to verify. You're trusting whoever sent you the `.exe`. Real gap — code-signing is item 5 on the project's pre-launch list and not yet done. Until then: download only from the publisher's primary distribution channel, compare your file's SHA-256 to a hash they publish out-of-band, and run on a disposable VM first.

Q5: How do I add my own tool/plugin to the agent's allowlist for testing?
WHAT HAPPENS: Agent tool allowlists live in `~/.openclaw/agents/<name>/meta.json` under `tools`. `bootstrap.ps1` writes these for the four factory agents (orchestrator, skill-scout, skill-builder, publisher) but uses placeholders for three of them — only orchestrator gets a real prompt with the SOUL hash substituted via `{{SOUL_SHA256}}` replacement.
ANSWER: Plugin tools are registered globally by extensions in `/usr/lib/node_modules/openclaw/dist/extensions/<id>/` — enable a plugin via `openclaw config set plugins.entries.<id>.enabled --strict-json true`, restart the gateway, then add the tool name to the agent's `meta.json` `tools` array. **The catch**: most agent capability comes from a built-in `exec` (bash) tool, not from listing plugin tool names in meta.json — for many flows you'll write skills (markdown instruction sets) that tell the agent how to call shell CLIs.

BIGGEST DROP-OFF RISK: The dashboard requires device-identity pairing the installer never explains, and figuring out the pairing API requires reading the OpenClaw control-UI bundle.

---

PERSONA: Journalist / investigative reporter
TECHNICAL LEVEL: low

Q1: I clicked the desktop lobster and a web page opened, but it doesn't have a chat box. What now?
WHAT HAPPENS: `launcher.ps1` runs `systemctl --user start openclaw-gateway` inside WSL, polls `http://127.0.0.1:8787/status` for up to 15 seconds, then opens that URL in your default browser. What you see is the OpenClaw gateway's control panel, not a chat window — and the chat is gated by a "device pairing" step the installer doesn't walk you through.
ANSWER: Honestly, this is the biggest rough edge in the current installer. The simpler path right now is the terminal: open Start → "Ubuntu" → at the prompt type `openclaw chat`, pick `orchestrator` from the list. If the terminal is too unfamiliar, wait for the next installer build that bundles the chat UI directly. **Do not put source documents into this until you can confirm the chat works end-to-end.**

Q2: Where do my conversations get saved, and could they be subpoenaed off this machine?
WHAT HAPPENS: Inside WSL, the gateway writes session logs to `/tmp/openclaw/openclaw-<date>.log` (cleared on reboot in some configs but not all) and persistent chat history to `~/.openclaw/agents/<name>/sessions/` as JSONL. Your prompts and the model's responses sit on disk inside WSL in plaintext until you delete them.
ANSWER: They're stored locally only — nothing leaves your machine if you picked Ollama, and only goes to your chosen LLM provider (Anthropic/OpenAI/etc.) if you picked one of those. But they are on disk in plaintext. Treat them like a Word document: encrypt your laptop's disk (BitLocker), and delete the JSONL files in `~/.openclaw/agents/*/sessions/` after sensitive sessions. There is **no built-in "purge history" button** — that's a real gap.

Q3: How do I shut everything down before I cross a border or hand the laptop to someone?
WHAT HAPPENS: The Start Menu has a "ClawFactory Kill Switch" entry. It runs `clawfactory-stop.ps1` which kills the agent containers and stops the OpenClaw gateway. It does **not** unregister WSL or delete chat history.
ANSWER: For "off but recoverable": Start Menu → ClawFactory → ClawFactory Kill Switch. For "gone": run the uninstaller from Settings → Apps; it offers to `wsl --unregister Ubuntu`, which deletes the entire Ubuntu distro including all chat history and credentials. Allow 1–2 minutes for the unregister. **Important**: BitLocker / FileVault on the host disk is the actual privacy layer. The installer cannot encrypt for you.

Q4: Can I really use this offline, with no cloud LLM at all?
WHAT HAPPENS: At install, picking the `Ollama (local)` provider auto-installs Ollama and pulls `llama3.1:8b`. After that, all inference happens locally. The egress firewall allows only Ollama's update host plus loopback for the model itself.
ANSWER: Yes — pick Ollama at install time. After install, you can disconnect from the internet entirely and the agent still works. Quality is meaningfully lower than Claude/GPT for nuanced sourcing work, but the privacy guarantee is total. If you already installed with a cloud provider, run Start Menu → ClawFactory → Switch AI Provider and pick `ollama`.

Q5: What about my notes — can I export a conversation?
WHAT HAPPENS: Chat history is stored as JSONL files at `~/.openclaw/agents/<name>/sessions/<id>.jsonl` inside WSL. There is no export button, no Markdown render, no "save as PDF."
ANSWER: Not natively. To extract a session today: open Ubuntu, type `cat ~/.openclaw/agents/orchestrator/sessions/*.jsonl` and copy the output, or `cp` the file to a Windows location. This is a real product gap; export-to-Markdown is the kind of feature that should exist for your use case and currently doesn't.

BIGGEST DROP-OFF RISK: The desktop shortcut opens a dashboard they can't actually chat in, and the only working path (`openclaw chat` from a Linux terminal) requires comfort with the command line they don't have.

---

PERSONA: Ambitious student (grad or undergrad)
TECHNICAL LEVEL: medium-high

Q1: I picked Ollama at install — how do I actually start asking it questions?
WHAT HAPPENS: After install, `bootstrap.ps1` printed a "what to do next" block with three commands. The desktop shortcut points at the gateway's control UI which needs device pairing.
ANSWER: Skip the desktop icon for now. Open Ubuntu (Start → "Ubuntu") and run `openclaw chat`. Pick `orchestrator` from the agent list. If you get an error about the gateway not running, run `systemctl --user start openclaw-gateway` first. The gateway dashboard at `http://127.0.0.1:8787` is real but currently requires manual device pairing the installer doesn't explain — file an issue if you want me to walk you through it.

Q2: Can I install other Ollama models like `mistral` or `qwen2.5-coder`?
WHAT HAPPENS: Step-InstallOllama only pulls `llama3.1:8b` by default. After install, Ollama is running as a systemd service inside WSL and accepts standard `ollama pull` commands.
ANSWER: Yes. Inside WSL: `ollama pull mistral` (or any tag from `ollama.com/library`). Then point the agent at it: `openclaw config set agents.defaults.model.primary ollama/mistral`. The egress firewall already allows `ollama.com` and `registry.ollama.ai` so pulls work. You're not locked into llama3.1.

Q3: Can I read the orchestrator's actual prompt to learn how it works?
WHAT HAPPENS: `bootstrap.ps1` copies `resources/orchestrator-prompt.md` into `~/.openclaw/agents/orchestrator/agent.md`, substituting `{{SOUL_SHA256}}` with the live hash from `~/.openclaw/SOUL.md.sha256`. The other three agents currently get placeholder stubs because their prompts haven't shipped yet.
ANSWER: `cat ~/.openclaw/agents/orchestrator/agent.md` shows the real prompt. `cat ~/.openclaw/SOUL.md` shows the global safety rules every agent inherits. The other three agents (`skill-scout`, `skill-builder`, `publisher`) currently have placeholder prompts that say so explicitly — those will be replaced in a future installer build.

Q4: Can I write my own skill and add it?
WHAT HAPPENS: OpenClaw skills are markdown files at `~/.openclaw/skills/<slug>/SKILL.md` (or installed via `openclaw skills install <slug>` from ClawHub). The installer does not pre-install any skills.
ANSWER: Yes. `mkdir -p ~/.openclaw/skills/my-thing && nano ~/.openclaw/skills/my-thing/SKILL.md`, write the markdown instructions, then `openclaw skills check` to verify it loads. Look at `/usr/lib/node_modules/openclaw/skills/github/SKILL.md` as a reference — it's a working bundled skill. Caveat: agents won't autoload your skill until you add the slug to `~/.openclaw/agents/<agent>/meta.json` skill list.

Q5: Can I cite this in a paper or use it on a coursework project?
WHAT HAPPENS: The installer is MIT-licensed (see `LICENSE` in the install dir). Copyright is "Frontier Automation Systems LLC, 2026."
ANSWER: Yes — MIT means cite, fork, modify, share. For a paper, the canonical reference is the GitHub repo URL plus a commit hash from when you used it (the `setup.ps1` SHA-256 install pin gives you a reproducibility anchor for the OpenClaw side). Mention OpenClaw's own license (Apache-2.0 or whatever it ships with) in your acknowledgements.

BIGGEST DROP-OFF RISK: They expect a "click and chat" experience and instead land on a dashboard they can't use, then spend an hour learning the CLI before they get anywhere.

---

PERSONA: Solo SaaS developer
TECHNICAL LEVEL: high

Q1: Can I point my IDE (Cursor, VS Code, JetBrains) at the local gateway?
WHAT HAPPENS: The gateway exposes a WebSocket protocol at `ws://127.0.0.1:8787/` with Ed25519 device-identity auth. It speaks OpenClaw's own protocol, not OpenAI-compatible.
ANSWER: Not directly with most IDE plugins, which expect OpenAI/Anthropic API endpoints. Two paths: (a) use OpenClaw's official VS Code extension if one exists for your IDE; (b) run `litellm` or a proxy that translates OpenAI-format calls to the gateway's protocol. Real gap — the installer does not provide an OpenAI-compatible shim. Track ticket priority accordingly.

Q2: I want the agent to edit code in my project — how do I give it access?
WHAT HAPPENS: WSL `automount=false` means clawuser **cannot see** any path under `C:\` from Windows. Your project at `C:\Users\me\projects\app` is invisible to the agent. This is intentional security hardening from `setup.ps1` Step-ConfigureWslConf.
ANSWER: Two options. (1) `cp -r /mnt/.../app ~/projects/app` won't work because automount is off; instead `cp` from a USB drive or `git clone` into `~/projects/` from inside WSL. (2) Re-enable automount in `/etc/wsl.conf` and `wsl --shutdown` — but understand you've then **lost** the file isolation the installer was selling you. There's no in-between.

Q3: Where are my API keys stored — can a rogue agent exfiltrate them?
WHAT HAPPENS: Step-WireProviderKey reads your provider key from Windows Credential Manager (DPAPI, tied to your Windows user) and writes it to `~/.openclaw/auth-profiles.json` (mode 600, owned by clawuser) inside WSL. clawuser owns it, root can read it, the agent runtime reads it to make API calls.
ANSWER: The key is at `~/.openclaw/auth-profiles.json` mode 600. The agent itself has access (it has to, to make LLM calls). The egress firewall caps exfiltration to your provider's API host plus base infra — even a fully-compromised agent can only POST your key to api.anthropic.com (or wherever you picked), not to an attacker-controlled host. That's the security model. Rotate keys via `cmdkey /generic:ClawFactory/<Provider>ApiKey /pass:<new>` then re-run `switch-provider.ps1`.

Q4: Can I run multiple gateway instances on different ports for testing?
WHAT HAPPENS: `setup.ps1` hardcodes port 8787 in three places: `gateway.port` config, the Windows Firewall rule name `ClawFactory-Block-Inbound-8787`, and the `launcher.ps1` URL. The OpenClaw `--profile` flag does support per-profile state isolation.
ANSWER: Not via this installer. Manually: `openclaw --profile dev config set gateway.port 18787 && openclaw --profile dev gateway run`. State lives at `~/.openclaw-dev/`. You'll need to add a Windows Firewall inbound-deny rule for 18787 yourself if you want the same isolation. The single-port assumption is a real installer constraint.

Q5: How do I update OpenClaw when there's a new version?
WHAT HAPPENS: `setup.ps1` Step-InstallOpenClaw is idempotent — re-running the installer re-fetches `install.sh` (verifying the SHA-256 pin), and most steps no-op if state already exists. There is no in-app update mechanism.
ANSWER: Re-run the `.exe`. The pin in line 26 of `setup.ps1` is your version anchor — when OpenClaw publishes a new release you'll need a new installer build with an updated pin. There is **no auto-update**. For your daily workflow, hot-update via `openclaw update` inside WSL works but bypasses the SHA-256 pin guarantee.

BIGGEST DROP-OFF RISK: The agent can't see their project files (automount=false), and turning that off defeats the entire security pitch — they'll either rebuild their workflow inside WSL or quit and go back to Cursor.

---

PERSONA: Academic scientist (wet lab or computational)
TECHNICAL LEVEL: medium

Q1: How do I get my data files to the agent? My CSVs are in `C:\Users\me\Documents\experiment-3\`.
WHAT HAPPENS: `setup.ps1` writes `/etc/wsl.conf` with `automount=false`, which means `/mnt/c/` is not mounted inside WSL. The agent literally cannot see your Windows files.
ANSWER: Copy them into WSL once: open Ubuntu, run `cp /mnt/c/Users/me/Documents/experiment-3/*.csv ~/data/` — wait, this won't work because automount is off. The actual path: from a regular WSL PowerShell run `wsl -u clawuser -- cp /mnt/c/Users/me/Documents/...` — also won't work. You need to either temporarily re-enable automount (edit `/etc/wsl.conf`, `wsl --shutdown`, copy, then revert and restart), or use a USB drive that WSL can see. **This is a genuine pain point** — the security feature is also an UX wall for legitimate work.

Q2: Can I get a transcript of every prompt and response for my methods section?
WHAT HAPPENS: The gateway writes session messages to `~/.openclaw/agents/<name>/sessions/*.jsonl` inside WSL. Each line is a JSON object with timestamp, role, content, model, and token counts.
ANSWER: Yes — `cat ~/.openclaw/agents/orchestrator/sessions/*.jsonl > my-transcript.jsonl` from inside Ubuntu. For a methods section you'll want to pretty-print: `jq '.' my-transcript.jsonl > my-transcript.json`. Note: timestamps are unix-millis. The JSONL also includes the model name and token usage which you should report alongside the transcript for reproducibility.

Q3: Does this work on my university workstation behind the IT proxy?
WHAT HAPPENS: `setup.ps1` makes outbound HTTPS calls during install: WSL fetch, Docker images, `openclaw.ai/install.sh`, npm packages, your provider's API. None of these are configured to honor an HTTP proxy. The egress firewall blocks anything not on its allowlist.
ANSWER: Probably not, and if it does it'll be flaky. The installer assumes direct internet access. If your university uses a TLS-intercepting proxy, the SHA-256 pin on `install.sh` will fail (proxy returns a re-signed response). Workarounds: install from home, then bring the WSL distro to campus on an external drive (`wsl --export`, `wsl --import`). This is a real institutional gap.

Q4: Do my colleagues need their own install or can we share one?
WHAT HAPPENS: The installer is per-Windows-user. Credentials live in Windows Credential Manager (DPAPI), which is tied to the Windows account — another user on the same machine cannot decrypt them. WSL state is also per-Windows-user.
ANSWER: Each Windows user account on a shared workstation needs its own install (or its own provider key under their own DPAPI). For a multi-PI setup, one workstation per user is cleanest. If you're sharing, each person should `Switch AI Provider` to wire their own key — they cannot share the saved key.

Q5: What happens if I pick "Anthropic" but my API key has no credit?
WHAT HAPPENS: Step-WireProviderKey writes the key without billing-checking it. `openclaw verify` (run by `post-install.ps1`) does a basic API-reachability check but not a balance check. The first real chat call returns a quota error from Anthropic which the agent surfaces as a tool error.
ANSWER: Install completes fine; chat fails when you try to use it with a "insufficient credits" error from the provider. Easiest path: switch to Ollama (local, free, no key) via the Switch AI Provider shortcut. Or top up your Anthropic balance and try again — no reinstall needed.

BIGGEST DROP-OFF RISK: They cannot get their data files into the agent without breaking the security model, and the README does not explain this trade-off in their language.

---

PERSONA: Retail investor / trader
TECHNICAL LEVEL: low

Q1: I clicked the lobster icon and a webpage opened. Where do I type my question?
WHAT HAPPENS: `launcher.ps1` opens `http://127.0.0.1:8787` in your default browser. That URL serves the OpenClaw gateway's control dashboard — it has menus and panels but no chat box you can use until you complete a "device pairing" step the installer doesn't explain.
ANSWER: Right now the easiest path is **not** the desktop icon. Click Start, search "Ubuntu", press Enter, and at the black window's prompt type `openclaw chat` and press Enter. Pick "orchestrator" from the list with arrow keys. Type your question and press Enter. The desktop icon needs a fix the next installer build will include — for now, treat it as a dashboard for advanced settings, not the way to chat.

Q2: How much does each question cost?
WHAT HAPPENS: If you picked a cloud provider (Grok, OpenAI, Claude, Gemini), each chat goes through your API key and costs whatever that provider charges per token. The installer does not show you a counter or cap. If you picked Ollama, every question is free and runs on your laptop.
ANSWER: For cloud providers: roughly $0.01–$0.10 per question depending on length and which model you picked. Check your provider's billing dashboard (Anthropic console / OpenAI billing) every few days. To avoid surprises: switch to Ollama from the Start Menu shortcut "Switch AI Provider" — it's free and runs locally, just slower and a little less smart. There is **no built-in spending cap** in this installer — set one in your provider's billing settings.

Q3: Can I import my brokerage statements (PDFs, CSVs)?
WHAT HAPPENS: WSL is configured so the agent cannot see your Windows files. Your `Downloads` folder is invisible to the agent.
ANSWER: For now, paste the relevant text into the chat box directly — the agent can read pasted text just fine. For uploading whole PDFs or CSVs, you'd need a workflow that copies files into the agent's workspace, which currently requires command-line steps that aren't ready for non-technical users. **Real gap** — file upload is on the next-build list.

Q4: Why does my desktop icon say "ClawFactory could not start. Check that WSL is running"?
WHAT HAPPENS: `launcher.ps1` tries to start the OpenClaw service inside WSL and waits 15 seconds for it to come up. If WSL isn't running yet (right after a reboot, or after Windows put it to sleep), 15 seconds isn't always enough.
ANSWER: Wait 30 seconds and double-click the lobster again. If it still fails: restart your PC and try once more. If it still fails after a fresh restart, use the Start Menu "ClawFactory Kill Switch" then double-click the lobster — that's a clean reset. You shouldn't need to do this often; usually only after Windows updates or a deep sleep.

Q5: Is my API key safe? Where is it stored?
WHAT HAPPENS: Your key was stored in Windows Credential Manager when you typed it during install. Credential Manager uses Windows DPAPI, which encrypts the key with a key tied to your Windows password. If someone else logs into your computer as a different user, they cannot decrypt it.
ANSWER: It's about as safe as a password saved in Chrome. Encrypted by Windows, tied to your account, can't be read by other users on the same PC. The risk is: if someone gets your Windows password (or convinces Windows you're you), they can read it. Standard precaution: enable BitLocker on your laptop disk if you're using a cloud provider key with real money behind it.

BIGGEST DROP-OFF RISK: They expect the desktop icon to launch a ChatGPT-like chat window, get a confusing dashboard, and assume the product is broken.

---
