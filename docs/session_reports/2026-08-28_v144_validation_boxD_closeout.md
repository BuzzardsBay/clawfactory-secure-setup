# CLOSE-OUT: v1.4.4 validation, BOX D — the keep-Linux uninstall, and the fitness verdict

**Companion to** `2026-08-27_v144_validation_boxA_closeout.md`,
`2026-08-28_v144_boxA_lessons_and_next_job_guidance.md` (the five clauses) and
`2026-08-28_v144_validation_boxBC_closeout.md` (whose section 21 is this box's spec).

**Scope.** Box D: the keep-Linux uninstall branch — the v1.4.2 change set, which
has never been measured on any release — plus the SMTP credential rows that
VOIDed on box A, the rendered dialog, and **the fitness-to-publish statement
aggregating all four boxes.**

*This close-out is written as the run proceeds and committed after every phase, so
an interruption at any point leaves an honest record rather than a missing one.*

---

## 0. PROMPT 15 preamble

Pasted in full from `FrontierAI_CC_Prompt_Library.md`, VM clauses included. The
copy read carries **`PROMPT 15` at line 645 of 925 and is NOT stale** — the same
position boxes B and C recorded. Nothing was deleted from it.

The five clauses from box A's root-cause analysis are in force, with clause 1
sharpened per the B/C close-out §20.3. Each is answered specifically in §17.

---

## 1. THREE CHALLENGES TO THE JOB CARD, RAISED BEFORE PROVISIONING

PROMPT 15: *"If an instruction is factually wrong about the code, STOP and report.
Do not quietly build the thing that was meant."*

### 1.1 TASK 3.2's premise is factually wrong: this dialog cannot carry mojibake

The card states the mojibake class *"renders em dashes as three garbage characters
in this dialog"* and asks the operator to confirm it in the **uninstall** dialog.

**It cannot appear there.** Measured on the bytes under test:

```
resources/uninstall.ps1   nonascii_lines=0   first3bytes=5b 43 6d   ("[Cm")
```

The defect is an encoding failure — UTF-8 without a BOM decoded by PowerShell 5.1
as the ANSI codepage — so a file containing **zero non-ASCII bytes** has nothing
to mangle. Box A's own close-out says the same at §18.1: *"It renders with no
mojibake, because it uses ASCII punctuation."*

The class lives in `rename-agent.ps1` (5 user-visible occurrences) and
`bootstrap.ps1` (2), with comment-only instances in `launcher.ps1`,
`post-install.ps1` and `setup.ps1`.

**Resolution, agreed with the operator before provisioning.** TASK 3.1 runs
unchanged. TASK 3.2 is recorded as a **measured negative** — the byte census
above, plus whatever the operator actually sees — rather than sending him hunting
for something the bytes say is not there. The mojibake decision owed under TASK
7.3 is unaffected: it remains a real, carded, customer-visible defect, in a
different dialog.

### 1.2 TASK 1.3 as written would have sent real email. This is the material one

The card states *"Phase 3's test 3 and test 6 write to a local sink and are safe."*

**That is true only while the credential points at the sink.** Phase 3 test 3
calls the shipped broker's approve path:

```
validation/interim-v120-phase3.ps1:216
    node /usr/local/sbin/clawfactory-sendctl.js approve '$reqId' '$payHash'
```

Nothing in phase 3 redirects the send. The sink is the **credential**, written by
`interim-v140-stagebox.ps1`. With the real Gmail credential configured, test 3
opens an SMTP session to `smtp.gmail.com:587` and transmits a message to
`sink@example.com` — and `Set-SendCredential` **authorises that destination in the
egress policy as part of saving it** (`clawfactory-sendd.js:680`, *"Configuring
SMTP is the act that authorizes its destination"*), so the firewall does not stop
it. Test 6 has the same shape.

"Configure the real credential, then run phase 3" and "zero outbound email is
authorised" cannot both hold.

**Resolution, agreed before provisioning — and it converts MORE rows than the
card's own reading, with zero outbound email:**

| Stage | Credential on the box | Rows that become real verdicts |
| --- | --- | --- |
| Phase 3 (matrix row 14) | **sink**, `127.0.0.1:2525`, written by root tooling | the row-14 mechanism rows, and **`G2.10`** (credential file unreadable by the agent uid). `G2.13` records VOID *"synthetic"* — which is TASK 1.4's rule firing correctly, not a gap |
| Phase 4 `-PostReboot` | **real Gmail**, entered by the operator in Studio | **`S.4`** and **`S.4leak`**, scanned against the actual secret |

Phase 4 `-PostReboot` runs two sections only — TCP connect probes as `clawuser`,
and the credential permission and leak scan. **It never calls `approve` and never
transmits**; verified in source rather than assumed. `credential-set` makes no
SMTP connection on save. The real credential is therefore on the box only during
a phase that has no send path in it.

`#198` stays VOID and `-ExpectRealCredential` is never passed.

### 1.3 Box D fits in one session, but it is the tightest of the four

Stated before `az vm create`, with a named split point. See §4.

---

## 2. THE ARTIFACT. Derivation 1 agrees

| | |
| --- | --- |
| version | v1.4.4 |
| signed sha256 | `6e65560325cb6d7d3fea204ebb72876b3b113cbbfe9f2fa4f94113237e9eb4d1` |
| signed bytes | 440,610,608 |
| build commit | `25945d5` |

**Derivation 1, on the build machine, by hand — and the Authenticode check run
FIRST, per the post-expiry lesson:**

```
Output\ClawFactory-Secure-Setup.exe
DERIV1_SHA256=6e65560325cb6d7d3fea204ebb72876b3b113cbbfe9f2fa4f94113237e9eb4d1   MATCH_SHA=True
DERIV1_BYTES=440610608                                                           MATCH_BYTES=True
AUTHENTICODE=Valid
SIGNER=CN=Bret Mckinney, O=Bret Mckinney, L=West Valley City, S=ut, C=US
```

Equal to the value the job card carries. Derivations 2 (blob, by download and
re-hash) and 3 (on the box after transfer) are performed at staging and recorded
in §5.

---

## 3. TASK 0.2: THE STALE-DEFAULT SWEEP, SIXTH CONSECUTIVE RUN

### 3.1 Scope and totals

Scope matches boxes B/C and adds `resources/*.sh`: `validation/**` (`.ps1`, `.md`,
`.sh`), `scripts/**`, `setup.ps1`, the `.iss`, `released-versions.tsv`,
`.gitattributes`.

```
SWEPT_FILES=91   (.gitattributes=1  .iss=1  .md=6  .ps1=79  .sh=3  .tsv=1)
  DIGEST   hits=42     distinct=31        [box A: 58 files / 920 hits]
  VERSION  hits=666    distinct=103       [box B/C: 89 files / 2082 hits]
  BYTES    hits=17     distinct=16
  HOST     hits=485    distinct=57
  ARTPATH  hits=29     distinct=6
  VMNAME   hits=258    distinct=59
TOTAL_HITS=1497
```

**The vacuity guard throws rather than reporting clean** if fewer than 50 files
match. The v1.4.3 instrument once reported `LEGACY_PROBE_FILES=0` from a bad glob,
which made every "no hits" column mean "nothing was searched".

**One pattern change worth naming: the DIGEST class is CASE-INSENSITIVE this run.**
`Get-FileHash` returns UPPERCASE hex, so a lowercase-only pattern is blind to
exactly the shape this repo produces. Five uppercase digests exist in the tree
(`REPORT_bisect_v1026_v1027.md`, `REPORT_v1.0.26/27/28.md`) and a lowercase-only
sweep would not have seen any of them. They are archived v1.0.2x reports and none
is a live pin, so nothing was stale — but the blindness would have been real.

### 3.2 The canary, in three shapes proven absent BEFORE planting

A canary certifies a pattern only against the shape of the canary, so absence was
**measured first**:

| Shape | Instances in the tree before planting |
| --- | --- |
| digest + byte count inside an **HTML comment in a `.md`** | **0** (`<!--` count = 0 across all six swept `.md`) |
| digest inside a **`.sh` HERE-DOC BODY** | **0** (no 64-hex in any `.sh` in scope) |
| **UPPERCASE-hex digest inside a `.ps1`** — the shape `Get-FileHash` returns | **0** |

Two further shapes were tested and **rejected as canaries because the tree already
contains them**: uppercase digests in `.md` (5 instances) and `cfv-` names with a
letter suffix (69). Recorded because a canary planted in a shape that already
exists certifies nothing.

Canary lengths were **asserted, not eyeballed** — box B/C's `.sh` digest canary was
written 62 characters long and the sweep correctly did not match it, which is
indistinguishable from a blind instrument:

```
CANARY_LEN_OK  dLower = 64
CANARY_LEN_OK  dUpper = 64
CANARY_LEN_OK  dSh    = 64
```

**12 of 12 canary hits, across four classes and three shapes, first attempt:**

```
CANARY_HIT  AA11BB22…DD77   validation\harness-selftest.ps1:475     DIGEST
CANARY_HIT  aa11bb22…dd66   validation\MANUAL_CHECKS_studio.md:445  DIGEST
CANARY_HIT  bb22cc33…ee88   validation\sp-prefix-fw.sh:74           DIGEST
CANARY_HIT  v1.3.9          (all three files)                       VERSION
CANARY_HIT  440607777 / 440601234 / 440609999                       BYTES
CANARY_HIT  cfv-999z        (all three files)                       VMNAME
```

### 3.3 INSTRUMENT DEFECT #1 — the restore reported success while doing the opposite

**Caught before any VM existed, by `git status --short`.**

The restore script re-ran its save-originals block before reaching the restore
branch, so it overwrote the saved originals with the **planted** bytes and then
"restored" those — reporting `match=True` against the wrong baseline:

```
=== RESTORE (defective run) ===
ORIG     MANUAL_CHECKS_studio.md  sha=044f206adbbb1b1b bytes=24758   <- the PLANTED file
RESTORED MANUAL_CHECKS_studio.md  sha=044f206adbbb1b1b bytes=24758 match=True

=== the independent check that caught it ===
git status --short
 M validation/MANUAL_CHECKS_studio.md
 M validation/harness-selftest.ps1
 M validation/sp-prefix-fw.sh
```

**A success marker compared against a baseline the same run had already
corrupted.** That is the project's characteristic defect — a verdict taken without
measuring its actual subject — reproduced inside the tool built to avoid it, for
the fourth session running. The only thing that caught it was a check that did not
share the instrument's state.

Restored properly, by truncating to the byte counts the **plant** run recorded, and
verified three ways. **Never `git checkout --`**: under this machine's system-level
`core.autocrlf=true` it silently re-materialises a file as CRLF while `git status`,
`git diff` and `grep` all read clean.

```
UNPLANTED MANUAL_CHECKS_studio.md  sha=e0a5922ff40c03a6 bytes=24616 matchesOriginal=True
UNPLANTED sp-prefix-fw.sh          sha=bee579419e262c70 bytes=3771  matchesOriginal=True
UNPLANTED harness-selftest.ps1     sha=6d2d75633d666eda bytes=31740 matchesOriginal=True
git status --short   -> empty
git ls-files --eol   -> i/lf w/lf on all three, unchanged
```

### 3.4 The enumeration: every load-bearing pin re-derived, not assumed

```
PIN.soul        setup.ps1:2846        CURRENT   resources\safety-rules.md
PIN.persona     setup.ps1:2945        CURRENT   resources\persona.md
PIN.studioAsar  phase1:95             CURRENT   Studio desktop\release\win-unpacked\resources\app.asar
Studio installer build_release:450    CURRENT   resources\ClawFactory-Studio-Setup-1.3.2.exe
orchestrator    bundlebytes:143       CURRENT   resources\orchestrator-prompt.md
Apache-2.0      .gitattributes:101    CURRENT   LICENSE
RUNBOOK_v135.md:11                    CURRENT   validation\sp-prefix-fw.sh
```

Seven re-derivable pins, seven CURRENT. `PIN.workspaceSoul` (`setup.ps1:2946`) is
current by construction and its two sites agree. `PIN.rootfs` (`setup.ps1:467`) is
current and still a dead literal — nothing compares it post-install; left alone,
as in v1.4.3 and boxes A/B/C.

**Version literals, the load-bearing subset — all four agree:**

```
ClawFactory-Secure-Setup.iss:9    #define MyAppVersion    "1.4.4"
ClawFactory-Secure-Setup.iss:16   #define StudioInstaller "ClawFactory-Studio-Setup-1.3.2.exe"
setup.ps1:56                      $InstallerVersion       = '1.4.4'
interim-v120-phase1.ps1:97        version                 = '1.4.4'
released-versions.tsv:47          1.4.4  unsigned 548562c7…  440594967  2026-08-27
```

`MANUAL_CHECKS_studio.md` is **CURRENT for a second consecutive run** — header
reads v1.4.4 (line 5), check 6f names installer 1.4.4 and Studio 1.3.2 (lines
272–273). Box A's fix has now held across two releases of scrutiny.

**Deliberately stale, and left stale, all out of scope and all on drivers no
current path invokes:** `interim-v120-validate.ps1:180-181` (forbidden by PROMPT
15 — it calls `az vm user update` after provisioning; refreshing its digest would
make a forbidden instrument look blessed), `validation\diag\g4-probe.ps1:76-77`,
`job3-validate.ps1:66`, `scripts\azure-validate.ps1:55`.

**One ARTPATH hit newly classified this run:** `scripts\egress-persistence-probe.ps1:68`
names `C:\cfv\ClawFactory-Studio-Installer.exe`, a filename no current driver
stages. Same class as the four above — an out-of-scope diagnostic — and **not
repointed**, for the same reason.

**`setup.ps1` carries 14 `cfv-` matches, and none is a stale default.** All
fourteen are in **comments**, recording which validation box caught which defect
(`cfv-128`, `cfv-167`, `cfv-0717d`, …). That is deliberate audit-trail
documentation in shipped bytes, classified rather than flagged.

**The six stale `$VmName` defaults are unchanged from boxes A, B and C:**

```
validation/finish-and-park.ps1:27       'cfv-162'
validation/interim-v120-job.ps1:31      'cfv-153'
validation/interim-v120-validate.ps1:33 'cfv-153'
validation/job3-validate.ps1:56         'cfv-152'
validation/diag/g4-probe.ps1:52         'cfv-165'
scripts/azure-validate.ps1:47           'cfv-138'
```

All six name boxes that no longer exist — which §4.1's estate listing proves
independently — so **all six fail safe**: an `az` call against a deleted VM errors
rather than quietly measuring the wrong machine. `-VmName` is passed explicitly on
every invocation this session. Not fixed, for box A's reason; carded as `#302`.

**Byte counts:** 17 hits, 16 distinct — twelve ledger rows plus the five
digest/byte pairs already classified. No unexplained value.

**The sweep instrument itself is not committed** — a throwaway, as in v1.4.3 and
boxes A/B/C. Committing it would imply a maintenance promise this job did not make.

---

## 4. TASK 0.1 AND 0.3: THE PLAN AND THE STARTING ESTATE

### 4.1 The estate before anything was provisioned, unfiltered and subscription-wide

```
=== az vm list -d, SUBSCRIPTION-WIDE ===        VM_EXIT=0    (no rows)
=== az resource list, ALL RESOURCE GROUPS ===   RES_EXIT=0
clawfactory-validation  clawfactoryvalc467             Microsoft.Storage/storageAccounts
clawfactory-validation  bake-vmVNET                    Microsoft.Network/virtualNetworks
clawfactory-validation  clawfactory-win11-baseline     Microsoft.Compute/images
clawfactory-validation  clawfactory-win11-baseline-v2  Microsoft.Compute/images
NetworkWatcherRG        NetworkWatcher_westus2         Microsoft.Network/networkWatchers
clawfactory-signing     clawfactory-signing            Microsoft.CodeSigning/codeSigningAccounts
DISK_EXIT=0  NIC_EXIT=0  PIP_EXIT=0  NSG_EXIT=0   -- all four empty
```

**Exactly the expected residual and nothing else.** Zero VMs, disks, NICs, public
IPs, NSGs. Every exit code read, never inferred from empty output. `az disk list`
was issued **with** `-g` deliberately: the subscription-wide form exits 2 with a
required-argument error whose empty output reads exactly like "no disks exist".

### 4.2 The plan, recorded BEFORE `az vm create`

**One box, `cfv-182`, `Standard_D2s_v4`, `clawfactory-win11-baseline-v2`.** Phase
order is fixed and each position is load-bearing:

| # | Step | Why here |
| --- | --- | --- |
| 1 | Install v1.4.4 clean, `-Provider claude` | everything needs it |
| 2 | `stagebox` → **sink** credential + read-fetch seed | phase 3's precondition, safely |
| 3 | **Phase 3** — matrix row 14, `G2.10` | must run before a real credential exists (§1.2) |
| 4 | Reboot, dispatched | |
| 5 | **Operator: Studio → Approvals → Email settings → real credential** | folded into the post-reboot login, saving a touch |
| 6 | **Phase 4 `-PostReboot`** — `S.4`, `S.4leak` | scan-only; no send path in it |
| 7 | **`uninstate -Mode Before`**, held and hashed | the after-state means nothing without it |
| 8 | **Operator: uninstall #1, choose NO** + quote the dialog | TASK 2.3, TASK 3 |
| 9 | `uninstate -Mode After`, `keepleftovers`, `teardownlog -Expect OK` | TASK 2.4, 2.6 |
| 10 | **`nextboot`** — distro restart with a boot_id control | TASK 2.8 |
| 11 | **Reinstall, confirm it completes** | TASK 2.5 — the row that flips v1.4.1's NO |
| 12 | `teardownfault -Mode Inject` | TASK 2.7 |
| 13 | **Operator: uninstall #2, choose NO** + quote the incomplete dialog | TASK 2.7's other half |
| 14 | `teardownlog -Expect INCOMPLETE`, cleanup, teardown | |

**Estimate, stated before it is spent:** ~8–9 hours excluding operator latency;
**4 operator touches**; one `Standard_D2s_v4` at ~$0.10/hour, so **$0.60–0.90**.

**Does box D fit in one session? Yes, and it is the tightest of the four.** Boxes
B and C together carried two installs and no reboot; box D carries two installs,
two uninstalls, a reboot and a distro restart on one box.

**The split point, agreed with the operator: stop after step 11.** That banks the
entire v1.4.2 change set, the read-back, the teardown marker, the next-boot check
and the reinstall. Steps 12–13 are the only items needing a second
install/uninstall cycle and would make a ~2-hour box E.

**No new probe is authored after hour six.** If one is needed it is named and
parked.

---

## 5. TASK 0 HARNESS WORK: FOUR NEW PROBES, ALL DRY-RUN BEFORE PROVISIONING

Box A's process finding, confirmed by boxes B and C: **every defect written after
hour six survived into the run; every probe dry-run against a rigged input before a
VM existed was cheap to fix.** All four probes below were written cold and
exercised against inputs whose correct answer was known in advance.

| Probe | What it measures |
| --- | --- |
| `interim-v144-uninstate.ps1` | the held before-state and the read-back against it |
| `interim-v144-teardownlog.ps1` | `CLAWFACTORY_TEARDOWN_OK` / `_INCOMPLETE` and the `READBACK` line |
| `interim-v144-nextboot.ps1` | nothing ClawFactory installed runs at the next boot of the kept distro |
| `interim-v144-teardownfault.ps1` | the negative half: make the teardown fail on purpose |

### 5.1 Why `uninstate` exists rather than reusing `interim-v141-uninstall.ps1`

That probe reads **eighteen named subjects** and was written for v1.4.1. The
v1.4.2 change set is about **completeness** — it grew the uninstaller's unit list
from five names to eleven and its `/usr/local/sbin` list from twelve to seventeen.
A probe that names a subset of those files reports a clean sweep over the wrong
set, which is the v1.4.2 defect class reproduced inside the instrument.

So `uninstate` **enumerates**: `ls` the directories, print the raw listing, and only
then compare against an expectation derived from `resources/uninstall.ps1` and
quoted in the probe. Both directions of the set difference are separate counts,
because an extra file and a missing file are different defects.

That is clause 1 as sharpened by boxes B and C: **discover the VALUE, not just the
name, and print what you found.**

### 5.2 Why the fault is `chattr +i` on a file in `/etc/clawfactory`

Three properties decided it, and the rejected alternative is the more useful half:

* **The shipped teardown cannot clear it.** It runs `chattr -i` on exactly three
  paths, all under `/home/clawuser/.openclaw`, so an immutable file in
  `/etc/clawfactory` survives the very operation it obstructs. `rm -rf
  /etc/clawfactory 2>/dev/null` then leaves the directory, with its error
  suppressed — so the failure is invisible **except** through the read-back this
  test exists to exercise.
* **A rigged systemd unit was rejected**, because the drift backstop
  `rm -f /etc/systemd/system/clawfactory-*.service` would sweep it. That is
  exactly the mistake that cost `PG.3f` two installs on boxes B and C: a rig
  erased by the run it exists to interrupt.
* It is exactly reversible, and it touches **no shipped byte**. Clause 5 is not in
  play.

### 5.3 The dry-runs. 19 of them, and the ones that matter are the ones that VOID

```
uninstate Before, complete install          PASS=8  FAIL=0            controls 3/3      rc=0
uninstate After,  clean teardown            PASS=23 FAIL=0 INFO=1     controls 3/3      rc=0
uninstate After,  READER BROKEN             PASS=0  FAIL=0 VOID=23    controls 2/3      rc=4
uninstate After,  real residual             PASS=17 FAIL=6  INFO=1    controls 3/3      rc=1
uninstate Before, MALFORMED RIG             throws, refuses to run                      rc=-1

teardownlog  ok log,         -Expect OK          STATE=TEARDOWN_OK          PASS=7 FAIL=0  rc=0
teardownlog  incomplete log, -Expect INCOMPLETE  STATE=TEARDOWN_INCOMPLETE  PASS=8 FAIL=0  rc=0
teardownlog  ok log,         -Expect INCOMPLETE  STATE=TEARDOWN_OK          PASS=4 FAIL=4  rc=1
teardownlog  incomplete log, -Expect OK          STATE=TEARDOWN_INCOMPLETE  PASS=4 FAIL=3  rc=1
teardownlog  NO marker,      -Expect OK          STATE=NO_MARKER            PASS=3 FAIL=4  rc=1
teardownlog  RemoveAll log,  -Expect OK          BRANCH_STATE=REMOVE_ALL    VOID=3         rc=4

nextboot  clean                     CFUNIT_STATE=NONE_LISTED   FW_STATE=ABSENT          PASS=6  rc=0
nextboot  systemctl cannot answer   CFUNIT_STATE=QUERY_FAILED                           VOID=6  rc=4
nextboot  distro did NOT restart    NB.CTL.RESTART did not fire                         VOID=6  rc=4
nextboot  a unit still enabled      CFUNIT_STATE=SOME_ENABLED  FW_STATE=PRESENT_FAILED  FAIL=3  rc=1

teardownfault  fault lands          FI.CTL.LANDED + FI.CTL.RM both fired   PASS=6        rc=0
teardownfault  chattr silently no-ops  FI.CTL.LANDED did not fire          VOID=6        rc=4
teardownfault  nothing to rig       precondition unmet                     VOID=2        rc=4
teardownfault  cleanup              PASS=4                                               rc=0
```

**Four rigs are the point of the exercise**, and each corresponds to a way a real
run could have produced a confident wrong answer:

* **A reader answering "absent" to everything** would otherwise have reported 23
  PASSes over a distro it could not see. It VOIDs instead, rc=4, every row
  annotated *"(was PASS, voided with the phase)"*.
* **A `systemctl` that cannot reach systemd** prints nothing, and "nothing is
  enabled" reads exactly like a clean box. `NB.CTL.QUERY` turns that into VOID.
* **A distro that did not actually restart** makes an unchanged unit list mean
  nothing. `NB.CTL.RESTART` catches it on the boot_id.
* **A `chattr` that silently no-ops** would produce a fault injection that injects
  nothing — which scores a false pass and looks exactly like a working control.

### 5.4 INSTRUMENT DEFECTS #2 AND #3, both found by those dry-runs

**#2 — a start-anchored marker regex that would have reported `NO_MARKER` on a
perfectly clean teardown.** The first version matched
`^\s*(\[in-distro\]\s*)?CLAWFACTORY_TEARDOWN_OK\s*$`. But `uninstall.ps1` re-logs
every line the distro emitted through `Write-Log`, so the marker actually arrives
as:

```
[2026-08-28T20:11:04] [INFO]   [in-distro] CLAWFACTORY_TEARDOWN_OK
```

which that pattern matches nowhere. **It was caught only because the rigged log was
built in the real line shape rather than a simplified one** — which is box C's
lesson (*"I calibrated against a simplified model of the subject instead of the
subject"*) applied deliberately. Anchored at end of line instead. `_OK` is not a
substring of `_INCOMPLETE`, so the two tests cannot collide.

**#3 — a dry-run seam that failed quietly into an empty state.** The first two
`uninstate` dry-runs read the **build machine's own** Windows state, which is both
meaningless and a read of a box no validation run should touch. Adding a
`-WinRigJson` seam fixed that — but the first rig file was malformed (a heredoc
collapsed `\\` to `\`), `ConvertFrom-Json` threw under `$ErrorActionPreference =
'Continue'`, and the probe carried on with an **empty** Windows state that scored
as *"nothing is installed"*: a FAIL that read like a finding. Same class as box
B/C's 62-character canary — the rig was broken, not the probe — but a seam that
can introduce a silently empty reader defeats the thing this probe exists to
prevent. It now **throws** rather than running, proven in both directions.

### 5.5 Commit

```
b701dda  validation(box D): four probes for the keep-Linux uninstall, all dry-run before provisioning
```

All four files are `i/lf w/lf` in `git ls-files --eol`. `git status --short` is
empty. **No shipped byte was changed.**

---

## 6. BOX PROVISIONED AND STAGED. All three derivations agree

```
[17:09:44]   uploaded combined-cfv-182.exe (440610608 bytes, confirmed at the service)
[17:22:39] Staged, digest re-verified ON THE BOX. OK staged;
           artifact=6e65560325cb6d7d3fea204ebb72876b3b113cbbfe9f2fa4f94113237e9eb4d1 size=440610608
[17:23:11]   WROTE wrapper=5201 runner=112 AutoAdminLogon=
```

**Derivation 1** by hand on the build machine (§2), **derivation 2** through blob
storage with the byte count confirmed at the service on upload, **derivation 3**
re-hashed on the box after a 440 MB transfer. The instruction was to stop if any
differed. None did.

`AutoAdminLogon=` is empty and was **asserted rather than set**. The driver arms no
auto-logon, which is what makes the operator login the correct price of the
PROMPT 15 credential rule rather than a defect to engineer around.

**The RDP scope was verified twice, independently** — once by the driver's own
read-back and once by a separate `az network nsg rule show` from this session,
with this machine's live public address re-read at the same time rather than
carried forward:

```
allow-rdp   67.164.251.99/32   3389   Allow   Inbound      NSG_EXIT=0
ProvisioningState/succeeded, PowerState/running           VM_EXIT=0
public IP: 20.69.122.150                                  IP_EXIT=0
this machine's live public address, re-read: 67.164.251.99
```

Never `0.0.0.0/0`, and the /32 was checked against reality rather than against
what it had been earlier.

**On the admin credential.** `az vm create` requires a value, so the driver
generates a random bootstrap password, passes it once and nulls it without
printing it. The operator set their own at Card 1. **This session never called
`az vm user update`, never generated, printed or requested a password, and never
saw one.**

### 6.1 Resources created, recorded now so teardown can be checked against them

```
cfv-182         Microsoft.Compute/virtualMachines
cfv-182-osdisk  Microsoft.Compute/disks
cfv-182VMNic    Microsoft.Network/networkInterfaces
cfv-182-pip     Microsoft.Network/publicIPAddresses
cfv-182-nsg     Microsoft.Network/networkSecurityGroups
```

Five resources. `az vm delete` removes only the first, so teardown sweeps the
other four explicitly, **NIC first**, because it references the public IP and the
NSG.

---

## 7. THE INSTALL, AND PHASE 1. **PASS, 15/0/0/4 of 19**

The install ran in the operator's interactive session and was polled from here,
one `run-command` at a time, reading the runner heartbeat separately from the
install state so *"runner alive, job slow"* and *"runner dead"* stay
distinguishable. Nine polls over roughly fourteen minutes:

```
poll 9/40  az_exit=0  17:52:52
PHASE1_DONE=True
SEED_OK=True
RUNNER_HEARTBEAT=2026-08-28T23:55:52
INSTALL_RESULT=INSTALLER_DONE=success
LOG_TAIL:
  2026-08-28 23:53:53.109   Need to restart Windows? Yes
  2026-08-28 23:53:53.117   Will not restart Windows automatically.
  2026-08-28 23:53:53.170   Log closed.
```

**Phase 1's verdicts:**

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
PHASE VERDICT: PASS
```

**Evidence was retrieved through a byte-count gate, not read off the console:**

```
PULLED C:\cfv\phase1-out-probe.txt  vmBytes=11150 localBytes=11150 match=True
PULLED C:\cfv\phase1-results.json   vmBytes=10426 localBytes=10426 match=True
```

**The two channels were COMPARED, not one trusted.** The results JSON tallies
independently to `PASS 15, INFO 4, TOTAL_ROWS 19` with `controls registered=2
fired=2` — identical to the transcript's own summary line.

**This is a corroboration of box A's row 1, not a re-run of it, and is not
reported as one.** Box A proved the clean install on `-Provider claude` on
`cfv-179`; box B proved the same 34 resources and seven pins land on
`-Provider later`. What box D adds is that the install this box's uninstall will
be measured against is itself complete and pinned — which is the precondition for
everything in §9 onward meaning anything.

---

## 8. THE SINK CREDENTIAL, WRITTEN BY ROOT TOOLING. **PASS 6/6**

Per §1.2, phase 3 runs against a **loopback sink** credential so that the only
code path in this validation that can transmit never has a real destination
behind it.

```
SB.CHAN  PASS  POSITIVE CONTROL: the file-based WSL channel discriminates
SB.1     PASS  SMTP sink credential written by the root tool, and the destination authorised with it
SB.1b    PASS  The credential file is mode 600 root:root as measured on the box
SB.2     PASS  Read-fetch allowlist carries the seeded destination outlook.office.com
SB.3     PASS  Toolchain switch reads ON, with a nonzero live address count
SB.4     PASS  Box state read back for the handover card

CARD_TOOLCHAIN=ON addresses=28
CARD_READFETCH=outlook.office.com
CARD_SMTP=configured 127.0.0.1:2525 as clawfactory-validation

PASS=6 FAIL=0 VOID=0 INFO=0  (counted 6 of 6)
positive controls registered=1 fired=1
PHASE VERDICT: PASS
```

`SB.1b` is worth separating from `SB.1`: *the credential was written* and *the
file only root can read it* are different claims, and only the second is the one
`G2.10` will go on to measure from the agent's side.
