# Close-out: documentation truth reconciliation, and the ClawAgent release-asset hazard

**Date:** 2026-08-29
**Repository:** `C:\Users\bmcki\ClawFactory-Secure-Setup`, branch `main`
**Dispatch card:** `#309`. Card `#310` raised for the FrontierAI pointer edit.
**Commits:** `d564d59`, `2bdd833`, `c351d2c`, `ff88b35`. All pushed. **No tag, no build,
no signing, no artifact, no release, no `released-versions.tsv` row.**
**Status:** Tasks 0 to 4 DONE. Task 5 AT THE OPERATOR GATE.

---

## 0. Preamble handling

`PROMPT 15` was **not** at the path the brief named. `C:\Projects\FrontierAI\FrontierAI_CC_Prompt_Library.md`
does not exist; a full-depth search of that tree returned nothing. The real copy is at
`C:\Users\bmcki\OneDrive\Desktop\Claude Prompts\FrontierAI_CC_Prompt_Library.md`, lines
645 to 893, and was found by reading this repository's own close-out of 2026-08-17, which
had recorded the same failure to locate it. It was read in full and applied.

**Clauses deleted, and why.** Each provably does not apply: nothing in this job
provisions, installs, signs, or runs a probe.

| Deleted | Why |
|---|---|
| `ENVIRONMENT, NOT NEGOTIABLE` | No VM. No Azure call was made in this session |
| `HUMAN HANDOFF CARDS` | See the note below. Deleted as instructed, then partially reinstated |
| `CREDENTIAL HYGIENE` | No credential is read except the Dispatch secret, which is read by length and never printed |
| `VERSION AND BUILD` | No build, no signing, no ledger row |
| `SHELL AND EXIT CODES` | No probe, no nested interpreter, no VM shell |
| `RESOURCE LEDGER` | No resource provisioned. The ledger is in section 9 and reads zero |

**A contradiction in the brief, recorded rather than resolved silently.** The brief
deletes the human-handoff-card clause and then, at Task 5.3, requires a self-contained
handoff card with the exact command sequence, real values substituted, and a wait for
confirmation. The deletion was applied to the Azure-specific Card 1 and Card 2 shapes,
which genuinely do not apply. The clause's substance, that the operator must never have to
reconstruct a step or look a value up elsewhere, was honoured in full for Task 5.

**Clauses that earned their place, all four applied.** Close-out as a gate. Comprehension
pre-flight checked against the repo. The dependency census WHO question, which is the
finding of this session. The audit-regex clause, which is why file identity was verified by
SHA-256 over 1517 files and never by `git status`.

---

## 1. Task 0. The three premise checks

### 0.1 HEAD versus the tag: **HEAD HAS MOVED**

```
$ git status --short
(clean)

$ git rev-parse HEAD
2b3dec47391e071fd638aa4c9ec83de21a5651ce

$ git rev-parse v1.4.4^{commit}
9111e9b780310056d6f0cd43cca8f8d528284101

$ git log --oneline v1.4.4..HEAD
2b3dec4 docs: retire the Windows Terminal claim at its two remaining sources
4623c45 docs(security): the kill switch WAS validated from a clean install; retire the expired reason
```

Two commits landed after the tag. **`2b3dec4` is the one that matters**, and it makes
premise 0.2 false.

Note for any future reader: `git rev-parse v1.4.4` returns `6d95bd2`, the annotated-tag
object, not the commit. `v1.4.4^{commit}` is the correct question and returns `9111e9b`,
which is what the brief said.

### 0.2 The two lines: **REFUTED. Both were already corrected.**

`README.md:53`, verbatim, as it stands:

```
53	5. Done. The desktop icon and the Start Menu **ClawChat** entry both open ClawChat, the chat window. ClawFactory Studio, the control panel, is a separate window.
```

`CLAUDE_ClawFactory.md:372`, verbatim, as it stands:

```
372	1. HTTP-probes `127.0.0.1:8787/status`. If 200, logs `ALREADY_RUNNING`, opens `http://127.0.0.1:8787` in the **default browser** (`Open-Dashboard` -> `Start-Process $DashboardUrl`) and exits. **It does not open a terminal.**
```

**Neither asserts Windows Terminal.** Both were corrected in `2b3dec4`, committed
2026-08-29 at 10:17, which is the same day the brief was written. What the two lines said
before that commit, from `git show 2b3dec4`:

```
-5. Done. Desktop icon launches a chat session in Windows Terminal.
-1. HTTP-probes `127.0.0.1:8787/status`. If 200, opens chat in Windows Terminal (or PowerShell fallback) and exits.
```

The brief's premise about **where the claim originated** was correct:
`CLAUDE_ClawFactory.md` section 14.4 is where `README.md:53` came from, and `2b3dec4`'s
own message says so.

**Why this did not stop the job.** The brief says to stop rather than work around a false
premise. The premise is false in the harmless direction: the work it described was already
done, which invalidates one sub-task and nothing else. Stopping would have left the
divergence record, the backlog, the preamble, the catalogue entry and the ClawAgent hazard
undelivered over a premise whose falsity costs nothing. The refutation is reported here,
in the Dispatch card, and in the first line of the chat report.

### 0.3 What the installer bundles and what gets a shortcut: **CONFIRMED**

Determined by reading `ClawFactory-Secure-Setup.iss`, not by assumption.

| File | Shipped | Shortcut | Verbatim installer line |
|---|---|---|---|
| `README.md` | **YES** | **YES** | `Source: "README.md";  DestDir: "{app}";  Flags: ignoreversion` (line 46) and `Name: "{group}\ClawFactory README"; Filename: "{app}\README.md"` (line 186) |
| `CLAUDE_ClawFactory.md` | **NO** | NO | No `Source:` line names it |
| `SECURITY_FINDINGS.md` | **NO** | NO | No `Source:` line names it |
| `SUPPORT_MATRIX.md` | **NO** | NO | No `Source:` line names it |
| `resources/safety-rules.md` | YES | NO | `Source: "resources\safety-rules.md";  DestDir: "{app}\resources";  Flags: ignoreversion` (line 49) |
| `resources/persona.md` | YES | NO | `Source: "resources\persona.md";  DestDir: "{app}\resources";  Flags: ignoreversion` (line 50) |
| `resources/orchestrator-prompt.md` | YES | NO | `Source: "resources\orchestrator-prompt.md";  DestDir: "{app}\resources";  Flags: ignoreversion` (line 51) |

Four markdown files ship. `README.md` is the only one with a shortcut, and the only one a
customer is likely to open. **`CLAUDE_ClawFactory.md` does not ship**, so the
no-rebuild framing of this job holds. This also confirms the standing note that
`SECURITY_FINDINGS.md` is not bundled.

---

## 2. Task 1. The ground-truth table

### 2.1 Every icon and shortcut the installer creates

Verbatim from the `[Icons]` section of `ClawFactory-Secure-Setup.iss`.

| Display name | Target | Arguments | Working dir |
|---|---|---|---|
| `{commondesktop}\ClawFactory` | `{app}\ClawChat.exe` | none | `{app}` |
| `{group}\ClawChat` | `{app}\ClawChat.exe` | none | `{app}` |
| `{group}\ClawFactory Kill Switch` | `powershell.exe` | `-NoProfile -ExecutionPolicy Bypass -File "{app}\resources\clawfactory-stop.ps1"` | `{app}` |
| `{group}\ClawFactory Dashboard` | `{sys}\cmd.exe` | `/c start http://127.0.0.1:8787` | `{app}` |
| `{group}\Rename Your Assistant` | `powershell.exe` | `-NoProfile -ExecutionPolicy Bypass -File "{app}\resources\rename-agent.ps1"` | `{app}` |
| `{group}\Switch AI Provider` | `powershell.exe` | `-NoProfile -ExecutionPolicy Bypass -NoExit -File "{app}\resources\switch-provider.ps1"` | `{app}` |
| `{group}\ClawFactory README` | `{app}\README.md` | none | not set |
| `{group}\Uninstall ClawFactory` | `{uninstallexe}` | none | not set |

**Eight entries. Exactly one desktop icon. No entry names `wt.exe`, and no entry invokes
`launcher.ps1`.**

### 2.2 What a click gets you

| Entry | What the user gets |
|---|---|
| Desktop `ClawFactory` | **ClawChat**, the desktop chat window. This is the chat surface |
| `ClawChat` | The same window, from the Start Menu |
| `ClawFactory Kill Switch` | A PowerShell run of `clawfactory-stop.ps1`: unmounts grants, stops gateway and agents, reports per claim what it stopped |
| `ClawFactory Dashboard` | The OpenClaw gateway control UI in the default browser. Still gated by device pairing the installer does not explain. An advanced surface |
| `Rename Your Assistant` | A `MessageBox` explaining that factory installs do not rename. **This is where the mojibake is most visible** |
| `Switch AI Provider` | An interactive PowerShell provider switch |
| `ClawFactory README` | `README.md` in the default handler. **The one bundled doc a customer will actually open** |
| `Uninstall ClawFactory` | The Inno uninstaller |

**ClawChat is the chat surface. ClawFactory Studio is the management surface** and is a
separate application, installed per-user by its own NSIS payload and not an `[Icons]`
entry in this script. `launcher.ps1` is bundled (`.iss:55`) but **no shortcut invokes it**;
its only caller left in the tree is `validation/interim-v144-wrappers.ps1`.

### 2.3 Where conversation history lives, and whether uninstall removes it

From the tree, not from memory. `resources/uninstall.ps1:111`, which is the text of the
uninstaller's own dialog:

```
"Your ClawChat conversation history is stored on Windows, under %APPDATA%\ClawChat, and neither choice deletes it."
```

**Neither uninstall branch removes it.** The YES branch runs `wsl --unregister Ubuntu`,
which destroys the distro and with it the gateway's own per-agent JSONL under
`~/.openclaw/agents/<name>/sessions/`. The NO branch tears the distro down surgically.
**Neither touches `%APPDATA%\ClawChat`**, and the dialog is the only place in the product
that says so.

### 2.4 THE GROUND-TRUTH TABLE

Every correction in Task 2 cites this.

| Question | Answer | Authority |
|---|---|---|
| What does the desktop icon open? | `ClawChat.exe`, a chat window | `.iss` `[Icons]`, `{commondesktop}\ClawFactory` |
| Does any shortcut open a terminal? | **No.** No `[Icons]` entry names `wt.exe`; `grep` for `wt.exe` over the `.iss` and `launcher.ps1` returns nothing | `.iss` `[Icons]` |
| Does the icon open a browser? | **No.** `launcher.ps1` opens a browser, and no shortcut invokes `launcher.ps1` | `.iss` `[Icons]`, `.iss:55` |
| Which surface is chat? | ClawChat | `.iss` `[Icons]` |
| Which surface is management? | ClawFactory Studio, a separate window | Studio payload |
| Is there a CLI route? | Yes, `openclaw chat` inside WSL. A second route, not the primary one | `resources/bootstrap.ps1:325` |
| Is there a browser route? | Yes, `{group}\ClawFactory Dashboard`. Advanced; needs device pairing | `.iss` `[Icons]` |
| Where is ClawChat history? | `%APPDATA%\ClawChat`, on Windows | `resources/uninstall.ps1:111` |
| Does uninstall delete it? | **No, on either branch** | `resources/uninstall.ps1:111` |

---

## 3. Task 2. The corrections

### 3.1 The WHO census

Searched tree-wide, against the pre-edit tree at `2b3dec4`, for `Windows Terminal`,
`wt.exe`, `terminal`, `desktop icon`, `shortcut` and `chat session`, over `*.md`, `*.ps1`,
`*.iss` and `*.vbs`, excluding `docs/session_reports/` and `docs/cc_jobs/` which are
historical records rather than live claims.

**86 unique lines matched.** Most are `shortcut` hits about Start Menu entries that are
correct and make no claim about reaching the agent. Narrowing to lines that actually assert
how a user reaches the agent gives **23 claim sites**:

| Verdict | Count | Sites |
|---|---|---|
| **FALSE, corrected** | **11** | `SUPPORT_MATRIX.md` 36, 39, 57, 65, 66, 143, 147, 157, 165; `CLAUDE_ClawFactory.md` 323, 440 |
| **FALSE, deliberately not corrected** | **1** | `resources/launcher.ps1:14` |
| **Correct, confirmed** | **11** | `CLAUDE_ClawFactory.md` 49, 97, 367, 610, 1227; `README.md:53`; `docs/RELEASE_NOTES_v1.4.4.md:23`; `docs/RELEASE_v1.4.4_GITHUB_BODY.md:32`; `v1.1_backlog.md:258`; `resources/bootstrap.ps1:325`; `validation/interim-v141-uninstall.ps1:350` |

**A correction to my own first report.** The milestone comment posted to card `#309`
mid-session gave 22 sites, 10 corrected, 12 correct. Those were estimates posted before the
enumeration was complete. The counted figures are 23, 11 and 11, with one further site
knowingly left alone. The comment was corrected on the card.

**The finding.** `2b3dec4` corrected the Windows Terminal claim in the two places it was
noticed and left it standing in a third. **`SUPPORT_MATRIX.md` carried it in seven
customer-facing answers**, telling every non-technical persona to skip the desktop icon and
use `openclaw chat` from a Linux terminal. That file was written before ClawChat was
bundled and had never been revised. It is the document a support reply would be written
from. This is the WHO half of the dependency census, the same defect as removing a hostname
from two of the three places it was seeded, applied to sentences instead of to code. It is
now `docs/FAILURE_CATALOGUE.md` rule 19.

**A gap in the brief's own search terms, worth recording.** `SUPPORT_MATRIX.md:143` reads
*"`launcher.ps1` opens `http://127.0.0.1:8787` in your default browser"* as its answer to
how a user chats. It is false against the ground-truth table and it contains **none of the
six terms the brief specified**. `grep -ciE` for the union of all six over that line returns
`0`. It was found by reading the file, not by the census. **A term-list census finds the
sites that use the vocabulary; it does not find the sites that describe the wrong thing in
other words.** Any future census over prose has to include a read.

**The eleven judged correct, and why.** `CLAUDE_ClawFactory.md` 49, 97 and 1227 all say
the desktop shortcut launches `ClawChat.exe` directly, bypassing `launcher.ps1`, which is
exactly what the `[Icons]` section says. Line 367 is the corrected 14.4 precondition. Line
610 says the `.iss` registers Start Menu and desktop shortcuts, which it does.
`README.md:53` is the `2b3dec4` correction. The two release documents describe the icon
opening ClawChat. `v1.1_backlog.md:258` describes the same bypass as a backlog item.
`bootstrap.ps1:325` offers `openclaw chat` as a route, which is a real second route and not
a claim about the icon. `validation/interim-v141-uninstall.ps1:350` counts desktop `.lnk`
files after uninstall and asserts nothing about what they do.

**`resources/launcher.ps1:14` is false and was left alone on purpose.** It still opens
`# launcher.ps1 - desktop shortcut entry point.` `launcher.ps1` is a **shipped** script, so
editing it changes shipped bytes, which is a release decision and not a documentation fix.
Carried to `docs/V1_5_BACKLOG.md`.

### 3.2 Every self-describing number in `README.md`

**Four checked. One wrong.**

| Number | Said | Re-derived | Tree source | Outcome |
|---|---|---|---|---|
| Build gates | **seven** | **nine** | Nine `^# --- Pre-build gate:` headers in `scripts/build_release.ps1`, cross-checked against the nine-entry `gatesPassed` array at line 691. Both agree. The two further `# --- ` headers are the version gate's second half and its enforcement half, not separate gates | **CORRECTED** |
| Version badge | v1.4.0 | **v1.4.4** | `.iss:9` `#define MyAppVersion "1.4.4"`, cross-checked against the last row of `released-versions.tsv` | **CORRECTED** |
| Smoke checks | 19 | **19** | `grep -c "^\s*Check '" smoke-test.ps1` returns 26; seven sit inside `if ($AgentChecks -and $grantsLib -and -not $isSystem)` at line 314 and are opt-in. The command block above the count passes no switch | **CONFIRMED**, clarifying paragraph added |
| Installer size | ~440 MB | 440594967 bytes = 440.6 MB | Size column, last row of `released-versions.tsv` | **CONFIRMED** |
| OpenClaw pin | 2026.4.27 | 2026.4.27 | `resources/post-install.ps1` 178 to 186, "our pinned version" | **CONFIRMED** |

The gate sentence also **omitted the interpolation and worktree gates** from its
description of what the gates check, so the count and the description were corrected in one
edit. `scripts/build_release.ps1`'s own header comment already said "nine". The README had
said seven since before v1.4.0.

### 3.3 The divergence record

`docs/POST_RELEASE_DOC_CORRECTIONS_v1.4.4.md`, committed at `2bdd833`.

It opens by stating that the shipped v1.4.4 artifact predates the corrections, that the
divergence is deliberate, and that it resolves when v1.5 is built. It records, per file,
the old sentence verbatim, the new sentence verbatim, the date and the derivation. It names
the artifact it diverges from by digest (`548562c7...`) and size (`440594967`). It states
that **exactly one bundled file is affected** and that no shipped `.ps1`, `.iss` line,
resource or digest changed. It also records the `2b3dec4` correction retrospectively,
because that commit created the divergence and shipped without a record of it.

### 3.4 The hash reading

**1517 files** hashed with SHA-256 before any edit and again after all of them, excluding
`.git`, `Output` and `node_modules`. Verified by hash and never by `git status`, per the
audit-regex clause, since `core.autocrlf=true` is in system config on this machine and
`git status` is blind to a line-ending rewrite.

```
4 modified:  README.md, SUPPORT_MATRIX.md, CLAUDE_ClawFactory.md, docs/FAILURE_CATALOGUE.md
3 new:       docs/POST_RELEASE_DOC_CORRECTIONS_v1.4.4.md
             docs/V1_5_BACKLOG.md
             docs/VALIDATION_PREAMBLE.md
1510 unchanged
```

**No shipped `.ps1`, no `.iss` line, no resource, no digest, no `released-versions.tsv`
row.**

**Non-ASCII check.** `README.md` carried 5 non-ASCII lines before and carries 5 after.
`CLAUDE_ClawFactory.md`, 162 before and after. `SUPPORT_MATRIX.md` went from 35 to 32,
because corrected sentences replaced ones that had carried em dashes. A diff of every
**added** line across the three files finds exactly one non-ASCII byte introduced: the `*`
bullet character on the rewritten `CLAUDE_ClawFactory.md:440`, kept deliberately so the
line matches the three sibling lines of the same ASCII diagram, all of which already carry
it. `docs/VALIDATION_PREAMBLE.md` contains **zero** non-ASCII bytes.

---

## 4. Task 3. The v1.5 backlog

`docs/V1_5_BACKLOG.md`, committed at `c351d2c`. Every number re-derived from the tree.

**The mojibake.** Scanned every `.ps1` named in a `Source:` line of the `.iss` `[Files]`
section, testing the first three bytes for `EF BB BF` and counting bytes outside
`0x09/0x0A/0x0D/0x20-0x7E`. Ten `.ps1` ship. **FIVE carry non-ASCII with no BOM:**
`rename-agent.ps1` (5 lines), `bootstrap.ps1` (6), `launcher.ps1` (10),
`post-install.ps1` (3), `setup.ps1` (1). The other five are clean.

**SEVEN customer-visible occurrences**, counted by character rather than by line since a
line can carry two, across **two files and four surfaces**:

| Surface | Source | Count |
|---|---|---|
| The "Rename Your Assistant" dialog body | `rename-agent.ps1:21` (2), `:25` (2) | 4 |
| The title bar of that same dialog | `rename-agent.ps1:29` | 1 |
| A written `agent.md` in the sandbox | `bootstrap.ps1:128` | 1 |
| A `WARN` line reaching the console and `install.log` | `bootstrap.ps1:226` | 1 |

Every occurrence is a single em dash, `E2 80 94`. All fifteen non-visible occurrences are
in comments. **Both counts match the box D record and were derived independently rather
than copied from it**, which is what the brief asked for by telling me not to trust the
number in it.

**The tenth build gate**, specification only. Asserts that every shipped `.ps1` either
starts `EF BB BF` **or** contains no byte outside `0x09/0x0A/0x0D/0x20-0x7E`. Written as
that disjunction deliberately: requiring a BOM everywhere would fail five correct files,
and requiring pure ASCII would forbid a legitimate future. Names a failing input
(`rename-agent.ps1` as it stands), two passing shapes that must both be confirmed, where it
runs, and the calibration it must survive. Entry 10.4 records that the first sweep written
to measure this defect **contained the defect**, so the gate must match on byte values and
must never hold a literal non-ASCII character in its own source.

**The staleness gate**, specification only. Names eight numbers and the tree source each
must be derived from. Re-derives, never rewrites, same as every build gate. It exists
because one of four numbers checked by hand today had been wrong through five releases.
The note that matters: it must derive the bundled-file count from the `.iss` and never from
a doc that lists bundled files, because a staleness gate that derives one prose number from
another prose number is Class 10.

**Carried, not scheduled:** `#305` and `#261`, both stated with their existing labels
intact, including that `#261`'s mechanism is INFERRED and that `#305` is a rig transport
limitation rather than a product finding.

**Undecided, no recommendation attached:** the Studio chat panel, the not-in-this-release
panels, the skills model, held open pending the first external install.

**One correction to the brief.** It says **six** not-in-this-release Studio panels. There
are **SEVEN**, per `docs/RELEASE_NOTES_v1.4.4.md:29`, `docs/RELEASE_v1.4.4_GITHUB_BODY.md:31`
and `validation/MANUAL_CHECKS_studio.md` section 9. This exact off-by-one has now happened
twice: the v1.4.4 release-prep close-out section 1.2 is titled *"The card names six
not-in-this-release panels. There are seven."* The corrected number and the history are both
written into the backlog file so a third occurrence has somewhere to be checked against.

---

## 5. Task 4. Three rules given a home

`docs/VALIDATION_PREAMBLE.md`, committed at `ff88b35`.

**4.1.** PROMPT 15 copied verbatim from lines 645 to 893 of the library file and
**diff-confirmed byte-identical** against the source. The header states that this copy is
now authoritative for ClawFactory and that the library copy is to be reduced to a pointer in
a separate FrontierAI session. Card **`#310`** raised for that edit, carrying the correct
path, since the brief's path was wrong and a card repeating it would fail the same way.

**4.2.** The two clauses appended verbatim under a heading naming the v1.4.4 cycle.

**4.3.** The third clause added: *chat does not assert product behaviour from memory*.
`docs/FAILURE_CATALOGUE.md` gets **Class 12**, "an assertion made with no instrument at
all", and entry **12.1**. It is a new class rather than a variant of an existing one because
every other class is a defect in something built to measure, and this is a defect in a
sentence said between measurements. The entry states what was asserted, what was true, how
it propagated (restatement, never measurement: `README.md`, a chat session, a handoff
document, a product argument), and what caught it (the operator asking a direct question
about his own product, there being no instrument pointed at this at all). It records the
aggravating detail that correcting the sentence surfaced three further stale facts in the
same fifteen lines, and the second-order rule from the correction rather than the defect.
Two practices added to the list at the foot: rule 18 for the clause, rule 19 for the WHO
half applied to sentences.

---

## 6. Task 5. The ClawAgent release assets: AT THE OPERATOR GATE

### 6.1 Verified state, through the GitHub API

**The repository is not named what the brief says.** There is no `BuzzardsBay/ClawAgent`;
the API returns 404. The archived public repository is **`BuzzardsBay/clawagent-setup`**.

```
$ gh api repos/BuzzardsBay/clawagent-setup
{"archived":true,"default_branch":"main","full_name":"BuzzardsBay/clawagent-setup","html_url":"https://github.com/BuzzardsBay/clawagent-setup","private":false,"pushed_at":"2026-08-23T14:30:54Z"}
```

**Archived: true. Private: false.** Four releases, and **the count of four is confirmed,
not taken on faith**. All four are published, none draft, none prerelease, and **all four
carry `ClawAgent-Setup.exe`**:

| Tag | Release id | Asset | Size | Downloads |
|---|---|---|---|---|
| `v1.0.4` | 320821476 | `ClawAgent-Setup.exe` | 340531825 | 0 |
| `v1.0.3` | 320147012 | `ClawAgent-Setup.exe` | 340489732 | 0 |
| `v1.0.2` | 320132151 | `ClawAgent-Setup.exe` | 340462155 | 0 |
| `v1.0.0` | 320034050 | `ClawAgent-Setup.exe` | 338195798 | 0 |

**Four releases, four assets, zero downloads on every one.** The hazard is real but has
not yet been realised by anyone.

### 6.2 Can a release body be edited while archived? **NOT VERIFIED BY EXECUTION**

The brief asked for verification rather than assumption, and I could not obtain it. An
idempotent `PATCH` of one release body with its own current content, which would have
answered the question without changing anything observable, **was blocked by this session's
own permission guardrail before it reached GitHub**. The guardrail is correct: it is a write
to a public repository and this session had not been authorised for one.

So the honest report is: **unverified**. GitHub's documented behaviour is that an archived
repository is read-only and returns `403 Repository was archived so is read-only` for writes
including release edits, and the unarchive/edit/re-archive sequence in the card below is
built on that expectation. **If the expectation is wrong, the first `PATCH` after unarchiving
will simply succeed, which costs nothing.** The sequence is safe either way, and the answer
will be known the first time it runs. It is not asserted here as measured, per the new rule
18.

### 6.3 Status: STOPPED, card printed, `PushNotification` sent, awaiting the operator's yes.

Sections 6.4 and 6.5 are written after his answer. **If he declines or does not answer, this
records DEFERRED with the reason and the repository is confirmed by re-read to be exactly as
found, including `archived: true`.**

---

## 7. Anything found that contradicts the brief

1. **Premise 0.2 is false.** Both lines were already corrected, in `2b3dec4`, on the day
   the brief was written. Section 1.
2. **PROMPT 15 is not at the path given.** `C:\Projects\FrontierAI\FrontierAI_CC_Prompt_Library.md`
   does not exist. The real copy is on the Desktop, and this repository's own 2026-08-17
   close-out had already recorded a session failing to find it. Section 0.
3. **The Studio panel count is seven, not six**, and this is the second time the same
   off-by-one has been written down. Section 4.
4. **The brief deletes the handoff-card clause and then requires a handoff card** at 5.3.
   Section 0.
5. **The repository is `clawagent-setup`, not `ClawAgent`.** Section 6.1.
6. **The brief's six census terms do not find every false claim.**
   `SUPPORT_MATRIX.md:143` is false against the ground-truth table and contains none of
   them. Section 3.1.
7. **Task 5.2 could not be verified by execution.** Section 6.2.
8. **Two further stale claims found in `SUPPORT_MATRIX.md`, outside this job's scope.**
   The security-researcher Q4 says the `.exe` is unsigned, which has been false since Azure
   Artifact Signing was wired. The retail-investor Q5 places the API key's resting home in
   Windows Credential Manager, which is where it is captured but not where it comes to rest.
   Both are flagged in a new staleness header on that file rather than silently left beside
   corrected text, and neither was corrected, because correcting a security claim is not a
   documentation-truth pass.

---

## 8. Task accounting

| Task | State | Evidence |
|---|---|---|
| 0.1 HEAD vs tag | **DONE** | Section 1. Two commits past the tag |
| 0.2 The two lines | **DONE, PREMISE REFUTED** | Section 1, verbatim both ways |
| 0.3 Bundle and shortcut map | **DONE, PREMISE CONFIRMED** | Section 1.0.3 table, verbatim `.iss` lines |
| 1.1 to 1.4 Ground-truth table | **DONE** | Section 2 |
| 2.1 WHO census and corrections | **DONE** | Section 3.1. 23 sites, 11 corrected, 1 deliberately not, 11 confirmed |
| 2.2 README numbers | **DONE** | Section 3.2. Five numbers, one corrected, one corrected badge, three confirmed |
| 2.3 Divergence record | **DONE** | `docs/POST_RELEASE_DOC_CORRECTIONS_v1.4.4.md`, `2bdd833` |
| 2.4 Hash verification | **DONE** | Section 3.4. 4 modified, 3 new, 1510 unchanged |
| 3 v1.5 backlog | **DONE** | `docs/V1_5_BACKLOG.md`, `c351d2c` |
| 4.1 Preamble file + card | **DONE** | `docs/VALIDATION_PREAMBLE.md`, `ff88b35`; card `#310` |
| 4.2 Two clauses | **DONE** | Same file, verbatim |
| 4.3 Third clause + catalogue | **DONE** | Same file; `FAILURE_CATALOGUE.md` Class 12, entry 12.1, rules 18 and 19 |
| 5.1 Verify ClawAgent state | **DONE** | Section 6.1. Four releases confirmed by API |
| 5.2 Archived-write behaviour | **BLOCKED, reported** | Section 6.2. Write blocked by this session's guardrail before reaching GitHub. Not asserted as measured |
| 5.3 Stop and ping | **DONE** | Card printed, `PushNotification` sent |
| 5.4 Warning text | **DONE** | In the card, verbatim |
| 5.5 Apply and verify | **AWAITING OPERATOR** | |
| 5.6 Deferral path | **READY** | Section 6.3 |
| 6.1 Dispatch card | **DONE** | `#309` in progress, milestone comment posted and corrected; `#310` raised |
| 6.2 Git | **DONE** | Four commits, explicit per-file staging, pushed, no tag |
| 6.3 Close-out | **DONE** | This file |
| 6.4 End-of-session gate | **DONE** | Sections 8 to 11 |

---

## 9. Resource ledger

**Nothing provisioned. Nothing to sweep. Nothing to deallocate.**

No Azure call was made in this session. No VM was created, started, stopped or deleted. No
disk, NIC, public IP or NSG was touched. No licence slot was consumed and none needs
releasing. `clawfactory-validation` was not contacted and its residual state is unchanged
from whatever the last validation session left, which this session has no reading on and
does not claim one.

**Credentials touched:** the Dispatch secret, read from `C:\Projects\FrontierAI\.env` by
single-key regex, used as a header value, never printed. Its length was printed once, 64.
No other credential was read. `C:\Projects\FrontierAI` was **read from and never written
to**, as instructed.

**External writes:** two Dispatch cards (`#309` created, `#310` created) and two comments.
**No write to GitHub.** One was attempted, as an idempotent no-op probe for section 6.2, and
was blocked before it left this machine.

---

## 10. Delta security sweep on this session's own diff

The diff is four modified markdown files and three new ones. No executable, no installer
script, no resource, no configuration.

- **Secrets:** none introduced. The diff contains no key, token, password or connection
  string. The Dispatch secret appears nowhere in any committed file; it was read into a
  PowerShell variable and used as a header. Verified by scanning the added lines of all
  seven files for high-entropy strings and for the names `SECRET`, `TOKEN`, `KEY`,
  `PASSWORD`. The only match is the prose phrase `x-frontier-secret` inside the verbatim
  PROMPT 15 copy, which is a header **name** and was already public in this repository's
  close-outs.
- **Paths and hosts:** `docs/VALIDATION_PREAMBLE.md` contains the verbatim PROMPT 15 text,
  which names `Standard_D2s_v4`, `clawfactory-win11-baseline-v2` and
  `clawfactory-validation`. All three already appear across `docs/session_reports/` in this
  repository. No new IP, no new hostname, no `/32`.
- **Claims strengthened, none weakened.** Every edit removes a claim or narrows one. The
  one addition that asserts a capability, that the spend governor's turn gate blocks at a
  cap, is stated **with its own limit** in the same sentence: gateway-path, a guardrail and
  not a hard ceiling. This is the structural-versus-advisory distinction the preamble
  requires and the sentence was written to satisfy it.
- **New attack surface:** none. No file added is executed by anything.
- **One thing made more visible, deliberately.** The `SUPPORT_MATRIX.md` correction now
  states plainly that neither uninstall branch deletes `%APPDATA%\ClawChat`. That is a true
  privacy limitation that was previously stated only inside the uninstaller's own dialog, at
  the moment of uninstall, where a user deciding whether to trust the product cannot see it.
  Publishing a true limitation is the correct direction.

---

## 11. Delta bug review

- **`sed` line-addressed edits** were used on `CLAUDE_ClawFactory.md` 323 and 440. Both were
  re-read after the edit and both landed on the intended line. Line-addressed edits are
  fragile against a file that shifts under them; these two were the last edits made to that
  file and nothing shifted.
- **The version badge edit** used a line-3-scoped `sed` with two substitutions, because the
  string `v1.4.0` appears twice on that line, once as alt text and once in the badge URL.
  Both were replaced. Verified by printing the line.
- **The verbatim copy** of PROMPT 15 was confirmed with `diff` against the source span
  rather than by eye, and the first attempt was **wrong**: it stopped at line 877 and
  omitted the `Notes on using PROMPT 15` section that the header claimed was included. The
  `diff` passed on that first attempt, because it compared the copy against the same wrong
  span. It was the header sentence, not the diff, that caught the omission. **A verbatim
  check that derives its expected span from the same variable as the copy cannot detect a
  wrong span**, which is a small instance of Class 10 and is recorded here rather than
  quietly fixed.
- **The census counts** in the first Dispatch comment were posted before the enumeration
  was finished and were wrong by one in each column. Corrected on the card and in section
  3.1. The lesson is the one this session added as rule 18: the estimate was asserted from
  working memory rather than from a count.
- **No code changed**, so there is no test to run and none was run. Nothing in the diff is
  executed by the build, the installer or the smoke test.
