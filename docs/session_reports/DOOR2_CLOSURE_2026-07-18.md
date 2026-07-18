# Door-2 closure — findings commit + claim-language audit + v2 roadmap

**Date:** 2026-07-18
**Card:** Dispatch #130 "Door-2 closure: findings + claim audit + v2 roadmap (v1 ship-gate)"
**Verdict executed:** Fable *ClawFactory Door-2 Security Architecture Verdict*, 2026-07-18, **Path B** (accept the same-identity residual for v1, document it plainly, commit separate-identity isolation to v2).
**Scope:** documentation, audit, and copy only. **No installer code changes.** No Door-2 mitigation of any kind.

---

## TL;DR

**Door-2 is resolved for v1 as accept-and-documented.** The three ship-gating
conditions from the verdict are satisfied for every surface I can change in the
repo; the surfaces that would auto-publish the live site or that live in
installer source are delivered here as exact before/after for Bret to apply (they
were **not** committed, per the "do not publish live-site changes / no installer
code changes" constraints).

| Condition | Status |
|---|---|
| **1. `SECURITY_FINDINGS.md`** — partition guarantees, state residual + actor model | ✅ **Committed** (repo root) |
| **2. Claim-language audit** — no surface presents spend/chat/safety gating as hostile-agent-proof | ✅ **Repo surfaces committed; site/installer/resource delivered below** |
| **3. v2 roadmap entry** — separate-identity isolation as Door-2's closure | ✅ **Committed** (`v1.1_backlog.md` #25) + cross-referenced from `SECURITY_FINDINGS.md` |

**`SECURITY_FINDINGS.md` — supplied late, verified, one claim corrected.**
It was not attached at session start (absent from repo, scratchpad, Downloads,
Desktop, Documents), so a placeholder was authored from the record and committed
first (`23f0990`). Bret then supplied his authored version, which was verified
against the record and **swapped in** (`<swap commit>`). Every claim held **except
one**, corrected per Task 1.2 (flag, don't silently ship):
> **Credential protection — "your API key is not stored in plain text."** The key
> *is* stored plaintext in the sandbox at `~/.openclaw/auth-profiles.json` mode
> 600 (SECURITY.md §1, README §14, `reference_openclaw_api_key_location`); DPAPI
> protects only the Windows-side copy. Same overclaim already fixed on the site
> ("never plaintext" → "never on a command line or in `.env`"). Corrected the row
> to what is true and proven: DPAPI on Windows + mode-600 file in the sandbox,
> never on a command line / in env / in `.env`, with the not-encrypted-at-rest
> nuance stated. Also added the Task 3.2 cross-reference to backlog #25 (his draft
> lacked it). All other claims verified below.

---

## Task 1 — `SECURITY_FINDINGS.md` (Condition 1)

**Placed at:** repo root (matches the `SECURITY.md` convention — security-facing
docs live at root, not under `docs/`). **Committed.**

It partitions every control into **structural** (holds against the network AND a
hostile agent as `clawuser`) vs **gateway-path** (holds through the gateway —
Door-1, closed — advisory against a same-UID bypass — Door-2, open), states the
residual in one plain sentence, and includes the actor model (local-only, not
remote, not a file-isolation break) so scope can't be misread in either
direction. It cross-links the v2 roadmap entry.

### Verification of every factual claim (Task 1.2 — repo is truth)

Checked each load-bearing claim in Bret's supplied doc against the record (the
file-isolation vectors were confirmed against `probe-v1039-validation.ps1`
§4.3–4.4, which drove cfv-0717d — including the `find / -name` filesystem-wide
search and `/etc/shadow`):

| Claim | Verified against | Result |
|---|---|---|
| Seven consecutive clean boxes | `validation-runs/cfv-0717a…g/install-verdict.txt` — all `INSTALLER_DONE=success` (7 dirs) + `CONFIRM_v1045_2026-07-17.md` | ✅ confirmed |
| Structural controls proven (file isolation, egress, inbound/loopback, key-at-rest, SOUL file integrity, kill switch) | `SECURITY.md` §§1,2,4,6; `CONFIRM_v1044`/`cfv-0717d` (file isolation from agent's own output); `setup.ps1` `Step-EgressFirewall` L1244-1267; `.iss` L109 (kill-switch shortcut) + `resources/clawfactory-stop.ps1` present | ✅ confirmed |
| Zero model tokens on **both** block cases | `CONFIRM_v1045` Task 4 table — 4.1 `cap=0` and 4.2 tampered-SOUL both "no (0 tokens)" | ✅ confirmed |
| `SOUL.md` `root:root` 444 + immutable | `CONFIRM_v1045` B4.0 (`lsattr` shows `+i`); `setup.ps1` `Step-ApplySafetyRules` L2286-2333 | ✅ confirmed |
| Loopback-only gateway (real gateway 8788 behind root proxy 8787) | `CONFIRM_v1045` Task 4; `project_chatcompletions_proxy` record; `SECURITY.md` §4 | ✅ confirmed |
| Credential nuance (agent holds its own key; egress bounds exfil) | `SECURITY.md` §1 limitations; `reference_openclaw_api_key_location` (key value in `auth-profiles.json` mode 600) | ✅ confirmed — reflected honestly in the doc |

**No claim failed verification.** (The only failed *premise* was the prompt's
"Bret has authored / provided alongside" — handled by authoring per the verdict,
flagged above, not silent.)

---

## Task 2 — Claim-language audit (Condition 2, load-bearing)

### 2.1 Surface inventory (checklist)

| # | Surface | Type | Disposition |
|---|---|---|---|
| A | `README.md` | Repo doc | ✅ changed + committed |
| B | `SECURITY.md` | Repo doc | ✅ changed + committed |
| C | `SECURITY_FINDINGS.md` | Repo doc (new) | ✅ self-consistent, committed |
| D | `docs/index.html` (**clawfactory.app** via Pages) | **Live site** | ⚠️ before/after below — **deliver, not committed** |
| E | `ClawFactory-Secure-Setup.iss` (wizard/dialog/ack text) | **Installer source** | ⚠️ before/after below — **deliver, not committed** |
| F | `resources/safety-rules.md` → `SOUL.md` (agent-recited) | **Installer resource (hash-pinned)** | ⚠️ before/after below — **deliver, not committed** |
| G | `CHANGELOG.md` | Repo doc | ✅ no change — historical record (Docker / 5-agent entries describe what shipped at that version; not marketing) |
| H | `CONTRIBUTING.md` | Repo doc | ✅ no change — no gating claims |
| I | Stripe checkout product descriptions (`buy.stripe.com/…`) | **External point-of-sale** | ⚠️ out of reach — **Bret to verify in Stripe** (see flags) |

**Key finding on Condition 2 itself:** *no public surface presents spend, chat,
or safety gating as hostile-agent-proof.* The site's strong "enforced at the OS
level… cannot be overridden by the agent" language (FAQ, hero) is correctly
**scoped to the four structural controls** (filesystem, inbound, outbound,
loopback) and does not foreground spend/chat/SOUL at all — so it is accurate and
was left strong. The audit's actual yield is **product-truth defects** (removed
Docker, false "containers", stale claims, one false key-storage statement) plus
two **gateway-path-as-absolute** phrasings in installer/resource text.

### 2.A README.md — CHANGED + COMMITTED

| Line (was) | Before | After | Why |
|---|---|---|---|
| Badge | `release-v1.0.37` | `release-v1.0.45` | Stale version |
| Intro | "…non-sudo `clawuser`, **rootless Docker**, an nftables…" | "…non-sudo `clawuser`, an nftables…" | Docker removed (SECFIX_CLOSE_DOORS decision A) |
| What's inside | "**Docker** in rootless mode under `clawuser`." (bullet) | *(removed)* | Docker removed |
| Egress bullet | "…base allowlist (GitHub, npm, **Docker Hub**, OpenClaw, ClawHub). 6 h refresh timer" | "…base allowlist (GitHub, npm/Node, OpenClaw, ClawHub, Ubuntu apt). Periodic refresh timer" | Docker Hub not in the allowlist (`setup.ps1` L1248-1260); aligned to actual hostlist |
| Kill Switch | "…stops the gateway and **any agent containers**." | "…stops the gateway and the agent processes." | No containers |
| Security table | "…Non-root, no sudo. **Rootless Docker.** `SOUL.md`…" | "…Non-root, no sudo. `SOUL.md`…" | Docker removed |
| Security section | "Full threat model in SECURITY.md." | + pointer to `SECURITY_FINDINGS.md` (structural vs gateway-path + residual) | New doc discoverability |

### 2.B SECURITY.md — CHANGED + COMMITTED

| Location | Change | Why |
|---|---|---|
| Security Model intro | Added a "Two classes of guarantee" callout (structural vs gateway-path) + pointer to `SECURITY_FINDINGS.md` | Makes the load-bearing distinction explicit at the top |
| §3 Limitations (prompt-injection) | Rewrote the stale "chatCompletions HTTP endpoint is **not** gated" → now **gated by the root proxy since v1.0.43** (Door-1 closed); residual = same-UID full-path bypass (**Door-2**); noted SOUL *file* immutable either way, only turn-time *enforcement* bypassable; cross-ref `SECURITY_FINDINGS.md` | The old text under-stated (said not gated when it now is) and didn't frame the residual |

*Note:* SECURITY.md §8 already labels GO-gating as "prompt-level enforcement"
(not enforced) — **already honest, no change needed** (see GO-gating flag).

### 2.D docs/index.html (clawfactory.app) — DELIVER (do NOT commit; Pages auto-publishes)

> `docs/CNAME` = `clawfactory.app`; this file is the live-site source served by
> GitHub Pages. Editing + pushing it would publish. Apply these by hand.

**S1 — Security table, "Rootless Docker" row (≈L722-724) — FIX (false):**
```html
<!-- BEFORE -->
<td class="control-name">Rootless Docker</td>
<td class="control-desc">No root access inside the container</td>
<!-- AFTER -->
<td class="control-name">Non-root clawuser</td>
<td class="control-desc">Agent runs as a non-root Linux user with no sudo — no privilege escalation</td>
```
Docker was removed; there is no container. False claim on the primary sales page.

**S2 — "DPAPI key storage" row (≈L742-743) — FIX (overclaim):**
```html
<!-- BEFORE -->
<td class="control-desc">API key in Windows Credential Manager, never plaintext</td>
<!-- AFTER -->
<td class="control-desc">API key in Windows Credential Manager (DPAPI); never on a command line or in .env</td>
```
"never plaintext" is not accurate — inside WSL the key is written to
`~/.openclaw/auth-profiles.json` (mode 600). The accurate protection is DPAPI at
rest on Windows + never on a command line / in `.env` / in the process env.

**S5 — SmartScreen FAQ (≈L878) — FLAG (stale, under-claim):**
> "The ClawFactory installer is **not yet code-signed** … We are working toward
> obtaining a code signing certificate."

A signed-build path exists (`scripts/build_release.ps1`, Azure Artifact Signing,
per README + wired 2026-07-06). **Confirm whether the shipped v1.0.45 artifact is
signed**; if so, rewrite this FAQ (and backlog #7, which is also stale). Not a
security overclaim, but inaccurate.

**S3/S4 — "5 agents" / "multi-agent workflows" (≈L677, L858, L953) — FLAG (positioning, your call):**
> hero note: "…ClawFactory: full security substrate, **5 agents**, kill switch"
> FAQ: "…**5 agent profiles and factory orchestration scaffolding for
> multi-agent workflows**." · comparison: "**Multi-agent support (5 agents)**"

Only the `main`/orchestrator agent is active; skill-scout/skill-builder/publisher
are staged profiles (stubs). The *profiles* exist, so "5 agent profiles" is
defensible; "multi-agent workflows" implies working orchestration that does not
run. Because this is the **$149 value proposition**, I did **not** unilaterally
rewrite it — it's a pricing/positioning decision. Recommended honest framing:
"5 agent profiles (main agent active; additional roles staged for the roadmap)."
Same class as the "four agents" item; **rewrite the copy, do not build the
agents this session.**

*No change:* hero "enforced at the OS level — not by prompting the agent"
(scoped to structural controls — accurate); FAQ "What exactly is restricted"
("None of these can be overridden by the agent itself" — bounded to the four
structural controls — accurate; this is the model of correct copy).

### 2.E ClawFactory-Secure-Setup.iss — DELIVER (do NOT commit; installer source)

**I1 — Kill Switch shortcut comment (L113) — FIX (false):**
```
BEFORE: Comment: "Emergency stop: kills all ClawFactory agent containers"
AFTER:  Comment: "Emergency stop: stops the OpenClaw gateway and agent processes"
```

**I2 — Welcome page guardrail (L434) — FIX (gateway-path stated as absolute):**
```
BEFORE: '  - Safety rules are immutable; every turn is spend- and integrity-gated.'
AFTER:  '  - Safety rules are immutable; turns through the gateway are spend- and integrity-gated.'
```
"Safety rules are immutable" is structural (keep). "every turn is gated" is a
gateway-path control; a same-UID full-path invocation isn't gated (Door-2).

**I3 — Security acknowledgement page, MANDATORY (L544-545) — FIX (false, highest priority):**
```
BEFORE: 'I understand agents execute code in isolated containers and I will '
        'personally review every skill before publishing.'
AFTER:  'I understand agents execute code inside a hardened WSL2 environment '
        '(non-root, network-restricted) and I will personally review every skill '
        'before publishing.'
```
The user is required to attest to a false statement ("isolated containers").

**I4 — API key page (L512-513) — FIX (false):**
```
BEFORE: 'Windows user). It is NEVER written to a file inside WSL.'
AFTER:  'Windows user). Inside WSL it is written only to ~/.openclaw/auth-profiles.json'
        '(mode 600) — never on a command line and never in .env.'
```
The key **is** written to `auth-profiles.json` inside WSL (README §14, SECURITY §1,
`setup.ps1`). "NEVER written to a file inside WSL" is a direct misstatement.

*No change:* Welcome page L430-433 (non-root, egress allowlist, loopback,
automount) — all accurate structural claims, keep strong.

### 2.F resources/safety-rules.md → SOUL.md — DELIVER (do NOT commit; hash-pinned resource)

Two lines state gateway-path enforcement as absolute. **Constraints:** (1) editing
this file recomputes the pinned SOUL SHA-256 (`setup.ps1` L2293 hashes it at
install), so any change **rides with an installer rebuild + re-validation** — out
of this session's docs-only scope; (2) this is the **agent-facing** SOUL, so the
reword must **not name the bypass** (that would hand a hostile agent the exact
Door-2 route). Proposed non-instructive rewording:

**R1 — L18:**
```
BEFORE: **Every turn is gated in code before you start**: a spend cap and a SOUL
        integrity check. A blocked turn never runs.
AFTER:  **Turns are gated in code before you start** — a spend cap and a SOUL
        integrity check — and you must not attempt to run outside that gate. A
        gated turn that is blocked does not run.
```
**R2 — L5:** soften "re-checked in code before **every turn**; on a mismatch the
turn is refused" → "re-checked in code **before a gated turn runs**; on a
mismatch the turn is refused." Keep the **file-integrity** sentence
("root-owned, read-only, and immutable — your account cannot change it") strong —
that is structural and true.

**Recommendation:** lowest-severity of the findings and coupled to a re-pin +
the no-teach-the-bypass constraint. Apply at the next installer build with review,
**or** consciously accept the current agent-facing wording for v1. Your call.

---

## Task 3 — v2 roadmap entry (Condition 3) — COMMITTED

Added **`v1.1_backlog.md` #25 "Door-2 closure: separate-identity agent
isolation."** It states: the residual it closes (shared `clawuser` UID → un-gated
full-path invocation), the design seed (the **root-proxy pattern already proven
in this release** — the chat proxy runs as root and that boundary holds), and the
open design question (**dedicated UID vs container vs user namespace**, to be
settled by an analysis pass on v2's clock). `SECURITY_FINDINGS.md` cross-links
back to it (Task 3.2 satisfied).

---

## Task 4 — Close-out

### Door-2 status
**Resolved for v1: accept-and-documented, per the Fable verdict.** Conditions 1
and 3 are fully committed. Condition 2 is committed for repo surfaces; the live
site (D), installer text (E), and safety-rules resource (F) are delivered above
as exact before/after for you to apply — none block the "Door-2 stops being a
blocker" line, which the committed `SECURITY_FINDINGS.md` satisfies.

### Remaining ship checklist (unchanged by this session)
1. **PolyForm Perimeter license swap** — LICENSE, README badge, and the site
   footer still say **MIT**. Separate job.
2. **API key wizard** — separate job (ClawChat settings tab, backlog #19).
3. **Hero copy rewrite** — largely **already absorbed**: the hero and FAQ already
   lead with structural proof and scope their strong language correctly. The
   remaining site edits are the product-truth fixes in §2.D, not a hero rewrite.
4. **Apply the delivered site/installer/resource edits** (§2.D/E/F) — your action.

### Flags for Bret (decisions / out-of-scope)
- **`SECURITY_FINDINGS.md`** — Bret's authored version is now committed; one
  credential claim was corrected on verification (see TL;DR). Confirm the reworded
  credential row reads the way you want.
- **"5 agents" / "multi-agent workflows"** on the site is the $149 value prop and
  is fiction (only `main` runs) — positioning/pricing decision; copy rewrite
  proposed, product not touched (per scope).
- **Code-signing status** — site FAQ + backlog #7 say "unsigned"; README + the
  2026-07-06 wiring say a signed path exists. Confirm whether v1.0.45's artifact
  is signed and reconcile.
- **Stripe checkout descriptions** (point of sale) — I can't reach them; verify
  they don't repeat the Docker / 5-agents / gating-absolute claims.
- **safety-rules.md reword** is coupled to an installer re-pin and must not teach
  the bypass — apply with the next build or accept for v1.

---

## Git — explicit per-file staging (docs/copy only)

Committed this session (no installer source in the diff):
- `SECURITY_FINDINGS.md` (new)
- `README.md`
- `SECURITY.md`
- `v1.1_backlog.md`
- `docs/session_reports/DOOR2_CLOSURE_2026-07-18.md` (this file)

**Not touched** (delivered as before/after, not applied): `docs/index.html`,
`ClawFactory-Secure-Setup.iss`, `resources/safety-rules.md`.

---

## End-of-session gate

- **Task accounting:** Conditions 1 & 3 committed; Condition 2 committed for repo
  surfaces + delivered for site/installer/resource. Comprehension gate met (with
  the missing-file discrepancy flagged). Card #130 → **done**.
- **Resource ledger:** **no Azure resources this session** (documentation only —
  no VM, no validation run). Nothing to tear down.
- **Delta security sweep:** **no security control was changed.** All edits are
  documentation/copy. `setup.ps1`, the `.iss`, and every `resources/*` control
  script are **unmodified**; the installer, firewall, SOUL protection, turn-gate,
  and proxy are byte-identical to v1.0.45. `SECURITY_FINDINGS.md` and the SECURITY.md
  §3 rewrite *describe* the existing posture more accurately — they do not alter it.
- **Delta bug review:** no code changed → no new code paths. Doc-consistency
  risks introduced: the README/SECURITY/site now reference `SECURITY_FINDINGS.md`
  and the two-class model — verified the file exists and the cross-links resolve.
  Pre-existing inconsistencies surfaced (not introduced): signing status
  (site/backlog vs README), 4-vs-5 agent count (README "four" vs site "5") —
  both flagged for Bret, neither fixed to avoid a positioning call.
- **Scratch key:** none used this session.
