# Ship-A — Live-Site Pass (Evergreen restyle + truth fixes + claim inventory) — close-out

*2026-07-21. Repo (write): `ClawFactory-Secure-Setup`, `docs/` site surfaces only. No
product code, installer, validation, or cloud touched. Site is GitHub Pages
(`clawfactory.app`), live on push. Model: Opus 4.8 (Sonnet recommended — flagged;
this is copy/CSS + an evidence-grounded truth audit, model-independent). Ground truth
established by a read-only investigation of both repos (cited inline). Commit:
`4946578` (site), on `main` at/after the `v1.1.0` tag (`487e930`).*

## Comprehension gate (recap)
1. The site is *description*, not product — every claim aligned here is already true of
   the shipped, signed, cfv-152-validated v1.1.0 artifact, so no code change / release is
   needed. License + orchestrator behavior changes are *product* work → v1.1.1.
2. Structural controls (UID/OS-permission boundaries, immutable files, kernel firewall,
   socket binding) may be stated as guarantees; advisory/config/bypassable controls must
   not. When unsure, understate.
3. The hero is the positioning surface Bret owns and is being rewritten separately, so it
   was restyle-only + extracted — with one **owner-directed** exception (the `cta-tier-note`
   value line, changed on Bret's explicit instruction this session).
4. Live-on-push = no staging buffer; no claim strengthened without evidence, diff re-read
   for accidental overclaim, judgment calls surfaced before push.

---

## Restyle (Task 2) — Evergreen, both modes, verified

Applied the Evergreen palette as CSS custom properties. The site was dark-only; kept
**dark as default** (`:root`) with a `@media (prefers-color-scheme: light)` override, so
light-preference users get the light palette automatically (Bret confirmed dark-default).
All previously hardcoded colors were moved into variables so both modes theme cleanly;
new tokens added to complete the system: `--on-accent`, `--verified`, `--alert`,
`--nav-bg`, `--thead-bg`, `--code-bg`, `--border-strong`, `--mascot-glow`.

**Mascot:** recolored to the accent, theme-aware via CSS classes (`.m-body`=accent,
`.m-face`/`.m-mouth`=on-accent) — dark-green body + white face on light, light-green body
+ dark face on dark; always readable. Favicon (static data-URI, can't be theme-aware) set
to the bright accent green `#97C459` with dark `#12240A` face. No red remains in
decorative use (`--alert` is defined but reserved for genuine warning content).

**Contrast — every changed text pairing checked against a 4.5:1 floor (WCAG AA), computed
not eyeballed.** All pass. Representative ratios:

| Pairing | Dark | Light |
|---|---|---|
| text / page | 14.9:1 | 13.8:1 |
| muted / page | 6.7:1 | 5.0:1 |
| text-dim / rail (worst case) | 5.6:1 | 4.6:1 |
| accent / page | 8.6:1 | 5.7:1 |
| on-accent / accent (buttons) | 8.1:1 | 6.2:1 |
| verified / card (feature check) | 6.0:1 | 8.2:1 |

**One accessibility-forced adjustment:** in light mode `--text-dim` is set equal to
`--text-muted` (`#5F6E54`). A *dimmer* light tier cannot clear 4.5:1 on the `#E9EEE1`
rail (a lighter dim = lower contrast), so the third text tier collapses to the muted level
in light mode only. Documented, intentional.

Verified by rendering `docs/index.html` in the browser pane in **both** color schemes:
hero, mascot, buttons, section labels, control table, and product cards render correctly;
layout intact; no horizontal scroll; the theme-aware mascot flips correctly.

---

## Truth fixes — before → after (every change)

| # | Location | Before | After | Basis |
|---|---|---|---|---|
| 1 | Controls table | **Rootless Docker** / "No root access inside the container" | **row removed** | Docker was removed from the product (decision A); agents are `clawuser` processes, no containers. `setup.ps1` has no Docker; Step-InstallDocker deleted. |
| 2 | Controls table | DPAPI / "API key in Windows Credential Manager, **never plaintext**" | "API key stored in Windows Credential Manager, **encrypted at rest (DPAPI) under your Windows account**" | Key is stored DPAPI-encrypted on Windows (`cmdkey`→Cred Manager) but exists as a **mode-600 plaintext** file inside the WSL sandbox for the runtime; "never plaintext" was false. |
| 3 | FAQ "Why does Windows warn me" | "not yet code-signed… working toward a certificate" | "code-signed (**Azure Trusted Signing**), **RFC 3161 timestamped**… verify via Properties → Digital Signatures" (SmartScreen first-run reputation caveat kept, honestly) | Installer signature verified **Valid + timestamped** this session and at 3B (`Get-AuthenticodeSignature`). |
| 4 | FAQ "What AI providers" | "pre-configured for Grok… switching (OpenAI, Anthropic, others) is **in active development**" | "choose your provider at install — Grok (default), OpenAI, Anthropic, Gemini, or local Ollama… change any time from the **Switch AI Provider** Start-Menu tool" | Provider **switching ships**: `.iss:139-143` Start-Menu item → `resources/switch-provider.ps1` (grok/openai/claude/gemini/ollama). 5-provider chooser: `.iss:651-656`. |
| 5 | FAQ ×3 ("data sent", "access by default", "restricted out of box") | "outbound … to your AI provider **only**" | "outbound … to an **allowlist** — your provider's API **plus** the update sources the runtime needs" | Live nftables allowlist adds `AUX_HOSTS` (anthropic/openai/x.ai/gemini + github/npm/ubuntu), refreshed 5-hourly: `setup.ps1:1786-1789`. "provider only" was overstated. |
| 6 | FAQ "What is ClawFactory" | ClawChat only | added factual mention of **ClawFactory Studio** (visual workbench for setup + folder grants) | Combined v1.1.0 installer installs Studio per-user (`.iss:13, 93, 1003-1091`). |
| 7 | Product cards + FAQ "difference" + hero cta-tier-note | "**Multi-agent support (5 agents)**" / "5 agent profiles" / "Factory orchestration" | agent-count framing **dropped entirely**; ClawFactory differentiator now leads with **Studio management app** (+ "Factory orchestration scaffolding"); cta-tier-note → "…full security substrate, **Studio management app**, kill switch" | Installer pre-creates orchestrator/scout/builder/publisher dirs + `main` (5 profiles), but **orchestration is not functional**: only `orchestrator-prompt.md` ships; scout/builder/publisher are placeholder stubs ("Nothing useful, by design"); no invokable orchestrator, no routing engine (`bootstrap.ps1:111-141`; `orchestrator-prompt.md:16-18`; `setup.ps1:2290-2294`). Studio is provable and shipped. **Per Bret's explicit direction.** |

**Owner-directed hero edit:** the `cta-tier-note` value line was changed on Bret's explicit
instruction (drop "5 agents" → "Studio management app"). The rest of the hero (headline,
sub, CTAs, meta) is restyle-only + extracted; the **"One click" headline is deliberately
left as-is** for the hero-rewrite audit (a mild simplification — install is multi-step).

**Overclaim check (diff re-read):** two claims got *stronger* — signing (unsigned→signed)
and provider-switching (roadmap→ships) — **both hard-evidence-backed**. Every other change
made a claim weaker/more precise (DPAPI, "provider only", Docker removal, agent-count).
Nothing strengthened without evidence.

**Product-shape (Task 4):** version — no explicit version string exists on the page ("v1.x"
in the subscription FAQ remains accurate; no "v1.0" to bump); installer size (~440 MB) is
**not** stated anywhere, so nothing to update; Studio (management app) now surfaced in the
"what you get" copy. Internal version drift noted for a separate task: `CHANGELOG.md` latest
is `[1.0.48]` and `setup.ps1:46 $InstallerVersion='1.0.34'` — both lag the shipped `1.1.0`
(not customer-facing; carded below).

---

## Full claim inventory (Task 5)

Classification: **STRUCTURAL** (provable, may be stated as a guarantee) · **FINE**
(accurate, non-security) · **EDITED** (fixed this session) · **STALE/FLAG** (judgment call
left for Bret / Ship-B). Evidence cites the investigation (repo `file:line`) or design.

| Claim | Location | Class | Evidence / note |
|---|---|---|---|
| "OpenClaw. Hardened. One click." | hero h1 | FLAG | "One click" simplifies a multi-step install; hero extraction-only, left for rewrite (Bret). |
| "doesn't phone home… OS-level, not by prompting the agent" | hero-sub | STRUCTURAL | All controls OS/kernel-enforced (Q5). Hero copy, unchanged. |
| "full security substrate, Studio management app, kill switch" | hero cta-tier-note | EDITED | Was "5 agents"; owner-directed. Studio ships v1.1.0. |
| WSL2 sandbox / isolated from Windows FS | controls table | STRUCTURAL | `setup.ps1` WSL2 + `wsl.conf`. |
| ~~Rootless Docker~~ | controls table | EDITED | Removed — Docker not in product. |
| nftables egress firewall / scoped to clawuser UID | controls table | STRUCTURAL | `setup.ps1:1252-1255`. (Allowlist broader than one provider — see FAQ edits.) |
| automount=false / drives invisible | controls table | STRUCTURAL | `setup.ps1:1092-1094` + fail-loud `Assert-WslAutomountDisabled`. |
| Loopback-only gateway 127.0.0.1:8787 | controls table | STRUCTURAL | `setup.ps1:1931-1979`. 8787 is the customer-facing gating proxy; real gateway on private 8788 — split *strengthens* the control; 8787 accurate. |
| Windows Firewall inbound-block 8787 | controls table | STRUCTURAL | `setup.ps1:2445-2452`. |
| DPAPI key storage | controls table | EDITED | Now within DPAPI's actual guarantee. |
| Kill Switch / Start Menu | controls table | STRUCTURAL | `.iss:124-128` → `clawfactory-stop.ps1`. |
| Steps 01–03 (download/configure/run @127.0.0.1:8787) | how-it-works | FINE | Accurate. "Nothing leaves your machine without your permission" — the permissioned egress is the provider API call; defensible, mild framing. |
| "What is ClawFactory" (ClawChat + Studio) | FAQ | EDITED | Studio added. |
| "Is my data sent anywhere" (allowlist) | FAQ | EDITED | Accurate allowlist. |
| "What does it have access to" (allowlist) | FAQ | EDITED | Accurate. |
| "What exactly is restricted" (allowlist + "cannot be overridden by the agent") | FAQ | STRUCTURAL/EDITED | Override-resistance is structural (immutable/kernel/socket). Allowlist wording fixed. |
| "How do I change settings… on the roadmap… contact support for file access" | FAQ | **STALE/FLAG** | Studio **grants folder access today** (`grantWorkspace`), so directing users to email support for file access is partly stale, and mildly contradicts the new Studio mention. Recommend Ship-B fix. |
| "How do I use it… ClawChat opens automatically" | FAQ | FINE (minor) | `launcher.ps1:214-222` auto-starts ClawChat post gateway-health; plausibly true, runtime-unverified. |
| "What AI providers" (chooser + Switch tool) | FAQ | EDITED | Accurate (Q1). |
| "Difference ClawFactory/ClawAgent" (Studio + scaffolding) | FAQ | EDITED | Accurate; agent-count dropped. |
| "private from others on my machine" | FAQ | FINE | Per-user profile; not multi-user. |
| "Why does Windows warn me" (signed) | FAQ | EDITED | Verified Valid + timestamped. |
| "Mac/Linux?" (Windows-only) | FAQ | FINE | Accurate. |
| "Uninstall" | FAQ | FINE | Uninstaller removes env/runtime/firewall/task (and Studio via Step 4.5). |
| "Subscription?" (one-time, v1.x free) | FAQ | FINE | Accurate. |
| "doesn't phone home" | privacy statement | STRUCTURAL | No telemetry home. |
| **"No cloud dependency. …Ever."** | privacy statement | **FLAG** | Defensible as "no *ClawFactory* cloud," but literal read is false (cloud AI providers are a dependency unless Ollama). Marketing tone — recommend clarifying/removing; left for Bret. |
| ClawAgent $49 feature list | products | EDITED | Studio + orchestration scaffolding shown as crosses (ClawAgent lacks both). |
| ClawFactory $149 feature list | products | EDITED | Studio (provable) + orchestration scaffolding as checks. |
| Download links (GitHub releases) | products | FINE | Correct repos. |
| "© 2026 Frontier Automation Systems LLC" | footer | FINE | — |
| **"MIT License" / "Build from source"** | footer | FLAG (accurate now) | `LICENSE` **is** MIT today, so accurate — but the **PolyForm swap is a pending item**; update the footer when that lands. Not this session. |

---

## Hero extraction (Task 6) — verbatim, for the chat-side rewrite

**Verbatim current hero text** (post-restyle; only the cta-tier-note value line changed
this session, per Bret):

```
[nav]        ClawFactory                                   Buy Now →

[h1]         OpenClaw. Hardened.
             One click.
             ("Hardened." is the accent-colored span)

[hero-sub]   A local AI runtime that doesn't phone home. ClawFactory installs OpenClaw
             inside a WSL2 sandbox with an egress firewall, loopback-only gateway, and
             one-click kill switch. Security controls enforced at the OS level — not by
             prompting the agent to behave.

[CTAs]       Buy ClawFactory — $149 →   (primary)
             Get ClawAgent — $49 →      (ghost)

[cta-tier]   ClawAgent: single agent, 5 min setup · ClawFactory: full security substrate,
             Studio management app, kill switch

[hero-meta]  Windows 10/11  ·  ClawAgent $49  ·  ClawFactory $149
```

**Structure (one paragraph):** The hero is a two-column layout — a text column (left) and
a decorative mascot SVG (right, hidden on mobile). The text column stacks, top to bottom:
a three-line **headline** (`h1`, with "Hardened." accented), a **sub-paragraph** carrying
the core value prop plus the OS-level-enforcement differentiator, a **CTA group** (primary
"Buy ClawFactory — $149" beside a ghost "Get ClawAgent — $49"), a **tier-note** line
contrasting the two products, and a small **meta** line (platform + prices). Rewrite
watch-items: the **"One click"** headline is a simplification (install is multi-step, needs
Administrator + a reboot); the sub-paragraph's control list is accurate and can stand; the
cta-tier-note already carries the corrected Studio framing.

---

## Verify + ship (Task 7)

- Rendered `docs/index.html` in both color schemes (browser pane) — layout intact, both
  modes correct, mascot theme-aware, no broken pairings.
- `git status` clean pre-commit; staged **only** `docs/index.html`; committed `4946578`;
  pushed `5ec8d63..4946578` to `origin/main`.
- **Deployment — BLOCKED (not a code issue; owner action needed).** The commit is on
  `main` and the source (`docs/index.html`) is correct, but **GitHub Pages is not
  currently deploying this repo**. Evidence: the last `github-pages` environment
  deployment was **2026-05-22**; **99 commits since (including this one) produced zero
  builds**; there is no Actions workflow; `POST …/pages/builds` returns **403 "The
  repository does not have a GitHub Pages site,"** and `GET …/pages` 404s (token has full
  `repo` scope, so this is not a permissions artifact). Pages went **dormant ~2026-05-22**;
  because no `docs/` change had been pushed since, it went unnoticed. The live
  `clawfactory.app` is still serving the **frozen** last build (old content: "Rootless
  Docker" present, old gold ×17, 37,922 B). **To publish:** re-enable Pages in **Settings →
  Pages → Source: Deploy from a branch → `main` → `/docs`** (the `docs/CNAME` keeps
  `clawfactory.app`); it will build from current `main` and the new content goes live.
  Re-enabling Pages is a repo-settings change left to the owner — **not done this session**.

---

## END-OF-SESSION GATE

### 1. Task accounting
Comprehension gate — DONE. Task 1 (preamble: HEAD at/after `487e930`, clean; full read;
card #158 created + "Ship-A starting") — DONE. Task 2 (Evergreen restyle, both modes,
contrast-verified) — DONE. Task 3 (four named truth fixes) — DONE. Task 4 (product-shape:
Studio surfaced; version/size — nothing to change; drift carded) — DONE. Task 5 (claim
inventory) — DONE (table above). Task 6 (hero extraction) — DONE. Task 7 (verify + ship)
— **verify DONE; commit + push DONE (`4946578`); live deploy BLOCKED** on GitHub Pages
being re-enabled (dormant since ~2026-05-22, 99 commits/0 builds — owner Settings action,
see Task 7 above). **Beyond the four named fixes**, corrected two more evidence-backed staleness
items (provider-switching-ships, allowlist overstatement). **FLAGGED, not edited:** the
"change settings → email support" staleness (Studio grants folders today), "No cloud
dependency", the "One click" headline (hero/rewrite), and the MIT→PolyForm footer (pending
swap). No silent drops.

### 2. Resource ledger
**Zero cloud.** Site artifact touched: `docs/index.html` (one file; +101/−68). One
read-only investigation subagent (Explore, ~109k tokens, 38 tool calls) + one background
Explore-equivalent = **1 Agent invocation**. Live-site fetch: read-only GETs of the public
`clawfactory.app`. No VMs, no Azure, no product/installer/validation files touched.

### 3. Delta security sweep
No credentials or secret values in the diff, the report, or any commit. No claim was
strengthened without evidence (the two stronger claims — signing, provider-switching — are
both verified). Diff re-read specifically for accidental overclaim: clean.

### 4. Delta bug review
Mechanical-fix exception not used (no product/validation code). Out-of-scope items **carded,
not fixed**: (a) "change settings" FAQ staleness vs Studio grants; (b) "No cloud dependency"
privacy-statement wording; (c) MIT→PolyForm footer at license swap; (d) internal version
drift (`CHANGELOG.md` 1.0.48, `setup.ps1` `$InstallerVersion='1.0.34'` → 1.1.0). These are
Ship-B / follow-up, not this session.

---

## Recommendations
1. **Hero rewrite (next):** audit "One click" (multi-step install) and carry the Studio-led,
   agent-count-free framing into the new hero copy.
2. **Ship-B candidates:** update the "How do I change settings" FAQ to point at Studio for
   folder grants; decide "No cloud dependency" wording; bump `CHANGELOG.md`/`setup.ps1`
   version constants to 1.1.0.
3. **At the PolyForm swap:** update the footer "MIT License" + `LICENSE`.
