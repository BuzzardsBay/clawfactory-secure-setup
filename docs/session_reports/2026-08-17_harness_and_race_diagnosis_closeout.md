# Close-out: the harness empty-verdict gap, and the install race diagnosis

Session date 2026-08-17. Build machine only. Dispatch card 255. Repo at `913548e`
on entry.

No VM was created. No Azure call of any kind was made. Nothing was built,
compiled, signed or installed. `setup.ps1` and every shipped resource were read
and not written.

This is a carve-out: task 1 and section 3.1 of
`CC_v1_Guard3_Rework_InstallRace_and_TC3_v1.md`. That prompt remains valid and
runs next. This document is its input.

---

## 1. The two answers, in one place

**Task 1 is DONE and proven.** The runner no longer counts an unreadable verdict
as nothing. The self-test went from 10/10 to 15/15, and the new checks were
confirmed to discriminate by neutering the guard and watching exactly the three
new assertions fail.

**Task 2 is DIAGNOSED, not fixed, as instructed.** The headline, which is the
answer that scopes the next session:

> **The race is not one accept. It is three accepts, two set checks, and the
> tripwire, because the thing that is transiently unreadable is the whole table
> rather than one rule. A fix scoped to the toolchain accept fixes one symptom
> of six.**

And a second finding that may matter more than the race itself:

> **`install-read-fetch.sh:140` and `:152` cannot tell "the rule is absent" from
> "the listing failed", because both discard stderr and both feed a pipeline
> under `pipefail`. The message the installer printed on `cfv-165` -- "the
> toolchain accept is missing or is not scoped to tcp dport 443" -- is a claim
> the code is not in a position to make.**

---

## 2. Task 1: the runner treats an empty verdict as VOID

### 2.1 What was wrong

`Complete-Phase` tallies by exact name:

```powershell
$nPass = @($emitted | Where-Object Verdict -eq 'PASS').Count
$nFail = @($emitted | Where-Object Verdict -eq 'FAIL').Count
$nVoid = @($emitted | Where-Object Verdict -eq 'VOID').Count
$nInfo = @($emitted | Where-Object Verdict -eq 'INFO').Count
```

A row whose verdict is none of those four is counted by no branch. It does not
raise `$nFail`, it does not raise `$nVoid`, so it never reaches the precedence
rule that withholds the pass. It vanishes. On card 254 question 6, five of ten
rows arrived with an empty verdict and the phase printed `PHASE VERDICT: PASS`.

### 2.2 What was changed

`validation/interim-v120-phaselib.ps1`. `Record` now READS the verdict rather
than storing it. `PASS`, `FAIL`, `VOID`, `INFO` is the entire vocabulary, held in
one place as `$script:CF_Verdicts` so the vocabulary and the tally cannot drift
apart. Anything else -- empty, null, whitespace, or a word the runner does not
know -- becomes `VOID`, is named with its raw value, and withholds the phase
pass.

The check lives in `Record` rather than in `Complete-Phase` for a specific
reason: only `Record` can still see how the CALL was shaped. By the time
`Complete-Phase` sees the row, the difference between "four arguments, one of
them empty" and "three arguments, so everything shifted" is gone.

**Row-level or instrument-level.** The work package asked that where the runner
cannot establish how many rows were affected it treat the void as
instrument-level. Two cases are detectable and both are implemented:

- the row has no usable id, so the void cannot be attributed to a named check and
  two such rows cannot be told apart
- the call arrived SHORT, with no evidence argument bound, which means the
  argument list shifted, so the runner does not know which argument it is holding
  and therefore does not know what else in the phase was mis-bound

A third case is NOT detectable, and it is documented in the file rather than
pretended away: a `Record` call that THREW never reaches the function, so its row
does not exist and nothing inside the runner can miss it. That is the driver's
job, via probe stderr.

Two supporting changes:

- the tally now prints the row count it was taken over
  (`counted 3 of 3 recorded rows`). Card 254 printed a tally of five over a table
  of ten and nothing in the output said so.
- a reconciliation assertion in `Complete-Phase` fires instrument-level if any row
  carries a verdict the tally cannot count. It can only fire if something bypasses
  `Record`'s normalisation. An assertion that never fires is the cheapest thing in
  the file, and on its own it would have caught card 254.

### 2.3 The blast radius, which is much larger than the empty string

**Found by parsing the PowerShell AST of every file in `validation/` and
extracting the fourth argument of all 203 `Record` call sites, not by regex.**
The regex attempt, and why it was abandoned, is in 2.5.

The phases in this directory already record verdicts outside the vocabulary:

| Verdict | Sites | Example |
| --- | --- | --- |
| `REVIEW` | 28 | `interim-v120-panels.ps1:247`, `interim-v120-phase3.ps1:245` |
| `MEASURED-BYPASS` | 6 | `interim-v120-phase2.ps1:212` |
| `UNTESTED` | 5 | `interim-v120-phase2.ps1:443`, `interim-v120-phase3.ps1:169` |
| `MEASURED-HELD` | 5 | `interim-v120-phase2.ps1:216` |
| `BLOCKED` | 4 | `interim-v120-phase3.ps1:411`, `interim-v120-phase4.ps1:201` |
| `BASELINE` / `BASELINE-UNEXPECTED` | 2 | `interim-v120-phase2.ps1:208` |
| `WARN` | 1 | `interim-v120-phase1.ps1:140` |
| `NOTE` | 1 | `interim-v120-phase5.ps1:154` |
| `MANUAL-CONFIRM` | 1 | `interim-v120-phase3.ps1:408` |
| `PARTIAL` | 1 | `interim-v120-phase2.ps1:439` |
| `NOT-DISCOVERED` | 1 | `interim-v120-phase3.ps1:389` |
| `PASS-TO-SINK` | 1 | `interim-v120-phase3.ps1:163` |
| `SENT-AWAITING-INBOX-CONFIRM` | 1 | `interim-v120-phase3b.ps1:122` |

**Every one of those was already being counted as nothing, and every one already
produced the same silent pass as the empty string did.** The empty verdict was
not a unique gap. It was the instance that happened to get noticed.

They now void loudly. That is the fix working, not a regression. But it has a
consequence the next session must act on:

> **Phases 1 through 6 and the panels probe will now report VOID where they used
> to report PASS, and `Complete-Phase` exits 4. Triage these call sites BEFORE
> the next VM run, or the run burns a box producing voids.**

**This was deliberately not fixed here.** Deciding what `REVIEW` means at each of
28 sites is a judgement about what that specific check measured, not a sweep, and
this job is timeboxed and scoped to the runner. Best guesses, labelled as guesses
and offered only to shorten the triage:

- `NOTE` and `WARN` most likely meant `INFO`
- `UNTESTED` and `BLOCKED` most likely meant exactly `VOID` and are already
  correct in spirit, so those sites probably just need the word changed
- `MEASURED-BYPASS` is a finding, not a non-verdict, and probably wants `FAIL`
- `REVIEW` is the genuinely open one and is the bulk of the work

### 2.4 The self-test: 15/15, was 10/10

`validation/harness-selftest.ps1` gains fault 5 in four parts:

| Check | What it injects |
| --- | --- |
| `SELF.5.inject` | proof that the injection LANDED |
| `SELF.5` | the card 254 shape: an empty verdict |
| `SELF.5ctl` | the paired control: the identical body with the variable set |
| `SELF.5b` | an unrecognised verdict (`REVIEW`) |
| `SELF.5c` | a short call, so the damage is uncountable |

**The injection is the real shape, not a stand-in.** The body sets
`Set-StrictMode -Version Latest` and references a variable that was never
assigned, exactly as the VM did. This was established empirically first, because
the reconstruction in the card 254 close-out and the local behaviour disagreed:

```
--- shape 1: subexpression that THROWS (strict, undefined var), EAP=Continue, no try/catch ---
The variable '$neverSet' cannot be retrieved because it has not been set.
  REACHED Rec id=S1 verdictNull=True verdict=[]
  (statement after)
```

Under `$ErrorActionPreference = 'Continue'` the strict-mode error is
NON-terminating: it prints, the subexpression yields nothing, and `Record` IS
reached with a null verdict. That is why the local box reproduced correct
behaviour on the day. Strict mode was off there, so the undefined variable was
silently `$null` and the `else` branch ran normally. Turning strict mode on in
the injected body is what makes this a reproduction rather than an
approximation.

**Proving the injection landed.** The job asked for this specifically and it is
the check that matters most, because an injection that fails to inject scores a
false pass and is indistinguishable from a working control. `SELF.5.inject`
asserts on two things the guard under test does not produce:

1. the child's **stderr** carries the undefined-variable error, so the fault
   genuinely fired
2. the row's `RawVerdict`, which the runner stores verbatim before it normalises
   anything, is empty

Result: `undefined-variable error present in child stderr=True ; F5.2
RawVerdict=[] empty=True`.

### 2.5 Two things found while doing this, both worth keeping

**The self-test could not run its children with `*>`.** Windows PowerShell 5.1
wraps every stderr line from a NATIVE executable in a `NativeCommandError`. The
self-test runs under `$ErrorActionPreference = 'Stop'`, so the first synthetic
phase that wrote to stderr killed the self-test instead of being measured by it
-- and fault 5 writes to stderr by design. Both `*> file` and `> out 2> err` were
tried and both still killed the run. The children now go through `cmd.exe`
redirection, which happens at the OS level, so PowerShell never sees the child's
stderr as an error at all.

Keeping the two streams separate is also the better shape on its own terms, and
it is the same lesson card 254 already paid for: that root cause sat in a job's
stderr for a whole session while the analysis read the phase transcript, which by
construction holds only what the probe successfully printed.

**Instruction I, applied, and it caught something.** Before trusting a grep to
enumerate verdict literals, a canary was introduced into a real phase file:

```
Record 'CANARY.1' 'deliberate control for the verdict-literal grep' 'ZZQQXX' 'this line must be found'
```

The pattern found the canary. But the first pattern used
`Record +'[^']*' +'[^']*' +'[A-Za-z]+'`, and running the corrected pattern beside
the canary showed the original had silently missed `MANUAL-CONFIRM`, because the
character class had no hyphen.

**That pattern was structurally incapable of matching a hyphenated verdict, which
is the identical failure mode as the `\\\$[A-Za-z(]` audit that could not match
`$2` on card 254.** The canary alone would NOT have caught it, because the canary
contained no hyphen either. What caught it was widening the class and watching a
new row appear that had not been there before. The lesson to carry forward is
sharper than "use a canary": **a canary only certifies the pattern against the
shape of the canary.** A canary must be built to look like the thing you are
afraid of missing, not like the things you already know are there.

The enumeration was then redone with the PowerShell AST parser rather than a
regex, which is what produced the 203-call-site table in 2.3. The canary was
reverted and `git status` was checked to confirm it.

### 2.6 The negative control on the guard itself

A self-test that passes proves nothing unless it can fail. The normalisation
branch in `Record` was temporarily neutered to `if ($true)` and the suite re-run:

```
SELF.5.inject PASS  FAULT 5 INJECTION LANDED: the fault fired and the verdict really did arrive empty
SELF.5     FAIL  FAULT 5: an empty verdict records VOID, names the row, and withholds the phase pass
SELF.5ctl  PASS  FAULT 5 CONTROL: a well-formed verdict from the same expression still reports PASS
SELF.5b    FAIL  FAULT 5b: an unrecognised verdict records VOID and names its raw value
SELF.5c    FAIL  FAULT 5c: an uncountable malformed verdict is INSTRUMENT-level, and the sound row is downgraded with it

HARNESS SELF-TEST FAILED: 3 of 15 checks did not hold.
```

Exactly the three new guard assertions failed. The ten pre-existing checks still
passed, so the new code does not interfere with them. `SELF.5.inject` still
passed, which is the correct and important result: the injection proof is
independent of the guard it tests. `SELF.5ctl` still passed, so the control is not
merely riding on the guard.

The guard was restored and the suite confirmed green.

### 2.7 The full self-test output, verbatim

```
===== HARNESS SELF-TEST: five injected faults =====

Library under test: C:\Users\bmcki\ClawFactory-Secure-Setup\validation\interim-v120-phaselib.ps1
Work dir          : C:\Users\bmcki\AppData\Local\Temp\cf-harness-selftest-21356

--- BASELINE (no fault injected): a healthy phase must still report PASS ---
  [PASS] SELF.0 :: BASELINE: a healthy phase still reports PASS (the runner is not simply voiding everything)
        rc=0 PhaseVerdict=PASS

--- FAULT 1: precondition removed (no SMTP credential) ---
  [PASS] SELF.1 :: FAULT 1: a missing precondition yields VOID with a NAMED reason, and no PASS and no FAIL
        rc=4 PhaseVerdict=VOID pass/fail rows=0 reason=this phase registered NO positive control, so nothing it measured can be reported as a pass / precondition not met: F1.PRE an SMTP credential is configured -- no SMTP credential on this box, so the send queue is empty and a refusal cannot be told apart from having nothing to refuse / a check could not be measured: F1.PRE PRECONDITION: an SMTP credential is configured

--- FAULT 2: positive control removed from an otherwise-passing phase ---
  [PASS] SELF.2 :: FAULT 2: a phase with no positive control cannot report PASS, and its passes are downgraded
        rc=4 PhaseVerdict=VOID downgraded PASS->VOID=2 reason=this phase registered NO positive control, so nothing it measured can be reported as a pass

--- FAULT 2b: positive control present but it did NOT fire ---
  [PASS] SELF.2b :: FAULT 2b: a registered control that did not FIRE voids the phase too
        rc=4 PhaseVerdict=VOID reason=positive control did not fire: F2b.CTL the probe can reach a known-good target

--- FAULT 3: search target replaced with a compressed blob ---
  built a compressed fixture: 88 B from 2000 B of text
  [PASS] SELF.3 :: FAULT 3: an unsearchable target voids the phase, and the "absent" result is NOT reported clean
        rc=4 PhaseVerdict=VOID F3.1 verdict=VOID (was PASS)

--- FAULT 3 CONTROL: the same search over a readable payload must PASS ---
  [PASS] SELF.3c :: FAULT 3 CONTROL: the identical search over a readable payload reports PASS (the assertion discriminates)
        rc=0 PhaseVerdict=PASS

--- FAULT 4: independent list edited to disagree with the product ---
  [PASS] SELF.4 :: FAULT 4: a disagreeing independent copy FAILS, and the evidence names BOTH numbers
        rc=1 PhaseVerdict=FAIL F4.1=FAIL evidence=this probe enumerates has 30; the installer claims reports 33. They disagree, so one of the two is stale. The disagreement IS the finding.

--- FAULT 4 CONTROL: agreeing copies must PASS ---
  [PASS] SELF.4c :: FAULT 4 CONTROL: agreeing copies report PASS (the comparison discriminates)
        rc=0 PhaseVerdict=PASS

--- FAULT 4b: the product reports nothing to compare against ---
  [PASS] SELF.4b :: FAULT 4b: nothing reported yields VOID, not a silent agreement, and the phase is not a clean pass
        rc=4 PhaseVerdict=VOID VoidKind=row F4b.1=VOID evidence=the installer claims reported nothing to compare against; this probe enumerates holds 33. An uncompared copy is a second stale list, not independence.

--- FAULT 4b CONTROL: a row-level void leaves the other rows standing ---
  [PASS] SELF.4d :: FAULT 4b CONTROL: a row-level void withholds the phase pass but does NOT downgrade sound rows
        rc=4 VoidKind=row F4d.1 survived as PASS=True

--- FAULT 5: the verdict argument arrives EMPTY (card 254, question 6) ---
  [PASS] SELF.5.inject :: FAULT 5 INJECTION LANDED: the fault fired and the verdict really did arrive empty
        undefined-variable error present in child stderr=True ; F5.2 RawVerdict=[] empty=True
  [PASS] SELF.5 :: FAULT 5: an empty verdict records VOID, names the row, and withholds the phase pass
        rc=4 PhaseVerdict=VOID VoidKind=row F5.2=VOID named=True F5.1 survived as PASS=True rowsRecorded=3 rowsCounted=3

--- FAULT 5 CONTROL: the same phase with the variable SET must PASS ---
  [PASS] SELF.5ctl :: FAULT 5 CONTROL: a well-formed verdict from the same expression still reports PASS
        rc=0 PhaseVerdict=PASS F5c.2=PASS rowsCounted=3/3

--- FAULT 5b: a verdict the runner does not recognise ---
  [PASS] SELF.5b :: FAULT 5b: an unrecognised verdict records VOID and names its raw value
        rc=4 PhaseVerdict=VOID F5b.1=VOID RawVerdict=[REVIEW] reason=malformed verdict: F5b.1 a check whose author invented a verdict -- recorded the verdict 'REVIEW', which is not one of PASS, FAIL, VOID, INFO. A verdict the runner cannot read is a measurement it did not get, so this row is VOID.

--- FAULT 5c: a SHORT Record call, so the damage is uncountable ---
  [PASS] SELF.5c :: FAULT 5c: an uncountable malformed verdict is INSTRUMENT-level, and the sound row is downgraded with it
        rc=4 PhaseVerdict=VOID VoidKind=instrument F5d.1 downgraded PASS->VOID=True reason=malformed verdict: F5d.2 a check whose argument list shifted -- recorded the verdict 'the evidence text that should have been the fourth argument', which is not one of PASS, FAIL, VOID, INFO. A verdict the runner cannot read is a measurement it did not get, so this row is VOID. It also arrived SHORT, with no evidence argument bound, so the argument list shifted and the runner does not know what else in this phase was mis-bound. The extent of the damage is therefore unknown, which makes this instrument-level: a runner that cannot count what it lost cannot certify what survived.

===== HARNESS SELF-TEST RESULT =====
SELF.0     PASS  BASELINE: a healthy phase still reports PASS (the runner is not simply voiding everything)
SELF.1     PASS  FAULT 1: a missing precondition yields VOID with a NAMED reason, and no PASS and no FAIL
SELF.2     PASS  FAULT 2: a phase with no positive control cannot report PASS, and its passes are downgraded
SELF.2b    PASS  FAULT 2b: a registered control that did not FIRE voids the phase too
SELF.3     PASS  FAULT 3: an unsearchable target voids the phase, and the "absent" result is NOT reported clean
SELF.3c    PASS  FAULT 3 CONTROL: the identical search over a readable payload reports PASS (the assertion discriminates)
SELF.4     PASS  FAULT 4: a disagreeing independent copy FAILS, and the evidence names BOTH numbers
SELF.4c    PASS  FAULT 4 CONTROL: agreeing copies report PASS (the comparison discriminates)
SELF.4b    PASS  FAULT 4b: nothing reported yields VOID, not a silent agreement, and the phase is not a clean pass
SELF.4d    PASS  FAULT 4b CONTROL: a row-level void withholds the phase pass but does NOT downgrade sound rows
SELF.5.inject PASS  FAULT 5 INJECTION LANDED: the fault fired and the verdict really did arrive empty
SELF.5     PASS  FAULT 5: an empty verdict records VOID, names the row, and withholds the phase pass
SELF.5ctl  PASS  FAULT 5 CONTROL: a well-formed verdict from the same expression still reports PASS
SELF.5b    PASS  FAULT 5b: an unrecognised verdict records VOID and names its raw value
SELF.5c    PASS  FAULT 5c: an uncountable malformed verdict is INSTRUMENT-level, and the sound row is downgraded with it

Detail written to C:\Users\bmcki\AppData\Local\Temp\cf-harness-selftest-21356\harness-selftest-results.json
Per-fault transcripts and results files are beside it in C:\Users\bmcki\AppData\Local\Temp\cf-harness-selftest-21356

HARNESS SELF-TEST PASSED: 15/15.
Each of the five injected faults was caught, each paired control shows the guard discriminates,
and fault 5 additionally proved that its injection landed rather than assuming it.
HARNESS_SELFTEST_COMPLETE rc=0
```

---

## 3. Task 2: the install race, diagnosis only

Nothing in this section was changed. `setup.ps1` and every shipped resource are
read-only in this job, and they were not written.

### 3.1 Question 1: what does `install-read-fetch.sh` assert, at what point, and what is it waiting on?

**It asserts four things about the live nftables ruleset, in section d, and it
waits on nothing at all.**

```
resources/install-read-fetch.sh:138    nft list set inet clawfactory read_fetch_ipv4 >/dev/null 2>&1 \
resources/install-read-fetch.sh:139        || fatal "set inet clawfactory read_fetch_ipv4 is missing from the live ruleset; Guard 3 would claim a control it does not have"
resources/install-read-fetch.sh:140    nft list chain inet clawfactory output 2>/dev/null \
resources/install-read-fetch.sh:141        | grep -qE '@read_fetch_ipv4 tcp dport 443 accept' \
resources/install-read-fetch.sh:142        || fatal "the read-fetch accept is missing or is not scoped to tcp dport 443"
...
resources/install-read-fetch.sh:150    nft list set inet clawfactory toolchain_ipv4 >/dev/null 2>&1 \
resources/install-read-fetch.sh:151        || fatal "set inet clawfactory toolchain_ipv4 is missing from the live ruleset; the toolchain toggle would claim a control it does not have"
resources/install-read-fetch.sh:152    nft list chain inet clawfactory output 2>/dev/null \
resources/install-read-fetch.sh:153        | grep -qE '@toolchain_ipv4 tcp dport 443 accept' \
resources/install-read-fetch.sh:154        || fatal "the toolchain accept is missing or is not scoped to tcp dport 443"
```

Plus a fifth, the tripwire, immediately after:

```
resources/install-read-fetch.sh:170    if [ -x /usr/local/sbin/clawfactory-fw-assert.sh ]; then
resources/install-read-fetch.sh:171        /usr/local/sbin/clawfactory-fw-assert.sh \
resources/install-read-fetch.sh:172            || fatal "the chain-shape tripwire failed after installing Guard 3"
```

**The point at which it asserts.** Section d runs after section c has already run
both resolvers:

```
resources/install-read-fetch.sh:128    /usr/local/sbin/clawfactory-read-fetch.sh || fatal "the read-fetch resolver failed on its first run"
resources/install-read-fetch.sh:129    /usr/local/sbin/clawfactory-toolchain.sh || fatal "the toolchain resolver failed on its first run"
```

**What it is waiting on: nothing.** There is no poll, no retry and no sleep
anywhere in section d. Each assertion is a single look. `install-read-fetch.sh:35`
sets `set -euo pipefail`, so `pipefail` makes the pipeline fail if EITHER the
`nft list` or the `grep -q` fails, and `|| fatal` cannot distinguish the two.

### 3.2 Question 2: what applies the toolchain accept, and what does "settled" mean for it?

**The accept rule is a static line in `/etc/nftables.conf`, not something added
at runtime.** It is written by `Step-EgressFirewall`:

```
setup.ps1:1523    cat > /etc/nftables.conf <<'NFT'
setup.ps1:1524    #!/usr/sbin/nft -f
setup.ps1:1525    flush ruleset
setup.ps1:1526    table inet clawfactory {
...
setup.ps1:1580            ip daddr @read_fetch_ipv4 tcp dport 443 accept
setup.ps1:1586            ip daddr @toolchain_ipv4 tcp dport 443 accept
```

and applied by a single command:

```
setup.ps1:1631    if /usr/sbin/nft -f /etc/nftables.conf 2>"$NFT_ERR"; then
```

**The step that must complete before the assert can be true is
`Step-EgressFirewall` (`setup.ps1:1390`), which runs synchronously via
`Invoke-WslBash` at `setup.ps1:1807`.** That is many steps before
`Step-InstallReadFetch` (`setup.ps1:2942`).

**But that is not the last thing to touch the chain.** The same file is
re-applied, in full, by `clawfactory-fw-apply.sh`:

```
setup.ps1:1735        /usr/sbin/nft -f /etc/nftables.conf
```

and `fw-apply.sh` is invoked from four places:

| Caller | Line | When |
| --- | --- | --- |
| `install-send.sh` | `resources/install-send.sh:162` | `Step-InstallSend`, the step immediately before the failing one |
| `clawfactory-read-fetch.sh` | `resources/clawfactory-read-fetch.sh:150` | **only on the `iptables-legacy` branch** |
| `clawfactory-toolchain.sh` | `resources/clawfactory-toolchain.sh:251` | **only on the `iptables-legacy` branch** |
| `clawfactory-fw.service` | `setup.ps1:1773`, enabled at `setup.ps1:1786` | boot, `WantedBy=multi-user.target` |

**So "settled" means: the most recent `nft -f /etc/nftables.conf` has committed.**
Because `/etc/nftables.conf` opens with `flush ruleset` (`setup.ps1:1525`), each
re-apply destroys and rebuilds the entire `inet clawfactory` table -- all three
accepts, all four sets, the uid guard and the terminal drop -- not just the
toolchain rule.

**Note for the nftables backend specifically:** on `nftables`, neither resolver
calls `fw-apply`. `clawfactory-read-fetch.sh:138-144` and
`clawfactory-toolchain.sh:238-246` only add set elements. The `fw-apply` calls at
`clawfactory-read-fetch.sh:150` and `clawfactory-toolchain.sh:251` sit inside
`elif [ "$BACKEND" = "iptables-legacy" ]` branches. So on a normal
nftables box, the last thing to rebuild the chain before the failing assert is
`install-send.sh:162`, one step earlier.

### 3.3 Question 3: does the same race exist on the read-fetch accept and the provider accept?

**This is the most valuable question in the job, and the answer is yes to all
three, plus two more surfaces. The race is not a property of the toolchain
accept. It is a property of the table.**

**Read-fetch accept: identical, and the evidence is decisive.**
`install-read-fetch.sh:140-142` is the same construction as `:152-154`, twelve
lines earlier, in the same script and the same process. Both accepts are static
lines in the same `nft -f` ruleset (`setup.ps1:1581` and `setup.ps1:1586`), so
they appear and disappear together -- there is no code path that can remove one
and leave the other.

**On `cfv-165`, `:141` passed and `:153` failed twelve lines later.** Since the
two rules cannot diverge, the state observed by the two consecutive
`nft list chain` calls must have differed. Either the whole table was momentarily
unreadable between them, or the second listing itself failed. That is the single
strongest piece of evidence in this diagnosis and it came from the shape of the
failure rather than from any log.

**Provider accept (`@allowed_ipv4`): the same exposure, on a different surface.**
It is not asserted in `install-read-fetch.sh` at all. It is asserted in the
tripwire:

```
resources/clawfactory-fw-assert.sh:72        *@allowed_ipv4*accept*)
resources/clawfactory-fw-assert.sh:73            if ! grep -qE 'tcp dport 443 accept' <<<"$line"; then
resources/clawfactory-fw-assert.sh:74                bad "provider allowlist accept is no longer scoped to tcp dport 443: $line"
```

which reads the chain once, at the top:

```
resources/clawfactory-fw-assert.sh:49    CHAIN="$(nft list chain inet clawfactory output 2>/dev/null)" || {
resources/clawfactory-fw-assert.sh:50        bad "cannot read chain inet clawfactory output (is the firewall applied?)"
resources/clawfactory-fw-assert.sh:51        exit 1
resources/clawfactory-fw-assert.sh:52    }
```

**`fw-assert.sh` is better than `install-read-fetch.sh` in one respect and no
better in the other.** It DOES distinguish "cannot read the chain" from "the rule
is absent", which `install-read-fetch.sh` does not. But it still takes exactly
one look, still discards stderr with `2>/dev/null` so it cannot say WHY the read
failed, and it is `fatal` at two install-time call sites:

```
resources/install-send.sh:194    /usr/local/sbin/clawfactory-fw-assert.sh || fatal "egress chain shape check failed; refusing to complete the send install"
resources/install-read-fetch.sh:171        /usr/local/sbin/clawfactory-fw-assert.sh \
```

and is also wired as `ExecStartPost` on the five-hourly refresh
(`resources/install-send.sh:177`), where a transient read failure would mark
`clawfactory-allow-providers.service` failed on a customer machine.

**Count of exposed assertions: six.** Three accept checks (`:141`, `:153`,
`fw-assert.sh:110`), two set checks (`:138`, `:150`, mirrored at
`fw-assert.sh:94` and `:107`), and `fw-assert.sh:49` itself, which gates all of
them.

**So: three accepts, not one.** A fix scoped to the toolchain accept would leave
five other single-look assertions on the same state, one of which
(`install-read-fetch.sh:141`) is twelve lines away from the one that failed.

### 3.4 Question 4: does anything else in the install assert on state produced asynchronously by an earlier step?

**Yes, and one of them is a genuinely different class worth naming.**

**(a) The toolchain host-list drift check, `install-read-fetch.sh:114-126`.** It
reconciles the resolver's own host list against a seed file written by a much
earlier step:

```
resources/install-read-fetch.sh:114    SEEDED=/etc/clawfactory/toolchain-hosts.seed
resources/install-read-fetch.sh:118        MINE="$(/usr/local/sbin/clawfactory-toolchain.sh --list-hosts 2>/dev/null | ...)"
resources/install-read-fetch.sh:119        THEIRS="$(tr ' ' '\n' < "$SEEDED" | ...)"
resources/install-read-fetch.sh:121            fatal "toolchain host list DRIFT. setup.ps1 seeded [$THEIRS] but clawfactory-toolchain.sh owns [$MINE]. ..."
```

written at `setup.ps1:1688`. This is cross-step state, but it is a FILE and it is
not rebuilt asynchronously, so it is not in the same race class. It is noted
because it fails the install hard on a value produced several steps earlier, and
because `--list-hosts 2>/dev/null` has the same swallowed-stderr shape: if the
resolver fails to run at all, `MINE` is empty, the comparison fails, and the
error message blames drift rather than the resolver.

**(b) The broker socket probes, and they are the CORRECT pattern.**

```
resources/install-send.sh:197    ok=0
resources/install-send.sh:198    for _ in $(seq 1 30); do
resources/install-send.sh:199        if [ -S /run/clawfactory/send.sock ]; then
...
resources/install-send.sh:213        sleep 1
resources/install-send.sh:214    done
resources/install-send.sh:215    [ "$ok" = "1" ] || fatal "broker did not answer a ping from $AGENT_USER within 30s"
```

The same shape appears at `resources/install-quarantine.sh:147-165`. These wait on
a unit started moments earlier by `systemctl enable --now`
(`resources/install-send.sh:190`), they poll for the CONDITION rather than for a
duration, they are bounded, and their failure message names the bound. **This is
the house pattern the chain asserts should adopt, and it already exists in the
same directory.**

**(c) `gateway-wait.sh`, the most developed version of the same idea.**

```
resources/gateway-wait.sh:42        while :; do
resources/gateway-wait.sh:44            if su "$as_user" -s /bin/bash -c "curl -fsS --max-time 5 http://127.0.0.1:${port}/status >/dev/null 2>&1"; then
resources/gateway-wait.sh:45                return 0
resources/gateway-wait.sh:52            now="$(date +%s)"
resources/gateway-wait.sh:53            [ "$((now - start))" -ge "$timeout_s" ] && return 1
resources/gateway-wait.sh:54            sleep "$interval"
```

Wall-clock bounded rather than iteration bounded, which is the more honest bound
when each attempt can itself block.

**(d) `setup.ps1:2500` and `setup.ps1:3583`,** `if ($i -lt 13) { Start-Sleep -Seconds 10 }`,
are bounded polls of the same correct shape (13 attempts, 120 s).

### 3.5 Question 5: does any of these currently wait on a fixed sleep?

**None of the six chain assertions waits on anything at all -- not a sleep, not a
poll. That is the specific answer for the assert that failed.**

Elsewhere in the install there ARE fixed sleeps, and they are the same defect with
a different constant:

| File and line | Sleep | What it is waiting for | Assessment |
| --- | --- | --- | --- |
| `setup.ps1:1260` | `Start-Sleep -Seconds 3` | WSL to finish shutting down after `wsl --shutdown` | **Fixed, and the boot that follows has its exit code logged but never checked.** No condition is tested at all |
| `setup.ps1:1307` | `Start-Sleep -Seconds 3` | same, in `Step-SetDefaultUser` | Fixed, but the boot that follows IS checked and has a fallback, so the sleep is a cushion rather than the test |
| `setup.ps1:1846` | `sleep 3` | `systemctl restart ollama` to bind | Fixed. Only runs when `Provider = ollama` |
| `setup.ps1:2444` | `sleep 5` | the gateway unit to bind before probing `is-active` | Fixed, but explicitly documented as best-effort, and followed by a 6 x 2 s poll (`setup.ps1:2451`) with the authoritative 120 s PowerShell poll after it. Acceptable as written |

`setup.ps1:1260` is the one worth a second look in the next session. It is the
only fixed sleep in the list with no condition test after it.

### 3.6 What the code plainly says, versus what is inference

**Plainly, from the code:**

- the assert takes exactly one look and waits on nothing (`:140`, `:152`)
- `pipefail` plus `2>/dev/null` makes a failed `nft list` and a missing rule
  produce the identical `fatal`, with a message that asserts the second
- all three accepts are static lines in one `nft -f` file that begins with
  `flush ruleset`, so they live and die together
- `:141` and `:153` check rules that cannot diverge, and on `cfv-165` they
  returned different answers twelve lines apart
- `fw-assert.sh:49` distinguishes a read failure from an absent rule;
  `install-read-fetch.sh` does not

**INFERENCE, and labelled as such:**

- **Inference 1: the rule was probably never absent; the LISTING probably
  failed.** On the nftables backend nothing between `install-send.sh:194` (which
  ran `fw-assert.sh` and passed, checking the same rule at `fw-assert.sh:110`) and
  `install-read-fetch.sh:152` runs `nft -f`. `nft -f` is a single netlink
  transaction, so `flush ruleset` and the table rebuild commit atomically and
  should present no window in which the chain exists without its rules. If no
  rebuild happened and no window exists, the remaining explanation is that the
  second `nft list chain` returned non-zero and its stderr went to `/dev/null`.
  This is consistent with the reported "appeared roughly one second later with no
  distro restart in between".
- **Inference 2: netlink contention is the most likely cause of a failed
  listing.** `clawfactory-allow-providers.timer` is enabled with
  `OnBootSec=30s` (`setup.ps1:2192`) and `systemctl enable --now`
  (`setup.ps1:2283`), so the provider refresh can fire during the install. That
  script issues one `nft add element` per resolved address in a loop
  (`setup.ps1:2146-2150`), each its own netlink transaction, and its
  `ExecStartPost` (`resources/install-send.sh:177`) runs `fw-assert.sh`, which
  issues another `nft list chain`. `clawfactory-send-gc.timer` and
  `clawfactory-quarantine-gc.timer` are also enabled `--now` in the same window.
  This is a hypothesis about WHY the listing failed, not about WHETHER it failed.
- **Inference 3: `Step-EgressFirewall` is not the step that has to settle.** The
  last rebuild before the failing assert is `install-send.sh:162`, one step
  earlier, which is synchronous. So the classic "earlier step has not finished"
  reading of this race is probably wrong, and that matters: a fix that waits for
  `Step-EgressFirewall` would wait for something that finished long ago.

**What would settle all three on a box.** All of it is cheap and none of it needs
a fix committed first:

1. Remove `2>/dev/null` from `install-read-fetch.sh:140` and `:152`, capture the
   listing into a variable with its exit status and stderr preserved, and print
   both before deciding. One run then says definitively whether the rule was
   absent or the read failed. **This alone converts the whole question from
   inference to measurement.**
2. Log the full `nft list chain` output at the moment of failure, so the next
   reader does not have to reproduce it.
3. Inject delay in both directions, as the work package requires: hold the assert
   back and confirm it then passes, and force the failure by running a concurrent
   `nft` load during the assert.
4. Record whether `clawfactory-allow-providers.service` ran during the install
   window (`journalctl -u clawfactory-allow-providers.service`), which tests
   inference 2 directly.

### 3.7 The recommended fix shape, not written

**What should be polled.** One `nft list chain inet clawfactory output` capture,
retried, from which all three accepts are checked. Not three separate listings.
The current code takes two listings twelve lines apart to check two rules that
cannot differ, which is both wasteful and the reason the two got different
answers.

**What the bound should be.** A bounded poll on the CONDITION, matching the house
pattern that already exists at `install-send.sh:198` and `install-quarantine.sh:148`:
roughly 30 attempts at 1 s. Not a fixed sleep. The observed recovery was about one
second, so 30 s is generous without being a mask; and because the poll exits on
success, a healthy box pays one iteration.

**What the failure message should name.** Four things the current message names
none of:

1. **whether the chain was READABLE**, reported separately from whether the rule
   was present. These are different failures with different owners and the code
   must never emit one message for both
2. the `nft` exit status and its **stderr**, which is currently discarded
3. how long it polled and how many attempts it made
4. the full chain text from the final attempt

**Apply the same treatment to `fw-assert.sh:49`.** It already distinguishes the
two failures, which is the harder half, but it still takes one look and still
discards stderr. It runs as `ExecStartPost` on a five-hourly timer
(`resources/install-send.sh:177`), so a transient read failure there marks a unit
failed on a customer machine hours after validation went green -- exactly the rot
mode `fw-assert.sh:11-13` was written to avoid.

**One caution for whoever writes it.** A retry loop around a check that can pass
for the wrong reason is worse than no retry. The condition being polled must stay
"the chain was readable AND names this accept", never "the grep succeeded". If
the listing cannot be read after the full bound, that is a distinct failure and
must be reported as one, not as a missing rule.

---

## 4. Whether the race is one accept or three

**Three, and stated plainly because it scopes the next session's fix:**

- all three accepts (`@allowed_ipv4`, `@read_fetch_ipv4`, `@toolchain_ipv4`) are
  static lines in one `nft -f` ruleset that begins with `flush ruleset`, so no
  code path can affect one without affecting all
- the toolchain accept is simply the one that lost, and the read-fetch accept
  twelve lines earlier is the same construction against the same state
- there are six exposed assertions, not one: `install-read-fetch.sh:138`, `:141`,
  `:150`, `:153`, and `fw-assert.sh:49` plus everything it gates
- the tripwire is a sixth surface with a seventh exposure, because it also runs on
  a five-hourly timer on customer machines, where the same transience marks a unit
  failed long after any validation

**A fix scoped to the toolchain accept is a fix for one machine's timing.**

---

## 5. Found while reading, belongs in the next job, not currently in it

1. **The verdict-vocabulary triage.** Roughly 50 `Record` call sites across
   `interim-v120-phase1..6`, `panels` and the `v130` probes now void. This must be
   triaged before the next VM run or the run burns a box. Full inventory in 2.3.
   It is not in the next prompt and it gates it.
2. **`install-read-fetch.sh:118`, `--list-hosts 2>/dev/null`.** Same swallowed-stderr
   shape as the chain asserts. If the resolver fails to run, `MINE` is empty and
   the install fails claiming host-list DRIFT, which is a misdiagnosis of the same
   kind. One line, same fix, same session.
3. **`fw-assert.sh` runs as `ExecStartPost` on the five-hourly refresh**
   (`resources/install-send.sh:177`). Whatever retry the next session gives the
   install-time asserts should be given here too, because this one runs forever on
   customer machines and its false positives are invisible to validation.
4. **`setup.ps1:1260`.** A fixed `Start-Sleep -Seconds 3` after `wsl --shutdown`
   whose following boot has its exit code logged but never checked. It is the only
   fixed sleep found with no condition test after it.
5. **`.gitattributes`: `*.ps1 text eol=lf`.** Carried forward unactioned from the
   JOB 2 close-out. CRLF-into-WSL defence. Not touched here because it is not this
   job.
6. **`FrontierAI_CC_Prompt_Library.md` has no PROMPT 15.** The copy at
   `C:\Users\bmcki\OneDrive\Desktop\Claude Prompts\FrontierAI_CC_Prompt_Library.md`
   ends at PROMPT 13 followed by the gotchas table, and no other copy exists on
   this machine. The close-out gate, the four pre-flight checks and the
   instruction-challenge clause were applied from the conventions of the recent
   close-outs in `docs/session_reports/` instead. **Flagged rather than guessed
   at**: if PROMPT 15 carries requirements not inferable from those conventions,
   they were not applied here. Adding it to the library is a two-minute fix that
   removes the ambiguity for every future session.

---

## 6. Chronology

| When | What |
| --- | --- |
| start | `git status --short` clean at `913548e`; `validation/` and the last close-out read |
| | Card 254 section 3.6 read for the exact failure shape |
| | PowerShell argument-binding semantics measured before designing the fix; established that an empty subexpression binds `$null` without shifting the argument list, and that a short call is detectable via `$PSBoundParameters` |
| | Verdict inventory attempted by regex; canary introduced per instruction I; canary found, but the pattern was shown to have missed `MANUAL-CONFIRM`. Canary reverted, `git status` confirmed clean |
| | Inventory redone by PowerShell AST parse of all 203 `Record` call sites |
| | `interim-v120-phaselib.ps1` changed; parse-checked |
| | Strict-mode vs `EAP=Continue` behaviour measured, establishing the faithful injection shape |
| | Fault 5 added to `harness-selftest.ps1`; two stream-redirection failures diagnosed and fixed via `cmd.exe` |
| | Self-test green 15/15 |
| | Guard neutered as a negative control; exactly SELF.5, 5b, 5c failed; guard restored; green again |
| | Dispatch card 255 created |
| | Runner fix committed at `bdf4a50` |
| | Install-race diagnosis by reading `install-read-fetch.sh`, `clawfactory-toolchain.sh`, `clawfactory-read-fetch.sh`, `clawfactory-fw-assert.sh`, `install-send.sh`, `install-quarantine.sh`, `gateway-wait.sh` and `setup.ps1` |
| | This close-out written, committed, pushed; card 255 moved to done |

## 7. What was NOT done, and why

- **The install race was not fixed.** Instructed. The fix must be proven by
  injecting delay in both directions on a real box, and its shape depends on what
  3.6's measurement finds.
- **The ~50 non-standard verdict call sites were not re-labelled.** Out of scope
  for a job scoped to the runner, and each is a judgement per check. Reported in
  full instead, with the consequence stated plainly.
- **No VM, no Azure call, no build, no signing, no tag, no publish.** Instructed.
- **`setup.ps1` and every shipped resource were read and not written.** Instructed.
