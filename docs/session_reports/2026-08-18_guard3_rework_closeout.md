# Close-out: Guard 3 rework. Verdict triage, the chain-read defect, and the TC.3 blocker

Session 2026-08-18. Dispatch card #256. Input artifact 1.3.3, signed
`5bef35dc3a4a944583470bdb0afe893d413d96eafcdf1df0ba66311a417522ab`, verified byte
for byte on disk before anything was changed.

**STATUS: IN PROGRESS.** This file is written before the VM phase completes so
that a close-out exists whatever happens to the session. Sections marked OWED are
not done. If this line is still present, the session ended early and the OWED
items are genuinely outstanding.

---

## 1. The two answers worth reading first

**The verdict triage is done and proven, and two of the card's four labelled
guesses were wrong.** Not because the guesses were careless, but because the word
recorded at a call site does not determine the verdict: the check does.
`MEASURED-BYPASS` means an expected, documented limit at five sites and an
agent-reachable defect at a sixth. Same word, opposite verdicts.

**The chain-read measurement contradicts card #255's highest-severity claim.**
That card said that if transient read failures are real, then
`clawfactory-allow-providers.service` "has been failing intermittently on every
box that has run for a while". Measured on a live box: 34 runs across 15 boots,
zero failures, plus 300 consecutive at-rest chain reads with zero failures, both
with controls that fired. At rest, the read is reliable. That bounds the rate; it
does not explain cfv-165, and the install-window contention hypothesis survives.

---

## 2. Pre-flight

**Prompt library.** PROMPT 15 is present at
`C:\Users\bmcki\OneDrive\Desktop\Claude Prompts\FrontierAI_CC_Prompt_Library.md`
line 645, carrying the close-out gate, the four pre-flight checks, the
instruction-challenge clause, the measurement and shell rules, the handoff cards,
the resource ledger and the credential rules. Not stale. Card #255 reported it
absent, and it has since been added, which removes the ambiguity that card worked
around.

**One instruction was stale.** The job says to delete
`CC_v1_Guard3_Rework_InstallRace_and_TC3_v1.md`. That file does not exist
anywhere on this machine; a search of the whole user profile returns nothing.
Nothing was deleted and nothing needed to be.

**Dependency census and failure-mode walk.** Both run, and the failure-mode walk
caught a real defect in my own fix before it shipped. See 4.4.

---

## 3. Task 0: the verdict triage

### 3.1 The inventory was redone rather than inherited

Card #255 reported roughly 50 sites from an AST parse. Re-parsing found **53
distinct sites and 61 occurrences**, because several sites carry two
out-of-vocabulary branches, and a per-call inventory counts those once.

The parse extracts only string literals in **value position**, where the parent
node is a `CommandExpressionAst`. That distinction is the whole reason this is an
AST walk: in `$(if ($o -match 'REVIEW') { 'PASS' })` the word `REVIEW` is a regex
operand, not a verdict, and a text search reports it.

**Calibrated before it was trusted**, per instruction I, against a canary built
to look like what I was afraid of missing rather than what I already knew was
there:

| Canary | Shape | Found |
| --- | --- | --- |
| C.2 | hyphenated verdict in an `elseif`, third branch | yes |
| C.3 | out-of-vocabulary word in a `switch` default | yes |
| C.5 | bare literal, no conditional | yes |
| C.6 | verdict passed by variable | yes |
| C.1 | DECOY: `REVIEW` as a `-match` operand | correctly ignored |
| C.4 | DECOY: clean all-vocabulary conditional | correctly ignored |
| C.7 | DECOY: lowercase `pass`, which `Record` upcases | correctly ignored |

### 3.2 Two of the card's guesses were wrong

The card offered guesses "as labelled guesses to shorten the work, not as a
mapping to apply mechanically". Applied mechanically, two would have caused harm.

**`MEASURED-BYPASS` does not uniformly want `FAIL`.** At `G1.2b` through `G1.2e`
and `G1.4` the code beside the call already says a bypass is the documented limit
of PATH interception in a non-gateway shell, and `G1.4`'s own evidence string
reads "not a regression". Recording `FAIL` would fail a phase on behaviour the
product never claimed to prevent. Those are `INFO`, with the measured outcome
moved into the evidence so nothing is lost. At `G1.2g` the same word means
something else entirely, and the evidence says so: "an agent-reachable bypass"
from inside the agent's own tool. That one is `FAIL`.

**`BASELINE` is not `INFO` in both directions.** `BASELINE-UNEXPECTED` means the
baseline that section 4's comparison rests on was not established, which is
`VOID`.

`NOTE`, `WARN`, `UNTESTED` and `BLOCKED` did land close to where the card
guessed, though `WARN` at `P1.0` went to `INFO` rather than `VOID`: its success
path is also `INFO`, no claim in the phase is contingent on it, and box
cleanliness is established by VM provenance rather than by that probe. Voiding a
phase over a `Get-CimInstance` hiccup is a false alarm about the product.

### 3.3 Three sites were findings about the phase, not labelling

Per the job: where a check turns out to be measuring nothing, say so.

**`G2.199a` had its polarity inverted against the shipped product decision.** It
recorded `PASS` when the agent DISCOVERED `clawfactory-send`.
`docs/reference/EMAIL_APPROVAL.md` section 2 says the agent is deliberately not
told the command exists, and that this is "a security property rather than a
missing feature". Under the shipped decision, discovery is the noteworthy event.
Both branches are now `INFO`. The real security assertion in that pair is
`G2.199b`, that the agent does not improvise another transport, which is a
genuine `PASS`/`FAIL` and was left untouched.

**`PNL.7b` cannot answer its own question.** It counts the whole pending queue,
so a nonzero count cannot separate "our approved request is still pending", a
defect, from "something else was queued", not a defect. Zero is a real `PASS`;
anything else is `VOID` and says why. To make it `FAIL`-capable it must count its
own `requestId`.

**`G1.7s` was a false clean.** It searched `app.asar` for an ABSENCE with nothing
proving the archive was searchable, so a `Select-String` that could not read it
returns zero hits and reads as "no purge surface". A searchability control was
added, matching the house pattern already at `PNL.8ctl2`. A nonzero hit count is
now `VOID` rather than `FAIL`, because a text scan names candidates to read, not
a purge surface.

### 3.4 Two liveness gates, because a dead probe looked like a passing product

`G2.4`/`G2.5`/`G2.5b`/`G2.6`/`G2.7` all read one probe body, and
`G2B.4`/`G2B.5`/`G2B.5b`/`G2B.6`/`G2B.7` read another. Every verdict there is a
search for an expected refusal string, so a probe that died early produced the
same empty output as a broker that refused nothing, and the old `REVIEW` branches
collapsed the two. Both clusters now gate on a marker emitted by the last test in
the body, and void when it is absent.

Where an unread value and a wrong value shared a branch they were split, because
they have different owners: `PNL.3b`, `PNL.8b`, `G2.2`, `G2.6`, `G2B.2`,
`G2B.3c`, `S.5`.

### 3.5 Malformed-row counts, before and after

| Measurement | Before | After |
| --- | --- | --- |
| Out-of-vocabulary verdict literals (occurrences) | 61 | 0 |
| Distinct call sites affected | 53 | 0 |
| Fall-through verdict expressions (`if` with no `else`, `switch` with no `default`) | 0 | 0 |
| Distinct verdict literals emitted by `validation/` | 17 | 4 |
| Malformed rows in a dry run through the real `Record` | n/a | 0, with the negative control firing |
| `harness-selftest.ps1` | 15/15 | 15/15 |
| Files in `validation/` with parse errors | 0 | 0 |

The one apparent remainder, `interim-v120-phase6.ps1:113`, passes `$verdict1`,
which is computed one line earlier as `VOID`/`PASS`/`FAIL`. It is a limitation of
static reading, not a defect, and was resolved by reading it.

**A literal sweep cannot see the card #254 shape**, because the defect there is a
branch producing NO literal at all. A second AST pass looked structurally for
`if` without `else` and `switch` without `default` in verdict position,
calibrated against two more canaries carrying exactly those shapes, and found
zero in `validation/` both before and after.

**The triage was executed, not just diffed.** Every verdict literal the phases
can now emit was fed through the real `Record` in the real `phaselib`: 4 distinct
literals, all countable, 0 malformed, with a negative control (`REVIEW`) that
fired and was counted malformed. Without that control firing the zero would prove
nothing.

Commit `034f6b8`.

---

## 4. Task 1: the chain-read defect

### 4.1 The measurement, which came before the fix

Card #255 section 3.6 asked for this first, and it changes what the fix is
insurance against.

**On a live ClawFactory box with real history:**

| Measurement | Result |
| --- | --- |
| `clawfactory-allow-providers.service` `is-failed` | `inactive`, `Result=success`, `NRestarts=0` |
| Runs recorded in the journal | 34, across 15 boots, 150 journal lines |
| Failure lines ever (`Failed with result`, `fw-assert FAIL`, `cannot read chain`, `has drifted`) | **0** |
| CONTROL A: journal has any entry for this unit | 150, nonzero as required |
| CONTROL B: same query against a unit that does not exist | 0, as required |
| 300 consecutive at-rest `nft list chain` reads | **0 failures** |
| CONTROL: the same capture against a nonexistent chain | rc=1 with real stderr, so the counter works |

**An honest caveat, found by checking rather than assuming.** The assert
installed on that box is an OLDER 97-line build that does not mention the Guard 3
sets, so it is not the current file. But its **line 49 is byte identical** to the
single-look chain read under investigation, and it is wired `ExecStartPost` with
`ignore_errors=no`, most recently exiting status 0. So the measurement is valid
for the specific construction being diagnosed, and not for the Guard 3 checks
layered above it.

**What this settles and what it does not.** It settles that the read is reliable
at rest, and therefore that card #255's claim of chronic intermittent failure on
long-running boxes is not supported. It does **not** settle cfv-165. Whether that
was a failed listing or an absent rule is still inference, and converting it
needs the VM, because the hypothesis that survives is contention specific to the
install window, when three timers are enabled `--now` and the provider refresh
fires at `OnBootSec=30s`.

### 4.2 The fix

One chain read, retried, from which every assertion is made, replacing four
single-look checks that included two separate listings twelve lines apart for two
rules that cannot differ. Bounded poll on the CONDITION, never on "the grep
succeeded", matching the house pattern at `install-send.sh:198` and
`install-quarantine.sh:148`. A healthy box pays one iteration.

The failure message now names all four things the old one named none of:

1. whether the chain was READABLE, reported separately from whether the rule was
   present, as two different failures with different owners
2. the `nft` exit status and its stderr
3. how many attempts over how long
4. the full chain text from the final attempt

`fw-assert.sh` gets the same treatment and is the higher-severity surface even
though the install failure is the one that got noticed, because it runs forever
on customer machines on a five-hourly timer. Its chain read additionally now
requires a NON-EMPTY capture: an empty string with exit 0 would have passed every
check below it and reported a clean shape over nothing at all.

`install-read-fetch.sh:118` had the same swallowed-stderr shape, where a resolver
that failed to run left `MINE` empty and aborted the install claiming host-list
DRIFT, blaming the wrong file. The resolver now runs apart from the pipeline that
reshapes its output, keeps stderr, and reports a failed or empty read as what it
is.

### 4.3 Proven in both directions before any VM

| Direction | Result |
| --- | --- |
| Installer block, live chain (box genuinely lacks the Guard 3 sets) | reports the ABSENT branch, prints the full chain text, names each rule separately, 30 attempts over 32s |
| Installer block, defect injected (same code pointed at a nonexistent table) | reports a READ failure with nft's real stderr, and claims nothing about any rule |
| `fw-assert.sh`, live chain | chain read succeeds on attempt 1, then honest absent findings carrying nft stderr |
| `fw-assert.sh`, defect injected | READ failure, real stderr, attempts and elapsed named, `bytes returned 0` |
| Injection proven to have LANDED | reference counts checked, not assumed: 5 and 4 rewritten, 0 real references remaining |
| `bash -n` on all four touched shell files | clean |

### 4.4 What the failure-mode walk caught, before it shipped

The set checks were first written at 30 attempts, matching the chain read.
`clawfactory-allow-providers.service` is `Type=oneshot` with **no
`TimeoutStartSec`**, so systemd's 90s default covers `ExecStart` and
`ExecStartPost` together. A box genuinely missing both sets would have spent
30 + 30 + 30 there and been **killed by the start timeout**, turning a precise
"set X is missing, nft said Y" into "start operation timed out". That is a worse
diagnostic than the single-look check being replaced.

Set checks are bounded at 5, which is sound because the chain read has already
proved the table readable by then. Measured: worst case fell from 64s to 9s with
the diagnostics unchanged.

This is the pre-flight earning its keep. Nothing about it would have shown up in
testing, because the fix works exactly as specified; it is the specification that
was wrong.

Commit `29f683e`.

### 4.5 OWED: the on-VM proof

Not yet run. A clean install proves nothing on its own, because the unfixed
artifact also installed cleanly once. Owed: delay held inside the bound,
concurrent `nft` load during the assert, and the bound-exceeded control on a real
installed box.

---

## 5. Build

**1.3.4**, all seven gates green (soul, bundle at 34 resources, studio, version,
persona, workspace-soul, rootfs).

| Field | Value |
| --- | --- |
| Unsigned digest (the ledger row) | `df1d89210cf40b5d3721f8ea43283f3344cc093301c651d16932f92b9b5fb642` |
| Unsigned bytes | 440591811 |
| Signed digest | `ee6a5cd0232d7eb039182fe45e967cf2407e4ccd70f2e06540e06c93b89b5214` |
| Signed bytes | 440607456 |
| Authenticode | Valid |

The phase 1 version pin moved with it, because that pin is re-derived on the VM
and compared; leaving it at 1.3.3 would have failed the install validation for a
reason unrelated to the install. `released-versions.tsv` committed with the
build. Commit `f84732a`.

---

## 6. Resource ledger

Starting state of `clawfactory-validation`, unfiltered, before anything was
provisioned: the storage account `clawfactoryvalc467`, the VNET `bake-vmVNET`,
and the two baseline images. Nothing else. No prior FAIL VMs, no orphan disks,
NICs, public IPs or NSGs to sweep.

`cfv-167` provisioned for this session (`Standard_D2s_v4`,
`clawfactory-win11-baseline-v2`, public IP `20.98.94.218`).

---

## 7. OWED

- **Task 1 on-VM proof.** Section 4.5.
- **Task 2, TC.3 isolation.** Not started. The isolation method is designed and
  written: a log rule inserted immediately before the terminal drop, because a
  packet capture is the WRONG instrument here (nft's output filter hook drops
  before the device layer, so tcpdump would show a clean nothing for exactly the
  case under investigation) and conntrack is no better (a dropped SYN never
  becomes a tracked connection). Calibration against a known-dropped destination
  is built in and gates the subject run.
- **Task 3, panel copy.** Deliberately not touched, per the job: the copy depends
  on the TC.3 outcome.
- **Task 4, the two #245 deferrals.** `MANUAL.*` and `TC.*.POSTREBOOT`.
- **VM2, clean-install validation of the shipping artifact.**

## 8. Git

Three commits on `main`, pushed: `034f6b8` (verdict triage), `29f683e`
(chain-read fix), `f84732a` (build 1.3.4 and ledger). No tag, per the job.
Studio untouched, so nothing to push there.
