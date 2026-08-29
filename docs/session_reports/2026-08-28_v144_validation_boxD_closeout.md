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

---

## 9. MATRIX ROW 14, PHASE 3. The precondition is MET for the first time, and `G2.10` is CLOSED

With the credential present, the TASK 0.2 precondition fix from boxes B/C is
satisfied rather than bypassed, and the phase produces real verdicts instead of
either box A's seven false FAILs or box B's blanket VOID.

```
G2.CRED  PASS  PRECONDITION: an SMTP send credential is configured on this box

G2.CHAN   PASS  POSITIVE CONTROL: the file-based WSL channel discriminates
G2.0      PASS  Send broker reachable: request socket EXISTS with correct modes
G2.sink   PASS  Local sink listening for mechanism tests
G2.1      PASS  Test 1: agent enqueues, nothing leaves the machine
G2.2      PASS  Test 2: approval card carries the full payload; staged hash equals source
G2.2c     PASS  CONTROL: a subject that was never queued must not appear in the card
G2.3      FAIL  Test 3: approve executes the send and writes a receipt (sink, mechanism)
G2.3b     PASS  Staging purged after send
G2.4      PASS  Test 4: deny sends nothing, receipt records denied, staging purged
G2.5      PASS  Test 5: replay of a consumed approval refused
G2.5b     PASS  Test 5b: wrong payload hash voids the approval
G2.6      FAIL  Test 6: attachment rewritten after approval, approved bytes are the sent bytes
G2.7      PASS  Test 7: expired approval refused, nothing sent
G2.8      PASS  Test 8: agent cannot approve through any of five channels
G2.8c     PASS  CONTROL: a legitimate agent operation still works
G2.9      PASS  Test 9/9b: clawuser has no route to SMTP at any destination, gmail included
G2.9ctlA  PASS  CONTROL (must succeed): allowlisted 443 connects
G2.9ctlB  PASS  CONTROL (must fail): non-allowlisted 443 is blocked
G2.11     PASS  Test 11: root-only file as attachment refused before staging
G2.11c    PASS  CONTROL: a readable attachment is accepted
G2.12     PASS  Test 12: broker down fails loud, preserves the draft, no fall-through
G2.199b   PASS  Card #199b: agent does NOT reach for sendmail, curl, smtplib or any ad-hoc path
G2.10     PASS  Test 10: credential file unreadable by the agent uid
G2.10c    PASS  CONTROL: a world-readable config IS readable by the agent
G2.13     VOID  Test 13: credential value appears in no log, receipt, error path or process listing
G2.198    VOID  Card #198: external delivery, real credential, third-party mailbox
G2.199a   INFO  Card #199a: whether the agent discovers clawfactory-send from the shipped prompt

PASS=23 FAIL=2 VOID=2 INFO=1  (counted 28 of 28 recorded rows)
positive controls registered=1 fired=1
preconditions declared=1 met=1
PHASE VERDICT: FAIL
```

### 9.1 `G2.10` is CLOSED — one of box A's three owed credential rows

```
G2.10   PASS  Test 10: credential file unreadable by the agent uid
G2.10c  PASS  CONTROL: a world-readable config IS readable by the agent
```

Both halves fired. On `cfv-179` this row FAILed **while its own control passed**,
which box A correctly read as the reader working and the subject being absent.
With a credential file present, the permission boundary exists and is measured:
the agent uid is refused, and a world-readable config in the same directory is
not — so the denial is a permission boundary rather than a missing file.

### 9.2 The two FAILs are the PRODUCT REFUSING TO DO SOMETHING UNSAFE

**Neither is a product defect, and the distinction is measured rather than
argued.** `G2.3`'s evidence, verbatim:

```
sink BEFORE=0
{"ok":false,"code":"ESMTP","error":"127.0.0.1:2525 does not offer STARTTLS; refusing to submit in cleartext"}
approve_rc=1
sink AFTER=0
```

and the receipt the broker wrote for it:

```
"result": { "sent": false, "outcome": "smtp_error",
            "error": "127.0.0.1:2525 does not offer STARTTLS; refusing to submit in cleartext" }
```

`send-smtp.js` refuses cleartext submission on any port other than 465. Phase 3's
sink speaks plain SMTP and advertises only `AUTH`. **The product and the test rig
disagree about transport, and the product is right.** A broker that submitted a
credential and a message in cleartext to a server offering no TLS would be the
defect.

**This is a known, documented, pre-existing rig limitation, not a discovery of
this session.** `validation/interim-v140-sinktls.ps1` — committed during the
v1.4.0 cycle — opens with it in as many words:

> *"Phase 3 test 3 has never produced a result in any run of this suite. The
> oldest evidence on the build machine records it as UNTESTED … So the product and
> the test rig disagree about transport, the broker is right, and the rig has
> never been able to accept a message from it."*

`G2.6` fails for the same single cause: it asserts that the **approved** bytes are
the bytes that arrive, and nothing arrives, so the comparison is not made. That
row is the most important assertion in the Guard 2 job — after approval, if the
source attachment is rewritten, do the approved bytes go or the tampered ones —
and a transport refusal leaves it unmeasured rather than failed.

**Recorded honestly: on the phase-3 sink, matrix row 14's verdict is FAIL, and the
two failing rows are caused by the rig, with the product behaving correctly in
both.** The correct response is not to reinterpret the rows but to give them a
sink the broker will talk to, which §10 does.

---

## 10. THE STARTTLS SINK: the refusal is confirmed as a PROPERTY, `G2.6` stays unmeasured

`interim-v140-sinktls.ps1` exists to give the broker a sink it will talk to. Run
on `cfv-182`:

```
ST.CHAN    PASS  POSITIVE CONTROL: the file-based WSL channel discriminates
ST.0       FAIL  Toolchain switch restored to ON and the read-fetch list is back to the seeded entry only
ST.1       PASS  The broker refuses to submit a credential over an unencrypted transport
ST.2.CTL   PASS  POSITIVE CONTROL: the replacement sink is listening and speaks STARTTLS
ST.2       VOID  A sink exists that the broker will accept, so delivery becomes measurable
ST.3       VOID  Test 3 mechanism: approve executes the send and a receipt records it
ST.6       VOID  Test 6: after a post-approval swap, the APPROVED bytes are the sent bytes
ST.4       PASS  The throwaway CA and the replacement sink are gone, verified rather than assumed

PASS=4 FAIL=1 VOID=3  (counted 8 of 8)
positive controls registered=2 fired=2
```

**`ST.1` is the row that converts section 9.2 from an absence into a property.**
The cleartext refusal is now recorded as a *positive* security assertion that
passed, rather than as two rows that failed to produce a result.

**`ST.2`/`ST.3`/`ST.6` VOID for a reason the probe anticipated in its own header:**

```
NODE_TLS_VERDICT=REJECTED unable to verify the first certificate; if the root CA is
installed locally, try running Node.js with --use-system-ca
```

This node build does not read the system trust store, so a locally-trusted CA
cannot make the broker accept the replacement sink. The probe says so and records
VOID **with the reason** rather than as a Guard 2 failure, which is the correct
call. It means **`G2.6` remains unmeasured on this box as on every previous one.**
That is carried into the fitness statement as an explicit gap, not smoothed over.

**`ST.4` PASS matters more than its position suggests:** the throwaway CA and the
replacement sink are gone, verified rather than assumed, so the box does not enter
the reboot pass trusting a test CA.

### 10.1 `ST.0`'s FAIL is a STALE LITERAL IN THE INSTRUMENT, measured not guessed

`ST.0` reported `readFetchIsSeededOnly=False` and explained it with a hard-coded
parenthetical from a different run: *"(the operator added and removed
docs.python.org during check 3 and check 5)"*. **No operator has touched Studio on
this box.** An unexplained FAIL left standing is how a harmless result becomes a
ship-blocker later, so the list was read rather than reasoned about.

`interim-v144-fetchlist.ps1` reads it from **two independent directions**, the
shipped control tool and the file the resolver actually reads, because a single
reading cannot tell a stale file from a tool that misreports it:

```
FL> {"ok":true,"allow":[{"host":"outlook.office.com","addedAt":"2026-08-28T23:59:34.250Z"}],
     "live":{"backend":"nftables","enforced":true,"addresses":18},
     "toolchain":{"enabled":true,"live":{"enforced":true,"addresses":28},"unreadable":false}}
FL> --FILE--
FL> outlook.office.com
FL> --END-FILE--

TOOL_HOSTS count=1 [outlook.office.com]
FILE_HOSTS count=1 [outlook.office.com]

FL.CTL.READ  PASS  POSITIVE CONTROL: both readings had something to read
FL.1         PASS  the control tool and the file the resolver reads agree
FL.2         PASS  the seeded host is present
FL.3         INFO  entries other than the seed: 0 []
PASS=4 FAIL=0 VOID=0 INFO=1  (counted 5 of 5)
```

**The list IS seeded-only.** `ST.0`'s verdict is false, and the cause is one line:

```
validation/interim-v140-sinktls.ps1:65
  $listOk = $fix.Out -match 'READ_FETCH_AFTER=www\.iana\.org$' -or ...
```

**`ST.0` asserts against `www.iana.org`, the seed host card `#282` deliberately
replaced with `outlook.office.com`** because a host whose address set does not move
cannot detect the stale-replay defect the seed exists to detect. The assertion was
never updated. **Carded, not fixed:** it is a false FAIL in a probe that is not on
box D's critical path, its cause is now measured and written down, and an
unvalidated edit mid-run is the wrong trade.

`FL.CTL.READ` is what makes `FL.1` mean anything: two empty readings from two
absent sources would agree perfectly and prove nothing.

### 10.2 INSTRUMENT DEFECT #4, IN MY OWN SWEEP: the one stale host was in the one shape the pattern could not see

This is the most instructive finding of the session and it is a correction to
section 3.

My TASK 0.2 sweep reported the HOST class at **485 hits / 57 distinct** and I
declared it clean, *"no stale entry"*, on the strength of a summary count with no
per-value enumeration behind it. That is exactly the shape section 5.1 says a
probe must never take: **a count with no listing beside it cannot be distinguished
from a count over the wrong set.**

The pattern required literal dots. The stale value is written into a PowerShell
`-match` and is therefore **regex-escaped**:

```
tree-wide occurrences of 'iana' in scope: 5
  stagebox.ps1:46        www.iana.org    comment, historical narrative of card #282  CURRENT as history
  bootpath.ps1:42        www.iana.org    comment                                     CURRENT as history
  bootpath.ps1:233,247   www.iana.org    a DELIBERATE stable-host control            CURRENT and correct
  sinktls.ps1:65         www\.iana\.org  a LIVE ASSERTION                            STALE
```

**Four plain instances, all benign; one escaped instance, and it is both the only
stale one and the only load-bearing one.** The sweep saw the four and was blind to
the fifth.

Re-run with a pattern tolerating an escaped dot:

```
BEFORE  HOST hits=485  distinct=57
AFTER   HOST hits=538  distinct=71
```

**53 host literals tree-wide were invisible, across 14 additional distinct
values.** Enumerated rather than summarised this time: 51 escaped literals across
15 distinct values, being `api.anthropic.com`, `anthropic.com`, `api.github.com`,
`registry.npmjs.org`, `raw.githubusercontent.com`, `clawhub.ai`, `api.clawhub.ai`,
`smtp.gmail.com`, `smtp.office365.com`, `example.org` and `example.net` as
deliberate negative controls, `neverssl.com`, `wikipedia.org`, `docs.python.org`.
**Every one current and correct except `www\.iana\.org`.**

**This is PROMPT 15's own canary rule, and I broke it.** It says in as many words:

> *"A CANARY ONLY CERTIFIES THE PATTERN AGAINST THE SHAPE OF THE CANARY. Build the
> canary to look like the thing you are afraid of missing, not like the things you
> already know are there."*

My three canaries were an HTML comment, a `.sh` here-doc and an uppercase digest.
All three were unescaped plain values. I proved the sweep could see three shapes it
had never been blind to, then declared clean a class containing the one value
written in a fourth shape. **Six consecutive runs of this sweep have carried the
same blind spot**, and it took a false FAIL from an unrelated probe to expose it.

The transferable generalisation: **a value that is compared against is often
written in the syntax of the comparison rather than in the syntax of the value.**
A digest inside a `-match`, a path inside a regex, a version inside a
`[ValidateSet]` are all the same class. The sweep instrument is a throwaway and is
not committed, but this belongs in the next job card, and it is carded.

---

## 11. TASK 1 IS COMPLETE. All three of box A's owed credential rows are CLOSED

The three rows box A VOIDed for one cause — no credential — now carry real
verdicts, and they were taken in the two-stage order section 1.2 set out so that
the box never held a real credential and a live send path at the same time.

### 11.1 `G2.10`, taken against the sink credential

```
G2.10   PASS  Test 10: credential file unreadable by the agent uid
G2.10c  PASS  CONTROL: a world-readable config IS readable by the agent
```

On `cfv-179` this row FAILed **while its own control passed**, which box A read
correctly as the reader working and the subject being absent. With the file
present the permission boundary exists and is measured from the agent's side: the
agent uid is refused and a world-readable config in the same directory is not, so
the denial is a boundary rather than a missing file.

### 11.2 `S.4` and `S.4leak`, taken against the REAL credential, post-reboot

The operator entered the kept throwaway in Studio (Approvals → Email settings).
The panel reported it back without the secret, which is the documented design:

```
Currently sending as clawfactory.validation.0805@gmail.com
via smtp.gmail.com:587 - signed in as clawfactory.validation.0805@gmail.com
Your password is stored where only the system account can read it. It is not
shown here and cannot be retrieved from this screen.
Saved. Your agent can now queue email through smtp.gmail.com, for your approval only.
```

Phase 4, post-reboot pass:

```
S.CHAN.POSTREBOOT    PASS  POSITIVE CONTROL: the file-based WSL channel discriminates
S.1.POSTREBOOT       PASS  No route to SMTP for uid 1000 at any destination
S.1ctlA.POSTREBOOT   PASS  CONTROL (must succeed): allowlisted 443 connects
S.1ctlB.POSTREBOOT   PASS  CONTROL (must fail): non-allowlisted 443 blocked
S.1ctlC.POSTREBOOT   PASS  CONTROL (must succeed): the probe can observe a real listener
S.4.POSTREBOOT       PASS  Credential unreadable by the agent uid
S.4leak.POSTREBOOT   PASS  Credential value absent from logs, receipts, errors, process listing
S.4ctl.POSTREBOOT    PASS  CONTROL: scanner finds the secret in the credential file itself

PASS=8 FAIL=0 VOID=0 INFO=0  (counted 8 of 8 recorded rows)
PHASE VERDICT: PASS
```

**`S.4leak` is a REAL verdict, not a synthetic one, and that is the whole point of
TASK 1.4.** The host was read rather than assumed:

```
CREDSTAT /etc/clawfactory/send-credential.json mode=600 owner=root:root
CREDHOST=smtp.gmail.com
secret configured, length=16
SCAN /var/lib/clawfactory hits=0     SCAN /var/log hits=0
SCAN /home/clawuser hits=0           SCAN /tmp hits=0
SCAN /etc/systemd hits=0             SCAN journal hits=0
SCAN ps hits=0                       SCAN env-of-broker hits=0
CONTROL_SCANNER_WORKS
```

Eight surfaces, zero hits, **and a control proving the scanner is not blind** — a
zero-hit scan from a scanner that cannot find the secret where it legitimately
lives would be a false pass. Only the LENGTH of the secret ever reached a
transcript; the value did not.

Had the sink credential still been in place, `S.4leak` would have recorded VOID
with the reason *"the configured credential points at the loopback sink, so it is
synthetic"* — which is exactly the defect TASK 1.4 names, and it is the reason the
real credential had to be present for this pass and absent for phase 3.

**Zero outbound email.** `phase3b` was not run, `-ExpectRealCredential` was not
passed, `G2.198` recorded VOID with its reason, and the only SMTP destination
anywhere in phase 3 was the loopback sink.

---

## 12. THE HEADLINE: THE KEEP-LINUX UNINSTALL

### 12.1 The before-state, held and hashed. **PASS 8/8**

```
DISCOVERED_UNITS   fenced=True count=11  [clawfactory-allow-providers.service
  clawfactory-allow-providers.timer clawfactory-egress-refresh.service
  clawfactory-fw.service clawfactory-proxy.service clawfactory-quarantine-gc.service
  clawfactory-quarantine-gc.timer clawfactory-quarantine.service
  clawfactory-send-gc.service clawfactory-send-gc.timer clawfactory-send.service]
DISCOVERED_ENABLED fenced=True count=8   [5 x multi-user.target.wants + 3 x timers.target.wants]
DISCOVERED_SBIN    fenced=True count=17  [all seventeen]
DISCOVERED_MAPS    fenced=True count=2   [/etc/clawfactory/read-fetch-ips.map
                                          /etc/clawfactory/toolchain-ips.map]
held snapshot written to C:\cfv\uninstate-before.json (3818 bytes)

PASS=8 FAIL=0 VOID=0 INFO=0  positive controls registered=3 fired=3
```

**`UST.1a` and `UST.1b` settle something on their own, before the uninstall even
runs.** The uninstaller's eleven-unit `CF_UNITS` list and its seventeen-helper `rm`
list are **exactly** the set the installer places — zero differences in either
direction. That is v1.4.2's completeness claim verified from the installer's side.
A difference in the `onBoxNotDerived` direction would have been the v1.4.2 defect
class recurring, because the drift backstop deletes the FILE and leaves the
ENABLEMENT.

### 12.2 The dialog, quoted as the operator saw it. **The copy is correct**

Two dialogs fire. Inno's *"Are you sure you want to completely remove…"* first,
answered **Yes**; then ClawFactory's own, answered **No**:

```
                         ClawFactory Uninstall

  Also remove the Ubuntu Linux distro that ClawFactory created?

  ClawFactory is removed from this machine either way: the agent, its
  configuration and plugins, clawuser's home directory, the OpenClaw
  runtime, and every ClawFactory service and firewall rule.

  YES also unregisters the Ubuntu distro and deletes its disk image (about 6 GB).
  Choose this unless something else on this machine uses that distro.

  NO leaves the now-empty Ubuntu distro registered, so anything else that
  shares it keeps working. You can install ClawFactory again later and it
  will reuse the distro.

  Your ClawChat conversation history is stored on Windows, under
  %APPDATA%\ClawChat, and neither choice deletes it.

                                          [ Yes ]   [ No ]
```

**TASK 3.1, by hand, from the operator's screen:**

| Check | Result |
| --- | --- |
| mid-sentence wrap | **none** — every paragraph wraps at word boundaries. v1.4.2 made each paragraph one logical line and let MessageBox wrap, which removed the defect as a class rather than re-tuning it |
| wider than the screen | **no**, fully contained, nothing cut off |
| Yes still the default button | **yes**, focused — consistent with `MessageBoxDefaultButton::Button1`. The default button and the `/SILENT` default must select the same branch, and they do |
| wording | matches `resources/uninstall.ps1:106-110` **word for word** |

**TASK 3.2: the mojibake class is ABSENT from this dialog, measured from both
directions.** Predicted from the bytes before the box existed
(`resources/uninstall.ps1` carries zero non-ASCII bytes, section 1.1) and
confirmed on screen: `clawuser's` renders with a correct apostrophe,
`%APPDATA%\ClawChat` is intact, and the copy contains **no em dashes at all** —
it uses colons and full stops throughout. The job card's premise was wrong about
this dialog and is now wrong by measurement rather than by argument.

*One correction to the record, in the instrument not the product:* box A's §18.1
transcription of this dialog dropped an "and" — it quoted *"the OpenClaw runtime,
every ClawFactory service"*. The shipped bytes and this render both read *"the
OpenClaw runtime, **and** every ClawFactory service and firewall rule."*

The uninstall then reported, unqualified:

```
ClawFactory Secure Setup was successfully removed from your computer.
```

Worth noting against box A, which saw the *"Some elements could not be removed"*
variant because ClawChat was running. Here the message is the unqualified one.

### 12.3 The read-back. Every held item, measured. **22 PASS, 1 FAIL, 1 INFO of 24**

```
UST.CHAN.After        PASS  POSITIVE CONTROL: the file-based WSL channel discriminates
UST.CTL.FENCE.After   PASS  POSITIVE CONTROL: every list the reader was asked for was actually emitted
UST.CTL.AFTER         PASS  POSITIVE CONTROL: the reader still answers present for things that ARE present, AFTER the uninstall
UST.CTL.NEG2          PASS  NEGATIVE CONTROL: a path that has never existed still reads absent
UST.PRE.SNAP          PASS  PRECONDITION: the held BEFORE snapshot exists
UST.3z                PASS  the snapshot being compared against is a BEFORE snapshot
UST.PRE.COMPLETE      PASS  PRECONDITION: the held snapshot recorded a COMPLETE install

UST.3a  PASS  the eleven unit FILES are gone                         11 -> 0
UST.3b  PASS  every ENABLEMENT symlink is gone, not just the files    8 -> 0
UST.3c  PASS  the seventeen /usr/local/sbin helpers are gone         17 -> 0
UST.3d  PASS  /usr/local/bin/clawfactory-send is gone
UST.3e  PASS  the allow-providers drop-in DIRECTORY is gone
UST.3f  PASS  /etc/clawfactory is gone, and the retention maps with it   2 maps -> 0
UST.3g  PASS  THE FIREWALL TABLE IS GONE
UST.3h  PASS  the openclaw runtime is gone, binary and module tree
UST.3i  PASS  CLAWUSER IS GONE, and its home with it
UST.3j  PASS  the state directories are gone
UST.4a  FAIL  the Windows application directory is gone
UST.4b  PASS  the uninstall registry entry is gone
UST.4c  PASS  HKLM\SOFTWARE\ClawFactory is gone
UST.4d  PASS  ProgramData\ClawFactory is gone
UST.4e  PASS  the scheduled tasks are gone
UST.5   PASS  the distro is STILL REGISTERED, which is what this branch promises
UST.6a  INFO  Credential Manager targets, target NAMES only

PASS=22 FAIL=1 VOID=0 INFO=1  (counted 24 of 24 recorded rows)
positive controls registered=3 fired=3   preconditions declared=2 met=2
```

**`UST.CTL.AFTER` is the row that makes the other twenty-one mean anything.** A
reader that had broken and now answered "absent" to everything would have produced
an identical-looking clean sweep. It was proven, after the uninstall, still able to
see `/etc` and `/bin/bash`, and still able to report a never-existent path as
absent.

**`UST.3b` and `UST.3i` are the two v1.4.2 rows that matter most.** Eight
enablement symlinks went to zero — an enabled unit pointing at a deleted script is
a failed unit in the journal at every future boot of a machine whose owner
believes the product is gone, and that is card `#285`'s exact defect. And
`clawuser` is gone with its home, which is card `#287` and the precondition for
the reinstall.

### 12.4 The single FAIL is MY PROBE, and the correct verdict is the opposite

`UST.4a` asserts *"the Windows application directory is gone"*. It is **a
RemoveAll property asserted on the keep-Linux branch**, and left uncorrected it
reads as *"the uninstaller leaves the application directory behind"* — a
ship-blocker-shaped claim about correct behaviour. Root-caused by measurement, in
three steps.

**What is actually left:**

```
APPDIR_EXISTS=True
FILE_COUNT=1
  LEFT C:\Program Files\ClawFactory\WSL\ext4.vhdx  6784286720 bytes
DIR_COUNT=1
  LEFTDIR C:\Program Files\ClawFactory\WSL
PROC_COUNT=0                 <- no ClawChat/ClawFactory/Studio process is running
CTL_WINDIR=True  CTL_NEVER=False    <- the reader discriminates in both directions
```

**What the installer put there is gone:**

```
UNINS_EXE_LEFT=False        SETUP_PS1_LEFT=False        RESOURCES_DIR_LEFT=False
```

**And the decisive reading, which had to come from the operator's session because
the distro is registered to `clawadmin` and `run-command` is SYSTEM:**

```
Ubuntu  BasePath=C:\Program Files\ClawFactory\WSL
  NAME      STATE       VERSION
* Ubuntu    Stopped     2
```

**The residual file is the kept distro's own backing disk.** A registered WSL
distro must have its VHDX; deleting it would destroy the distro the user
explicitly chose to keep, which is the opposite of what the dialog promises. The
dialog even prices it — *"YES also unregisters the Ubuntu distro and deletes its
disk image (about 6 GB)"* — so a ~6.8 GB image surviving a NO is the documented
behaviour.

**This is not box A's residual.** That one was a running `ClawChat.exe` the OS
refused to delete; here `PROC_COUNT=0` and the cause is entirely different.

Two SYSTEM-context readings in the same diagnostic were **discarded rather than
used**: the `HKCU` Lxss enumeration returned nothing, and `wsl.exe` answered
`Running WSL as local system is not supported. Error code:
Wsl/WSL_E_LOCAL_SYSTEM_NOT_SUPPORTED`. Both are standing trap 3 — the artefact
that produced box C's false "Studio is not installed" claim. Named as artefacts,
not results.

**Corrected verdict for row `UST.4a`: the keep-Linux uninstall removed everything
it installed under `{app}`, and the only survivor is the kept distro's backing
store, which must survive.** The probe row was fixed rather than carded, because
the second uninstall later in this run exercises the fixed row on this same box
and therefore validates it.

**One product observation, not a defect, worth carding:** after *"ClawFactory
Secure Setup was successfully removed from your computer"*, a directory named
`C:\Program Files\ClawFactory` remains, holding 6.8 GB. It is disclosed by
implication in the dialog and it is structurally necessary, but a user who goes
looking will find a ClawFactory folder after being told ClawFactory was removed.
Same family as box A's `#300`.

### 12.5 TASK 2.6: the teardown log. **PASS 7/8, and the log was DISCOVERED**

```
USING_LOG=C:\Users\clawadmin\AppData\Local\Temp\ClawFactory-Uninstall.log
BRANCH_STATE=KEEP_LINUX
STATE=TEARDOWN_OK   (NO_LOG | NO_MARKER | TEARDOWN_OK | TEARDOWN_INCOMPLETE | BOTH_MARKERS)
READBACK_PARSED units=0 sbin=0 enabled=0 left='[]'

TL.PRE.LOG     PASS  PRECONDITION: an uninstall log was found on this box
TL.CTL.SEARCH  PASS  POSITIVE CONTROL: search target is searchable (the uninstall log)
TL.PRE.BRANCH  PASS  PRECONDITION: the uninstaller took the KEEP-LINUX branch
TL.1           PASS  the teardown reports state TEARDOWN_OK
TL.2           PASS  the teardown printed a parseable READBACK line naming what it left
TL.3           PASS  the READBACK reports units=0 sbin=0 enabled=0 left=[ ]
TL.4           PASS  the Windows side logged the success sentence only because the marker was present
TL.6           INFO  the in-distro teardown exit code, reported as a fact

PASS=7 FAIL=0 VOID=0 INFO=1  controls 1/1  preconditions 2/2
```

**The log path was discovered across every candidate profile rather than taken
from `$env:TEMP`.** It lives in `clawadmin`'s temp; anything dispatched through
`run-command` runs as SYSTEM and would have looked in a different directory
entirely and found nothing — reporting NO_LOG on a box that has one.

**`TL.3` is card `#286`'s claim, met exactly**, and it is independently
corroborated: the uninstaller's own in-distro read-back says `units=0 sbin=0
enabled=0 left=[ ]`, and `interim-v144-uninstate.ps1 -Mode After` measured the same
four subjects from outside and agrees. Two instruments, one answer.

**`TL.4` is the row that detects the pre-v1.4.2 defect specifically**: the Windows
side now logs *"verified by read-back inside the distro"* only because the marker
was present, where the old code logged *"In-distro ClawFactory artifacts removed"*
unconditionally.

### 12.6 TASK 2.8: the next boot of the kept distro. **PASS 6/7**

```
NB.CHAN         PASS  POSITIVE CONTROL: the file-based WSL channel discriminates
NB.CTL.RESTART  PASS  POSITIVE CONTROL: the distro really restarted: its boot_id changed
NB.CTL.QUERY    PASS  POSITIVE CONTROL: systemctl list-unit-files can actually answer on this distro
NB.1            PASS  systemctl list-unit-files 'clawfactory-*' returns nothing enabled at the next boot
NB.2            PASS  clawfactory-fw.service is neither present nor failed
NB.3            PASS  no ClawFactory unit is in the failed state after the restart
NB.4            INFO  what this boot journal says about ClawFactory, reported as a fact

CFUNIT_STATE=NONE_LISTED   FW_STATE=ABSENT
PASS=6 FAIL=0 VOID=0 INFO=1  positive controls registered=3 fired=3
```

**Both controls are what make this row a result rather than a shrug.**
`NB.CTL.RESTART` proves the distro genuinely restarted — without it an unchanged
unit list proves only that nothing happened. `NB.CTL.QUERY` proves `systemctl`
could answer at all, by finding rows for a glob that must match on any Ubuntu: a
`systemctl` that cannot reach a running systemd prints nothing, and *"nothing is
enabled"* then reads exactly like a clean box. The dry-run rig for that case VOIDs
at rc=4, so this is a discriminating control and not a decorative one.

`clawfactory-fw.service` is named specifically because v1.4.1 deleted its script
and left the unit enabled. It is now `LoadState=not-found`, `ActiveState=inactive`,
no unit file on disk.
