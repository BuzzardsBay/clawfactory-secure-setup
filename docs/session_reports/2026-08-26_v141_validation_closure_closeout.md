# CLOSE-OUT: v1.4.1 validation closure, box cfv-176

Session 2026-08-26. The four items the previous run left unmeasured: a clean uninstall,
the install-time fatal read-back, matrix rows 2 and 4, and check 10.
One VM. No tag, no GitHub release, no publish, no rebuild, no re-sign. Zero outbound email.

**STATUS: COMPLETE. All four items measured.** Three of the four are clean passes. The
fourth — the uninstall — passed on the branch a silent uninstall takes and **failed on the
branch the dialog offers**, which is a new defect class this release had never exercised.

**The fitness verdict is NO, and for a different reason than last time.** Section 9 names it
in one sentence and says exactly what flips it.

---

## Session summary

**The job.** The v1.4.1 close-out refused publication on coverage, not on any defect: the
uninstaller had changed and no uninstall had been run, an install-time fatal had never fired,
two matrix rows were unmeasured, and check 10 was untaken. This session measured all four.

**The headline: every previously-unmeasured item is now measured, and the uninstall is where
the news is.** Rows 2 and 4 pass with controls. The fatal read-back fires, aborts, and quotes
both named messages verbatim — and leaves the machine fail-closed. Check 10 was observed on
the rendered GUI by the operator. The uninstall passes cleanly on the RemoveAll branch and is
**materially broken on the keep-Linux branch**, which had never been run in the history of
this product.

**Four new product defects, all in the uninstaller, all measured with controls.** Cards `#284`
through `#287`. The sharpest is `#287`: the keep-Linux dialog tells the user *"You can
re-install ClawFactory later and reuse the existing distro"*, and a reinstall on that branch
was measured to ABORT. The product makes a promise this run proved false — the same class of
defect as `#274`, which was a reason for the v1.4.0 refusal.

**One hypothesis of mine was refuted by its own rig, and is recorded rather than deleted.**
I predicted the teardown was truncated by stdin consumption. A rig with a known answer and a
one-line-different control killed that theory in ninety seconds. The FAIL row stands in the
evidence.

**Nothing was published, tagged, sent, or rebuilt. No product code was changed.** Every commit
this session is validation instrumentation.

---

## 0. Task accounting

| Task | State |
| --- | --- |
| PROMPT 15 preamble | **Read in full from the library and followed.** Present at line 645; the library is NOT stale. VM clauses included, nothing deleted |
| 0.1 Plan and cost stated before provisioning | **DONE** — one box, sequence published before `az vm create`, 3–4 h estimate; actual ≈ 4 h 15 m |
| 0.2 Delete accumulated `combined-*.exe` blobs | **DONE** — 17 deleted, 6.98 GB reclaimed, read back from the service |
| 0.3 Stale defaults fixed | **DONE** — `#282` seed host (`c42274f`); switchprovider injection file made structural (`0278fa6`) |
| 0.4 Starting estate clean, unfiltered list | **DONE** — already clean, nothing to delete |
| 1.1 Clean uninstall through the supported path | **DONE**, both branches, path resolved from the registry |
| 1.2 Removal verified by read-back | **DONE** — 8 named classes, each against its held before-value |
| 1.3 What is left behind, and whether it is correct | **DONE** — and this is where the defects are |
| 1.4 Control proving the enumeration can detect a present resource | **DONE** — three controls, before, after, and distro-side |
| 2.1 Break the registration realistically | **DONE**, shape stated as injected, calibrated first |
| 2.2 Install ABORTS with its named message verbatim | **DONE, PASS** — both messages quoted |
| 2.3 Machine left in a defensible state | **DONE, PASS** — fail-closed, 6 of 6 |
| 3.1 Row 2, licence host unreachable | **DONE, PASS** 7/7 |
| 3.2 Row 4, `-Provider later` | **DONE, PASS** 5/5 |
| 4.1 No automated probe during operator by-hand work | **DONE** — nothing ran while he was on the box |
| 4.2 Handoff cards with PushNotification | **DONE** — two cards, two pushes, checklist inline |
| 5 Standing traps | **DONE** — see section 10 |
| 6 Teardown by explicit name, unfiltered proof | **DONE** — 6 resources subscription-wide, 0 `cfv-176` references |
| 7 Fitness statement | **DONE**, section 9 |
| 8 Cards, close-out, gate | **DONE**, sections 11–12 |

---

## 1. The artifact, unchanged and verified three ways

Build machine, before provisioning:

```
LOCAL_SHA256=90c673ddaf0959418eef8b19b959894581003f0c5dbf0d78cfb2f52beb3ef398
LOCAL_BYTES=440602224   MATCH_SHA=True  MATCH_BYTES=True
AUTHENTICODE=Valid  SIGNER=CN=Bret Mckinney, O=Bret Mckinney, L=West Valley City, S=ut, C=US
```

Re-derived **on the box** after transfer:

```
[09:24:16] Staged, digest re-verified ON THE BOX. OK staged;
artifact=90c673ddaf0959418eef8b19b959894581003f0c5dbf0d78cfb2f52beb3ef398 size=440602224
```

And again by the probe immediately before the deliberately-broken install:

```
[18:35:29] artifact sha256: 90c673ddaf0959418eef8b19b959894581003f0c5dbf0d78cfb2f52beb3ef398
```

The row-2 control artifact, recorded so it is on the record:

```
prior artifact sha256: 67619df79179db11e76454e9734de244a51128b37c55f66071213c98f72719a9  (440,525,520 B)
```

---

## 2. TASK 0

### 0.2 Blob purge, measured at the service on both sides

```
CONTAINER_BLOBS_BEFORE=463  BYTES_BEFORE=8115212460  GB=7.56
COMBINED_COUNT=17           COMBINED_BYTES=7490185080  GB=6.98
DELETE_CALLS=17 FAILED=0
CONTAINER_BLOBS_AFTER=446   BYTES_AFTER=625027380   GB=0.58
RECLAIMED_BYTES=7490185080  GB=6.98
COMBINED_STILL_LISTED=0
PRIOR_SETUP_STILL_PRESENT=True bytes=440525520
```

17 deleted (`cfv-153` … `cfv-175`), **6.98 GB reclaimed**, re-read from the service rather than
inferred from exit codes. The last line is the control: the same listing still sees a blob that
IS there, so `COMBINED_STILL_LISTED=0` means gone rather than unreadable. `prior-setup.exe` was
retained deliberately — row 2's control B2 needs it. Images and storage account untouched.

### 0.4 Starting estate

```
=== az vm list, ENTIRE SUBSCRIPTION ===   (no rows)
=== az resource list -g clawfactory-validation, UNFILTERED ===
clawfactoryvalc467              Microsoft.Storage/storageAccounts
bake-vmVNET                     Microsoft.Network/virtualNetworks
clawfactory-win11-baseline      Microsoft.Compute/images
clawfactory-win11-baseline-v2   Microsoft.Compute/images
```

Already clean. No preserved FAIL VMs existed, so the delete step had no subjects.

### 0.3 The two stale defaults

`c42274f` — `#282`. `interim-v140-stagebox.ps1` seeded `www.iana.org`, whose address set does
not move. Measured on the build machine, six lookups each straight at `8.8.8.8`:
`www.iana.org` = **1** distinct set, `outlook.office.com` = **4** near-disjoint sets. A stale
set for a stable host is byte-for-byte identical to a fresh one, so the old default scores a
false pass on precisely the defect it is seeded to catch.

`0278fa6` — the switchprovider fault-injection file is now staged **structurally** by
`interim-v120-job.ps1`, matched by leaf name, throwing with a named reason if absent. This is
the same hazard the phaselib line immediately above it already closes. Calibrated in three
directions rather than reasoned about:

```
PHASE=interim-v135-switchprovider.ps1 STAGES_SP=True
PHASE=interim-v120-phase3.ps1         STAGES_SP=False
ALREADY_PASSED_would_add=False (must be False)
```

---

## 3. TASK 3: the two matrix rows

### Row 2 — install completes with the licence host unreachable. **PASS, 7/7, controls 2/2**

```
[16:03:53] subject api.clawfactory.app -> 69.46.46.108
[16:03:53] control openclaw.ai -> 216.150.1.1
[16:04:12] after the block: api.clawfactory.app reachable=False ; openclaw.ai reachable=True
[16:04:12]   [PASS] B1 :: POSITIVE CONTROL: the block is real and specific

[16:05:05]    PRIOR> License activation failed under /SILENT - missing or invalid /LICENSE= argument.
[16:05:05]    PRIOR> Got EAbort exception.
[16:05:06] v1.1.1 log says licence activation failed : True
[16:05:06] v1.1.1 left an install behind             : False
[16:05:06]   [PASS] B2 :: POSITIVE CONTROL: the block WOULD have stopped the old licence-carrying build
[16:05:06]   [PASS] B2.1 :: v1.1.1 left the box clean for the subject install

[16:21:44] v1.4.0 returned after 17 min
[16:21:44] install-result.txt: INSTALLER_DONE=success
[16:21:44]   [PASS] B3 :: ROW 2: v1.4.0 installs to completion with api.clawfactory.app unreachable
[16:21:44]   [PASS] B3.1 :: the block was still in force when the install finished

PASS=7 FAIL=0 VOID=0 INFO=0  (counted 7 of 7 recorded rows)
positive controls registered=2 fired=2 ; preconditions declared=2 met=2
```

The shape is what makes it a measurement: the **same block**, on the **same machine, minutes
apart**, stopped v1.1.1 before it copied a file and did not stop v1.4.1. `B3.1` closes the hole
where a block that lapsed mid-install would turn the row into an ordinary install.

**Cosmetic, stated rather than smoothed over:** the probe's banner reads "v1.4.0". That is its
own phase-name string, written for the previous release and never updated. The artifact under
test is v1.4.1 and its digest is on the SUBJECT line.

### Row 4 — the provider gate under `-Provider later`. **PASS, 5/5, controls 2/2**

Install with the provider deferred: **PASS 15/0/0/4 INFO**, controls 2/2, including
`PIN.version PASS Installed version reports 1.4.1` — the fourth stale default fixed last
session holding on a fresh box.

The gate's own words, from the install log the user can read:

```
[2026-08-26 17:00:56] [INFO] Step 15h: Provider-route gate SKIPPED, reason: provider deferred
   (-Provider later). There is no provider to reach yet; the route is proven when a provider is chosen.
[2026-08-26 17:01:05] [INFO] ==== ClawFactory Secure Setup - completed successfully ====
```

```
PG.3a  PASS  TEST 3: with the provider deferred, the gate is SKIPPED and says so
PG.3b  PASS  TEST 3: the deferred install still completed
```

Both halves are required. A gate that silently does nothing when its subject is absent is
indistinguishable from a gate that is broken.

---

## 4. TASK 4: check 10, observed rather than inferred

Taken by the operator by hand on the shipped packaged Studio 1.3.2, over RDP, **with nothing
automated running against the box**. Both halves, because the whole title block is one link and
testing one click leaves the other unmeasured:

- From **Settings**, clicking the **lobster** lands on the home route.
- From **Web access**, clicking the **words "ClawFactory Studio"** lands on the home route.

The home route confirmed by its positive control, not by absence — heading
`ClawFactory Studio`, the paragraph `This is where you decide what your agent is allowed to
do.`, the green pill `ClawFactory Studio v1.3.2` / `Running as a desktop app`, and
`Studio has no server and opens no network port.` Screenshot on file in the session transcript.

`#273` moved to **done**. This is the rendered-DOM confirmation the previous close-out recorded
as NOT TAKEN; the card no longer rests on shipped-artifact evidence alone.

---

## 5. TASK 2: the install-time fatal read-back, exercised for the first time

### 5.1 What was broken, and why that shape

The read-back at `resources/install-read-fetch.sh:384` exists for one narrow failure:
`systemctl enable` returns nonzero, the shipped `|| true` swallows it, and the unit is left not
enabled while every preceding line reports success. The injection reproduces exactly that
observable failure by placing a **directory** at the path the enable must symlink into:

```
/etc/systemd/system/multi-user.target.wants/clawfactory-egress-refresh.service
```

**The mechanism is injected and is labelled as injected.** The failure it produces is the real
one. It is targeted at one unit, which was proven rather than asserted.

### 5.2 Calibrated before an install was spent on it

```
CTL_ENABLE_RC=0        CTL_ISENABLED=enabled     <- the rig can produce a known-correct "enabled"
SUBJ_ENABLE_RC=1       SUBJ_ISENABLED=disabled   <- with the block: enable fails, unit not enabled
SUBJ_ENABLE_OUT=Failed to enable unit: File .../cfv-calib-a.service already exists.
COLL_ENABLE_RC=0       COLL_ISENABLED=enabled    <- a DIFFERENT unit still enables in the same dir
CLEANUP_UNITS_LEFT=0   CLEANUP_WANTS_LEFT=0      <- the rig left no trace of itself
```

5 of 5. The collateral control is the one that matters: an injection that broke every enable
would abort the install somewhere else and prove nothing about this fatal.

### 5.3 The fault landed

```
POST_WANTS_ISDIR=yes   POST_WANTS_ISLINK=no
POST_WANTS_LS=drwxr-xr-x 2 root root 4096 Aug 26 18:29
              /etc/systemd/system/multi-user.target.wants/clawfactory-egress-refresh.service
PRE_OTHER_CF_WANTS=4
```

### 5.4 The install ABORTS, with both named messages verbatim. **PASS 11/0, controls 3/3**

```
[wsl:root err] [install-read-fetch] FATAL: clawfactory-egress-refresh.service did not enable
(systemctl is-enabled said 'disabled'). Without it, the Web access panel would report a live
address count after a reboot while the addresses it names are stale. The firewall itself is
unaffected and still denies, so this is an honesty failure rather than an exposure, but it is
not shippable.

[2026-08-26 18:53:22] [ERROR] Install failed: Failed to install the read-fetch allowlist and the
toolchain toggle (Guard 3). Refusing to finish: the product would offer a Web access panel with
nothing behind it, and a control that is absent is worse than one that was never claimed.

install-result.txt: INSTALLER_DONE=failure reason=Failed to install the read-fetch allowlist and
the toolchain toggle (Guard 3). Refusing to finish: ...
```

Both matched with `String.Contains` against literals copied from the shipped files, never with
a regex loose enough to accept a paraphrase. **The fatal is not a no-op.**

### 5.5 The state the abort leaves. **Fail-closed**

```
FR.R5  PASS  unit file=present, is-enabled='disabled'
FR.R6  PASS  uid 1000 blocked on 6 of 6 attempts to 1.1.1.1:443, while root reached it on 3 of 3.
             nft table=present with 4 terminal-drop line(s).
FR.R8  PASS  Studio: core install did not report success (...); NOT installing Studio
FR.R9  INFO  uninstall registry entries after the aborted install = 1
```

Six attempts as uid 1000, not one, and a root control that must succeed — otherwise "the agent
is blocked" and "the box has no network" are the same reading. An install that failed loudly
and left the agent with an open route would be a worse outcome than the false panel this fatal
exists to prevent. It does not.

`FR.R9` is the honest cost, recorded rather than discovered later: Inno writes its registry
entry and copies files **before** `[Run]` executes `setup.ps1`, and the `.iss` raises no
exception on `setup.ps1`'s exit code. A failed core therefore leaves an installed-looking
Settings entry whose `install-result.txt` says failure. The user can reach Uninstall, which is
the good half.

### 5.6 The first attempt was VOID, and the harness is why that is good news

The first run of this probe aborted at `Failed to create clawuser (exit=1)` — ninety steps
before the read-back under test.

```
FR.R.CTL.LOG  FAIL  the Guard 3 step banner ... was not found either, so every 'absent' result
                    here is meaningless -- this control did not fire, so every measurement it
                    underwrites is VOID
PHASE VERDICT: VOID
```

Without that searchability control, `FR.R2` and `FR.R3` would have reported "the named message
is absent" and read as a **product failure**. The message was absent because the code that
prints it never ran. The cause was `clawuser` left behind by the broken keep-Linux teardown —
defect `#287` blocking the test for defect-free code.

---

## 6. TASK 1: the uninstall. Clean on one branch, broken on the other

### 6.1 Why both branches had to be run

The v1.4.1 diff to `uninstall.ps1` lives **entirely inside the `else` branch** of the
`DoRemoveAll` decision — the keep-Linux path. On the RemoveAll path
`wsl --unregister Ubuntu` deletes the distro and every new line is dead code. A single
RemoveAll uninstall would have reported a clean box while exercising **none** of what changed.

### 6.2 The reader was controlled three ways

```
UN.CTL.BEFORE       PASS  appDir=True resources=34/34 uninstaller=True uninstall-registry-keys=2
UN.0b               PASS  Test-Path on a path that has never existed returned False
UN.CTL.DISTROREADER PASS  READER_CTL_ETC=present READER_CTL_BASH=present
UN.CTL.AFTER        PASS  C:\cfv present=True, C:\Windows\System32\cmd.exe present=True
```

The held before-state, which every later row is measured against:

```
UNIT_FILE=present  UNIT_WANTS=present  UNIT_ISENABLED=enabled  BOOT_SCRIPT=present
TOOLCHAIN_SH=present  READFETCH_SH=present  SBIN_CLAWFACTORY_COUNT=17
UNIT_FILES_CLAWFACTORY=14  ETC_CLAWFACTORY=present  IPS_MAPS=2
NFT_TABLE=present  NFT_CHAINS=1  CLAWUSER=present  OPENCLAW_BIN=present
REG> ...\{8D7C4B2A-...}_is1 'ClawFactory Secure Setup version 1.4.1' v1.4.1
REG> ...\d34a8b58-...       'ClawFactory Studio 1.3.2' v1.3.2
tasks = \ClawFactory WSL Host | \ClawFactory-PostInstall-Smoke
credTargets = Target: LegacyGeneric:target=ClawFactory/AnthropicApiKey
```

### 6.3 RemoveAll branch — the supported path. **PASS 16/0/3 INFO**

The binary was resolved from the registry rather than assumed:

```
UN.2a  PASS  UninstallString resolves to 'C:\Program Files\ClawFactory\unins000.exe'
UN.2b  PASS  [2026-08-26T16:43:51] [INFO] Resolved DoRemoveAll = True
```

```
UN.3a  PASS  Test-Path 'C:\Program Files\ClawFactory' = False (before: True)
UN.3b  PASS  resources found after = 0 of 34 (before: 34)
UN.3c  PASS  uninstall keys matching ClawFactory after = 0 (before: 2)
UN.3d  PASS  Test-Path 'C:\ProgramData\ClawFactory' = False (before: True)
UN.3e  PASS  Start Menu ClawFactory groups after = 0 (before: 1)
UN.3f  PASS  desktop .lnk after = 0 (before: 1)
UN.3g  PASS  scheduled tasks after = 0 [] (before: 2 [\ClawFactory WSL Host, \ClawFactory-PostInstall-Smoke])
UN.3h  PASS  Lxss hive distros after = []; wsl --list --quiet = [] (before Lxss: [Ubuntu])
UN.5   PASS  There is no distribution with the supplied name.
             Error code: Wsl/Service/WSL_E_DISTRO_NOT_FOUND
```

**Left behind, and correctly:**

```
UN.4a  INFO  ClawFactory credential targets after = 0 [] (before: 1)
UN.4b  INFO  %LOCALAPPDATA%\Programs\ClawFactory Studio present after = False (before: True)
UN.4c  INFO  %USERPROFILE%\.wslconfig present after = False
```

Nothing survives that should not. Studio goes with the core uninstall despite being a separate
per-user NSIS app with its own registry entry in a different hive. The **API key credential is
removed** — the leftover with the most real-world consequence. `.wslconfig` was deleted rather
than edited, which is the correct surgical reverse: the state file recorded `created`, so the
installer made the file and removing it restores the machine.

### 6.4 Keep-Linux branch — taken by hand, through the real dialog. **FAIL, 10 PASS / 5 FAIL**

The dialog, quoted as the operator saw it:

```
Also remove the Linux sandbox and all agent data?
Selecting YES will:
  - Unregister the Ubuntu WSL distro that ClawFactory created
  - Delete clawuser's home directory (agents, plugins, config)
  - Delete the OpenClaw install and the bundled VHDX (~6 GB)
Selecting NO leaves the Ubuntu distro registered. Your conversation
history and agent configs stay on disk. You can re-install ClawFactory
later and reuse the existing distro.
```

**Every line the v1.4.1 diff added worked**, on the only branch where it runs:

```
UN.K.PRE  PASS  Resolved DoRemoveAll = False
UN.K.3a   PASS  /etc/systemd/system/clawfactory-egress-refresh.service = absent
UN.K.3b   PASS  its ENABLEMENT is removed, not just the file
UN.K.3c   PASS  /usr/local/sbin/clawfactory-egress-refresh.sh = absent
UN.K.3d   PASS  /usr/local/sbin/clawfactory-toolchain.sh = absent   <- the v1.4.1 addition
UN.K.3e   PASS  read-fetch.sh=absent fetchctl.js=absent
UN.K.3i   PASS  nft list table inet clawfactory = absent, chains counted 0
```

**And the branch as a whole does not:**

```
UN.K.1   FAIL  appDir=True uninstall-registry-keys=0
UN.K.3f  FAIL  ls /usr/local/sbin/clawfactory-* counted 7
UN.K.3g  FAIL  /etc/clawfactory = present; *-ips.map files counted 2
UN.K.3h  FAIL  ls /etc/systemd/system/clawfactory-* counted 12
UN.K.3j  FAIL  /usr/bin/openclaw = present
```

`UN.K.1` is benign and explained by measurement, not by argument: the only thing left in the
app directory is `WSL\ext4.vhdx (6359613440 B)` — the distro the user asked to keep. Inno
removes what it installed; that file was written afterwards, so the directory stays with it.

### 6.5 Severity: not inert files

A count is not a diagnosis. The question is not *is it present* but **is it live**.

```
KL.CTL.READER  PASS  /etc=present /bin/bash=present never-existed-path=absent
KL.4           PASS  nft list table inet clawfactory = absent
KL.2           FAIL  units in state=enabled: 6
                     [clawfactory-fw.service clawfactory-quarantine.service clawfactory-send.service
                      clawfactory-allow-providers.timer clawfactory-quarantine-gc.timer
                      clawfactory-send-gc.timer]; .wants symlinks: 6
KL.3           FAIL  active units: 5 ; processes running as clawuser: 3 ; listeners: 0
```

Six units enabled to run at the next boot, five active at the moment of measurement, three
processes still running as the agent user, `/etc/clawfactory` intact with the egress policy,
both SOUL pins, the persona and the v1.4.1 retention maps, and `/usr/bin/openclaw` still in
place — on a machine whose owner has uninstalled the product.

`clawfactory-fw.service` was measured `enabled` with `active=failed`, because the teardown
deleted the script it invokes while leaving the unit enabled. That is a failed unit in the
journal at every future boot — **the exact outcome v1.4.1's own comment says it added the
egress-refresh disable to avoid**. The fix was applied to one unit and not to its siblings.

### 6.6 Three distinct defects, separated by measurement

**A refuted hypothesis first, recorded because it is evidence.** The shipped script is piped
into bash's stdin and the first command in the unexecuted half is a `node -e` command
substitution, so stdin consumption looked obvious. A rig with a known answer, plus a control
differing in exactly that one line:

```
TD.CTL.RIG  PASS  control rig printed RIG_A=True RIG_B=True RIG_C=True
TD.1        FAIL  subject rig printed RIG_A=True RIG_B=True RIG_C=True
TD.0        INFO  index.json = present, so the if-branch runs and node IS invoked
```

`node -e` does not consume the piped script. **Theory dead in ninety seconds.**

**The measurement that settles it.** The shipped bash, extracted verbatim from
`uninstall.ps1` lines 365–439 (`sha256 3ded3520c217ad…`) and run through the **identical**
invocation, completes:

```
OUT> [uninstall] removing the delete quarantine and the 0 file(s) still held in it
OUT> Removing 'local diversion of /usr/bin/rm to /usr/bin/rm.real'
OUT> [uninstall] /usr/bin/rm divert removed; stock rm restored
OUT> Looking for files to backup/remove ...
OUT> Removing user `clawuser' ...
OUT> OK
invocation exit code: 0

TR.1  PASS  quarantine marker=True ; divert-restored marker=True ; terminal OK=True ; exit=0
```

and removes what the real uninstall left:

```
TR.2.ETC_CLAWFACTORY   PASS  before=present after=absent
TR.2.OPENCLAW_BIN      PASS  before=present after=absent
TR.2.OPENCLAW_MODULES  PASS  before=present after=absent
TR.2.CLAWUSER_HOME     PASS  before=present after=absent
TR.2.VARLIB            PASS  before=present after=absent
TR.2.USRLOCALLIB       PASS  before=present after=absent
TR.2.QUAR_UNIT         PASS  before=present after=absent
```

**So the script is correct and its execution was cut short.** The proximate cause is NOT
established, and is deliberately not guessed at. Card `#284`.

**A second, independent defect the same run separates out:**

```
TR.3  FAIL  enabled clawfactory units before=6 after=4; fw=enabled send=enabled
            providers-timer=enabled
```

Four units are never named in the teardown at all, so a complete second run does not disable
them and no number of re-runs will. Card `#285`.

**A third, which is why the other two reached a release.** `uninstall.ps1` line 437 assigns the
invocation to `$null` with `2>&1` folded in, and line 439 then logs *"In-distro ClawFactory
artifacts removed"* unconditionally. The output that would have shown a half-run teardown is
discarded and success is asserted without being checked. Card `#286`.

**A fourth, with the failure quoted from the tool itself:**

```
BEFORE_CLAWUSER=present
userdel: user clawuser is currently used by process 222
/usr/sbin/deluser: `/sbin/userdel clawuser' returned error code 8. Exiting.
AFTER_CLAWUSER=present
```

The teardown's **first** line stops the gateway with
`sudo -u clawuser bash -c 'systemctl --user stop openclaw-gateway'` and **no
`XDG_RUNTIME_DIR`**, so it cannot reach the user bus; the failure is swallowed by
`2>/dev/null`, the processes survive, and `deluser` exits 8. A later line **in the same
script** already does it correctly: `sudo -u clawuser XDG_RUNTIME_DIR=/run/user/1000
systemctl --user daemon-reload`.

Confirmed by control — killing the processes let the account be removed immediately:

```
=== BEFORE ===  CLAWUSER=present  PROCS=2   ENABLED=4  INJECTION=dir
=== AFTER  ===  CLAWUSER=absent   PROCS=0   ENABLED=0  UNITFILES=0  HELPERS=0
                ETC=absent  OPENCLAW=absent  INJECTION=dir  INJECTION_ISLINK=no
```

And it has a consequence beyond tidiness: with `clawuser` left behind, a subsequent v1.4.1
install **aborted** at `Failed to create clawuser (exit=1)`. Card `#287`.

---

## 7. Instrument defects found this session

**7.1 The uninstall snapshot serialised an object graph.** The held before-snapshot was
**100,420,570 bytes** from a box whose largest captured file is 108 bytes. `Get-Content -Raw`
returns a string carrying the provider's `PSPath`/`PSDrive`/`Provider` NoteProperties, and
`ConvertTo-Json -Depth 6` followed them. Fixed with `[string]` at the point of capture, plus a
ceiling assertion so a recurrence fails loudly. **Canaried in both directions** on the build
machine, because a guard that has never seen the defect is not known to detect it:

```
UNCAST_JSON_BYTES=94997473
CAST_JSON_BYTES=33592
GUARD_WOULD_FAIL_ON_UNCAST=True  (must be True, or the guard is a no-op)
GUARD_WOULD_PASS_ON_CAST=True    (must be True, or the guard fails a healthy run)
```

Re-run: `held snapshot written to C:\cfv\uninstall-before.json (3092 bytes)`, `UN.1b PASS`.
The product was not implicated: `.wslconfig` on cfv-176 is 108 bytes, 3 lines, exactly what
`setup.ps1` writes. Commit `cc272c7`.

**7.2 A waiter whose filter matched pre-existing text.** My first background wait on the
provisioning driver exited instantly because its alternation included `Exception`, which
matched `RemoteException` in an `az` warning printed minutes earlier. Re-armed on strings
verified absent first (`grep -c` returned 0 before arming). No measurement was affected.

**7.3 A job builder with a real PowerShell bug.**
`[Text.Encoding]::UTF8.GetBytes(@"..." -replace ...)` binds as two arguments and threw
`Cannot find an overload for "GetBytes" and the argument count: "2"`. Rewritten to build the
string first. Caught by reading the job's own `.out`, which is why PROMPT 15 says to read
probe stderr rather than only the phase transcript.

**7.4 Three `PRE_*` values in the Inject survey came back `(not reported)`** — a here-string
escaping fault in my own probe. It does not touch the load-bearing assertion (`FR.I1` read the
injected path back directly, with a reader control), but `FR.I2`'s "before" context is thinner
than intended and is not claimed as measured.

**7.5 An `az` list command errored while its siblings printed `[]`.** In the first teardown
verification, one of four list calls returned
`ERROR: the following arguments are required: --resource-group/-g` while all four printed
empty. An errored command's empty output is not evidence, so the whole verification was
re-derived with a single unfiltered `az resource list` whose exit code was checked.

---

## 8. Deviations and judgement calls, stated

**8.1 I modified box state to unblock TASK 2, and it was not the product's doing.** After the
keep-Linux uninstall left `clawuser`, 4 enabled units and helper scripts behind, the v1.4.1
install aborted at `Step-CreateClawUser`. I cleared those leftovers — the ones the product's
own uninstaller was supposed to remove — while preserving the injection, and re-ran. Stated
here because the fatal read-back was measured on a box I had cleaned, not on one the
uninstaller left clean.

**8.2 The RemoveAll uninstall was driven with `/SILENT` rather than clicked.** The binary was
resolved from the registry `UninstallString`, so it is the exact one Settings launches, and it
takes the same `CurUninstallStepChanged` path and the same `DoRemoveAll=true` branch the
dialog's default button selects. The MessageBox render itself was not exercised on that branch
— it was exercised on the other one, by hand.

**8.3 My card named the wrong dialog.** Card 2 described only `uninstall.ps1`'s
sandbox question and not Inno's own "Are you sure you want to completely remove…"
confirmation, which fires first. The operator hit the unnamed one. Corrected in the same
minute; clicking No there would have cancelled the uninstall entirely.

**8.4 A copy defect in the keep-Linux dialog, recorded not fixed.** Its closing paragraph
carries hard line breaks that wrap mid-sentence — *"Your conversation / history and agent
configs stay on disk."* Cosmetic, but it is customer-visible copy in the one dialog where a
user decides whether to delete their own data.

**8.5 Zero outbound email.** `phase3b` was not run. No probe that transmits was run. The
authorisation from the previous session was not carried forward and was not needed.

---

## 9. FITNESS TO PUBLISH

### What is proven, and would survive an audit

- **The artifact is the one that was built.** Three derivations agree; Authenticode Valid.
- **Matrix row 2 passes**, with the block proven real in both directions and the old
  licence-carrying build proven to die under the identical block minutes earlier.
- **Matrix row 4 passes**, with the skip visible, reasoned in the log, and the install
  completing.
- **The install-time fatal read-back is exercised and works** — aborts, quotes both named
  messages verbatim, and leaves the machine **fail-closed** at 6 of 6 with a root control at
  3 of 3.
- **Check 10 is observed on the rendered GUI**, both click paths, with a positive control on
  the destination page.
- **The uninstall is clean on the RemoveAll branch** — 8 removal classes verified by read-back
  against held before-values, credential removed, Studio removed, distro unregistered on two
  independent reads.
- **Every line the v1.4.1 uninstall diff added does its job** on the branch where it runs.
- **No product code was changed this session, and no security control regressed.**

### What is measured and BAD

- **The keep-Linux uninstall branch leaves the product running.** Six units enabled, five
  active, three processes as `clawuser`, `/etc/clawfactory` intact with the egress policy and
  both SOUL pins, `/usr/bin/openclaw` in place, and `clawfactory-fw.service` enabled with its
  script deleted so it fails at every future boot.
- **The product promises something this run measured false.** The dialog says *"You can
  re-install ClawFactory later and reuse the existing distro."* A reinstall on that branch
  **aborted** at `Failed to create clawuser (exit=1)`.
- **The teardown's output is discarded and success is logged unconditionally**, which is why
  the above reached a release.

### Verdict

**NO.**

One sentence, and it contains no argued premise: **the keep-Linux uninstall branch tells the
user they can reinstall later, and a reinstall on that branch was measured to abort.**

That is the same defect class as `#274` — the product stating something about itself that is
not true — and `#274` was one of the two reasons v1.4.0 was refused. The previous NO was on
coverage; this one is on a measured defect.

Three qualifications, so the verdict is not read as broader than it is:

1. **The install side is unaffected.** Nothing found in the uninstaller changes any
   install-side conclusion. Rows 2 and 4, the fatal read-back, the 34 resources, the pins, the
   firewall and the boot unit all stand exactly as measured. If the uninstaller were fixed
   tomorrow, no install-side row would need re-running.
2. **The default path is clean.** A `/SILENT` uninstall and the dialog's default button both
   take RemoveAll, which passed 16 of 16. The break is on the branch a user must actively
   choose.
3. **Nothing here is a security exposure.** The firewall table is removed on both branches, and
   the surviving units are ClawFactory's own brokers, not a hole. This is unwanted persistence
   and a false promise, not an escape.

### What would turn this into a yes

**Option A, the fix.** Cards `#287`, `#285`, `#286`, `#284`: set `XDG_RUNTIME_DIR` on the
gateway stop; add the four unnamed units to the disable list; capture the teardown's output and
check it; and use that capture to find why execution stops. Then one box: install, keep-Linux
uninstall, verify the distro is clean, reinstall, verify it completes. **One box, about two
hours**, and the instruments to do it are committed and working.

**Option B, the product decision.** Remove the choice and always take RemoveAll. The measured-
clean path becomes the only path and the defect becomes unreachable. That is the operator's
call, not mine — it trades a user's data-retention option for a shipping date.

**INFERRED, and labelled as such:** I judge Option A low-risk because the fix for `#287` is
already written correctly two lines further down the same file, and `#285` is a list addition.
That is an argument about effort, not a measurement, and it is not part of the verdict.

### `#261`, as an accepted written condition of shipping

**Not measured this session.** No `#261` work was in scope and none was done. The numbers below
are the previous session's, restated so a release-notes reader has them, and labelled as prior
measurement rather than as this run's:

> With the software-sources switch reading **ON** and a freshly-resolved set, the route
> answered **2 of 6** attempts after a real reboot, and **5 of 12** before one. The user's own
> allowed site answered **9 of 12**. The panel reads `On. 28 network addresses reachable.` and
> admits no "sometimes".

In the terms a reader of the release notes would need: **when the software-sources switch is
on, fetches from GitHub and npm succeed intermittently — roughly half the time in measurement —
because the firewall holds a snapshot of addresses while those services answer from a larger
rotating pool. The switch is not lying about being on; the address list behind it is
incomplete. Turning it off still reliably blocks.**

This is pre-existing, carded, and narrowed rather than caused by v1.4.1. **I make no
recommendation for or against publishing on it.** That is the operator's call and he has it.

---

## 10. Standing traps, as they actually played out

1. **`az vm user update` never called by me.** The operator set the password once, at Card 1.
2. **One `az vm run-command` at a time** — confirmed live rather than assumed: a second invoke
   during the 440 MB stage returned
   `(Conflict) Run command extension execution is in progress.` Polled until it cleared.
3. **A single reachability attempt is a coin flip** — `FR.R6` takes six as uid 1000 and three
   as root, and reports the counts.
4. **run-command runs as SYSTEM and cannot touch WSL** — confirmed by accident when a SYSTEM
   diagnostic reported `PATH=C:\Windows\system32\config\systemprofile\.wslconfig EXISTS=no`.
   Every WSL read went through the interactive runner.
5. **No binary string scan of the installer was used** anywhere in this run.
6. `/mnt/c` was not used as a visibility test.
7. **`python` not used.** All Dispatch writes went through PowerShell to
   `POST /api/agent/update` with `x-frontier-secret`.

---

## 11. Cards

| Card | State | Why |
| --- | --- | --- |
| `#273` | **`done`** | check 10 observed on the rendered GUI, both click paths, positive control on the destination |
| `#282` | **`done`** | seed host fixed and measured, `c42274f` |
| `#284` | **NEW**, `queued` | the keep-Linux teardown terminates before it finishes; script proven correct by verbatim re-run |
| `#285` | **NEW**, `queued` | four units never disabled; still enabled after a complete second teardown; fw fails at every boot |
| `#286` | **NEW**, `queued` | teardown output discarded, success logged unconditionally — why the others shipped |
| `#287` | **NEW**, `queued` | missing `XDG_RUNTIME_DIR` → gateway survives → `deluser` exits 8 → reinstall aborts |
| `#261` | untouched | not measured this session; prior numbers restated in section 9 |
| `#277` `#278` `#280` `#281` `#283` | untouched | left alone as instructed; no new measurements to add |
| `#198` | untouched | no outbound email was authorised or sent |

Verified from the board after writing, not assumed:

```
card #273 status=done      card #282 status=done
card #284 status=queued    card #285 status=queued
card #286 status=queued    card #287 status=queued
card #261 status=todo      card #277 status=queued
card #278 status=queued    card #280 status=queued
card #281 status=queued    card #283 status=queued
card #198 status=todo
card #274 status=done      card #275 status=done      card #276 status=done
```

---

## 12. End-of-session gate

### Resource ledger

| Resource | State |
| --- | --- |
| VMs provisioned | one, `cfv-176`, `Standard_D2s_v4`, westus2, `clawfactory-win11-baseline-v2` |
| VMs now | **none, subscription-wide** |
| Orphans swept | OS disk, NIC, public IP, NSG — all deleted by explicit name, VM first then NIC |
| RDP rule | `67.164.251.99/32`, a single `/32`, never `0.0.0.0/0`; gone with the NSG |
| Blobs | 6.98 GB reclaimed; evidence blobs retained, not billable compute |
| Background tasks | none running |

```
=== EVERY RESOURCE IN THE SUBSCRIPTION, UNFILTERED ===   az exit=0
clawfactory-validation  Microsoft.Storage/storageAccounts      clawfactoryvalc467
clawfactory-validation  Microsoft.Network/virtualNetworks      bake-vmVNET
NetworkWatcherRG        Microsoft.Network/networkWatchers      NetworkWatcher_westus2
clawfactory-validation  Microsoft.Compute/images               clawfactory-win11-baseline
clawfactory-validation  Microsoft.Compute/images               clawfactory-win11-baseline-v2
clawfactory-signing     Microsoft.CodeSigning/codeSigningAccounts  clawfactory-signing

TOTAL_RESOURCES=6
virtualMachines=0  disks=0  networkInterfaces=0  publicIPAddresses=0  networkSecurityGroups=0
CFV176_REFERENCES=0  (must be 0)
```

**Nothing is billing compute.** The two baseline images remain the standing cost in that group;
deleting them forces a rebake and is the operator's call, not this job's.

### Delta security sweep

- **No product code was changed.** Every commit is validation instrumentation: two stale
  defaults, four new probes, one extracted script, one snapshot fix.
- **No security control was added, removed, weakened or re-scoped.**
- **One security-relevant property newly proven:** the install-time fatal aborts and leaves the
  machine fail-closed — uid 1000 blocked 6 of 6 with a root control at 3 of 3, nft table
  present with 4 terminal-drop lines.
- **One new persistence finding, not an exposure:** after a keep-Linux uninstall, ClawFactory's
  own root-owned brokers remain enabled and running. The firewall table is removed on both
  branches, so no rule outlives the product.
- **`/etc/clawfactory` surviving an uninstall carries both SOUL pins, the persona and the
  egress policy.** No credential: the API key lives in Windows Credential Manager and was
  measured removed (`credCount` 1 → 0).
- **No credential value entered any transcript, commit or file.** The provider key was reported
  as present with a length only, by the driver. `cmdkey` was read for target NAMES only.

### Delta bug review

- **PowerShell AST parse clean, 0 errors**, on all four new probes and both edited files.
- **Control-character escape sweep clean** (`` `n `` `` `r `` `` `t `` `` `a `` `` `b `` `` `0 ``
  `` `v `` `` `f `` outside `-split`/`-replace`) — one real hit found and fixed before running:
  a backtick-quoted `bash …` inside a double-quoted string, where `` `b `` is a backspace.
- **The snapshot ceiling guard was canaried in both directions** before being trusted.
- **A hypothesis was tested and refuted rather than assumed**, and its FAIL row was kept.
- **Every phase carries a registered positive control**; the run's one VOID phase was a
  control correctly refusing to underwrite measurements the install never reached.
- **No `TODO`, `FIXME`, `XXX` or `HACK` introduced.**
- Known residual, stated: the uninstall probe's transcript file APPENDS across modes, so a
  retrieved transcript carries every prior run. Each pass was verified by its own
  `mode=<Mode>` banner rather than by position in the file.

---

## 13. Lessons learned

**13.1 A control that stops you claiming a defect is worth more than one that confirms it.**
The first fatal-read-back run aborted 90 steps early; `FR.R2` and `FR.R3` would have reported
"named message absent" as a product failure. The searchability control voided the phase
instead. The message was absent because the code that prints it never ran.

**13.2 Where the changed code lives decides the shape of the test.** The v1.4.1 uninstall diff
sits entirely inside one branch. Testing the other branch — the one a silent uninstall takes —
would have produced a clean 16-of-16 pass while exercising none of what changed.

**13.3 "Present" is not a severity. "Live" is.** Twelve surviving unit files could have been
inert. Reading each one twice, for existence and for enablement, turned a count into six
enabled units and five active ones, which is a different finding with a different card.

**13.4 A refuted hypothesis is a result.** The stdin-consumption theory was clean, plausible,
supported by a comment in the codebase, and wrong. A rig with a known answer and a
one-line-different control killed it in ninety seconds and stopped it reaching this document
as an explanation.

**13.5 An instrument that serialises an object graph looks exactly like one that works.** A
100 MB snapshot from a 108-byte file passed every row it was asked about. The ceiling guard now
fails loudly, and it was canaried against the defect before being trusted.

**13.6 A defect can block the test for a different defect.** `clawuser` left behind by the
broken teardown made the v1.4.1 installer abort before reaching the fatal under test. Two
unrelated-looking failures, one cause.

**13.7 Name every dialog the operator will see, not just the one you care about.** My card
described the second dialog and not the first, and the operator hit the first. Clicking the
obvious answer there would have cancelled the whole measurement.

---

## 14. Commits

```
c42274f  validation: stagebox seeded a host that cannot detect its own defect
0278fa6  validation: stage switchprovider's fault-injection file structurally
32da215  validation: measure a clean uninstall by read-back, both branches
e741b05  validation: exercise the install-time fatal read-back, which has never fired
cc272c7  validation: the uninstall snapshot serialised an object graph, not a value
2c317ef  validation: diagnose the keep-Linux teardown, which stops half way
```

Explicit per-file staging throughout. No `git add -A`, no worktree, **no tag created**, no
release, no publish, no rebuild, no re-sign.
