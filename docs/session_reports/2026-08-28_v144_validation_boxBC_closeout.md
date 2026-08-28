# CLOSE-OUT: v1.4.4 validation, BOXES B and C

**Companion to** `2026-08-27_v144_validation_boxA_closeout.md` (box A's evidence) and
`2026-08-28_v144_boxA_lessons_and_next_job_guidance.md` (the five clauses this job
is run under).

**Scope.** Box B (`-Provider later`, matrix row 4 plus `PG.3f`) and box C (licence
host unreachable, matrix row 2 with the prior artifact as its control), plus the
carry-forward items box A could not close. **Box D is a separate session and
carries the keep-Linux uninstall.**

**No fitness-to-publish verdict.** Two boxes of four, by instruction and because it
would be unsupportable in any case.

---

## 0. PROMPT 15 preamble

Pasted in full from `FrontierAI_CC_Prompt_Library.md`, VM clauses included. The copy
read carries `PROMPT 15` at line 645 of 925 and is **not stale**. Nothing was
deleted from it.

The five clauses from box A's root-cause analysis are in force and each one is
answered specifically in section 17.

---

## 1. THREE CHALLENGES TO THE JOB CARD, RAISED BEFORE EXECUTING IT

PROMPT 15: *"If a premise is stale, say which and what the repo actually shows.
The repo is truth."*

### 1.1 "Confirm the digest and bytes from the ledger" — the ledger does not carry it

The card directs that box C's control artifact be confirmed **from the ledger**
rather than from memory of a close-out. `released-versions.tsv` **begins at 1.2.0**
and has no v1.1.1 row at all, so the ledger cannot confirm it. Its own header says
why: rows before the gate existed are backfilled or absent, and the gate refuses to
compare against a `kind=signed` row.

Three independent sources were used instead, and they agree:

| Source | sha256 | bytes |
| --- | --- | --- |
| `Output\ClawFactory-Secure-Setup.exe.PRIOR`, re-hashed today | `67619df79179db11e76454e9734de244a51128b37c55f66071213c98f72719a9` | 440,525,520 |
| Retained blob `prior-setup.exe`, read at the service | (size read at the service) | 440,525,520 |
| `2026-08-26_v141_validation_closure_closeout.md:98` | `67619df7…` | 440,525,520 |

**The instruction is not followable as written; the intent is satisfied.** Recorded
rather than silently substituted.

### 1.2 `PG.3f` on box B needed a harness fix first, or it would have manufactured two FAILs

`interim-v135-providergate.ps1` reaches its level-2 control **only when
`-DeferredProvider` is absent** — that switch completes the phase early. So taking
`PG.3f` on box B means running the phase a second time without it, and `PG.2a` and
`PG.2b` then read the install log for a verdict that a `-Provider later` install
**never writes**, because the gate is skipped by design at `setup.ps1:3225`.

Sent as written, `PG.3f` on box B produces **two product FAILs against an installer
behaving exactly as specified**. Fixed under TASK 0 (section 3.3), not worked
around.

### 1.3 The by-hand pass: row 11 is already PASSED, and only `5d` is owed

The card says to expect "the by-hand checks". Matrix row 11 passed in full on box A
with all ten checks read by a human. The only owed by-hand item is **`5d`**, which
box A recorded VOID because no driver on that run seeded the entry it describes.

Re-running all ten checks on B and C would cost 20 minutes of operator time to
re-measure something already measured on this same artifact digest. **The plan is a
targeted four-item batch — checks 5a to 5d only — on one box**, which closes box
A's owed item at near-zero marginal cost. Said here rather than decided silently.

---

## 2. THE ARTIFACT. Derivation 1 agrees; 2 and 3 follow at staging

| | |
| --- | --- |
| version | v1.4.4 |
| signed sha256 | `6e65560325cb6d7d3fea204ebb72876b3b113cbbfe9f2fa4f94113237e9eb4d1` |
| signed bytes | 440,610,608 |
| build commit | `25945d5` |

**Derivation 1, on the build machine, by hand:**

```
Output\ClawFactory-Secure-Setup.exe   440610608 bytes
SHA256 = 6e65560325cb6d7d3fea204ebb72876b3b113cbbfe9f2fa4f94113237e9eb4d1
```

Equal to the value the job card carries. Derivations 2 (blob, by download and
re-hash) and 3 (on the box after transfer) are performed by the driver at staging
and are recorded in section 5.

**The control artifact for box C** is `67619df7…` / 440,525,520 B — see 1.1.

---

## 3. TASK 0: the harness fixes, all landed and all dry-run BEFORE provisioning

Box A's process finding: **all five of its day-two instrument defects were in
probes written after hour four, and none of them could be dry-run.** Every change
below was written before any VM existed and exercised against a rigged input on the
build machine, which costs nothing.

### 3.1 TASK 0.1: checklist `5d`, and the recommendation the card asked for

**The two options the card names, and which one is right.**

* **(a) Seed the entry from root tooling during staging.** The tool exists and
  ships with the product: `interim-v140-stagebox.ps1` section 2 calls
  `clawfactory-fetchctl add <host>` as root and records `SB.2`. Box A did not run
  that driver, which is the whole cause.
* **(b) Rewrite the check to state its own precondition.**

**Recommendation: (a), and (b) as the safety net — but they are not
interchangeable and the card's "recommend one" deserves a straight answer.**

**(a) is the right primary fix, because (b) alone permanently converts `5d` into a
check that never measures anything.** The property `5d` exists to prove is that
the panel renders a **persisted** entry *at load* — as opposed to one it added
itself moments earlier, which is a different and much weaker claim. If the box is
never seeded, that property stays unmeasured for ever and the check becomes a
line the operator reads and skips. A check nobody can ever pass is worse than an
absent one: it trains the reader to skip checks.

**(b) is still landed, because (a) cannot be guaranteed by the checklist itself.**
The checklist is a file handed to a person; the seeding lives in a driver a future
run may or may not invoke. So `5d` now branches on a named line the handover card
must carry — `SEEDED READ-FETCH HOST: <hostname>` or `(none)` — and directs a VOID
rather than a FAIL when nothing was seeded. Under that shape the check can never
again produce a FAIL against correct behaviour, whichever driver ran.

**What would stop this MECHANICALLY, which is the more useful half of the question.**

Two different recurrences are tangled together here and they need different fixes:

| Recurrence | Mechanical fix |
| --- | --- |
| **The version string goes stale on every release** (`1.4.1` → `1.4.3` → fixed to `1.4.4` in three consecutive runs, each time by a human noticing) | **A build gate.** The interpolation gate added in v1.4.4 already parses every shipped script; extend the same pass to assert that every version literal in `validation\MANUAL_CHECKS_studio.md` equals `#define MyAppVersion` / `$InstallerVersion` / the Studio filename in the `.iss`, **excluding lines carrying an explicit historical marker**. That is byte-level, canary-able in the shape of the existing nine, and it makes the recurrence impossible rather than remembered. **Carded, not built** — this job changes no build path. |
| **The checklist carries expectations created by a phase that may not run** (`5d`, twice in two runs) | **The card, not the checklist, states the state.** The by-hand file should quote no value that a staging phase decides; it should name the card line that carries it. `interim-v140-stagebox.ps1` already emits a `HANDOVER_CARD_*` block designed for exactly this and `5d` was the one check not wired to it. Every remaining state-dependent expectation in that file should be moved to the same shape, which is a mechanical audit rather than a judgement call. **Carded.** |

**The generalisation, stated plainly:** a by-hand check may assert on the
*product*, never on the *box's configuration*, unless it names where that
configuration is reported.

### 3.2 TASK 0.2: phase 3 declares its precondition

`interim-v120-phase3.ps1` had `preconditions declared=0` and reported
`PASS=14 FAIL=7 VOID=4 INFO=1 / PHASE VERDICT: FAIL` on cfv-179, a box on which
nothing was broken and nothing was configured.

`G2.CRED` now declares `CREDENTIAL_PRESENT`. **The scope is deliberately narrow.**
Voiding the whole suite by reflex would throw away real coverage, so only the rows
whose subject is an enqueue, an approval-to-send, a receipt or the credential
**file** are gated: `G2.1`, `G2.2`, `G2.2c`, `G2.3`, `G2.3b`, `G2.4`, `G2.5`,
`G2.5b`, `G2.6`, `G2.7`, `G2.10`, `G2.11`, `G2.11c`. The rows that do not depend on
a credential keep real verdicts.

A second, smaller fix in the same file: **`G2.3b` used to vanish entirely** down
the no-`requestId` branch, so a run in which staging was never checked and a run in
which it passed produced different row counts and the same verdict list.

**Dry-run, both directions, against a rigged channel, before any box existed:**

```
credential ABSENT   13 of 13 gated rows VOID, FAIL=0,
                    PASS=0 FAIL=0 VOID=28 INFO=1 (counted 29 of 29)
                    preconditions declared=1 met=0
                    PHASE VERDICT: VOID (instrument)

credential PRESENT  (channel rigged empty, so everything else IS broken)
                    G2.1 FAIL, G2.10 FAIL, G2.11c FAIL
                    PASS=8 FAIL=9 VOID=10 INFO=1 (counted 28 of 28)
                    preconditions declared=1 met=1
                    PHASE VERDICT: FAIL
```

**Both halves matter.** The first is the fix working. The second proves the gate is
**not a blanket suppressor**: with a credential present, real failures still
surface as FAIL rather than being hidden behind a precondition.

**One cost, stated rather than glossed.** The phase runner voids an entire phase
whose declared precondition is unmet, so on an unconfigured box the
credential-*independent* rows — socket modes, the five approval channels, the SMTP
route blocks for uid 1000, the broker-down loud failure — are downgraded too, and
row 14 contributes no positive coverage. That is PROMPT 15's rule applied
literally and it is what box A recommended, and the runner annotates each row
`(was PASS, voided with the phase)` so nothing is lost from the record. **The
follow-up is to split phase 3 into a credential-dependent phase and a
credential-independent one; carded, not done here.**

### 3.3 The providergate precondition, which `PG.3f` on box B requires

See 1.2 for why. `PG.2.PRE` **discovers** which of three states the install log is
in and prints it, rather than assuming one:

```
gateRan     the log carries 'Provider-route gate PASSED' or '... FAILED'
gateSkipped the log carries 'Provider-route gate SKIPPED'
neither
```

Every string is quoted from the product, not paraphrased: `setup.ps1:3225`
(skip, deferred), `:3243` (placement), `:3282` (passed), `:3272` (failed).

`PG.3c` and `PG.3d` were also **classified rather than tested for a string**, per
clause 2. The level-2 rig points the provider host at an unroutable address for the
*whole* install, so an abort at an earlier step is a live possibility that has
never been measured; `GATE_ABORT`, `OTHER_ABORT`, `COMPLETED` and `NO_MARKER` are
now four distinguishable outcomes. **`PG.3d` previously matched bare
`INSTALLER_DONE`, which `INSTALLER_DONE=success` also satisfies — a control that
could not fail.**

**Dry-run against install logs quoting the product verbatim:**

```
gate-ran      install log states: gateRan=True  gateSkipped=False
              PG.2.PRE PASS, PG.2a PASS, PG.2b PASS
gate-skipped  install log states: gateRan=False gateSkipped=True
              PG.2.PRE VOID (named reason), PG.2a VOID, PG.2b VOID
              FAIL=0
```

Before the fix the second case produced two product FAILs.

### 3.4 Row 2 identifies BOTH of its binaries

Row 2's argument is *"the old licence-carrying build died under this block minutes
before the new one completed under it."* That is a behaviour change only if both
files are the ones they are named as, and **neither was checked on the box**.

`B2.0` is now a precondition on the control binary's digest AND byte count,
re-hashed on the VM. `B3.PRE` pins the subject the same way when the driver
supplies it, and records an explicit INFO when it does not — so "taken on trust"
and "verified" never look the same. `interim-v140-relgate-box.ps1` gained
`-PriorExe`, which gives the control binary the same build-machine preflight the
subject gets and re-verifies its digest on the box.

The probe's row labels also carried `v1.4.0`, stale by four releases. The subject
is now named by the digest it is handed rather than by a number in a string.

### 3.5 Two new probes, written cold and dry-run against rigged inputs

**`interim-v144-crcensus.ps1`** — section 14.11's missing half (TASK 3.1).
It **enumerates** what is installed rather than asserting against a remembered
list, and names the one file whose destination differs from its source, quoting
the line that decides it:

```
ClawFactory-Secure-Setup.iss:61
  Source: "smoke-test.ps1";   DestDir: "{app}\resources";   Flags: ignoreversion
```

Ten shipped Windows-side scripts: `{app}\setup.ps1` and nine under
`{app}\resources`. The held copy is measured from the repo at this commit and
**compared**, not printed.

```
DRY-RUN 1, clean rig            PASS=15 FAIL=0 VOID=0 INFO=0 (15 of 15)
                                calibration: planted expected=1 measured=1
                                             stripped expected=0 measured=0
DRY-RUN 2, three planted faults PASS=11 FAIL=4  -- and exactly the right four:
    CR.resources\launcher.ps1   FAIL  cr=250 after CRLF-ifying it
    CR.SET                      FAIL  onBoxNotExpected=1 [stowaway.ps1]
                                      expectedNotOnBox=1 [uninstall.ps1]
    CR.HELD                     FAIL  launcher box=250 repo=0
    CR.BYTES                    FAIL  launcher box=11600 repo=11350
```

**The dry-run found a defect in the probe itself.** With the calibration sample
chosen by ascending size, the 18-byte stowaway *became* the calibration subject —
so anyone able to drop a file into the install directory could choose what the
instrument calibrates on. Sample is now the **largest** file, which cannot be
displaced downwards.

**`interim-v144-attempts.ps1`** — `#261`'s repeated-attempt measurement (TASK 3.2).
Twelve attempts per host as uid 1000. Subject hosts are **read off the box** from
the files the product writes, quoted rather than guessed:

```
setup.ps1:1721                          -> /etc/clawfactory/toolchain-hosts.seed
resources/clawfactory-read-fetch.sh:36  -> /etc/clawfactory/read-fetch-hosts.txt
```

*(The first draft of this probe read `toolchain-hosts.txt`, a name that does not
exist. Clause 1 caught it before it ran — the discovery step is what turned an
assumption into a check.)*

Two rows per host, as box A's bootpath probe does:

* `AT.EXISTS.<host>` — a real verdict: did a working route get built at all (`#276`,
  closed)
* `AT.ALWAYS.<host>` — **the raw count only, recorded INFO.** This session takes no
  verdict on `#261`, proposes no fix and makes no recommendation. That is the
  operator's call and he has it.

```
DRY-RUN rigA healthy/intermittent  PASS=8 VOID=0 INFO=4, verdict PASS
                                   github 5/12 INTERMITTENT, npm 12/12 ALWAYS
DRY-RUN rigB blind probe           deny host also connects -> AT.CTL FAIL
                                   verdict VOID (instrument), exit 4
DRY-RUN rigC switch OFF            AT.PRE.SWITCH not met -> verdict VOID
DRY-RUN rigD no hosts discovered   AT.PRE.HOSTS not met  -> verdict VOID
```

**The switch-off rig found a second defect in the probe.** Its evidence field
asserted *"a shortfall here is the rotating-pool sampling gap rather than a switch
position"* over a `0/12` the switch had caused. An evidence field that names the
wrong cause is the same defect class as a probe that measures the wrong subject.
The cause clause is now conditional on the switch position and on whether the host
is toolchain- or read-fetch-governed.

### 3.6 One instrument defect found and CORRECTED IN THE RECORD, not just in code

A render test of the driver's new staging string appeared to show the prior
artifact's SAS URL rendering **without its blob name**, and a comment saying so was
written into `interim-v140-relgate-box.ps1`.

**That diagnosis was wrong and the fault was in my test stub.** The stub wrote
`"$n?SASTOKEN"` without escaping the `?`; PowerShell reads that as a variable
literally named `n?SASTOKEN`, which is undefined, so the empty URL came from the
stub. The real function escapes it (`` $name`?$s ``). Retested with a correct stub:
**both the inline and hoisted forms render the blob name correctly.**

The change was kept — one URL built differently from the other six is a reading
hazard in the builder whose historical failure mode was a silently malformed remote
script — but the comment now says what is true rather than what was first
concluded, and the commit says so too. Recorded here because a false defect left in
a comment is a worse outcome than the defect it claimed.

### 3.7 TASK 0.3: the stale-default sweep, fifth consecutive run

**Scope widened past box A's final scope.** Box A's sweep as first written covered
`.ps1` only and would have missed the stale value it eventually found in
`MANUAL_CHECKS_studio.md`. This run includes `.md`, `.sh`, `.mjs`, the `.iss`,
`setup.ps1`, `released-versions.tsv` and `.gitattributes`, and adds `scripts\`,
which box A did not sweep at all.

```
SWEPT_FILES=89   (ps1=76  md=6  sh=3  other=4)     [box A: 58 files]
TOTAL_HITS=2082                                     [box A: 920]
  DIGEST   hits=37    distinct=28
  VERSION  hits=987   distinct=156
  BYTES    hits=17    distinct=16
  HOST     hits=773   distinct=91
  ARTPATH  hits=42    distinct=9
  VMNAME   hits=226   distinct=49
```

`VMNAME` is a sixth class box A found by reading rather than by sweeping; it is a
first-class class here.

**The vacuity guard throws rather than reporting clean if zero files match.** The
v1.4.3 instrument once reported `LEGACY_PROBE_FILES=0` from a bad glob, which made
every "no hits" column mean "nothing was searched".

#### The canary, in three shapes the tree does not contain — proven absent first

A canary certifies a pattern only against the shape of the canary, so absence was
**measured before planting**, not assumed:

| Shape | Files in the tree matching it, before planting |
| --- | --- |
| digest as a **hashtable literal value**, `@{ … = '<64hex>' }` | **0** |
| version inside a **`[ValidateSet(…)]` attribute argument** | **0** |
| digest / byte count inside a **`.sh` file** | **0** |

```
PLANTED  validation\interim-v141-teardownstop.ps1  hashtable literal: digest + bytes
PLANTED  validation\interim-v141-teardownstop.ps1  ValidateSet attribute: version
PLANTED  validation\sp-prefix-fw.sh                shell comment: digest + bytes + VM name

CANARY_HIT  aa11bb22…8899   interim-v141-teardownstop.ps1:136   DIGEST
CANARY_HIT  440601234       interim-v141-teardownstop.ps1:136   BYTES
CANARY_HIT  1.3.9           interim-v141-teardownstop.ps1:137   VERSION
CANARY_HIT  440609999       sp-prefix-fw.sh:73                  BYTES
CANARY_HIT  cfv-999         sp-prefix-fw.sh:73                  VMNAME
CANARY_HIT  99887766…bbaa   sp-prefix-fw.sh:74                  DIGEST
```

**6 of 6 found — but only on the second attempt, and the first miss is worth
recording.** The `.sh` digest canary was initially written 62 hex characters long,
so the sweep correctly did not match it. **The canary was malformed, not the
instrument** — which is exactly the ambiguity a canary exists to resolve, and it
resolved it the right way round: had the instrument been blind to `.sh` files, the
symptom would have been identical, and the only way to tell was to count the
characters and re-plant.

**Restoration was by writing back the bytes saved before planting, proven by hash**
— never `git checkout --`, which under this machine's system-level
`core.autocrlf=true` silently re-materialises a file as CRLF while `git status`,
`git diff` and `grep` all report it clean:

```
ORIG interim-v141-teardownstop.ps1  sha=0a3fbfff…3e37  bytes=7932
ORIG sp-prefix-fw.sh                sha=bee57941…4da0  bytes=3771
RESTORED interim-v141-teardownstop.ps1 sha=0a3fbfff…3e37 bytes=7932 match=True
RESTORED sp-prefix-fw.sh               sha=bee57941…4da0 bytes=3771 match=True
git status --short -> neither file listed
```

#### The enumeration: digests, re-derived rather than assumed

| Pin | Value | Verdict |
| --- | --- | --- |
| `PIN.soul` / `setup.ps1:2846` | `e70212603f…db7941` | **CURRENT.** `resources\safety-rules.md` re-hashes to it |
| `PIN.persona` / `setup.ps1:2945` | `0557d07004…ff63a0` | **CURRENT.** `resources\persona.md` re-hashes to it |
| `PIN.workspaceSoul` / `setup.ps1:2946` | `441b6279f6…a257` | **CURRENT by construction**, and the two sites agree |
| `PIN.rootfs` / `setup.ps1:467` | `1483cc5c1d…b4109` | **CURRENT**, and still a dead literal — nothing compares it post-install. Left alone, as in v1.4.3 and box A |
| `PIN.studioAsar` (`phase1:95`, `stagecards:132`) | `a64a118f7a…2a49e` | **CURRENT**, two sites agree. Studio unchanged |
| `build_release.ps1:450` Studio installer | `ac59375166…e7dca` | **CURRENT.** `resources\ClawFactory-Studio-Setup-1.3.2.exe` re-hashes to it |
| `bundlebytes:143` orchestrator prompt | `f781634267…2ec43` (`f7f81634…`) | **CURRENT.** `resources\orchestrator-prompt.md` re-hashes to it |
| `.gitattributes:101` Apache-2.0 | `cfc7749b96…3d30` | **CURRENT.** `LICENSE` re-hashes to it |
| `relgate-box:54,55` subject | `6e655603…` / 440,610,608 | **CURRENT.** Box A repinned it; re-verified today |
| `offline-install:54,55`, `relgate-box:64,65` control | `67619df7…` / 440,525,520 | **CURRENT.** See 1.1 |
| `phase3:254`, `phase3b:149`, `phase6:395` all-zeros | — | **NOT A PIN.** A deliberately wrong hash passed to `approve` as a negative control |
| `interim-v120-validate.ps1:180,181` | `257f30ff…` / 440,613,512 | **STALE, DELIBERATELY LEFT.** That driver is forbidden by PROMPT 15 (it calls `az vm user update` after provisioning). A stale digest in a driver nobody may run is a brake, not a hazard; refreshing it would make a forbidden instrument look blessed |
| `validation\diag\g4-probe.ps1:76,77` | `5bef35dc…` / 440,606,872 | **STALE**, out of scope: a Guard 4 diagnostic, not a matrix instrument, not run by this job |
| `job3-validate.ps1:66` | `ffe86406…` | **STALE**, out of scope: the archived JOB 3 validator |
| `azure-validate.ps1:55` | `e412a516…` (v1.0.48) | **STALE**, and newly visible because this sweep includes `scripts\`. Same class as the two above: that driver is not on any current path. **Not repointed**, for the same reason |
| `released-versions.tsv:36–47` | twelve rows | **NOT PINS.** The ledger, which is the record; `1.4.4` is present at `548562c7…` |

#### Version literals, the load-bearing subset

```
ClawFactory-Secure-Setup.iss:9    #define MyAppVersion   "1.4.4"
ClawFactory-Secure-Setup.iss:16   #define StudioInstaller "ClawFactory-Studio-Setup-1.3.2.exe"
setup.ps1:56                      $InstallerVersion      = '1.4.4'
interim-v120-phase1.ps1           PIN.version            = '1.4.4'
```

All four agree. **`MANUAL_CHECKS_studio.md` is CURRENT** — header reads "for the
v1.4.4 build" (line 5), check 6f names the installer version `1.4.4` (line 273) and
Studio `1.3.2` (line 272). Box A's fix held. The `v1.4.0` / `v1.4.1` mentions at
lines 245–247 and 411–413 are **historical narrative** and are correct as history.

The `VERSION` class is intrinsically noisy — it matches section numbers, IP
addresses, `Set-StrictMode -Version 3.0` and PowerShell `5.1`. Stated plainly
rather than presenting a filtered list as though it were the raw one.

#### The sixth class: stale VM-name defaults, unchanged from box A

```
validation/finish-and-park.ps1:27       $VmName = 'cfv-162'
validation/interim-v120-job.ps1:31      $VmName = 'cfv-153'
validation/interim-v120-validate.ps1:33 $VmName = 'cfv-153'
validation/job3-validate.ps1:56         $VmName = 'cfv-152'
validation/diag/g4-probe.ps1:52         $VmName = 'cfv-165'
scripts/azure-validate.ps1:47           $VmName = "cfv-138"
```

**All six name boxes that no longer exist**, which section 4's estate listing proves
independently, so **all six fail safe**: an `az` call against a deleted VM errors
rather than quietly measuring the wrong machine. `-VmName` is passed explicitly on
every invocation in this session. **Not fixed, for box A's reason:** repointing them
makes them stale again the moment these boxes are torn down; the correct fix is to
make the parameter mandatory, which is a behaviour change to six instruments and
belongs in its own change. `interim-v140-relgate-box.ps1`, the driver this session
actually uses, already has `[Parameter(Mandatory)]$VmName`.

#### Byte counts, hosts and artifact paths

**Byte counts.** 17 hits, 16 distinct: twelve ledger rows plus the five digest/byte
pairs already classified above. No unexplained value.

**Hosts.** 91 distinct DNS names, up from box A's 30 because `scripts\` and
`setup.ps1` are in scope. No stale entry: the product hosts match the documented
base and toolchain sets, and the remainder are deliberate probe targets, competitor
provider endpoints used as controls, SMTP targets and infrastructure.

**Artifact paths.** 9 distinct. Every driver default on a current path resolves to
`Output\ClawFactory-Secure-Setup.exe` on the build machine or
`C:\cfv\combined-setup.exe` on the box. The three versioned filenames
(`…-v1.0.48.exe`, `…-v1.1.0.exe`, `ClawFactory-Studio-Setup-1.2.0.exe`) all sit in
the three out-of-scope drivers already named above.

### 3.8 Commits

```
53959d2  validation(phase 3): declare the SMTP-credential precondition PROMPT 15 requires
c51b6c6  validation(by-hand): check 5d states its own precondition instead of assuming one
72697f4  validation(providergate): PG.2a/PG.2b need the gate to have RUN; classify PG.3c/3d
9f27bb4  validation(row 2): identify BOTH binaries by digest, and stage the control build
b492769  validation: two new probes for section 14.11's CR census and #261's sample count
9efbf5a  validation(driver): hoist the prior-artifact SAS URL alongside the other six
```

Every touched file is `i/lf w/lf` in `git ls-files --eol` before and after, so no
edit re-materialised line endings. **The sweep instrument itself is not committed**
— a throwaway, as in v1.4.3 and box A; committing it would imply a maintenance
promise this job did not make.

---

## 4. TASK 0.4: the starting estate, unfiltered — and the plan

### 4.1 The estate before anything was provisioned

```
=== az vm list -d, SUBSCRIPTION-WIDE ===        VM_EXIT=0   (no rows)
=== az resource list, ALL RESOURCE GROUPS ===   RES_EXIT=0
clawfactory-validation  clawfactoryvalc467             Microsoft.Storage/storageAccounts
clawfactory-validation  bake-vmVNET                    Microsoft.Network/virtualNetworks
clawfactory-validation  clawfactory-win11-baseline     Microsoft.Compute/images
clawfactory-validation  clawfactory-win11-baseline-v2  Microsoft.Compute/images
NetworkWatcherRG        NetworkWatcher_westus2         Microsoft.Network/networkWatchers
clawfactory-signing     clawfactory-signing            Microsoft.CodeSigning/codeSigningAccounts
=== disks (-g clawfactory-validation) ===  DISK_EXIT=0  empty
=== nics, public-ips, nsgs (subscription-wide) ===  all exit 0, all empty
```

**Exactly the expected residual and nothing else.** The NetworkWatcher is Azure's
own auto-created resource and the signing account is the build-time code-signing
account; neither is validation estate and neither bills compute. **Zero VMs, zero
disks, zero NICs, zero public IPs, zero NSGs.** Every exit code read, not inferred
from empty output.

`az disk list` was issued **with** `-g` deliberately: box A recorded that the
subscription-wide form exits 2 with a required-argument error, whose empty output
reads exactly like "no disks exist".

### 4.2 The plan, recorded BEFORE `az vm create`

**Two boxes, sequential, B then C.** They are run one after another rather than
concurrently because PROMPT 15 permits **one `az vm run-command` at a time,
subscription-wide**, and the driver polls the on-VM runner through `run-command`.
Overlapping the two boxes would interleave two polling streams against that
constraint.

| | Box B — `cfv-180` | Box C — `cfv-181` |
| --- | --- | --- |
| Install | `-Provider later` | `-Provider claude`, licence host blocked |
| Carries | matrix row 4, `PG.3f` | matrix row 2 + its prior-artifact control |
| Also | TASK 3.1 CR census, TASK 3.2 `#261` samples, phase 3 (exercises the 0.2 fix) | checks `5a–5d` by hand |
| Size / image | `Standard_D2s_v4`, `clawfactory-win11-baseline-v2` | same |

**Phase order on box B, and why it is not negotiable:**

1. `interim-v120-phase1.ps1 -Provider later` — the install. Everything needs it.
2. `interim-v135-providergate.ps1 -DeferredProvider` — **matrix row 4**. Must run
   while the box is still in its deferred state.
3. `interim-v144-crcensus.ps1` — TASK 3.1.
4. `interim-v144-attempts.ps1` — TASK 3.2.
5. `interim-v120-phase3.ps1` — exercises the credential precondition on a real box.
6. `interim-v135-providergate.ps1 -RunFullInstallControl` — **`PG.3f`. LAST**, because
   its level-2 control re-runs the installer with `-Provider claude` and would
   destroy the deferred state row 4 depends on.

**Estimate, stated before it is spent:**

| | |
| --- | --- |
| Wall clock | **5 to 6 hours** for both boxes, plus TASK 0 already spent |
| Operator touches | **2 to 3**: one RDP login per box, plus one four-item by-hand batch |
| Compute | two `Standard_D2s_v4` at roughly $0.10/hour, **well under $2** for both |

**Does this job fit in one session? Yes, and the reason is that neither box needs a
reboot.** Box A cost 5.5 hours across two days with five operator touches, three of
which were reboot- and uninstall-driven. Boxes B and C carry no reboot pass, no
uninstall branch and no full row-11 re-run, so the only unavoidable human step is
the RDP login that starts each runner — auto-logon is deliberately not armed.

**Box B is deleted before box C is provisioned**, so at most one VM bills at a time
and the teardown of each is proven before the next exists.

### 4.3 One decision taken before dispatch, so it is not argued into afterwards

**`5d` is closed on box C, not box B, and phase 3 runs on box B, not box C.** They
cannot both happen on one box, and the reason is worth stating rather than
discovering:

* The driver that seeds `5d`'s subject, `interim-v140-stagebox.ps1`, writes an SMTP
  **sink** credential in the same run as the read-fetch seed — one call sets both,
  deliberately, so the credential and the policy cannot drift apart.
* A box carrying that credential reports `CREDENTIAL_PRESENT`, which is precisely
  the state under which the TASK 0.2 fix is **not** exercised.

So box B stays unconfigured and runs phase 3 (the credential-absent path, which is
the fix's subject), and box C runs `stagebox` and then the four-item by-hand batch
(the seeded path, which is `5d`'s subject). Nothing sends: the sink credential
points at `127.0.0.1:2525` and no probe in either box's plan transmits. **Zero
outbound email, and `-ExpectRealCredential` is not passed on either box.**

---

## 5. BOX B PROVISIONED AND STAGED. All three derivations agree

```
[11:23:55]   artifact verified: 6e65560325cb6d7d3fea204ebb72876b3b113cbbfe9f2fa4f94113237e9eb4d1 (440610608 bytes), Authenticode Valid
[11:23:57]   provider key present (value never printed)
[11:23:57]   build machine public IP: 67.164.251.99
[11:26:37] Provisioned.
[11:26:40]   RDP rule confirmed by read-back: 67.164.251.99/32
[11:26:42]   public IP: 20.98.84.133
[11:26:43]   agent: Ready
[11:38:41] Staged, digest re-verified ON THE BOX. OK staged; artifact=6e65560325cb6d7d3fea204ebb72876b3b113cbbfe9f2fa4f94113237e9eb4d1 size=440610608
[11:39:13]   WROTE wrapper=5200 runner=112 AutoAdminLogon=
[exited with code 0]
```

**Derivation 1** by hand on the build machine, **derivation 2** through blob storage
with the byte count confirmed at the service on upload, **derivation 3** re-hashed
on the box after a 440 MB transfer. The job card's instruction was to stop if any
differed. None did.

`AutoAdminLogon=` is empty and was **asserted rather than set**. The driver arms no
auto-logon, which is what makes the operator login the correct price of the
PROMPT 15 credential rule rather than a defect to engineer around.

**The RDP scope was verified twice, independently** — once by the driver's own
read-back and once by a separate `az network nsg rule show` from this session:

```
67.164.251.99/32   3389   Allow   Inbound      NSG_EXIT=0
ProvisioningState/succeeded, PowerState/running  VM_EXIT=0
```

Never `0.0.0.0/0`.

**On the admin credential.** `az vm create` requires a value, so the driver
generates a random 24-character bootstrap password, passes it once and nulls it
without printing it. The operator set their own at Card 1. **This session never
called `az vm user update`, never generated, printed or requested a password, and
never saw one.**

### 5.1 Resources created, recorded now so teardown can be checked against them

```
cfv-180         Microsoft.Compute/virtualMachines
cfv-180-osdisk  Microsoft.Compute/disks
cfv-180VMNic    Microsoft.Network/networkInterfaces
cfv-180-pip     Microsoft.Network/publicIPAddresses
cfv-180-nsg     Microsoft.Network/networkSecurityGroups
```

Five resources. `az vm delete` removes only the first, so teardown sweeps the other
four explicitly, **NIC first**, because it references the public IP and the NSG.

---

## 6. BOX B, THE INSTALL: `-Provider later` completes. **PASS**

The install ran in the operator's interactive session (nothing launches
`wrapper.cmd`; no auto-logon is armed) and was polled from here, one
`run-command` at a time, with **no automated probe touching the box while the
operator was on it**.

Nine polls over roughly fourteen minutes, each reading the runner heartbeat
separately from the install state so *"runner alive, job slow"* and *"runner dead"*
stay distinguishable:

```
poll 9/60  az_exit=0  12:00:59
PHASE1_DONE=True
RUNNER_HEARTBEAT=2026-08-28T18:03:55
INSTALL_RESULT=INSTALLER_DONE=success
LOG_TAIL:
  [2026-08-28 18:03:19] [INFO] PostInstall smoke task registered (fires at next user logon)
  [2026-08-28 18:03:19] [INFO] ==== ClawFactory Secure Setup - completed successfully ====
  [2026-08-28 18:03:20] [INFO] INSTALLER_DONE=success
```

### 6.1 Phase 1 on a deferred-provider box. **PASS, 15/0/0/4 of 19**

```
P1.5              PASS  install-result.txt reports success
P1.2              PASS  Step-Preflight ran and passed (installer claim)
P1.3.CTL          PASS  POSITIVE CONTROL: the enumeration can see a resource that IS there
P1.3              PASS  All 34 required resources on disk (independent enumeration)
P1.3b             PASS  Installer resource count and this probe agree
P1.3c             PASS  CONTROL: absent resource must not be found
P1.CHAN           PASS  POSITIVE CONTROL: the file-based WSL channel discriminates
PIN.persona       PASS  Pin 1of7 persona.md
PIN.soul          PASS  Pin 2of7 safety-rules.md (SOUL)
PIN.soul.indistro PASS  Pin 2of7 SOUL as installed in distro
PIN.soul.rootpin  PASS  Root-owned /etc/clawfactory/soul.sha256 matches pin
PIN.workspaceSoul PASS  Pin 3of7 composed workspace SOUL matches pin
PIN.studio.asar   PASS  Studio pin: the INSTALLED app.asar matches the build-time digest
PIN.version       PASS  Installed version reports 1.4.4
PIN.bundle        PASS  Bundle completeness (all 34 preflight resources shipped)

PASS=15 FAIL=0 VOID=0 INFO=4  (counted 19 of 19 recorded rows)
positive controls registered=2 fired=2
preconditions declared=0 met=0
PHASE VERDICT: PASS
```

**This is not a re-run of box A's row 1 and is not reported as one.** Box A proved
the clean install on `-Provider claude`. What this adds is that **the same 34
resources, the same seven pins and the same version all land identically when the
provider is deferred** — a variant no box has taken since cfv-171 at v1.4.0, and a
different install path through `setup.ps1` (the key wizard and the provider-route
gate are both skipped). The two `INFO` rows carrying `PIN.rootfs` and the baseline
are the same four INFO rows box A recorded, for the same reasons.

`SENTINEL_PRESENT=True`, transcript 11,310 bytes, and the results JSON agrees with
the transcript on all three summary numbers — two independent channels, compared
rather than one trusted.

---

## 7. MATRIX ROW 4: the provider gate is skipped with a stated reason, and the install still completes. **PASS**

**TASK 1.1 requires both halves, and the reason it does is worth restating: a gate
that silently does nothing when its subject is absent is indistinguishable from a
gate that is broken.** Both halves are recorded separately.

```
PG.CHAN    PASS  POSITIVE CONTROL: the file-based WSL channel discriminates
                 SUBJECT_MARKER=0 | CONTROL_RC=1 | EXPAND=expanded-ok
PG.1.PRE   PASS  PRECONDITION: the install log is present and readable
PG.1.SRCH  PASS  POSITIVE CONTROL: search target is searchable (the install log)
PG.3a      PASS  TEST 3: with the provider deferred, the gate is SKIPPED and says so
PG.3b      PASS  TEST 3: the deferred install still completed

PASS=5 FAIL=0 VOID=0 INFO=0  (counted 5 of 5 recorded rows)
positive controls registered=2 fired=2
preconditions declared=1 met=1
PHASE VERDICT: PASS
```

**`PG.3a` is the half that matters and it is an assertion on the product's own
words, not on silence.** It requires the install log to carry, verbatim:

```
Provider-route gate SKIPPED, reason: provider deferred
```

which `setup.ps1:3225` writes as *"Step 15h: Provider-route gate SKIPPED, reason:
provider deferred (-Provider later). There is no provider to reach yet; the route is
proven when a provider is chosen."* A skip that happened without saying so would
FAIL this row, which is precisely the "silently does nothing" case.

**`PG.1.SRCH` is why the row above means anything.** Before searching the log for a
phrase, the phase proves the log is searchable at all by finding a phrase it knows
must be there. A search over an unreadable or empty target reports a clean absence
and says nothing — discipline 5 in the phase runner's header.

**`PG.2a` and `PG.2b` did not run on this pass**, because `-DeferredProvider`
completes the phase at section 1. They run on the second pass, which carries
`PG.3f` — see section 11, and see 1.2 for why that second pass needed a harness fix
before it could be taken at all.

---

## 8. SECTION 14.11's CR CENSUS. **PASS, 15 of 15** — and it closes box A's owed item

Box A proved the shipped Windows-side scripts **execute** (`WR.1/2/3/4/7/8/9`). It
never counted their carriage returns. That count is now taken, per file, on the box.

**The set was DISCOVERED, not asserted against a remembered list:**

```
DISCOVERED_COUNT=10
  FOUND resources\bootstrap.ps1            16038 bytes
  FOUND resources\clawfactory-grants.ps1   54751 bytes
  FOUND resources\clawfactory-stop.ps1     10595 bytes
  FOUND resources\launcher.ps1             11350 bytes
  FOUND resources\post-install.ps1         13130 bytes
  FOUND resources\rename-agent.ps1          1438 bytes
  FOUND resources\smoke-test.ps1           20983 bytes
  FOUND resources\switch-provider.ps1      21388 bytes
  FOUND resources\uninstall.ps1            38423 bytes
  FOUND setup.ps1                         214311 bytes
```

**The counter was calibrated on the box, in both directions, on real shipped bytes,
before it counted anything:**

```
calibration sample: setup.ps1 (214311 bytes, CR=0 as shipped)
PLANTED  expected=1  measured=1
STRIPPED expected=0  measured=0
CR.CTL   PASS
```

**The census:**

```
CR.resources\bootstrap.ps1            PASS   cr=0
CR.resources\clawfactory-grants.ps1   PASS   cr=0
CR.resources\clawfactory-stop.ps1     PASS   cr=0
CR.resources\launcher.ps1             PASS   cr=0
CR.resources\post-install.ps1         PASS   cr=0
CR.resources\rename-agent.ps1         PASS   cr=0
CR.resources\smoke-test.ps1           PASS   cr=0
CR.resources\switch-provider.ps1      PASS   cr=0
CR.resources\uninstall.ps1            PASS   cr=0
CR.setup.ps1                          PASS   cr=0
NONZERO_FILES=(none)

ON_BOX_NOT_EXPECTED = (none)
EXPECTED_NOT_ON_BOX = (none)
CR_MISMATCH         = (none)
BYTE_MISMATCH       = (none)

CR.SET    PASS  the set of shipped .ps1 on the box is the set the repo bundles
CR.HELD   PASS  every shipped script matches the repo CR count at this commit
CR.BYTES  PASS  every shipped script matches the repo BYTE COUNT at this commit

PASS=15 FAIL=0 VOID=0 INFO=0  (counted 15 of 15)
controls fired=1/1; preconditions met=1/1
```

**Three things this establishes that are worth separating.**

1. **The CR count itself is zero on all ten**, which is what section 14.11 asked
   for. The repo pins `*.ps1 text eol=lf`, so any CR here would be a divergence
   between shipped bytes and committed bytes — the exact class that had ten
   bundled files silently CRLF as recently as v1.4.3.
2. **`CR.SET` closes a question the census alone would not have.** A per-file CR
   count over a set that quietly gained or lost a member reports a clean sweep of
   the wrong set. Both directions are reported as separate counts because an extra
   file and a missing file are different defects.
3. **`CR.BYTES` corroborates section 14.8 per file rather than over a sample.** Box
   A proved bundled bytes are committed bytes for the set it sampled; this compares
   every one of the ten against the repo at the commit under test, and a byte
   difference with an equal CR count would have meant the divergence was something
   other than line endings.

**The held copy was regenerated from `HEAD` at dispatch time, not reused from the
dry-run file**, so what was compared is what is committed now.

---

## 9. `#261`: MY FIRST READING IS RETRACTED, AND CLAUSE 1 IS WHY IT WAS CAUGHT

### 9.1 Revision 1 measured 1 of 8 hosts and reported a clean PASS

```
PASS=6 FAIL=0 VOID=0 INFO=2  (counted 8 of 8 recorded rows)
PHASE VERDICT: PASS. Every positive control fired and every precondition was met.
```

**That verdict is withdrawn.** It is arithmetically true and substantively
worthless: the phase probed **one** toolchain host out of eight.

The cause is a shape assumption one level below the identifier. The probe
discovered the right FILE — `/etc/clawfactory/toolchain-hosts.seed`, quoted from
`setup.ps1:1721` — and then assumed its CONTENT was one host per line. It is not:

```
setup.ps1:1721   printf '%s\n' "$TOOLCHAIN_HOSTS" > /etc/clawfactory/toolchain-hosts.seed
```

The variable is **quoted**, so all eight hostnames land on a single
space-separated line. Three lines above, in the same block, `printf '%s\n'
$ALLOWED_IPS` is **unquoted** and does give one per line. Two idioms, three lines
apart, opposite results. A parser taking `(\S+)` off each line kept
`api.clawhub.ai` and dropped seven hosts in silence.

### 9.2 What caught it, precisely, because that is the transferable part

**The probe printed the raw content it discovered.** So the transcript carried, on
adjacent lines:

```
TC_HOST api.clawhub.ai api.github.com clawhub.ai codeload.github.com github.com objects.githubusercontent.com raw.githubusercontent.com registry.npmjs.org
DISCOVERED_TOOLCHAIN_HOSTS  = api.clawhub.ai
```

**The defect is visible only because both lines are there.** Every summary number
in that run was internally consistent — 8 of 8 rows counted, 2 of 2 controls fired,
2 of 2 preconditions met, `HOSTS_MEASURED=3 of 3 requested` — and every one of them
was consistent with the wrong set. Nothing but the raw print distinguished
"measured all eight" from "measured one".

**This is clause 1 earning its place, and it also sharpens it.** The clause as
written says to discover the *identifier*. This defect was one level down: the
identifier was right and the *shape of its content* was assumed. The general form
is **discover the value, not just the name, and print what you found** — an
enumeration derived from a file must show the file.

It is also, exactly, the project's characteristic defect reproduced inside the tool
built to detect it: *a check that produced a verdict without measuring its actual
subject.* Third time this session, all three in my instruments, none in the product.

### 9.3 The fix, and its dry-run

Split on whitespace, which handles both shapes. Dry-run against a rig reproducing
the real cfv-180 content verbatim:

```
DISCOVERED_TOOLCHAIN_HOSTS  = api.clawhub.ai api.github.com clawhub.ai
                              codeload.github.com github.com
                              objects.githubusercontent.com
                              raw.githubusercontent.com registry.npmjs.org
DISCOVERED_READFETCH_HOSTS  = docs.python.org outlook.office.com
HOSTS_MEASURED=12 of 12 requested
```

Eight toolchain hosts and both read-fetch shapes parsed.

### 9.4 What revision 1 does establish, kept because it is real

Two readings from that run stand on their own and are not affected by the
undercount, because they are per-host measurements that were actually taken:

```
ATT api.anthropic.com  ok=12 n=12   ALWAYS        <- control, must connect
ATT example.org        ok=0  n=12   NEVER         <- control, must not
ATT api.clawhub.ai     ok=11 n=12   INTERMITTENT
```

**The controls discriminate in both directions on this box**, which is what makes
any count here meaningful, and `api.clawhub.ai` at **11 of 12** is a genuine
`#261`-class sample. The full-set reading follows in section 10.

---

## 10. `#261`: THE MEASUREMENT. 96 attempts across 8 toolchain hosts. **NO VERDICT**

Ten hosts, twelve attempts each, as uid 1000, switch confirmed ON.

```
TOOLCHAIN_SWITCH_ENABLED = True
HOSTS_MEASURED=10 of 10 requested
PASS=13 FAIL=0 VOID=0 INFO=9  (counted 22 of 22 recorded rows)
controls fired=2/2; preconditions met=2/2
PHASE VERDICT: PASS
```

### 10.1 The raw counts

| Host | Class | Connected | State |
| --- | --- | --- | --- |
| `api.anthropic.com` | **CONTROL, must connect** | **12 / 12** | ALWAYS |
| `example.org` | **CONTROL, must not** | **0 / 12** | NEVER |
| `clawhub.ai` | toolchain | 12 / 12 | ALWAYS |
| `objects.githubusercontent.com` | toolchain | 12 / 12 | ALWAYS |
| `raw.githubusercontent.com` | toolchain | 12 / 12 | ALWAYS |
| `registry.npmjs.org` | toolchain | 12 / 12 | ALWAYS |
| `codeload.github.com` | toolchain | 10 / 12 | **INTERMITTENT** |
| `api.clawhub.ai` | toolchain | 9 / 12 | **INTERMITTENT** |
| `github.com` | toolchain | 7 / 12 | **INTERMITTENT** |
| `api.github.com` | toolchain | 6 / 12 | **INTERMITTENT** |

**Both controls fired in the same run**, which is what makes every other number on
this table mean something: the probe demonstrably can connect and can be refused,
so a shortfall is neither a dead network nor a probe that always says yes.

### 10.2 The two questions, kept on separate rows

**`AT.EXISTS` — PASS for all eight toolchain hosts.** Every one answered at least
once, so the boot/refresh path built a working route to each. That is card `#276`
territory and `#276` is closed; this is a corroboration of it on a
`-Provider later` box, which is a variant it had not been measured on.

**`AT.ALWAYS` — recorded INFO, raw counts only, for all eight.** Four of eight
answered on every attempt; four did not. **This session records no verdict on
`#261`, proposes no fix and makes no recommendation about it.** The job card is
explicit that this is the operator's call and he has it.

### 10.3 What the sample adds to the two readings box A had

Box A had one PASS before a reboot and one after — two single-shot readings, of
which the second was of one host. This run contributes **96 attempts across eight
distinct hosts**, and one incidental cross-check worth naming: `api.clawhub.ai`
returned **11/12 in revision 1 and 9/12 in revision 2**, minutes apart on the same
box with nothing changed between them. Two different counts for the same host in
one session is itself a direct observation of the variability `#261` describes,
independent of any single number in the table.

**Stated as INFERRED, because it is argued rather than measured:** the split — four
hosts at 12/12 and four below — is *consistent with* the documented mechanism, a
firewall holding a resolved address snapshot while a service answers from a
rotating pool. Nothing in this run measures the pool itself, so that is an
interpretation offered to the operator, not a finding.

---

## 11. THE TASK 0.2 FIX, MEASURED ON A REAL BOX. Row 14 is **VOID**, not FAIL

Phase 3 was run on box B for one purpose: to see whether the precondition added
under TASK 0.2 behaves on a real unconfigured machine the way it behaved against a
rigged channel. It does.

**The credential is absent, measured rather than assumed:**

```
cred : stat: cannot statx '/etc/clawfactory/send-credential.json': No such file or directory
CREDENTIAL_ABSENT
Real credential configured: False
```

**Same artifact, same unconfigured state, before and after the fix:**

| | cfv-179 (box A) | cfv-180 (box B) |
| --- | --- | --- |
| Tally | `PASS=14 FAIL=7 VOID=4 INFO=1` | `PASS=0 FAIL=0 VOID=27 INFO=1` |
| Preconditions | `declared=0 met=0` | `declared=1 met=0` |
| Phase verdict | **FAIL** | **VOID (instrument)** |

```
G2.CRED  VOID  PRECONDITION: an SMTP send credential is configured on this box
               NOT MET: ... Nothing downstream of this is a product verdict.
PHASE VERDICT: VOID (instrument). This phase reports no product result at all.
```

**Seven FAILs became zero, and none of them was ever a product defect.** A reader
skimming box A's row 14 would have concluded the approval-gated send path is broken
on v1.4.4. It is not; it is unconfigured, and the results file now says so in the
runner's own vocabulary.

### 11.1 The cost I flagged in advance is visible, and it is bounded

Nine rows are annotated `(was PASS, voided with the phase)`:

```
G2.CHAN  G2.0  G2.sink  G2.8  G2.8c  G2.9  G2.9ctlA  G2.9ctlB  G2.12  G2.10c  G2.199b
```

These are the credential-**independent** measurements — the request-socket ownership
and modes, the five approval channels the agent cannot use, the SMTP route blocks
for uid 1000 with both its controls, the broker-down loud-failure path, and the
ad-hoc-transport check. **They passed on their own merits and the runner records
that they did**, then withholds certification because the phase as a whole could not
be trusted. Nothing is lost from the record; what changes is that none of it is
claimed as a verdict.

That is the correct behaviour under PROMPT 15's rule and it is what box A
recommended. It is also a reason to split the phase, which stays carded: a suite
where a third of the rows do not depend on the precondition that voids them is a
suite doing two jobs.

### 11.2 Scope, so this is not read as more than it is

**This run does not certify Guard 2 and is not offered as row 14's verdict for the
release.** Row 14 becomes a real verdict only on a box where the credential exists,
which is **box D**. What box B establishes is narrower and was its whole purpose:
*the instrument now reports an unconfigured box as unmeasured rather than as
broken.*

**Zero outbound email.** `phase3b` was not run, `-ExpectRealCredential` was not
passed, `G2.198` recorded VOID with its reason, and the only SMTP destination
anywhere in the phase is the local sink on `127.0.0.1:2525`.



---

*This close-out is written as the run proceeds and is committed after every phase,
so an interruption at any point leaves an honest record rather than a missing one.*
