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

---

## 7. TASK 4.2, section 14.9: the orchestrator prompt reaches the distro with CR=0. **PASS**

Read inside the distro **as `clawuser`**, through the file-based WSL channel:

```
CHAN_SELFTEST_OK=True
RC=0
EXISTS=yes
BYTES=4277
CR=0
SHA=f7f8163426790c05bbec090cc7efcfd83809a81531214fd26db68c6e4d12ec43
LINES=65
PLACEHOLDER_HITS=0
OWNER=clawuser:clawuser MODE=644
CTL_CR_COUNTER=1
CTL_ABSENT=ok
WHOAMI=clawuser UID=1000
```

**The delivered file is byte-identical to the committed source.** `SHA` equals the
blob digest of `resources/orchestrator-prompt.md` at `de4da85` exactly.

**The 65-byte claim is confirmed arithmetically and by measurement.** The file is
65 lines, so a CRLF rendering is exactly 65 bytes larger: 4277 against 4342. The
box delivers 4277. A v1.4.2 build, whose working copy of this file was CRLF, would
have delivered 4342.

Four controls, because "CR=0" from a broken reader looks identical to "CR=0" from a
correct one:

- `CHAN_SELFTEST_OK=True` — the channel passes a subject that must pass and fails
  one that must fail. Without it, an absent result from a dead channel is
  indistinguishable from a finding.
- `CTL_CR_COUNTER=1` — the CR counter reports 1 on a file that genuinely holds one CR.
- `CTL_ABSENT=ok` — a sibling path that cannot exist does not read as present.
- `WHOAMI=clawuser UID=1000` — the read happened as the identity the item specifies,
  not as root and not as SYSTEM.

### 7.1 The prompt specifies a control that cannot exist, and a stronger one replaced it

The run prompt says: *"Control: assert the file is non-empty and carries the
substituted SOUL digest, so an absent or truncated file cannot read as a pass."*

**There is no substituted SOUL digest in this file, and there should not be.**
`PLACEHOLDER_HITS=0`: `orchestrator-prompt.md` contains no `{{SOUL_SHA256}}` token,
so `bootstrap.ps1`'s substitution is a no-op for it. That is deliberate. The prompt
itself says so at line 13: *"SOUL.md integrity is NOT self-enforced by this
prompt"*, and explains that a prompt computing its own hash is advisory theatre
while the real enforcement is a root-owned pin checked in code before every turn.
The digest was removed from this file when that was fixed.

So the specified control is unsatisfiable, and asserting it would have produced a
FAIL against correct behaviour. **Replaced with a strictly stronger one:** the
delivered file's full SHA-256 must equal the committed blob. "Carries a digest
somewhere" is weaker than "is exactly these 4277 bytes", and the substitute also
subsumes the non-empty and not-truncated requirements the original was reaching
for.

---

## 8. TASK 4.3, section 14.10: the keepalive runs from its LF form. **PASS**, one part deferred

```
TASK_PRESENT=True
TASK_STATE=Ready
TASK_ACTION=wscript.exe "C:\Program Files\ClawFactory\resources\wsl-keepalive.vbs" Ubuntu clawuser
TASK_LASTRESULT=0
TASK_LASTRUN=08/27/2026 16:33:38
CTL_FAKE_TASK_PRESENT=False
WSL_PROCESSES=2
WSCRIPT_PROCESSES=0
VBS_BYTES=764 VBS_CR=0
```

The scheduled task exists, is Ready, and **has actually run, at exit code 0**. The
`.vbs` on the box is `CR=0`, so this is the LF form executing rather than parsing.
`WSL_PROCESSES=2` shows a session is held. `WSCRIPT_PROCESSES=0` is expected and
documented: `wsl.exe` is reparented from `wscript`, which then exits.

Control: the same query against a task name that cannot exist finds nothing, so
`TASK_PRESENT=True` means the task rather than meaning the query answers anything.

**Deferred, not passed:** *"no console window flashes at logon"* is a by-hand
observation that only a human at a logon can make. It belongs to the reboot pass
and is carded, not claimed here.

---

## 9. TASK 4.4, section 14.11: the Windows-side scripts execute from LF. **PART A PASS, PART B FOUND A DEFECT**

CR census on the box first, so "it ran" is attributable to the LF form:

```
CR|smoke-test.ps1|bytes=20983|cr=0
CR|clawfactory-stop.ps1|bytes=2581|cr=0
CR|switch-provider.ps1|bytes=20141|cr=0
CR|clawfactory-grants.ps1|bytes=54751|cr=0
CR|launcher.ps1|bytes=11350|cr=0
```

### 9.1 Part A. **PASS**

```
SMOKE_EXIT=0
Result: 19 pass, 0 fail, 0 skip

LAUNCHER_DOTSOURCES_GRANTS=1
GRANTS_DOTSOURCE_OK=True
GRANTS_FUNCTIONS_DEFINED=43
CTL_BAD_DOTSOURCE_OK=False_control_fired
```

`smoke-test.ps1` executes and its own summary reports 19 pass, 0 fail, 0 skip,
including `Egress firewall clawfactory chain present in nft ruleset`, so the
standing check-9 false-positive rule does not apply here. `clawfactory-grants.ps1`
dot-sources the way `launcher.ps1` does it and defines 43 functions. The control
fired: a deliberately malformed file refuses to dot-source, so
`GRANTS_DOTSOURCE_OK=True` means the file is sound rather than meaning the try
block cannot fail.

**One instrument nit, stated rather than buried:** my own `[PASS]` line counter
reported `SMOKE_PASS=0` because it matched the wrong shape. The authoritative
figure above is the smoke test's own summary line, not my count.

### 9.2 Part B. **THE KILL SWITCH DOES NOT STOP ANYTHING, AND REPORTS THAT IT DID**

This is a product defect, it is a ship-blocker, and it was found by executing a
script that until now had only ever been parsed.

**What the product claims.** `SECURITY_FINDINGS.md` lists, in the **structural**
table: *"Kill switch, so you can stop everything immediately | Terminates the real
agent process | **Proven.**"* On the box, `clawfactory-stop.ps1` prints:

```
Done. The agent can no longer see your files, the gateway is stopped,
and any running agent turn is killed.
```

**What is true.** Both of its WSL lines fail with a bash syntax error, and it exits
0 anyway:

```
Stopping any running agent turn...
/bin/bash: -c: line 1: syntax error near unexpected token `('
/bin/bash: -c: line 1: `bash -lc "if pkill -u clawuser -f "[o]penclaw agent" 2>/dev/null;
then echo "(killed running agent turn(s))"; else echo "(no running agent turns)"; fi"'
Stopping OpenClaw gateway...
/bin/bash: -c: line 1: syntax error near unexpected token `('
/bin/bash: -c: line 1: `bash -lc "openclaw gateway stop 2>/dev/null || echo "(gateway not
running)""'
STOP_EXIT=0
```

Measured either side of it:

```
GATEWAY_BEFORE_STOP=up(200)
STOP_EXIT=0
GATEWAY_AFTER_STOP=up(200)
```

**Three controls decide that this is the product and not my harness.**

```
CONTROL A: wsl -u clawuser -- bash -lc "echo CONTROL_A_OK"    -> CONTROL_A_OK
CONTROL B: the shipped line, verbatim                          -> same syntax error, CONTROL_B_EXIT=2
CONTROL C: the same line with the inner double quotes removed  -> Stopped systemd service: openclaw-gateway.service
                                                                  CONTROL_C_EXIT=0
```

and after control C:

```
STATUS=down
openclaw processes owned by clawuser = 0
```

- **A** proves the invocation path works, so the failure is not how the job called it.
- **B** proves the shipped line fails on its own, so the defect is in the shipped script.
- **C** proves the gateway *can* be stopped this way and the repair is small: the
  inner double quotes inside the single-quoted `bash -lc` argument do not survive
  the pass through `wsl.exe`, which re-quotes with double quotes and terminates the
  string early.

**The cause is quoting, not line endings.** This is not a v1.4.3 regression. Both
lines are byte-identical at `89f49db` (v1.4.2) and `de4da85` (v1.4.3), and
`git log -S` puts the pattern in `d9b6d36`, the initial v1.0 release. **It has never
worked, on any release.**

**The part that does work.** The folder unmount half is pure PowerShell and ran
correctly: `Unmounted 0 workspace folder(s)`. So the honest split is that the Kill
Switch unmounts granted folders and does **not** kill the agent process or stop the
gateway, while telling the user it did all three.

### 9.3 The commit that created this replaced one inert kill with another

`d6d63f3` is where these lines took their current form. Its own comment says the
previous Docker-based kill *"NEVER matched anything ... So the kill switch claimed
to kill agents but never did. Docker is now removed; that no-op is replaced with
the truthful equivalent: kill the agent processes."*

**The truthful equivalent is also a no-op**, for an unrelated reason, and has been
since it was written. A defect of exactly the class the fix was written to remove
was reintroduced by the fix, and nothing measured it because nothing had ever
executed the script on a box. That is what section 14.11 exists for, and it found
this on its first run.

---

## 10. TASK 4.5, section 14.6: the launcher against a gateway-down box. **VOID**

Not a product result. The precondition could not be established: `14.6` requires a
box whose gateway is **down**, and the only supported way to put it down is the Kill
Switch, which does not work (9.2). The launcher therefore ran against a box whose
gateway was still up:

```
GATEWAY_BEFORE_STOP=up(200)
GATEWAY_AFTER_STOP=up(200)
LAUNCHER_EXIT=0
GATEWAY_AFTER_LAUNCH=up(200)
LAUNCHER_LOG_STILL_ABSENT
```

`LAUNCHER_EXIT=0` and a live gateway afterwards would read as a pass and would mean
nothing: the launcher's own `ALREADY_RUNNING` path produces exactly that. **A
missing precondition is never a product verdict**, so this is VOID with a named
reason rather than PASS.

It is re-runnable cheaply now that control C has shown how to put the gateway down
by hand, and it is re-run before any verdict is offered on 14.6.

**A second finding, smaller and separate.** `C:\ProgramData\ClawFactory\logs\launcher.log`
did not exist either before or after the launcher ran, so the launcher wrote no
state line on this run. Whether that is because the `ALREADY_RUNNING` branch was
taken and the log path differs from the one derived here, or because the log is
never written, is **not yet established** and is not claimed either way.

---

## 11. TASK 4.5, section 14.6, RE-RUN with its precondition established. **PASS**

The first attempt (section 10) was VOID. Re-run after putting the gateway down by
the method control C proved works:

```
BEFORE      http=down(502)  procs=0
Stopped systemd service: openclaw-gateway.service
AFTER_STOP  http=down(502)  procs=0
PRECONDITION_MET=True  (http=down(502) AND procs=0, both agree)
LAUNCHER_EXIT=0
LOG_USED=C:\ProgramData\ClawFactory\launcher.log
--- new log lines ---
[2026-08-27 17:12:02] [STARTED]
```

and the started gateway is genuinely healthy, not merely spawned:

```
poll 1  http=200  procs=1
```

**`[STARTED]`, not `[ALREADY_RUNNING]`, is the whole result.** That is precisely
the v1.4.2 change: on a box whose gateway is down the launcher starts it rather
than silently doing nothing.

**The launcher's own log corroborates that the earlier VOID was the right call**,
because it holds both runs:

```
[2026-08-27 17:03:36] [ALREADY_RUNNING]     <- the VOID attempt
[2026-08-27 17:12:02] [STARTED]             <- this one
```

The first run took the `ALREADY_RUNNING` path, exactly as predicted, and would
have scored a PASS indistinguishable from this one while proving nothing.

### 11.1 Two corrections to my own instrument

**The "launcher log is absent" note in section 10 was my path bug, not a product
finding.** The log lives at `C:\ProgramData\ClawFactory\launcher.log`. Section 10
looked under a `logs\` subdirectory that does not exist and I recorded the result
as "not yet established" rather than as a finding, which is the only reason it did
not become one.

**The gateway reader was wrong and the precondition gate caught it.** The first
re-run reported `http=up(502)` with `procs=0` and refused to measure. Port 8787 is
the **root-owned gating proxy**, which answers even when the real gateway behind it
is down, returning 502. Treating any HTTP response as "up" made a dead gateway look
alive. Corrected so only a 2xx counts, and the gate now requires **two independent
readers to agree**, the HTTP status and a process count taken inside the distro.

The gate refusing to produce a verdict on a disagreement is the harness working.
Had it not been a gate, this would have been a VOID reported as a PASS.

---

## 12. TASK 4.4 concluded: `switch-provider.ps1` is BROKEN FOR EVERY PROVIDER

The fourth script of section 14.11, and the second ship-blocker.

```
SWITCHPROV_EXIT=1
C:\Program Files\ClawFactory\resources\switch-provider.ps1 : The variable '$baseHosts'
cannot be retrieved because it has not been set.
    + FullyQualifiedErrorId : VariableIsUndefined,switch-provider.ps1
```

### 12.1 The mechanism

`switch-provider.ps1` sets `Set-StrictMode -Version 3.0` at line 24. At line 168 it
builds its firewall payload as an **expandable** here-string, `$fwScript = @"`.
Every bash variable inside is correctly escaped as backtick-dollar. **Four
occurrences of `$baseHosts` are not**, at lines 182, 185, 194 and 235, and all four
are inside *comments*:

```
# hardcoded 16-host mirror of setup.ps1's $baseHosts, and seven of those hosts
# #245 moved them out of $baseHosts into @toolchain_ipv4 so the user's toggle
# own $baseHosts to /etc/clawfactory/base-hosts.seed (root:root 0644) and this
#   construction: these are setup.ps1's $baseHosts and nothing else. If you are
```

PowerShell expands them when the here-string is evaluated, the variable does not
exist, and StrictMode turns that into a terminating error. **The script dies while
building its firewall payload, before it applies anything.**

This is not provider-specific. The here-string is built on the path every provider
takes, so **the Start Menu "Switch AI Provider" item cannot work at all.**

### 12.2 It was introduced by the commit that fixed the Guard 3 defeat

`git log -S` puts all four occurrences in **`3818bc0`, 2026-08-19,
"fix(egress): switch-provider no longer re-seeds the toolchain hosts it cannot
revoke"**.

That commit fixed a real and serious defect: the provider switch used to re-seed
seven toolchain hostnames into the set nothing can revoke, silently defeating the
user's toolchain toggle while the panel still reported it as off. The fix is
correct, and it added a fail-closed guard that refuses to write any toolchain host
into the allowlist.

**The explanatory comments the fix added are what broke the script.** A defect was
replaced by a worse one, in the same file, in the same commit, and nothing noticed.

### 12.3 Why no previous run caught it, which is the transferable part

`validation/interim-v135-switchprovider.ps1` does not execute
`switch-provider.ps1`. It extracts the **firewall block** as rendered bash and runs
that inside the distro as root; `validation/sp-prefix-fw.sh` is by its own header
*"the firewall block of resources/switch-provider.ps1 as it stood at commit
9710c5a, rendered"*.

So the suite tests the **payload** and never the **PowerShell wrapper that builds
the payload**. A defect in the wrapper's string interpolation is invisible to it by
construction, and both ship-blockers found today live in exactly that blind spot.

**This is what section 14.11 was written to close**, and on its first execution it
found two.

### 12.4 The failure is fail-safe, verified rather than reasoned

The script threw while building the payload, so nothing should have been applied.
Checked instead of assumed:

```
TABLE=present
ALLOWED_V4=37
TOOLCHAIN_V4=28
ALLOWED_FILE_LINES=46
SEED_HOSTS=9
CTL=ok_fake_set_not_found
```

The egress firewall is intact, the toolchain addresses are still in their own
separate set rather than in the unrevocable one, and the base seed still holds the
documented nine hosts. The control fired: a set that cannot exist is not found, so
these counts mean something.

**So `switch-provider.ps1` fails closed.** It does not damage the firewall; it
simply cannot do its job.

### 12.5 A third, smaller finding in the same script

```
bash: line 1: ollama: command not found
  [x] Ollama running with model llama3.1:8b
```

Line 155 is an unconditional `Write-Host`. It reports the provider as running
immediately after the shell reported the binary missing. Same class as the Kill
Switch: **a success line that is printed rather than earned.**

This one is confined to the Ollama path and is materially less serious than the
other two, because Ollama could not install on this box anyway. It is recorded
because it is the same defect class and a fixer should sweep for it rather than
patch one instance.

### 12.6 Scope of the quoting class, enumerated and canaried

The Kill Switch defect is a class, so the class was swept rather than the instance
patched. Across 39 WSL invocation sites in the shipped `.ps1` files, exactly
**two** pass an inline command containing double quotes inside a single-quoted
`bash -lc` argument, and both are the two Kill Switch lines. A third grep hit in
`setup.ps1` is inside a diagnostic *message string* shown to the user, not an
executed command.

The sweep was canaried before being trusted: a synthetic instance planted in a copy
of `switch-provider.ps1` was found, and the real `switch-provider.ps1` reports zero.
So "only two sites" is a measurement, not an absence of results.

---

## 13. The blocker-2 defect class, swept across every shipped script

Because the fix should cover the class rather than the instance, and because the
discovery in 12.3 is that nothing has ever executed these wrappers, the whole
shipped surface was swept for the same shape: **an undefined variable interpolated
inside an expandable string, in a file that sets StrictMode.**

Parsed rather than grepped, because a regex cannot distinguish an escaped
backtick-dollar from a real interpolation, nor a variable assigned elsewhere from
one never assigned at all.

**Canaried before it was trusted**, against the known defect:

```
File                Line Var        Strict
switch-provider.ps1  182 $baseHosts   True
switch-provider.ps1  185 $baseHosts   True
switch-provider.ps1  194 $baseHosts   True
switch-provider.ps1  235 $baseHosts   True
TOTAL = 4
```

Exactly the four sites found by hand, at the same line numbers. The instrument
detects a real instance.

**Swept across all 10 shipped `.ps1` files** (the eight in `resources\`, plus
`setup.ps1` and `smoke-test.ps1`): **TOTAL = 4**, the same four.

**The class is confined to `switch-provider.ps1`.** No other shipped script
carries it. That bounds the second blocker to one file and four comment lines.

---

## 14. TASK 8: FITNESS TO PUBLISH

Written fresh. Every claim carries verbatim evidence. Anything argued rather than
measured is labelled INFERRED in the sentence that makes it.

### 14.1 What is proven, and would survive an audit

**The artifact under test is the one that was built.** Four independent
derivations agree, and Authenticode is Valid:

```
b2cd6408e5d6fe39116c6e5c559f7de6cf86b2ac2d7a4a8e9093e399edb8c6a1  (build machine, by hand)
[09:39:36] artifact verified: b2cd6408...b8c6a1 (440609096 bytes), Authenticode Valid
[10:01:53] Staged, digest re-verified ON THE BOX. OK staged; artifact=b2cd6408...b8c6a1 size=440609096
[16:18:21] On-VM artifact sha256: b2cd6408e5d6fe39116c6e5c559f7de6cf86b2ac2d7a4a8e9093e399edb8c6a1
```

**A clean install completes, and every pin holds.**

```
PASS=15 FAIL=0 VOID=0 INFO=4  (counted 19 of 19 recorded rows)
positive controls registered=2 fired=2
PHASE VERDICT: PASS. Every positive control fired and every precondition was met.
```

**Section 14.8: the bundled bytes on the installed box are the committed bytes.**
This is the headline of v1.4.3 and it is proven, with the negative half that makes
it mean anything:

```
files compared      : 54  (of 54 tracked bundled)
DIGEST MATCH        : 54
DIGEST MISMATCH     : 0
CANARY_ALTERED  -> 78d4c36a...  (differs from the committed e7021260..., one byte appended)
CANARY_CR       -> cr=1         (the CR counter can count)
CANARY_ABSENT   -> absent       (a missing file cannot read as a match)
```

**Section 14.9: the orchestrator prompt reaches the distro with CR=0**, delivered
byte-identical to its committed blob, read as the right identity:

```
BYTES=4277  CR=0  LINES=65
SHA=f7f8163426790c05bbec090cc7efcfd83809a81531214fd26db68c6e4d12ec43
WHOAMI=clawuser UID=1000
CTL_CR_COUNTER=1   CTL_ABSENT=ok   CHAN_SELFTEST_OK=True
```

**Section 14.10: the keepalive runs from its LF form.**

```
TASK_PRESENT=True  TASK_STATE=Ready  TASK_LASTRESULT=0
VBS_BYTES=764 VBS_CR=0   WSL_PROCESSES=2   CTL_FAKE_TASK_PRESENT=False
```

**Section 14.6: the launcher starts a down gateway**, with the precondition
genuinely established and two readers agreeing:

```
PRECONDITION_MET=True  (http=down(502) AND procs=0, both agree)
[2026-08-27 17:12:02] [STARTED]
poll 1  http=200  procs=1
```

**WSL 2, not a WSL1 fallback**, despite the install log's BIOS warning:

```
* Ubuntu    Running         2
CONTROL_FAKE_PRESENT=False
```

**Two of the four scripts in 14.11 execute correctly from their LF form:**

```
SMOKE_EXIT=0 / Result: 19 pass, 0 fail, 0 skip
GRANTS_DOTSOURCE_OK=True  GRANTS_FUNCTIONS_DEFINED=43
CTL_BAD_DOTSOURCE_OK=False_control_fired
```

**The egress firewall is intact and correctly partitioned:**

```
TABLE=present  ALLOWED_V4=37  TOOLCHAIN_V4=28  SEED_HOSTS=9
CTL=ok_fake_set_not_found
```

### 14.2 What is VOID or unmeasured, and why

- **Matrix rows 2, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14: NOT RUN.** The run was
  stopped when the second ship-blocker was found. Rows 2 and 4 need their own
  boxes; 10 and 11 need the operator; the rest were planned for this box and were
  not reached.
- **TASK 2, the keep-Linux uninstall headline: NOT RUN.** This is the single item
  that would have turned the v1.4.1 NO into a yes, and it was planned for a
  separate box that was never provisioned.
- **TASK 3, the RemoveAll branch: NOT RUN.**
- **Section 14.10's "no console window flashes at logon": DEFERRED.** It is a
  by-hand observation that only a human at a logon can make, and it belongs to the
  reboot pass, which did not happen.
- **`#198`: VOID BY DESIGN**, as the run prompt directs. Zero outbound email was
  authorised, `phase3b` was not run, and no send was attempted. It is recorded as a
  receiving-provider outcome rather than a ClawFactory behaviour: the delivery path
  is already proven end to end, a real message was accepted with a `250 OK`, and the
  failure is inbound filtering at the recipient. No spend was made re-testing it.
- **The first attempt at 14.6 was VOID** and was re-run rather than reported. Its
  named reason is in section 10 and the launcher's own log corroborates it.

### 14.3 What stands in the way

**Two ship-blockers, both found by executing scripts that had only ever been
parsed, and both in the same blind spot.**

**BLOCKER 1. The Kill Switch does not kill anything, and reports that it did.**

```
GATEWAY_BEFORE_STOP=up(200)
/bin/bash: -c: line 1: syntax error near unexpected token `('
/bin/bash: -c: line 1: `bash -lc "openclaw gateway stop 2>/dev/null || echo "(gateway not running)""'
STOP_EXIT=0
GATEWAY_AFTER_STOP=up(200)
```

while printing to the user:

```
Done. The agent can no longer see your files, the gateway is stopped,
and any running agent turn is killed.
```

Both of its WSL lines fail. Three controls place the defect in the shipped script:
a plain command through the same path works (`CONTROL_A_OK`), the shipped line
fails verbatim standalone (`CONTROL_B_EXIT=2`), and the same line with the inner
double quotes removed works (`Stopped systemd service: openclaw-gateway.service`,
`CONTROL_C_EXIT=0`, leaving `STATUS=down` and zero openclaw processes).

Not a v1.4.3 regression. Both lines are byte-identical at `89f49db` and `de4da85`,
and `git log -S` places the pattern in `d9b6d36`, the initial v1.0 release.

**BLOCKER 2. `switch-provider.ps1` fails for every provider.**

```
SWITCHPROV_EXIT=1
switch-provider.ps1 : The variable '$baseHosts' cannot be retrieved because it has not been set.
    + FullyQualifiedErrorId : VariableIsUndefined,switch-provider.ps1
```

Four unescaped `$baseHosts`, all inside comments, inside the expandable here-string
that builds the firewall payload, in a file that sets `Set-StrictMode -Version 3.0`.
Bounded by an AST sweep to exactly those four sites across all 10 shipped scripts.
Introduced by `3818bc0`, the commit that fixed the Guard 3 toolchain re-seed.

It fails closed, verified rather than reasoned: `TABLE=present ALLOWED_V4=37
TOOLCHAIN_V4=28 SEED_HOSTS=9`.

**BLOCKER 3, documentation.** `SECURITY_FINDINGS.md` lists, in the **structural**
table, *"Kill switch, so you can stop everything immediately | Terminates the real
agent process | Proven."* That claim is false as written, and the structural table
is the one the marketing claims are allowed to match.

**Minor, same class.** `switch-provider.ps1:155` prints `[x] Ollama running with
model ...` unconditionally, immediately after `bash: line 1: ollama: command not
found`.

### 14.4 The two previously unvalidated releases are NOT fully covered

Asked explicitly by the run prompt, and the answer is no.

v1.4.2's changes live almost entirely in the keep-Linux uninstall branch, and
**none of that branch was measured**: TASK 2 and TASK 3 were not run. Of v1.4.2's
six change areas, only the launcher change (14.6) was measured. Of v1.4.3's
additions, 14.8, 14.9, 14.10 and half of 14.11 were measured and passed, 14.12
needed no on-box check by its own terms, and 14.11 is where both blockers surfaced.

So: **v1.4.3's own line-ending work is proven. v1.4.2 remains substantially
unmeasured.**

### 14.5 `#261`, as an accepted written condition of shipping

**Not measured this session.** No `#261` work was in scope and none was done. The
figures below are the previous session's, restated so a release-notes reader has
them, and labelled as prior measurement rather than as this run's:

> With the software-sources switch reading **ON** and a freshly-resolved set, the
> route answered **2 of 6** attempts after a real reboot, and **5 of 12** before
> one. The user's own allowed site answered **9 of 12**. The panel reads
> `On. 28 network addresses reachable.` and admits no "sometimes".

In the terms a reader of the release notes needs: **with the software-sources
switch on, fetches from GitHub and npm succeed intermittently, roughly half the
time in measurement, because the firewall holds a snapshot of addresses while those
services answer from a larger rotating pool. The switch is not lying about being
on. The address list behind it is incomplete. Turning it off still reliably
blocks.**

**I make no recommendation for or against publishing on it.** That is the
operator's call and he has it.

### 14.6 Verdict

# NO.

One sentence, and it contains no argued premise: **the Kill Switch, which
`SECURITY_FINDINGS.md` lists as a proven structural guarantee, does not stop the
gateway or kill the agent process, and tells the user that it did.**

Three qualifications, so the verdict is not read as broader than it is.

1. **v1.4.3's own work is sound.** The line-ending re-materialisation, the build
   gate it added, and the four new checks it created are proven where they were
   measurable. Nothing found today is a v1.4.3 regression. Both blockers predate
   it, one by a week and one by every release ever shipped.
2. **Nothing found today is a containment escape.** The firewall is intact and
   correctly partitioned, the pins hold, file isolation was not implicated, and
   both failures fail closed. The Kill Switch's folder-unmount half works. What is
   broken is the ability to *stop* the agent on demand, and a provider switch.
3. **The install path is unaffected.** A clean install completes at 15 PASS / 0
   FAIL with both controls firing.

### 14.7 What would turn this into a yes

**The fixes are small and bounded.** Stated as scope, not as a promise, and the
effort judgement below is INFERRED:

- **Blocker 1:** two lines, `resources/clawfactory-stop.ps1:27` and `:30`. Control
  C already demonstrated the working shape on the box.
- **Blocker 2:** four comment lines, `resources/switch-provider.ps1:182,185,194,235`.
  Escape the dollars or reword the comments.
- **Blocker 3:** move the kill switch out of the structural table, or restate what
  it actually guarantees, in `SECURITY_FINDINGS.md` and anywhere that table is
  mirrored.
- **Minor:** make `switch-provider.ps1:155` conditional.

**INFERRED, and labelled as such:** I judge these low-risk because each is a
localised edit with a demonstrated correct form, and because the AST sweep bounds
blocker 2 to one file. That is an argument about effort, not a measurement, and it
is not part of the verdict.

**Then the measurement that is actually owed**, and it is not small: a rebuild
changes the binary, and **prior measurements do not transfer across a rebuild** —
which is the premise this entire job was written on. So a v1.4.4 needs the full
matrix, TASK 2 and TASK 3, not just a re-run of what broke.

**The one thing I would add to that run:** section 14.11 exists because an AST
parse is not an execution, and on its first outing it found two ship-blockers in
scripts the suite had only ever parsed. **Every shipped PowerShell entry point
should be executed on the box, not parsed** — including `post-install.ps1`,
`rename-agent.ps1` and `bootstrap.ps1`, which this run did not reach and which live
in the same blind spot.
