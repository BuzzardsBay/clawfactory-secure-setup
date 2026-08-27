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
