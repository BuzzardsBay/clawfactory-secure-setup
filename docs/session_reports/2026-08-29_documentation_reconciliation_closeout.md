# Close-out: documentation reconciliation, 2026-08-29

**Working root:** `C:\Users\bmcki\ClawFactory-Secure-Setup`, confirmed by
`git rev-parse --show-toplevel`. Branch `main`, starting at `2d46f9a`.

**Scope held.** No shipped bytes. No build, no release, no tag, no version bump. No change
to `BuzzardsBay/clawfactory-site`. No repository settings. Three commits on `main`: the
reconciliation (`1f7f918`), this close-out (`658a6cc`), and the addendum in section 9 that
the end-of-session gate produced after `658a6cc` was already pushed.

**Verdict: the job's premises were mostly right and two were wrong.** Both are reported in
section 1 rather than worked around. Of the seven census items in TASK 1, **three needed a
correction, four were already correct in every live document**, and reporting that is the
result, not a shortfall.

---

## 0. PROMPT 15 preamble, and the clauses deleted from it

The full block from `docs/VALIDATION_PREAMBLE.md` was read at the start of this session.
Deleted for this job, with reasons:

| Deleted clause | Why it provably does not apply |
|---|---|
| **ENVIRONMENT, NOT NEGOTIABLE** (all of it: `Standard_D2s_v4`, `baseline-v2`, one `run-command` at a time, `/var/tmp`, RDP `/32`, `-OutDir`, `az` exit codes, deallocate at handoff) | No VM is provisioned. No Azure resource is created, read for state, or deleted. `az` is not invoked once in this session |
| **HUMAN HANDOFF CARDS** (cards 1 and 2, the admin-password rules, the timed-probe staging rule) | The job has no point at which it needs a human. There is no install, no reboot, no interactive session and no credential to set. A card would have been ceremony |
| **RESOURCE LEDGER** (prior FAIL VMs, disk/NIC/pip/NSG sweep, licence-slot release, unfiltered residual list, validation blobs) | No compute is provisioned and no licence slot is consumed. There is nothing to sweep and nothing to prove absent |
| **MEASUREMENT DISCIPLINE**, the phase-runner half only (`interim-v120-phaselib.ps1`, the PASS/FAIL/VOID/INFO vocabulary, warm-the-agent, calibrate-before-measuring **as a phase requirement**) | There are no phases. **The calibration principle itself was NOT deleted and was applied** — see section 5.3, where it caught a scanner that reported a clean tree without running |
| **VERSION AND BUILD** (`released-versions.tsv` as a gate, the unsigned-digest rule, committing the ledger with the build) | No build. `released-versions.tsv` is **read** in this job as the authority for the unsigned byte count, and is not written |

**Kept and load-bearing:** close-out-is-a-gate; the four pre-flight checks; "if this prompt
is wrong, say so before executing it"; shell and exit-code discipline; "an audit regex is
itself a probe"; credential hygiene; GIT; and all four clauses in *Clauses earned in the
v1.4.4 cycle* — of which **clause 3, the citation clause added in `fa4423f`, governs this
job directly.** Every correction below was made against the tree or against a live API
reading, never against another document.

---

## 1. CHALLENGING THE PROMPT. Two premises were wrong

The brief invited this and it is the job working.

### 1.1 `CLAUDE_ClawFactory.md` is untracked and gitignored. **Its corrections cannot be committed**

TASK 2.4 says *"the operator must re-upload it to his Claude project files, because the
repo copy and the project-files copy are separate objects and only the repo one is being
fixed here."* **There is no repo copy.**

```
$ git check-ignore -v CLAUDE_ClawFactory.md
.gitignore:62:CLAUDE_ClawFactory.md    CLAUDE_ClawFactory.md
```

`.gitignore` says why, in the file itself:

> The operator's private working-context file. Never written to be read by anyone
> else: it carried a plaintext VM admin credential (never used, but committed at
> `CLAUDE_ClawFactory.md:1279` from 2026-05-11), the Azure subscription id, Stripe
> pricing and payout account, and the local paths of four other private projects.
> Untracked in the 2026-08-29 pre-publication sweep. It stays on disk, out of git.

**This repository is now public.** `git add -f CLAUDE_ClawFactory.md` would publish a
plaintext admin credential and a subscription id to a public repository. That is not a
scope judgement, it is the thing the pre-publication sweep existed to prevent.

**What was done instead.** The file was corrected **on disk only**, in full, to the
standard TASK 2 asked for. It is not staged and not pushed. It appears in no
`git status --short` output in section 7 because git cannot see it.

**And while correcting it, two secrets were removed from it** — see section 5.4. That was
not asked for. It was done because this session was editing the section that held them,
the file has been committed to this repository before, and leaving a live credential in a
file being actively edited is worse than the scope stretch.

**The re-upload instruction survives intact and is more important, not less**: the
project-files copy is now the *only* copy carrying the false claims, and nothing in the
repository will ever correct it.

### 1.2 TASK 1.5 asks for a correction that has already been made

> **1.5 The Studio panel count is seven.** Correct every occurrence of six.

**There is no live document asserting six.** Tree-wide census, `*.md`, whole repository:
**6 hits** for "six … panels". Every one is a deliberate record of the error:

| Hit | What it is |
|---|---|
| `docs/FAILURE_CATALOGUE.md:893` | The **Claimed** line of entry 12.2, whose subject is the false six |
| `docs/FAILURE_CATALOGUE.md:902` | That entry quoting the close-out heading that refuted it |
| `docs/session_reports/2026-08-29_v144_release_prep_closeout.md:74` | The section title *"The card names six not-in-this-release panels. There are seven"* |
| `docs/session_reports/2026-08-29_doc_truth_and_clawagent_hazard_closeout.md:366` | *"One correction to the brief. It says six … There [are seven]"* |
| `docs/V1_5_BACKLOG.md:275` | Quoting that section title |
| (the brief itself) | Not in the tree |

**Correcting any of them would destroy the record of the defect.** The brief's own rule —
*"Do not delete a documented decision … because it now looks stale"* — forbids it.

Every **live assertion** already says seven, and they agree:
`docs/RELEASE_NOTES_v1.4.4.md:26`, `docs/RELEASE_v1.4.4_GITHUB_BODY.md:31`,
`Output/v1.4.4-release-body.md:20`, `validation/MANUAL_CHECKS_studio.md` §9,
`docs/V1_5_BACKLOG.md:272`.

**Census result: 6 found, 0 corrected, 0 needing correction, 6 deliberately preserved.**

---

## 2. TASK 0. Inventory

### 2.1 Every markdown document describing system state

**152 tracked `.md` files in the repository.** They split cleanly into records and live
claims, and the distinction decides whether a stale sentence is a defect or a fact:

| Class | Count | Treatment |
|---|---|---|
| `docs/session_reports/**` | 88 | **Records.** Dated, and true as of their date. Not corrected |
| `validation-runs/**` | 14 | **Records.** Per-run reports; the directory is gitignored going forward |
| `docs/cc_jobs/**` | 5 | **Records.** Archived job briefs |
| `REPORT*.md`, `validation/REPORT*.md`, `reports/**` | 12 | **Records.** Per-version validation reports |
| **Live system-state documents** | **33 tracked + 1 untracked = 34** | **In scope** |

The 33 tracked live documents, with the commit and date that last touched each:

| Document | Last commit | Date |
|---|---|---|
| `README.md` | `d564d59` | 2026-08-29 |
| `SUPPORT_MATRIX.md` | `d564d59` | 2026-08-29 |
| `SECURITY_FINDINGS.md` | `4623c45` | 2026-08-29 |
| `docs/V1_5_BACKLOG.md` | `877ee51` | 2026-08-29 |
| `docs/FAILURE_CATALOGUE.md` | `fa4423f` | 2026-08-29 |
| `docs/VALIDATION_PREAMBLE.md` | `fa4423f` | 2026-08-29 |
| `docs/POST_RELEASE_DOC_CORRECTIONS_v1.4.4.md` | `2bdd833` | 2026-08-29 |
| `docs/RELEASE_NOTES_v1.4.4.md` | `9111e9b` | 2026-08-29 |
| `docs/RELEASE_v1.4.4_GITHUB_BODY.md` | `9111e9b` | 2026-08-29 |
| `docs/RELEASE_NOTES_v1.4.3.md` | `8c6c704` | 2026-08-29 |
| `validation/MANUAL_CHECKS_studio.md` | `c51b6c6` | 2026-08-28 |
| `SECURITY.md` | `c2cb37b` | 2026-08-27 |
| `CHANGELOG.md` | `6686d45` | 2026-08-23 |
| `CONTRIBUTING.md` | `6686d45` | 2026-08-23 |
| `PERSONAS.md` | `6686d45` | 2026-08-23 |
| `resources/orchestrator-prompt.md` | `6686d45` | 2026-08-23 |
| `docs/reference/HOSTNAME_WRITE_CENSUS.md` | `2d081bc` | 2026-08-19 |
| `validation/RUNBOOK_v135.md` | `04237f3` | 2026-08-19 |
| `ClawFactory_Install_Lessons_Learned.md` | `f05ee41` | 2026-08-15 |
| `docs/reference/EMAIL_APPROVAL.md` | `950c10a` | 2026-08-13 |
| `resources/persona.md` | `000d4d9` | 2026-08-04 |
| `resources/safety-rules.md` | `cec72f0` | 2026-08-03 |
| `docs/reference/OPENCLAW_VERSION_POLICY.md` | `d76a8b9` | 2026-07-20 |
| `v1.1_backlog.md` | `23f0990` | 2026-07-18 |
| `ClawFactory_Session_Handoff_2026-07-14.md` | (July) | 2026-07 |
| `REPORT.md` | `962a189` | 2026-06-10 |
| `Weekly_Work_Log.md` | `3ed3d1e` | 2026-05-22 |
| `CC_Git_Hygiene_Both_Repos.md` | `aa1f932` | 2026-05-16 |
| `ClawFactory_Session_Handoff_May26.md` | (May) | 2026-05 |
| `resources/context/identity.md`, `me.md`, `people.md`, `priorities.md`, `verify.md` | various | — |

**Plus, untracked:** `CLAUDE_ClawFactory.md`, last *tracked* at `d7e563b` (2026-08-29),
removed from git in the pre-publication sweep the same day.

**A classification note.** The five `resources/context/*.md` files are 42–1278 bytes and
are agent context stubs, not system-state descriptions. They are not bundled
(`grep -c 'resources\context' ClawFactory-Secure-Setup.iss` returns **0**) and nothing in
this job's censuses touched them.

### 2.2 What ships, and therefore what could not be corrected here

**56 `Source:` lines** in the `.iss` `[Files]` section. **Four are markdown:**

| Bundled document | `.iss` line | Start Menu shortcut? |
|---|---|---|
| `README.md` | 46 | **Yes**, `.iss:186` — `{group}\ClawFactory README` |
| `resources/safety-rules.md` | 49 | No |
| `resources/persona.md` | 50 | No |
| `resources/orchestrator-prompt.md` | 51 | No |

**`SECURITY_FINDINGS.md` is NOT bundled**, and a close-out says it is. See section 6.4 —
that record now carries an inline correction rather than a rewrite.

**Corrections routed to `docs/V1_5_BACKLOG.md` because they live in shipped bytes:** see
section 4.

### 2.3 Reconciling against what is there

`docs/V1_5_BACKLOG.md` (278 lines) and `docs/FAILURE_CATALOGUE.md` (1133 lines) were both
read in full before any edit. The catalogue is 59.6 KB and could not be echoed into the
transcript in one piece; its complete heading structure was enumerated and every section
that this job touches — Class 10 in full, Class 12 in full, the instrument-defect record,
and the 19-item practices list — was read verbatim. That is stated rather than implied,
because "I printed it" and "I read it" are different claims.

---

## 3. TASK 1. The seven censuses

Each was run tree-wide before any file was edited. Counts are **hits found / corrected /
already correct**.

### 3.1 The repository is public — **18 / 0 / 18**

**Verified, not assumed:**

```
$ gh api repos/BuzzardsBay/clawfactory-secure-setup
{"private": false, "visibility": "public", "has_pages": false,
 "pushed_at": "2026-08-29T20:33:42Z"}
```

18 hits for private/publication language across `*.md`. **Zero required correction.** They
divide into:

- **Records** — `ClawFactory_Session_Handoff_May26.md:5,168` ("Repo is private"),
  `docs/session_reports/2026-07-21_site_migration_closeout.md:101`,
  `.../2026-08-23_free_release_prep_closeout.md:267`,
  `.../2026-08-27_v143_runner_closeout.md:162`,
  `.../2026-08-29_prepublication_sweep_closeout.md:706,718`. All dated, all true when
  written. Correcting a record is falsifying it.
- **Still true** — every reference to a *different* repository being private:
  `CC_Git_Hygiene_Both_Repos.md:26` and `CLAUDE_ClawFactory.md:1204` (ClawChat),
  `docs/session_reports/2026-08-13_v1_2_0_handoff.md:118` (Studio). Confirmed by
  `gh repo list BuzzardsBay`: `clawchat` PRIVATE, `ClawFactory-Studio` PRIVATE.
- **Not about visibility at all** — "private gateway port", "private input channel",
  "private, sourced web research". Excluded on reading, not on pattern.

**One live sentence was corrected as a consequence** rather than as a hit:
`docs/FAILURE_CATALOGUE.md` said *"The product is being published now."* It is published.
See 3.8.

### 3.2 The ClawAgent assets are deleted, not warned — **0 / 0 / n-a**

**Zero live documents describe the superseded plan.** The census searched for
"prepend a warning", "keep them downloadable", "remain downloadable", "warning banner" and
`clawagent` across all `*.md`. Every ClawAgent hit outside the session reports is either
about the *repository* (correct: archived, public) or about the FAQ prose on the site
(correct: superseded and unmaintained).

**Verified:**

```
$ gh api repos/BuzzardsBay/clawagent-setup
{"archived": true, "private": false}
$ gh api repos/BuzzardsBay/clawagent-setup/releases
v1.0.4  assets: []
v1.0.3  assets: []
v1.0.2  assets: []
v1.0.0  assets: []
```

Four releases, four empty asset lists, warnings intact in the bodies.

**The reversal is now recorded as a live fact**, not only inside a dated close-out. It went
into `CLAUDE_ClawFactory.md` §20.5 (the distribution section, where a future session looks
up "where do the releases live") and, as a transferable rule, into
`docs/VALIDATION_PREAMBLE.md` as **clause 4**.

**The reversal and its reason, stated as the brief asked:** the original instruction was to
prepend a warning and **keep the four installers downloadable so existing links keep
working**. The handoff card enumerated the assets rather than counting them, and the
enumeration carried **`download_count: 0` on all four**. If nothing had ever been fetched,
there were no existing links to preserve, and the only argument for leaving a
knowingly-unsafe installer downloadable evaporated. The operator changed the instruction to
warning **and** delete. All four binaries were downloaded and size-checked against the API
first, to `C:\Users\bmcki\ClawAgent-asset-archive-2026-08-29\`, so the deletion is
reversible. **The old decision was not overwritten**: it is stated, and then the
measurement that overturned it is stated beside it.

The download counts are quoted from
`docs/session_reports/2026-08-29_doc_truth_and_clawagent_hazard_closeout.md` §6.1, lines
420–423, and **cannot be re-derived today** — the assets are gone, and with them the
counters. That limitation is stated rather than hidden.

### 3.3 `docs/index.html` and `docs/CNAME` no longer exist — **1 / 1 / 0**

Both deleted in `8747dc0`. Confirmed absent from the working tree.

**Verified by API, and this is the citation the brief asked for:**

```
$ gh api repos/BuzzardsBay/clawfactory-site/pages
{"cname": "clawfactory.app",
 "source": {"branch": "main", "path": "/"},
 "status": "built",
 "html_url": "https://clawfactory.app/"}

$ gh api repos/BuzzardsBay/clawfactory-secure-setup/pages
HTTP 404  {"message": "Not Found"}
```

And the deployed bytes were compared, not assumed:

| | Bytes | SHA-256 |
|---|---|---|
| `https://clawfactory.app/` | 45,430 | `214db95ad1741fbd8d98d181f96d2863e5256ab00fdfa1e94ddfac6ee6168a76` |
| `BuzzardsBay/clawfactory-site@main:/index.html` | 45,430 | `214db95ad1741fbd8d98d181f96d2863e5256ab00fdfa1e94ddfac6ee6168a76` |

**Byte-identical.** This is clause 3's second paragraph applied: the artefact was
identified before it was cited.

**One live hit, corrected:** `CLAUDE_ClawFactory.md` §20.1. See 3.9.

`CHANGELOG.md:99` refers to *"the unpublished `docs/index.html`"* — **correct as written**,
and correct as a record of what `[1.4.0]` changed. Left alone.

### 3.4 The site download links point at the installer file — **1 / 1 / 0**

Read from the live page, not from a local copy. Seven GitHub links:

```
749  nav          .../releases/latest/download/ClawFactory-Secure-Setup.exe   "Download"
760  hero         .../releases/latest/download/ClawFactory-Secure-Setup.exe   "Download for Windows"
852  step 01      .../releases/latest/download/ClawFactory-Secure-Setup.exe   "Get ClawFactory-Secure-Setup.exe"
748  nav          .../releases/latest                                          "Release notes and SHA-256"
762  hero         .../releases/latest                                          "Release notes and SHA-256"
853  step 01      .../releases/latest                                          "Release notes and SHA-256"
1066 footer       github.com/BuzzardsBay/clawfactory-site                       "GitHub ->"
```

**Three download buttons, all at the file; three release-page links beside them.** The
download URL was exercised: `HEAD` → **200**, `Content-Length: 440610608`, matching the
published signed asset exactly.

**The filename coupling, and where it was recorded.** `/releases/latest/download/<name>`
resolves by **filename**. A release that attaches its asset under any other name 404s all
three buttons, silently: the filename lives in a different repository and nothing in this
repository's build reads it.

**Recommendation, and it was acted on:** `docs/V1_5_BACKLOG.md`, as **item 6, explicitly
labelled a standing release obligation rather than a v1.5 work item.** That page is the one
a person cutting the next release opens, and it already carries the release-shaped material
(the ledger rows, the two byte counts, the version literals). The alternative — a line in
`README.md` — was rejected: `README.md` is bundled, so adding to it changes shipped bytes,
which this job may not do, and a customer-facing file is the wrong home for an internal
release checklist. The matching **post-release assertion** is specified separately as item
4b, because it is an HTTP reading and not a tree derivation.

### 3.5 The Studio panel count — **6 / 0 / 6.** See section 1.2

### 3.6 Card `#311` — filed as a deletion, with the measurement question routed separately

**The shortcut, verbatim from `ClawFactory-Secure-Setup.iss` `[Icons]`:**

```
Name: "{group}\ClawFactory Dashboard"; \
  Filename: "{sys}\cmd.exe"; \
  Parameters: "/c start http://127.0.0.1:8787"; \
  WorkingDir: "{app}"; \
  Comment: "Open ClawFactory dashboard in browser (gateway must be running)"
```

Device-pairing gated (`SUPPORT_MATRIX.md:26`, grounded in the gateway's Ed25519
device-identity connect), with no pairing flow shipped and no explanation of one. A
one-click Start Menu dead end under a label promising a dashboard.

**Filed as `docs/V1_5_BACKLOG.md` item 5, as a DELETION and not a fix**, with the reasoning
recorded: shipping a pairing flow is a feature, for a surface nobody has asked for and
nobody has measured; removing five `[Icons]` lines costs nothing and leaves the dashboard
reachable by anyone who types the URL.

**The open measurement question went somewhere else, deliberately.** It is in
`docs/VALIDATION_PREAMBLE.md`, in a new section *"Open measurements owed by the next
validation cycle"*, as **OM-1** — **outside the paste block**, so it is not pasted into
every job but is in the file every validation job opens. A v1.5 *planning* page is read by
planning; a validation cycle reads the preamble. The entry specifies the suspension of
hazard rule #5 as an explicit, recorded, one-time act; requires the box be torn down
anyway; requires a `/status` control **before and after** the click, from a non-browser
path, because otherwise a wedge and a clean result look identical in the transcript; and
states plainly that the measurement does **not** decide whether the shortcut should ship.

### 3.7 Both installer byte counts — **3 corrected / 4 flagged / rest correct**

**Derived, not copied from the brief:**

| Artifact | Bytes | Source, executed |
|---|---|---|
| **Signed, published** | **440,610,608** | `.assets[0].size` from the releases API; equal to `(Get-Item Output\ClawFactory-Secure-Setup.exe).Length`; equal to the live `Content-Length` on the site's download URL |
| **Unsigned, ledger** | **440,594,967** | Size column, last row of `released-versions.tsv` (v1.4.4, 2026-08-27, digest `548562c7…`) |

Three independent readings agree on the signed number, and they are genuinely independent:
a GitHub API field, a local filesystem stat, and an HTTP header from a CDN.

**Documents asserting a size without saying which artifact — the full census:**

| Location | Assertion | Disposition |
|---|---|---|
| `docs/POST_RELEASE_DOC_CORRECTIONS_v1.4.4.md:31` | `Size \| 440594967 bytes` under a heading reading "Released artifact" | **CORRECTED.** Rows relabelled `(unsigned)`; the signed pair added. The numbers were self-consistent; the *label* was ambiguous, and "released" most naturally reads as the published, signed file |
| `docs/RELEASE_NOTES_v1.4.4.md:70` | "It is about 440 MB" | **CORRECTED** to name 440,610,608 as the signed download, with both counts and the 15,641-byte explanation |
| `README.md:49` | "(~440 MB…)" | **NOT CORRECTED — BUNDLED.** Routed to the v1.5 backlog, where item 4 already names this exact sentence as the coincidence that hides the ambiguity |
| `docs/RELEASE_v1.4.4_GITHUB_BODY.md:29` and `Output/v1.4.4-release-body.md:18` | "before you download 440 MB" | **NOT CORRECTED — FLAGGED.** These are the body of the published GitHub release. Editing the repo copy would create a divergence from what is live on GitHub, which is the defect class `docs/POST_RELEASE_DOC_CORRECTIONS_v1.4.4.md` exists to prevent |
| `docs/RELEASE_NOTES_v1.4.3.md:62` | "about 440 MB" | **NOT CORRECTED — RECORD.** v1.4.3 was superseded before publication and the file says so in its own header |

`docs/RELEASE_NOTES_v1.4.4.md:14` and `:561` already name the signed artifact by digest and
were confirmed correct, not changed.

### 3.8 Corrections made in committed files

| File | Old, verbatim | New |
|---|---|---|
| `docs/FAILURE_CATALOGUE.md` | "**No user-reported issues appear here**, because there have not been any. The product is being published now." | "…The product **was published on 2026-08-29**: this repository is public, and `v1.4.4` is its first GitHub Release. Anything reported from here on is a user report and belongs in a different document from this one." |
| `docs/VALIDATION_PREAMBLE.md` | "The **three** clauses below are not part of the PROMPT 15 text…" / "The third is new and is recorded together with…" | "The **four** clauses below…" / "…**The fourth was added on 2026-08-29 by the documentation reconciliation** and is the only one that governs the handoff card rather than a measurement or a sentence." |
| `docs/POST_RELEASE_DOC_CORRECTIONS_v1.4.4.md` | `\| SHA-256 \| 548562c7… \|` and `\| Size \| 440594967 bytes \|` | Both relabelled `(**unsigned**)`; two rows added for the signed, published artifact; a note explaining that the rows were consistent and the label was not |
| `docs/RELEASE_NOTES_v1.4.4.md:70` | "Download the installer from the Releases page. It is about 440 MB, because…" | "…**The signed file you download is 440,610,608 bytes** — about 440 MB — because… (Two byte counts for this release are in circulation and both are correct, of different artifacts…)" |
| `docs/session_reports/2026-08-27_v144_wrapper_fixes_closeout.md:829` | `\| SECURITY_FINDINGS.md, README.md \| **Yes** — both are in [Files] \|` | **Row left standing**; a `CORRECTION, 2026-08-29` row added beneath it naming the four files that actually ship. See 6.4 |

### 3.9 Corrections made in `CLAUDE_ClawFactory.md` (disk only, not committed)

See section 5.

---

## 4. Corrections routed to `docs/V1_5_BACKLOG.md` because they live in shipped bytes

| Correction | Why it cannot be made here | Backlog home |
|---|---|---|
| `README.md:49` "~440 MB" does not say which artifact | `README.md` is `.iss:46` and carries the shortcut at `.iss:186`. Editing it changes shipped bytes at the next build | Item 4, already named there |
| `README.md:3` version badge, `README.md:129` gate count, the smoke-check list | Same | Item 2 |
| `resources/launcher.ps1:14-20`, a seven-line header with four false assertions | A shipped `.ps1` | Item 2 |
| The mojibake in five shipped `.ps1` | Shipped `.ps1` | Item 1 |
| **NEW: delete the `ClawFactory Dashboard` `[Icons]` entry** | `[Icons]` is shipped bytes | **Item 5** |
| **NEW: the asset filename is load-bearing for the site's three download buttons** | Not shipped bytes, but a release-time obligation with no gate | **Item 6** |

---

## 5. TASK 2. `CLAUDE_ClawFactory.md`

**Read in full**, 1314 lines, in six byte-bounded passes. **1314 lines before, 1564 after.**

### 5.1 Claims the tree does not support, with the tree evidence

| # | Claim | Tree evidence | Disposition |
|---|---|---|---|
| 1 | Header: "SHIP STATUS: v1.0.21 / v1.0.4 — STABLE" | `#define MyAppVersion "1.4.4"` at `.iss:9`; the releases API shows `v1.4.4` published 2026-08-29 | Marked **HISTORICAL / SUPERSEDED**, paragraph retained |
| 2 | "Current heads: … + ClawAgent v1.0.4" | `clawagent-setup` is `archived: true` with four asset-less releases | Same |
| 3 | Current-state table: ClawFactory **$149**, ClawAgent **$49** | `CHANGELOG.md` `[1.4.0]`: licence checking removed in full, no outbound licence call, Apache-2.0 | Marked stale **including every price**; rows retained |
| 4 | Roadmap: ClawFactory "$149 LIVE", ClawAgent "$49 LIVE — clawfactory.app" | As above; and the live site mentions ClawAgent only as FAQ prose stating it is superseded | Prices struck, status cells corrected. **The ten roadmap rows below were NOT deleted** — they are product intent |
| 5 | Active issues **M4**: `switch-provider.ps1` writes `~/skills-factory/openclaw.json` via `python3` | `grep 'skills-factory' resources/switch-provider.ps1` → **no match**. Line 354: *"Update openclaw.json via openclaw CLI (no python3, no direct JSON edit)"*, over four `openclaw config set` calls | Marked **STALE — CLOSED**, row retained because `v1.1_backlog.md` references the ID |
| 6 | Active issues **M5**: aux hosts not re-added to the allowlist on switch | Five allowlist-host references in the file; provider hosts re-resolved on switch | Marked **STALE — CLOSED** |
| 7 | Active issues **C2**: ClawChat has no settings tab | Contradicted by **this file's own line 3**, which records v1.1 adding a settings tab with provider switching and a security tier selector | Marked **STALE**, with the internal contradiction named |
| 8 | §14.8: "19 checks" with no mention of the opt-in set | `grep -c "Check '"` → **26**; 19 before the `if ($AgentChecks …)` guard at `smoke-test.ps1:317`, 7 at or after | **Corrected**: all three numbers stated, each labelled |
| 9 | **§16 `[Icons]`: desktop icon = `powershell.exe … -WindowStyle Hidden -File launcher.ps1`** | `.iss` `[Icons]`: `{commondesktop}\ClawFactory` → `Filename: {app}\ClawChat.exe`. `grep -c "WindowStyle Hidden"` over the real `.iss` → **0**. `grep -c launcher.ps1` inside the real `[Icons]` → **0** | **Replaced with tree text.** See 5.2 |
| 10 | §16: `#define MyAppVersion "1.0.0"` | `.iss:9` says `1.4.4` | Replaced |
| 11 | §16 `[Files]`: 14 sources | 56 `Source:` lines | Replaced with the markdown/payload subset plus an explicit count and a refusal to reproduce the rest |
| 12 | **§16: an entire `[UninstallRun]` section** | `sed -n '/^\[UninstallRun\]/,/^\[/p'` over the real `.iss` returns **nothing**. There is no such section; since v1.0.34 the uninstaller runs from `CurUninstallStepChanged(usUninstall)` in `[Code]`, and the `.iss` says so in a comment | **Deleted, and replaced by a note recording that it was wrong and since when** |
| 13 | §16 `[Icons]`: seven entries, no `{group}\ClawChat` | Eight entries in the real `[Icons]` | Replaced |
| 14 | §16 Kill Switch comment: "kills all ClawFactory agent containers" | Real comment: "stops the OpenClaw gateway and agent processes" | Replaced |
| 15 | §16 `[Code]` welcome text: "Four agents run in Docker sandbox (network=none, sandbox=all)" | Docker is not the isolation boundary; recorded as a false claim in `docs/FAILURE_CATALOGUE.md` Class 6 | **Banner added** naming it, block retained as a v1.0.0 record |
| 16 | §19: ClawChat "bundled into both installers", "10.88 MB", sha `0bb56c62…`, "Version: 1.0.0" | `resources/ClawChat.exe` is **11,702,272 bytes**, sha256 `596c0825…`. One installer bundles it | Corrected, with the stale figures retained as the correction record |
| 17 | **§20.1: "Source: `docs/index.html` in `clawfactory-secure-setup` repo / Hosted: GitHub Pages"** | `docs/index.html` deleted in `8747dc0`; `has_pages: false`; `/pages` → 404; the site's Pages API names `clawfactory-site` | **Rewritten in full** with the API readings and the byte comparison |
| 18 | §20.1 / §20.5: "Download buttons point at `releases/latest` URLs for both repos" | Three buttons at `/releases/latest/download/ClawFactory-Secure-Setup.exe`; ClawAgent has no assets | Rewritten, with the filename-coupling hazard stated |
| 19 | §20.3: Stripe prices | Free since v1.4.0 | Marked historical |
| 20 | §20.6: baseline image `clawfactory-win11-baseline` | `docs/VALIDATION_PREAMBLE.md`: image is `clawfactory-win11-baseline-v2` | Corrected |
| 21 | §20.6: "VM pattern: **Standard_D2s_v5**" | Preamble: `Standard_D2s_v4`; DSv5 quota in westus2 is **zero** | **Corrected**, with the reason, because this one costs a run |
| 22 | §20.6: a plaintext VM admin password and the Azure subscription id | Not a truth defect — a hygiene defect in a file this public repository has held before | **Both removed.** See 5.4 |

**Not re-verified, and said so in the file rather than left to look current:** §13 (install
execution map), §15 (diagnostic quick reference), §17 (OpenClaw config schema), §18
(reference healthy install state), and §19.1–19.3. These describe a v1.0.x install and were
marked or left with their existing dated framing; asserting they are current would repeat
the defect this job exists to close.

### 5.2 §16 was the origin of `FAILURE_CATALOGUE` entry 12.1

Entry 12.1 records that "the desktop icon launches a chat session in Windows Terminal"
propagated from `CLAUDE_ClawFactory.md` §14.4 into `README.md:53` (bundled, with its own
Start Menu shortcut), into `SUPPORT_MATRIX.md` in seven customer-facing answers, and from
there into a chat argument about a user's first minute. §14.4 was corrected earlier on
2026-08-29.

**§16 was not, and §16 is where the claim was checkable.** It carried the `[Icons]` block
that pointed the desktop icon at `launcher.ps1` under `-WindowStyle Hidden`, and
`docs/V1_5_BACKLOG.md` item 2 cites *"`grep -c "WindowStyle Hidden"` over the entire `.iss`
returns **0**"* as proof that `launcher.ps1`'s own header is false — while the same string
sat, uncorrected, in this file. **The count in this file was 1. It is now 0.**

This is entry 12.3's shape one level down: a session correcting 12.1 could have cited §16,
cited it accurately, and been wrong.

### 5.3 The shortcut ground-truth table is now the first thing in the file

TASK 2.3, done as specified. The new **READ THIS FIRST** block carries: a provenance and
staleness warning; a nine-row "where the product actually is" table with the derivation of
each value; **the eight-entry shortcut table** verbatim from `[Icons]`; the **what a click
gets you** table, with the Dashboard row naming the dead end and pointing at card `#311`;
the ClawChat-vs-Studio distinction; where conversation history lives and that neither
uninstall branch removes it; and the re-upload instruction.

### 5.4 Two secrets removed while correcting §20.6

Not asked for, done anyway, reported rather than buried. §20.6 held a plaintext VM admin
password and the Azure subscription id — the two things `.gitignore:62` names as the reason
the file was untracked. Both are replaced by pointers to the correct procedure. Neither
value appears in this close-out, in the dispatch card, or in the session transcript beyond
the `grep` that confirmed their removal.

### 5.5 Line count, and the re-upload

**1314 → 1564 lines (+250).**

**The operator must re-upload `CLAUDE_ClawFactory.md` to his Claude project files.** The
repository copy and the project-files copy are separate objects. In this case they are more
separate than the brief assumed: the file is gitignored, so **there is no repository copy at
all** and nothing in the repository will ever correct the project-files copy. Until it is
re-uploaded, a chat session reading project files will still read every claim in 5.1 —
including the desktop-icon claim that produced entry 12.1.

---

## 6. TASK 3. The staleness gate, sharpened, specification only

**Nothing was implemented.** `docs/V1_5_BACKLOG.md` item 4 gained a *Sharpening* subsection
and a new item 4b.

### 6.1 Every self-describing number, with its tree source

| # | Number | Value | Derived from |
|---|---|---|---|
| 1 | Build-gate count | **9** | Length of the `gatesPassed` array literal, `scripts/build_release.ps1:691` |
| 2 | Bundled-file count | **56** | `Source:` lines in the `.iss` `[Files]` section |
| 2b | Bundled **markdown** count | **4** | Those `Source:` lines matching `.md` |
| 3 | Smoke checks, default | **19** | `Check '` before the `if ($AgentChecks …)` guard at `smoke-test.ps1:317` |
| 3b | Smoke checks, opt-in | **7** | `Check '` at or after that guard. File total **26** |
| 4 | Unsigned installer size | **440,594,967** | Size column, last row of `released-versions.tsv` |
| 5 | Signed installer size | **440,610,608** | `size` field of the published release asset |
| 6 | Version literal | **1.4.4** | `#define MyAppVersion`, `.iss:9`, cross-checked against the ledger and the `README.md:3` badge (twice on one line) |
| 7 | Studio panels not in this release | **7** of **11** | **Not derivable.** Three-document agreement check — see 6.3 |
| 8 | Mojibake file count | **5** of 10 shipped `.ps1` | Byte scan: no `EF BB BF` prefix **and** a byte outside `09 0A 0D 20-7E` |
| 9 | Mojibake customer-visible occurrences | **7** | Non-ASCII characters on `rename-agent.ps1:21,25,29` and `bootstrap.ps1:128,226` |
| 10 | OpenClaw version pin | **2026.4.27** | The pinned literal in the installer scripts |

### 6.2 Three corrections to the specification that was already there

**(a) The build-gate cross-check as specified FAILS on a correct tree.** The existing spec
required counting `^# --- Pre-build gate:` headers and cross-checking against `gatesPassed`,
"**Both, and they must agree**". Header count **8**; array **9**. Nothing is stale: the
header at `scripts/build_release.ps1:527` reads *"the persona and the COMPOSED workspace
SOUL"* — **one header covering two gates**. A gate built from that spec would have failed
the build on its first run, on a correct tree.

This is Class 10 one level up: a *specification* carrying the defect it audits. The rule
"derive it, never trust the prose" was applied, the derivation was written down, and **the
derivation itself was never run.** Added as practice **22**.

**(b) Number 7 is not derivable and must not pretend to be.** Every other row reads a file
in this repository. The panel count reads three prose documents that agree with each other,
about a repository whose source is elsewhere. Deriving one prose number from another is what
the page's own note calls Class 10. It stays in the census — the number has been asserted
wrongly more than once — but as a labelled agreement check.

**(c) The scanner must not use `grep -P`.** See 6.3.

### 6.3 The instrument defect this job found in its own work

Re-deriving numbers 8 and 9, the obvious pattern — a `grep -cP` with a negated hex character
class under `LC_ALL=C`, inside a loop ending `|| echo 0` — returned **0 for all ten shipped
scripts.** A completely clean tree.

**It was wrong.** `grep -P` on this platform refuses under `LC_ALL=C` —
*"grep: -P supports only unibyte and UTF-8 locales"* — and exits **2**. The `|| echo 0`
turned the refusal into a zero. Ten files, ten zeroes: **a failure to run, presented as a
pass**, on the exact defect class the gate exists to catch. The uniformity is what made it
convincing.

**It was caught by the preamble rule, applied mechanically.** An em dash was planted in a
copy of a clean shipped script and the pattern was required to find it *before* the clean
result was believed. It did not. A byte-value scan then found 3 bytes in the canary and 0 in
the control, and reproduced the published census **exactly**: 10 shipped scripts, 5
affected, same files, same line numbers as `docs/V1_5_BACKLOG.md` item 1 — an independent
re-derivation, not a copy.

Filed as `docs/FAILURE_CATALOGUE.md` **entry 10.6** and practice **21**: *a measuring
program that exits non-zero has not measured anything.*

### 6.4 A missing practice, and a false row in a record

Two things surfaced while reading the catalogue:

- **Practice 20 was missing.** Entry 12.3's *"a citation proves the provenance of a
  sentence, not the provenance of the artefact"* was written into
  `docs/VALIDATION_PREAMBLE.md` when the entry was recorded, and **never added to the
  practices list** — the list that the catalogue itself calls the transferable part. Added,
  with a note saying it was missing.
- **`docs/session_reports/2026-08-27_v144_wrapper_fixes_closeout.md:829`** states
  *"`SECURITY_FINDINGS.md`, `README.md` — **Yes**, both are in `[Files]`"*. **False.** Only
  `README.md` is. This decides whether correcting `SECURITY_FINDINGS.md` costs a release or
  a commit; it costs a commit. **The row was left standing and a `CORRECTION, 2026-08-29`
  row added beneath it.** A record is not rewritten; it is annotated.

### 6.5 The site download-link check, recorded separately as item 4b

As the brief required: **not folded into the staleness gate.** It is an HTTP reading, not a
tree derivation; putting a network call inside a lint lets a transient 502 fail a
documentation check, and it cannot pass before publication because the asset does not exist.
It is specified as the **last step of cutting a release**: `HEAD` the download URL, require
**200** and a `Content-Length` equal to the signed size of the release just published.

The size and not merely the 200, because `latest` moves and a stale edge can serve the
previous release's binary under a 200 — this project watched a CDN serve a stale page across
32 consecutive polls on 2026-07-21.

**Its missing control is named rather than glossed.** The negative case is a real 404
against a public URL, so the nearest available control is to request a filename that cannot
exist and require 404 in the same run, proving the reading distinguishes present from
absent. A `HEAD` that returns 200 for everything is measuring a redirect, not an asset.

---

## 7. TASK 4. Close-out

### 7.1 Dispatch

Card **314** created via `POST https://avital-dispatch.up.railway.app/api/agent/update`
from PowerShell with the `x-frontier-secret` header, action `create`, status `done`, then
tagged `clawfactory,docs,reconciliation` via action `add_tags`. The secret was read from
`C:\Projects\FrontierAI\.env` and never printed; its length was reported and nothing more.

**Two honest limitations, stated rather than implied:**

1. **The detail was posted as a comment (`{"action":"add_comment","card_id":314,
   "content":…}`), HTTP 200, but could not be read back.**
   `GET /api/cards/314/comments` returns the SPA HTML shell, not JSON; the card object
   carries no comment count; and the card's `updated_at` did not move on the comment POST.
   The 200 is the same success signal `scripts/dispatch_card.py` itself uses, so the comment
   almost certainly landed — but *almost certainly* is the honest word. **Not verified by
   read-back.**
2. **The card `description` is empty and cannot be filled.** The board's write endpoint
   accepts exactly `create`, `update_status`, `add_comment`, `set_priority`, `add_tags`
   (read from `scripts/dispatch_card.py`). `description` is accepted **only at create
   time**, and this session passed the body as `content` instead. `action: update` with a
   `description` returns **400 with an empty body**. Creating a second card to carry it
   would leave a duplicate; that was judged worse than an empty description on a card whose
   title, status and tags are correct and readable. **A future session should pass
   `description` in the `create` call.**

`python` is blocked by Windows Application Control on this machine; `dispatch_card.py` was
read, not run.

### 7.2 Git

```
git status --short   (before staging)
 M docs/FAILURE_CATALOGUE.md
 M docs/POST_RELEASE_DOC_CORRECTIONS_v1.4.4.md
 M docs/RELEASE_NOTES_v1.4.4.md
 M docs/V1_5_BACKLOG.md
 M docs/VALIDATION_PREAMBLE.md
```

Five explicit `git add` calls, one per file. **No `git add -A`.** No `git worktree add`.
**No tag.**

All five are `i/lf w/lf` under the repository's `text=auto eol=lf` attribute, confirmed with
`git ls-files --eol` before staging, so the committed blobs carry LF and the working tree
matches.

**Line counts, before → after:**

| File | Before | After |
|---|---|---|
| `docs/V1_5_BACKLOG.md` | 278 | 460 |
| `docs/VALIDATION_PREAMBLE.md` | 356 | 454 |
| `docs/FAILURE_CATALOGUE.md` | 1133 | 1190 |
| `docs/POST_RELEASE_DOC_CORRECTIONS_v1.4.4.md` | 181 | 193 |
| `docs/RELEASE_NOTES_v1.4.4.md` | 587 | 592 |
| `CLAUDE_ClawFactory.md` **(untracked)** | 1314 | 1564 |

**Two deviations from TASK 4.2, stated rather than hidden.**

1. **`CLAUDE_ClawFactory.md` is not staged.** It is gitignored and carries private working
   context; see section 1.1. `git add -f` would publish a credential to a public repository.
2. **This close-out is a second commit.** Section 7.1 reports the dispatch result and
   section 7.2 reports the first commit's hash, neither of which can be written before they
   happen. A single commit would have required writing the report before performing the work
   it reports.

The first commit was amended once, before push, for a mechanical reason worth recording: the
commit message was passed using PowerShell here-string syntax (`@'…'@`) through the **Bash**
tool, which is `sh` and does not parse it — the `@` delimiters landed in the message as
literal lines. Caught by reading the message back, fixed with `commit --amend -F`.

### 7.3 Drift flagged and deliberately NOT erased

| Drift | Why it was left |
|---|---|
| `CHANGELOG.md`'s newest entry is `[1.4.0] - 2026-08-23`. **Versions 1.4.1, 1.4.2, 1.4.3 and 1.4.4 have no entries.** | Writing four release entries is authoring, not reconciliation, and is outside this job's scope. Flagged as the single largest documentation gap found |
| `docs/RELEASE_v1.4.4_GITHUB_BODY.md` and `Output/v1.4.4-release-body.md` say "download 440 MB" without naming the artifact | These are the *published* release body. Editing the repo copy diverges it from what is live on GitHub — the exact defect `docs/POST_RELEASE_DOC_CORRECTIONS_v1.4.4.md` exists to prevent |
| `docs/RELEASE_NOTES_v1.4.3.md` describes a release that was never published | Its own header says so. It is a record |
| `v1.1_backlog.md` (2026-07-18) references M4/M5, now closed | A backlog is a record of intent. The closure is noted in `CLAUDE_ClawFactory.md` where the issues are described; the backlog IDs are left addressable |
| `validation/RUNBOOK_v135.md` is v1.3.5-specific and its artifact digests are three releases old | A per-version runbook. Not a live claim |
| `ClawFactory_Session_Handoff_May26.md`, `ClawFactory_Session_Handoff_2026-07-14.md`, `CC_Git_Hygiene_Both_Repos.md`, `Weekly_Work_Log.md` (last touched 2026-05-22), `REPORT.md` | Dated handoffs and logs. Records |
| The ten unshipped roadmap products in `CLAUDE_ClawFactory.md` (ClawResearch through ClawSight) and their prices | **Explicitly not deleted.** The brief forbids removing a roadmap item because it looks stale. The prices are marked as never charged; the intent is retained |
| `CLAUDE_ClawFactory.md` §13, §15, §17, §18, §19.1–19.3 | Describe a v1.0.x install. Not re-verified in this job, and the file now says so rather than letting them read as current |
| `docs/session_reports/**` (88 files) | Records. Exactly one was touched, by annotation not rewrite: see 6.4 |

### 7.4 Defect ledger for this session

| | Count |
|---|---|
| Product defects found | **0** — none were sought; this job touches no product code |
| Defects found in **this session's own instruments** | **2** — the `grep -P` scanner (6.3) and the pipeline-masked secret check (9.1) |
| of those, would have produced a **false finding** | **2**. The first would have reported the mojibake defect as fixed; the second reported a live credential in three tracked files that does not exist |
| Defects found in **existing specifications** | **1** — the build-gate cross-check, 6.2(a) |
| Defects found in **existing records** | **2** — the false `SECURITY_FINDINGS` bundling row (6.4); the missing practice 20 (6.4) |
| **Prompt premises found wrong** | **2** — section 1 |
| Caught **before** anything was written | **2 of 2** instrument defects. Both were caught by a control firing in the same invocation, not by suspicion |
| **Security findings** | **1** — the Azure subscription id is in 7 tracked files of a public repository and in 6 commits of its history. 9.3. Reported, not fixed: the disposition is the operator's |

**The instruments were wrong more often than the documents were.** Four of the seven
censuses found the tree already correct. What this session actually produced was one
corrected working-context file, two new backlog items, one sharpened specification, and four
new rules — three of them earned by defects in the reconciliation itself.

---

## 8. What is NOT closed

1. **`CLAUDE_ClawFactory.md` must be re-uploaded to the Claude project files by the
   operator.** Nothing in this repository can do it. Until then, the copy a chat session
   reads still carries every claim in 5.1.
2. **Card 314's comment is unverified by read-back**, and its description is empty. 7.1.
3. **OM-1, the `:8787` dashboard, has still never been measured.** It is now recorded where
   a validation cycle will read it. It is not answered.
4. **`CHANGELOG.md` has no entries for v1.4.1 through v1.4.4.**
5. **Nothing in TASK 3 was implemented**, by instruction. The staleness gate, the tenth
   build gate and the post-release download check are all specification.
6. **The Azure subscription id is public and no disposition has been chosen.** 9.3. It is
   in 7 tracked files and 6 commits of a public repository. Accept-and-document is the
   recommendation; a history rewrite is the alternative; neither is decided.

---

## 9. ADDENDUM: what the end-of-session gate found, after the close-out was committed

The gate in 7.2 was extended with a check that this session's own secret-removal (5.4) had
not simply moved the problem. It found two things.

### 9.1 My own gate check was a defective instrument, and the controls caught it

The first form of the check was `git grep -l '<password>' HEAD -- | head -3 || echo "..."`.
**In a pipeline, `$?` is the last command's status**, so `head`'s exit 0 suppressed the
`|| echo` branch and the *next* command's output appeared under the first command's label.
It looked exactly like a live credential in three tracked files.

This is the `cmd | head` followed by `$?` trap, named verbatim in
`docs/VALIDATION_PREAMBLE.md` under SHELL AND EXIT CODES, walked into while running a
security check. It was resolved by re-running with `if git grep -q …; then` and **two
controls in the same invocation**: a string that must be present (`ClawFactory-Secure-Setup`
→ found) and one that cannot exist (→ not found). Only then was either result believed.

**Second instrument defect of this session**, and the second caught by a control rather than
by care. See 6.3 for the first.

### 9.2 The plaintext admin password is ABSENT from the repository. Confirmed

```
$ git grep -q '<password>' HEAD  ->  exit 1, ABSENT
```

The pre-publication sweep did its job. Nothing about the credential removed from
`CLAUDE_ClawFactory.md` §20.6 in 5.4 was ever pushed.

### 9.3 **The Azure subscription id IS in the public repository, in 7 tracked files**

**A finding for the operator, not something this session should decide.**

```
$ git grep -l '<subscription-id>' HEAD
REPORT.md
docs/session_reports/HANDOFF_2026-08-20_card258.md
reports/AZURE_SIGNING_WIRED_20260706.md
validation-runs/phase1-bake-20260506-130428/log.md
validation-runs/phase1-bake-20260506-132433/log.md
validation-runs/phase1-bake-20260506-144034/log.md
validation-runs/phase1-bake-20260506T185022Z/log.md
```

It appears inside full ARM resource ids — the baseline image, the signing account, the
validation resource group — in commands that were pasted into reports. **6 commits in the
history touch it**, so it is in the published history and not only in the tip.

**Why this is reported and not fixed.**

- **An Azure subscription id is an identifier, not a credential.** It grants nothing on its
  own; every operation against it is authenticated separately. It is not the same class of
  exposure as a password, and this report does not claim it is.
- **But the pre-publication sweep treated it as sensitive.** `.gitignore:62` names "the
  Azure subscription id" among the reasons `CLAUDE_ClawFactory.md` was untracked. **The
  sweep untracked the file that held it and did not census the identifier itself** — which
  is `docs/FAILURE_CATALOGUE.md` practice 19 exactly: *a claim removed from the place it was
  noticed is not a claim removed*, applied to a value instead of a sentence.
- **Redacting the working tree would not remove it.** It is in six commits of a public
  repository's history. Closing it properly means either accepting the exposure explicitly,
  or a history rewrite on a repository that has already been cloned by an unknown number of
  people. **Both are the operator's call and neither is a documentation-reconciliation
  task.**

**Recommended disposition, offered not taken:** accept and document. The identifier is
low-value, the history rewrite is high-cost and incomplete, and an explicit line in
`SECURITY_FINDINGS.md` saying the subscription id is public and why that is acceptable is
worth more than a rewrite that leaves forks untouched. **Not decided here.**

**This did not delay the push and does not change any commit above.** It is recorded because
the gate found it and a gate finding that is not written down did not happen.
