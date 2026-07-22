# Site content pass — hide buy path + truth fixes (2026-07-22)

**Card:** #161 → done · **Repo written:** public `clawfactory-site` (commit `9e440c0`)
**Close-out location:** product repo `session_reports/` — the convention, and close-outs
carry internal strategy context (pricing deferral, liability reasoning) that must not
live in a public repo.

## Headline

The live site no longer sells anything: every Stripe control replaced by an honest
non-clickable "Launching soon" state, all prices removed, and six truth defects fixed.
Live-verified on clawfactory.app. Zero pricing/tier decisions made.

## Before/after (every change)

| # | Where | Before | After |
|---|---|---|---|
| 1 | Nav | `Buy Now →` → Stripe | `Launching soon` chip (non-clickable, accent outline) |
| 2 | Hero CTAs | `Buy ClawFactory — $149` + `Get ClawAgent — $49` → Stripe | Single `Launching soon` chip; tier-note line kept (no prices in it) |
| 3 | Hero meta | `Windows 10/11 · ClawAgent $49 · ClawFactory $149` | `Windows 10/11 · One-time purchase` |
| 4 | Step 03 | "Your AI agent is live at `127.0.0.1:8787`" | "Open **ClawFactory Studio** from the Start Menu — your agent runs locally. Nothing leaves your machine without your permission." (browser-at-a-port model retired; Studio IS in the Start Menu per the v1.1.0 combined installer) |
| 5 | Tier FAQ | "ClawFactory ($149)… plus the orchestration scaffolding for multi-agent workflows. ClawAgent ($49)…" | Prices removed; orchestration clause removed (scaffolding ≠ sold functionality); Studio stays the stated differentiator |
| 6 | SmartScreen FAQ | "…against the value published on the GitHub Releases page" | "…against the value published with the release" |
| 7 | Subscription FAQ | "…free — download the latest installer from the releases page and reinstall…" | "…free." (unreachable releases-page pointer cut) |
| 8 | Privacy banner | "No telemetry. No cloud dependency. No data collection. Ever." | "No telemetry. No data collection. Nothing leaves your machine except the API calls you configure." |
| 9 | Product cards | `$49`/`$149` badges, `Buy` Stripe CTAs, `Download from GitHub` links, "Factory orchestration scaffolding" rows | De-priced cards, no buttons/links, orchestration row gone; shared line "One-time purchase. **Launching soon.**" |
| 10 | Footer | `MIT License · Build from source (private repo) · support@` / `GitHub →` private repo | `PolyForm Perimeter License · support@` / `GitHub →` public clawfactory-site (name only — no license URL invented) |

**Stripe URLs: removed entirely** (not commented out) — zero occurrences in the served
page; recoverable from git history if fulfillment returns.

## Pricing-card render choice

Kept both cards minus prices/buttons (option B) with the shared launching-soon line.
Reasoning: the feature lists are accurate product information; collapsing to a single
note would delete truthful content and hollow out the section. RECOMMENDED tag kept
(pre-existing state, not a new decision).

## Verification

- **Local render, both modes** (headless Edge, 1300px; Browser pane was unresponsive —
  two 300 s navigate timeouts, fell back): dark + light screenshots clean, chips read
  intentional, no layout breaks.
- **Live (clawfactory.app, HTTP 200, build `built` on `9e440c0`):**
  - PRESENT: "Launching soon" ×3 · "PolyForm Perimeter License" · "ClawFactory
    Studio</strong> from the Start Menu" · "except the API calls you configure"
  - ABSENT (0 matches): `stripe`, `$49`, `$149`, `MIT License`, `Build from source`,
    `releases/latest`, Step-03 `127.0.0.1:8787</code>`
  - Untouchable intact: security table still shows "Gateway binds to 127.0.0.1:8787"
    (exactly 1 occurrence — the accurate table row).
- **Remaining external links, anonymous:** Google Fonts 200, clawfactory-site 200,
  mailto n/a. Nothing else remains.

## Strategy items flagged — NOT edited

1. **Prices** — hidden, not decided.
2. **Tier differentiation** — cards now differ only by the Studio row; the near-identical
   split is the pricing analysis's problem.
3. **ClawAgent positioning + free-download conflict** — discovered: `clawagent-setup` is
   a PUBLIC repo with a live release (v1.0.4). ClawAgent was simultaneously priced $49
   and freely downloadable; the site link is gone but the repo remains public. Whether
   to privatize it is a strategy call.
4. **Fulfillment wording** — nothing beyond "launching soon".
5. **Change-settings FAQ** — still directs users to email support and predates Studio
   grants; not in this session's named fixes, left untouched (known Ship-B item).

## Carded / chipped

- Dispatch **#162** (todo): pricing + fulfillment analysis (unhide buy path) — owns
  items 1–4 above.
- Chip `task_0c26e512`: wire PolyForm Perimeter end-to-end — product LICENSE is still
  MIT + README badge; site footer is name-only ahead of the swap by Bret's direction.
- Chip `task_61e58954` (fix download links) dismissed — superseded by this pass.

## Gate

1. **Task accounting:** T1 preamble DONE · T2 hide transaction layer DONE · T3 truth
   fixes DONE (all seven) · T4 strategy items flagged-not-edited DONE · T5 verify+ship
   DONE. No drops.
2. **Resource ledger:** zero cloud; files changed: `index.html` only (site repo);
   product repo: this close-out only. Live state = launching-soon, de-priced, verified.
3. **Delta security sweep:** no credentials touched or present; NO visible path reaches
   Stripe or a private-repo 404; no claim strengthened (every edit weakens or
   neutralizes a claim except Step 03, which restates shipped, validated behavior).
4. **Delta bug review:** all remaining external links verified anonymous-resolvable;
   Browser-pane unresponsiveness noted (tooling, not site); clawagent-setup public
   exposure flagged to #162.
