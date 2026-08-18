# ClawFactory Guard 3 rework: self-contained handoff

Written 2026-08-18 to be read by someone with **no access to the repo**. Every
measurement quoted here is reproduced inline rather than referenced, so this
document stands alone. The engineering close-out beside it
(`2026-08-18_guard3_rework_closeout.md`) carries the same findings with file
paths and commit hashes for someone who does have the repo.

---

## 0. Orientation, for a reader coming to this cold

ClawFactory is a Windows installer that sets up a sandboxed AI agent inside WSL
(Linux on Windows). The security model is that the agent runs as a specific Linux
user (uid 1000, `clawuser`) and a firewall rule set filters *by that uid*, so the
agent can only reach network destinations that have been explicitly allowed.

The firewall is nftables. It holds several named **address sets**:

- `@allowed_ipv4`: the AI model provider (Anthropic). Must always work, or the
  agent is bricked.
- `@read_fetch_ipv4`: web pages the user has explicitly allowed. Empty by default.
- `@toolchain_ipv4`: software sources (GitHub, npm). Governed by a user-facing
  on/off switch called the **toolchain toggle**.

The chain ends in a terminal `drop`, so anything not in an allowed set is refused.

**"Guard 3"** is the feature that gives the user control over those last two sets.

Three terms used throughout:

- **structural vs advisory**: a control the agent cannot influence, versus one it
  could. Marketing claims may only describe structural controls.
- **control (in the testing sense)**: a check that must produce a *known* result
  in the same run, proving the instrument works. If a control fails, the
  measurement beside it means nothing.
- **VOID**: a test verdict meaning "this was not measured", as distinct from
  pass or fail.

---

## 1. What this session was asked to do

Three tasks, in a forced order, each blocking the next:

0. **Verdict triage.** A previous session fixed the test harness so that a test
   recording an unreadable verdict is treated as VOID. That exposed ~50 existing
   test call sites recording words outside the allowed vocabulary. They had to be
   given real verdicts before any VM run, or the run would burn a machine
   producing voids.
1. **The chain-read defect.** Version 1.3.3 reportedly did not install on a clean
   machine. The diagnosis said the failing check could not distinguish "the
   firewall rule is missing" from "reading the firewall failed".
2. **TC.3.** With the toolchain toggle switched OFF, a real agent turn was
   refused. This was the actual blocker, and the job said to diagnose it by
   measurement and not to guess.

---

## 2. THE HEADLINE FINDING, which is not what the job expected

### 2.1 What was measured

A real agent turn was run three times on a freshly installed clean machine
(Azure VM `cfv-167`, build 1.3.4), while a logging rule recorded every packet the
firewall dropped for the agent's uid.

| Run | Toolchain toggle | Result | Duration | Packets dropped, and to where |
| --- | --- | --- | --- | --- |
| **CONTROL** | **ON**, 25 addresses loaded | **FAILED**, empty response | 301s | 78 to `160.79.104.10` |
| **SUBJECT** | **OFF**, 0 addresses loaded | **FAILED**, `{"error":{"message":"internal error","type":"api_error"}}` | 165s | 91 to `160.79.104.10` |
| **SECOND**, gateway not restarted | OFF | **FAILED** | 162s | 84 to `160.79.104.10` |

`160.79.104.10` resolves as **`api.anthropic.com`**, the AI model provider.

For contrast, the toolchain hosts resolve nowhere near it:
`api.github.com` → `140.82.114.6`; `registry.npmjs.org` → `104.16.x.34`.

### 2.2 What it means

**The toolchain toggle is exonerated.** The turn fails identically with the
toggle ON. The toggle does not govern the provider route at all, and the
product's own tool says so when you switch it off, in its own output:

> `[toolchain] backend=nftables toolchain=OFF addresses=0 (skill installation,
> GitHub and npm are denied; the provider route is untouched)`

**The real defect: on a clean install, the agent could not reach its own AI
model.** The address the gateway dials for the model is not present in the
provider allow-list `@allowed_ipv4`, so it falls through to the terminal drop.
Three turns, ten minutes, all blocked by the machine's own firewall.

**The dependency is per-turn**, not once per gateway start: the third turn, with
the gateway deliberately not restarted, failed the same way to the same address.

### 2.3 Why the control failing is the result, not a spoiled run

The control turn (toggle ON) was supposed to succeed and thereby prove the
subject's failure was caused by the toggle. It failed instead, in **the same way and on the same address**.

That does more than void the attribution. It inverts it: from "the toggle broke
the turn" to "something else broke the turn and the toggle was never implicated".
Running only the subject would have confirmed the obvious and wrong answer.

This is very likely what happened in the earlier session that produced the TC.3
report: it observed a turn failing with the toggle off and attributed it to the
toggle. The ~4.5 minute stall reported there matches the 301s and 165s timeouts
measured here. If no control run with the toggle ON was performed, nothing was
holding that attribution up.

### 2.4 What was NOT established, stated plainly

**Why the provider address is missing from the allow-list was not determined.**
Two candidates, neither tested:

1. The refresh job resolved a *different* address than the one the gateway later
   dialled. Anthropic publishes several addresses, and an nftables address set
   holds fixed addresses, so it cannot follow a name that moves. This would make
   the failure **intermittent and environment-dependent**, which is the nasty
   case.
2. The refresh silently failed to populate the set at all.

Both are answerable in one short VM run. Neither was run.

**Severity:** this should be treated as a ship-blocker until explained. It is
more serious than the toggle question it displaced. It is also **not known**
whether it affects every install or was specific to that machine, and that is
exactly what the untested candidates above decide.

---

## 3. What was completed and proven

### 3.1 Task 0, the verdict triage: DONE

53 distinct call sites carrying 61 out-of-vocabulary verdicts, all given real
verdicts by reading what each check actually measured.

| Measurement | Before | After |
| --- | --- | --- |
| Out-of-vocabulary verdict occurrences | 61 | **0** |
| Distinct sites affected | 53 | **0** |
| Distinct verdict words emitted | 17 | **4** (PASS/FAIL/VOID/INFO) |
| Malformed rows in a live run through the real recorder | n/a | **0**, with a negative control that fired |
| Harness self-test | 15/15 | **15/15** |

**Two of the four labelled guesses handed to this session were wrong**, and the
reason generalises: *the word recorded at a site does not determine the verdict,
the check does.* `MEASURED-BYPASS` marks an expected, documented limitation at
five sites (where recording it as a failure would fail a test suite over
intended behaviour) and a genuine agent-reachable defect at a sixth. Same word,
opposite verdicts.

**Three sites turned out to be defects in the tests themselves:**

- One test scored **PASS when the agent discovered the email command**, but the
  product's own documentation says the agent is deliberately not told that
  command exists, and that non-discovery *is* the security property. The test was
  rewarding the outcome the product treats as notable. Polarity inverted.
- One test counted the whole pending queue, so it could never distinguish "our
  request is stuck" from "something unrelated was queued".
- One test searched a packed archive for the *absence* of something, with nothing
  proving the archive was readable, so an unreadable archive would have scored
  as clean. A searchability control was added.

### 3.2 Task 1, the chain-read defect: FIXED AND PROVEN

**The measurement came first, and it contradicts the diagnosis that was handed
over.** That diagnosis claimed that if these transient failures were real, the
firewall refresh service "has been failing intermittently on every box that has
run for a while".

Measured on a live long-running machine:

- refresh service: `Result=success`, `NRestarts=0`, **34 runs across 15 boots**,
  **zero** failure entries in 150 log lines
- control A (log contains entries for this service): 150, non-zero as required
- control B (same query against a service that does not exist): 0, as required
- **300 consecutive firewall reads at rest: 0 failures**, with a control that
  failed as required, proving the failure counter worked

So the read is reliable at rest and the "chronic intermittent failure" claim is
not supported.

**The fix:** one firewall read, retried on a bounded poll, from which every check
is made, replacing four single-look checks including two separate reads twelve
lines apart for two rules that physically cannot differ. The failure message now
names four things the old one named none of: whether the chain was *readable*
(reported separately from whether the rule was *present*), the exact error text,
how many attempts over how long, and the full rule set text.

**Proven on a real clean install:**

| Test | Result |
| --- | --- |
| Install completes clean | **PASS** |
| Concurrent firewall load during the check | **PASS**, rc=0 in 1s under 40 full rule-set re-applies |
| CONTROL: exceed the retry budget | **PASS**, correctly reporting the rule *absent*, explicitly not a read failure |
| CONTROL: make the read itself impossible | **PASS**, correctly reporting a *read* failure with the real error text, and makes no claim about any rule |

Those last two are the whole point: the same code, given two different faults,
now produces two different correct diagnoses. Before the change both produced one
message, and that message asserted the wrong one.

### 3.3 Two defects caught in my own work, recorded rather than buried

**Before shipping:** the retry budgets were first written at 30 attempts each.
The service they run under has a 90-second startup limit, so a genuinely broken
machine would have spent 30+30+30 there and been killed by the timeout, turning
a precise "this rule is missing, here is the error" into a useless "start
operation timed out". Worse than the check it replaced. Bounded at 5 instead;
worst case fell from 64s to 9s with no loss of detail. Nothing about this would
have shown up in testing, because the code worked exactly as specified. The
specification was wrong.

**During testing:** one test surprised me by failing, and the specification was
wrong again rather than the code. The tripwire refused to "ride out" a deleted
firewall rule, failing in 1 second. That is *correct*, because a deleted rule is exactly
the tampering it exists to catch, and retrying would delay detection of real
tampering. The principle is now written into the file so nobody "fixes" the
apparent inconsistency later: **retry reads, never retry findings.** No behaviour
was changed, only the comment.

A related result worth keeping: 40 concurrent full rule-set re-applies produced
**zero** false findings, because the firewall load is a single atomic
transaction with no window where the rules are momentarily absent. So contention
does not manufacture a missing rule, which leaves a failed *read* as the
surviving explanation for the original install failure, which is precisely what the new
message can now distinguish and the old one could not.

---

## 4. Judgement calls made without asking

- **One VM focused on TC.3, rather than the full two-machine plan.** The job
  itself said that naming the TC.3 dependency precisely is a successful session
  even if nothing ships. This proved right: TC.3 was not a toolchain problem at
  all, so the remaining tasks would have been work against a premise that has now
  moved.
- **The VM was destroyed rather than kept.** The open question needs a fresh
  install to answer honestly anyway, and a kept machine bills while a report is
  written.
- **The tripwire was NOT changed when a test surprised me.** Making it retry
  would have been a regression dressed as a fix.
- **No new build after 1.3.4.** The only later change is a source comment.

---

## 5. What is open, ranked

1. **Why the AI provider's address is missing from the firewall allow-list.**
   Top item, above everything remaining from the original job. Needs one short
   VM run: compare what the refresh job put in the list against what the gateway
   actually dials, and confirm the refresh populated at all.
2. **The user-facing panel copy.** Deliberately untouched. The job said not to
   touch it until the TC.3 outcome was known; the outcome moved the premise, so
   the planned rename (which assumed the toggle was at fault) is now an open
   question rather than a settled one.
3. **Two deferred manual checks** from an earlier session: the Studio panel
   checks by hand, and a set of tests repeated after a reboot. Neither has ever
   passed and neither should be recorded as passing.
4. **A second clean-install validation** of the shipping build. Not run.

**Unchanged and still true:** nothing in this session made the agent able to
reach anything it could not reach before. The only behavioural changes are
retries on failed reads and a better error path when a resolver fails.

---

## 6. Housekeeping

**Build 1.3.4** was produced and signed, all seven build gates passing.
Unsigned digest `df1d89210cf40b5d3721f8ea43283f3344cc093301c651d16932f92b9b5fb642`
(440,591,811 bytes); signed digest
`ee6a5cd0232d7eb039182fe45e967cf2407e4ccd70f2e06540e06c93b89b5214`
(440,607,456 bytes), Authenticode Valid. It installs clean. It is **not**
validated beyond the tests listed in 3.2, and the provider-route problem in
section 2 was found *on* it.

**Cost and cleanup.** One VM used and destroyed. Licence slot released
(`Machine deactivated successfully`). All five child resources deleted
individually and verified by an unfiltered listing, not by searching for the
machine name. Zero VMs left running anywhere in the subscription.

**A stale instruction in the job**, noted for whoever maintains these prompts:
it asked for the deletion of a superseded file that does not exist anywhere on
the machine. Nothing was deleted.
