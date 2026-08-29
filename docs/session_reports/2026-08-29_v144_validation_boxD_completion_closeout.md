# CLOSE-OUT: v1.4.4 validation, BOX D COMPLETION — the negative half, and the fitness verdict

**Companion to** `2026-08-27_v144_validation_boxA_closeout.md`,
`2026-08-28_v144_boxA_lessons_and_next_job_guidance.md` (the five clauses),
`2026-08-28_v144_validation_boxBC_closeout.md` and
`2026-08-28_v144_validation_boxD_closeout.md` (whose **section 19 is this job's spec**).

**Scope.** The one item box D owed: **TASK 2.7, the fault-injected negative half of
the teardown marker.** Then the teardown of `cfv-182`, the disposition of card
`#286`, and **the conversion of box D §16.4's WITHHELD verdict into a yes or a no,
aggregating all four boxes.**

*Written as the run proceeded. No shipped byte was changed. No tag was created.*

---

## 0. PROMPT 15 preamble

Pasted in full from `FrontierAI_CC_Prompt_Library.md`, VM clauses included. The
copy read carries **`PROMPT 15` at line 645 of 925 and is NOT stale** — the same
position boxes B, C and D recorded. It runs to line 878 (`### Notes on using
PROMPT 15`). Nothing was deleted from it.

The five clauses from box A's root-cause analysis are in force, with clause 1
sharpened per the B/C close-out §20.3. Each is answered specifically in §16.

---

## 1. THREE CHALLENGES TO THE JOB CARD, ALL RAISED BEFORE THE OPERATOR WAS ASKED FOR ANYTHING

PROMPT 15: *"If an instruction is factually wrong about the code, STOP and report.
Do not quietly build the thing that was meant."*

**Two of the three would have cost the operator touch this session exists to spend.**

### 1.1 The `UST.4a` correction the card asks me to validate does not exist

Section 19 step 6 reads: *"`interim-v144-uninstate.ps1 -Mode After` — which also
**validates the `UST.4a` correction** made in §12.4 on the same box that motivated
it."*

**There was no correction in the assertion to validate.** Commit `dbf744e` added
the *measurement*:

```
$s.uninsExe    = [bool](Test-Path 'C:\Program Files\ClawFactory\unins000.exe')
$s.setupPs1    = [bool](Test-Path 'C:\Program Files\ClawFactory\setup.ps1')
$s.resourceDir = [bool](Test-Path 'C:\Program Files\ClawFactory\resources')
$s.wslVhdx     = [bool](Test-Path 'C:\Program Files\ClawFactory\WSL\ext4.vhdx')
$s.nonWslFiles = @($leftover)   $s.nonWslFileCount = @($leftover).Count
```

but left the assertion untouched at `interim-v144-uninstate.ps1:386`:

```
@{ id='UST.4a'; n='the Windows application directory is gone'; v=(-not $win.appDir); ... }
```

**The half that was done is the half that produces evidence; the half that was
missing is the half that takes the verdict.** Run as written it would have FAILed
again, identically, and the session would have re-derived box D's own conclusion
at the cost of the box.

**Resolution: fixed and calibrated before it measured anything** (commit
`aa0d5b8`, §1.4 below). It is a validation file, not a shipped byte, so clause 5
is not in play — and the previous session's own stated justification for editing
it mid-run (*"the second uninstall later in this run re-exercises the fixed row on
this same box"*) only holds if the row is actually fixed.

### 1.2 THE MATERIAL ONE: the uninstall log APPENDS, so the second uninstall would have voided its own measurement

`resources/uninstall.ps1:51`:

```
try { Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8 } catch {}
```

**`Add-Content`, not `Set-Content`.** The log is not truncated per run. Measured on
the box before anything was touched:

```
LOG_FOUND C:\Users\clawadmin\AppData\Local\Temp\ClawFactory-Uninstall.log
          bytes=4532 startLines=1 OKmarkers=1 INCOMPLETEmarkers=0 keepBranch=1 removeAll=0
```

A second uninstall appending to that file yields `OKmarkers=1 INCOMPLETEmarkers=1`.
`interim-v144-teardownlog.ps1` classifies that as **`BOTH_MARKERS`**, and `TL.1`
requires `TEARDOWN_INCOMPLETE`, so **`TL.1` would have FAILed** — on a run where
the product did exactly the right thing.

**This is the worst shape a failure can take in this project: an instrument
artefact wearing the costume of the product defect under test.** A `TL.1` FAIL is
indistinguishable, from the transcript alone, from "the teardown did not emit
`INCOMPLETE`" — which is card `#286`'s exact defect, and would have read as a
ship-blocker on the last row of the last box.

The probe is not at fault. `BOTH_MARKERS` is a named state the probe classifies
deliberately (*"two teardowns in one log, ambiguous"*). **The defect is in the
run plan** — section 19's step list has no log-rotation step.

**Resolution:** run 1's log archived to `C:\cfv\run1-archive\` before the operator
was asked to do anything (§4).

### 1.3 Stale probe evidence was sitting in the dispatcher's fetch path

`interim-v120-job.ps1:165` retrieves `C:\cfv\<probe>-out-probe.txt` **by name**.
Both probes this session re-runs had left files there yesterday:

```
STALE_TX teardownlog-out-probe.txt bytes=9493 lastWrite=2026-08-29T01:42:11
STALE_TX uninstate-out-probe.txt   bytes=23366 lastWrite=2026-08-29T01:25:53
STALE_RJ teardownlog-results.json  bytes=7283
STALE_RJ uninstate-results.json    bytes=16775
```

A probe that died early would have handed back **yesterday's verdict as this
run's**, with no error anywhere — the failure mode the dispatcher's own comment
block describes for the post-reboot results file. Moved to the archive; all seven
fetch paths confirmed absent before the first dispatch.

### 1.4 The `UST.4a` fix, calibrated in four directions before it ran

PROMPT 15: *"CALIBRATE BEFORE MEASURING. Run every probe body once against a
synthetic target whose answer is already known, and assert that answer."*

The row now asserts what is load-bearing **on the keep-Linux branch**: that
everything the *installer* placed under `{app}` is gone — the three artifacts Inno
put there by name, **plus a recursive count of every file under `{app}` outside the
WSL backing store**. The surviving directory is not discarded; it becomes
`UST.4a2` INFO, because it is card `#306`'s subject and an assertion is not the
place to hide a fact.

| Rig | Shape | Required | Got |
| --- | --- | --- | --- |
| A | payload gone, VHDX survives (the real cfv-182 run-1 shape) | PASS | **PASS** |
| B | uninstaller left its own payload behind | FAIL | **FAIL** |
| C | RemoveAll shape, whole directory gone | PASS | **PASS** |
| D | the three named files gone but one stray file remains | FAIL | **FAIL** |

**Rig C and rig D are the two that matter and neither is decorative.** C proves
the row was not merely *inverted* into one that passes only when the directory
survives — which would be a different wrong answer, not a fix. D proves the row is
not satisfied by the three named files alone, which is **the v1.4.2 short-list
defect class reproduced in miniature inside the instrument**: a check that names a
subset of the subject reports a clean sweep over the wrong set.

**What the calibration did NOT cover, stated because clause 1 now requires it:**
the probe's WSL reader and the dispatcher, both unchanged by the commit.

Parse-checked with the PowerShell AST parser (`PARSE_OK tokens=2561`) and
`git ls-files --eol` re-read afterwards: `i/lf w/lf`, CR count 0.

---

## 2. THE ARTIFACT. Unchanged, and nothing was rebuilt

| | |
| --- | --- |
| version | v1.4.4 |
| signed sha256 | `6e65560325cb6d7d3fea204ebb72876b3b113cbbfe9f2fa4f94113237e9eb4d1` |
| signed bytes | 440,610,608 |
| build commit | `25945d5` |

This session **built nothing, signed nothing and bumped nothing.** The box carried
the same `combined-setup.exe` (440,610,608 bytes, confirmed on the box at §3)
whose three derivations agreed in box D §2 and §6. The install under test is the
**reinstall** box D §13 performed onto the emptied distro, which reported
`INSTALLER_DONE=success` and 15/0/0/4 of 19.

---

## 3. THE BOX, RESTARTED. RDP re-read against reality rather than carried forward

```
az vm start -g clawfactory-validation -n cfv-182          START_EXIT=0
cfv-182 / VM running / Succeeded / 20.69.122.150          VM_EXIT=0
```

**The `/32` was re-read on both sides, and this machine's live address was read
TWICE from two independent services** — because a single reader that lies produces
an operator who cannot connect and a wasted touch:

```
az network nsg rule show ... allow-rdp
  allow-rdp  67.164.251.99/32  3389  Allow  Inbound  300      NSG_EXIT=0

this machine, api.ipify.org   -> 67.164.251.99            LIVE_IP_EXIT=0
this machine, ifconfig.me/ip  -> 67.164.251.99            SECOND_READER_EXIT=0
```

Two readers, one answer, and it equals the rule. Never `0.0.0.0/0`.

**The box state before the operator was asked for anything**, so the card could
name what he would see:

```
CFV start-runner.cmd bytes=112     CFV wrapper.cmd bytes=5201
UNINST_ENTRY 'ClawFactory Secure Setup version 1.4.4' key={8D7C4B2A-...}_is1
APPDIR=True UNINS_EXE=True SETUP_PS1=True RESOURCES=True WSL_VHDX=True
HKLM_PRODUCT=False
```

`start-runner.cmd` at 112 bytes matches the staging record in box D §6, and
`wrapper.cmd` at 5201 bytes is the five-line installer wrapper — which is why the
card names the first by full path and says in the same breath what the second
would do.

---

## 4. BOX PREPARATION, AND **INSTRUMENT DEFECT #1 — MY OWN, WITHIN MINUTES**

### 4.1 The prep

```
LOG_SRC=C:\Users\clawadmin\AppData\Local\Temp\ClawFactory-Uninstall.log bytes=4532
LOG_ARCHIVED=C:\cfv\run1-archive\ClawFactory-Uninstall-run1.log bytes=4532
LOG_ORIGINAL_NOW_ABSENT=True
LOGS_VISIBLE_TO_PROBE_NOW=0  (must be 0)

SNAP_RUN1 mode=Before takenAt=2026-08-29T01:00:52 units=11 sbin=17 enabled=8
          clawuser=present hasWinUninsExeField=False
MOVED_STALE teardownlog-out-probe.txt / teardownlog-results.json
MOVED_STALE uninstate-out-probe.txt   / uninstate-results.json
```

`hasWinUninsExeField=False` is the line that settled a question §1.1 left open:
**yesterday's snapshot predates the enriched reader**, so the corrected `UST.4a`
would have printed empty before-values against it. That is the second independent
reason to retake `-Mode Before`, and it was measured rather than assumed.

### 4.2 The defect: `H()` bound to `Get-History`, and a success marker was computed over two nulls

I defined a one-letter helper `function H($p) { (Get-FileHash $p).Hash }` inside
the prep payload. **`H` is PowerShell's built-in alias for `Get-History`**, and
alias resolution won:

```
Get-History : Cannot bind parameter 'Id'. Cannot convert value
"C:\cfv\teardownlog-out-probe.txt" to type "System.Int64".
```

Every `H $p` returned `$null`. The consequence is the one this project keeps
finding:

```
LOG_ARCHIVE_IDENTICAL=True      <- computed as ($null -eq $null)
SNAP_ARCHIVED_IDENTICAL=True    <- computed as ($null -eq $null)
```

**Two empty readings agreeing perfectly, reported as verification.** That is
box D §10.1's `FL.CTL.READ` lesson — *"two empty readings from two absent sources
would agree perfectly and prove nothing"* — committed by the person who wrote that
sentence down the day before.

**This is standing trap 7, which box D's own trap table lists** (*"`H()` collides
with `Get-History` — held — no single-letter function defined"*). Box D held it by
not defining one. I defined one.

**Caught immediately, because `az` returned the `ParameterBindingException` block
on the same result and it was read rather than skipped past.** The byte counts in
that same output were legitimate (`Get-Item .Length` does not go through `H`), so
the moves themselves were real; only the *verification* was hollow.

**Re-verified with a properly named function AND both controls**, because a hash
function that returns nothing and a hash function that returns `ABSENT` for a
missing file are different instruments:

```
CTL_HASH_LEN=64  CTL_LOOKS_LIKE_SHA256=True
CTL_ABSENT_RETURNS=ABSENT  (must be ABSENT, not empty)

SNAP_LIVE    sha256=68848B9691CC8C4F217CFD22D26740AFBE362EB17172D5116B42250082761CE6 bytes=3818
SNAP_ARCHIVE sha256=68848B9691CC8C4F217CFD22D26740AFBE362EB17172D5116B42250082761CE6 bytes=3818
SNAP_ARCHIVE_IDENTICAL=True

LOG_ARCHIVE  sha256=184A476FF3314771B8381249366495F9543184D360793C25738469894FAD875A
LOG_ARCHIVE  bytes=4532 startLines=1 OKmarkers=1 INCOMPLETEmarkers=0 keepBranch=1
LOG_ARCHIVE_MATCHES_PREMOVE_DISCOVERY=True
```

**Stated precisely, because the two archives are not verified to the same
standard.** The snapshot was *copied*, so the original survived and a direct
hash-to-hash comparison was possible. The log was *moved*, so its pre-move hash
can never be recovered — its identity is reconstructed from the **independent
read-only discovery taken before the move** (4532 bytes, 1 start line, 1 OK
marker, 0 INCOMPLETE) and every one of those four properties matches. That is
weaker than a hash comparison and it is labelled as such rather than presented as
one.

---

## 5. THE BEFORE-STATE, RETAKEN AGAINST THE REINSTALLED BOX. **PASS 8/8**

```
DISCOVERED_UNITS   fenced=True count=11  [all eleven]
DISCOVERED_ENABLED fenced=True count=8   [5 x multi-user.target.wants + 3 x timers.target.wants]
DISCOVERED_SBIN    fenced=True count=17  [all seventeen]
DISCOVERED_MAPS    fenced=True count=2   [read-fetch-ips.map toolchain-ips.map]
WIN> appDir=True uninsExe=True setupPs1=True resourceDir=True wslVhdx=True
WIN> nonWslFileCount = 56
WIN> regKeyCount=2  hklmProduct=False  programData=True  taskCount=1  distroPresent=True
held snapshot written to C:\cfv\uninstate-before.json (9651 bytes)

UST.CHAN.Before      PASS   UST.CTL.FENCE.Before PASS
UST.CTL.READER       PASS   UST.CTL.NEG          PASS
UST.1a  PASS  onBox=11 derived=11; derivedNotOnBox=[]; onBoxNotDerived=[]
UST.1b  PASS  onBox=17 derived=17; derivedNotOnBox=[]; onBoxNotDerived=[]
UST.1   PASS  THE BEFORE-STATE: a complete v1.4.4 install is present on this box
UST.1z  PASS  snapshot=9651 bytes

PASS=8 FAIL=0 VOID=0 INFO=0  positive controls registered=3 fired=3
PHASE VERDICT: PASS
```

**The retake earned its place twice over.** The snapshot went from **3818 bytes to
9651**, because it now carries the Windows fields the corrected row compares
against — `nonWslFileCount = 56` is a real before-value where yesterday's snapshot
had none. And `UST.1a`/`UST.1b` are a **second independent confirmation on a second
install** that the uninstaller's eleven-unit `CF_UNITS` list and seventeen-helper
`rm` list are *exactly* the set the installer places, zero differences in either
direction.

---

## 6. THE FAULT INJECTION. **PASS 6/6, both controls fired**

```
DISCOVERED_ETC_CLAWFACTORY count=18 [allowed-ips.txt base-hosts.seed dns-resolvers.txt
  egress-policy.json fw-backend governor.json openclaw-real persona.md quarantine.json
  read-fetch-hosts.txt read-fetch-ips.map read-fetch-ips.txt send.json soul.sha256
  toolchain-hosts.seed toolchain-ips.map toolchain-ips.txt workspace-soul.sha256]
FI.PRE  PASS  /etc/clawfactory=present entries=18 chattr=present fstype=ext2/ext3
CHOSEN_TARGET=/etc/clawfactory/allowed-ips.txt

INJ> CHATTR_RC=0
INJ> LSATTR=----i---------e------- /etc/clawfactory/allowed-ips.txt
INJ> /usr/bin/rm.real: cannot remove '/etc/clawfactory/allowed-ips.txt': Operation not permitted
INJ> TARGET_STILL_THERE=yes
INJ> CONTROL_CREATED=yes   CONTROL_GONE=yes
INJ> DIR_STILL_THERE=yes

FI.CTL.LANDED  PASS  THE FAULT LANDED
FI.CTL.RM      PASS  root CAN delete a sibling file in the same directory
FI.1           PASS  the box is now rigged so the shipped teardown CANNOT complete
FI.2           PASS  wrote C:\cfv\teardownfault-target.txt

PASS=6 FAIL=0 VOID=0 INFO=0  controls registered=3 fired=3  preconditions declared=1 met=1
PHASE VERDICT: PASS
```

**The subject was DISCOVERED, not named.** The listing was printed in full and the
target chosen from it deterministically (sorted, first entry), so nothing here
assumes a filename — and the name chosen was written to a marker file so the
cleanup pass asserts on *that* name rather than a remembered one.

**`FI.CTL.RM` is the control that makes `FI.CTL.LANDED` mean anything.** Without
it, "root cannot delete this file" could equally be a broken `rm`, a read-only
mount, or a missing directory — three different findings that look identical.

*One readability note, not a defect:* the payload prints `RM_SUBJECT_RC=0` because
`rm ... | head -2` makes `$?` the status of `head` — PROMPT 15's own pipeline trap.
**The probe does not assert on that value**; it asserts on `TARGET_STILL_THERE`.
The design is right and the printed number is misleading, which is worth fixing in
the print rather than in the logic.

---

## 7. THE OPERATOR'S THREE DIALOGS, AS HE SAW THEM

All three captured by screenshot rather than transcribed, so the record carries no
transcription risk. Box D §12.2 recorded that box A's transcription of the
keep-Linux dialog had dropped an "and"; screenshots remove that class.

**Dialog 1, Inno's → `Yes`:**
> *"Are you sure you want to completely remove ClawFactory Secure Setup and all of its components?"*

**Dialog 2, ClawFactory's → `No`.** Rendered correctly for a **second independent
time** on this box: every paragraph wraps at word boundaries, nothing is cut off,
and there is no mojibake — consistent with box D §12.2 and with the byte census
(`resources/uninstall.ps1` carries zero non-ASCII bytes).

**Dialog 3 — THE ONE THIS SESSION EXISTS FOR.** Title
`ClawFactory Uninstall - Linux cleanup incomplete`, warning icon, single OK button:

```
ClawFactory has been removed from Windows, but it could not finish
cleaning up inside the Ubuntu Linux distro you chose to keep.

What is left: [uninstall] READBACK units=0 sbin=0 enabled=0 left=[ /etc/clawfactory ]

To remove the rest, open a terminal and run:  wsl -d Ubuntu
-u root

The full log is at
C:\Users\CLAWAD~1\AppData\Local\Temp\ClawFactory-Uninst
all.log.
```

**It matches `resources/uninstall.ps1:622-627` word for word**, and it matches the
prediction recorded in §7.1 below before the operator acted.

**Dialog 4, Inno's final → `OK`:**
> *"ClawFactory Secure Setup was successfully removed from your computer."*

The **unqualified** variant, as in run 1 — not box A's *"Some elements could not be
removed"*, which appeared there because ClawChat was running.

### 7.1 The prediction, recorded before he touched the box

Derived from `resources/uninstall.ps1:484` (`rm -rf /etc/clawfactory 2>/dev/null`,
no `set -e`, error suppressed) and `:540` (`[ -d /etc/clawfactory ] && LEFT="$LEFT
/etc/clawfactory"`):

| Row | Predicted | Measured |
| --- | --- | --- |
| `TL.1` | `TEARDOWN_INCOMPLETE` | **`TEARDOWN_INCOMPLETE`** |
| READBACK | `units=0 sbin=0 enabled=0 left=[ /etc/clawfactory ]` | **identical** |
| `UST.3f` | FAIL, by design | **FAIL, by design** |
| `UST.4c` | PASS but vacuous | **PASS, `False (before: False)`** |

**Stating the expected result before the measurement is what makes the FAIL in
§9 readable as the rig working rather than reinterpretable afterwards.**

---

## 8. TASK 2.7 IS MET. **`TEARDOWN_INCOMPLETE`, PASS 8/0/0/1 of 9**

```
CANDIDATES_SEARCHED=5  LOGS_FOUND=2
USING_LOG=C:\Users\clawadmin\AppData\Local\Temp\ClawFactory-Uninstall.log bytes=4826
BRANCH_STATE=KEEP_LINUX
STATE=TEARDOWN_INCOMPLETE   (NO_LOG | NO_MARKER | TEARDOWN_OK | TEARDOWN_INCOMPLETE | BOTH_MARKERS)
READBACK_PARSED units=0 sbin=0 enabled=0 left='[/etc/clawfactory]'

TL.PRE.LOG     PASS  PRECONDITION: an uninstall log was found on this box
TL.CTL.SEARCH  PASS  POSITIVE CONTROL: the target is searchable
TL.PRE.BRANCH  PASS  PRECONDITION: the uninstaller took the KEEP-LINUX branch
TL.1           PASS  the teardown reports state TEARDOWN_INCOMPLETE
TL.2           PASS  the teardown printed a parseable READBACK line naming what it left
TL.3           PASS  the READBACK NAMES what was left behind rather than only failing
TL.4           PASS  the Windows side logged the failure AS a failure, and told the user how to finish
TL.5           PASS  the failure path echoed the read-back into the log for the user to act on
TL.6           INFO  In-distro teardown exit code = 0

PASS=8 FAIL=0 VOID=0 INFO=1  (counted 9 of 9)
positive controls registered=1 fired=1   preconditions declared=2 met=2
PHASE VERDICT: PASS
```

### 8.1 The single most important line in the entire validation cycle

```
[2026-08-29T13:51:00] [INFO]   [in-distro] CLAWFACTORY_TEARDOWN_INCOMPLETE
[2026-08-29T13:51:00] [INFO] In-distro teardown exit code = 0
```

**The teardown exited ZERO while leaving files behind.**

The pre-v1.4.2 caller assigned the invocation to `$null` and logged *"In-distro
ClawFactory artifacts removed"* unconditionally. Even a caller that checked the
exit code — the obvious fix, and the one a reviewer would most likely have
accepted — **would have reported unqualified success on this exact run.** The
v1.4.2 code is:

```
$teardownOk = ($rc -eq 0) -and ($teardownOut -contains 'CLAWFACTORY_TEARDOWN_OK')
```

and the `-and` is the whole card. **The terminal marker is the only thing standing
between this run and a false success**, and that is now measured rather than
argued.

### 8.2 Why this could not have been inferred from the happy path

The same instrument, unchanged, produced `TEARDOWN_OK` on box D's clean run and
`TEARDOWN_INCOMPLETE` here. **That is what makes the marker a discriminator rather
than a constant.** Box D §14.2 stated the principle and this run supplies the
missing half:

> *a success marker that has never been observed to fail is indistinguishable from
> one that cannot fail.*

The full product narrative, verbatim from the retrieved log
(sha256 `E069B3C7C5EA10DAF738F95A16FCD70378BCFFA896243FC697B1ED2E53615CB6`, 4826 bytes):

```
[2026-08-29T13:49:28] [INFO] Resolved DoRemoveAll = False
[2026-08-29T13:51:00] [INFO]   [in-distro] [uninstall] READBACK units=0 sbin=0 enabled=0 left=[ /etc/clawfactory ]
[2026-08-29T13:51:00] [INFO]   [in-distro] CLAWFACTORY_TEARDOWN_INCOMPLETE
[2026-08-29T13:51:00] [INFO] In-distro teardown exit code = 0
[2026-08-29T13:51:00] [ERROR] In-distro teardown did NOT complete. ClawFactory files remain inside the Ubuntu distro.
[2026-08-29T13:51:00] [ERROR] Read-back from inside the distro: [uninstall] READBACK units=0 sbin=0 enabled=0 left=[ /etc/clawfactory ]
[2026-08-29T13:51:00] [ERROR] The rest of the uninstall will still finish. To clear the Linux side by hand, open a terminal and run:  wsl -d Ubuntu -u root
```

The log was retrieved to local evidence and **verified byte-identical to the copy
on the box** — 4826 bytes, sha256 matching exactly. It is filed at
`validation-runs/cfv-182-teardownlogINCOMPLETE-20260829-074847/ClawFactory-Uninstall-run2.log`.

### 8.3 The rotation was necessary AND sufficient, proven by the log itself

```
LOG startLines=1 OK=0 INCOMPLETE=1 keepBranch=1 removeAll=0
```

**One uninstall, one marker, and it is the failing one.** Had §1.2's rotation not
happened this would read `OK=1 INCOMPLETE=1` and the state would be
`BOTH_MARKERS`.

### 8.4 Two instrument observations, neither affecting a verdict

**`LOGS_FOUND=2` for a single file.** The same path is listed twice because
`$env:TEMP` in the operator's session holds the **8.3 short form**
(`C:\Users\CLAWAD~1\...`) while the `C:\Users` enumeration produces the long form —
two distinct strings that `Sort-Object -Unique` cannot collapse. Harmless here (the
newest is taken and both are the same file) but it reads as two logs on the box.
This is the *same root cause* as the dialog's `CLAWAD~1` path, sighted
independently — see §12, card `#307`.

**`TL.PRE.LOG` prints its failure reason on PASS.** `Require-Precondition` echoes
`-Reason` regardless of outcome, so a PASSing row carries the sentence *"was not
present in any of the 5 profiles searched"*. Cosmetic, in the shared phase library,
and capable of misleading a future reader of the transcript.

---

## 9. THE INDEPENDENT READ-BACK. **22 PASS / 1 FAIL / 2 INFO of 25, and the FAIL is the fault**

```
DISTRO> --UNITS--   (empty)      DISTRO> --ENABLED-- (empty)
DISTRO> --SBIN--    (empty)      DISTRO> --MAPS--    (empty)
DISTRO> ETC_CLAWFACTORY=present  <- THE INJECTED FAULT
DISTRO> CLAWUSER=absent  CLAWUSER_HOME=absent  NFT_TABLE=absent  NFT_CHAINS=0
WIN> appDir=True uninsExe=False setupPs1=False resourceDir=False wslVhdx=True
WIN> nonWslFileCount = 0   regKeyCount=0  programData=False  taskCount=0  distroPresent=True

UST.CTL.AFTER    PASS  the reader STILL answers present for things that ARE present
UST.CTL.NEG2     PASS  a path that has never existed still reads absent
UST.3z           PASS  the snapshot compared against is a BEFORE snapshot
UST.PRE.COMPLETE PASS  the held snapshot recorded a COMPLETE install

UST.3a  PASS  units       11 -> 0
UST.3b  PASS  enablements  8 -> 0
UST.3c  PASS  sbin helpers 17 -> 0
UST.3d  PASS  /usr/local/bin/clawfactory-send gone
UST.3e  PASS  drop-in DIRECTORY gone
UST.3f  FAIL  /etc/clawfactory = present   <- BY DESIGN, this is the injected fault
UST.3g  PASS  THE FIREWALL TABLE IS GONE
UST.3h  PASS  openclaw runtime gone, binary and module tree
UST.3i  PASS  CLAWUSER IS GONE, and its home with it
UST.3j  PASS  state directories gone
UST.4a  PASS  files under {app} outside \WSL\ = 0 (before: 56)
UST.4b  PASS  uninstall registry entries 2 -> 0
UST.4c  PASS  HKLM\SOFTWARE\ClawFactory = False (before: False)
UST.4d  PASS  ProgramData\ClawFactory = False (before: True)
UST.4e  PASS  scheduled tasks 1 -> 0
UST.5   PASS  the distro is STILL REGISTERED
UST.4a2 INFO  C:\Program Files\ClawFactory = True; WSL\ext4.vhdx = True
UST.6a  INFO  Credential Manager targets, NAMES only: 0

PASS=22 FAIL=1 VOID=0 INFO=2  (counted 25 of 25)
positive controls registered=3 fired=3   preconditions declared=2 met=2
PHASE VERDICT: FAIL  (failing check: UST.3f)
```

### 9.1 The FAIL is the rig, and it was predicted in writing before the box was touched

`UST.3f` asserts *"/etc/clawfactory is gone"*. **This run deliberately made that
impossible.** §7.1 recorded the prediction before the operator acted, so this is a
confirmed expectation rather than a result reinterpreted after the fact.

**Its value is corroborative and it is the strongest row in this section.** The
uninstaller's own in-distro READBACK said `left=[ /etc/clawfactory ]`; an
enumeration from *outside* the uninstaller, using a different reader, independently
found `/etc/clawfactory = present` while every other subject went to zero. **Two
instruments, one answer, one of them the product and one of them not.**

### 9.2 `UST.4a` now says the true thing, on the box that motivated the correction

```
UST.4a  PASS  unins000.exe = False (before: True); setup.ps1 = False (before: True);
              resources\ = False (before: True);
              files under {app} outside \WSL\ = 0 (before: 56) []
UST.4a2 INFO  C:\Program Files\ClawFactory = True (before: True);
              WSL\ext4.vhdx = True (before: True). Card #306.
```

**56 files to 0.** Yesterday this row FAILed and read as *"the uninstaller leaves
the application directory behind"* — a ship-blocker-shaped claim about correct
behaviour. It now asserts what is actually true on this branch: the product is
gone; the kept distro's backing disk remains, because the Ubuntu registration's
`BasePath` is that directory and deleting it would destroy the distro the user
explicitly chose to keep.

**The surviving directory did not vanish from the record when the assertion stopped
naming it** — that is what `UST.4a2` is for, and it remains card `#306`.

### 9.3 One row that passes vacuously, named rather than counted

`UST.4c` reads `HKLM:\SOFTWARE\ClawFactory = False (before: False)`. **The subject
was absent on both sides, so the row proves no removal.** It passed identically in
box D's run for the same reason. It is not wrong, but it contributes nothing, and a
PASS that contributes nothing is exactly the *"INFO row that reads like coverage"*
the PROMPT 15 gotcha table warns about. Counted honestly here rather than folded
into the 22.

---

## 10. THE FAULT REMOVED, AND THE REMOVAL PROVES THE TEARDOWN WAS CORRECT

```
TARGET_FROM_MARKER=/etc/clawfactory/allowed-ips.txt
CLN> EXISTS_BEFORE=yes   CHATTR_RC=0
CLN> LSATTR_AFTER=--------------e------- /etc/clawfactory/allowed-ips.txt
CLN> EXISTS_AFTER=no     DIR_AFTER=absent     RESIDUAL_LISTING=

FI.C.PRE PASS   FI.C.1 PASS   FI.C.2 PASS
PASS=4 FAIL=0 VOID=0 INFO=0   controls 1/1   preconditions 1/1
PHASE VERDICT: PASS
```

**`FI.C.2` is worth more than its position suggests.** After clearing the immutable
attribute, **the same directory removal the teardown had attempted succeeded** —
`DIR_AFTER=absent`, residual listing empty. So the obstruction was the injected
attribute and nothing else: **the shipped teardown logic was correct throughout,
and the only thing that ever stopped it was the fault this session installed.**
Without this row, `UST.3f` would be open to the reading that the teardown cannot
remove that directory at all.

The immutable bit is visibly cleared in the `lsattr` output (`----i---` → `-------`),
which is a different claim from the file being gone, and both are asserted.

---

## 11. TEARDOWN. Clean, by explicit name, proven subscription-wide

```
az vm delete            -n cfv-182         VM_DELETE_EXIT=0
az disk delete          -n cfv-182-osdisk  DISK_EXIT=0
az network nic delete   -n cfv-182VMNic    NIC_EXIT=0    <- NIC FIRST
az network public-ip delete -n cfv-182-pip PIP_EXIT=0
az network nsg delete   -n cfv-182-nsg     NSG_EXIT=0
```

**NIC before the public IP and the NSG**, because it references both.

**Proven with an UNFILTERED subscription-wide list, not a grep for the VM name:**

```
=== az vm list -d, SUBSCRIPTION-WIDE ===        VM_EXIT=0   (no rows)
=== az resource list, ALL RESOURCE GROUPS ===   RES_EXIT=0
clawfactory-validation  clawfactoryvalc467             Microsoft.Storage/storageAccounts
clawfactory-validation  bake-vmVNET                    Microsoft.Network/virtualNetworks
clawfactory-validation  clawfactory-win11-baseline     Microsoft.Compute/images
clawfactory-validation  clawfactory-win11-baseline-v2  Microsoft.Compute/images
NetworkWatcherRG        NetworkWatcher_westus2         Microsoft.Network/networkWatchers
clawfactory-signing     clawfactory-signing            Microsoft.CodeSigning/codeSigningAccounts
DISK_EXIT=0  NIC_EXIT=0  PIP_EXIT=0  NSG_EXIT=0   -- all four empty
```

**Exactly the expected residual and nothing else**, identical to the estate box D
recorded before it provisioned. `az disk list` was issued **with** `-g`
deliberately: the subscription-wide form exits 2 with a required-argument error
whose empty output reads exactly like "no disks exist".

**Standing trap 6 did not fire.** Nothing still listed after deletion, so there was
no propagation race to re-check; recorded as which of the two it was, per PROMPT 15.

---

## 12. TASK 8.2: INSTRUMENT DEFECTS, COUNTED AND TIMED — FIFTH CONSECUTIVE SESSION

### 12.1 The count

| | Box A | Boxes B+C | Box D | **Box D completion** |
| --- | --- | --- | --- | --- |
| **Product defects found** | 1 (cosmetic) | **0** | **0** | **0** |
| Instrument / plan defects | 8 | 5 | 5 | **5** |
| …that would have produced a **false finding** | 3 | 2 | 3 | **3** |
| …**ship-blocker-shaped** | 2 | — | 2 | **1** |
| …caught **before** the operator was asked for anything | 1 of 8 | 2 of 5 | 3 of 5 | **4 of 5** |
| Product observations carded | 1 | 0 | 1 | **2** |

### 12.2 The five, each with when it was written and what caught it

| # | Defect | Written | Caught by |
| --- | --- | --- | --- |
| 1 | `H()` bound to `Get-History`; every hash `$null`; `LOG_ARCHIVE_IDENTICAL=True` computed as `$null -eq $null` | **this session**, ~20 min in | **reading `az`'s error block instead of only its output** — the exception text arrived beside a result that otherwise looked clean |
| 2 | `UST.4a`'s assertion never corrected, though the close-out and the job card both said it was | **2026-08-28**, before provisioning | **reading the tree before running it**, prompted by the card asserting a correction existed |
| 3 | **the run plan omits log rotation**, and the uninstall log APPENDS → `BOTH_MARKERS` → false `TL.1` FAIL | **2026-08-28**, in section 19's step list | **reading `resources/uninstall.ps1:51` before dispatching**, then measuring the live log's marker counts |
| 4 | the run plan omits clearing stale probe evidence from the dispatcher's fetch path | **2026-08-28**, in section 19's step list | **a read-only discovery pass run before any mutation** |
| 5 | `run-command` truncates its output; the single-shot log pull returned silently truncated base64 | **this session**, at retrieval | **checking the decoded byte count against the known 4826**, rather than trusting a command that exited 0 |

**Three of the five would have produced false findings** (#1, #2, #3), and **#3 was
ship-blocker-shaped**: a `TL.1` FAIL on the last row of the last box, wearing the
exact costume of card `#286`'s defect.

**Four of the five were caught before the operator was asked to do anything**, which
is the highest proportion of the four sessions. The fifth was caught before
teardown.

### 12.3 What the comparison shows — and the thing box D predicted, repeating

Box D §15.3 named the next clause-shaped lesson:

> *The measurement being right does not make the expectation right. State where each
> expectation came from, and re-derive it when the thing it describes changes.*

**Defect #2 is that lesson exactly, one session later, unfixed.** The `UST.4a`
*measurement* was added and the *expectation* attached to it was not re-derived —
the same shape as box D's own `ST.0` (right list, superseded value) and its
regex-escaped canary blind spot.

**But defects #3 and #4 are a class box D did not name, and it is worth naming
now.** Neither is a wrong expectation inside a probe. Both are **correct probes
placed in a plan that did not account for the state the box was already in.** The
probes were right; `BOTH_MARKERS` is a state `teardownlog` classifies deliberately,
and the dispatcher's fetch-by-name is documented in its own source. What was wrong
was the *sequence* — and a sequence is not calibrated by any of the five clauses,
because every clause governs an instrument rather than the order instruments run in.

**The generalisation, offered for the next card:**

> **A probe is calibrated against a rigged input; a RUN is not. Before the first
> dispatch, read what the box already holds that the probe will read — logs that
> append, evidence files fetched by name, snapshots about to be overwritten — and
> state what each will contain at the moment the probe reads it. A second run over
> a box that has already been run is not the same measurement as the first.**

Both defects were caught this session by exactly that discipline, applied
informally. Written down it becomes repeatable.

### 12.4 And the honest line, for the fifth session running

**The product looked better than my instruments.** Zero product defects against
five instrument and plan defects, three of which would have been false findings and
one of which would have looked like a ship-blocker on the final row of the final
box.

---

## 13. TASK 7: THE FITNESS-TO-PUBLISH VERDICT

Box D §16.4 withheld this on one named item. **That item is now measured.**

Every claim below carries verbatim evidence. **Anything argued rather than measured
is labelled INFERRED in the sentence that makes the claim.**

### 13.1 THE VERDICT: **YES**

**v1.4.4 — signed sha256
`6e65560325cb6d7d3fea204ebb72876b3b113cbbfe9f2fa4f94113237e9eb4d1`, 440,610,608
bytes, build commit `25945d5` — is fit to publish**, subject to two disclosures
that are release-notes items and not blockers (§14.1, §14.3), and one cosmetic
decision that is the operator's and does not change the verdict either way (§14.2).

**This yes contains no argued premise.** Every row it rests on is a measurement
with a control that fired in the same run. The three items in this cycle that are
inferred rather than measured are enumerated in §13.4, and **none of them carries
any weight in the yes** — each is either a gap being disclosed or a coverage claim
about a path not being separately tested.

**Across four boxes and this entire validation cycle, zero product defects were
found on v1.4.4, and nothing measured is a regression.** The only product-shaped
findings in the whole cycle are cosmetic and carded: box A's encoding class
(`#296`), and this session's two dialog observations (`#307`, `#308`).

### 13.2 What the yes rests on, all measured, across boxes A / B / C / D

| Claim | Box | Evidence |
| --- | --- | --- |
| The installer installs, completely and identically, across four boxes and three provider variants | A B C D | `PASS 15/0/0/4 of 19` four times; 34 resources by independent enumeration; seven pins re-derived on the box |
| It installs with the licence host unreachable, where the old licence-carrying build dies in 7 s under the identical block | C | row 2, `8/8`, 2 controls, 3 preconditions; both binaries pinned by digest on the box |
| The provider gate is SKIPPED with a stated reason when the provider is deferred, and the install still completes | B | row 4, `5/5`, both halves |
| The provider gate ABORTS loudly when the provider is unreachable, naming itself and telling the operator what to do | C | `PG.3f`, `16/16`, 7 of 7 controls — open since v1.3.5, closed |
| All ten shipped Windows-side `.ps1` are CR-free and byte-identical to the committed blobs | B | CR census `15/15`, counter calibrated both directions, SET compared both directions |
| The shipped wrappers execute | A | `WR.1/2/3/4/7/8/9` |
| The kill switch, and its refusal to claim success unverified | A | `8I.1`, `8I.2` |
| **The keep-Linux uninstall removes everything it installs**: 11 units → 0, 8 enablement symlinks → 0, 17 helpers → 0, `clawuser` and home gone, nft table gone, `/etc/clawfactory` and both maps gone, registry / ProgramData / tasks gone, distro still registered | D | `22/1/1 of 24`, after-control fired |
| **Everything the installer places under `{app}` is removed** — 56 files → 0 — with the kept distro's backing store correctly surviving | **D-completion** | `UST.4a` PASS, §9.2, on a corrected row calibrated in four directions |
| The uninstaller's unit and helper lists are EXACTLY the set the installer places, zero differences either direction, **on two separate installs** | D + **D-completion** | `UST.1a`/`UST.1b` 11/11 and 17/17, twice |
| **The teardown states what it left, and the caller REQUIRES that statement — proven in BOTH directions** | D + **D-completion** | `TEARDOWN_OK` + `left=[ ]` on the clean run; **`TEARDOWN_INCOMPLETE` + `left=[ /etc/clawfactory ]` on the fault-injected run, with `exit code = 0`** |
| **The failure path reports honestly to the user AND tells them how to recover** | **D-completion** | `TL.4`, `TL.5`, plus the dialog observed and screenshotted by the operator |
| Nothing ClawFactory installed runs at the next boot of the kept distro | D | `NONE_LISTED`, `fw.service` ABSENT, no failed units, across a proven restart |
| **A reinstall onto the emptied distro COMPLETES** — the v1.4.1 blocker is gone | D | `INSTALLER_DONE=success`, `clawuser` recreated |
| The credential file is unreadable by the agent uid, and the real secret appears on none of eight surfaces | D | `G2.10`, `S.4`, `S.4leak` + `S.4ctl` |
| `clawuser` has no route to SMTP at any destination, gmail included, with both controls | A D | `G2.9`, `S.1` + three controls |
| The agent cannot approve its own send through any of five channels | A D | `G2.8`, `G2.8c` |
| The broker refuses to submit a credential over an unencrypted transport | D | `ST.1` |
| The uninstall dialog's copy is correct, honest and correctly rendered, **on two independent invocations** | D + **D-completion** | §7, screenshotted |

### 13.3 TASK 7.3(a): is v1.4.2's, v1.4.3's and v1.4.4's work now covered? **YES, all three, with no uncovered row**

| Release | Its change set | Covered? |
| --- | --- | --- |
| **v1.4.2** — the keep-Linux uninstall: eleven units disabled before deletion, seventeen helpers named, the drop-in directory, `/usr/local/bin/clawfactory-send`, `XDG_RUNTIME_DIR` on the gateway stop, the `deluser` escalate-verify-report loop, the `READBACK` line and terminal marker | **FULLY COVERED.** Box D §12.3/§12.5/§12.6/§13 measured every item on the success path; **this session measured the one row box D could not — the marker's FAILURE path.** Nothing in v1.4.2 is now unmeasured |
| **v1.4.3** — line-ending re-materialisation, the Worktree-pin build gate, LF-normalising the teardown payload before transport | **COVERED.** Box B's CR census: all ten shipped `.ps1` at CR=0 and byte-identical to the repo at the commit under test. Box D added the consequence; **this session added a second one — the transported teardown ran to completion and emitted its marker on a SECOND uninstall**, which is what the CRLF defect prevented on cfv-176 |
| **v1.4.4** — the wrapper fixes (kill switch out of the structural table, the ninth interpolation build gate, the wrapper-execution phase) | **COVERED.** Box A: `8I.1`, `8I.2`, `WR.*`, sections 14.6/14.8/14.9/14.10; box B: the CR census closing 14.11's missing half |

**Unmeasured and NOT attributable to any of the three:** `G2.6`, which predates all
of them — see §14.1.

### 13.4 TASK 7.2: what is INFERRED rather than measured, in this whole cycle

Three, none of them load-bearing for the yes:

1. **§14.3** — that the four-of-eight `#261` intermittency split is *consistent
   with* a rotating-address-pool mechanism. Nothing in any run measures the pool.
   **INFERRED.** The split itself is measured (96 attempts).
2. **A reinstall after the RemoveAll branch** needs no separate row because
   RemoveAll unregisters the distro and a reinstall there reduces to the ordinary
   clean-install path every box already exercises. **INFERRED**, though the premise
   (RemoveAll unregisters the distro) is measured, by box A. **It is listed in
   §14.5 as not-measured rather than counted as covered.**
3. **Box D §12.4** — that the exclusive-open failure on `ext4.vhdx` indicated WSL
   holding it. **INFERRED as to mechanism.** The conclusion that mattered — that
   the file is the registered distro's backing disk — was measured from
   `BasePath=C:\Program Files\ClawFactory\WSL`, and **this session removed the last
   dependence on that inference entirely** by asserting on the installer's own
   artifacts instead of on the directory (§9.2).

Everything else in this document is a reading.

---

## 14. CARRIED FORWARD, RESTATED IN FULL RATHER THAN SUMMARISED

### 14.1 `G2.6` — the largest single gap in the evidence, and it is a RIG problem

**`G2.6` asks: after approval, if the source attachment is rewritten, do the
APPROVED bytes go or the tampered ones?** It is the most important single assertion
in the Guard 2 job.

**It has NEVER been measured on any release of this product, on any box, in this
project's history.** Not on v1.4.4, not on v1.4.3, not on any earlier version.

**It is a rig transport problem, not a product failure**, and the distinction is
measured rather than argued:

* Against the plain loopback sink, the broker **correctly refuses**:
  `{"ok":false,"code":"ESMTP","error":"127.0.0.1:2525 does not offer STARTTLS; refusing to submit in cleartext"}`.
  That refusal is recorded as a *positive security property* by `ST.1` PASS. A
  broker that submitted a credential in cleartext would be the defect.
* Against a STARTTLS sink with a locally-trusted throwaway CA, this node build will
  not read the system trust store:
  `NODE_TLS_VERDICT=REJECTED unable to verify the first certificate`.
  `ST.2`/`ST.3`/`ST.6` record VOID **with the reason**.

**So the product behaves correctly in both directions and the harness cannot reach
the assertion.** Card `#305`.

**Said plainly, for the release notes rather than omitted:** ClawFactory ships with
a post-approval payload-binding guarantee that this validation cycle did not
measure. The surrounding mechanism *is* proven — enqueue, approval, single-use
approval, payload hash binding at approval time (`G2.5b`, wrong payload hash voids
the approval), receipt, staging purge, and the refusal of a replayed approval — but
the specific end-to-end "the approved bytes are the bytes that arrived" comparison
was never made, because nothing ever arrived.

### 14.2 The mojibake class, as a decision the operator has to make

**Stated as a choice with costs. No recommendation is made.**

**What it is.** Five shipped `.ps1` are UTF-8 **without a BOM**, and Windows
PowerShell 5.1 decodes a BOM-less `.ps1` as the ANSI codepage, so each em dash
(`E2 80 94`) renders as three garbage characters. **Seven occurrences are
customer-visible:** five in `rename-agent.ps1`'s dialog, two in `bootstrap.ps1`
(one lands inside a written `agent.md`, one in a `WARN` line that reaches the
console and the install log). The rest are in comments. Card `#296`.

**It is cosmetic.** Nothing about the sandbox, the firewall, the guards, the
gateway or containment is implicated. The meaning survives; it looks broken.

**It is customer-visible in a dialog whose job is explaining a decision** — the
`rename-agent.ps1` dialog exists solely to explain why renaming is not supported
yet.

**It is NOT in either uninstall dialog**, measured both ways across two independent
invocations (box D §12.2; this session §7).

| Path | Cost |
| --- | --- |
| **Ship v1.4.4 as it is** | The defect ships. A customer's first impression of a considered explanation is that the software cannot render a dash. Zero engineering cost, zero schedule cost, **and no measurement in this document is invalidated** |
| **Fix it** | Re-saving five files as UTF-8-with-BOM is minutes of work. But it changes shipped bytes, which means **v1.4.5, a rebuild, a re-sign, and a re-validation** — *"prior measurements do not transfer across a rebuild"* is the premise this entire cycle rests on. Concretely: **all four boxes' results, including this session's, would be against a superseded artifact.** Box A cost 5.5 hours, boxes B+C about 9, box D about 9, this completion about 1. A re-run need not be as thorough as the first, but the install, the pins, the bundled-bytes checks and both uninstall branches would have to be retaken |
| **Fix it AND add the tenth build gate** (no shipped `.ps1` may contain a non-ASCII byte without a BOM) | Same rebuild cost, plus a byte-level gate that closes the class permanently rather than the instance. Card `#296` already specifies it |

**No recommendation. The decision is the operator's.**

### 14.3 `#261` as an accepted, written condition of shipping

**Reported as PRIOR measurement. No recommendation is made and no verdict is taken
here** — boxes B/C deliberately took none, box D added no second opinion, and this
session adds no third.

**What was measured (boxes B/C, cfv-180, 96 attempts across 8 toolchain hosts, 12
attempts each, as uid 1000, switch confirmed ON, with both controls firing in the
same run — `api.anthropic.com` 12/12 must-connect and `example.org` 0/12
must-not):**

| Host | Connected |
| --- | --- |
| `clawhub.ai`, `objects.githubusercontent.com`, `raw.githubusercontent.com`, `registry.npmjs.org` | **12 / 12** |
| `codeload.github.com` | 10 / 12 |
| `api.clawhub.ai` | 9 / 12 |
| `github.com` | 7 / 12 |
| `api.github.com` | 6 / 12 |

**Four of eight toolchain hosts answered on every attempt; four did not.** Every one
of the eight answered at least once, so a working route was built to each — that is
`#276`, and `#276` is closed.

One incidental cross-check: `api.clawhub.ai` returned 11/12 and then 9/12 minutes
apart on the same box with nothing changed between, which is a direct observation of
the variability itself.

**In the terms a release-notes reader needs:** with the software-source switch ON, a
fetch from a GitHub-family host may intermittently fail and succeed on retry. The
firewall holds a snapshot of resolved addresses while those services answer from a
rotating pool, so an address that was allowed at refresh time may not be the address
DNS returns moments later. *(That mechanism is **INFERRED** — it is consistent with
the split, but nothing in any run measures the pool itself.)* A user sees an
occasional failed download that works when retried. **It does not affect the
provider route**, which is separately allowlisted and measured at 12/12.

### 14.4 `#198`, VOID by design

**`#198` is the only transmitting path in this suite and it was deliberately not
run, on any box, in this entire cycle.** It is gated behind **both** a present
credential **and** `-ExpectRealCredential`; that switch was not passed on any box.
`G2.198` records VOID with its reason on every run.

**The reason it stays VOID rather than being closed:** it is a *receiving-provider*
outcome, not a ClawFactory behaviour. When it was last exercised, Gmail accepted a
real message with a `250 OK` and Microsoft silently filtered it inbound. **Neither
result measures anything about the product.** Guard 2's delivery path — enqueue,
approval, single-use approval, payload binding, receipt, staging purge — is proven
end to end by the other rows, and the one assertion still owed inside it is `G2.6`,
which is a transport problem in the rig (§14.1, card `#305`) and not a delivery
question.

**Zero outbound email left this cycle, including this session.** `phase3b` was never
run, `-ExpectRealCredential` was never passed, and the only SMTP destination
reachable in phase 3 was the loopback sink at `127.0.0.1:2525`. **This session ran
no send path at all.**

### 14.5 Everything else recorded as unmeasured, so the yes is not read as covering it

| Item | State |
| --- | --- |
| `G2.6` | **UNMEASURED on every box in this project.** §14.1, card `#305` |
| `#198` external delivery | **VOID by design.** §14.4 |
| `G2.13` phase-3 leak scan | **VOID, correctly** — ran against the loopback sink credential; the same claim IS measured against the real secret by `S.4leak` |
| A reinstall after the **RemoveAll** branch | **not attempted.** INFERRED to need no separate row (§13.4 item 2) |
| Cross-account install | **never measured** — out of scope since JOB 3; v2 |
| `SP.8` | **not run on box D or here** — not in the plan; not adjusted, retired or inverted |
| `PIN.rootfs` | INFO, a dead literal — nothing compares it post-install; unchanged since v1.4.3 |
| The mojibake class in `rename-agent.ps1` / `bootstrap.ps1` dialogs | **not exercised on any box this cycle**; known from the bytes, carded `#296` |

---

## 15. CARDS, VERIFIED FROM THE BOARD AFTER WRITING

| Card | Before | After | Basis |
| --- | --- | --- | --- |
| **`#286`** teardown output discarded, success logged unconditionally | **Review (HELD)** | **done** | **Both directions measured. `TEARDOWN_INCOMPLETE` with `left=[ /etc/clawfactory ]` while `exit code = 0`** — §8. Four-part evidence comment posted |
| `#284` | done | done | unchanged |
| `#285` | done | done | unchanged |
| `#287` | done | done | unchanged |
| **`#307`** incomplete-teardown dialog shows the log path as an 8.3 short name | — | **idea** (new) | §7, §8.4, §12; cause measured via `Scripting.FileSystemObject` |
| **`#308`** "Linux cleanup incomplete" followed by "successfully removed" | — | **idea** (new) | §7; both readings stated, no recommendation |
| `#293` v1.4.4 built and signed — NOT validated | Review | **done** | the verdict is taken; §13 |

**Not touched, by instruction:** `#261` and `#198`.
**Left as they are:** `#296`, `#300`, `#302`, `#303`, `#304`, `#305`, `#306`.

*One process note worth recording:* the Dispatch `add_comment` route rejected a
2959-character body on **every** field name, which reads exactly like a wrong field
name. A short probe then succeeded on `content` — **so the field was right and the
limit was the cause.** Posting in four ~850-character chunks succeeded 4 of 4. The
distinction was measured with a one-line probe rather than guessed at, and the
working chunk size is recorded here so the next session does not rediscover it.

---

## 16. THE FIVE CLAUSES, ANSWERED SPECIFICALLY

**CLAUSE 1 — DISCOVER, DO NOT ASSUME; discover the VALUE, and state what the
calibration covered.**

Answered. The fault target was **discovered** by listing `/etc/clawfactory` and
printing all eighteen entries before choosing one, and the chosen name was written
to a marker file so the cleanup pass asserts on *that* name rather than a remembered
one. The uninstall log path was **discovered across five candidate profiles**. The
box's own state — the appending log, the stale fetch-path files, the snapshot's
missing fields — was **discovered by a read-only pass before any mutation**, which
is what caught defects #3 and #4. **What the `UST.4a` calibration covered is stated
explicitly in §1.4, including what it did not cover** (the WSL reader and the
dispatcher).

**CLAUSE 2 — CLASSIFY, DO NOT TEST FOR ABSENCE.**

Answered, and this is the session where it paid. `STATE=TEARDOWN_INCOMPLETE` came
from a named, exhaustive, mutually exclusive set
(`NO_LOG | NO_MARKER | TEARDOWN_OK | TEARDOWN_INCOMPLETE | BOTH_MARKERS`) with the
state printed. **A probe that tested for the absence of `_OK` would have scored
`NO_LOG` and `NO_MARKER` as INCOMPLETE and passed on a teardown that never ran at
all.** `BRANCH_STATE` is classified the same way, and `TL.PRE.BRANCH` is what makes
the marker attributable to the keep-Linux branch.

**CLAUSE 3 — STATE WHEN THE MEASUREMENT IS TAKEN.**

Answered. The before-state was **retaken against the reinstalled box** rather than
compared to a snapshot from a previous install, and §4.1/§5 record why (the box had
changed, and the snapshot predated the reader). The fault was injected
**immediately before** the uninstall it enables, not staged in advance —
PROMPT 15's expiring-probe rule. `UST.3z` asserts the snapshot being compared
against is a Before snapshot. The log was rotated **before** the uninstall, and the
rotation verified before the operator was asked to act.

**CLAUSE 4 — DECLARE PRECONDITIONS PROMPT 15 ALREADY DECIDES.**

Answered and **all met**: `FI.PRE` (a file exists to make immutable, on an
ext-family filesystem, with `chattr` present), `FI.C.PRE` (the injected target is
known from the marker), `TL.PRE.LOG`, `TL.PRE.BRANCH`, `UST.PRE.SNAP`,
`UST.PRE.COMPLETE`. `preconditions declared=N met=N` in every phase.
**`TL.PRE.BRANCH` is the one that matters most**, because a marker read from a
RemoveAll log would measure nothing this session exists to measure.

**CLAUSE 5 — DO NOT FIX SHIPPED BYTES MID-VALIDATION.**

**Held. No shipped byte was changed by this session.** The mojibake class stays
carded as `#296`; the two new dialog observations were **carded, not fixed**
(`#307`, `#308`). The only code change was to `interim-v144-uninstate.ps1`, a
validation file that does not ship — made because the uninstall later in this same
run re-exercised the corrected row on the same box, which validates it rather than
shipping it unproven, and it was calibrated in four directions first.

---

## 17. TASK 8.4: END-OF-SESSION GATE

### 17.1 Task accounting

| Task | State |
| --- | --- |
| PROMPT 15 preamble, pasted in full, staleness checked | **DONE** — §0, line 645 of 925, not stale |
| Challenge duty | **DONE** — three challenges, all raised before the operator was asked for anything, §1 |
| Start the box, re-read the RDP `/32` against the live address | **DONE** — §3, two independent readers |
| Operator card: RDP, `start-runner.cmd` elevated, `wrapper.cmd` named as the wrong one | **DONE** — Card A |
| `teardownfault -Mode Inject`, both controls | **DONE, PASS 6/6** — §6 |
| Operator card: uninstall, Yes to Inno, No to ClawFactory, dialog read back verbatim | **DONE** — Cards B and C, §7, screenshotted |
| `teardownlog -Expect INCOMPLETE` | **DONE, PASS 8/0/0/1** — §8 |
| `uninstate -Mode After`, validating the `UST.4a` correction | **DONE, 22/1/2 of 25** — §9; the correction was completed first, §1.1 |
| `teardownfault -Mode Cleanup` | **DONE, PASS 4/4** — §10 |
| Teardown by explicit name, NIC first, unfiltered proof | **DONE** — §11 |
| **9.1 `#286` to done iff `TEARDOWN_INCOMPLETE` recorded** | **DONE — condition met, card moved and verified from the board** — §8, §15 |
| **9.2 convert the withheld verdict** | **DONE — YES** — §13 |
| `G2.6` carried forward, stated plainly | **DONE** — §14.1 |
| Mojibake as an operator decision, no recommendation | **DONE** — §14.2 |
| `#261` as an accepted written condition, prior measurement labelled prior | **DONE** — §14.3 |
| `#198` VOID by design with the reason | **DONE** — §14.4 |
| Instrument-defect count and when each probe was written | **DONE** — §12 |
| Library-entry wording recommended, library NOT edited | **DONE** — §18 |
| Close-out committed, printed in full, both repos pushed, no tag | **this document** |

### 17.2 Resource ledger

| | |
| --- | --- |
| VMs provisioned | **0** — `cfv-182` was restarted, not rebuilt |
| VMs running now | **0** |
| VMs deleted | **1** — `cfv-182`, with all four orphan classes swept explicitly, NIC first |
| Concurrency | never more than one box existed |
| Compute window | roughly 13:12 to 14:10 UTC, **about one hour** at ~$0.10/h, so **about $0.10** |
| Cumulative for box D | ~10 hours across two sessions, **about $1.00**, plus one OS disk held overnight |
| Licence slots | none consumed; no licence check exists since v1.4.0 |
| Background tasks | **none started** |
| Persistent Monitors | **none started** |
| Local WSL rigs | **none.** Nothing touched the build machine's own ClawFactory install. The `UST.4a` calibration ran against in-memory rigged objects, not against this machine's state |
| Repo mutations outside the commits | **none.** `git status --short` empty at every commit boundary |
| Outbound email | **NONE** — no send path was executed in this session |

### 17.3 Credential hygiene

**No password was generated, printed, requested or set by this session.**
`az vm user update` was **never called** — the operator used the password he set at
Card 1 during box D's provisioning, which is the one sanctioned use, and Card A said
so explicitly and told him to stop and report rather than let me reset it. The SMTP
app password was **not touched**; it remains the deliberately KEPT throwaway.
`DISPATCH_SECRET` was read **single-key by name** from `FrontierAI/.env` and
reported only as `present=True len=64 (values not printed)`. `DISPATCH_URL` likewise
never printed. **No secret value appears in any evidence file, commit, card comment
or message.**

### 17.4 Delta security sweep

**No product code was changed by this session.** Committed: one corrected assertion
in a validation probe, one new INFO row, and this close-out.

* `interim-v144-uninstate.ps1` is **not bundled** and does not ship. Verified: it
  appears in no `[Files]` entry of the `.iss`.
* **The injected fault was removed and the removal VERIFIED, not assumed** — §10,
  `FI.C.1` and `FI.C.2`, with the immutable bit visibly cleared in `lsattr` and the
  directory subsequently removed by the same operation that had been refused. **No
  fault remains anywhere**, and the box no longer exists in any case.
* The three files moved into `C:\cfv\run1-archive` were on the VM only and went with
  it; their content is preserved in this repo's evidence directories and in box D's
  close-out.
* **The artifact validated is byte-identical** to the one built at `25945d5` and
  signed as `6e655603…`. Nothing was rebuilt, re-signed or re-versioned.
* **Zero product defects found.** Nothing was fixed in shipped bytes, which is
  clause 5.

### 17.5 Delta bug review

Five instrument and plan defects, three of which would have produced false findings
and one of those ship-blocker-shaped. Counted, timed and root-caused in §12. **Zero
product defects.** Two cosmetic product *observations* carded (`#307`, `#308`).

### 17.6 Files changed

```
aa0d5b8  validation(box D): complete the UST.4a correction -- the reader was fixed, the assertion was not
<this>   docs(closeout): box D completes -- the negative half MEASURED, #286 closed, verdict YES
```

Plus evidence under `validation-runs/cfv-182-*-20260829-*` (five run directories)
and the retrieved product log
`cfv-182-teardownlogINCOMPLETE-20260829-074847/ClawFactory-Uninstall-run2.log`.

**No shipped byte was changed. No tag was created. No release was published.**

### 17.7 TASK 5's standing traps, each accounted for

| Trap | Outcome |
| --- | --- |
| 1. never `az vm user update` after provisioning | **held** — never called; Card A told the operator I would not, and to stop and report instead |
| 2. one `run-command` at a time, subscription-wide | **held** — every dispatch sequential |
| 3. `run-command` is SYSTEM, cannot touch WSL, reads a different profile | **held** — every WSL probe went through the interactive runner; the log path was **discovered** across five profiles rather than taken from SYSTEM's `%TEMP%`; the archive/rotation used absolute paths, which is a Windows filesystem operation SYSTEM performs correctly |
| 4. `$( )` in an inline WSL payload comes back empty | **held** — every payload went through the file channel and emitted values as plain output |
| 5. an errored `az`'s empty output is not evidence | **held, and it fired twice.** The single-shot log pull exited 0 with silently truncated output (defect #5), caught by checking the decoded byte count; and the `H()` collision arrived as an error block beside otherwise-clean output (defect #1) |
| 6. a resource may still list after a successful delete | **held, not needed** — nothing still listed; recorded as which of the two it was |
| 7. **`H()` collides with `Get-History`** | **VIOLATED — this is instrument defect #1.** Caught in the same result and re-verified with a named function plus both controls, §4.2 |
| `SP.8` will FAIL, do not adjust | **held** — not run at all, and stated rather than left to look like a pass |

---

## 18. THE LIBRARY ENTRY, RECOMMENDED NOT WRITTEN

Box D §15.3 asked that its lesson be carried into PROMPT 15 permanently. **The
library was NOT edited in this session, per instruction.** Recommended wording,
combining box D's lesson with the class this session found beside it:

> **THE MEASUREMENT BEING RIGHT DOES NOT MAKE THE EXPECTATION RIGHT.**
>
> State where each expectation came from, and re-derive it when the thing it
> describes changes. Three of five defects in one session were correct measurements
> with stale expectations attached — a row asserting a RemoveAll property on the
> keep-Linux branch, an assertion naming a seed host that had been deliberately
> replaced, a sweep pattern blind to the syntax its own subject was written in.
> **Discovering the subject harder does not fix any of them.** When a probe is
> edited to measure something new, the assertion is a separate edit and needs its
> own calibration: adding the reader and leaving the verdict alone produces a probe
> that gathers the right evidence and still returns the wrong answer.
>
> **AND A PROBE IS CALIBRATED AGAINST A RIGGED INPUT; A RUN IS NOT.**
>
> Before the first dispatch of a session, read what the box ALREADY HOLDS that the
> probes will read — logs that append rather than truncate, evidence files the
> dispatcher fetches by name, snapshots about to be overwritten — and state what
> each will contain at the moment the probe reads it. **A second run over a box that
> has already been run is not the same measurement as the first.** No clause governs
> this, because every clause governs an instrument rather than the order instruments
> run in.

---

## 19. WHAT THE NEXT SESSION INHERITS

**Box D is closed. The v1.4.4 validation cycle is closed. The verdict is YES.**

Nothing is owed by this job. What exists, for the operator to decide on:

1. **The mojibake decision** (§14.2, card `#296`) — three paths, costs stated, no
   recommendation. It does not change the verdict either way.
2. **Two release-notes disclosures** — `G2.6` (§14.1, card `#305`) and `#261`
   (§14.3). Both are disclosures, not blockers.
3. **The release action itself** — tag and publish v1.4.4. **This session created no
   tag and published nothing**, by instruction.
4. Queued cards untouched by this cycle: `#296`, `#300`, `#302`, `#303`, `#304`,
   `#305`, `#306`, and the two new ones, `#307` and `#308`.

**Do not re-run anything recorded here against this artifact.** It is the same
digest, and `cfv-182` no longer exists.
