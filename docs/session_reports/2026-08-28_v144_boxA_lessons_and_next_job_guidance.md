# BOX A: full session summary, root-caused lessons, and the prompt text for boxes B, C and D

**Companion to** `2026-08-27_v144_validation_boxA_closeout.md` (2,465 lines), which
holds the evidence. This file holds the **judgement**: what went wrong, why, and
what to write in the next job card so it does not go wrong again.

Written because the operator asked for it directly. It is opinionated on purpose.

---

# PART 1 — WHAT HAPPENED

## 1.1 The result, in one table

| | |
| --- | --- |
| Artifact | v1.4.4, signed `6e655603…`, 440,610,608 bytes, Authenticode Valid |
| Box | `cfv-179`, Standard_D2s_v4, provisioned and torn down |
| Matrix rows PASS | **1, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13** |
| Matrix rows VOID | **14** — no SMTP credential, by design |
| Expected FAIL | **`SP.8`** — documented address-scoping residual, untouched |
| Sections PASS | **14.6, 14.8, 14.9, 14.10 (both halves), 14.11 (execution half)** |
| TASK 2 | **All five items PASS** |
| RemoveAll | **Measured.** Everything removed but one running binary |
| Product defects found | **1** — mojibake in a shipped dialog. Cosmetic |
| Instrument defects found | **8**, all mine |
| Compute cost | ~5.5 hours, about **$0.55** |
| Fitness verdict | **None.** Box A is one of four |

## 1.2 The headline

**The two defects that made v1.4.3 a NO are fixed and proven on a clean install.**

* The kill switch genuinely stops the gateway and any running turn (`WR.3`), with
  the gateway confirmed UP beforehand by **both** readers, and it **refuses to
  claim success when it cannot verify** (`WR.4`) with a control proving the fault
  landed.
* `switch-provider.ps1` runs at all — the StrictMode death is gone, the firewall
  change lands, and the toolchain set stays untouched at 27.

**A third result falls out of the first:** section 14.6 VOIDed in v1.4.3 because
the only supported way to put the gateway down *was* the broken kill switch.
Fixing one made the other measurable. **Fixes compose; so do defects.**

## 1.3 The one product defect, and who found it

The `rename-agent.ps1` dialog renders every em dash as `â€"`. The file is UTF-8
**without a BOM**, and PowerShell 5.1 decodes a BOM-less `.ps1` as the ANSI
codepage.

**No automated phase in this suite could have found it.** It was found by the
operator reading a dialog during the by-hand pass. Swept as a class: **5 shipped
scripts BOM-less, 7 customer-visible occurrences across 2 of them.**

**This is the argument for keeping the by-hand pass.** It is the slowest,
least-automatable, most-often-deferred part of the matrix, and it produced the
only product finding of the entire box.

---

# PART 2 — THE PART THAT MATTERS: WHY MY INSTRUMENTS FAILED

Eight instrument defects. **Three would have produced false findings** — a phantom
dead gateway, a phantom broken send path, a phantom missing prompt. Each was
caught, but by the harness rather than by me.

## 2.1 The eight, root-caused into five patterns

| # | Defect | Pattern |
| --- | --- | --- |
| 1 | Read the gateway token from a path that does not exist | **A. Assumed an identifier** |
| 2 | Scored `Unauthorized` as "not blocked" (tested only for absence of a flag) | **B. Assertion cannot discriminate** |
| 3 | Asserted on unit name `clawfactory-chatgate`; the real one is `clawfactory-proxy` | **A. Assumed an identifier** |
| 4 | Measured the toolchain switch *after* `TC.9` had restored it | **C. Measured at the wrong time** |
| 5 | Used `Record` where `Register-Control` was required; phase had 0 controls | **B-adjacent. Wrong mechanism** |
| 6 | Searched the distro for `orchestrator-prompt.md`, a name that never exists there | **A. Assumed an identifier** |
| 7 | Used git's blob object id where SHA-256 of content was needed | **D. Wrong quantity** |
| 8 | Encoding-scope script mangled by the very encoding bug it measured | **E. Instrument subject to the defect** |

**Pattern A alone accounts for three of eight, and all three of the near-miss false
findings.** That is the single highest-value thing to fix in the next job card.

## 2.2 The one-sentence diagnosis

**Every one of the eight was a check that produced a verdict without measuring its
actual subject.**

That is the same sentence as the product defects this whole release cycle was about:
the kill switch printed success over commands that failed; `S.4` once printed
`0600 root:root` as a hardcoded literal; the Studio pin hashed a payload the
installer discards. **The project's characteristic defect reproduced itself inside
the tools built to detect it — four times in one session.**

## 2.3 What actually caught them

Worth naming, because these are the controls worth keeping:

1. **The phase runner's rule that a phase with zero registered controls cannot
   report a PASS.** Caught #5 outright.
2. **VOID-on-unmeasurable rather than FAIL-on-missing.** Caught #6 — the false
   ship-blocker — and is the single reason it never entered the record.
3. **PROMPT 15's "NAME THE REAL SUBJECT" clause.** Already existed, from an earlier
   violation of the same kind. I violated it anyway. **A rule that exists and is not
   applied is worth nothing**, which argues for making it a mechanical step rather
   than a principle.
4. **Reading code before running it.** Caught #7 before it ever executed.
5. **Checking `git status` instead of assuming a write happened.** Caught a heredoc
   that silently wrote nothing.

---

# PART 3 — WHAT TO PUT IN THE NEXT JOB CARD

## 3.1 Five new clauses, in priority order

These are drafted to be pasted directly into the next card. Each exists because of
a specific failure above.

### CLAUSE 1 — DISCOVER, DO NOT ASSUME. (Prevents 3 of the 8.)

```
Before any probe ASSERTS on a path, a unit name, a file name, a process name or a
config key, it must first DISCOVER that identifier on the box and PRINT what it
found. An assertion against a guessed identifier is not a measurement of the
product; it is a measurement of the guess.

Three specific traps this run hit, all avoidable this way:
  - a gateway token read from a path that does not exist -> every turn 401
  - `systemctl is-active` on a unit name that does not exist -> reports inactive,
    which is INDISTINGUISHABLE from a stopped service
  - a file searched for by its SOURCE name when the product delivers it under a
    DIFFERENT name

Where the product transforms a name between source and destination, the probe must
name the DESTINATION and say where that name came from. Read the installer or the
bootstrap script and quote the line that decides it.
```

### CLAUSE 2 — CLASSIFY, DO NOT TEST FOR ABSENCE.

```
A probe that decides a verdict by testing for the ABSENCE of a failure string will
pass when nothing happened at all. Every result must be classified into one of a
NAMED, MUTUALLY EXCLUSIVE set of states, and the state must be printed.

Not:   blocked = response does not contain '"blocked":true'
But:   state = MARKER_OK | BLOCKED | UNAUTHORIZED | EMPTY | OTHER

The success state must require a POSITIVE marker that appears nowhere else in the
probe's own output. This run scored an `Unauthorized` response as "not blocked"
because an auth error contains no blocked flag.
```

### CLAUSE 3 — STATE WHEN THE MEASUREMENT IS TAKEN.

```
Phases restore state at their end. A probe that runs afterwards measures the
RESTORED state, not the state that produced the reading it is investigating.

Any probe written to explain another phase's result must either run inside that
phase, or state explicitly which state it is observing and why that is still
informative. This run measured a toolchain switch AFTER the phase had restored it
and got an answer that could not settle the question.
```

### CLAUSE 4 — DECLARE PRECONDITIONS THAT PROMPT 15 ALREADY DECIDES.

```
PROMPT 15 states: if a phase needs the SMTP credential and it is absent, that
phase is VOID. `interim-v120-phase3.ps1` has no mechanism to apply that rule --
it declares no precondition, so it reported FAIL=7 on a box where nothing was
broken and nothing was configured.

Any phase whose subject depends on a configured credential must call
Require-Precondition on CREDENTIAL_PRESENT. A reader skimming FAIL=7 on the Guard 2
suite will conclude the approval-gated send path is broken. It is not.
```

### CLAUSE 5 — DO NOT FIX SHIPPED BYTES MID-VALIDATION.

```
If a defect is found in a shipped file, CARD IT AND CONTINUE. Do not fix it on the
box or in the repo during the run. Every measurement in the run is taken against
one artifact digest, and changing a shipped byte invalidates all of them --
including the bundled-bytes check that proves the box carries the committed bytes.

Fix in a separate commit, bump, rebuild, and re-validate. That is the premise this
entire cycle rests on: prior measurements do not transfer across a rebuild.
```

## 3.2 Two clauses worth ADDING TO PROMPT 15 permanently

Clauses 1 and 2 are not box-specific. They belong in the preamble beside "NAME THE
REAL SUBJECT" and "CALIBRATE BEFORE MEASURING", because they are the mechanical
form of those principles — and this session proves the principle alone does not
survive contact with a long run.

## 3.3 One build-gate recommendation

**Add a tenth pre-build gate: no shipped `.ps1` may contain a non-ASCII byte unless
it carries a UTF-8 BOM.**

Cheap, byte-level, canary-able in exactly the shape of the existing nine, and it
closes the only product defect box A found — as a class, permanently. The
interpolation gate added in v1.4.4 already parses every shipped script and is the
natural home.

---

# PART 4 — THE ACTUAL PROMPTS FOR BOXES B, C AND D

## 4.1 What each box is for

| Box | Install variant | Carries |
| --- | --- | --- |
| **B** | `-Provider later` | Matrix row 4, plus `PG.3f` |
| **C** | licence host blocked, prior artifact as control | Matrix row 2 |
| **D** | normal, uninstall is the subject | **TASK 2 in full** — the v1.4.2 debt |

**Box D is the important one.** Its change set has **never been measured on any
release**, and it is the only box that can turn row 14 and the three credential
VOIDs into real verdicts.

## 4.2 Recommended sequencing

**Run B and C first, in either order, and D last.**

Reasons, in order of weight:

1. **B and C are small.** Row 4 and row 2 are single-variant install checks. Each
   is a couple of hours with two operator touches. They bank quickly.
2. **`PG.3f` rides B or C for free.** Both install anyway; the Level 2 control
   costs a full install, which those boxes are already paying.
3. **D is the largest and most likely to surface something.** It carries seven
   sub-items including a fault-injected negative half and a reinstall. Going in
   with B and C already banked means a finding there does not also cost you rows
   2 and 4.
4. **D benefits from the harness fixes.** If clause 4's precondition fix lands
   before D runs, D closes row 14 and the credential VOIDs properly rather than
   reproducing `FAIL=7`.

**Consider combining B and C onto one session, two boxes.** They are both short,
neither destroys its install, and the operator touches are nearly identical. That
would make the remaining work two sessions rather than three.

## 4.3 Box D's card must say these things explicitly

```
CONFIGURE THE SMTP CREDENTIAL BEFORE THE GUARD 2 PHASE RUNS.

Three separate rows VOIDed on box A for one cause: no credential was configured.
Row 14 (the Guard 2 suite), G2.10, and S.4/S.4leak in the post-reboot pass. All
three become real verdicts on a box where the credential exists.

The credential is a deliberately KEPT throwaway. Do not ask for a new one and do
not ask for it to be revoked. The account and the panel path are already recorded.
Entering it is an OPERATOR step in Studio; it never enters a script, a transcript
or the model's context.

STILL ZERO OUTBOUND EMAIL unless the card explicitly authorises it. Test 3 and
test 6 write to a LOCAL SINK and are safe; the only transmitting path is card #198,
gated behind BOTH a present credential AND -ExpectRealCredential. Do not pass that
switch unless #198 is deliberately in scope.
```

And:

```
THE KEEP-LINUX BRANCH IS THE HEADLINE. Choose NO at the dialog.

Box A took the RemoveAll branch. The v1.4.2 change set lives ENTIRELY in the
keep-Linux branch, and RemoveAll exercises none of it. A box that takes RemoveAll
again has not measured what box D exists to measure.

Required: install, uninstall through the real dialog choosing NO, read back against
a HELD BEFORE-STATE, reinstall and confirm it completes, read the teardown log for
CLAWFACTORY_TEARDOWN_OK with a READBACK line showing units=0 sbin=0 enabled=0
left=[ ], the fault-injected negative half, and the next-boot check.

The before-state is what makes the after-state mean anything, and the reader needs
a control proving it can still detect something that IS present.
```

## 4.4 A carry-forward list for whichever box runs next

Small items box A could not close. Each is cheap on a box that is installing anyway:

* **`PG.3f`** — the installer's loud abort, via `-RunFullInstallControl`. Box B or C.
* **Section 14.11's CR census** — a per-file CR count on the shipped Windows-side
  `.ps1` files on the box. Box A proved they EXECUTE; it never counted their CRs
  separately.
* **`#261`** — needs a REPEATED-ATTEMPT measurement, not another single reading.
  Box A has one PASS pre-reboot and one post-reboot; the residual is about
  intermittency and two samples settle nothing.
* **`5d`** — either seed an entry from root tooling during staging, or rewrite the
  check to state its own precondition.

---

# PART 5 — PROCESS NOTES THAT WORKED, AND ONE THAT DID NOT

## 5.1 Worked, keep doing

**Naming a confound BEFORE dispatching.** Section 6.3 predicted that running rows
5–7 and 8–9 on one box could confound the toolchain rows. It did. Because it was
named in advance, it cost one re-run and was reported as a confound rather than
argued into one after the fact. **A prediction on the record is worth ten
explanations after.**

**Reading the by-hand checklist against reality before handing it over.** Check
`5d` expects a seeded entry no current driver places. Sent as written it would have
produced a **FAIL against correct behaviour**. Caught by comparing the checklist to
the operator's first screenshot. **That file has now had two stale expectations in
two runs.**

**Batching operator work 4–5 items at a time**, with expected strings quoted so the
operator matches text rather than judging correctness. One screenshot answered nine
separate checks.

**Committing after every phase.** The close-out was pushed ~15 times during the run.
An interruption at any point would have left an honest record.

**Deallocating at the handoff.** The box was parked overnight for well under a
dollar, and the operator was never the reason a VM was billing.

## 5.2 Did not work

**Writing new probes late in a long session.** Every one of the five day-two
instrument defects was in a probe written after hour four. The probes written
cold — the manifest generator's assertions, the classification logic — were sound;
the ones written in flow were not.

**Recommendation for the next card:**

```
Write every new probe BEFORE provisioning, and dry-run each one against a
known-answer target on the build machine. PROMPT 15 already says CALIBRATE BEFORE
MEASURING; this run did that for the sweep instrument and skipped it for four
on-box probes, and all four were defective.

A probe that cannot produce a known-correct result on a rigged input is not
permitted to report a result on a real one -- and "rigged input" includes a
synthetic file on the build machine, which costs nothing and needs no VM.
```

## 5.3 The honest summary of this session

**The product looked better than my instruments.** One cosmetic product defect
against eight instrument defects, three of which would have generated false
findings against correct behaviour.

That is not a comfortable sentence and it is the useful one. **The harness is doing
its job; the weak link is what gets written under time pressure inside a long run.**
The fix is mechanical clauses, dry-runs before provisioning, and fewer probes
authored in flow — not more care, which is what everyone promises and nobody
delivers at hour six.

---

# PART 6 — CARDS OWED

**From box A, five new:**

1. The **encoding class** — 5 BOM-less shipped scripts, 7 user-visible mojibake
   occurrences, plus the proposed tenth build gate.
2. **Phase 3 declares no precondition**, so it reports FAIL where PROMPT 15
   requires VOID.
3. **`Invoke-WslBashBlock` discards payload stdout**, so the toolchain guard cannot
   report that it checked — this made `WR.5` unobservable.
4. **The uninstaller does not name which elements it could not remove**, nor suggest
   closing ClawChat first.
5. **`MANUAL_CHECKS_studio.md` check `5d`** assumes a seeding step no driver performs.

**Sixth, lower priority:** six drivers carry stale `$VmName` defaults naming deleted
boxes. All fail safe; the right fix is a mandatory parameter, not a repoint.

**Closeable on box A evidence:** the kill-switch fix, and the `switch-provider.ps1`
fix.

**Staying open:** everything uninstall-scoped (box D), and `#261`.
