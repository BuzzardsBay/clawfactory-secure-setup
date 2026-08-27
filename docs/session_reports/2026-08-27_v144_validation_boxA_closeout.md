# CLOSE-OUT: v1.4.4 validation, BOX A

**Status at the time of writing: IN PROGRESS — rows 1,3,5,6,7,8,9 PASS. Rows 12-14 in flight. Rows 10-11 await the operator.**
Written incrementally so an interrupted session leaves an honest record rather
than nothing. Sections carry their own state. Anything not measured says so.

**No fitness-to-publish verdict appears in this document, by instruction.** Box A
is one of four and a verdict on partial coverage would rest on an unmeasured
premise.

---

## 0. PROMPT 15 preamble

Pasted and followed, VM clauses included. **No clause was deleted.**

The job card's stop condition did not fire. The copy at
`C:\Users\bmcki\OneDrive\Desktop\Claude Prompts\FrontierAI_CC_Prompt_Library.md`
is 925 lines and carries PROMPT 15 at line 645 with its notes at 878. It is
current, so the run proceeds.

All three required reports were read in full before anything was touched:
`2026-08-27_v144_wrapper_fixes_closeout.md` (967 lines, section 9 is the box
plan), `2026-08-27_v143_validation_closeout.md` (1199 lines) and
`2026-08-27_site_killswitch_claims_closeout.md` (579 lines).

Job card moved to `docs/cc_jobs/CC_v1_v144_Validation_BoxA_v1.md` and committed
at `191bff5`.

---

## 1. The artifact. Derivations 1 and 2 agree; derivation 3 is owed on the box

**Derivation 1, build machine.** The standing rule is that the post-expiry
Authenticode check comes first, so it did:

```
AUTHENTICODE=Valid
SIGNER=CN=Bret Mckinney, O=Bret Mckinney, L=West Valley City, S=ut, C=US
NOTAFTER=08/28/2026 15:23:23
SHA256=6e65560325cb6d7d3fea204ebb72876b3b113cbbfe9f2fa4f94113237e9eb4d1
BYTES=440610608
MATCH_SHA=True
MATCH_BYTES=True
```

`NotAfter` one day out is **normal** for Trusted Signing, which mints three-day
certificates daily. It is not an expiry warning and no alarm is raised on it.

**Derivation 2, blob storage, BY DOWNLOAD AND RE-HASH.** The job card is explicit
that a service property will not do. Recorded here is what the service property
said *and* what the round trip said, so the two can be compared:

```
LOCAL_SHA=6e65560325cb6d7d3fea204ebb72876b3b113cbbfe9f2fa4f94113237e9eb4d1
LOCAL_BYTES=440610608
UPLOADING combined-cfv-179.exe ...
SERVICE_PROPERTY_BYTES=440610608      <- the WEAK check, the one the driver does
DOWNLOADING back to a different path ...
ROUNDTRIP_SHA=6e65560325cb6d7d3fea204ebb72876b3b113cbbfe9f2fa4f94113237e9eb4d1
ROUNDTRIP_BYTES=440610608
DERIVATION2_MATCH=True
```

**The re-hash carries a control, because a comparison that cannot fail is not a
comparison.** One byte of the downloaded copy was flipped and re-hashed:

```
CONTROL_ONE_BYTE_FLIPPED_SHA=f480f4078f3fde631ab13ae44a49e5abf95be113d906eba343944b906e721775
CONTROL_FIRED=True
```

**Why this was done by hand rather than left to the driver.** The driver's own
staging check at `interim-v140-relgate-box.ps1:204` reads
`properties.contentLength` — the service agreeing with itself about how many
bytes it believes it stored. It cannot detect a corrupted body of the correct
length. The driver's *later* on-box check is a real SHA-256 and is derivation 3.

**Derivation 3 is owed** and is recorded in section 5 when the box exists.

| | |
| --- | --- |
| version | v1.4.4 |
| signed sha256 | `6e65560325cb6d7d3fea204ebb72876b3b113cbbfe9f2fa4f94113237e9eb4d1` |
| signed bytes | 440,610,608 |
| unsigned, as the ledger records | `548562c72d5261bc62d590df03746ea2bb52134a413e10d137b590e589fdcdea` |
| build commit | `25945d5`, stamp fix `31e2aa1` |
| Studio | unchanged at 1.3.2, installer pin `ac59375…` |

The signed digest is not reproducible across signing runs and no fresh sign was
performed here, so nothing in this run treats a differing signed digest as a
defect.

---

## 2. TASK 0.2: the stale-default sweep

The job card is explicit that **the enumeration is the deliverable and the two
named fixes are not.**

### 2.1 Method, and why it is a token sweep rather than an AST-node sweep

The v1.4.3 session proved by canary that an AST pass over `param()` defaults and
assignment right-hand sides finds only **4 of 6** planted pin shapes: it misses a
digest held as an **array element** and a digest inside a **here-string body**.
Both are shapes a real pin can take.

So this sweep tokenizes each file with the PowerShell tokenizer and scans every
`String`, `Number`, `Comment` and `CommandArgument` token. The tokenizer sees a
string regardless of where it sits in the tree, which covers both missed shapes.
**Comments are swept deliberately**: a stale value in a comment misleads a reader
exactly the way a stale value in code misleads a runner, and this project has
already shipped one defect that lived entirely in comments.

Five classes, matching the five the job card names: `DIGEST` (64 hex), `VERSION`
(dotted numeric), `BYTES` (integers of artifact scale), `HOST` (dotted DNS names
on a known TLD), `PATH` (a path-separated artifact-extension string).

```
SWEPT_FILES=58   (48 in validation\, 10 in validation\diag\)
TOTAL_HITS=920
```

The vacuity guard matters and is stated: the sweep **throws** rather than
reporting clean if it matches zero files. The v1.4.3 session's equivalent
instrument once reported `LEGACY_PROBE_FILES=0` from a bad glob, which made every
"no hits" column mean "nothing was searched".

### 2.2 The canary, planted in a shape the tree does not already contain

The rule is that a canary certifies the pattern only against the shape of the
canary, so it must look like the thing you are afraid of missing. Every digest in
the real tree sits in a plain `String` token. So the canary was planted as the
two shapes that are **absent** from the tree and were the two the AST method
missed:

```
PLANTED: a stale artifact digest and byte count inside a HERE-STRING BODY
PLANTED: a stale version literal as an ARRAY ELEMENT

CANARY_HIT: interim-v141-bootpath.ps1  394 BYTES   String 440602224
CANARY_HIT: interim-v141-bootpath.ps1  394 DIGEST  String 90c673dd1122...99aabb
CANARY_HIT: interim-v141-bootpath.ps1  398 VERSION String 1.4.0
```

**3 of 3 found.** The file was then restored **by writing back the original bytes
that were saved before planting**, not with `git checkout --`, and the restoration
was proven by hash rather than by `git status`:

```
ORIG_SHA=27850df3f374a48e81842ba32b8abd293113f7154be894820b679c76b01995da BYTES=23689
PLANTED_SHA=c206a9d1c59109d5c52151536c332ba8ad74aa9f09a25df7d5e92c20493f4cd6
RESTORED_SHA=27850df3f374a48e81842ba32b8abd293113f7154be894820b679c76b01995da BYTES=23689
git status --short -> empty
```

That method was chosen deliberately. `git checkout --` under this machine's
system-level `core.autocrlf=true` silently re-materialises a file as CRLF while
`git status`, `git diff` and `grep` all report it clean — the failure met live in
the site job earlier the same day, which corrupted 1,080 line endings invisibly.

### 2.3 The enumeration: digests

| Site | Name | Verdict |
| --- | --- | --- |
| `interim-v140-relgate-box.ps1:54,55` | Sha256, ExpectBytes | **WAS STALE** at `b2cd6408…` / 440609096, the v1.4.3 artifact. **FIXED** to `6e655603…` / 440610608 |
| `interim-v120-phase1.ps1:65` | PIN.soul | **CURRENT.** Re-derived: `resources/safety-rules.md` hashes to `e70212603f2f91e6abf6db576c9535b1aaad60506e2fb075c199f18160db7941` |
| `interim-v120-phase1.ps1:66` | PIN.persona | **CURRENT.** Re-derived: `resources/persona.md` hashes to `0557d07004d4d067d8cd9e7cee7b2a3a783e0ac8ff4c492c0c152d7e35ff63a0` |
| `interim-v120-phase1.ps1:67` | PIN.workspaceSoul | **CURRENT by construction.** Composed from the two files above, both re-derived unchanged |
| `interim-v120-phase1.ps1:68` | PIN.rootfs | **CURRENT, and still a dead literal.** Re-derived: `resources/ubuntu-rootfs.tar.gz` hashes to `1483cc5c1dce13064f774834cbffdff226559fd522a67a381a8ea77d63fb4109`, equal to the pin. Nothing compares it post-install; the file lands in `{tmp}` and is deleted. Recorded because a literal that looks load-bearing and is not is the same reading hazard as a stale one. **Left alone**, as in v1.4.3 |
| `interim-v120-phase1.ps1:95` and `interim-v140-stagecards.ps1:132` | studioAsar | **CURRENT, and the two sites agree** at `a64a118f…`. This is the INSTALLED `app.asar`, a different subject from the installer pin `ac59375…` that the build gates. Studio is unchanged, so both hold |
| `interim-v120-phase3.ps1:204`, `phase3b.ps1:149`, `phase6.ps1:395` | all-zeros | **NOT A PIN.** A deliberately wrong hash passed to `approve` as a negative control. Classification unchanged from v1.4.3 |
| `interim-v120-validate.ps1:180,181` | Sha256, ExpectBytes | **STALE, DELIBERATELY LEFT** at `257f30ff…` / 440613512. That driver is forbidden by PROMPT 15: it arms a one-shot auto-logon by resetting the admin account with `az vm user update`. A stale digest in a driver nobody may run is **a brake, not a hazard** — its preflight throws before provisioning. Refreshing it would make a forbidden instrument look blessed |
| `validation/diag/g4-probe.ps1:76,77` | Sha256, ExpectBytes | **STALE** at `5bef35dc…` / 440606872. Out of scope: a Guard 4 diagnostic, not a matrix instrument, and not run by this job |
| `job3-validate.ps1:66` | CombinedSha256 | **STALE** at `ffe86406…`, the v1.1.0 combined installer. Out of scope: the archived JOB 3 validator |

### 2.4 The enumeration: version literals

The `VERSION` class is intrinsically noisy — it matches section numbers (`5.2`,
`6.3`), IP addresses, `Set-StrictMode -Version 3.0` and PowerShell `5.1`. Stating
that plainly rather than presenting a filtered list as if it were the raw one.
The load-bearing subset:

| Site | Verdict |
| --- | --- |
| `interim-v120-phase1.ps1:97` `PIN.version` | **CURRENT at `1.4.4`.** The job card said to confirm rather than assume, and this is the confirmation: read directly from the file, not inferred from the commit that claimed to bump it |
| `ClawFactory-Secure-Setup.iss` `#define MyAppVersion` | `"1.4.4"` |
| `setup.ps1` `$InstallerVersion` | `'1.4.4'` — the two agree, which is what the build's version gate enforces |
| `interim-v144-wrappers.ps1:1,156` | `1.4.4`, current |
| `interim-v140-stagecards.ps1:138` | Studio `1.3.2`, current |
| `MANUAL_CHECKS_studio.md:254` | **WAS STALE at `1.4.3`. FIXED** to `1.4.4`. See 2.6 |
| `MANUAL_CHECKS_studio.md:5` | **WAS STALE.** Header read "Updated 2026-08-24 (second pass) for the v1.4.1 build", two releases behind. **FIXED** |
| `MANUAL_CHECKS_studio.md` checks 6b, 6f, 6g, Studio `1.3.2` | **CURRENT**, confirmed against the built bundle rather than assumed. See 2.6 |
| `MANUAL_CHECKS_studio.md:11,226,285` | `v1.4.0` / `v1.4.1` in **historical narrative** ("Until v1.4.1 the lobster was a bare span"). Correct as history, **left** |

### 2.5 The enumeration: seed hosts, byte counts, artifact paths

**Seed hosts.** 30 distinct DNS names across `validation\`. No stale entry found:
the product hosts (`api.anthropic.com`, `openclaw.ai`, `clawhub.ai`,
`api.clawhub.ai`, `api.clawfactory.app`, `api.github.com`, `github.com`,
`raw.githubusercontent.com`, `objects.githubusercontent.com`,
`codeload.github.com`, `registry.npmjs.org`) match the documented base and
toolchain sets; the remainder are deliberate probe targets (`example.com/.org/.net`,
`www.iana.org`, `neverssl.com`, `api.ipify.org`, `wikipedia.org`), competitor
provider endpoints used as controls (`api.openai.com`, `auth.openai.com`,
`api.x.ai`), SMTP targets (`smtp.gmail.com`, `smtp.office365.com`,
`smtp.mail.yahoo.com`, `outlook.office.com`) and infrastructure
(`management.azure.com`, `ubuntu.com`, `docs.python.org`).

**Byte counts.** Seven hits. Five are the digest/byte pairs already classified
above. Two are **false positives of the instrument and are named as such**:
`615079982` and `944583470` are decimal-looking substrings *inside* a 64-hex
digest on the same line. They are reported rather than filtered, because a filter
that silently drops them is a filter that could silently drop a real one.

**Default artifact paths.** One distinct `PATH` hit,
`/mnt/c/Users/*/AppData/Local/Programs/clawfactory-studio/resources/app.asar`.
Every driver artifact default resolves to `Output\ClawFactory-Secure-Setup.exe`
on the build machine or `C:\cfv\combined-setup.exe` on the box; none names a
versioned filename except the archived JOB 3 validator. All **CURRENT**.

### 2.5a A sixth class the job card's five did not name: stale VM-name defaults

Found while reading the dispatcher rather than by the sweep, because a VM name is
not a pin, a digest, a version, a host or an artifact path. It is a stale default
of exactly the kind the job card's preamble is about — "stale defaults have cost a
box in four consecutive runs" — so it is reported.

```
validation/interim-v120-job.ps1:31       $VmName = 'cfv-153'
validation/interim-v120-validate.ps1:33  $VmName = 'cfv-153'
validation/finish-and-park.ps1:27        $VmName = 'cfv-162'
validation/job3-validate.ps1:56          $VmName = 'cfv-152'
validation/diag/g4-probe.ps1:52          $VmName = 'cfv-165'
scripts/azure-validate.ps1:47            $VmName = 'cfv-138'
```

**All six name boxes that no longer exist**, which the section 3 estate listing
proves independently. **All six are therefore fail-safe rather than fail-dangerous**:
an `az` call against a deleted VM errors, it does not quietly measure the wrong
machine. That is the reason this is a reading hazard and not a ship-blocker.

`interim-v120-job.ps1` is the one that matters, because it is the dispatcher this
run drives every phase through. `-VmName` is passed explicitly on every invocation
in this session.

**Not fixed here, deliberately, and the reason is the same one v1.4.3 gave for
`PIN.rootfs` and the forbidden driver:** changing an instrument this run is about
to trust, mid-run, is the wrong order. Repointing them at `cfv-179` would also be
the wrong fix — it makes them stale again the moment this box is torn down. The
correct fix is to make `$VmName` mandatory, which is a behaviour change to six
instruments and belongs in its own change, carded rather than smuggled into a
validation run.

### 2.6 A finding the instrument's own scope would have missed, and the fix to both

**The sweep as first written covered `.ps1` only.** `validation\` also holds two
`.sh` files and six `.md` files, and one of the `.md` files is the by-hand
checklist an operator reads at the keyboard. Swept separately by hand:

`MANUAL_CHECKS_studio.md:254` told the operator that Studio's `1.3.2` is
deliberately not the same as the ClawFactory installer's version, **and then named
1.4.3**. That is the exact defect the v1.4.3 session found and fixed in the same
line when it read `1.4.1`. It goes stale on every release and nothing enforces it.
A human reads that sentence mid-check, so a wrong value there invites a wrong FAIL
on a correct install.

**Studio's own strings are current and were confirmed, not assumed**, as TASK 4.3
requires — against the built bundle rather than against intention:

```
resources\ClawFactory-Studio-Setup-1.3.2.exe
  sha256 ac5937516e7edbb5aac00433bfa6e5074449cbc28b132883099391639e1e7dca
ClawFactory-Secure-Setup.iss:16
  #define StudioInstaller "ClawFactory-Studio-Setup-1.3.2.exe"
```

`resources\` also holds `ClawFactory-Studio-Setup-1.3.0.exe` and `-1.3.1.exe`.
Neither is referenced by the `.iss`, so neither ships. Recorded because three
Studio installers in one directory is a reading hazard for the next person, not
because it is a defect today.

### 2.7 Commits

```
cef6cbd  validation: repin the release-gate driver to the v1.4.4 signed artifact
b11c2c5  validation: the by-hand checklist quoted the v1.4.3 installer version
```

Both files are `eol=lf` in the index and in the worktree before and after
(`git ls-files --eol`), so neither edit re-materialised line endings.

The sweep instrument itself is **not committed**. It is a throwaway, and
committing it would imply a maintenance promise this job did not make — the same
decision, for the same reason, as the v1.4.3 session.

---

## 3. TASK 0.4: the starting estate, unfiltered

```
=== az resource list -g clawfactory-validation, UNFILTERED ===
clawfactoryvalc467              Microsoft.Storage/storageAccounts
bake-vmVNET                     Microsoft.Network/virtualNetworks
clawfactory-win11-baseline      Microsoft.Compute/images
clawfactory-win11-baseline-v2   Microsoft.Compute/images
AZ_EXIT=0
```

**Exactly the expected residual and nothing else.** Widened beyond the job card's
ask to the whole subscription, because "the resource group is clean" and "nothing
is billing" are different claims:

```
=== az vm list -d, SUBSCRIPTION-WIDE ===   AZ_EXIT=0   VM_LIST_EMPTY=True
=== az disk list -g clawfactory-validation ===  DISK_EXIT=0  DISK_LIST_EMPTY=True
=== az network nic / public-ip / nsg list, subscription-wide ===  all exit 0, all empty
=== az resource list, ALL resource groups ===
clawfactory-validation  clawfactoryvalc467             Microsoft.Storage/storageAccounts
clawfactory-validation  bake-vmVNET                    Microsoft.Network/virtualNetworks
clawfactory-validation  clawfactory-win11-baseline     Microsoft.Compute/images
clawfactory-validation  clawfactory-win11-baseline-v2  Microsoft.Compute/images
NetworkWatcherRG        NetworkWatcher_westus2         Microsoft.Network/networkWatchers
clawfactory-signing     clawfactory-signing            Microsoft.CodeSigning/codeSigningAccounts
```

`cfv-178` and its four orphans are gone, as the job card predicted. The
NetworkWatcher is Azure's own auto-created resource and the signing account is the
build-time code-signing account; neither is validation estate and neither bills
compute. **Zero VMs, zero disks, zero NICs, zero public IPs, zero NSGs. Nothing is
billing compute at the start of this run.**

**One instrument note, recorded because an errored `az` command's empty output is
not evidence.** The first `az disk list` was issued subscription-wide and returned
`DISK_EXIT=2` with `ERROR: the following arguments are required: --resource-group/-g`.
That exit code was checked rather than the empty output believed; the call was
re-issued with `-g` and returned exit 0 and genuinely empty. Had the exit code not
been read, a required-argument error would have read as "no disks exist".

---

## 4. TASK 0.1: the plan, and an honest statement of its size

*(Recorded BEFORE `az vm create`, as the job card requires. Outcomes are appended
below as they happen.)*

**Box: one. `cfv-179`, Standard_D2s_v4, image `clawfactory-win11-baseline-v2`,
resource group `clawfactory-validation`, `-Provider claude`.** One box, as
instructed; boxes B, C and D are separate sessions on separate days and no second
VM is provisioned here.

### 4.1 Phase order

Fixed by TASK 1 and stated here so the close-out can be checked against it. Two
phases change box state and that is why the order is not negotiable.

| # | Phase | Carries | Why here |
| --- | --- | --- | --- |
| 1 | `interim-v120-phase1.ps1` | Matrix row 1, clean install, all seven pins | Everything else needs an install |
| 2 | providergate | Matrix row 3 | |
| 3 | switchprovider, `-ExtraFiles validation\sp-prefix-fw.sh` | Matrix rows 5, 6, 7 | v1.4.3 made the staging structural; confirm it stages rather than trusting it |
| 4 | toolchain | Matrix rows 8, 9 | |
| 5 | phases 2, 3, 5, 6 and harness self-test | Matrix rows 12, 13, 14 | |
| 6 | reboot pass, `-PostReboot` | Matrix row 10 | **Operator touch:** auto-logon is one-shot, so a human logs in and restarts the runner |
| 7 | by-hand panel checks | Matrix row 11 | **Operator touch:** ten Studio checks plus the panels, at the keyboard |
| 8 | sections 14.8, 14.9, 14.10, 14.11, 14.6 | The v1.4.3 carry-forward | 14.6 needs the gateway genuinely down, which now depends on 2.1 |
| 9 | `interim-v144-wrappers.ps1 -RunProviderSwitch` | WR.1–WR.9, and 2.1–2.5 | **Second to last.** WR.5 switches the box to ollama and would confound anything after it |
| 10 | RemoveAll uninstall branch, 16 rows | Section 14.4 | **Last of all.** It destroys the install |

`rename-agent.ps1` is an operator click inside step 7, not an unattended row: it
blocks on a modal `MessageBox` and an unattended phase would hang rather than fail.

**`SP.8` will FAIL.** It is the documented address-scoping residual. It is not
adjusted, retired or inverted.

### 4.2 Cost, stated before it is spent rather than discovered

| | |
| --- | --- |
| Wall clock, estimated | **7 to 9 hours** |
| Operator touches, estimated | **5** |
| Compute | one `Standard_D2s_v4` at roughly $0.10/hour, so **under $1** for the whole box, plus its OS disk |

The five touches, named so they can be planned for rather than discovered:

1. **RDP login at provisioning**, to set the admin password and start the runner.
   Nothing launches `wrapper.cmd`; the driver deliberately arms no auto-logon.
2. **RDP login after the reboot pass** (matrix row 10). Auto-logon is one-shot.
3. **The by-hand panel checks** (matrix row 11), ten Studio checks plus panels.
   30 to 45 minutes at the keyboard.
4. **The `rename-agent.ps1` modal click.**
5. **The RemoveAll uninstall dialog.**

### 4.3 Does box A fit in one session? Stated before provisioning, as instructed

**Not as an unattended session, and the constraint is operator availability rather
than money.** Seven to nine hours with five keyboard touches is a working day with
a human on call, not a run that can be started and collected later. The job card
asks to be told this before provisioning rather than half way through, so it is
said here.

**It does fit as a working day, and it fits as two half-days**, because the box can
be deallocated between step 7 and step 8 and restarted the next morning. That
costs nothing beyond the OS disk and adds no operator touch that is not already
planned: restarting a deallocated box requires an RDP login to restart the runner,
and touch 2 is already exactly that.

This is a decision for the operator and it is carded rather than taken. Nothing is
provisioned until it is answered, because a box provisioned into an absence is the
failure this project has already paid for once at 64 hours.

---

## 5. Box A provisioned and staged. Derivation 3 agrees

The operator chose the **split** plan (steps 1 to 7 today, box deallocated
overnight, steps 8 to 10 tomorrow) and confirmed the RDP address.

```
[14:32:42]   artifact verified: 6e65560325cb6d7d3fea204ebb72876b3b113cbbfe9f2fa4f94113237e9eb4d1 (440610608 bytes), Authenticode Valid
[14:32:43]   provider key present (value never printed)
[14:32:43]   build machine public IP: 67.164.251.99
[14:35:54] Provisioned.
[14:35:57]   RDP rule confirmed by read-back: 67.164.251.99/32
[14:35:58]   public IP: 52.247.200.136
[14:35:59]   agent: Ready
[14:48:50] Staged, digest re-verified ON THE BOX. OK staged; artifact=6e65560325cb6d7d3fea204ebb72876b3b113cbbfe9f2fa4f94113237e9eb4d1 size=440610608
[14:49:22]   WROTE wrapper=5201 runner=112 AutoAdminLogon=
DRIVER_EXIT=0
```

**All three derivations agree**: by hand on the build machine, through blob
storage by download and re-hash, and re-derived on the box after a 440 MB
transfer. The job card's instruction was to stop if any differed. None did.

`AutoAdminLogon=` is empty and was **asserted rather than set**. The driver arms
no auto-logon, which is what makes the operator logins the correct price of the
PROMPT 15 credential rule rather than a defect to engineer around.

**The RDP scope was verified twice, independently.** Once by the driver's own
read-back, and once afterwards by a separate `az network nsg rule show` from this
session:

```
67.164.251.99/32   3389   Allow   Inbound
```

Never `0.0.0.0/0`.

**On the admin credential.** `az vm create` requires a value, so the driver
generates a random 24-character bootstrap password, passes it once, and nulls it
without ever printing it. Nothing in the harness writes an account password
again. The operator sets their own at Card 1 and this session never sees it,
never asks for it, and never calls `az vm user update` itself.

### 5.1 Resources created, recorded now so teardown can be checked against them

```
cfv-179        Microsoft.Compute/virtualMachines
cfv-179-osdisk Microsoft.Compute/disks
cfv-179VMNic   Microsoft.Network/networkInterfaces
cfv-179-pip    Microsoft.Network/publicIPAddresses
cfv-179-nsg    Microsoft.Network/networkSecurityGroups
```

Five resources. `az vm delete` removes only the first, so teardown sweeps the
other four explicitly, **NIC first** because it references the public IP and the
NSG.

---

## 6. Three judgement calls taken before dispatching any phase

Recorded here rather than buried beside the results they affect.

### 6.1 Rows 10 and 11 are deferred out of the stated order, and why

The job card fixes the phase order and asks for it to be stated. **It is followed
with one deviation: matrix rows 10 and 11 are deferred**, and everything after
them keeps its specified position.

Both are structurally human-only and neither can be automated around:

* **Row 10, the reboot pass.** Auto-logon is one-shot and PROMPT 15 forbids
  re-arming it, so after a reboot a person must log in and restart the runner.
* **Row 11, the by-hand panel checks.** Ten Studio checks read by eye.

The deviation is safe because **the job card's own rationale for the order is
about phases that change box state** — the wrapper phase, which switches the box
to ollama, and RemoveAll, which destroys the install. Rows 10 and 11 change
nothing that rows 3, 5 to 9 and 12 to 14 measure. The two state-changing phases
keep their positions, second to last and last.

**What is NOT claimed:** that deferring them is free. Row 10 is the reboot pass,
and any row measured before it is measured on a box that has not rebooted. That
is the same condition every pre-reboot row has always been measured under, and
the `.POSTREBOOT` variants exist precisely to re-measure the ones that matter.

### 6.2 The job card's zero-outbound-email clause, and a correction to it

The card says: *"Do not run `phase3b` or any probe that transmits. It sends
twice, in test 3 and in test 6."*

**`phase3b` is not run.** That is obeyed without qualification.

**The reason given is not quite right, and the card asks to be told so.** The two
sends named — test 3 and test 6 — are in `interim-v120-phase3.ps1`, and both go
to a **local SMTP sink** started on the box for the purpose (`sink@example.com`,
a node listener answering `220 cf-sink ESMTP`). Test 6's own verdict is computed
from `approvedBytesAtSink` and `tamperedBytesAtSink`. **No packet leaves the VM
on either.**

The one path in that file that genuinely transmits is card **#198**, and it is
gated at line 468 behind **both** a present credential **and** the
`-ExpectRealCredential` switch:

```powershell
if ($credPresent -and $ExpectRealCredential) {
```

So `interim-v120-phase3.ps1` is run **without `-ExpectRealCredential`**, which
leaves #198 recorded with its reason rather than executed. **`#198` stays VOID as
a receiving-provider outcome**, exactly as the card directs, and zero outbound
email is achieved — but by gating the third path, not by avoiding the two the
card named.

### 6.3 Rows 5 to 7 and rows 8 to 9 share a box here; the v1.4.0 baseline used two

The v1.4.0 matrix measured rows 5, 6, 7 on `cfv-170` and rows 8, 9 on `cfv-174`.
This job puts all of them on box A, which is correct per the card and is what the
`SP.*` phase was designed for: it is an A/B on one box, deliberately, so that DNS,
timing and provider addresses do not become a second variable, and it is
**self-cleaning** — the fixed arm's own flush removes the pre-fix arm's pollution.

It does, however, rewrite the nft allowlist, and rows 8 and 9 measure reachability
against that allowlist. The phase does **not** change the configured provider —
it renders and runs the firewall block rather than executing
`switch-provider.ps1`, which is the blind spot v1.4.3 section 12.3 identified.

**Stated so it is not discovered later:** if any `TC.*` row reports an anomaly, the
shared box is a candidate confound and will be named as one rather than the
anomaly being reported as a clean product finding.

---

## 7. MATRIX ROW 1: clean install, all resources, all pins. **PASS**

```
PASS=15 FAIL=0 VOID=0 INFO=4  (counted 19 of 19 recorded rows)
positive controls registered=2 fired=2
preconditions declared=0 met=0

PHASE VERDICT: PASS. Every positive control fired and every precondition was met.
PHASE1_PROBE_COMPLETE rc=0
```

Install exit was clean at 16 minutes: `install-result.txt: INSTALLER_DONE=success`.
Studio's per-user installer landed in the original user profile, de-elevated, as
designed.

### 7.1 The evidence was retrieved through a hash gate, not read off the console

`az vm run-command` truncates its payload, and the v1.4.3 run produced a reading
where the completion sentinel arrived and **only 25 of 54 evidence rows did**. So
the transcript was fetched in chunks with the box's own digest as the gate:

```
FETCH_SHA=b28a333edde06b65a675d7b4a3bf43e9f4b378991e8ba480514b4d7f704b7585
FETCH_BYTES=11020
FETCH_CHUNKS=6
LOCAL_SHA=b28a333edde06b65a675d7b4a3bf43e9f4b378991e8ba480514b4d7f704b7585
FETCH_INTACT=True
```

A short read cannot be mistaken for a complete one, because the reassembled copy
must hash to what the box computed before any of it is quoted.

### 7.2 The rows that settle questions TASK 0 raised

```
PIN.version         PASS   Installed version reports 1.4.4
PIN.studio.asar     PASS   the INSTALLED app.asar matches the build-time digest
PIN.bundle          PASS   all 34 preflight resources shipped
PIN.soul            PASS   e70212603f2f91e6abf6db576c9535b1aaad60506e2fb075c199f18160db7941
PIN.soul.indistro   PASS   same digest, as installed in the distro
PIN.soul.rootpin    PASS   root-owned /etc/clawfactory/soul.sha256 matches
PIN.persona         PASS   0557d07004d4d067d8cd9e7cee7b2a3a783e0ac8ff4c492c0c152d7e35ff63a0
PIN.workspaceSoul   PASS   441b6279f6613c313e87e9e9e034f97a220540cddbf1cf738bb9a86c37a5a257
PIN.rootfs          INFO   ubuntu 22.04 jammy; tarball not re-derivable post-install
P1.CHAN             PASS   POSITIVE CONTROL: the WSL channel discriminates
P1.3.CTL / P1.3c    PASS   the enumeration sees a present resource and not an absent one
```

**`PIN.version` reading 1.4.4 is the evidence that the TASK 0 repin is live rather
than merely committed.** Before this morning `interim-v120-phase1.ps1` would have
been read against a stale literal.

**`PIN.studio.asar` PASS settles section 2.6 by measurement**, not by reading the
`.iss`: the installed `app.asar` equals `a64a118f…`, so Studio 1.3.2 is what
actually shipped and the by-hand checklist's `1.3.2` strings are correct.

**`PIN.rootfs` recorded INFO, exactly as section 2.3 predicted.** The dead literal
is confirmed dead by observation rather than only by reading.

**Derivation 3, a second time and from inside the probe:**
`On-VM artifact sha256: 6e65560325cb6d7d3fea204ebb72876b3b113cbbfe9f2fa4f94113237e9eb4d1`.

### 7.3 Seven install warnings, none an ERROR, and what each is

`ERROR lines : 0`. The seven `WARN` lines are recorded in full rather than
summarised, because three of them are the kind that get rediscovered as findings:

| Warning | Reading |
| --- | --- |
| `Virtualization may be disabled in BIOS. WSL2 may fail to start.` | The v1.4.3 run measured this on the same image and found **WSL 2, not a WSL1 fallback** — a detection artifact at this VM size. **Not assumed here**: it is re-measured in the next phase, because WSL1 would be a different isolation story than the structural claims rest on |
| `gateway-install block exited 1, but the unit file exists` | The installer's own text names this as the known-benign non-zero block exit and defers to the `/status` health poll. Consistent with the v1.0.45 lineage |
| `Step-EnableChatCompletions returned exit=1` | **Tracked, not dismissed.** The installer says the native chat app may not connect. This is the ClawChat gating path, and it is followed up rather than left as a warning nobody read |
| `bonjour drop-in returned 1` | Install continues; the drop-in is to be verified rather than assumed |
| three × `[bootstrap] skill-scout / skill-builder / publisher: placeholder` | The documented stub agents. Consistent with the standing record that "four agents" overstates what ships |

**`AUTOMOUNT_LINE=enabled=false`** — the drift this project has chased repeatedly
is absent on this box. **`MNT_C_PRESENT=yes`** is the documented empty stub and is
NOT evidence of Windows visibility; a directory test is not a valid check for it.

---

## 8. Sections 8 onward: IN PROGRESS

Matrix row 3 is dispatched at the time of writing. Rows 5 to 9 and 12 to 14, the
sections, the wrapper phase and the uninstall branch are owed and none is claimed
in either direction.

---

## 9. Task accounting so far

| Task | State |
| --- | --- |
| Job card moved to `docs/cc_jobs/`, committed | **DONE**, `191bff5` |
| PROMPT 15 preamble, stop condition checked | **DONE**, did not fire |
| Three required reports read in full | **DONE** |
| TASK 0.1 plan stated before `az vm create` | **DONE**, section 4 |
| TASK 0.2 two named fixes | **DONE**, `cef6cbd` and `b11c2c5` |
| TASK 0.2 wider enumeration | **DONE**, section 2 |
| TASK 0.2 canary | **DONE, 3 of 3**, section 2.2 |
| TASK 0.3 upload + verify by download and re-hash | **DONE**, section 1 |
| TASK 0.4 starting estate, unfiltered | **DONE**, section 3 |
| TASK 1 phase order | **STATED**, section 4.1. Not run |
| TASK 2 the v1.4.4 changes | **NOT RUN** |
| TASK 3 the v1.4.3 sections | **NOT RUN** |
| TASK 4 operator handoffs | Card 1 printed; awaiting the go/no-go |
| TASK 5 standing traps | Followed; two hit already and are recorded (sections 2.2, 3) |
| TASK 6 teardown | **NOT DUE** — nothing provisioned |
| TASK 7 close-out | this file |

**Resource ledger so far: zero VMs provisioned, zero VMs running, nothing
billing compute.** One 440 MB blob uploaded to the validation container, which is
retained as evidence and is not billable compute.

---

## 8A. MATRIX ROW 3: install-time provider-route gate. **PASS**

```
PASS=11 FAIL=0 VOID=0 INFO=1  (counted 12 of 12 recorded rows)
positive controls registered=6 fired=6
preconditions declared=1 met=1

PHASE VERDICT: PASS. Every positive control fired and every precondition was met.
PROVIDERGATE_PROBE_COMPLETE rc=0
```

**This row is strong because it was measured in both directions in one run**, which
is the shape a gate has to be proven in — "the gate did not fire" and "the gate is
not wired up" are otherwise indistinguishable:

```
PG.2.CTL0  PASS  the gate probe was extracted from the INSTALLED setup.ps1
PG.2.CTL1  PASS  the gate probe reached the distro intact
PG.2.CTL2  PASS  THE FAULT LANDED: the provider host now resolves to an unroutable address
PG.2.CTL3  PASS  the gate probe SUCCEEDS on the healthy box in this same run
PG.2a      PASS  TEST 2: the provider-route gate PASSED on this healthy box
PG.2c      PASS  with the provider route deliberately broken, the gate's probe FAILS
PG.2d      PASS  the rig was removed and the provider resolves normally again
```

`PG.2.CTL0` matters more than it looks: the probe under test was extracted from
the **installed** `setup.ps1`, not from the repo, so this measures the artifact
that shipped rather than a copy of the source.

`PG.2d` matters for everything after it. A fault-injection phase that leaves its
fault behind poisons every later phase, and this one would have bricked the
agent's provider route. Removal was verified, not assumed:
`RESTORED=160.79.104.10`.

### 8A.1 What row 3 does NOT prove, recorded as INFO rather than omitted

```
PG.3f  INFO  LEVEL 2 CONTROL NOT RUN: the installer's loud abort was not observed in this run
```

The phase's own words, kept because they are the correct standard: *"Level 1 above
proves the gate MEASURES correctly in both directions on the shipped probe. It does
NOT observe the installer aborting. Re-run this phase with `-RunFullInstallControl`
to close that half; it costs a full install. Recorded as INFO rather than omitted,
because a control that was skipped and a control that passed must never look the
same in a results file."**

**Carried forward as owed**, not quietly absorbed into the PASS. Closing it costs a
dedicated install and is a candidate for box B or C, which install anyway.

---

## 8B. MATRIX ROWS 5, 6 and 7: the `SP.*` switch rows. **ALL THREE PASS**

```
PASS=39 FAIL=1 VOID=0 INFO=1  (counted 41 of 41 recorded rows)
positive controls registered=13 fired=13
preconditions declared=1 met=1

PHASE VERDICT: FAIL. Failing checks: SP.8.PRE
SWITCHPROVIDER_PROBE_COMPLETE rc=1
```

**The phase verdict is FAIL and the three matrix rows it carries all PASS. Both
statements are true and neither is allowed to hide the other**, so they are stated
together. The single failing row is `SP.8`, which the job card names in advance as
the documented address-scoping residual.

| Matrix row | The claim | Evidence | Verdict |
| --- | --- | --- | --- |
| **5** | no toolchain address enters the allowlist after a switch | `SP.4a` no toolchain address in `allowed_ipv4`; `SP.4b` none in `allowed-ips.txt` | **PASS** |
| **6** | with the toggle OFF, GitHub and npm unreachable after a switch | `SP.5a` | **PASS** |
| **7** | CONTROL for 6: with the toggle ON, they ARE reachable | `SP.6a` | **PASS** |

### 8B.1 The A/B that proves the Guard 3 fix holds on v1.4.4

The phase demonstrates the defect and the fix on the same box, in the same run,
with only the script text differing:

```
SP.2.CTL.PRE  PASS  THE FAULT LANDED: the pre-fix block actually ran and rebuilt the allowlist
SP.2a.PRE     PASS  REFERENCE: the 1.3.4 script puts toolchain addresses into allowed_ipv4
SP.2b.PRE     PASS  REFERENCE: the 1.3.4 script PERSISTS them to allowed-ips.txt
SP.2c.PRE     PASS  THE SECURITY FAILURE: with the toggle OFF, GitHub and npm are reachable again after the switch
SP.2d.PRE     PASS  The panel still reports the toggle as OFF while the route is open
SP.4a/4b.PRE  PASS  after the FIXED switch, NO toolchain address in either place
SP.4c.PRE     PASS  the provider route SURVIVED the fixed rebuild
```

**The old defect reproduces and the shipped v1.4.4 script does not exhibit it.**
`SP.3.CTL.PRE` matters here: the fixed block was rendered from the **INSTALLED**
`switch-provider.ps1`, so this measures the artifact that shipped rather than the
repo.

### 8B.2 The fail-closed guard refuses on every malformed input, and cleans up

```
SP.7.CTL.PRE  PASS  THE FAULT LANDED: a toolchain host really was added to the seed
SP.7a.PRE     PASS  a toolchain host in the seed makes the fixed script REFUSE rather than widen the unrevocable set
SP.7b.PRE     PASS  the injected fault was removed again, so later phases start from the real seed
SP.7c.PRE     PASS  an EMPTY seed is fatal and the firewall is left untouched
SP.7d.PRE     PASS  a MALFORMED seed line is fatal and is named in the refusal
SP.7e.PRE     PASS  the real seed was restored and the script succeeds again
```

That is the PROMPT 15 input-shape sweep answered by execution rather than by
reading: present, poisoned, empty and malformed each have a decided and measured
meaning, and **a fault denies rather than defaulting**.

### 8B.3 `SP.8`: the documented residual, reported verbatim and NOT adjusted

```
SP.8.PRE  FAIL  PANEL-COPY CHECK: with the toggle OFF, is the SKILL HUB actually unreachable?
  clawhub.ai:443 CONNECTED with the toggle OFF (api.clawhub.ai blocked=True). The panel copy
  says the toggle stops skill installation, and on this box it does not, because clawhub.ai
  shares an address with the permanently-allowed base host openclaw.ai. PRE-EXISTING and not
  caused by the switch-provider fix, which is proven separately by SP.5a. The finding is that
  a control's copy overstates what the control can do
```

**Not adjusted, not retired, not inverted**, per the job card. It is the
address-level-versus-hostname-level limit already on record: the toggle is
structural at the address level, and `clawhub.ai` is co-hosted with a base host
that must stay allowed. `SP.1z` records the co-hosting map as INFO.

### 8B.4 The calibration that makes every reachability row above mean something

```
SP.1.CTL.PRE  PASS  the reachability probe both connects AND is refused in the same run
  provider reachable=True (must be true); un-allowlisted site refused=True (must be true).
  A probe proven in only one direction passes whether the log rule sits above or below the
  accepts, which is the cfv-167 error
```

Both halves, in the same run. That is the standing rule that a one-directional
reachability probe once produced a false ship-blocker.

`SP.9.PRE` PASS: **the box is left with the toggle OFF**, which is the defined
starting state the reboot pass needs.

### 8B.5 One instrument observation, recorded rather than smoothed over

`SP.2.CTL0.PRE` passed with `landed 3772 bytes, expected 3771` — a one-byte
difference, consistent with a trailing newline added by the write path. The control
is an intactness check and a one-byte trailing newline does not make the reference
parse differently, which is why it passed. Recorded because a control that reports
a number other than the one it expected and still says PASS is worth a reader
knowing about, even when the reason is benign.

---

## 8C. MATRIX ROWS 8 and 9: **VOID (instrument)**, and the two causes tangled inside it

```
PASS=0 FAIL=0 VOID=30 INFO=0  (counted 30 of 30 recorded rows)
positive controls registered=7 fired=7
preconditions declared=1 met=0

PHASE VERDICT: VOID (instrument). This phase reports no product result at all.
TOOLCHAIN_PROBE_COMPLETE rc=4
```

**No product verdict is claimed for rows 8 or 9.** The unmet precondition is
`TC.3.PRE.PRE`, "a real agent turn completes with the toolchain toggle ON", and a
missing precondition is never a product verdict. All seven positive controls fired,
so the instrument was working; it declined to report, which is the phase runner
doing its job.

**Two different causes are tangled in this output and they must not be reported as
one thing.**

### 8C.1 Cause 1: `TC.1a/1b/1c` — the shared-box confound, predicted before dispatch

```
TC.1a.PRE  FAIL  A fresh install has the toolchain switch ON     policy reports enabled=false
TC.1b.PRE  FAIL  The switch being on has actually populated the set   0 address(es) live, 0 persisted
TC.1c.PRE  FAIL  With the switch ON, the software sources are reachable   github and npm reachable=False
```

**This is a phase-ordering artifact, not a product finding.** The `SP.*` phase ends
with `SP.9.PRE PASS: The box is left with the toggle OFF for the reboot pass`, and
the toolchain phase asserts that a **fresh install** has the toggle ON. The
toolchain phase's own later output confirms the state it found:
`{"ok":true,"enabled":false,"changed":false,"note":"already off"}`.

**This is exactly the confound named in section 6.3 before either phase was
dispatched**, which is the only reason it is being reported as a confound now
rather than argued into one after the fact. The v1.4.0 baseline ran rows 5 to 7 and
rows 8 to 9 on two different boxes; this job puts them on one, per the card.

It is confirmed by measurement in `interim-v144-gatediag.ps1` rather than by this
reasoning alone, and rows 8 and 9 are **re-run from the correct starting state**
before any verdict is offered on them.

### 8C.2 Cause 2: `TC.1d` — a real agent turn is fail-safe blocked. **NOT the toggle.**

```
{"id":"chatcmpl_cc56ed63…","model":"openclaw/main",
 "choices":[{"message":{"role":"assistant",
   "content":"ClawFactory could not verify that this turn is allowed, so it refused it (fail-safe). "}}],
 "usage":{"prompt_tokens":0,"completion_tokens":0,"total_tokens":0},
 "clawfactory_gate":{"blocked":true,"state":"gate_error"}}
```

**Zero model tokens, `state":"gate_error"`.** The gate could not verify the turn and
refused fail-safe, which is the security-correct direction and is also a product
that cannot answer.

**It is not the toolchain toggle.** `TC.1.CTL.PRE` PASSED in the same run with
`provider reachable=True`, so the agent's route to its model was open. The toolchain
switch governs GitHub and npm, not the provider.

The phase's own note is the right standard and is quoted rather than paraphrased:
*"this is the control turn for TC.3. It is recorded as its own row as well as
gating TC.3, because 'the agent cannot reach its model with the toggle ON' is a
ship-blocker in its own right and must not be visible only as the VOID reason of
another row."*

**A candidate cause is already on the record from this run's own install log**, and
the two were flagged as connected before this phase ran:
`[WARN] Step-EnableChatCompletions returned exit=1. The gateway may still be
operational; the native chat app may not connect until this is fixed manually.`

**Under diagnosis, not yet a finding.** `interim-v144-gatediag.ps1` measures the
gate service state, the spend meter, and **two consecutive turns in one run** —
because if turn 1 blocks and turn 2 succeeds this is a cold-start regression of the
v1.0.45 prime-and-retry fix, and if both block it is a harder fault. Those are
different findings and the difference is measured rather than guessed.

---

## 8D. The `gate_error`: diagnosed, and MY FIRST INSTRUMENT RETRACTED

### 8D.1 Revision 1 was defective and its results are withdrawn

**Retracted in full: `GD.1`, `GD.2`, `GD.4a`, `GD.4b` from the first gatediag run.**
They are recorded here rather than deleted, because a retracted measurement that
leaves no trace is how a wrong number gets re-derived later.

Revision 1 read the gateway token from `/home/clawuser/.openclaw/gateway-token`,
**a path that does not exist**. Both of its turns therefore went out with an empty
Bearer:

```
NO_TOKEN
===== TURN 1 =====  {"error":{"message":"Unauthorized","type":"unauthorized"}}
===== TURN 2 =====  {"error":{"message":"Unauthorized","type":"unauthorized"}}
```

That is the documented 401 trap, met head-on.

**And then it scored that as a PASS.** `GD.4a` tested only for the ABSENCE of
`"blocked":true`; an `Unauthorized` body contains no such string, so **a turn that
never ran was recorded as a turn that was not blocked**. Its positive control was
equally weak — it matched the word `error`, so "a body came back" was accepted as
"reached the gate".

**That is the defect class this project keeps paying for, written into the very
instrument built to investigate a fail-safe block.** It is the same shape as the
kill switch printing a success banner over a step that failed.

Two more revision-1 errors, both of which would have produced false findings:

* **`GD.2` asserted on an invented unit name.** There is no
  `clawfactory-chatgate.service`; the real unit is **`clawfactory-proxy.service`**.
  `systemctl is-active` on a nonexistent unit reports inactive, **which reads
  exactly like a stopped service**. It would have been reported as "the gating
  proxy is down" on a box where it was running fine.
* **`GD.1` measured the toolchain switch too late to mean anything.** The toolchain
  phase's own `TC.9` restores the switch to the shipped default at the end, so by
  the time revision 1 looked, the state it was trying to explain had already been
  reverted. It is **inconclusive**, not evidence against the confound.

### 8D.2 Revision 2, structurally fixed. **PASS**

```
PASS=7 FAIL=0 VOID=0 INFO=1  (counted 8 of 8 recorded rows)
positive controls registered=1 fired=1
preconditions declared=1 met=1

PHASE VERDICT: PASS. Every positive control fired and every precondition was met.
```

The fixes are structural rather than patches: the token is read the way the working
phase reads it and **its non-emptiness is a PRECONDITION**, so a turn verdict can
never again be a statement about authentication; every turn is classified into
exactly one of `MARKER_OK` / `GATE_BLOCKED` / `UNAUTHORIZED` / `EMPTY` / `OTHER`;
and the marker `ZQ7GATEPROOF` appears nowhere else in the probe's own output.

### 8D.3 THE ANSWER: the agent completes turns. `TC.1d` did not reproduce.

```
TOKEN_PRESENT_LEN=48
===== TURN 1 =====
{"choices":[{"message":{"role":"assistant","content":"ZQ7GATEPROOF"}}],
 "usage":{"prompt_tokens":3,"completion_tokens":11,...}}
===== TURN 2 =====
{"choices":[{"message":{"role":"assistant","content":"ZQ7GATEPROOF"}}],
 "usage":{"prompt_tokens":11678,"completion_tokens":11,...}}

TURN1_CLASS=MARKER_OK
TURN2_CLASS=MARKER_OK
```

**Real model output, real token usage, both turns.** So the gate is NOT broken on a
clean v1.4.4 install, and `Step-EnableChatCompletions returned exit=1` did **not**
leave the chat path inoperable.

The architecture is correct and was verified rather than assumed:

```
clawfactory-proxy.service  loaded active running
  ClawFactory chatCompletions gating proxy (SOUL + spend gate on 127.0.0.1:8787)
LISTEN 127.0.0.1:8787  pid=12615     <- root-owned gating proxy
LISTEN 127.0.0.1:8788  pid=12180     <- the real gateway, behind it
       [::1]:8787 / [::1]:8788       <- both families bound
```

**The proxy journal contains exactly one `gate_error`, and it is `TC.1d`'s:**

```
Aug 27 22:25:28  [clawfactory-proxy] listening on 127.0.0.1:8787 -> real gateway 127.0.0.1:8788;
                 gating POST /v1/chat/completions via /usr/local/sbin/clawfactory-turn-gate.sh as clawuser
Aug 27 22:52:12  [clawfactory-proxy] chat turn BLOCKED (gate_error) stream=false
```

One event, at 22:52:12. Nothing before it, nothing after it, and two successful
turns thirteen minutes later.

### 8D.4 What is NOT claimed

**The root cause of the 22:52:12 `gate_error` is NOT identified.** It happened once
and did not reproduce. Saying more than that would be an argument dressed as a
measurement, so:

* **Not claimed: "cold start".** The toolchain phase warms the agent (L17) before
  `TC.1d`, which weakens that explanation — though the warm-up turn's own result
  was never asserted, so it may itself have failed silently. Unknown either way.
* **Not claimed: "the toolchain toggle caused it".** The toggle was OFF at 22:52
  and ON at 23:05, which is a real difference between the failing and succeeding
  observations, but the gate runs locally and the provider route was reachable in
  the same run. **Plausible and unproven.** Recorded as a candidate, not a cause.
* **Not claimed: "it is harmless".** A one-off unexplained fail-safe block on the
  primary customer path is worth a card even though it did not reproduce, because
  the failure mode is a user whose agent silently refuses one turn.

**The direction of the failure is the safe one**: the gate refused a turn it could
not verify and spent zero model tokens, rather than allowing an unverified turn.

`/etc/clawfactory/spend.json`, `gate.json` and `chatgate.json` are all **ABSENT**,
with a control proving the probe can tell present from absent. The gate reads its
configuration from somewhere other than those paths. Recorded as an observation,
not a defect: the gate demonstrably works.

---

## 8E. MATRIX ROWS 8 and 9, RE-RUN from the correct starting state. **BOTH PASS**

```
PASS=30 FAIL=0 VOID=0 INFO=0  (counted 30 of 30 recorded rows)
positive controls registered=7 fired=7
preconditions declared=1 met=1

PHASE VERDICT: PASS. Every positive control fired and every precondition was met.
TOOLCHAIN_PROBE_COMPLETE rc=0
```

A clean sweep: every row PASS, nothing VOID, all seven controls fired.

### 8E.1 The confound of section 8C.1 is now PROVEN, not argued

The three rows that FAILed on the first attempt all PASS on the re-run, with the
only difference being the toolchain switch's starting state:

| Row | First attempt (switch OFF) | Re-run (switch ON, shipped default) |
| --- | --- | --- |
| `TC.1a` A fresh install has the toolchain switch ON | **FAIL** `policy reports enabled=false` | **PASS** |
| `TC.1b` the switch being on has populated the set | **FAIL** `0 address(es) live, 0 persisted` | **PASS** |
| `TC.1c` with the switch ON the sources are reachable | **FAIL** `github and npm reachable=False` | **PASS** |

**This is the measurement that converts section 6.3's prediction into a result.**
It was named as a candidate confound before either phase was dispatched, and it is
now demonstrated by re-running from the correct state rather than by reasoning
about it. **Rows 8 and 9 carry no product defect.**

### 8E.2 `TC.1d` PASSES, confirming the transient reading from a second direction

```
TC.1d.PRE    PASS  A real agent turn completes with the toolchain toggle ON
TC.3.PRE.PRE PASS  PRECONDITION: a real agent turn completes with the toolchain toggle ON
TC.3.PRE     PASS  A real agent turn completes end to end with the toolchain switch OFF
```

The row that produced the `gate_error` now passes, and its precondition is met so
`TC.3` reports a real verdict rather than VOIDing. Together with the proxy journal
holding exactly one `gate_error` (section 8D.3), **the transient reading is
corroborated by two independent observations.** The root cause remains
unidentified and is still not claimed.

### 8E.3 What rows 8 and 9 actually establish

```
TC.2b  PASS  switching off actually emptied the live set AND the persisted file
TC.2c  PASS  with the switch OFF, the software sources are unreachable for uid 1000
TC.4   PASS  a real five-hourly refresh does NOT re-open a route the user closed
TC.4b  PASS  the sources are still unreachable after the refresh, measured not inferred
TC.5   PASS  switching back ON restores the route (reversible, not one-way)
TC.6   PASS  the agent cannot change the toolchain switch through any channel it can reach
TC.8   PASS  the tripwire FAILS the unit when the toolchain accept rule is removed
TC.8c  PASS  the toolchain set cannot be deleted while its accept rule references it
TC.7a/b/c PASS  user-added destinations still work, revoking still removes, the two sets do not disturb each other
```

`TC.4` is the L30 row — a scheduled refresh re-opening a user-closed route — and it
holds, **with `TC.4.CTL` proving the refresh actually ran and actually added
provider addresses**, so the PASS is not the refresh silently failing to happen.

`TC.6` is the containment row: uid 1000 cannot flip its own switch, with
`TC.6.CTL` proving uid 1000 *can* write somewhere it owns, so the refusals are real
refusals rather than a broken writer.

### 8E.4 One PASS that does NOT retire its residual

`TC.1c` PASSED here. **That does not close `#261`.** `#261` is about
*intermittency*: the switch reads ON while the firewall holds a snapshot of
addresses that the sources answer from a larger rotating pool, previously measured
at 5 of 12 attempts before a reboot and 2 of 6 after one. **A single reachability
reading against a rotating pool is close to a coin flip**, and one PASS is one
sample. The residual stands and is re-measured properly on the reboot pass.

---

## 8F. MATRIX ROW 12: the harness self-test. **PASS, 15 of 15**

```
HARNESS SELF-TEST PASSED: 15/15.
Each of the five injected faults was caught, each paired control shows the guard discriminates,
and fault 5 additionally proved that its injection landed rather than assuming it.
HARNESS_SELFTEST_COMPLETE rc=0
```

**This row carries more weight than its position suggests**, because every verdict
in this close-out is produced by the machinery it tests. If the phase runner could
be fooled, nothing above would mean anything.

What it establishes, in the runner's own words:

```
SELF.4b       PASS  nothing reported yields VOID, not a silent agreement, and the phase is not a clean pass
SELF.4d       PASS  a row-level void withholds the phase pass but does NOT downgrade sound rows
SELF.5.inject PASS  FAULT 5 INJECTION LANDED: the fault fired and the verdict really did arrive empty
SELF.5        PASS  an empty verdict records VOID, names the row, and withholds the phase pass
SELF.5ctl     PASS  a well-formed verdict from the same expression still reports PASS
SELF.5b       PASS  an unrecognised verdict records VOID and names its raw value
SELF.5c       PASS  an uncountable malformed verdict is INSTRUMENT-level, and the sound row is downgraded with it
```

`SELF.5.inject` is the one that makes the rest trustworthy: **a fault injection that
does not inject scores a false pass and looks exactly like a working control**, so
the injection's landing is asserted rather than assumed.

**One cosmetic instrument nit**, recorded rather than ignored: the job transcript
ends with a garbled line, `啒乎剅䕟䥘䍔䑏㵅ര`, which is a UTF-16/UTF-8 decoding
artifact of the runner's own exit-code line. It affects the transcript's last line
only; the sentinel, the 15/15 count and `rc=0` all parsed correctly. Recorded
because an unreadable line in an evidence file is worth a reader knowing is benign.

---

## 8G. MATRIX ROW 14: Guard 2 send path. **VOID, with a named reason. NOT a product FAIL.**

The phase reported:

```
PASS=14 FAIL=7 VOID=4 INFO=1  (counted 26 of 26 recorded rows)
positive controls registered=1 fired=1
preconditions declared=0 met=0
PHASE VERDICT: FAIL.
```

**Those seven FAILs are NOT reported as product defects, and the reason is a rule
rather than a judgement call.** PROMPT 15: *"The SMTP app password is a
deliberately KEPT throwaway. Do not ask for a new one and do not ask for it to be
revoked. **If a phase needs it and it is absent, that phase is VOID.**"*

The credential is absent, measured rather than assumed:

```
cred : stat: cannot statx '/etc/clawfactory/send-credential.json': No such file or directory
--- credential configured? (existence only, value never read) ---
CREDENTIAL_ABSENT
```

It is absent **by design in this run**: configuring it is the human-in-the-loop
Studio step, and this job mandates zero outbound email.

### 8G.1 The evidence that these are precondition failures, not defects

**`G2.10` is the clearest case, because its own control passed:**

```
G2.10   FAIL  Test 10: credential file unreadable by the agent uid
G2.10c  PASS  CONTROL: a world-readable config IS readable by the agent
              proves the denial above is a permission boundary, not a missing file
CREDHOST=
NO_SECRET_CONFIGURED
```

The reader demonstrably works. The **subject file does not exist**. "Unreadable by
the agent uid" cannot be measured against a file that is absent, and a FAIL here
says nothing about the product's credential protection.

**`G2.11c` is a CONTROL that FAILED**, which by the runner's own rules makes the
rows around it uninterpretable rather than failing:

```
G2.11c  FAIL  CONTROL: a readable attachment is accepted
--- broker down: the agent client must fail LOUD and preserve the draft ---
clawfactory-send: the send broker is unreachable (connect ENOENT /run/clawfactory/send.sock).
```

The phase deliberately takes the broker down to test the loud-failure path, and the
socket was still down for what followed. **A control that did not fire voids what
it protects.**

**`G2.1` never got a request id at all** — `requestId=` is empty — so tests 2
through 6, which all operate on that request, had no subject to act on.

### 8G.2 What DID pass, and is worth keeping

```
G2.0  PASS  Send broker reachable: request socket EXISTS with correct modes
            req-sock   : /run/clawfactory/send.sock  660 root:clawuser
            admin-sock : /run/clawfactory/send-admin.sock  600 root:root
            ctl        : /usr/local/sbin/clawfactory-sendctl.js  750 root:root
            store      : /var/lib/clawfactory/send  700 root:root
```

The **ownership and mode structure of the send stack is intact**: the request socket
is group-accessible to `clawuser`, the admin socket is root-only, the control script
is root-only, and the store is root-only. That is the structural shape Guard 2's
"no send path at the agent's identity" claim rests on, and it holds.

`clawfactory-send.service` and `clawfactory-send-gc.timer` are both **active**.

### 8G.3 `#198` stays VOID, exactly as the job card directs

```
G2.198  VOID  Card #198: external delivery, real credential, third-party mailbox
```

**Zero outbound email was sent. `phase3b` was not run.** The gating at
`interim-v120-phase3.ps1:468` (`if ($credPresent -and $ExpectRealCredential)`) meant
#198 could not execute, and the phase was invoked without `-ExpectRealCredential`.

### 8G.4 A HARNESS FINDING: phase 3 declares no precondition and so reports FAIL where PROMPT 15 requires VOID

`preconditions declared=0 met=0`.

**This is an instrument defect, not a product defect, and it is the more useful
finding of the two.** PROMPT 15 states the rule plainly, and the phase has no
mechanism to apply it: it cannot tell "the send path is broken" from "there is
nothing configured to send with", so it reports the second as the first.

The consequence is concrete and this run nearly walked into it: **a reader
skimming `FAIL=7` on the Guard 2 suite would conclude the approval-gated send path
is broken on v1.4.4.** It is not; it is unconfigured.

**The fix is the same shape the other phases already use** — `Require-Precondition`
on `CREDENTIAL_PRESENT`, so the affected rows record VOID with a named reason.
`interim-v135-switchprovider.ps1` and `interim-v130-toolchain.ps1` both do exactly
this and both behaved correctly this session. **Carded, not fixed here**: changing
an instrument mid-run is the wrong order, and box D re-runs this phase.

### 8G.5 The verdict recorded for row 14

**VOID**, reason: *the Guard 2 suite requires a configured SMTP credential; none is
configured on this box by design, and PROMPT 15 directs that such a phase is VOID.*
The v1.4.0 baseline recorded this row as "PASS on the mechanism, VOID on delivery";
**this run cannot claim the mechanism half**, because the mechanism tests had no
credential and no request id to work with.

---

## 8H. MATRIX ROW 13: zero malformed verdict rows. **PASS**

Every phase this session counted N of N, with no row the runner could not read:

| Phase | Counted |
| --- | --- |
| phase 1 (row 1) | 19 of 19 |
| providergate (row 3) | 12 of 12 |
| switchprovider (rows 5–7) | 41 of 41 |
| toolchain, first attempt | 30 of 30 |
| gatediag revision 2 | 8 of 8 |
| toolchain, re-run (rows 8–9) | 30 of 30 |
| harness self-test (row 12) | 15 of 15 |
| phase 3 (row 14) | 26 of 26 |

**No phase invented a verdict word and no row was uncountable**, including the two
phases that ended FAIL and the one that ended VOID. That is the property row 13
asserts, and row 12's self-test independently proved the runner *would* have caught
a malformed verdict had one occurred.
