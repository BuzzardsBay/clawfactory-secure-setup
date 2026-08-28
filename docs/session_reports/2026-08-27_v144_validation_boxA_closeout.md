# CLOSE-OUT: v1.4.4 validation, BOX A

**Status: BOX A COMPLETE. cfv-179 TORN DOWN, nothing billing.** Rows 1,3,5-13 PASS; row 14 VOID (no SMTP credential, by design); sections 14.6, 14.8, 14.9, 14.10, 14.11 and TASK 2 all PASS; RemoveAll measured. ONE product defect found (encoding, cosmetic). NO fitness verdict - box A is one of four.
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

---

## 8I. TASK 2: the v1.4.4 changes, on a clean install. **THE HEADLINE ROWS PASS**

```
PASS=13 FAIL=0 VOID=0 INFO=4  (counted 17 of 17 recorded rows)
positive controls registered=5 fired=5
preconditions declared=1 met=1

PHASE VERDICT: PASS. Every positive control fired and every precondition was met.
WRAPPERS_COMPLETE rc=0
```

Run **without** `-RunProviderSwitch`, deliberately: `WR.5` switches the box to
ollama and matrix row 11 reads provider state by hand, so switching before the
panel checks would confound them. The switch rows are re-run with the flag after
row 11, in the job card's specified position.

### 8I.1 TASK 2.1: the kill switch, from a clean install. **PASS**

**This is the defect that made v1.4.3 a NO**, and it is fixed and measured on a
clean box rather than on a hand-patched one:

```
WR.3.CTL  PASS  POSITIVE CONTROL: the gateway was UP before the kill switch ran, by BOTH readers
WR.3.PRE  PASS  PRECONDITION: a running gateway to stop
WR.3      PASS  clawfactory-stop.ps1 actually stops the gateway and any agent turn
```

**Both readers, not one.** Port 8787 is the root-owned gating proxy and answers 502
while the gateway behind it is dead, so an any-HTTP-response-means-up reader is a
defect that has already voided a phase. The control confirms UP by both before the
subject runs.

Until v1.4.3 this script's two WSL lines failed on a quoting fault and it printed
its success banner anyway, on **every release since v1.0**.

### 8I.2 TASK 2.2: it refuses to claim success when it cannot verify. **PASS**

```
WR.4.CTL  PASS  POSITIVE CONTROL: the fault was actually injected (the copy names a distro that does not exist)
WR.4      PASS  with every sandbox call failing, clawfactory-stop.ps1 refuses to claim success
```

**The fault-landed control is what makes this row mean anything.** A fault injection
that does not inject scores a false pass and looks exactly like a working control.
A success path that has never failed is indistinguishable from one that cannot.

### 8I.3 TASK 2.6 and section 14.11: the shipped wrappers EXECUTE

```
WR.1.CTL  PASS  smoke-test.ps1 printed its own summary line, so a silent death is distinguishable from a clean run
WR.1      PASS  smoke-test.ps1 executes from its installed form and reports zero failures
WR.7      PASS  post-install.ps1 executes (-Provider later, the no-credential branch)
WR.8      PASS  bootstrap.ps1 executes and is re-runnable
WR.9.CTL  PASS  a deliberately malformed library refuses to dot-source, so a clean load means the file is sound
WR.9      PASS  clawfactory-grants.ps1 dot-sources cleanly and defines its functions
```

**`post-install.ps1` and `bootstrap.ps1` had never been executed by any harness
generation.** The v1.4.4 close-out's coverage table recorded both as `--` in every
column. They now run from their installed form.

### 8I.4 TASK 3.5 and section 14.6: the launcher against a genuinely down gateway. **PASS**

```
WR.2  PASS  launcher.ps1 STARTS a stopped gateway rather than reporting ALREADY_RUNNING
```

**This closes the item that VOIDed in v1.4.3.** That run could not establish the
precondition, because the only supported way to put the gateway down was the kill
switch and the kill switch did not work. Here `WR.3` puts it down for real, and
`WR.2` then measures the launcher against a genuinely down gateway. **The two fixes
compose: fixing the kill switch made section 14.6 measurable.**

### 8I.5 The four INFO rows, and why a skipped row must not look like a passed one

```
WR.5   INFO  switch-provider.ps1 NOT EXECUTED in this run
WR.6   INFO  the fail-closed toolchain guard NOT EXERCISED in this run
WR.10  INFO  rename-agent.ps1 NOT EXECUTED: it blocks on a modal MessageBox
WR.11  INFO  uninstall.ps1 NOT EXECUTED here: running it is the destruction it performs
```

**TASK 2.3, 2.4 and 2.5 are therefore NOT measured on a clean install yet.** They
ride `WR.5`/`WR.6` behind `-RunProviderSwitch` and are owed. `WR.10` is an operator
click in row 11; `WR.11` is the RemoveAll branch, last of all.

---

## 9. Where box A stands, and what boxes B, C and D still owe

### 9.1 Every row measured this session, with its verdict and evidence

| Row / item | Verdict | Evidence |
| --- | --- | --- |
| **1** clean install, all resources, all pins | **PASS** | 15/0/0/4 of 19; 2 of 2 controls; section 7 |
| **3** install-time provider-route gate | **PASS** | 11/0/0/1 of 12; 6 of 6 controls; section 8A |
| **5** no toolchain address enters after a switch | **PASS** | `SP.4a`, `SP.4b`; section 8B |
| **6** toggle OFF, sources unreachable after a switch | **PASS** | `SP.5a`; section 8B |
| **7** CONTROL: toggle ON, reachable | **PASS** | `SP.6a`; section 8B |
| **8** `TC.3` real agent turn, toggle OFF | **PASS** | 30/0/0/0 of 30 on re-run; section 8E |
| **9** `TC.*` regression | **PASS** | same phase; 7 of 7 controls; section 8E |
| **12** harness self-test | **PASS** | 15 of 15 faults caught; section 8F |
| **13** zero malformed verdict rows | **PASS** | eight phases, all N of N; section 8H |
| **14** Guard 2 send path | **VOID** | credential absent by design, PROMPT 15 rule; section 8G |
| **TASK 2.1** kill switch from a clean install | **PASS** | `WR.3` + `WR.3.CTL` both readers; section 8I.1 |
| **TASK 2.2** refuses to claim success unverified | **PASS** | `WR.4` + fault-landed control; section 8I.2 |
| **TASK 2.6** WR.1/2/3/4/7/8/9 | **PASS** | 13/0/0/4 of 17; 5 of 5 controls; section 8I |
| **TASK 3.5** section 14.6 launcher vs down gateway | **PASS** | `WR.2`; section 8I.4 |
| **`SP.8`** address-scoping residual | **FAIL, expected** | reported verbatim, not adjusted; section 8B.3 |

### 9.2 What box A still owes, and it is NOT a small remainder

| Owed | Why not done | Needs |
| --- | --- | --- |
| **Row 10**, reboot pass | auto-logon is one-shot; PROMPT 15 forbids re-arming it | operator |
| **Row 11**, ten by-hand panel checks | read by eye | operator |
| **TASK 2.3 / 2.4 / 2.5**, `WR.5` / `WR.6` | behind `-RunProviderSwitch`; must run AFTER row 11 or it confounds the panel reading | unattended, after row 11 |
| **TASK 2.6** `rename-agent.ps1` | blocks on a modal dialog | operator click |
| **TASK 3.1**, section 14.8 bundled bytes = committed bytes, with a planted CR | never run this session | unattended |
| **TASK 3.2**, section 14.9 orchestrator-prompt reaches the distro CR=0 | never run this session | unattended |
| **TASK 3.3**, section 14.10 keepalive from its LF form + no console flash at logon | the flash half is a logon observation | operator + unattended |
| **RemoveAll branch, 16 rows** | destroys the install; last of all | operator dialog |
| **`PG.3f`** Level 2 control, the installer's loud abort | costs a full install | box B or C |

**Sections 14.8, 14.9 and 14.10 were NOT reached.** They are the v1.4.3
carry-forward debt and they remain owed. Section 14.11's *execution* half is covered
by `WR.1/7/8/9`; its **CR census half is not**.

### 9.3 What boxes B, C and D owe, so the next session inherits a spec

**Box B, `-Provider later`**

* Matrix **row 4**: provider gate skipped with a stated reason.
* Candidate host for **`PG.3f`**, the Level 2 control, since it installs anyway.

**Box C, licence host blocked, prior artifact as the control**

* Matrix **row 2**: install completes with `api.clawfactory.app` unreachable.
* The other candidate host for **`PG.3f`**.

**Box D, normal install, uninstall is the subject**

* **TASK 2 in full**: install, keep-Linux uninstall through the real dialog, read-back
  against a held before-state, reinstall that completes, teardown log, the
  fault-injected negative half, the next-boot check.
* **This is v1.4.2 debt and it has never been measured on any release.**
* **Re-runs phase 3 with a configured credential**, which is what would turn row 14
  from VOID into a real verdict.
* Carries the harness fix from section 8G.4 if it is made by then.

**Not owed by any box:** `phase3b` and card `#198`. Zero outbound email is mandated
and `#198` stays VOID as a receiving-provider outcome.

---

## 10. No fitness-to-publish verdict

By instruction, and it would be unsupportable in any case. **Box A is one of four,
and box A itself is incomplete**: rows 10 and 11 are unmeasured, sections 14.8,
14.9 and 14.10 were not reached, `WR.5`/`WR.6` are owed, and the RemoveAll branch
has not run. A verdict on that coverage would rest on an unmeasured premise.

**What can be said without a verdict:** the two defects that made v1.4.3 a NO are
fixed and now measured on a clean install with controls that fired, and nothing
measured this session is a regression.

---

## 11. End-of-session gate

### 11.1 Task accounting

| Task | State |
| --- | --- |
| Job card moved to `docs/cc_jobs/`, committed | **DONE** `191bff5` |
| PROMPT 15 preamble, stop condition checked | **DONE**, did not fire |
| Three required reports read in full | **DONE** |
| TASK 0.1 plan stated before `az vm create` | **DONE**, section 4 |
| TASK 0.2 the two named fixes | **DONE** `cef6cbd`, `b11c2c5` |
| TASK 0.2 wider enumeration | **DONE**, section 2, plus a sixth class in 2.5a |
| TASK 0.2 canary | **DONE, 3 of 3**, section 2.2 |
| TASK 0.3 upload + verify by download and re-hash | **DONE**, section 1 |
| TASK 0.4 starting estate, unfiltered | **DONE**, section 3 |
| TASK 1 phase order stated and followed | **DONE**, with rows 10/11 deferred and the deviation recorded in 6.1 |
| TASK 2.1 kill switch from a clean install | **DONE, PASS**, section 8I.1 |
| TASK 2.2 refuses to claim success unverified | **DONE, PASS**, section 8I.2 |
| TASK 2.3 switch-provider completes | **NOT DONE** — `WR.5`, owed |
| TASK 2.4 fail-closed toolchain guard refuses | **NOT DONE** — `WR.6`, owed |
| TASK 2.5 Ollama honesty line | **NOT DONE** — rides `WR.5`, owed |
| TASK 2.6 the other wrapper rows | **DONE, PASS**, section 8I.3 |
| TASK 3.1 section 14.8 | **NOT DONE** |
| TASK 3.2 section 14.9 | **NOT DONE** |
| TASK 3.3 section 14.10 | **NOT DONE** |
| TASK 3.4 section 14.11, execution half | **DONE, PASS**; CR-census half **NOT DONE** |
| TASK 3.5 section 14.6 | **DONE, PASS**, section 8I.4 |
| TASK 3.6 14.12 build-time, not sought on the box | **DONE** — correctly not attempted |
| TASK 4 operator handoffs | Card 1 delivered; the reboot-pass card is delivered with this close-out |
| TASK 5 standing traps | Followed; four hit and each is recorded |
| TASK 6 teardown | **NOT DUE** — the box is deallocated, not deleted, because the run resumes |
| TASK 7 close-out | this file |

### 11.2 Resource ledger

| | |
| --- | --- |
| VMs provisioned | **1** — `cfv-179`, Standard_D2s_v4, `clawfactory-win11-baseline-v2` |
| VMs running now | **0** — `cfv-179` **deallocated**, exit 0, confirmed `VM deallocated` |
| VMs deleted | **0** — deliberately. The run resumes on this box |
| Running window | roughly **14:32 to 17:36 local**, about 3 hours of compute at ~$0.10/hour, so **about $0.30**, plus the OS disk which bills either way |
| Licence slots | none consumed; no licence check exists since v1.4.0 |
| Blobs | one 440 MB artifact plus seven phase scripts in the validation container, retained as evidence, not billable compute |

**Resources that exist and must be swept at teardown**, recorded so the sweep can
be checked against a list rather than a memory:

```
cfv-179                    Microsoft.Compute/virtualMachines
cfv-179-osdisk             Microsoft.Compute/disks
cfv-179VMNic               Microsoft.Network/networkInterfaces
cfv-179-pip                Microsoft.Network/publicIPAddresses
cfv-179-nsg                Microsoft.Network/networkSecurityGroups
cfv-179/enablevmaccess     Microsoft.Compute/virtualMachines/extensions
```

`az vm delete` removes only the first. **NIC first**, because it references the
public IP and the NSG.

**The VMAccess extension is new since section 5.1** and appeared when the operator
set the admin password at Card 1. That is the expected and only intended use of
`az vm user update` in this run: **this session never called it**, and it must not
be called again.

**RDP rule scope**, stated exactly as TASK 6 requires: `67.164.251.99/32`, port
3389, Allow, Inbound, on `cfv-179-nsg`. Never `0.0.0.0/0`. Verified twice
independently at creation and again at deallocation.

**Credential hygiene.** No password was generated, printed, requested or set by
this session. The provider key was read from Windows Credential Manager by the
driver and reported only as `provider key present (value never printed)`. The
gateway token was read **on the box, by the probe, inside the distro**; only its
length reached the transcript (`TOKEN_PRESENT_LEN=48`). No secret value appears in
any evidence file, commit or message.

### 11.3 Delta security sweep

Scoped to what this session changed. **No product code was modified.** The only
committed changes are two stale-default fixes in `validation/`, one new validation
probe, and this close-out.

* **`interim-v140-relgate-box.ps1`** — a digest and a byte count. Narrows what the
  driver will accept; cannot widen it.
* **`MANUAL_CHECKS_studio.md`** — a version number a human reads. No runtime effect.
* **`interim-v144-gatediag.ps1`** — new, **not bundled**, does not ship. It reads
  unit states, file modes and journals, and sends two chat turns as `clawuser`. It
  writes nothing outside `/var/tmp` and removes what it writes.
* **Nothing shipped changed**, so the artifact validated is byte-identical to the
  one built at `25945d5` and signed as `6e655603…`.

**On the box:** every phase that injected a fault also removed it, and each removal
was verified rather than assumed — `PG.2d` restored the provider route, `SP.7b`/`7e`
restored the seed, `SP.2`'s fixed arm flushed the pre-fix pollution, `TC.8b` left
the firewall intact, `TC.9` left the shipped default state, and `WR.4`'s injected
fault was a copy rather than the shipped file. **The box is left installed,
firewalled, toggle ON, provider `claude`.**

**One residual reported and untouched:** `SP.8`, the address-scoping limit where
`clawhub.ai` is co-hosted with `openclaw.ai`. Not adjusted, not retired, not
inverted.

### 11.4 Delta bug review

Bugs found in this session's own work.

1. **My gatediag probe read a nonexistent token path**, so both its turns returned
   `Unauthorized` and never reached the gate. **Fixed in revision 2**; results
   retracted in section 8D.1.
2. **The same probe scored that as a PASS**, because it tested only for the absence
   of `"blocked":true`. **A turn that never ran was recorded as a turn that was not
   blocked.** Fixed structurally: token non-emptiness is now a precondition and
   every turn is classified into exactly one named state.
3. **The same probe asserted on an invented unit name**, `clawfactory-chatgate`.
   The real unit is `clawfactory-proxy`. `systemctl is-active` on a nonexistent unit
   reports inactive, **which reads exactly like a stopped service**, and it would
   have been reported as "the gating proxy is down" on a box where it was running.
   Fixed by enumerating units instead of asserting on a guessed name.
4. **The same probe measured the toolchain switch after `TC.9` had restored it**, so
   it could not settle the question it was written to settle. Recorded as
   inconclusive rather than treated as evidence.
5. **My first phase dispatch passed a bare leaf name** where the dispatcher takes a
   path. It threw before uploading, so the box was untouched.
6. **My sweep instrument covered `.ps1` only** and would have missed the stale
   version in `MANUAL_CHECKS_studio.md`, which is the one a human reads at the
   keyboard. Found by sweeping the other file types by hand; the gap is recorded in
   section 2.6 rather than silently patched.
7. **I hit the `H()` / `Get-History` alias collision** documented in the v1.4.4
   close-out, in exactly the same way. Cosmetic; renamed.
8. **A heredoc in one of my commit commands failed to parse**, writing nothing. Caught
   by checking `git status` rather than assuming the append had happened.

**Four of these eight are the same defect class this project keeps paying for: a
check that passes when nothing happened.** They were caught because the phase
runner's rules were applied to my own instruments as well as to the product, and
because row 12 independently proved the runner would catch a malformed verdict. That
is uncomfortable and it is the honest record.

### 11.5 Cards `#284` to `#292`

**Moved only as far as box A's evidence supports.** A card whose fix is proven on
one box of four is not `done` if its scope spans the others.

| Card scope | Recommendation | Why |
| --- | --- | --- |
| **The kill switch fix** (v1.4.4 TASK 2.1/2.2) | **Evidence sufficient to close on box A's part**, but hold at Review until the wrapper phase re-runs with `-RunProviderSwitch`, because `WR.5`/`WR.6` are part of the same v1.4.4 change set | proven from a clean install with both readers and a fault-landed control |
| **`switch-provider.ps1` fix** | **STAYS OPEN.** `WR.5` was not executed | rows 5–7 prove the *rendered firewall block* is correct; they do not execute the wrapper, which is the defect class v1.4.3 found |
| **The documentation / structural-table change** | **No box-A evidence either way** | not a runtime claim |
| **Anything scoped to uninstall** | **STAYS OPEN** | box D |
| **`#261`** | **STAYS OPEN.** `TC.1c` passed once; that is one sample against a rotating pool | section 8E.4 |

**Two new cards are owed from this session:**

1. **Phase 3 declares no precondition** and reports FAIL where PROMPT 15 requires
   VOID, so a reader sees `FAIL=7` on the Guard 2 suite and concludes the
   approval-gated send path is broken when it is merely unconfigured. Fix:
   `Require-Precondition` on `CREDENTIAL_PRESENT`. Section 8G.4.
2. **One unexplained `gate_error`** on the primary customer path at 22:52:12, which
   did not reproduce across two later turns. Root cause not identified. Section 8D.4.

**A third, lower priority:** six drivers carry stale `$VmName` defaults naming
deleted boxes. All fail safe. The correct fix is a mandatory parameter, not a
repoint. Section 2.5a.

---

## 12. SECTIONS 14.8 and 14.9, day 2. **BOTH PASS** — and three defective revisions on the way

```
PASS=11 FAIL=0 VOID=0 INFO=0  (counted 11 of 11 recorded rows)
positive controls registered=6 fired=6
preconditions declared=1 met=1

PHASE VERDICT: PASS. Every positive control fired and every precondition was met.
BUNDLEBYTES_COMPLETE rc=0
```

### 12.1 Section 14.8: the bundled bytes on the box ARE the committed bytes

```
COMPARED=54  MATCH=54  MISMATCH=0  ABSENT=0  CR_BAD=0  CR_WAIVED_BINARY=3
```

**Every one of the 54 tracked files the `.iss` bundles has, on the installed
machine, a SHA-256 identical to its committed blob at build commit `25945d5`, and
CR=0 across all 51 text files.**

The three CR-bearing files are `logo.png`, `lobster.ico` and `ClawChat.exe`, where
`0x0D` is data rather than a line ending. **Their digest assertion still applies
and passed**; only the CR assertion is waived, and the waiver is counted and named
rather than silent.

**The negative half, which is what makes the above mean anything:**

```
CANARY_ALTERED  sha=006a3631d5fe96682952e67eba2b69a9e64f76fff7ad16381883cdc7dfb5d232
                (committed safety-rules.md is e70212603f2f...db7941 -- one appended byte, digest differs)
CANARY_CR       cr=1     (a planted CR is reported)
CANARY_ABSENT   present=False
```

**The CR canary is the one that matters most.** A CR counter that always returned
zero would pass all 54 files identically and produce exactly this same clean
result. It was planted and it was caught.

**The manifest generator carries seven assertions of its own** and refused to emit
twice before it produced a usable file. The v1.4.3 generator had three defects
that all failed toward a full, confident, uniform answer, including one that
produced 55 rows every one of which carried `e3b0c442…`, the SHA-256 of the empty
string. This generator asserts that no row holds that digest, that no destination
contains an unexpanded `{var}`, that destinations are unique, and that the tracked
count is what the `.iss` says. **Its assertions fired on the real tree**, catching
that the Studio installer is referenced through an Inno preprocessor macro
`{#StudioInstaller}` rather than by filename.

**54 is independent corroboration**: reached here by parsing the `.iss` and hashing
git blobs, and matching the v1.4.3 count of 54 tracked bundled files reached by a
different route.

### 12.2 Section 14.9: the orchestrator prompt reaches the distro, CR=0

```
PATH_USED=/home/clawuser/.openclaw/agents/orchestrator/agent.md
EXISTS=yes  BYTES=4277  CR=0  LINES=65
SHA=f7f8163426790c05bbec090cc7efcfd83809a81531214fd26db68c6e4d12ec43
OWNER=clawuser:clawuser MODE=644  PLACEHOLDER_HITS=0
WHOAMI=clawuser UID=1000
SOURCE_NAME_IN_DISTRO=0
CTL_FIND_ABSENT=0  CTL_CR_COUNTER=1  CTL_ABSENT=ok
```

**The delivered file is byte-identical to its committed source.** `SHA` equals the
blob digest of `resources/orchestrator-prompt.md` at `25945d5` exactly, which is
also the value the v1.4.3 run recorded — the file is unchanged between releases.

**The 65-line claim is confirmed arithmetically as well as by measurement.** The
file is 65 lines, so a CRLF rendering would be exactly 65 bytes larger: 4342
against 4277. The box delivers 4277.

Four controls, because "CR=0" from a broken reader looks identical to "CR=0" from
a correct one: the CR counter reports 1 on a file holding one CR, a sibling path
that cannot exist reads absent, the search discriminates, and the read happened as
`clawuser` uid 1000 rather than as root or SYSTEM.

**The other three agents carry placeholders** at 997, 1000 and 1000 bytes, matching
the install log's three `[bootstrap] … placeholder` warnings exactly. Consistent
with the documented stub-agent behaviour; not a finding.

### 12.3 THE INSTRUMENT FAILED THREE TIMES FIRST, AND ONE WOULD HAVE BEEN A FALSE SHIP-BLOCKER

Recorded at length because it is the most transferable thing in this section.

**Revision 1 — controls recorded as ordinary rows.** The three canaries were
emitted with `Record` instead of `Register-Control`, so the phase ended with
`positive controls registered=0` and the runner **correctly downgraded every PASS
in it**: *"this phase registered NO positive control, so nothing it measured can be
reported as a pass."* The underlying 14.8 numbers were already clean. They were not
reportable, and the runner was right.

**Revision 2 — the wrong subject, and this is the dangerous one.** The probe
searched the whole distro filesystem for `orchestrator-prompt.md` and found
nothing. **That filename never exists inside the distro by design**: `bootstrap.ps1`
base64-streams the content to `~/.openclaw/agents/orchestrator/agent.md` and
atomic-renames it. Reported as written, that reading would have said **"the
orchestrator prompt never reaches the distro on v1.4.4"** — a false ship-blocker
against entirely correct behaviour.

**It VOIDed rather than FAILed, and that is the only reason the false reading never
left this file.** `BB.3` and `BB.4` were written to record VOID when no digest could
be read, because a measurement that could not be taken is not a product verdict.
Had they been written to FAIL on a missing file, this close-out would carry a
phantom regression.

**PROMPT 15 already names this rule and I did not apply it:** *"NAME THE REAL
SUBJECT. Where a control protects a specific location, the package must name that
location's real filesystem or path and require the measurement there."* It was
written after a Guard 4 probe answered YES on ext4 while the answer on the drvfs
mount that granted workspaces actually use was NO. This is the same error in a
different costume.

**Revision 3 — `find / -xdev`.** The filesystem-wide search stopped at mount
boundaries, so even a correctly-named file on another mount would have been missed.
Fixed by naming the delivered path directly.

**A fourth, caught before it ran:** the manifest generator initially used
`git rev-parse <commit>:<path>`, which returns the blob **object id** — a SHA-1 over
a header plus content — where the SHA-256 of the content was needed. It would have
mismatched all 54 rows while looking authoritative. Caught by reading the code
rather than by running it.

---

## 13. MATRIX ROW 10: the reboot pass. **PASS**, with two credential rows VOID

Row 10 has two legs and both ran after a real Windows reboot.

**Leg 1, phase 4 structural, `-PostReboot`:**

```
PASS=5 FAIL=0 VOID=2 INFO=0  (counted 7 of 7 recorded rows)
S.1.POSTREBOOT      PASS  No route to SMTP for uid 1000 at any destination
S.1ctlA.POSTREBOOT  PASS  CONTROL (must succeed): allowlisted 443 connects
S.1ctlB.POSTREBOOT  PASS  CONTROL (must fail): non-allowlisted 443 blocked
S.1ctlC.POSTREBOOT  PASS  CONTROL (must succeed): the probe can observe a real listener
S.4.POSTREBOOT      VOID  Credential unreadable by the agent uid
S.4leak.POSTREBOOT  VOID  Credential value absent from logs, receipts, errors, process listing
```

**The structural claim survives a real reboot**, measured consumer-side with
calibration in both directions in the same run.

**The two VOIDs are the same absent-credential precondition as row 14**, and this
is now the third place it has surfaced: `G2.10`, row 14, and `S.4`. **One cause,
three symptoms**, and box D closes all three by installing with a credential
configured.

**Leg 2, toolchain `-PostReboot`:**

```
PASS=30 FAIL=0 VOID=0 INFO=0  (counted 30 of 30 recorded rows)
positive controls registered=7 fired=7
preconditions declared=1 met=1
PHASE VERDICT: PASS.
```

**A clean sweep after a reboot.** The egress firewall, the toolchain toggle, the
five-hourly refresh behaviour, the tripwire and the agent's inability to change its
own switch all hold across a real Windows restart.

### 13.1 `TC.1c` passed after the reboot, and it still does not retire `#261`

```
TC.1c.POSTREBOOT  PASS  With the switch ON, the software sources are reachable for uid 1000
                        github and npm reachable=True
```

This row **FAILed on the v1.4.0 baseline** and is the `#261` intermittency residual,
previously measured at 2 of 6 attempts after a reboot and 5 of 12 before one.

**It passed here. That is one sample.** `#261` is a claim about *intermittency*
against services answering from a rotating address pool while the firewall holds a
resolved snapshot. One PASS and one FAIL are both consistent with the residual as
documented. **`#261` stays open**, and closing it needs a repeated-attempt
measurement, not another single reading.

The agent also completed a real turn after the reboot, returning `TOOLCHAINONOK`
with real token usage — a third independent observation that the 22:52:12
`gate_error` was transient.

### 13.2 Section 14.10, the logon half: **PASS, observed by a human**

> **Does a console window flash open and disappear at logon?** — **No.**

Reported by the operator at a fresh post-reboot logon.

**This is the first time this assertion has ever been taken.** It was deferred in
v1.4.3 and in every earlier run, because it can only be observed by a person at the
moment of login and no run had a human watching for it. `wsl-keepalive.vbs` runs
through `wscript` precisely so it is silent, and it is now confirmed silent by
observation rather than by reading the invocation.

The automated half of 14.10 — the scheduled task exists, is Ready, has run at exit
0, the `.vbs` is CR=0 and a WSL session is held — is **still owed** and is a
candidate for the same box before teardown.

---

## 14. MATRIX ROW 11: the ten by-hand Studio panel checks. **PASS**

Run by the operator over RDP, with screenshots retained as the evidence. **Nine of
ten checks PASS outright; `5d` records VOID with a named reason.** No product defect
was found by any of the ten.

| Check | Subject | Verdict |
| --- | --- | --- |
| 1a–1d | the software-sources card, its button, its count line, its paragraph | **PASS** |
| 2a | the footnote, word for word | **PASS** |
| 3a–3c | adding a destination | **PASS** |
| 4a–4c | three malformed inputs refused | **PASS** |
| 5a–5c | removing a destination | **PASS** |
| 5d | one seeded entry must remain | **VOID**, see 14.2 |
| 6a–6e | the home route and its header | **PASS** |
| 7a–7b | the footer, both halves | **PASS** |
| 8a–8f | the toggle, off and on, both messages | **PASS** |
| 9a–9e | all seven not-in-this-release panels | **PASS** |
| 10a–10c | both ways back to the home route | **PASS** |

### 14.1 The three readings that carry the most weight

**Check 1d and check 8b are the same claim from two different pieces of copy**, and
until v1.4.1 they contradicted each other on the same screen three lines apart. Both
now carry the honest version, quoted from the operator's screenshots:

> paragraph (1d): *"It does not stop skill installation: the skill hub shares a
> network address with ClawFactory's own site, which stays reachable and which this
> switch does not cover."*

> switch-off message (8b): *"Your agent can no longer fetch code from GitHub or npm.
> **This does not stop skill installation**: the skill hub shares a network address
> with ClawFactory's own site, which this switch does not cover. Its AI provider is
> unaffected."*

The old message said the switch **did** stop skill installation. That was measured
false on cfv-169 by completing a real `openclaw skills install` with the switch off.
**Check 1 could never have caught it, because check 1 only reads the paragraph.**
Both are now correct and both were transcribed rather than judged.

**Check 2a carries the clause that matters most:**

> *"Matching is by network address rather than by name, so allowing a site also
> allows anything else served from the same address."*

The previous version omitted it and mentioned only the provider, **understating the
residual in the direction that flatters the product**. It is present.

**Check 10 closes a defect the operator himself reported twice.** Until v1.4.1 the
lobster was a bare `<span>` and the title a plain `<h1>` with no Home entry in the
nav, so once you left the home route there was no click path back. It went into the
v1.3.5 close-out and was never carded; he hit it again by hand on cfv-174 while
following this very file. **Both halves now work**: the lobster and the title text.

### 14.2 `5d` is VOID, and the checklist is what is wrong

Check 5d asserts that after removing `docs.python.org` **one entry remains**, seeded
from root tooling before the operator starts, so the panel has a persisted entry to
render at load rather than only one it just added itself.

**No entry was seeded on this box.** The panel correctly reads
`Nothing allowed yet, so your agent cannot read any website.`

**This was caught BEFORE the check was handed to the operator**, by reading the
checklist against the first screenshot rather than by trusting it. Had it been sent
as written, it would have produced **a FAIL against correct behaviour** — the same
shape as the `On. 28 network addresses` defect this file already carries a correction
for.

**The seeding step belongs to a driver that this run does not use.** `5d` is recorded
VOID with that named reason, and the checklist is the thing that needs fixing:
either the step becomes part of the phase that stages the box, or the check states
its own precondition. **Carded, not patched mid-run.**

The property `5d` exists to prove — that the panel renders a *persisted* entry at
load, not merely one it added in the same session — **remains unmeasured on this
box** and is owed.

### 14.3 What the by-hand pass found that no automated phase could

Nothing failed, and that is worth stating precisely rather than as a shrug. Four of
these are unautomatable in principle:

* **Check 9's absence assertion** — that none of the seven panels says `scaffold`,
  `/api/`, `backend` or `unreachable`. A blank page would satisfy the absence
  perfectly, which is why `9a`–`9d` are presence checks first and `9e` clicks a link
  to prove the panels behind them are real. The operator's Workspace screenshot shows
  a genuinely working panel with three populated sections, not another stub.
* **Check 6g** — that the version string and the word `Templates` are visibly
  separated rather than rendered as `v1.3.2Templates`. That is a pixel question.
* **Check 10** — that a click path home exists at all.
* **Section 14.10's logon half** — recorded in section 13.2.

---

## 15. A REAL PRODUCT DEFECT, found by a human looking at a screen

**This is the only product defect box A found, and no automated phase in this
suite could have found it.** It was found by the operator reading the
`rename-agent.ps1` dialog during the row 11 by-hand pass.

### 15.1 What the customer sees

The dialog renders as:

```
ClawFactory a-EUR" Rename Your Assistant                       <- title bar
ClawFactory ships four role-based agents a-EUR" Orchestrator,
Scout, Builder, Publisher a-EUR" that work together as a "skill factory."
A single-agent installer variant a-EUR" which fully supports
personal-assistant renaming a-EUR" is planned for a future release.
```

(The mojibake is transcribed here in ASCII; the operator's screenshot holds the
literal bytes.) Every em dash is replaced by three garbage characters, in a
dialog whose entire purpose is to explain a product decision to a customer.

### 15.2 Root cause, measured rather than guessed

```
resources\rename-agent.ps1
  FIRST_3_BYTES=91,67,109
  HAS_UTF8_BOM=False
  UTF8_EMDASH_SEQUENCES=7
  MOJIBAKE_OCCURRENCES_WHEN_READ_AS_ANSI=7
```

The file is **UTF-8 without a BOM**. **Windows PowerShell 5.1 decodes a BOM-less
`.ps1` as the ANSI codepage**, so the three UTF-8 bytes of an em dash (`E2 80 94`)
are read as three separate Windows-1252 characters. The count matches exactly: 7
sequences in the file, 7 mojibake occurrences when decoded the way PowerShell
actually decodes it.

**This is NOT a delivery defect and section 14.8 is not contradicted.** The file
on the box is byte-identical to its committed blob — 14.8 proved that, and it is
still true. **The bytes are delivered perfectly; the file is authored in an
encoding its own interpreter does not read.**

### 15.3 Scope: a class across five shipped scripts, and which occurrences a user sees

The instance was swept as a class rather than patched as a one-off:

| File | BOM | total | in code/strings | in comments |
| --- | --- | --- | --- | --- |
| `rename-agent.ps1` | **no** | 7 | **5** (lines 21, 25, 29) | 2 |
| `bootstrap.ps1` | **no** | 6 | **2** (lines 128, 226) | 4 |
| `launcher.ps1` | **no** | 4 | 0 | 4 |
| `post-install.ps1` | **no** | 3 | 0 | 3 |
| `setup.ps1` | **no** | 1 | 0 | 1 |

**Seven user-visible occurrences across two files.** The distinction matters and
is measured per occurrence rather than asserted per file: a mojibake in a comment
is invisible to the customer and is tidiness; one in a displayed string is a
defect the customer reads.

The two in `bootstrap.ps1` are both user-visible and were checked individually
rather than assumed:

* **line 128** sits inside the placeholder `agent.md` body that is written into
  the distro for the three stub agents, so the mojibake lands in a prompt file.
* **line 226** is a `Write-BootstrapLog WARN` line, so it reaches the console and
  the install log.

`launcher.ps1`, `post-install.ps1` and `setup.ps1` carry the same latent hazard in
comments only. **They are not customer-visible today**, and they are one edit away
from becoming so.

### 15.4 Severity, stated plainly

**Cosmetic, not a security or containment defect.** Nothing about the sandbox, the
firewall, the guards or the gateway is implicated. The dialog's *meaning* survives;
it just looks broken.

**It is nonetheless a shipping defect in a product whose entire pitch is that it
tells you the truth carefully.** A customer's first impression of a considered
explanation is that the software cannot render a dash.

### 15.5 The fix, and the gate that should have caught it

The fix is to save the affected files as **UTF-8 with BOM**, which PowerShell 5.1
reads correctly, or to avoid non-ASCII punctuation in shipped scripts entirely.

**The build has nine gates and none of them looks at encoding.** The interpolation
gate added in v1.4.4 parses every shipped `.ps1` with the PowerShell parser — it
would be the natural home for a tenth check: *no shipped `.ps1` may contain a
non-ASCII byte unless it carries a UTF-8 BOM.* That is a byte-level assertion,
cheap, and canary-able in the same shape as the existing gates.

**Carded, not fixed here.** Fixing shipped bytes mid-validation would invalidate
every measurement taken against this artifact, including section 14.8's 54 of 54.

### 15.6 The defect reproduced inside the instrument investigating it

Recorded because it is the sharpest available demonstration of the failure mode.

The first version of the scope-analysis script searched for the mojibake by
writing the literal characters into a `.ps1`. That script was itself saved without
a BOM, PowerShell re-mangled its search string, and it died with a parse error
before measuring anything. **The bug corrupted the tool built to measure the bug.**

The rewrite contains no non-ASCII literal at all and works on raw bytes.

---

## 16. TASK 2.3, 2.4, 2.5: the provider switch. Proven, with one assertion VOID rather than FAIL

```
PASS=16 FAIL=1 VOID=0 INFO=2  (counted 19 of 19 recorded rows)
positive controls registered=6 fired=6
preconditions declared=1 met=1
PHASE VERDICT: FAIL. Failing checks: WR.5
```

### 16.1 What the run actually shows

`switch-provider.ps1` **completed**:

```
Switched to ollama. Gateway restarted automatically; switch is live.
exit=0   strictmode-death=False
WR.5 firewall after:  FW_TABLE=1  FW_ALLOWED_V4=30  FW_TOOLCHAIN_V4=27
                      FW_SEED_HOSTS=9  FW_CTL_FAKESET=ok_fake_set_not_found
```

* **`strictmode-death=False`** — the v1.4.3 ship-blocker is fixed on a clean
  install. That script died on four unescaped `$baseHosts` in comments, for every
  provider, before applying anything.
* **The firewall change landed**, and `FW_TOOLCHAIN_V4=27` is untouched — the
  precise property commit `3818bc0` exists to protect.
* **The reader is controlled**: a set that cannot exist is not found.

### 16.2 Why `WR.5`'s FAIL is an unobservable assertion, and the reasoning is not an excuse

`WR.5` failed on one sub-assertion: `guard-ran=False`.

**The v1.4.4 close-out predicted exactly this, before this run existed.** Section
4A.2 of that document records that `Invoke-WslBashBlock` assigns the WSL call to
`$null`, discarding the payload's **stdout**; the toolchain guard echoes its
*confirmation* to stdout and its *FATAL* to stderr with `>&2`. **So the guard can
report that it stopped something and cannot report that it checked.**

`guard-ran=False` is therefore consistent with both "the guard ran and passed
silently" and "the guard never ran". **An assertion that cannot discriminate
between those two is not a FAIL, it is a VOID**, and recording it as a FAIL
attributes an instrument limitation to the product.

**The discriminating evidence is `WR.6`, and it PASSED:**

```
WR.6  PASS  the fail-closed toolchain guard refuses to write a toolchain host
            into the unrevocable allowlist
```

The guard demonstrably exists, is wired, and refuses when it should. That is a
separate invocation with an injected fault, and it is the row that carries the
claim.

**Stated so it cannot be read as explaining away a failure:** if `WR.6` had also
failed, `WR.5` would stand as a product FAIL and this section would say so.

### 16.3 The three TASK 2 items this settles

| Item | Verdict | Evidence |
| --- | --- | --- |
| **2.3** switch-provider completes, applies its firewall change, leaves the toolchain set untouched | **PASS** | exit=0, no StrictMode death, `FW_TOOLCHAIN_V4=27` either side, reader controlled |
| **2.4** the fail-closed toolchain guard refuses | **PASS** | `WR.6` |
| **2.5** the Ollama honesty line | **PASS** | `WR.5b`, and it proved itself on a real failure rather than a rigged one |

**2.5 is worth quoting**, because Ollama genuinely could not install on this box
and the script told the truth about it:

```
bash: line 1: ollama: command not found
WARNING: Ollama is NOT installed in the sandbox, so the agent will have no model
to talk to. The install step above failed; the firewall change below still
applies. Install Ollama and run this script again.
```

v1.4.3 printed `[x] Ollama running with model llama3.1:8b` at exactly that point.

### 16.4 A harness finding, carded

`WR.5` should record VOID with a named reason rather than FAIL, because its
`guard-ran` assertion is unobservable by construction. Two candidate fixes, and
the second is better: stop discarding the payload's stdout in
`Invoke-WslBashBlock`, so the guard's confirmation becomes observable and the
assertion becomes real. That closes the diagnosability gap the v1.4.4 session
carded rather than working around it.

---

## 17. Section 14.10 COMPLETE: the keepalive, both halves

```
TASK_PRESENT=True  TASK_STATE=Ready  TASK_LASTRESULT=0
TASK_LASTRUN=08/28/2026 16:29:27
TASK_ACTION=wscript.exe "C:\Program Files\ClawFactory\resources\wsl-keepalive.vbs" Ubuntu clawuser
CTL_FAKE_TASK_PRESENT=False
VBS_BYTES=764 VBS_CR=0
WSL_PROCESSES=6
WSCRIPT_PROCESSES=0
```

**PASS.** The scheduled task exists, is Ready, and **has actually run at exit code
0 after the reboot** — the timestamp is post-restart. The `.vbs` on the box is
`CR=0`, so the **LF form is what executes** rather than merely parses.
`WSL_PROCESSES=6` shows a session is genuinely held. `WSCRIPT_PROCESSES=0` is
expected and documented: `wsl.exe` is reparented from `wscript`, which then exits.

**Control:** the same query against a task name that cannot exist finds nothing, so
`TASK_PRESENT=True` means the task rather than meaning the query answers anything.

**The by-hand half is section 13.2** — no console window flashed at logon, observed
by the operator at a fresh post-reboot login. **Both halves are now measured, and
this item has never been complete on any previous run.**

---

## 18. THE REMOVEALL UNINSTALL BRANCH. Everything removed but one running binary

Run last, through the real dialog, by the operator. It destroys the install, which
is why nothing is measured on this box afterwards.

### 18.1 The dialog, quoted, because its copy is the thing being shipped

```
Also remove the Ubuntu Linux distro that ClawFactory created?

ClawFactory is removed from this machine either way: the agent, its configuration
and plugins, clawuser's home directory, the OpenClaw runtime, every ClawFactory
service and firewall rule.

YES also unregisters the Ubuntu distro and deletes its disk image (about 6 GB).
Choose this unless something else on this machine uses that distro.

NO leaves the now-empty Ubuntu distro registered, so anything else that shares it
keeps working. You can install ClawFactory again later and it will reuse the distro.

Your ClawChat conversation history is stored on Windows, under %APPDATA%\ClawChat,
and neither choice deletes it.
```

**This copy is correct and honest**: it states what happens on both paths, names the
disk cost, gives a decision rule, and discloses that conversation history survives
either choice. **It renders with no mojibake**, because it uses ASCII punctuation —
the same class of text as the `rename-agent.ps1` dialog, authored correctly. That
contrast is the clearest available evidence that section 15's defect is an encoding
accident rather than a house style.

`YES` was chosen. Elapsed time: **about one minute**.

### 18.2 The read-back. One residual, fully explained

```
LEFT C:\Program Files\ClawFactory  files=1
   C:\Program Files\ClawFactory\ClawChat.exe
GONE C:\ProgramData\ClawFactory
SCHEDTASK_PRESENT=False
FIREWALL_RULES_LEFT=0
UNINSTALL_KEYS_LEFT=0
DISTRO_VHDX_LEFT=0
SHORTCUTS_LEFT=0
CTL_CANNOT_EXIST=False        <- the path probe discriminates
CTL_FAKE_PROC=0               <- the process probe discriminates
```

and from the operator's own session, which is the only context that can see a
per-user distro registration:

```
C:\Users\clawadmin>wsl -l -v
Windows Subsystem for Linux has no installed distributions.
```

**The distro is unregistered and its disk image is deleted.** The one-minute
elapsed time was real work, not a skipped step: `DISTRO_VHDX_LEFT=0` over a
recursive search of `C:\Users`.

**Everything the dialog promised is gone**: the configuration directory, the
scheduled task, every firewall rule, every uninstall registry key, every shortcut,
and the distro.

### 18.3 Why `ClawChat.exe` survived, confirmed from two independent directions

```
CLAWCHAT_RUNNING_NOW=1   PID=7116   START=08/28/2026 16:24:21
CLAWCHAT_EXCLUSIVELY_LOCKABLE=False (something holds it)
```

The process start time **precedes the uninstall**, and the file cannot be opened
exclusively, so it is still held. Independently, **the operator reported without
being asked that the app was open when he clicked uninstall.**

**Windows will not delete a running executable.** This is the operating system, not
a flaw in the removal logic, and no amount of uninstaller code removes a file the
kernel has mapped.

### 18.4 Verdict, and the one thing worth carding

**The removal itself is correct.** Every item the dialog names is gone; the single
residual is a locked binary with an external cause, and **no orphaned shortcut
points at it** (`SHORTCUTS_LEFT=0`), so the user is not left with an icon that
launches a broken app.

**The message is honest, and that is worth saying plainly given this release's
history:**

```
ClawFactory Secure Setup uninstall complete.
Some elements could not be removed. These can be removed manually.
```

**It under-claims rather than over-claims.** That is the exact opposite of the
defect that made v1.4.3 a NO, where the kill switch printed a success banner over
two commands that had failed. Here the product did nearly everything and told the
user it had not done everything.

**The gap, and it is a real one: it does not say WHICH elements.** A user is told
"some elements" and left to guess. It also does not tell them the likely cause —
that a ClawFactory app was running — or offer to close it first. Both are cheap:
the uninstaller knows which deletes failed, and could name the file and suggest
closing ClawChat and re-running.

**Carded as a diagnosability and UX improvement, not as a defect in removal.**

### 18.5 What this does and does NOT establish

**Establishes:** the RemoveAll branch removes what it says it removes, on a clean
v1.4.4 install, after a reboot and a full validation pass, with the distro
unregistered and its image deleted.

**Does NOT establish, and is explicitly not claimed:**

* **The keep-Linux branch (`No`).** Untouched here. That is v1.4.2's change set,
  it has never been measured on any release, and it is **box D's headline**.
* **A reinstall after this uninstall completes.** Not attempted; also box D.
* **The teardown log's `CLAWFACTORY_TEARDOWN_OK` marker and its `READBACK` line.**
  Not retrieved — the box was torn down after this read-back and the log lives on
  it. Owed.
* **The fault-injected negative half** — that the uninstaller reports failure and
  shows a dialog when the teardown genuinely cannot complete. Owed, box D.
* **The 16-row structured RemoveAll phase.** What is recorded here is a read-back
  of the resulting state, not `interim-v141-uninstall.ps1` executed under the phase
  runner. **The rows are therefore evidence, not phase-runner verdicts**, and they
  carry no registered controls beyond the two discrimination probes quoted above.
  That distinction is stated rather than blurred.

---

## 19. TEARDOWN. Verified by re-read, not by the delete commands' exit codes

Deleted by explicit name, **NIC first** because it references the public IP and
the NSG:

```
az vm delete            cfv-179          -> exit 0
az network nic delete   cfv-179VMNic     -> exit 0
az network public-ip delete cfv-179-pip  -> exit 0
az network nsg delete   cfv-179-nsg      -> exit 0
az disk delete          cfv-179-osdisk   -> exit 0
```

**"It said deleted" and "it is gone" are different claims**, so the estate was
re-read unfiltered:

```
=== az resource list -g clawfactory-validation, UNFILTERED ===
clawfactoryvalc467              Microsoft.Storage/storageAccounts
bake-vmVNET                     Microsoft.Network/virtualNetworks
clawfactory-win11-baseline      Microsoft.Compute/images
clawfactory-win11-baseline-v2   Microsoft.Compute/images

=== az vm list -d, SUBSCRIPTION-WIDE ===   NO_VMS_ANYWHERE=True
disk: EMPTY   nic: EMPTY   pip: EMPTY   nsg: EMPTY
CFV179_RESOURCES_REMAINING=0
```

**Exactly the expected residual: the storage account, the VNET and the two
baseline images.** No propagation race was observed; the resources were gone on
first re-read.

**One instrument note, because an errored `az` command's empty output is not
evidence.** The first subscription-wide `cfv-179` sweep used a `contains()` query
and returned **exit 255** with `].[name was unexpected at this time.` — the
standing `az.cmd` trap, where `cmd.exe` re-parses the parentheses. Had the exit
code not been checked, a parse failure would have read as "nothing found", which
is precisely the answer the sweep was hoping for. Re-derived with a paren-free
query and filtered locally: **0 resources remaining.**

**RDP rule scope, as TASK 6 requires**: `67.164.251.99/32`, port 3389, Allow,
Inbound, on `cfv-179-nsg`. Never `0.0.0.0/0`. Created at provisioning, verified by
read-back twice, and **deleted with the NSG.**

**Nothing is billing compute.** The validation container retains the artifact blob
and the staged phase scripts as evidence, which is storage, not compute.

---

## 20. NO FITNESS-TO-PUBLISH VERDICT

By instruction, and it would be unsupportable regardless.

**Box A is one box of four, and three of the four have not been provisioned.**
Boxes B, C and D carry matrix rows 2 and 4, and the entire keep-Linux uninstall
change set — **which is v1.4.2's work and has never been measured on any
release.** A verdict now would rest on an unmeasured premise.

**What can be said without a verdict:**

* **The two defects that made v1.4.3 a NO are fixed and measured on a clean
  install**, with controls that fired: the kill switch genuinely stops the gateway
  and refuses to claim success when it cannot verify, and `switch-provider.ps1`
  runs at all.
* **Section 14.6 is closed by the same fix**, because a working kill switch is
  what made a genuinely-down gateway achievable.
* **Nothing measured in box A is a regression.**
* **One product defect was found**, section 15, and it is cosmetic.
* **Box A itself is complete except for the items listed in 21.2.**

---

## 21. End-of-session gate, day 2

### 21.1 Final task accounting

| Task | State |
| --- | --- |
| TASK 0.1 plan before `az vm create` | **DONE**, section 4 |
| TASK 0.2 the two named fixes | **DONE** `cef6cbd`, `b11c2c5` |
| TASK 0.2 wider enumeration + canary | **DONE**, sections 2, 2.2, plus a sixth class in 2.5a |
| TASK 0.3 upload verified by download and re-hash | **DONE**, section 1 |
| TASK 0.4 starting estate | **DONE**, section 3 |
| TASK 1 phase order | **DONE**, one recorded deviation in 6.1 |
| TASK 2.1 kill switch from a clean install | **PASS**, 8I.1 |
| TASK 2.2 refuses to claim success unverified | **PASS**, 8I.2 |
| TASK 2.3 switch-provider completes | **PASS**, 16.3 |
| TASK 2.4 fail-closed toolchain guard refuses | **PASS**, `WR.6`, 16.3 |
| TASK 2.5 Ollama honesty line | **PASS**, `WR.5b`, 16.3 |
| TASK 2.6 the other wrapper rows | **PASS**, 8I.3; `rename-agent` by hand, section 15 |
| TASK 3.1 section 14.8 | **PASS**, 12.1 |
| TASK 3.2 section 14.9 | **PASS**, 12.2 |
| TASK 3.3 section 14.10 | **PASS**, both halves, sections 13.2 and 17 |
| TASK 3.4 section 14.11 | **PASS** execution half; **CR census owed**, 21.2 |
| TASK 3.5 section 14.6 | **PASS**, 8I.4 |
| TASK 3.6 14.12 build-time, not sought on the box | **DONE** — correctly not attempted |
| TASK 4 operator handoffs | **DONE**, five cards, all with real values |
| TASK 5 standing traps | Followed; six hit and each recorded |
| TASK 6 teardown | **DONE**, section 19 |
| TASK 7 close-out | this file |

### 21.2 What box A still owes

| Owed | Why |
| --- | --- |
| **Section 14.11's CR census** on the shipped Windows-side `.ps1` files | the execution half is covered by `WR.1/7/8/9`; the per-file CR count on the box was never taken separately |
| **`PG.3f`**, the installer's loud abort | costs a full install; belongs to box B or C |
| **The 16-row structured RemoveAll phase** | what was taken is a read-back, not `interim-v141-uninstall.ps1` under the phase runner. See 18.5 |
| **The teardown log's `CLAWFACTORY_TEARDOWN_OK` and `READBACK` line** | lives on a box that no longer exists |
| **Row 14 and the three credential VOIDs** | one cause: no SMTP credential. Box D |
| **`5d`**, that the panel renders a *persisted* entry at load | the seeding step belongs to a driver this run does not use. See 14.2 |
| **`#261`** | one PASS pre-reboot and one post-reboot is two samples against a rotating pool |

### 21.3 Resource ledger, final

| | |
| --- | --- |
| VMs provisioned | **1**, `cfv-179` |
| VMs running now | **0** |
| VMs deleted | **1**, with all four orphans and the VMAccess extension |
| Estate after teardown | storage account, VNET, two baseline images. **Verified by unfiltered re-read** |
| Compute window | roughly 14:32–17:36 day 1 and 08:20–10:45 day 2, about **5.5 hours** at ~$0.10/hour, so **about $0.55**, plus one night of a Premium OS disk |
| Licence slots | none consumed; no licence check exists since v1.4.0 |

**Credential hygiene.** No password was generated, printed, requested or set by this
session. `az vm user update` was called **once, by the operator, at Card 1**, which
is the one sanctioned use; this session never called it. The provider key was
reported only as `provider key present (value never printed)`. The gateway token's
**length only** reached a transcript. **No secret value appears in any evidence
file, commit or message.**

### 21.4 Delta security sweep

**No product code was changed by this session.** Committed: two stale-default fixes
in `validation/`, two new validation probes, and this close-out.

* `interim-v144-gatediag.ps1` and `interim-v144-bundlebytes.ps1` are **not bundled**
  and do not ship.
* **Every injected fault was removed and each removal verified**: `PG.2d` restored
  the provider route, `SP.7b`/`7e` the seed, `TC.8b` left the firewall intact,
  `TC.9` the shipped default state, `WR.4` injected into a copy rather than the
  shipped file, and `BB` removed its canary directory.
* **The artifact validated is byte-identical** to the one built at `25945d5` and
  signed as `6e655603…`. Sections 14.8 and 14.9 prove it on the installed machine.
* **One defect found and NOT fixed**, deliberately: section 15's encoding class.
  Fixing shipped bytes mid-validation would invalidate every measurement taken
  against this artifact.

### 21.5 Delta bug review

Instrument defects in this session's own work. **Eight, and five were mine on day
two alone.**

1. **gatediag rev 1 read a nonexistent token path** — both turns `Unauthorized`.
2. **…and scored that as a PASS**, testing only for the absence of a blocked flag.
   **A turn that never ran read as a turn that was not blocked.**
3. **…and asserted on an invented unit name.** `systemctl is-active` on a
   nonexistent unit reports inactive, **indistinguishable from a stopped service**.
   Would have reported a healthy proxy as down.
4. **…and measured the toolchain switch after `TC.9` had restored it.**
5. **bundlebytes rev 1 recorded controls with `Record` instead of
   `Register-Control`**, leaving the phase with zero registered controls. The runner
   correctly downgraded every PASS.
6. **bundlebytes rev 2 searched the distro for `orchestrator-prompt.md`**, a name
   that by design never exists there. **Reported as written that was a FALSE
   SHIP-BLOCKER.** It VOIDed instead of FAILing, which is the only reason it never
   left the file.
7. **The manifest generator used git's blob object id where SHA-256 of content was
   needed** — would have mismatched all 54 rows while looking authoritative. Caught
   by reading, before running.
8. **The encoding-scope script reproduced the very defect it was measuring**,
   section 15.6.

**Plus two shell-level slips**: a bare leaf name where the dispatcher takes a path
(threw before touching the box), and a heredoc that failed to parse and wrote
nothing (caught by checking `git status` rather than assuming).

**The pattern is one thing, and it is the same thing every time: a check that
passes, or fails, without measuring its actual subject.** Three of the eight would
have produced false findings — a phantom dead gateway, a phantom broken send path,
a phantom missing prompt. **All three were caught by the phase runner's rules being
applied to my instruments as rigorously as to the product**, and by PROMPT 15's
"name the real subject" clause, which I violated and which already existed because
of an earlier violation of the same kind.

**The product looked better than my instruments all session.** That is the honest
summary of day two.

### 21.6 Cards

**Moved only as far as box A's evidence supports.**

| Card scope | Recommendation |
| --- | --- |
| kill switch fix (`#289`–`#292` family) | **Evidence complete for box A.** Proven from a clean install, both readers, fault-landed control. Closeable on this evidence |
| `switch-provider.ps1` fix | **Closeable.** `WR.5b`, `WR.6` and the firewall read-back carry it; `WR.5`'s FAIL is an unobservable assertion, section 16.2 |
| documentation / structural table | no box-A runtime evidence either way |
| anything scoped to uninstall | **STAYS OPEN** — box D |
| `#261` | **STAYS OPEN** — two samples |

**Five new cards owed from this session:**

1. **The encoding class**, section 15 — 5 shipped scripts BOM-less, 7 user-visible
   mojibake occurrences, plus a proposed tenth build gate.
2. **Phase 3 declares no precondition** and reports FAIL where PROMPT 15 requires
   VOID, section 8G.4.
3. **`Invoke-WslBashBlock` discards payload stdout**, so the toolchain guard cannot
   report that it checked — this made `WR.5` unobservable, section 16.4.
4. **The uninstaller does not name which elements it could not remove**, nor
   suggest closing ClawChat, section 18.4.
5. **`MANUAL_CHECKS_studio.md` check `5d` assumes a seeding step** no current driver
   performs, section 14.2.

**A sixth, lower priority:** six drivers carry stale `$VmName` defaults naming
deleted boxes, section 2.5a. All fail safe.
