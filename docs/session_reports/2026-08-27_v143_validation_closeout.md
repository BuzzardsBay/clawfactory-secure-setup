# CLOSE-OUT: v1.4.3 full release validation

**Status at the time of writing: IN PROGRESS.** This file is written incrementally
so that an interrupted session still leaves an honest record rather than nothing.
Sections carry their own state. Anything not yet measured says so.

---

## 0. PROMPT 15 preamble

Pasted and followed, VM clauses included. **No clause was deleted.**

The run prompt's own stop-condition on this point did not fire: it says "If the
copy you read ends before PROMPT 15, it is stale. Stop and say so." The copy at
`C:\Users\bmcki\OneDrive\Desktop\Claude Prompts\FrontierAI_CC_Prompt_Library.md`
is 925 lines and carries PROMPT 15 at line 645, with its "Notes on using
PROMPT 15" at 878. It is current, so the run proceeds.

---

## 1. The artifact, verified

| | |
| --- | --- |
| version | v1.4.3 |
| build commit | `de4da85`, `origin/main` at `38edb66` |
| Studio | unchanged at 1.3.2 |

**Derivation 1, build machine, by hand:**

```
b2cd6408e5d6fe39116c6e5c559f7de6cf86b2ac2d7a4a8e9093e399edb8c6a1 *Output/ClawFactory-Secure-Setup.exe
440609096 bytes
```

**Derivation 2, build machine, through the driver's own preflight** (which also
runs the Authenticode check first, per the standing rule that a post-expiry
signature check comes before anything else):

```
[09:39:36]   artifact verified: b2cd6408e5d6fe39116c6e5c559f7de6cf86b2ac2d7a4a8e9093e399edb8c6a1 (440609096 bytes), Authenticode Valid
```

Both agree with the values the run prompt states. **Derivation 3 is re-derived on
the box after transfer** and is recorded in section 3.

The ledger's unsigned digest for 1.4.3 is
`60f4e817f45147ba9b2d1c55b1ca43271b4eb589591735427f9ae518f29365e7`, which is a
different quantity and is not expected to match: signing embeds a countersigned
timestamp, so the signed digest differs on every run over identical input.

---

## 2. TASK 0.2: the stale-default sweep, done BEFORE provisioning

The run prompt names three expected stale defaults and then asks for something
larger: *"enumerate every pin, digest, version literal and default artifact path
in `validation/` and report which are current and which are stale. That
enumeration is the deliverable, not the three fixes."*

### 2.1 Method, and why it is not a grep

PROMPT 15: *"Where the question is enumeration rather than detection, parse the
AST instead of matching text."* So pass 1 parses every `.ps1` under `validation/`
with the PowerShell language parser and reports every `param()` default and every
assignment right-hand side (walking into hashtables at any depth) whose name or
value is pin-shaped.

**Then the instrument was canaried, because an audit regex is itself a probe.**
Six pin shapes were planted in a synthetic file, deliberately built to look like
what I was afraid of missing rather than like what I had already found:

| shape | planted as | pass 1 |
| --- | --- | --- |
| A | plain assignment, name with no pin-ish word | found |
| B | digest nested two hashtables deep | found |
| C | digest as an **array element** | **MISSED** |
| D | version literal under a non-version name | found |
| E | digest inside a **here-string body** | **MISSED** |
| F | a param default named ExpectedDigest | found |

**4 of 6.** The AST pass was not trustworthy on its own, and the two it missed
are both shapes a real pin could take. So pass 2 is a deliberately dumber and
wider **token sweep**: every string token in the file, here-string bodies
included, scanned for 64-hex content. Re-canaried: **5 of 5**, both previously
missed shapes found.

Pass 2 over the real tree found **10 distinct 64-hex literals across 13 sites**
and surfaced exactly one literal pass 1 had not: an all-zeros digest at
`interim-v120-phase3.ps1:204`, `phase3b.ps1:149` and `phase6.ps1:395`. It is not
a pin. It is a deliberately wrong hash passed to `approve` as a negative control,
and the classification "not a pin" is correct.

Both passes live in the session scratchpad and are not committed: they are
throwaway instruments, and committing them would imply a maintenance promise this
job did not make.

### 2.2 The enumeration, classified

**Digest and byte-count pins**

| Site | Name | Verdict |
| --- | --- | --- |
| `interim-v140-relgate-box.ps1:54,55` | Sha256, ExpectBytes | **WAS STALE** (90c673dd... / 440602224, a v1.4.0-era artifact). **FIXED** to b2cd6408... / 440609096 |
| `interim-v120-phase1.ps1:65` | PIN.soul | **CURRENT.** Hashed `resources/safety-rules.md`; equals `e70212603f2f91e6abf6db576c9535b1aaad60506e2fb075c199f18160db7941` |
| `interim-v120-phase1.ps1:66` | PIN.persona | **CURRENT.** Hashed `resources/persona.md`; equals `0557d07004d4d067d8cd9e7cee7b2a3a783e0ac8ff4c492c0c152d7e35ff63a0` |
| `interim-v120-phase1.ps1:67` | PIN.workspaceSoul | **CURRENT.** Composed from safety-rules.md plus persona.md, both verified unchanged above |
| `interim-v120-phase1.ps1:68` | PIN.rootfs | **DEAD LITERAL.** See 2.3 |
| `interim-v120-phase1.ps1:95` | PIN.studioAsar | **CURRENT.** See 2.4 |
| `interim-v140-stagecards.ps1:132` | pinned | **WAS STALE at Studio 1.3.1** (5c4ffbf4...). **FIXED** to a64a118f... Not named by the prompt; found by enumerating |
| `interim-v120-validate.ps1:180,181` | Sha256, ExpectBytes | **STALE, DELIBERATELY LEFT.** See 2.5 |
| `validation/diag/g4-probe.ps1:76,77` | Sha256, ExpectBytes | **STALE at 1.3.3**, out of scope: a Guard 4 diagnostic, not a matrix instrument |
| `job3-validate.ps1:65,66` | CombinedBlob, CombinedSha256 | **STALE at v1.1.0**, out of scope: the archived JOB 3 combined-installer validator |

**Version literals**

| Site | Verdict |
| --- | --- |
| `interim-v120-phase1.ps1:97` PIN.version | **WAS STALE at 1.4.1.** **FIXED** to 1.4.3. The prompt guessed "presumably 1.4.2 or older"; it was two releases behind, not one |
| `MANUAL_CHECKS_studio.md` checks 6b, 6f, 6g, Studio 1.3.2 | **CURRENT**, confirmed rather than assumed, as the prompt asked |
| `MANUAL_CHECKS_studio.md` check 6f, installer version 1.4.1 | **WAS STALE.** **FIXED** to 1.4.3. See 2.6 |

**Default artifact paths.** Every one resolves to
`Output\ClawFactory-Secure-Setup.exe` on the build machine or
`C:\cfv\combined-setup.exe` on the box. All **CURRENT**. None names a versioned
filename except the archived JOB 3 validator, which names
`ClawFactory-Secure-Setup-v1.1.0.exe`.

### 2.3 PIN.rootfs is assigned and never compared

`interim-v120-phase1.ps1:68` holds a 64-hex rootfs digest that reads as
load-bearing. It is not. The only two places the identifier appears afterwards
are line 601, which records `PIN.rootfs` as **INFO** from the distro's
`OS_RELEASE` string, and line 605, which names it in a VOID list. The file says
why, honestly: the tarball lands in `{tmp}` and is deleted after install, so its
hash cannot be re-derived post-install, and the weaker claim is recorded rather
than dressed up as a hash match.

**Not stale, because nothing reads it, and it cannot go stale for the same
reason.** Reported because a literal that looks like a pin and is not one is the
same reading hazard as a stale pin, and the enumeration is not honest without it.
Left alone: deleting it is a change to an instrument this run is about to trust,
which is the wrong order.

### 2.4 The two Studio pins are two different subjects, and both are current

The run prompt says Studio is unchanged at 1.3.2 with pin ac59375..., and the
harness pins a64a118f... These are not in conflict. They are different files.

- `ac5937516e7edbb5aac00433bfa6e5074449cbc28b132883099391639e1e7dca` is the
  **Studio installer** that `scripts/build_release.ps1:329` gates the build on.
  Verified directly: `resources/ClawFactory-Studio-Setup-1.3.2.exe` hashes to
  exactly that.
- `a64a118f7ae748059b482589d2c124d082cc42dbf9d3239ba615079982d2a49e` is the
  **installed app.asar** that lands in the customer profile, which is what a
  post-install probe can actually reach.

The installer is byte-identical to the pin the build enforces, and the NSIS
payload is a single lossless 7z archive, so the installed asar is unchanged too.

### 2.5 One stale pin is deliberately NOT fixed, and the reason is the point

`interim-v120-validate.ps1` still defaults to 257f30ff... / 440613512. That
driver is **forbidden by PROMPT 15**: it arms a one-shot auto-logon, and to do so
it resets the admin account with `az vm user update`. The header of
`interim-v140-relgate-box.ps1` records what that cost the last time it ran, that
one forbidden call created the need for another and the operator's credential
stopped working, and records that fixing the driver is carded separately.

A stale digest in a driver nobody should run is **a brake, not a hazard**. Its
preflight throws a hash mismatch and stops before it provisions anything.
Refreshing the digest would remove the brake and make a forbidden instrument look
blessed. It stays stale on purpose, and this paragraph is the record of that
decision rather than an oversight.

### 2.6 Two corrections to the run prompt

1. **The prompt's third expected item was right but incomplete.** It says the
   by-hand checklist quotes Studio version strings, that Studio is unchanged at
   1.3.2, and that those stay as they are. Confirmed: they are 1.3.2 and correct.
   What it did not anticipate is that the same checklist also quotes the
   **installer's** version, at check 6f, to tell the operator the two numbers are
   deliberately different, and that one said 1.4.1. A human reads that line
   mid-check, so a wrong value there invites a wrong FAIL.
2. **A fourth stale default exists that the prompt did not name**, and it is the
   one that would have cost something. `interim-v140-stagecards.ps1` pinned the
   installed Studio app.asar to the **1.3.1** digest while
   `interim-v120-phase1.ps1` pinned the 1.3.2 digest for the same subject. Two
   files, one subject, two values, so any run executing both was guaranteed to
   report one of them wrong. `SC.3` would have reported **FAIL on a correct
   install**.

### 2.7 Commits

```
0943842  validation: repin the release-gate driver and phase 1 to the v1.4.3 artifact
ea65c69  validation: repin the Studio app.asar in stagecards, which still pinned 1.3.1
fdb813c  validation: correct the installer version quoted in the by-hand checklist
```

---

## 3. TASK 0.3: the starting estate

Unfiltered, and reported as the type list rather than as a grep for a VM name:

```
=== az resource list -g clawfactory-validation, UNFILTERED (types) ===
Microsoft.Storage/storageAccounts
Microsoft.Network/virtualNetworks
Microsoft.Compute/images
Microsoft.Compute/images
```

Four resources: the storage account `clawfactoryvalc467`, the VNET `bake-vmVNET`,
and the two baseline images. **That is exactly the expected residual and nothing
else.** No preserved FAIL VMs existed, so the delete step had no subjects, and no
OS disk, NIC, public IP or NSG was present to sweep.

A note on the instrument. The per-type counts were first attempted with a
`length([])` query and every one of them failed with "-o was unexpected at this
time" and exit 255. That is the standing az.cmd trap: `az` on Windows is a batch
wrapper and cmd.exe re-parses the parentheses. The paren-free query above is what
produced the result, and the failed calls are recorded rather than hidden because
**an errored az command's empty output is not evidence**, and four unchecked
failures would have read as "nothing found".

---

## 4. TASK 0.1: the plan, and an honest statement of its size

*(Recorded before provisioning. Box outcomes are appended below as they happen.)*

**Boxes: 4. Estimated 11 to 15 hours of wall clock and about 12 operator touches.
This does not fit in one unattended session, and the run prompt asks to be told
that before provisioning rather than half way through, so it is said here.**

Money is not the constraint. Four Standard_D2s_v4 boxes at roughly ten cents an
hour, plus their OS disks, is a few dollars for the whole run. Operator
availability is the constraint: nothing past the stage happens without a human in
an RDP session, because this driver deliberately arms no auto-logon.

| Box | Install variant | Items |
| --- | --- | --- |
| **A** `cfv-178` | normal, `-Provider claude` | Matrix rows 1, 3, 5, 6, 7, 8, 9, 10 (reboot pass), 11 (the seven by-hand panel checks), 12, 13, 14. Then TASK 4: 14.8 bundled bytes, 14.9 orchestrator-prompt in the distro, 14.10 the keepalive task, 14.11 the four Windows-side scripts, 14.6 the launcher with the gateway down. **Then TASK 3, the RemoveAll branch, 16 rows, last** |
| **B** | `-Provider later` | Matrix row 4 |
| **C** | licence host blocked, prior artifact as the control | Matrix row 2 |
| **D** | normal | TASK 2 in full: install, keep-Linux uninstall through the real dialog, read-back against a held before-state, reinstall that completes, the teardown log, the fault-injected negative half, and the next-boot check. TASK 5.1, the rendered dialog, rides here |

**Why not fewer.** Rows 2 and 4 are install-time variants: each needs its own
install invocation, and the last three runs kept them on separate boxes for that
reason. TASK 2 needs a pristine install whose uninstall is the subject; running
it on a box that has already been provider-switched, rebooted and probed would
confound the read-back that is the entire point of it.

**Why not more.** TASK 3 rides box A rather than taking a fifth box. Box A is a
normal complete install and RemoveAll is the last thing that can be done to it,
so it costs nothing and saves an operator login.

**Rows 5 to 7 need `-ExtraFiles validation\sp-prefix-fw.sh`.** v1.4.3 made that
staging structural; the run confirms it stages rather than trusting it.

**`SP.8` is expected to FAIL.** It is the documented address-scoping residual,
not a regression, and it is not adjusted, retired or inverted.

### 4.1 The first attempt at box A was lost, and to my own defect

`cfv-177` was provisioned and then abandoned. The cause was not the driver and
not the product: I invoked the harness as `& .\driver.ps1 2>&1 | Tee-Object`.
The driver runs under `$ErrorActionPreference = 'Stop'`, and in PowerShell 5.1
redirecting a native command's stderr wraps each line in an ErrorRecord, so
`az vm create`'s entirely benign

```
WARNING: The default value of '--size' will be changed to 'Standard_D2s_v5' from 'Standard_DS1_v2' in a future release.
```

became a terminating error and killed the script one line after the VM was
created. This is the standing "never redirect a harness under EAP=Stop" trap, and
I walked into it.

**The VM was real.** `az vm list` across the whole subscription showed `cfv-177`
at `provisioningState=Succeeded`, so this was a wrapper failure, not a
provisioning failure, and the box existed with no RDP rule, nothing staged and no
`wrapper.cmd`.

It was swept rather than hand-completed. Hand-finishing the remaining steps would
have replaced a tested instrument with bespoke ones inside the run whose results
this job has to trust. Deleted by explicit name, NIC before the public IP and the
NSG, and then **re-read** rather than believed:

```
vm delete exit=0
nic delete exit=0
pip delete exit=0
nsg delete exit=0
disk delete exit=0
=== RE-READ, unfiltered ===
clawfactoryvalc467              Microsoft.Storage/storageAccounts
bake-vmVNET                     Microsoft.Network/virtualNetworks
clawfactory-win11-baseline      Microsoft.Compute/images
clawfactory-win11-baseline-v2   Microsoft.Compute/images
```

Back to exactly the four expected residuals. Box A was then re-provisioned as
`cfv-178` on a fresh name, with the redirect removed.

### 4.2 Box A staged. Derivation 3, on the box.

```
[09:49:31]   uploaded combined-cfv-178.exe (440609096 bytes, confirmed at the service)
[10:01:53] Staged, digest re-verified ON THE BOX. OK staged; artifact=b2cd6408e5d6fe39116c6e5c559f7de6cf86b2ac2d7a4a8e9093e399edb8c6a1 size=440609096
[10:02:25]   WROTE wrapper=5201 runner=112 AutoAdminLogon=
```

**All three derivations agree**: by hand on the build machine, through the driver's
preflight with the Authenticode check, and re-derived on the box after a 440 MB
transfer. The run prompt's instruction was to stop if any differed. None did.

`AutoAdminLogon=` is empty and was **asserted rather than set**. The driver arms no
auto-logon, which is what makes the two operator logins the correct price of the
PROMPT 15 credential rule rather than a defect to engineer around.

Upload to the service took 36 seconds; the download onto the box took 12 minutes, which
is `Invoke-WebRequest` buffering 440 MB in PowerShell 5.1 and is normal for this rig.

---

## 5. TASK 1 row 1 and the pins: phase 1. **PASS**

```
PASS=15 FAIL=0 VOID=0 INFO=4  (counted 19 of 19 recorded rows)
positive controls registered=2 fired=2
preconditions declared=0 met=0

PHASE VERDICT: PASS. Every positive control fired and every precondition was met.
PHASE1_PROBE_COMPLETE rc=0
```

Install exit code 0. Studio per-user installer landed in the original user profile
at exit 0, de-elevated, as designed.

Rows that settle questions TASK 0 raised:

```
PIN.version              PASS   Installed version reports 1.4.3
PIN.studio.asar          PASS   Studio pin: the INSTALLED app.asar matches the build-time digest
PIN.bundle               PASS   Bundle completeness (all 34 preflight resources shipped)
PIN.soul.indistro        PASS   Pin 2of7 SOUL as installed in distro
PIN.soul.rootpin         PASS   Root-owned /etc/clawfactory/soul.sha256 matches pin
PIN.workspaceSoul        PASS   Pin 3of7 composed workspace SOUL matches pin
PIN.rootfs               INFO   Pin 4of7 rootfs identity (distro produced by the pinned tarball)
P1.CHAN                  PASS   POSITIVE CONTROL: the file-based WSL channel discriminates
```

**PIN.version reading 1.4.3 is the evidence that the TASK 0 fix is live rather than
merely committed.** Before this morning it read 1.4.1 and would have mislabelled
every row of this run.

**PIN.studio.asar PASS settles section 2.4 by measurement.** The installed
`app.asar` equals `a64a118f...`, so repinning `interim-v140-stagecards.ps1` away
from the 1.3.1 value was correct, and `SC.3` would indeed have reported FAIL on
this correct install had it been left alone.

**PIN.rootfs recorded INFO, as section 2.3 predicted.** The dead literal is
confirmed dead by observation, not only by reading.

### 5.1 The virtualization warning, answered rather than assumed

The install log carries:

```
[WARN] Virtualization may be disabled in BIOS. WSL2 may fail to start.
```

That matters more than most warnings here. If WSL2 were genuinely unavailable the
installer falls back to WSL1, and WSL1 is a different isolation story than the one
the structural claims rest on. Measured in the interactive session, because a
per-user distro is invisible to `run-command`:

```
WHOAMI=cfv-178\clawadmin
---wsl -l -v---
  NAME      STATE           VERSION
* Ubuntu    Running         2
---wsl --status---
Default Distribution: Ubuntu
Default Version: 2
DISTROS=Ubuntu
CONTROL_FAKE_PRESENT=False
```

**WSL 2.** The warning is a detection artifact on this VM size, not a fallback.

Two controls, because an answer this convenient deserves them. `CONTROL_FAKE_PRESENT=False`
shows a distro name that cannot exist is not listed while the real one is, so the
reader discriminates. `WHOAMI` shows the job executed in the interactive session
rather than as SYSTEM, which is the only context that can see the distro at all.

---

## 6. TASK 4.1, section 14.8: the bundled bytes on the box ARE the committed bytes. **PASS**

The item that has never run anywhere, and the one that ten files would have failed
against every release up to and including v1.4.2.

### 6.1 Result

```
files compared      : 54  (of 54 tracked bundled)
DIGEST MATCH        : 54
DIGEST MISMATCH     : 0
ABSENT / NO ROW     : 0
CR != 0             : 3   (all three binary, see 6.3)
```

**Every one of the 54 tracked files the `.iss` bundles has, on the installed
machine, a SHA-256 identical to its committed blob at `de4da85`.**

### 6.2 The negative half, which is what makes the above mean anything

Three canaries, all fired:

```
CANARY_ALTERED|C:\cfv\canary\altered.md|present|78d4c36a8b5016a810b17ceda3574ddc19cacaded00099976a6bca853c6cd890|0|4278
CANARY_CR     |C:\cfv\canary\withcr.md |present|81cf0971bfc3d4e75931fb2bdecb88304a25f03a97ae6e7b1d4787afdb057f16|1|4278
CANARY_ABSENT |...\this-cannot-exist.md|absent|-|-|-
```

- **ALTERED.** A copy of `safety-rules.md` with one byte appended, read by the same
  probe body, hashes to `78d4c36a...` against the committed `e7021260...`. The
  comparison detects a one-byte change.
- **CR.** A copy with a single CR inserted reports `cr=1`. **This is the control
  that matters most.** A CR counter that always returned 0 would have passed all 54
  files and produced exactly the same clean result.
- **ABSENT.** A path that cannot exist reports `absent`, so a missing file cannot
  read as a match.

### 6.3 The three CR-bearing files are binaries, and the assertion does not apply

`logo.png` at cr=2, `lobster.ico` at cr=463, `ClawChat.exe` at cr=35509. A `0x0D`
byte in a PNG, an icon or an executable is data, not a line ending. Confirmed from
git rather than asserted:

```
i/-text w/-text attr/text=auto eol=lf   resources/ClawChat.exe
i/-text w/-text attr/text=auto eol=lf   resources/lobster.ico
i/-text w/-text attr/text=auto eol=lf   resources/logo.png
```

`-text` on both sides means git auto-detected them as binary and never normalised
them, which is what the repo-wide `text=auto` rule is for. **All three digests match
their committed blobs exactly**, which is the claim that matters. So: **CR=0 across
all 51 text files, and 54 of 54 digests match.**

### 6.4 Three instrument defects in my own generator, each caught before it reported

Recorded because all three failed in the direction that produces a full, confident,
uniform answer, which is the shape this project has been burned by repeatedly.

1. **The leaf variable never expanded**, so all 54 destination paths came out
   pointing at one nonexistent path. Would have reported 54 files missing on the box
   and read as a catastrophic product failure.
2. **The path parse emptied**, and the generator then reported **55 tracked files,
   every one carrying `e3b0c442...`, which is the SHA-256 of the empty string.** A
   uniform digest across every row is the most alarming output this check could
   produce, and it was produced by a parse bug rather than by the product.
3. **The backslash conversion ate itself**, leaving 50 of 55 files marked untracked.

The generator now carries seven assertions that must all pass before the manifest is
usable, including that no row holds the empty-string digest, that no row carries an
unexpanded variable, and that the tracked count is 54. **That 54 is independent
corroboration**: derived here by parsing the `.iss`, and matching the v1.4.3
close-out own count of 54 tracked bundled files, reached by a different route.

### 6.5 Two further findings, in the retrieval rather than the probe

**The completion sentinel arrived without the evidence.** The first version printed
its rows directly and `run-command` truncated the middle: `PROBE_148_COMPLETE` was
present and **only 25 of 54 rows were**. A reader gating on the sentinel would have
called it complete and counted 25 files as 54. The probe now writes to a file on the
box and reports counts, and the rows are retrieved in chunks.

**The transfer carries its own control.** The box reports the SHA-256 of the results
file, and the reassembled local copy must hash to the same value. It did not, on the
first attempt: 54 rows instead of 57. The cause was my retrieval filter, which
required a literal `CANARY` followed by a pipe and therefore silently dropped all
three `CANARY_ALTERED`-style rows. **The three canaries are exactly what this check
depends on, and the filter dropped precisely those.** Fixed, refetched, and the
reassembled digest now equals the digest the box computed:

```
reassembled=573f91caecaeabddc7df663ca22aa494abbeb67bbbd90f2b3933151d88433bf3
MATCH=True
```

Evidence retained **on the build machine only**, at
`validation-runs/cfv-178-148-manifest.txt` and `validation-runs/cfv-178-148-rows.txt`.
`validation-runs/` is gitignored by design, so these are not committed and a reader
of the repository alone cannot see them. The counts and the canary lines quoted
above are therefore the committed record, and they are quoted in full for that
reason rather than summarised.
