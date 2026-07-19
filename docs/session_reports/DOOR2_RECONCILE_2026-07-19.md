# Door-2 closure — reconciliation / re-verification pass

**Date:** 2026-07-19
**Card:** Dispatch #130 "Door-2 closure: findings + claim audit + v2 roadmap (v1 ship-gate)"
**Nature of this session:** the Door-2 closure card was **re-dispatched**, but the work
was already executed and committed on 2026-07-18. This session **reconciled repo state
against the card, independently re-verified the committed findings against the record, and
did not redo committed work** (that would produce duplicate commits / overwrite Bret's
finalized files). No installer code changes. No Door-2 mitigation.

---

## TL;DR

**Door-2 is already resolved for v1 — accept-and-documented, per the Fable Path B verdict
(2026-07-18).** All three ship-gating conditions were satisfied and committed on 2026-07-18
across `23f0990` → `404651f` → `3105bd1`. The working tree is clean; there is nothing left
to commit for the three conditions. This session's contribution is an **independent
re-verification** (below) and this record.

| Condition | State (unchanged since 2026-07-18) | Evidence |
|---|---|---|
| **1. `SECURITY_FINDINGS.md`** | ✅ Committed at repo root (Bret's authored version, `404651f`) | present, verified below |
| **2. Claim-language audit** | ✅ Repo surfaces committed (README, SECURITY.md); site/installer/resource delivered as before/after for Bret to apply | `DOOR2_CLOSURE_2026-07-18.md` §2 |
| **3. v2 roadmap entry** | ✅ `v1.1_backlog.md` #25, bidirectionally cross-linked with `SECURITY_FINDINGS.md` | verified below |

The authoritative close-out remains
[`DOOR2_CLOSURE_2026-07-18.md`](DOOR2_CLOSURE_2026-07-18.md). This file only records the
re-run and its verification.

---

## Comprehension gate (restated)

**The three conditions** (Fable verdict, Path B): (1) commit `SECURITY_FINDINGS.md`
partitioning the guarantees and stating the residual + actor model; (2) audit every public
surface so none presents spend / chat / safety-rules gating as hostile-agent-proof; (3) add
a v2 backlog entry naming separate-identity isolation as Door-2's closure.

**Structural vs gateway-path, in my own words.** A *structural* guarantee is enforced by
the OS / filesystem / network stack, so it holds no matter what the agent does — it stays
true against a hostile agent that already has shell access as `clawuser`. Those are: file
isolation, egress allowlist, inbound deny, credential-at-rest protection, safety-rules
*file* integrity, and the kill switch. A *gateway-path* guarantee is enforced on the network
path through the local gateway/proxy; it holds against everything arriving over that path
(Door-1, closed and verified — including all of ClawChat), but is only **advisory** against
an agent that starts the runtime by another route as the same UID (Door-2, open). Those are:
the spend cap, chat gating, and safety-rules *enforcement at turn time*. The realistic
Door-2 actor is the agent itself acting on hostile instructions — in scope by the product's
own "assume the model is hostile" principle. The honest line is exactly which controls are
which, and never dressing a gateway-path control as absolute.

**No installer code changes are in scope.** This is documentation, audit, and copy. Any
mitigation of Door-2 keys on the same shared identity it would try to constrain, so it can be
routed around while implying the boundary moved — shipping one would violate the product's
own structural-vs-advisory line.

---

## Independent re-verification of the committed `SECURITY_FINDINGS.md`

Re-checked each load-bearing claim against the record this session (not trusting the prior
pass):

| Claim | Verified against | Result |
|---|---|---|
| "Passed the install gate on **seven consecutive clean machines**" | `validation-runs/cfv-0717a…g` = 7 dirs; `CONFIRM_v1045_2026-07-17.md` header ("7th consecutive clean-box install") | ✅ confirmed |
| File isolation refused by direct path, listing, symlink, `../../..`, fs-wide search; `/etc/shadow` denied; contents never appeared | cfv-0717d headline PROVEN (`CONFIRM_v1045` L97; verification table in `DOOR2_CLOSURE_2026-07-18.md` vs `probe-v1039-validation.ps1` §4.3–4.4) | ✅ confirmed |
| Zero model tokens on **both** block cases | `CONFIRM_v1045` Task 4 table — 4.1 `cap=0` and 4.2 tampered-SOUL both "no (0 tokens)"; "4.3 SECURITY: neither block case ran the model → PASS" | ✅ confirmed |
| Safety-rules file root-owned, read-only, immutable, hash-pinned; agent can't write/chmod/delete-recreate | `CONFIRM_v1045` B4.0 (`SOUL.md root:root -r--r--r-- lsattr=----i…`) | ✅ confirmed |
| Loopback-only gateway; agent's identity must traverse the root proxy to reach the private gateway port | `CONFIRM_v1045` Task 4 (proxy relays `CONFIRMPROXYOK`; isolation proven); chat-proxy record | ✅ confirmed |
| Credential row — key in Windows Credential Manager (DPAPI) on Windows; inside the sandbox a **mode-600 file**, not encrypted at rest | `reference_openclaw_api_key_location` (key value in `auth-profiles.json` mode 600); README §14 / SECURITY §1 | ✅ confirmed — this is the corrected row (no longer claims "never plaintext"); reads honestly |
| Residual = same-identity full-path runtime invocation; exposure is cost/unmetered, **not** data access; closed by separate-identity isolation (backlog #25); root-proxy pattern proven | `CONFIRM_v1045` "Still open #1"; `v1.1_backlog.md` #25 | ✅ confirmed |

**No claim failed re-verification.** The one claim corrected during the original pass (the
credential "never plaintext" overclaim) is committed in its corrected, accurate form.

**Condition 3 cross-reference is live in both directions:** `SECURITY_FINDINGS.md` →
`v1.1_backlog.md` #25, and #25 → `SECURITY_FINDINGS.md`. Backlog #25 states the residual, the
proven root-proxy design seed, and the open (a) dedicated-UID / (b) container / (c) userns
design question — Task 3.1/3.2 satisfied.

---

## Card sync — could not be performed from this session

`C:/Projects/FrontierAI/scripts/dispatch_card.py` requires `DISPATCH_URL` / `DISPATCH_SECRET`.
The Secure-Setup repo's `.env` carries **only the Azure signing credentials** — no Dispatch
config — so the helper is a **logged no-op** here (by its own design, exit 0). Consequently
this session **could not fetch card #130 comments and could not move the card's status**.

**Action for Bret:** if the board still shows #130 as `in_progress`, move it to `done` from a
Dispatch-enabled session, or confirm the 2026-07-18 session already synced it. The *work* is
complete regardless of board state.

---

## Remaining ship checklist (unchanged by this session)

1. **PolyForm Perimeter license swap** — LICENSE, README badge, and site footer still say
   **MIT**. Separate job.
2. **API key wizard** — separate job (ClawChat settings tab; backlog #19).
3. **Apply the delivered site / installer / resource copy edits** — `docs/index.html`
   (clawfactory.app), `ClawFactory-Secure-Setup.iss` wizard text, `resources/safety-rules.md`
   → `SOUL.md`. All delivered as exact before/after in `DOOR2_CLOSURE_2026-07-18.md` §2.D/E/F;
   Bret's action (Pages auto-publish / installer source / SOUL re-pin). The hero copy is
   largely already absorbed — the remaining site edits are product-truth fixes (removed
   Docker, "5 agents"/"multi-agent workflows" positioning, key-storage wording, signing-status
   FAQ), not a hero rewrite.
4. **Confirm-and-reconcile flags** (from the prior close-out): code-signing status (site FAQ
   says "unsigned" vs README's signed path), the "5 agents / multi-agent workflows" $149
   positioning claim (only `main` runs), and the Stripe checkout product descriptions
   (out of reach — verify they don't repeat Docker / 5-agents / gating-absolute claims).

None of these block the "Door-2 stops being a blocker" line, which the committed
`SECURITY_FINDINGS.md` already satisfies.

---

## End-of-session gate

- **Task accounting:** Comprehension gate met. All three conditions confirmed
  already-committed and independently re-verified against the record. Card #130 work =
  **done**; board sync **not reachable** from this repo (flagged above). One new file this
  session: this reconciliation record.
- **Resource ledger:** **no Azure resources this session** (documentation only — no VM, no
  validation run). Live ledger unchanged; nothing to tear down.
- **Delta security sweep:** **no security control was changed.** `git status` clean at start;
  the only write this session is this `docs/session_reports/*.md` record. `setup.ps1`, the
  `.iss`, and every `resources/*` control script are byte-identical to v1.0.45. No installer
  source appears in the diff.
- **Delta bug review:** no code changed → no new code paths, no regressions. Cross-links in
  `SECURITY_FINDINGS.md` ↔ `v1.1_backlog.md` #25 re-checked and resolve.
- **Scratch key:** none used.
