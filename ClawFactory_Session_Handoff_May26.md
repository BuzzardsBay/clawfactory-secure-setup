# ClawFactory Session Handoff -- May 26, 2026

## TL;DR

License system is code-complete and deployed to GitHub. Not yet live -- needs manual deployment steps before v1.0.30 can be validated and shipped. Old GitHub releases deleted. Repo is private. v1.0.30 source is committed.

## Current Version: v1.0.30

**Commit:** `1c189c7`

**What's in it:**

- **v1.0.29:** WSL console window suppressed (`Invoke-WslExe`, `CreateNoWindow=true`)
- **v1.0.29:** PostInstall smoke task registered (`ClawFactory-PostInstall-Smoke`, AtLogon, `BUILTIN\Users`, writes `smoke-results.json`, self-unregisters)
- **v1.0.30:** License key wizard page (second page after Welcome)
  - MachineGuid from HKLM (stable hardware ID, not ComputerName+UserName)
  - `ValidateLicenseKey` via WinHTTP -> `api.clawfactory.app/activate`
  - `/LICENSE=<key>` CLI shim for silent/headless installs
  - Skips on `/resume` (key already validated pre-reboot, stored in HKLM)
  - `SanitizeLicenseKey` strips to `[A-Z0-9-]` before sending (no JSON injection)
  - Invalid key: stops install, shows "Purchase at clawfactory.app"

## License API: Code Complete, Not Deployed

**Repo:** github.com/BuzzardsBay/clawfactory-license-api (private)
**Commit:** init (FastAPI + PostgreSQL + Stripe webhook)

**Endpoints built:**

- `GET /health`
- `POST /activate` (rate-limited 10/min/IP, 2-machine limit)
- `POST /deactivate` (rate-limited 10/min/IP)
- `POST /verify` (rate-limited 30/min/IP)
- `POST /webhook/stripe` (Stripe sig verified, idempotent, emails key via Resend)

**Security review:** PASS (13 checks -- SQL ORM, sig verify, no key logging, MachineGuid hashed, rate limits, CORS locked, .env gitignored, no hardcoded secrets, OpenAPI disabled, idempotency, TOCTOU fixed)

## What Needs To Happen Before v1.0.30 Ships

Do these in order. All manual -- CC can't authenticate to these services.

### Step 1 -- Resend (transactional email for license key delivery)

- resend.com -> sign up with Google
- Add domain `clawfactory.app` -> add SPF + DKIM DNS records
- Wait for verified status
- Settings -> API Keys -> create key with "Sending" scope
- Save the `re_...` key

### Step 2 -- Stripe products + webhook

- Check existing Stripe products for ClawFactory ($149) and ClawAgent ($49) -- copy the `price_...` IDs if they exist, create them if not
- Developers -> Webhooks -> Add endpoint:
  - **URL:** `https://api.clawfactory.app/webhook/stripe`
  - **Event:** `checkout.session.completed` (only this one)
- Reveal signing secret -> save the `whsec_...` value

### Step 3 -- Railway deploy

```powershell
cd C:\Users\bmcki\clawfactory-license-api
railway login          # opens browser
railway init --name clawfactory-license-api
railway add --plugin postgresql
railway up
```

Then in Railway dashboard set these 6 environment variables:

| Variable | Value |
|----------|-------|
| `STRIPE_SECRET_KEY` | `sk_live_...` |
| `STRIPE_WEBHOOK_SECRET` | `whsec_...` (from Step 2) |
| `STRIPE_PRICE_CLAWFACTORY` | `price_...` (from Step 2) |
| `STRIPE_PRICE_CLAWAGENT` | `price_...` (from Step 2) |
| `RESEND_API_KEY` | `re_...` (from Step 1) |
| `DATABASE_URL` | auto-injected by Postgres plugin |

### Step 4 -- DNS

- CNAME `api.clawfactory.app` -> the `*.up.railway.app` URL Railway gives you
- Railway -> Settings -> Domains -> add `api.clawfactory.app`
- Wait ~2 minutes for TLS

### Step 5 -- Email forwarding (incoming)

- `hello@clawfactory.app` -> Bret's Gmail
- If domain is on Cloudflare: Email Routing (free, 5 min)
- If not: ImprovMX or Forwardemail.net (both free)

### Step 6 -- End-to-end test

```bash
curl https://api.clawfactory.app/health
```

Expected: `{"status":"ok"}`

Then in Stripe dashboard:

- Webhooks -> your endpoint -> Send test event
- Event: `checkout.session.completed`
- Confirm: 200 response + license row in Postgres + email arrives

## Once Steps 1-6 Are Done

Tell Claude -- it will write the v1.0.30 compile + validation prompt:

- Compile installer (ISCC.exe)
- Azure: provision cfv-131, download, silent install with `/LICENSE=<test-key>`
- Smoke test, idle test, chatCompletions
- `REPORT_v1.0.30.md` committed
- VM cleaned up
- v1.0.30 ships

## Azure State

- **RG:** `clawfactory-validation` (westus2)
- **Keep-list:**
  - `clawfactoryvalc467` (storage account)
  - `bake-vmVNET` (virtual network)
  - `clawfactory-win11-baseline` (baseline image -- **NEVER DELETE**)
- No active VMs. RG is clean.
- **Subnet:** `bake-vmSubnet` (not "default")
- **Blob upload:** `--auth-mode key` (not login)
- **Install flags:** `/SILENT /SUPPRESSMSGBOXES /NORESTART /LOG /PROVIDER=claude /LICENSE=<key>`

## Open Items Queue (v1.0.31+)

1. **SOUL.md hash fix** -- OpenClaw updated upstream, broke Bret's own install (v1.0.21 binary failed at Step-ApplySafetyRules on real hardware). Fix: fetch current hash at install time instead of pinning at build time. **Priority: HIGH** -- every user on a machine with updated OpenClaw will hit this.
2. **`/deactivate` page on clawfactory.app** -- users need UI for machine transfers. Currently would need to curl the API directly.
3. **Baseline image rebake** -- run-command extension wedges on fresh provisioning after ~2 weeks. Needs a fresh Azure marketplace Win11 base.
4. **Discoverability pass** -- README, CHANGELOG, SECURITY.md, CONTRIBUTING.md. Prompt already built: `CC_ClawFactory_Discoverability.md` (session artifact).
5. **v1.1 quick wins batch** -- stale error message, dead tee calls, stale comments, Defender exclusion. Prompt already built: `CC_ClawFactory_v1_1_QuickWins.md`.
6. **ClawPack architecture** -- format spec + loader.
7. **ClawBuild scraper pack** (supported sites, one-click auth).
8. **ClawBuild software factory pack.**

## Key Repo Locations

| What | Path |
|------|------|
| ClawFactory installer | `C:\Users\bmcki\ClawFactory-Secure-Setup` |
| License API | `C:\Users\bmcki\clawfactory-license-api` |
| Installer source | `ClawFactory-Secure-Setup.iss` |
| Main install script | `setup.ps1` |
| Build command | `& 'C:\Program Files (x86)\Inno Setup 6\ISCC.exe' 'ClawFactory-Secure-Setup.iss'` |
| Output binary | `Output\ClawFactory-Secure-Setup.exe` |

## Opening Prompt for New Session

Paste this at the start of the new thread:

> I'm Bret. Continuing ClawFactory work. Current version is v1.0.30 (commit `1c189c7`).
>
> Please read these project files to load full context:
>
> - `CLAUDE_ClawFactory.md`
> - `ClawFactory_Install_Lessons_Learned.md` (mandatory before any install changes)
> - `ClawFactory_Session_Handoff_May26.md`
>
> State summary:
>
> - License system code-complete at github.com/BuzzardsBay/clawfactory-license-api
> - v1.0.30 installer committed with license key wizard page
> - Needs manual deployment steps before v1.0.30 can be validated
> - Old GitHub releases deleted (v1.0.17 through v1.0.21)
> - Repo is private
> - Azure RG is clean, no active VMs
>
> Today's focus: complete the license API deployment steps (Resend, Stripe, Railway, DNS, email forwarding), then validate and ship v1.0.30.
