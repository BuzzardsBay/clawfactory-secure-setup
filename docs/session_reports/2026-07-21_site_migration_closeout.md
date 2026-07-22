# Site migration — clawfactory-site close-out (2026-07-22)

**Card:** #160 · **Session date:** 2026-07-22 (prompt dated 2026-07-21)
**Repos:** public `BuzzardsBay/clawfactory-site` (target) · private `ClawFactory-Secure-Setup` (read-only source; two permitted writes: README pointer + this report)

## Headline

`clawfactory.app` now serves the v1.1.0 truth-pass site (Evergreen restyle, `4946578`
content) from the public `clawfactory-site` repo. Zero downtime, zero DNS changes,
scrub gate passed before push, product repo stays private.

## Deviation from spec (material, beneficial)

The spec said CREATE `BuzzardsBay/clawfactory-site`. **It already existed** — created
2026-07-10 by a prior session ("Restore clawfactory.app: public marketing site decoupled
from installer source", card #82 era), and it was **already the live Pages site serving
`clawfactory.app`**: Pages `built`, custom domain attached, HTTPS enforced, cert approved
through 2026-10-08, source `main` `/` root. The spec's recon checked only the product
repo's Pages (correctly found dormant) and missed this repo. Consequence: the frozen
live site was the 2026-07-13 state of this repo, not a May build of the product repo.

Adapted plan: audit the existing public repo (contents + full history), push the
`4946578` site content through the scrub gate, verify the build. Tasks 2/5/6 (create,
enable Pages, attach domain) collapsed into verification-only. No-downtime preserved by
Pages semantics — the old build serves until the new build succeeds; the domain was
attached throughout.

## Site-file inventory (Task 1)

Product repo `docs/` inspected at HEAD `b0a3f1c` (includes `4946578`, tree clean):

| File | Verdict | Reason |
|---|---|---|
| `docs/index.html` (39,948 B) | SITE | The entire site: single page, inline CSS/JS, data-URI favicon, Google Fonts CDN, zero relative refs |
| `docs/CNAME` (`clawfactory.app`, 15 B) | SITE | Domain binding (already present in target repo, byte-identical) |
| `docs/reference/OPENCLAW_VERSION_POLICY.md` | EXCLUDED | Internal engineering doc: unlinked from site, references `setup.ps1` internals + validation harness; postdates the live build — no URL breaks |
| `docs/session_reports/*.md` (40 files) | EXCLUDED | Private close-outs |

Layout: **root-served** (`main` `/`) — matches the repo's existing (and cleanest) Pages config.

## Scrub gate (Task 3) — PASS, printed before push

Published tree = exactly 4 files:

1. `index.html` — safe because: deliberate public marketing page (Ship-A truth pass);
   grep hits are only the phrase "API key" in product-behavior copy (DPAPI/Credential
   Manager claims); no credential values, no dev paths, no internal IDs, no
   findings/harness refs; links are Stripe pay links + public GitHub URLs already live.
2. `CNAME` — safe because: exactly `clawfactory.app`.
3. `README.md` — safe because: repo purpose + standing rule only; internal card-ID
   reference removed in this revision; no product internals.
4. `.gitignore` — safe because: three generic OS/log patterns.

Confirmations:
- No product source / tests / close-outs / SECURITY_FINDINGS in the tree.
- No product-repo git history: target history = 2 site-only commits (2026-07-10/13),
  both audited blob-by-blob — no private content. One benign "card #82" mention remains
  in the superseded README revision (already public 9 days; history not rewritten).
- Entropy scan for credential-shaped strings: only public GitHub URLs.
- Zero hits: `C:\Users`, `bmcki`, `.env`, Door-1/Door-2 residual language,
  `azure-validate`, TODO/FIXME, `cfv-*`, `SECURITY_FINDINGS`, `session_report`.

## Publish + verification (Tasks 4–6)

- Commit `85b3c05` "Ship v1.1.0 site: Evergreen restyle + truth-pass content";
  `index.html` blob **`d8af6012`** verified identical to product `HEAD:docs/index.html`.
- Pages build for `85b3c05`: `building` → **`built`** (~3 min after push, 15:24Z).
- **github.io URL:** `https://buzzardsbay.github.io/clawfactory-site/` → HTTP 200
  (301s to the custom domain, standard Pages behavior) — serves NEW content:
  "ClawFactory Studio" present (0 occurrences in old content), "Azure Trusted Signing" present.
- **Domain:** `https://clawfactory.app/` → HTTP 200 direct — "ClawFactory Studio" +
  "Evergreen palette" present. Cutover state: fully propagated at verification time,
  no cert wait (cert pre-existing, expires 2026-10-08).
- `www.clawfactory.app` → 301 → apex; `http://` → 301 → `https://`; `https_enforced: true`.

## Task accounting

| Task | Status | Note |
|---|---|---|
| 1 Preamble + inventory | DONE | HEAD includes `4946578`, tree clean; inventory above |
| 2 Create public repo | DONE (as verify) | Repo pre-existed + already live; cloned to `C:\Users\bmcki\clawfactory-site`; contents + history audited |
| 3 Copy + scrub gate | DONE | PASS; checklist above; push blocked until pass |
| 4 CNAME + commit | DONE | CNAME pre-existing byte-identical; README refreshed (kept standing rule, dropped card ID); `.gitignore` added; pushed `85b3c05` |
| 5 Verify on github.io | DONE | 200 + new-content markers before any domain action |
| 6 Domain cutover | DONE (no-op verify) | Domain already attached; HTTPS enforced; both hosts verified serving new content |
| 7 Product-repo pointer | DONE | One-line README note (this commit); `docs/` files untouched |

## Resource ledger

- Public repo: `https://github.com/BuzzardsBay/clawfactory-site` (pre-existing; updated).
- Files published: `index.html`, `CNAME`, `README.md`, `.gitignore` — nothing else.
- Cloud VMs: **zero**. DNS changes: **zero**. Namecheap: untouched.
- Product repo writes: README pointer line + this close-out (both permitted).

## Delta security sweep

- Scrub-gate checklist printed above — **nothing private is in the public repo**
  (working tree and full git history both audited). No credentials anywhere.
- The live site's provenance corrected: it serves from `clawfactory-site`, not the
  product repo's dormant Pages. Product repo Pages remains dormant/404 — nothing to
  disable; re-enabling it is NOT needed and would be wrong (private repo).

## Delta bug review

- **Carded (task chip `task_61e58954`):** live site download links point at the PRIVATE
  product repo (`.../ClawFactory-Secure-Setup/releases/latest` 404s for visitors;
  footer "Build from source" links likewise). Pre-existing since 2026-05-22, not a
  regression — the buy/download path needs a public artifact home. Related Ship-B
  items: MIT→PolyForm footer, "No cloud dependency" overclaim, change-settings FAQ.
- Stale memory to correct: "Pages dormant → Bret must re-enable on product repo" —
  superseded; the site never needed product-repo Pages again.

## New repo URL

`https://github.com/BuzzardsBay/clawfactory-site` — live at `https://clawfactory.app`.
