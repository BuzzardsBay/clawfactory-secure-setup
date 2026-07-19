# API Key Wizard — in-installer, zero-terminal (v1.0.46)

*Session date: 2026-07-19. Card: Dispatch #138 "API Key Wizard (in-installer, zero-terminal)".*

## Goal

Let a non-technical buyer go from "I bought this" to a working agent **without obtaining a key by guesswork and without touching a terminal**. First of the zero-terminal UX items.

## What shipped

The interactive wizard already had a provider radio page, a masked key field, a "Get key" button, and a defer checkbox. This job turned that into an actual **guided key-acquisition experience**: a new guidance page that walks the user through getting a key, plus format + live validation on entry, plus honest security/billing copy. The silent path is untouched.

All changes are in `ClawFactory-Secure-Setup.iss` `[Code]` — no new bundled files, no change to `[Files]`, `[Run]`, `setup.ps1`, the install path, firewall, SOUL, or gating logic.

---

## The wizard, page by page (interactive install)

Order: **Welcome → License → Provider → Get-your-key (NEW) → Enter-your-key → Security acknowledgement.**

### Page 3 — Choose your AI provider (existing, unchanged)

Radio list: Grok (xAI), OpenAI (ChatGPT), Anthropic Claude, Google Gemini, Ollama (local), "I'll configure a provider later". **Default = Grok (index 0)** — preserved from prior releases. This is the same value `/PROVIDER=` sets.

> **Task 1.2:** there are five real providers, so the page stays (not a single-item choice). **Decision for Bret:** the "recommended" default is currently **Grok**. Changing which provider a first-time buyer is steered toward is a product/marketing call, not mine to make silently, so I left it as-is. It's a one-line change (`ProviderPage.SelectedValueIndex := N`) if you want a different default; it does **not** affect the silent harness, which always passes `/PROVIDER=claude` explicitly.

### Page 4 — Get your <Provider> API key (NEW — the point of this job)

A read-only guidance page. Header caption is set per provider ("Get your Anthropic API key"), subtitle: *"A one-time setup step. It usually takes only a few minutes."*

**Numbered steps** (Anthropic shown; each provider has its own, console URLs verified live 2026-07):

> 1. Click the button below to open the Anthropic console (console.anthropic.com).
> 2. Sign in, or create an account if this is your first time.
> 3. Add a payment method and a little credit under Plans & Billing.
> 4. Go to Settings then API keys, click "Create Key", and name it.
> 5. Copy the key it shows you (shown only once), then click Next below.

**Button:** *"Open the <Provider> console"* → opens the provider's key page in the default browser (`ShellExec`). URLs: Grok `console.x.ai`, OpenAI `platform.openai.com/api-keys`, Anthropic `console.anthropic.com/settings/keys`, Gemini `aistudio.google.com/app/apikey`.

**Format hint:**

> A valid <Provider> key starts with "<prefix>" (for example <example>). If what you copied does not start that way, you have the wrong value.

Prefixes: Anthropic `sk-ant-`, OpenAI `sk-`, xAI `xai-`, Gemini `AIza` (all verified against live provider docs 2026-07).

**Security + billing note (Task 2.2 / 2.3):**

> Your key is yours. It bills to your own provider account, and ClawFactory never sends it anywhere except to the provider you chose. On this PC it is kept in Windows Credential Manager (DPAPI-protected); in the sandbox it lives only in a locked-down file, never in plain text.
>
> A configurable spend cap stops turns once you reach your limit — a strong guardrail on the gateway path, not an absolute ceiling (see SECURITY.md). You can also set a hard spending limit in your provider account.

The spend-cap sentence is deliberately calibrated to the published findings: it names the cap as a **gateway-path** control, not an absolute ceiling, and points at `SECURITY.md`.

### Page 5 — Enter your API key (existing page, enriched)

Subtitle: *"Paste the key you just copied."* Body:

> It is stored in Windows Credential Manager (DPAPI-protected) and is never written to a log, a temp file, or a plain-text file inside the sandbox.
>
> Not ready yet? Tick the box below — you can add your key later from the Start Menu (ClawFactory > Switch AI Provider), which walks you through it.

Controls: masked field, **"Show key"** toggle, **"Get your <Provider> API key"** button (fallback), **"I'll add my API key later (agents will not run until I do)"** checkbox.

### Page 6 — Security acknowledgement (existing, unchanged)

---

## Task 3 — entry, validation, storage

- **3.1 Masked field + show toggle + trim.** Field is a `TPasswordEdit` (masked). "Show key" flips `Password` (True=masked, False=revealed) and is reset to masked on every page (re-)entry. Paste is trimmed **live** via the edit's `OnChange` — CR/LF/TAB are stripped and the value `Trim()`-med the instant it lands (kills the trailing-newline-from-copy failure), plus a final `Trim()` on submit.
- **3.2 Format validation.** On Next, before any network call, the key must begin with the provider prefix or a **named** error fires: *"That does not look like a valid Anthropic API key. Anthropic keys start with 'sk-ant-' (for example sk-ant-api03-…)…"* — not a generic failure.
- **3.3 Live validation — IMPLEMENTED (not faked).** A minimal, **no-token** `GET` of the provider's model list with the pasted key, 8-second timeouts, classifying the HTTP status:
  - Anthropic: `GET api.anthropic.com/v1/models` (`x-api-key` + `anthropic-version`)
  - OpenAI / xAI: `GET .../v1/models` (`Authorization: Bearer`)
  - Gemini: `GET generativelanguage.googleapis.com/v1beta/models` (`x-goog-api-key` header — **key never in the URL**)

  It **never blocks the install by itself**: `401/403` → "rejected" warning that still offers *"use it as-is anyway"*; `429` → informational, continue; network/timeout/any other status → *"Continue without verifying?"* (default continue). Model listing spends zero tokens, and the key is sent only to the provider the user chose, over HTTPS. *Nuance:* an invalid Gemini key can return `400` (not `401/403`), which falls into "could not verify → continue anyway" rather than a hard "rejected"; the `AIza` format gate is the primary guard there.
- **3.4 Storage — existing mechanism only.** Still `cmdkey /generic:ClawFactory/<Provider>ApiKey /user:clawuser /pass:<key>` → Windows Credential Manager → read back by `setup.ps1 Step-WireProviderKey` → `~/.openclaw/auth-profiles.json` (mode 600, global + per-agent). No second storage path was added. Field is cleared after store.
- **3.5 Deferral + post-install path.** The "add later" checkbox completes the install with the agent unconfigured. Copy points to the Start-Menu **Switch AI Provider** item, **not** a terminal command. See the GUI-gap note below.

## Task 4 — failure/recovery text

Readable, actionable messages (no raw errors, no key echoed) for: empty key, wrong format (named prefix), key rejected by provider (mistyped/revoked/not-yet-active), rate-limited, and no-network-during-verify. All consistent with the claim-language standard (spend cap described as a gateway-path control, never absolute).

---

## Task 5 — silent install unbroken (SHIP GATE)

**By inspection — verified:**
- `ShouldSkipPage` under `WizardSilent()` skips LicensePage, ProviderPage, **KeyGuidePage (new)**, ApiKeyPage, AckPage. Both new pages are in the silent skip set → the wizard displays **nothing** new under `/SILENT`.
- `/PROVIDER=` mapping (`GetCmdLineValue('/PROVIDER=')` → indices 0–5) unchanged; `/LICENSE=` up-front validation unchanged; `[Run]` line + `GetProviderLabel`/`GetSilentFlag`/`GetResumeFlag` unchanged.
- Credential target names unchanged: `ClawFactory/{Grok,OpenAI,Anthropic,Gemini}ApiKey`.
- `Step-WireProviderKey` (setup.ps1) not touched.
- The new interactive logic (format/live-check/store) is reachable only on ApiKeyPage, which is skipped under `/SILENT`; every prompt is additionally gated by `not WizardSilent()`, and the `cmdkey` store only runs when `Key<>''`, which never happens on the silent path (the harness pre-seeds Credential Manager; the field is never populated).

**Local dry-run limits.** A full `/SILENT` run installs WSL (10–20 min, mutates the machine) and, as confirmed this session, a GUI installer launched headlessly hangs on an unanswerable window — and the standing rule keeps validation headless/off the local desktop. So the end-to-end silent run was **not** executed locally.

**What the next Azure run confirms (do NOT provision a VM this session):** run `.\scripts\azure-validate.ps1 -VmName cfv-146`. The harness installs with `/SILENT /SUPPRESSMSGBOXES /NORESTART /LOG /PROVIDER=claude /LICENSE=CF-TEST-TEST-TEST-TEST` and pre-seeds `ClawFactory/AnthropicApiKey`. Green = no wizard pages shown, key read from Credential Manager, `Step-WireProviderKey` writes `auth-profiles.json`, install completes and the seven-clean-box gate holds. That is the true regression gate for the silent contract.

## Key never logged (delta security sweep)

- The scripting `Exec()` and underlying `InstExec`/`InstExecEx` do **not** write their parameters to the Inno `/LOG` — verified against Inno source (`Setup.ScriptFunc.pas`, `Setup.InstFunc.pas`). The "Running Exec … Parameters:" log lines come only from `[Run]`/`[UninstallRun]` entries, which are not used for the key.
- The key never appears in any `Log()` or `MsgBox` string (messages reference only the provider name, prefix, and masked example).
- No temp file is written; the field is cleared after store.
- **Residual (pre-existing, unchanged):** the key transits `cmdkey`'s command line for the moment it runs, which is briefly visible to a WMI/Task-Manager observer on the same Windows account. This is inherent to the existing Credential-Manager mechanism (Task 3.4 says use it); not introduced here.

## Post-install GUI path — GAP (flagged for follow-up UX work)

There is **no true GUI** to add/rotate a key after install today. The closest path is the Start-Menu **Switch AI Provider** item, which opens a **guided PowerShell console** (`switch-provider.ps1`: prompts for provider, then a masked key prompt) — clickable and guided, but still a console window. The deferral copy points there rather than to a raw command. **A proper GUI key-entry surface is the next zero-terminal UX item** and is not papered over here.

---

## Build / sign / stage evidence

| Item | Value |
|---|---|
| Version | 1.0.46 |
| HEAD | `2e7cee92a38e0d0aa1bfccf4571aa2cdf4d43c69` |
| Parent | `ee4a4f3` |
| Tag | `v1.0.46` → `2e7cee9` |
| ISCC | Successful compile; `[Code]` verified; Step-Preflight bundling guard unaffected (all 10 security resources still in `[Files]`, clean compile) |
| Signed file size | 340,596,352 bytes |
| Signed sha256 | `d1befc20c63bd4777081408e7fbd3169bbf31380ed24ca4c5a3ade8e70d42472` |
| Signature | `signtool verify /pa /v` → **Successfully verified**; issued to **Bret Mckinney** via Azure Artifact Signing (Microsoft ID Verified CS EOC CA 04); RFC 3161 timestamped Sun Jul 19 08:34:25 2026; 0 warnings / 0 errors |
| Blob | `clawfactoryvalc467/installers/ClawFactory-Secure-Setup-v1.0.46.exe` |
| Byte-exact | **PASS** — blob downloaded and re-hashed: len 340,596,352, sha256 `d1befc20…d42472` (matches local signed) |
| Harness default | `azure-validate.ps1` `$Blob` and `$ExpectSha256` bumped to v1.0.46 |

## Files changed

- `ClawFactory-Secure-Setup.iss` — version bump + wizard (guidance page, format/live validation, show toggle, trim, copy).
- `scripts/azure-validate.ps1` — default blob + sha256 → v1.0.46.
- `CHANGELOG.md` — 1.0.46 entry.
- `docs/session_reports/API_KEY_WIZARD_2026-07-19.md` — this report.

## Out of scope (untouched, as instructed)

No grant UI, no changes to install path / restart class / firewall / SOUL / gating, no Azure validation run this session. The wizard is validated in the next full pass.
