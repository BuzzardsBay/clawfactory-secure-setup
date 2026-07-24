# Ship-B — v1.1.1 product batch close-out

*2026-07-22 (session date; the CC prompt is dated 2026-07-21). Repo (write):
`ClawFactory-Secure-Setup`. Model: Sonnet. NO cloud VMs — the confirmatory run is
Ship-C (cfv-153), authored in a fresh session after this close-out. NO writes to
`ClawFactory-Studio` or `clawfactory-site` (one writer per repo). Dispatch card #164
("Ship-B — v1.1.1 product batch") created in_progress, commented with the session
plan.*

Batches two product-file changes that were deliberately deferred out of v1.1.0
(tagged `487e930`) into one version bump: the PolyForm Perimeter license swap (MIT
currently permits anyone, including a competitor, to resell this installer for free)
and the approved orchestrator-prompt reword (correcting a false "enforced by
gateway" claim surfaced but not applied in the v1.0.48 session). One rebuild, one
signing, one confirmatory run.

---

## Comprehension gate (answered before editing)

1. **Why the license swap matters commercially/legally:** MIT permits anyone to take
   the installer source and resell it, including a rebrand, with no obligation back
   to the project. PolyForm Perimeter 1.0.0 keeps every practical use (personal,
   academic, internal audit/fork) but blocks providing a competing product built on
   the software — closing the free-resale gap before the product is sold.
2. **SOUL hash-pin risk:** traced in `setup.ps1` `Step-ApplySafetyRules`
   (`setup.ps1:2304-2351`) — the SOUL hash is **not** a static value committed
   anywhere in the repo. It is computed fresh at *install time* via `Get-FileHash`
   against the shipped `resources/safety-rules.md`, then written to both
   `~/.openclaw/SOUL.md.sha256` (root-owned, in-VM) and the launch-gate pin
   `/etc/clawfactory/soul.sha256`. A mismatch makes `Test-SoulIntegrity`
   (`resources/clawfactory-grants.ps1`) refuse every gated turn — fail closed, never
   silently insecure. This session's Task 2 target, `resources/orchestrator-prompt.md`,
   is a different file that does not feed that hash. Verified by grepping the diff
   for `SOUL`/`sha256` (see §4 below) — zero hits outside the file's pre-existing,
   untouched SOUL.md references.
3. **Why the Studio artifact is re-embedded, not rebuilt:** it lives in a separate
   repo this session has no write access to, and was already built, signed, and
   validated end-to-end (cfv-151/cfv-152). Rebuilding here would produce different
   bytes than what was validated, silently invalidating that proof.
4. **Why no tag this session:** v1.1.1's only proof is Ship-C (cfv-153), which runs
   after this close-out. Tagging now would assert validation that hasn't happened.
5. **If the approved wording couldn't be found:** stop and report rather than write
   new security language. Not triggered — located and quoted verbatim below.

---

## Session preamble

- `git log --oneline -5` / `git tag --list 'v1.*'` / `git status --short`: v1.1.0
  tag present at `487e930a1f30717260f337a7f30b88d74d5ca203` (confirmed via
  `git rev-parse`), three site-migration/content-pass commits on top, working tree
  **clean** at session start.
- Read `docs/session_reports/2026-07-21_job3b_combined_installer_closeout.md`
  (build/sign procedure, `.iss` structure, the Studio-artifact pin) and
  `docs/session_reports/2026-07-21_site_migration_closeout.md` (current repo/site
  state — confirms `docs/` in this repo is no longer the published site source).
- Dispatch card #164 created (`ensure ... --status in_progress`) and commented with
  the plan (`dispatch_card.py` lives in `FrontierAI/scripts/`, not this repo —
  confirmed via `--help` since the tool takes a card **title**, not a numeric id, for
  `comment`).

---

## TASK 1 — PolyForm license swap end-to-end (chip `task_0c26e512`)

`grep -rn '\bMIT\b'` across the full repo, classified every hit:

| File : line | Verdict | Action |
|---|---|---|
| `LICENSE:1` | live claim | **Replaced** — full PolyForm Perimeter 1.0.0 text |
| `README.md:3` (badge) | live claim | **Replaced** — PolyForm Perimeter badge |
| `README.md:132` (License section) | live claim | **Replaced** |
| `CONTRIBUTING.md:3` | live claim | **Replaced** |
| `CONTRIBUTING.md:42` | live claim | **Replaced** |
| `SUPPORT_MATRIX.md:81-82` (Q5 FAQ) | live claim | **Replaced** |
| `PERSONAS.md:64` | live claim | **Replaced** |
| `PERSONAS.md:85` | live claim | **Replaced** |
| `PERSONAS.md:116` | live claim (contained an overclaim — see note) | **Replaced + softened** |
| `PERSONAS.md:127` | live claim | **Replaced** |
| `docs/index.html:1000` (footer) | live claim (unpublished — `docs/` is no longer the site source per the 2026-07-21 migration) | **Replaced** for repo consistency, matching the wording the live public site (`clawfactory-site` repo) already shipped in the 2026-07-22 content pass |
| `docs\session_reports\2026-07-21_ship_a_site_pass_closeout.md` (4 hits) | historical record | left |
| `docs\session_reports\2026-07-22_site_content_pass_closeout.md` (3 hits) | historical record | left |
| `docs\session_reports\2026-07-21_site_migration_closeout.md` (1 hit) | historical record | left |
| `docs\session_reports\DOOR2_CLOSURE_2026-07-18.md` (1 hit) | historical record | left |
| `docs\session_reports\DOOR2_RECONCILE_2026-07-19.md` (1 hit) | historical record | left |
| `docs\session_reports\RELEASE_v1047_2026-07-19.md` (1 hit) | historical record | left |
| `signing\tools\Microsoft.ArtifactSigning.Client\LICENSE.md` | third-party (NuGet-fetched, gitignored) | left |

**PERSONAS.md:116 overclaim note:** the original text paired "MIT license" with
"(no procurement)" — implying the license type removes procurement objections.
PolyForm Perimeter is source-available, not OSI-approved open source, so some
procurement processes that specifically require an OSI license *would* still
object. Rather than carry that overclaim forward under the new license name, the
clause was reworded to "source-available (PolyForm Perimeter) license so their team
can fork and audit internally" — accurate, no new claim invented.

**LICENSE file:** replaced with the verbatim PolyForm Perimeter License 1.0.0 text,
fetched from the official plain-text file linked off `polyformproject.org`. The live
`polyformproject.org/licenses/perimeter/1.0.0` path now 404s (the site's current
default is 1.0.1); the exact 1.0.0 text the task specified was retrieved via the
Wayback Machine's archive of the same official page/file
(`web.archive.org/web/20260419150051/.../PolyForm-Perimeter-1.0.0-1.txt`) — fetched,
not paraphrased or reconstructed from memory. A `Required Notice:` line was added
above the license body (`Required Notice: Copyright Frontier Automation Systems LLC
(https://clawfactory.app)`) using the license's own documented attribution
mechanism (see its "Notices" section, which specifies exactly this convention and
gives the same example format).

Post-edit verification — `grep -rn '\bMIT\b'` again: **6 hits remain, all in
`docs/session_reports/*.md`** (historical close-outs). Zero live claims.

---

## TASK 2 — Orchestrator reword + SOUL integrity

**Diagnosis:** the orchestrator prompt is a single file,
`resources/orchestrator-prompt.md`, staged into
`~/.openclaw/agents/orchestrator/agent.md` by `resources/bootstrap.ps1`. It is
**not** SOUL.md and does not pin or feed any SOUL hash. The only file that feeds the
SOUL hash is `resources/safety-rules.md`, hashed live at install time by
`Step-ApplySafetyRules` (`setup.ps1:2304-2351`) via `Get-FileHash`, written to
`~/.openclaw/SOUL.md.sha256` and `/etc/clawfactory/soul.sha256`. Neither file was
touched this session (`git diff -- resources/safety-rules.md setup.ps1` → 0 lines,
confirmed after the edit).

**Pre-existing gap noted, not fixed (out of scope):** `bootstrap.ps1`,
`smoke-test.ps1`, `CLAUDE_ClawFactory.md`, `SUPPORT_MATRIX.md`, and `README.md` all
describe/check for a `{{SOUL_SHA256}}` placeholder token being substituted into the
orchestrator prompt. `resources/orchestrator-prompt.md` does not and never did
contain that literal token (grepped directly — zero matches before this session's
edit). The smoke check `grep -q "{{SOUL_SHA256}}" ... && echo BAD || echo OK`
therefore currently passes *vacuously* (the placeholder was never present to
substitute), not because substitution succeeded. This is a documentation/code
mismatch that predates this session and is a design question, not a copy/license/
version item — flagged in Recommendations, not touched (Untouchables: "the security
architecture — this is a copy/license/version batch, not a design change").

**Approved wording — source and verbatim quote.** Located in
`docs/session_reports/2026-07-19_version_pin_tool_policy.md:83-91` ("Proposed
replacement wording (for Bret to approve — not applied this job)"), written after
the v1.0.48 session found the prior "Tool allowlist/denylist (enforced by gateway)"
section false: most of the listed names (`github`, `clawhub`, `fs.readLimited`,
`shell`, `net.fetch`, `system.run`) are not real OpenClaw tool names, so a
`tools.deny` of them would be a no-op even if configured.

Verbatim as proposed:
> **## Tools**
> - `exec` (shell) **is available** — you use it to do real work. It is **not**
>   removed. Destructive commands (`rm`, `sudo`, out-of-workspace writes) require
>   the user's explicit "GO" (a behavioral rule, not a code gate).
> - The **`browser` tool is structurally denied** (`tools.deny`, enforced by the
>   gateway) — you do not have it.
> - Network reach is bounded by the **nftables egress allowlist** (a structural OS
>   control), not by a tool policy: you can only reach approved hosts over HTTPS
>   regardless of which tool you use.

Applied verbatim to `resources/orchestrator-prompt.md`, replacing the old "Tool
allowlist" / "Tool denylist" sections. One consistency fix beyond the reword itself:
the preceding "GO gating" bullet list referenced "any tool not on the allowlist
below" — a dangling pointer once the enumerated allowlist was replaced by prose.
Changed to "any tool use outside what 'Tools' below describes as available." No new
claim; a mechanical cross-reference fix so the file stays internally consistent.

**SOUL pin verification.** No pinned file changed this session, so there is nothing
to recompute or re-pin:
- `resources/safety-rules.md` — 0-line diff (confirmed above) → the value
  `Step-ApplySafetyRules` computes at the next install is unchanged from before this
  session.
- `resources/orchestrator-prompt.md` — diff touches only the Tools section and the
  one cross-reference line; `git diff` shows zero occurrences of `SOUL` or `sha256`
  in the changed hunks.
- No pin site (`~/.openclaw/SOUL.md.sha256`, `/etc/clawfactory/soul.sha256`, or the
  `{{SOUL_SHA256}}` substitution in `bootstrap.ps1`) reads from
  `orchestrator-prompt.md`'s content, so none needed updating.

**Local smoke test:** not applicable/not run. Per standing rule, ClawFactory
validation never touches Bret's local desktop, and there is no running sandbox in
this session to test against regardless. Since no pinned file changed, there is no
integrity-check behavior to exercise locally. cfv-153's `T1.2a-f` and `T4.5` cells
remain the authoritative proof of SOUL integrity end-to-end, as always.

**Site-copy contradiction check (Task 2.4):** fetched `clawfactory.app` and searched
for any browser/shell/exec/tool-allowlist claims. None found — the only related
statement is filesystem-isolation copy ("Almost nothing outside its own sandbox...
your Windows filesystem... is invisible to it"), which the reword does not
contradict. Nothing to flag for the site pass from this task.

---

## TASK 3 — Version, build, sign

**Pre-build artifact verification (Studio, must match before touching the build):**
```
resources\ClawFactory-Studio-Setup-1.1.0.exe
size:   100,022,000 bytes                                                 MATCH
sha256: D5FF8370943194C2643674DDBA98E917CA61865CE127EC424A1CB37C746D45A7   MATCH
sig:    Valid   CN=Bret Mckinney
```
Matched the 3B pin exactly — proceeded.

**Version bump.** `ClawFactory-Secure-Setup.iss`: `#define MyAppVersion "1.1.0"` →
`"1.1.1"` (the only literal changed — `git diff` on the `.iss` is a single line).
Searched the rest of the repo for other `1.1.0`-as-current-version assertions
(`validation/*.ps1`, `.gitignore`, `.gitattributes`, `resources/uninstall.ps1`): all
remaining hits are dated `(v1.1.0, JOB 3B)`-style historical annotations describing
*when* that code was added, or the validation harness's intentional pin to the
already-validated v1.1.0 artifact (explicitly listed as an Untouchable — Ship-C
updates that pin in its own session) — none are live version declarations that
needed to move. `.gitignore`'s Studio pattern (`resources/ClawFactory-Studio-Setup-*.exe`)
is already a wildcard; no edit needed. `setup.ps1`'s internal `$InstallerVersion`
constant is a separate, pre-existing, unused (grepped — referenced nowhere else in
the codebase) drift already at `1.0.34`, already flagged as an open item in the
2026-07-21 Ship-A site-pass close-out — left alone as out of scope for this batch
(not a `1.1.0`→`1.1.1` case; a longer-standing drift).

**Build.** `ISCC.exe ClawFactory-Secure-Setup.iss` → `Successful compile (53.546 sec)`.
Embedded the same verified `ClawFactory-Studio-Setup-1.1.0.exe` (see file list in
the compiler log — one `[Files]` entry, unchanged since 3B).

**Sign.** `scripts\sign_installer.ps1 -InstallerPath Output\ClawFactory-Secure-Setup.exe`
→ Azure Artifact Signing, `Signing completed with status 'Succeeded'`, 0 errors, 0
warnings. One expected Azure signing call.

**Output verification:**
```
name:    ClawFactory-Secure-Setup.exe  (Output\)
size:    440,525,520 bytes
sha256:  67619DF79179DB11E76454E9734DE244A51128B37C55F66071213C98F72719A9
sig:     Valid
subject: CN=Bret Mckinney, O=Bret Mckinney, L=West Valley City, S=ut, C=US
issuer:  CN=Microsoft ID Verified CS EOC CA 04, O=Microsoft Corporation, C=US
valid:   NotBefore 2026-07-23 12:51:50Z  NotAfter 2026-07-26 12:51:50Z (3-day Azure leaf, rotates)
RFC3161 timestamp: PRESENT — TimeStamperCertificate = CN=Microsoft Public RSA Time
         Stamping Authority, thumbprint 9D64791BDBA7AB705D8EEB6BC275951F512BC45C
ProductVersion (file metadata): 1.1.1  (confirmed via Get-Item .VersionInfo)
```
The RFC3161 timestamp is present, so the signature stays `Valid` past the 3-day
leaf's `NotAfter` — the leaf rotates roughly every 3 days but the timestamp pins the
signing time inside the leaf's validity window at the moment of signing, which is
what Authenticode checks.

---

## TASK 4 — CHANGELOG entry

Added a `## [1.1.1] - 2026-07-22` entry to `CHANGELOG.md` (existing file, so no new
file needed) documenting the license swap, the orchestrator-prompt correction
(with its "no behavior change, accuracy fix" framing since the orchestrator agent
isn't invoked in normal operation), and the version bump / unchanged-Studio note.

---

## END-OF-SESSION GATE

### 1. Task accounting
Comprehension gate — DONE. Session preamble — DONE (repo clean, close-outs read,
card #164 created + commented). Task 1 (PolyForm end-to-end) — DONE-with-evidence
(classification table above, LICENSE replaced with fetched-verbatim text, zero live
MIT claims remain). Task 2 (orchestrator reword + SOUL integrity) — DONE-with-evidence
(verbatim wording applied, SOUL chain confirmed untouched via 0-diff on the two
files that could affect it, pre-existing `{{SOUL_SHA256}}` gap noted not fixed, site
contradiction check clean). Task 3 (version/build/sign) — DONE-with-evidence (Studio
pin re-verified before build, `.iss` version bump is the only literal touched,
compile + sign succeeded, output hash/sig/timestamp recorded above). Task 4
(CHANGELOG) — DONE. No silent drops.

### 2. Resource ledger
**Zero cloud VMs.** One expected Azure Artifact Signing call (signed the new
combined installer, Succeeded). Local artifacts (gitignored, not committed):
`Output\ClawFactory-Secure-Setup.exe` (440,525,520 bytes, signed — the Ship-C pin);
`resources\ClawFactory-Studio-Setup-1.1.0.exe` (staged, unchanged, re-verified
against the JOB-3B hash). No new Azure resources created or deleted.

### 3. Delta security sweep
`git diff` scanned for credential-shaped strings (`sk-ant`, `sk-proj`,
`AZURE_SIGNING_CLIENT_SECRET`, password/API-key patterns, PEM headers) — **zero
hits**. No security control was weakened: the license swap is a legal/copy change
with no code path affected; the orchestrator-prompt reword is a **truth correction**
(an unenforced claim → an accurate description of the same, already-shipped
enforcement — `browser` denial and the egress firewall are unchanged code, only the
prompt's description of them changed) and does not strengthen any claim beyond the
wording proposed and reasoned through in the 2026-07-19 session. SOUL pin state is
internally consistent: `resources/safety-rules.md` and `setup.ps1` both 0-diff, so
`Step-ApplySafetyRules`'s live hash computation is unaffected; no static hash
constant exists anywhere in the repo to go stale.

### 4. Delta bug review
Re-read the full diff (9 files, `+161/-40`). Functional change: the orchestrator
prompt's Tools section wording, plus the one dangling cross-reference fix it
required. Everything else is license/version/changelog text: `LICENSE` (full
replace), `README.md`/`CONTRIBUTING.md`/`SUPPORT_MATRIX.md`/`PERSONAS.md`/
`docs/index.html` (MIT→PolyForm Perimeter references), `ClawFactory-Secure-Setup.iss`
(one version line), `CHANGELOG.md` (new entry). No `.ps1`/`.sh`/`.js` logic, no
`[Code]` section in the `.iss`, no `validation/` file, and no `resources/safety-rules.md`
or `setup.ps1` byte was touched — verified via `git diff --stat` and targeted 0-diff
checks above.

---

## RECOMMENDATIONS

1. **`{{SOUL_SHA256}}` placeholder gap.** `resources/orchestrator-prompt.md` has
   never contained the `{{SOUL_SHA256}}` token that `bootstrap.ps1`,
   `smoke-test.ps1`, `CLAUDE_ClawFactory.md`, `SUPPORT_MATRIX.md`, and `README.md`
   all describe/check for. The smoke check currently PASSes vacuously. Worth a
   design decision in a future session: either re-add the placeholder to the prompt
   (so the substitution and its integrity story are real) or update the five
   describing/checking files to match the current prompt's prose-based description.
   Not touched here — out of scope for a copy/license/version batch.
2. **`setup.ps1`'s `$InstallerVersion` constant is stale at `1.0.34`**, unreferenced
   anywhere else in the codebase (dead write-only variable), already flagged in the
   2026-07-21 Ship-A site-pass close-out. Separate small cleanup item, not part of
   this batch's `1.1.0`→`1.1.1` scope.
3. **Site-copy contradiction check (Task 2.4): none found.** `clawfactory.app` makes
   no browser/shell/exec/tool-allowlist claims, so the orchestrator reword does not
   contradict live site copy. Nothing to carry into a future site pass from this
   task.
4. **PolyForm Perimeter 1.0.0 vs 1.0.1.** `polyformproject.org` now serves 1.0.1 as
   its current version; 1.0.0 (what this task specified) had to be retrieved via the
   Wayback Machine since the live path 404s. If a future session wants to move to
   1.0.1, that is a deliberate version decision for Bret, not something inferred
   here — 1.0.0 was applied exactly as specified.

---

## Pin for Ship-C — READ THIS FIRST

```
ClawFactory-Secure-Setup.exe
sha256: 67619DF79179DB11E76454E9734DE244A51128B37C55F66071213C98F72719A9
size:   440,525,520 bytes
sig:    Valid (CN=Bret Mckinney, RFC3161-timestamped, timestamper
        thumbprint 9D64791BDBA7AB705D8EEB6BC275951F512BC45C)
ProductVersion: 1.1.1
```

Ship-C (cfv-153) should re-verify this hash **and** the signature against the local
`Output\ClawFactory-Secure-Setup.exe` before staging it (a rebuild would change the
bytes — the pin catches it), update `validation\job3-validate.ps1`'s
`$CombinedBlob`/`$CombinedSha256` constants to match, and run a fresh clean-box
validation. **No tag is applied this session** — v1.1.1 is tagged only after Ship-C
grades clean, per the standing rule.

Final HEAD after this session's commit: see the commit this file ships in
(`git log -1 --format=%H` on `main` immediately after push).
