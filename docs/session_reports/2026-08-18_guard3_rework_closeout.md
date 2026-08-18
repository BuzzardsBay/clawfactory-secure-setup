# Close-out: Guard 3 rework. Verdict triage, the chain-read defect, and the TC.3 blocker

Session 2026-08-18. Dispatch card #256. Input artifact 1.3.3, signed
`5bef35dc3a4a944583470bdb0afe893d413d96eafcdf1df0ba66311a417522ab`, verified byte
for byte on disk before anything was changed.

**STATUS: COMPLETE for tasks 0, 1 and 2. Tasks 3 and 4 not started, deliberately
and by the job's own decision rule.** Section 9 says what is owed and why.

---

## 1. The three answers worth reading first

**TC.3 is outcome C, and the toolchain toggle is exonerated.** With the toggle
OFF a real agent turn failed and 91 packets were dropped to `160.79.104.10`.
With the toggle ON, the control turn **also failed**, dropping 78 packets to the
**same address**. `160.79.104.10` is `api.anthropic.com`, the AI provider, which
the toolchain toggle explicitly does not govern and which `fetchctl` itself
describes as "the provider route is untouched". So the turn does not fail because
of the toggle. It fails because the address the gateway dials for the model is
not in `@allowed_ipv4` and hits the terminal drop. The card #245 inference, that
"the stall is downstream in the gateway", pointed at the wrong subsystem.

**The control did not fire, and that is the finding rather than a spoiled run.**
A control that fails in the same run voids the attribution it was there to
support, and here it does more: because it failed the SAME way, on the SAME
address, it converts "the toggle broke the turn" into "something else broke the
turn and the toggle was never implicated". Had I run only the subject, the
obvious and wrong conclusion was sitting right there.

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

### 4.5 The on-VM proof, on cfv-167

1.3.4 installed clean on a fresh box: `INSTALLER_DONE=success`, with all three
accepts and all three sets present afterwards. That is test 1, and on its own it
proves nothing, because the unfixed artifact also installed cleanly once. The
injected directions are what matter.

| Test | Result |
| --- | --- |
| 1. Install completes clean | **PASS.** `INSTALLER_DONE=success`; chain carries all three 443-scoped accepts, all three sets present |
| 2. Concurrent `nft` load during the assert | **PASS.** rc=0 in 1s while 40 full re-applies of `/etc/nftables.conf` hammered the same table |
| 3. CONTROL, exceed the bound | **PASS.** rc=1, `SAYS_ACCEPT_MISSING=1`, `SAYS_CANNOT_READ=0`. Chain readable, rule genuinely absent, and it said exactly that |
| 4. CONTROL, unreadable chain | **PASS.** rc=1, `SAYS_CANNOT_READ=1`, `CARRIES_NFT_STDERR=1`, 30 attempts over 30s, `bytes returned 0`, and no claim about any rule. Injection proven landed: 5 references rewritten, 0 real remaining |

Tests 3 and 4 together are the whole point of the fix: the same script, given two
different faults, produces two different and correct diagnoses. Before this
change both produced the same message, and that message asserted the wrong one.

**Test 1's delay-inside-the-bound direction did not behave as I specified it, and
the specification was wrong rather than the code.** With the toolchain accept
deleted and restored 5s later, `fw-assert` failed in 1s instead of riding it out.
I had written the expectation as "must ride it out". That is wrong for a
tripwire: a deleted accept is precisely the drift it exists to catch, and
polling would be tamper TOLERANCE, delaying detection of real tampering.

The principle, now written into the file so the apparent inconsistency is not
"fixed" later: **retry reads, never retry findings.** The chain read and the set
checks retry because they are syscalls that can fail transiently and tell you
nothing when they do. The shape checks are greps over text already in hand, with
no read left to fail. The INSTALLER is the opposite case and polls the accepts on
purpose, because during install the timers are racing and a transient absence is
a read problem rather than tampering.

Test 2 also quietly settles card #255's inference 2. Forty concurrent full
re-applies produced **zero** false findings, because `nft -f` is a single atomic
netlink transaction and presents no window in which the chain exists without its
rules. So contention does not manufacture a missing rule. Combined with 4.1, the
surviving explanation for cfv-165 is a failed READ, which is exactly what the new
message can now distinguish, and what the old one could not.

**A defect in my own probe, recorded rather than quietly corrected.** The
`INJECTION_LANDED_ACCEPT_GONE=0` line reads as a failed injection and is the
opposite: 0 matching lines after deleting the rule IS the proof it landed. The
label was inverted. It did not affect any verdict, but a reader of the raw output
would misread it.

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

## 7. Task 2: TC.3, isolated by measurement

### 7.1 The instrument, and why the two obvious ones are wrong

A packet capture cannot see this. nft's output filter hook drops the packet
BEFORE it reaches the device layer, so `tcpdump` reports a clean nothing for
exactly the case under investigation, which would read as "not a network
problem" and send the next session after the wrong subsystem. conntrack is no
better: a dropped SYN never becomes a tracked connection. What does see it is the
ruleset, so a rate-limited `log` rule was inserted immediately before the
terminal drop, scoped to uid 1000, and the kernel names the destination.

**Calibrated first, and the calibration gated the subject.** The rule was pointed
at `example.org`, which is in no allowlist and must be dropped. It was named,
`CALIBRATION OK`. Had it not been, the probe was written to refuse to run the
subject at all, because a null result from an uncalibrated instrument is
uninterpretable and would have read as "no network dependency".

### 7.2 What was measured

| Run | Toggle | Turn | Seconds | Packets dropped, and to where |
| --- | --- | --- | --- | --- |
| CONTROL | **ON**, 25 addresses in the set | **FAILED**, empty body | 301 | 78 to `160.79.104.10` |
| SUBJECT | **OFF**, 0 addresses in the set | **FAILED**, `{"error":{"message":"internal error"}}` | 165 | 91 to `160.79.104.10` |
| SECOND, no gateway restart | OFF | **FAILED** | 162 | 84 to `160.79.104.10` |

`160.79.104.10` is `api.anthropic.com`, verified by resolution. For contrast the
toolchain hosts resolve elsewhere entirely: `api.github.com` to `140.82.114.6`,
`registry.npmjs.org` into `104.16.x.34`.

### 7.3 The answer, and which outcome applies

**Outcome C.** The block is real and it is a network block, but not on anything
the toolchain toggle governs. The gateway cannot reach the model provider,
because the address it dials is not in `@allowed_ipv4` and falls through to the
terminal drop. The toggle is exonerated: the turn fails identically with it ON,
and `fetchctl` correctly reports "the provider route is untouched" when switching
it off.

Per the job's decision rule for C: stop and report, ship tasks 0 and 1, and card
TC.3 with the isolation evidence. The 4.1 diagnosis was wrong and a fix aimed at
the toolchain list would have been aimed at the wrong subsystem.

**Per turn or per gateway start:** per turn. The third turn, with the gateway not
restarted, failed the same way with the same destination.

**This probably explains cfv-166's original observation.** That run saw a turn
fail with the toggle off and attributed it to the toggle. The 4.5 minute stall
reported there matches the 301s and 165s timeouts seen here. If no control turn
with the toggle ON was run, the attribution had nothing holding it up.

### 7.4 What this does NOT establish, stated because it matters

I did not determine WHY the provider address is missing from `@allowed_ipv4`.
The candidates are that the refresh resolved a different address than the one the
gateway later dialled (Anthropic publishes several, and an address set cannot
follow that), or that the refresh silently did not populate. Both are testable in
one short VM run and neither was run here.

**This is more serious than the toggle question it displaced.** On a clean 1.3.4
install the agent could not reach its own model on any of three turns over ten
minutes. That should be treated as a ship-blocker until explained, and it is not
the blocker the work package expected to find.

## 8. Judgement calls, and the reasoning behind them

Recorded because the operator asked for reasoning rather than questions.

**One VM, TC.3 first, rather than the full two-VM plan.** The job says a session
that triages the verdicts, fixes the chain read and precisely names the TC.3
dependency is a successful session even if the toggle does not ship. With finite
budget, naming the blocker beat validating copy that the blocker might change.
It was the right call: TC.3 turned out not to be a toolchain problem at all, so
tasks 3 and 4 would have been work against a premise that has now moved.

**The VM was torn down rather than kept for the provider follow-up.** The
question in 7.4 needs a fresh install to answer honestly anyway, and a kept VM
bills while a session writes its close-out. One VM once ran 64 hours for nothing.

**`fw-assert` was NOT changed when test 1 surprised me.** The temptation was to
make it poll the accepts like the installer does. That would have been a
regression dressed as a fix: it would delay detection of exactly the tampering
the tripwire exists to catch. A comment was added instead, because the next
reader will see the same apparent inconsistency and reach for the same wrong fix.

**No 1.3.5 build.** Nothing shipped after 1.3.4 that changes installed behaviour;
the only later edit is a comment in `fw-assert.sh`. Bumping to consume a version
number for a comment would waste a ledger row.

## 9. OWED, and none of it silently

- **The provider-route root cause, 7.4.** This is now the top item, above
  anything remaining from the original work package.
- **Task 3, panel copy.** Not touched, correctly: the job says not to touch it
  until the TC.3 outcome is known, and the outcome moved the premise. Under
  outcome C the copy question is now open rather than answered, because the
  control being renamed was predicated on outcome A.
- **Task 4, the two #245 deferrals.** `MANUAL.*` and `TC.*.POSTREBOOT`. Neither
  was recorded as a pass and neither became one.
- **VM2, clean-install validation of the shipping artifact.** Not run.
- **The ratified claim sentence** was not touched, so it is unchanged. Nothing in
  this session made the agent reach anything it could not reach before; the only
  behavioural changes are retries on reads and a resolver error path.
- **Test table items 5 to 11** from the work package: not run.

## 10. Resource ledger, closing state

Licence slot released: `Machine deactivated successfully` for machine_id
`ff9f7887-e31b-4f8e-8656-08df4e6385de`. `cfv-167` and all five child resources
deleted, each `rc=0`, NIC first. Unfiltered resource list shows exactly the
expected residual: the storage account, the VNET and the two baseline images.
Zero VMs in the subscription. Verified by an unfiltered list, not a grep for the
VM name.

## 11. Git

Commits on `main`: `034f6b8` (verdict triage), `29f683e` (chain-read fix),
`f84732a` (build 1.3.4 and ledger), `4203aaa` (interim close-out), plus this
close-out and the `fw-assert` comment. No tag, per the job. Studio untouched, so
nothing to push there.
