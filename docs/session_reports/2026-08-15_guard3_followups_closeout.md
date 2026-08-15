# Guard 3 follow-ups: harness hardening, version discipline, the toolchain toggle. Close-out, 2026-08-15.

Dispatch card #245. Track: v1 fast-security-harness.

Input: Secure-Setup at `9b3bbee`, Studio at `34c9947`, artifact `6282a228...`.
Output: Secure-Setup `TBD`, Studio `229ad26`, artifact `5bef35dc...` (v1.3.3).

---

## 1. What was done, in the order the job required

The job set the order deliberately: harness first, because a run made with a
broken harness produces another set of unaudited results; version second, because
the bump ripples through the harness; the toolchain toggle third; copy fourth.
That order was followed.

| # | Item | Outcome |
| --- | --- | --- |
| 2 | Harness hardening, proven against injected faults | **DONE**, 10/10 on the build machine and again on the box |
| 3 | Version discipline: a ledger the gate enforces | **DONE**, proven both directions, and it then fired for real three times |
| 4 | Toolchain access toggle | **NOT READY TO SHIP.** Firewall behaviour validated (27 PASS); one validated defect remains, see 8.5 |
| 5 | Web access footnote, header spacing, stale banner | **DONE**, shipped in Studio 1.3.0 |
| 6 | Card #197 probe | **DONE**, and the answer is not the one the first probe gave (section 9) |
| 7 | Build and validate | **DONE**, four builds, three VMs, and the run found three of my own defects |

**The headline, stated plainly.** Three of the four items are finished. The
toolchain toggle is not, and the reason it is not is that this session's own
validation caught it: the toggle's firewall behaviour is correct and thoroughly
proven, but switching it off currently stops the agent working, which is not what
the panel says it does. Details in 8.5. Nothing was tagged or published.

---

## 2. The scoping report the job asked for before any toggle code

Section 1 required a stop-and-report if the toolchain toggle turned out to be
more than the read-fetch machinery reapplied.

**It was not.** Every piece had a validated counterpart: a second flushed-and-rebuilt
nft set, a root-owned resolver, a boolean in the same root-owned policy file, the
same 0750 `clawfactory-fetchctl` write path, the same three-layer validation, the
same tripwire.

One thing was genuinely new and was named before writing code: the toolchain hosts
had to be **removed** from `allowed_ipv4` in the two places `AUX_HOSTS` appears. If
they had stayed, the toggle would silently do nothing. That is a subtraction from an
existing list, not new machinery, so the scope held.

---

## 3. Harness hardening

### 3.1 What is now mechanical rather than habitual

`validation/interim-v120-phaselib.ps1` is a phase runner every phase dot-sources.
The L29 rules are properties of the runner:

- a phase that registers **no positive control** cannot report PASS
- a phase whose positive control **did not fire in the same run** reports VOID, and
  its passes and failures are downgraded with it
- a declared **precondition** that is absent records VOID with a **named reason**
- a **held copy** of a list is compared against what the product reports, as a
  first-class call
- a **search for absences** must first prove its target is searchable

**Two kinds of VOID**, kept apart because collapsing them loses what a reader needs.
An *instrument-level* void (no control, unfired control, unmet precondition) means
the instrument was never shown to work, so every measurement is unsafe including the
failures, and all rows downgrade. A *row-level* void means one check was untakeable
while the rest measured fine, so those rows stand and only the phase pass is
withheld. Either way the phase does not exit 0.

**Exit 4 for VOID**, neither 0 nor 1. A driver that reads VOID as a pass repeats the
exact failure this work exists to stop; one that reads it as a product failure
manufactures defects out of harness gaps.

### 3.2 The four injected faults, verbatim

Run on the build machine against the real library. `validation/harness-selftest.ps1`.

```
===== HARNESS SELF-TEST: four injected faults =====

Library under test: C:\Users\bmcki\ClawFactory-Secure-Setup\validation\interim-v120-phaselib.ps1

--- BASELINE (no fault injected): a healthy phase must still report PASS ---
  [PASS] SELF.0 :: BASELINE: a healthy phase still reports PASS (the runner is not simply voiding everything)
        rc=0 PhaseVerdict=PASS

--- FAULT 1: precondition removed (no SMTP credential) ---
  [PASS] SELF.1 :: FAULT 1: a missing precondition yields VOID with a NAMED reason, and no PASS and no FAIL
        rc=4 PhaseVerdict=VOID pass/fail rows=0 reason=this phase registered NO positive control, so nothing it
        measured can be reported as a pass / precondition not met: F1.PRE an SMTP credential is configured --
        no SMTP credential on this box, so the send queue is empty and a refusal cannot be told apart from
        having nothing to refuse / a check could not be measured: F1.PRE PRECONDITION: an SMTP credential is configured

--- FAULT 2: positive control removed from an otherwise-passing phase ---
  [PASS] SELF.2 :: FAULT 2: a phase with no positive control cannot report PASS, and its passes are downgraded
        rc=4 PhaseVerdict=VOID downgraded PASS->VOID=2 reason=this phase registered NO positive control, so
        nothing it measured can be reported as a pass

--- FAULT 2b: positive control present but it did NOT fire ---
  [PASS] SELF.2b :: FAULT 2b: a registered control that did not FIRE voids the phase too
        rc=4 PhaseVerdict=VOID reason=positive control did not fire: F2b.CTL the probe can reach a known-good target

--- FAULT 3: search target replaced with a compressed blob ---
  built a compressed fixture: 88 B from 2000 B of text
  [PASS] SELF.3 :: FAULT 3: an unsearchable target voids the phase, and the "absent" result is NOT reported clean
        rc=4 PhaseVerdict=VOID F3.1 verdict=VOID (was PASS)

--- FAULT 3 CONTROL: the same search over a readable payload must PASS ---
  [PASS] SELF.3c :: FAULT 3 CONTROL: the identical search over a readable payload reports PASS (the assertion discriminates)
        rc=0 PhaseVerdict=PASS

--- FAULT 4: independent list edited to disagree with the product ---
  [PASS] SELF.4 :: FAULT 4: a disagreeing independent copy FAILS, and the evidence names BOTH numbers
        rc=1 PhaseVerdict=FAIL F4.1=FAIL evidence=this probe enumerates has 30; the installer claims reports 33.
        They disagree, so one of the two is stale. The disagreement IS the finding.

--- FAULT 4 CONTROL: agreeing copies must PASS ---
  [PASS] SELF.4c :: FAULT 4 CONTROL: agreeing copies report PASS (the comparison discriminates)
        rc=0 PhaseVerdict=PASS

--- FAULT 4b: the product reports nothing to compare against ---
  [PASS] SELF.4b :: FAULT 4b: nothing reported yields VOID, not a silent agreement, and the phase is not a clean pass
        rc=4 PhaseVerdict=VOID VoidKind=row F4b.1=VOID evidence=the installer claims reported nothing to compare
        against; this probe enumerates holds 33. An uncompared copy is a second stale list, not independence.

--- FAULT 4b CONTROL: a row-level void leaves the other rows standing ---
  [PASS] SELF.4d :: FAULT 4b CONTROL: a row-level void withholds the phase pass but does NOT downgrade sound rows
        rc=4 VoidKind=row F4d.1 survived as PASS=True

HARNESS SELF-TEST PASSED: 10/10.
Each of the four injected faults was caught, and each paired control shows the guard discriminates.
HARNESS_SELFTEST_COMPLETE rc=0
```

**On fault 4, a deviation from the work package, stated rather than silently resolved.**
The summary table in section 7 calls all four faults "VOID"; the detailed table in 2.2
calls this one "FAIL naming both numbers". The detailed table is the one that is right,
and it is what shipped. A disagreement between the harness's copy and the product's
report is a real finding about a real stale list, so voiding it would discard the very
signal the comparison exists to raise.

**Six of the ten checks are controls, not subjects.** A self-test that only proved
guards fire would pass trivially if the runner voided everything, so the baseline and
each paired control exist to show the guards *discriminate*.

### 3.3 Two defects found while migrating, both the same family

- **Phase 5 exited 0 unconditionally.** A FAIL in `G2.8f` (the agent reaching approve
  through the Studio IPC bridge, which is Guard 2's central claim) would have reached
  the driver as a clean pass. It had never fired, so nobody noticed.
- **Phase 2 exited with the FAIL count as its exit code**, and **phase 6 computed rc
  from failures alone and ignored VOIDs entirely**, so a phase that measured nothing
  exited 0.

### 3.4 `PIN.studio` replaced, not repinned

It hashed the **staged** Studio installer, which the combined installer consumes at
`ssPostInstall` and does not retain. On any *successful* install the file was already
gone and the check recorded INFO. It could only speak once something else had broken.

It now hashes the **installed `app.asar`**, which exists on every successful install,
so it fires on the happy path. Derivability was checked rather than assumed: the
electron-builder NSIS installer carries exactly **one** embedded archive (a 7z payload,
signature found at a single offset in the artifact) and 7z is lossless.

The old check was **deleted**. An INFO row that reads like coverage is worse than an
absent check, because it gets counted.

`PIN.bundle`'s label said 30 while the check counted 33; both now read one field.
`$REQUIRED30` was renamed for the same reason.

### 3.5 Already fixed, confirmed present, changed nothing

All four verified in place: the checked `az vm user update` exit code
(`interim-v120-validate.ps1:332`), the ~12-minute `no-runner` poll abort (`:410`), the
live control queued *after* the wait in phase 6 (`:329`), and `finish-and-park.ps1`
treating `DRIVER ERROR` as terminal (`:63`).

---

## 4. Version discipline

### 4.1 What the existing gate checked, reported before extending it

It read `#define MyAppVersion` from the `.iss` and `$InstallerVersion` from
`setup.ps1` and failed if they disagreed. That is all. **Both can agree and still be a
number that has already shipped meaning something else**, which is exactly what
happened three times at 1.2.0, with the two literals agreeing every time. Agreement
between two copies of a stale value is not freshness.

### 4.2 The extension

The **existing** gate was extended rather than an eighth added. `released-versions.tsv`
is a repo-tracked ledger, one row per shipped artifact: version, artifact, digest kind,
sha256, bytes, date, note. The gate refuses a build whose version already appears
against a **different** digest, and appends a row on every build that signs.

Enforcement runs **after the compile and before the signature**, because the compiled
digest does not exist earlier. Same posture as the build stamp: unsigned dev compiles
stay cheap, the route that reaches a customer is gated.

The ledger records the **unsigned** digest. Signing embeds a countersigned timestamp,
so a signed digest differs on every run over identical input. Observed directly this
session: two signings of the identical unsigned bytes `26e7b291…` produced
`afa3aa72…` and `3621c600…`. A `digest_kind` column exists because the backfilled
1.2.0 row carries a *signed* digest, that being the only value the close-out recorded;
the gate refuses to compare against it and says so.

### 4.3 Proven in both directions

**Permits a fresh version:**

```
Version OK: 1.3.0 (.iss and setup.ps1 agree)
Ledger OK: released-versions.tsv carries 1 prior artifact row(s).
...
Ledger: appended 1.3.0 26e7b29178c2c475ac0c74f6197c3d4a34b45d7709a023156a01164647bd945d (440587611 B).
  COMMIT released-versions.tsv with this build. An unrecorded release defeats the gate.
```

**Refuses a reused version with different content:**

```
Ledger: version 1.3.0 has shipped before. The compiled digest will be checked against it.
  prior: 1.3.0 unsigned 26e7b29178c2c475ac0c74f6197c3d4a34b45d7709a023156a01164647bd945d 440587611 B  2026-08-15
...
Fail : build_release.ps1: VERSION REUSE: 1.3.0 has already shipped as
26e7b29178c2c475ac0c74f6197c3d4a34b45d7709a023156a01164647bd945d (440587611 B, 2026-08-15) and this build produced
e7c936145a4c3054cca577a7eaee390218ea1af988db64a1c5e4730d9cbab7f6 (440588268 B). The same version number would name two
different payloads, which is the defect released-versions.tsv exists to prevent. ... it has NOT been signed.
```

Exit code 1, before signing.

**The first attempt at the refusal test was itself wrong, and it is worth recording.**
The injected change was a comment line in the `.iss`, which Inno strips, so the
compiled bytes were identical and the gate correctly reported a byte-for-byte rebuild:

```
Ledger OK: 1.3.0 rebuilt byte-for-byte identically to its recorded artifact.
```

That was a flawed test, not a passing gate. Changing a file bundled *verbatim*
(`setup.ps1`) produced the real refusal. It is the same class of error the harness work
is about: the measurement succeeded while the thing being measured was absent.

That accident also produced a useful positive result: **an Inno compile over identical
inputs is byte-for-byte deterministic**, confirmed twice at `26e7b291…`.

### 4.4 The gate fired for real, on this session's own work, within the hour

This is the part worth reading.

After 1.3.0 was built, signed and its row appended, the toolchain policy reader was
tested against every shape it can meet. A `toolchain` section that was **present but
not an object** (a string, an array) fell through the same branch as an *absent*
section and read as **ON**, while every other malformed value denied. That contradicted
the rule stated in that very file: an absent key means a policy predating the feature
and reads on, but a fault is not a preference and a fault denies.

Not reachable by the agent, which cannot write the policy file at all. Fixed anyway: in
a security product, code that disagrees with its own comment is a defect, because the
comments are the audit trail.

Fixing it changed the payload, so **the version gate refused the 1.3.0 rebuild**: the
gate built three hours earlier, firing on its author's own work.

**It was obeyed, not worked around.** The 1.3.0 row stays in the ledger, annotated as
superseded-before-validation, and the fix shipped as **1.3.1**. Deleting a row to let a
changed rebuild through would be exactly the 2am shortcut the ledger exists to prevent,
and doing it in the session that built the ledger would have made it decorative from
birth.

The VM provisioned for the 1.3.0 run (`cfv-163`) was **deleted rather than reused**. It
had not yet staged, so the cost was minutes, and validating one build while shipping
another is not a trade worth making at any price.

Studio was **not** re-versioned. Its payload did not change, and the version identifies
the payload, which is the whole principle. ClawFactory 1.3.1 embeds Studio 1.3.0.

---

## 5. The toolchain access toggle

### 5.1 Shape

| Piece | Where |
| --- | --- |
| `toolchain_ipv4` | a **third** nft set, 443-scoped accept, flushed and rebuilt every run |
| `clawfactory-toolchain.sh` | root-owned resolver, holds the host list as a root-owned constant |
| `clawfactory-fetchctl toolchain on\|off` | the only write path, 0750 root:root, existing tool extended |
| `toolchain.enabled` | a boolean in the existing root-owned policy file, default `true` |
| Web access panel | the switch, its breakage text, and the three states that would otherwise look alike |

### 5.2 The removal is the load-bearing half

The five toolchain hosts were **deleted** from `AUX_HOSTS` in both places it appears.
`allowed_ipv4` is refreshed additively by hostname every five hours with element
timeouts, so nothing is ever removed from it deliberately. Had they stayed, switching
the toggle off would have appeared to work and been silently undone by a timer up to
five hours later, on a customer machine, hours after validation went green. L11.1,
applied a second time.

### 5.3 Default ON, and the reasoning is encoded in the panel

Off would ship a product where skill installation, npm and GitHub fail on a fresh box:
a functional regression, not a safety win. It buys no honesty either, because the
ratified claim sentence already names the software sources. What the toggle buys is
**control**.

**The ratified claim sentence is unchanged and still true:**

> Web access is denied by default. Your agent can reach the AI provider, the software
> sources ClawFactory needs, and the network addresses of the sites you have allowed.
> Nothing else.

It survives because the toggle only ever **narrows**: with it off the agent reaches
strictly less.

### 5.4 Structural or advisory, and every bypass named

**Structural with respect to the agent, at the level of network addresses.** It holds
for the same reason Guard 3 does: the nft chain filters by **uid**, not by process, so
the agent cannot escape it by choosing a different tool or shelling out. Three
independent things stop the agent flipping the switch: the mode on the control tool
(0750 root:root), the mode on the policy file (root:root 0644), and the fact that
applying a change requires talking to nftables, which refuses a non-root caller.

**The bypasses, named:**

1. **Address-level, not hostname-level.** It inherits Guard 3's residual in full.
   Switching off removes these addresses from this set; it does not make a host
   unreachable if the same address is reachable for another reason. **This must never
   be described as hostname-exact.**
2. **The provider route is unaffected by design.** A toolchain host sharing an address
   with a provider front end stays reachable with the switch off.
3. **The five-hour window.** A flip takes effect immediately because the control tool
   re-derives the set on every write, but an address that *moves* is only re-resolved
   on the refresh cycle.
4. **DNS is not gated.** Unchanged by this work.
5. **Root compromise ends it**, as it ends everything else.

### 5.5 The panel text that is not optional

Switching the toggle off breaks real features, and the failure surfaces as a network
error inside WSL that cannot be made to name the panel. The panel states, next to the
control, that switching it off stops skill installation and stops the agent fetching
code from GitHub and npm, and that it does not affect the AI provider.

The panel also distinguishes three states that would otherwise look identical: off,
on-but-no-addresses-reachable, and could-not-read-the-policy. Only the first is a
choice the user made.

---

## 6. The Web access footnote and two Studio copy items

The footnote ships **verbatim** as ratified, amended only for the toggle:

> A site you have not added is not reachable. Your agent can always reach the AI provider
> it talks to. It can also reach the software sources ClawFactory needs, which are GitHub
> and npm, unless you switch them off above. Matching is by network address rather than by
> name, so allowing a site also allows anything else served from the same address.
> Removing a site takes effect immediately.

The previous text was honest but incomplete: it noted a site sharing an address with the
provider, and omitted that the same is true of a site sharing an address with one the
**user** allowed. On shared CDN infrastructure that is the larger of the two cases, so
the omission understated the residual in the direction that flatters us.

**The header spacing.** `justify-between` alone left nothing holding the two groups apart
as the window narrowed, so the version and the first nav item ran together and read as
one token. `gap-x-6` plus `flex-wrap` fixes it at every width.

**The stale banner: REMOVED, not reworded, and here is why.** The home route called
`/api/version` and rendered any failure as "Studio backend unreachable". Studio has no
backend: the 127.0.0.1:8080 server was retired, and it is not in the packaged app at all
and `electron-builder`'s `files` list carries `dist`, `renderer` and `package.json` and
nothing else, and the renderer is loaded with `loadFile`, so there is no origin to fetch
against. In the shipped product that call could only fail, so **the first screen a user
sees always claimed a component was unreachable**. The sentence is false twice over:
nothing is unreachable, and there is no backend to be unreachable.

Rewording assumes there is a real condition to describe and only the words are wrong.
Here the condition itself was retired, so the honest fix is to stop asserting anything
about a component that is gone. This banner caused the D4 misdiagnosis, in which a
working Studio was twice declared broken across three sessions.

What replaces it is what the shipped app can actually observe: its own version through
the preload bridge, and the one genuinely useful failure, which is the renderer running outside
the Electron shell, which is real and actionable.

---

## 7. Artifacts

| | Value |
| --- | --- |
| Studio installer | `46288d06aaf1e786e30310e4bc316e40af04513b013a97f51d24dafb6759fa79` |
| Studio bytes | 100,034,008 |
| Studio `app.asar` | `dc24d41618545f6043d3160e7d4d3d93dd28eb90e620da0c44eb62fac2b6d7dd` (571,726 B) |
| Studio commit | `229ad26` |
| ClawFactory version | **1.3.3** (see the version lineage below) |
| ClawFactory installer, signed | `5bef35dc3a4a944583470bdb0afe893d413d96eafcdf1df0ba66311a417522ab` |
| ClawFactory bytes | 440,606,872 |
| ClawFactory unsigned (ledger) | `3de5c5af5cc81182c523d18194ed9d76c824359495c3418e9e9e620769c947c6` (440,591,218 B) |
| Gates | all seven: soul, bundle (**34**), studio, version, persona, workspace-soul, rootfs |
| Authenticode | `Valid`, `CN=Bret Mckinney`, timestamped, both artifacts |

**Panel markers**, searched in the packaged `app.asar` with a search that discriminates
in both directions: seven new markers present (`web:toolchain`, `setToolchain`,
`Software sources ClawFactory needs`, `stops skill installation`, `unless you switch them
off above`, `Matching is by network address rather than by name`, `Running outside the
ClawFactory Studio app`); five stale strings absent (`Studio backend unreachable`, `Two
things are always reachable regardless`, `Running on http://127.0.0.1:8080`, `MIT
licensed`, `v0.1.0`); positive controls `Workspace` and `Web access` both present.

**Version lineage, three builds, and every one is in the ledger.**

| Version | Unsigned digest | Fate |
| --- | --- | --- |
| 1.3.0 | `26e7b291…` | Superseded before validation. A malformed `toolchain` policy section read as ON instead of denying (4.4). Never released. |
| 1.3.1 | `af2fb2e8…` | Validated on `cfv-164`, and that validation found the toggle could not close the route it advertises (8.3). Never released. |
| **1.3.2** | `b87442f3…` | Ships. Both fixes, re-validated on a clean box. |

Three versions in one session looks untidy and is the correct outcome: each one
names exactly one payload, the ledger records all three, and the gate refused
every attempt to reuse a number rather than letting the digest quietly become
the only truth. That is the behaviour the ledger was built for, exercised three
times on its first day.

**The backtick audit.** The cfv-161 failure class was re-checked over the firewall
here-string after editing it: no backtick escape maps to a control character. The two
pre-existing benign instances (backtick-o, backtick-m at lines 1507-1508) are unchanged.

---

## 8. Validation

One VM, `cfv-164`. `Standard_D2s_v4` (DSv5 quota in westus2 is 0), image
`clawfactory-win11-baseline-v2`. Both deviations carried forward from prior runs and
re-confirmed live.

A second VM, `cfv-163`, was provisioned for the 1.3.0 build and **deleted without being
used** when that build was superseded (4.4). It never staged.

### 8.1 Phase 1: install, clean

**15 PASS, 0 FAIL, 0 VOID, 4 INFO. Both positive controls fired.**

```
P1.3.CTL         PASS   POSITIVE CONTROL: the enumeration can see a resource that IS there (safety-rules.md)
P1.3             PASS   All 34 required resources on disk (independent enumeration)
P1.3b            PASS   Installer resource count and this probe agree (the copies are reconciled)
P1.3c            PASS   CONTROL: absent resource must not be found
P1.CHAN          PASS   POSITIVE CONTROL: the file-based WSL channel discriminates (subject passes, control fails)
PIN.persona      PASS   Pin 1of7 persona.md
PIN.soul         PASS   Pin 2of7 safety-rules.md (SOUL)
PIN.soul.indistro PASS  Pin 2of7 SOUL as installed in distro
PIN.soul.rootpin PASS   Root-owned /etc/clawfactory/soul.sha256 matches pin
PIN.workspaceSoul PASS  Pin 3of7 composed workspace SOUL matches pin
PIN.rootfs       INFO   Pin 4of7 rootfs identity (distro produced by the pinned tarball)
PIN.studio.asar  PASS   Studio pin: the INSTALLED app.asar matches the build-time digest
PIN.version      PASS   Installed version reports 1.3.1
PIN.bundle       PASS   Bundle completeness (all 34 preflight resources shipped)

PASS=15 FAIL=0 VOID=0 INFO=4
positive controls registered=2 fired=2
preconditions declared=0 met=0

PHASE VERDICT: PASS. Every positive control fired and every precondition was met.
PHASE1_PROBE_COMPLETE rc=0
```

**Three of those rows are this session's work reporting on itself.**

- **`PIN.studio.asar` PASS.** The replacement for the vacuous staged-installer pin fires
  on a *successful* install, which is exactly what the old check could never do. It also
  settles the derivability question by execution: the installed `app.asar` is
  byte-identical to the one the digest was taken from, so the NSIS 7z payload is lossless
  in practice and not merely in principle.
- **`P1.3b` PASS**, and it is now a runner-level call rather than a local comparison, so
  it cannot be dropped by a future edit and an absent installer count would record VOID
  rather than reading as agreement.
- **`PIN.version` PASS at 1.3.1**, which is required test 10: filename, header, package
  metadata and the uninstall entry all read one field.

`PIN.bundle` reports **34**, up from 33, confirming `clawfactory-toolchain.sh` is
bundled. Its label and its check now read the same field.

### 8.2 Required test 12: the harness self-test, on the box

**10/10 PASS**, matching the build-machine run in 3.2 exactly.

It failed on its first attempt there, and the failure is worth keeping rather than
tidying away. The self-test resolved the phase runner for the repo layout only, so on
the VM (where it lives at `C:\cfv\`) it looked for `C:\validation\interim-v120-phaselib.ps1`
and died before running a single check:

```
harness-selftest: cannot find C:\validation\interim-v120-phaselib.ps1
RUNNER_EXITCODE=1
```

**It failed LOUDLY and named the exact missing path.** A self-test that had silently
skipped when it could not find its subject would have reported a clean run over nothing
at all, which is the precise defect it exists to catch, one level up. The loudness is
the property worth keeping; the path was the bug. It now searches both layouts and names
both if neither works.

---

### 8.3 The toolchain suite on 1.3.1, and the defect it found

**This is the most important result in the run, and it is a defect in my own work
that only execution could have found.**

Eight of eleven substantive checks passed, including every structural one:
`TC.0a-c` (installed, root-only, tripwire covers all three accepts), `TC.2a`,
`TC.2b` (the set really does empty), `TC.3` (a real agent turn completes with the
switch off), **`TC.4` (a real five-hourly refresh did not re-open the closed
route, with its control confirming the refresh genuinely ran and added provider
addresses)**, `TC.5`, `TC.6` (ten channels, agent cannot touch it), `TC.7a-c`
(read-fetch regression), `TC.8`, `TC.8b`, `TC.8c`, `TC.9`. Seven positive
controls registered, seven fired.

**Three reachability checks FAILED, and together they say the switch did not
work:**

| Switch | `api.github.com` | `registry.npmjs.org` | `raw.githubusercontent.com` |
| --- | --- | --- | --- |
| **ON**, 18 addresses in set | **blocked** | CONNECTED | CONNECTED |
| **OFF**, 0 addresses in set | blocked | **CONNECTED** | **CONNECTED** |

The set contents were perfect: 18 when on, 0 when off, 0 after the refresh. What
was wrong was the relationship between an address and a hostname.

#### Root cause, and it is mine

There are **three** places a hostname can enter the unrevocable `allowed_ipv4`
set: `$baseHosts` in `Step-EgressFirewall`, `AUX_HOSTS` at install, and
`AUX_HOSTS` in the refresh script. I removed the toolchain hosts from the last
two and **missed the first**. `$baseHosts` seeds the set at install *and* is
persisted to `/etc/clawfactory/allowed-ips.txt`, which the boot path re-applies.
So the addresses came straight back into the set nothing can revoke.

That is **L11.1, the lesson this entire feature was built around, half-executed.**
`$baseHosts` also carried three hosts the toolchain list did not
(`github.com`, `codeload.github.com`, `api.clawhub.ai`), so those were
unrevocable too.

#### I got the first explanation wrong, and the diagnostic corrected me

My initial hypothesis was CDN sharing with the provider, which would have made
this a permanent, unfixable residual. **The measurement disproved it**: the
provider resolves to `160.79.104.10`, while the npm (`104.16.x`) and GitHub Pages
(`185.199.10x.133`) addresses sitting in `allowed_ipv4` came from `$baseHosts`.

```
SET allowed_ipv4 = 52 address(es)
SET toolchain_ipv4 = 18 address(es)
  registry.npmjs.org 104.16.0.34 allowed=1 toolchain=1
  raw.githubusercontent.com 185.199.108.133 allowed=1 toolchain=1
  api.anthropic.com 160.79.104.10 allowed=1 toolchain=0
```

Recorded because the wrong answer would have been written up as a permanent
residual instead of a fixable bug, and a residual nobody can fix is exactly the
kind of claim that stops getting questioned.

#### A second finding, inherent rather than a bug

`api.github.com` **rotates**: `140.82.116.6` and `20.29.134.17` across five
lookups. The toolchain set is flushed and rebuilt on every run, which is what
makes revocation work, so unlike the additively-refreshed provider set it never
accumulates a pool. A set built from one lookup misses the address the next
connection uses.

**That is the price of revocability, not a mistake.** Mitigated by resolving three
times and taking the union, which recovers most of the pool without giving up
revocation, since the union is still discarded and rebuilt next run. No number of
lookups turns address matching into hostname matching, and the copy does not
claim otherwise.

### 8.4 The fix broke the install, in the opposite direction

**1.3.2 could not install at all**, and the failure is the mirror image of the one
it fixed.

```
INSTALLER_DONE=failure reason=Failed to pre-configure gateway (exit=1)
  at Step-PreinstallGatewayRuntime, setup.ps1: line 2272
```

Removing the toolchain hosts from `$baseHosts` made the toggle able to revoke,
which was correct, and it also left uid 1000 with **no route to GitHub, npm or the
skill hub** for the entire window between `Step-EgressFirewall` and
`Step-InstallReadFetch`, which is where the toolchain resolver first runs. Step 8c
(`openclaw config set gateway.*`) runs as **clawuser**, inside that window.

**It spent 21 minutes timing out before failing** (17:42 to 18:03 in the install
log). That gap is the diagnostic: a logic error fails immediately, a network
timeout does not, and the only thing that had changed was clawuser's reachability.

#### The fix, and why seeding early is safe

`@toolchain_ipv4` is now seeded at **firewall time**, from the same list, with the
same three resolve passes. That closes the window while giving up nothing the
toggle depends on, because the set is still flushed and rebuilt from the
root-owned policy on every later run.

The distinction that matters, and which the three versions got wrong in three
different ways: **seeding the toolchain set early is safe; seeding into
`allowed_ipv4` is not.** One is rebuilt from policy on every run and therefore
revocable, the other is refreshed additively with element timeouts and therefore
permanent.

#### Two guards so it cannot recur silently

- The install-time list and the resolver's list are **reconciled at install**, and
  the install **fails naming both** on drift. A host in one and not the other is
  either unreachable during install or silently dropped at the first refresh, and
  both are invisible today.
- `setup.ps1` asserts the seed block survived into the emitted firewall script,
  in the same shape as the existing `/usr/sbin/nft` guard, because a future edit
  that dropped it would fail 21 minutes away from its cause.

#### A third error, caught before it shipped

The reconciliation originally **scraped the resolver's source** with a `sed` that
matched only a single-line assignment, while the list was backslash-continued
across three lines. It parsed to **empty** and would have aborted every install
claiming total drift. Fail-closed, so not dangerous, but **wrong about the
reason**, and a check that misreports its reason sends the next person to the
wrong place. Found by testing the parser against the real file before building.
The resolver now reports its own list through `--list-hosts`, which removes the
parsing surface entirely.

#### What shipped

**1.3.3.** 1.3.0, 1.3.1 and 1.3.2 were all built, signed, recorded in the ledger,
and are **not** what ships.

### 8.5 The toolchain suite on 1.3.3: the toggle works, and one real defect remains

**27 PASS, 1 FAIL, 0 VOID. Seven positive controls registered, seven fired.**

Everything the previous two builds got wrong is fixed and proven by execution:

| Test | 1.3.1 | 1.3.3 |
| --- | --- | --- |
| `TC.1c` switch ON, sources reachable for uid 1000 | FAIL | **PASS** |
| `TC.2c` switch OFF, sources unreachable for uid 1000 | FAIL | **PASS** |
| `TC.2b` the set and the persisted file actually empty | PASS | **PASS** |
| `TC.4` a real refresh does not re-open the closed route | PASS | **PASS** |
| `TC.4b` still unreachable after that refresh, measured | FAIL | **PASS** |
| `TC.5` switching back ON restores the route | PASS | **PASS** |
| `TC.6` the agent cannot change the switch, ten channels | PASS | **PASS** |
| `TC.8` tripwire fails the unit when the accept is removed | PASS | **PASS** |
| Install completes | pass | **PASS** |

The refresh evidence, which is what this feature was built to get right:

```
[toolchain] policy says TOOLCHAIN=off
[toolchain] backend=nftables toolchain=OFF addresses=0 (skill installation, GitHub and npm are denied; the provider route is untouched)
[fw-assert] chain shape OK (uid-scoped, all three allowlist accepts are 443-only, read-fetch and toolchain sets present with their accepts, SMTP dropped explicitly, terminal drop present)
```

#### THE REMAINING DEFECT, AND IT BLOCKS THE FEATURE

`TC.3` FAILED: **with the switch OFF, a real agent turn is refused.**

```
"content":"ClawFactory could not verify that this turn is allowed, so it refused it (fail-safe). "
"clawfactory_gate":{"blocked":true,"state":"gate_error"}
```

This test **passed on 1.3.1**, but only because the toolchain hosts were still
reachable through the defect 1.3.2 fixed. Making the toggle work exposed a
dependency that the broken toggle had been hiding.

**Why this blocks shipping.** The panel copy promises that switching off "stops
skill installation, and stops your agent fetching code from GitHub and npm" and
"does not affect the AI provider". The measured truth is that **the agent stops
working altogether**. A control whose stated consequence understates its real one
is worse than no control, because the user makes a decision on the strength of
the sentence.

**What the diagnostic established**, read-only, on the same box:

- `SRC_URL_COUNT=0`: the turn gate and the spend check name **no** network
  endpoints in their own source, so the gate is not itself fetching anything.
- `gate_rc=0`: the gate runs **fine** when invoked directly as root.
- The proxy logged `chat turn BLOCKED (gate_error)` on both attempts, and the
  turn took roughly 4.5 minutes before failing.

Taken together: the gate is sound in isolation, and the stall is downstream in
the **gateway**, which runs as uid 1000 and is therefore subject to the chain. A
long block followed by a gate timeout and a fail-safe refusal fits the timing
exactly. The precise host was not isolated and **is not guessed at here**.

**Consequence for the feature: the toolchain toggle is NOT ready to ship.** Its
firewall behaviour is correct and thoroughly validated; its user-facing
consequence is not what the product says it is. Carded with the diagnosis above
so the next session starts from the measurement rather than from scratch.

Nothing was tagged or published, so no artifact carrying this reached anyone.

## 9. Card #197

**The answer is NOT the "no" the first probe produced, and the difference matters
for Guard 4.**

### 9.1 What the first probe measured, and why it was not the question

The probe set `models.providers.anthropic.baseUrl` to a root-owned loopback
listener, restarted the gateway, ran a turn, and the listener was never contacted:

```
OVERRIDE_SET_ON=anthropic
PLUGIN_HITS=1          (1 = this probe's own control curl; 0 from the plugin)
BU.2 PASS  Positive control: the unmodified provider path works on this box
BU.4 PASS  The box was restored: the override is gone and a real turn completes again
```

That reads as "the override is ignored". But the same probe also reported:

```
{}
HAS_PROVIDERS=false
TOP_LEVEL_KEYS=gateway,meta,plugins,tools,agents,auth
```

**The shipped configuration has no `models.providers` section at all**, so the
probe created the key it then tested. "The plugin did not read a key that does not
otherwise exist in this config" is a far weaker statement than "the plugin ignores
`baseUrl`", and Guard 4's shape must not be settled on the weaker one dressed as
the stronger.

### 9.2 What the follow-up found, and the runner stopping a false conclusion

The follow-up's first run went **VOID (instrument)**, and this is the single best
demonstration in the session of why the harness work came first.

Its counter used `grep -c` across multiple files (which emits `path:N` per file)
piped to `bc` (not installed), so the substitution produced an empty string. The
check computed **FAIL**, meaning "the anthropic plugin does not reference
`baseUrl`". That is flatly contradicted by the grep output printed two lines
above it in the same transcript.

Because the positive control could not fire, **the runner voided the phase and
downgraded that FAIL instead of publishing it**. Under the pre-session harness a
confident false negative would have gone into this close-out and settled Guard 4's
direction the wrong way, on the one question where being wrong is most expensive.

### 9.3 The actual finding

With the counter fixed (6289 hits, control 0, so the search discriminates):

```
=== WHICH key does it read? ===
    baseUrl: readStringValue(model.baseUrl),
```

**The bundled anthropic plugin reads `model.baseUrl`: a property of the MODEL
definition, not `models.providers.*.baseUrl`.**

### 9.4 The verdict, stated at the strength the evidence supports

| Question | Answer |
| --- | --- |
| Does the plugin honour `models.providers.*.baseUrl`? | **No.** That key is absent from the shipped config shape and setting it changed nothing. |
| Does the plugin support a baseUrl override at all? | **Probably yes, at `model.baseUrl`.** Demonstrated in its own code, NOT yet demonstrated by execution. |
| Is a root-owned outbound proxy therefore ruled out for Guard 4? | **NO. It is not ruled out.** The first probe's "no" would have said it was. |

**What this means for Guard 4:** the door is likely open, and this session
knocked on the wrong one. Address-scoping should **not** be recorded as
permanently unavoidable for v1 on this evidence. The next step is a probe that
sets `baseUrl` on the model definition the agent actually uses and repeats the
same listener test, which is one focused run away.

**Carded, not built.** The job said report it, card it, stop, and nothing in this
session depends on the answer.

**Credential discipline held throughout.** The listener recorded only arrival,
path, and whether an Authorization header was *present*. It never read, logged or
stored a header value, and the config survey redacted every field whose name
suggests a secret before anything reached stdout.

---

## 10. Carried-forward test table

Rows marked **new** are this session's. The required-test numbers from the work package
are given so the mapping is checkable rather than asserted.

All verdicts below are from **1.3.3 on cfv-166** unless stated. Rows marked **new**
are this session's.

| Id | Test | Req # | Verdict | Note |
| --- | --- | --- | --- | --- |
| SELF.0-4d | Harness self-test, four injected faults plus six controls | 12 | **10/10** | build machine AND the box, twice on the box |
| P1.* | Clean install, 34 resources, pins re-derived | | **15 PASS / 0 FAIL / 0 VOID** | 2 controls registered, 2 fired |
| P1.3b | Installer count and probe count reconciled | | **PASS** | now a runner-level call, cannot be dropped by an edit |
| PIN.studio.asar | Installed `app.asar` matches the build-time digest | | **PASS** | **new**, replaces a vacuous check; fires on the happy path, which the old one could not |
| PIN.version | Installed product reports 1.3.3 | 10 | **PASS** | filename, header, package metadata and uninstall entry all one field |
| PIN.bundle | 34 preflight resources shipped | | **PASS** | label and check now read the same field |
| VERSION.GATE | Refuses a reused version, permits a fresh one | 11 | **PASS** | build machine, both directions (4.3), then fired for real 3 times |
| TC.0a-c | Toggle installed: resolver root-owned, third set, 443 accept, tripwire covers all three | | **PASS** | **new** |
| TC.1a-c | Switch ON: sources reachable for uid 1000, with a control that must fail | 1 | **PASS** | **new** |
| TC.2a-c | Switch OFF: unreachable AND the addresses actually leave the set | 2 | **PASS** | **new**, both halves checked |
| TC.3 | CONTROL: a real agent turn completes with the switch OFF | 3 | **FAIL** | **new**. THE BLOCKER, see 8.5. Turn refused with `gate_error` |
| TC.4, TC.4b | **Survives a real five-hourly refresh** | 4 | **PASS** | **new**, the load-bearing test; real unit, with a control proving the refresh ran |
| TC.5 | Switching back ON restores the route | 5 | **PASS** | **new**, the switch is reversible |
| TC.6 | The agent cannot change the switch, ten channels, with a control | 6 | **PASS** | **new** |
| TC.7a-c | Read-fetch add, reach, revoke still work alongside the third set | 7 | **PASS** | **new**, G3.3 regression, and the two sets do not disturb each other |
| TC.8, TC.8b, TC.8c | Tripwire fails the unit when the accept is removed, and the chain is restored | 8 | **PASS** | **new**, with a control proving the fault was genuinely injected |
| TC.9 | Box left in the shipped default state | | **PASS** | **new** |
| TC.*.POSTREBOOT | Tests 2, 3, 4 and 8 after a full reboot | 9 | **NOT RUN** | deliberately. `TC.3` blocks the feature, so a reboot pass would re-measure a known-broken control. It runs in the rework session |
| MANUAL.* | Studio by hand: toggle, breakage text, footnote, add/remove, banner, header | 13 | **NOT RUN** | deferred, see below |
| BU.0-4 | Card #197: does the plugin honour a `baseUrl` override? | 14 | **ANSWERED** | section 9. Not a simple pass/fail; the answer corrects the first probe's |

**On the two NOT RUN rows, and why deferring is the honest call rather than a
shortfall.** Both depend on a panel whose copy is now known to be wrong: the
breakage text describes a consequence milder than the real one (8.5). Sending a
person to verify that a sentence renders correctly, when the sentence itself has
to change, would produce a "verified" result against text that is about to be
rewritten. The rework session runs both, against final copy. **Neither is recorded
as a pass.**

The reboot pass is deferred for the same reason and one more: `TC.3` fails
pre-reboot, so a post-reboot run would be re-measuring a control already known to
be broken, which tells nobody anything they do not already know.

---

## 11. Resource ledger

Starting state verified before provisioning anything: the only resources in
`clawfactory-validation` were the storage account, the VNET and the two baseline images,
matching the prior close-out's teardown proof exactly.

| Resource | Created | Disposed | Evidence |
| --- | --- | --- | --- |
| VM `cfv-163` | 2026-08-15 09:52 local | **deleted** 09:59 | provisioned for the superseded 1.3.0 build; never staged, never installed. Deleted in the same turn the decision was made, not at close-out |
| `cfv-163-osdisk`, `cfv-163VMNic`, `-pip`, `-nsg` | with the VM | **deleted** 10:45 | `az vm delete` does NOT remove these. Swept explicitly, NIC first because it references the pip and nsg, then an unfiltered `az resource list` confirmed nothing matching `cfv-163` remained |
| VM `cfv-164` | 2026-08-15 09:59 local | **deleted** 11:26 | the v1.3.1 run: phase 1, self-test, toolchain suite (which found the defect), address diagnostic, #197 probe and follow-up |
| `cfv-164-osdisk`, `VMNic`, `-pip`, `-nsg` | with the VM | **deleted** 11:26 | swept explicitly. The first unfiltered check still listed the disk AFTER the delete reported success; a re-check confirmed it was a propagation race, not a failed delete. Recorded because "it said deleted" is not the same claim as "it is gone" |
| VM `cfv-165` | 2026-08-15 11:19 local | **deleted** 12:07 | the v1.3.2 run. The install FAILED (8.4), which is what the box was for: it caught a regression that only a fresh install can surface |
| `cfv-165` disk, NIC, pip, NSG | with the VM | **deleted** 12:07 | swept explicitly, unfiltered check clean |
| VM `cfv-166` | 2026-08-15 12:08 local | **deleted** 13:22 | the v1.3.3 run: install green, self-test 10/10, toolchain suite 27 PASS / 1 FAIL, gate diagnostic |
| `cfv-166` disk, NIC, pip, NSG | with the VM | **deleted** 13:22 | swept explicitly |
| NSG rule for RDP | during each run | deleted with each NSG | scoped to a single `/32`, never `0.0.0.0/0`. No human ever needed RDP this session |
| License slot | on each install | released with each VM delete | three installs, three deletes |
| Blobs in `validation` container | staged | retained | evidence, not billable compute |

**Credential hygiene.**

- The **provider API key** was read from the Windows Credential Manager inside the
  launcher process, base64-encoded in memory, and handed straight to the driver. It never
  crossed a tool boundary, never appeared on a command line, and never entered a
  transcript. The only thing reported about it was its length.
- The **VM admin passwords** were generated in memory and never printed or written to
  disk on this side.
- **No SMTP credential was needed or used.** None of the fourteen required tests touches
  Guard 2, so the kept throwaway app password was not requested, not entered and not
  revoked, per the standing decision.
- The **card #197 listener** records only that a request arrived, its path, and whether
  an Authorization header was *present*. It never reads, logs or stores any header value.

---

## 12. Delta security sweep

Only the surface this session changed is assessed. Everything else is unchanged and its
prior assessment stands.

| Change | Surface added | Assessment |
| --- | --- | --- |
| `toolchain_ipv4` set and accept | one more 443-scoped accept in the egress chain | **Net narrowing.** Those addresses were already reachable, in a set nothing could revoke. They are now revocable. No destination is reachable that was not reachable before. |
| `clawfactory-toolchain.sh` | a new root-owned executable, 0755 | Reads a root-owned file, writes a root-owned file, calls `nft`. No input from uid 1000. The host list is a constant inside it, not configuration. |
| `fetchctl toolchain on\|off` | one more subcommand on an existing 0750 root:root tool | Takes a two-valued word, not a destination. The worst a hostile caller achieves is a state the user could set themselves. |
| `web:toolchain` IPC channel | a fourth channel on the existing bridge | Strict boolean, refused rather than coerced. Runs in the Electron main process as the logged-in Windows user; the agent has no IPC bridge. |
| `toolchain` policy key | one more key in an existing root-owned file | Agent cannot write the file. Absent reads ON (upgrade path); malformed DENIES. |
| `released-versions.tsv` | a repo-tracked build input | Build-machine only, never installed, never read at runtime. Affects what may be signed, not what runs. |
| Phase runner and self-test | validation code | Never shipped. Not in `[Files]`, not in `$required`. |

**No new privilege boundary was created and none was widened.** The one genuinely new
decision point (what an absent versus a malformed `toolchain` value means) was found by
testing to be wrong in the permissive direction and was fixed before shipping, at the
cost of a version bump. See 4.4.

**The claim sentence is unchanged and remains true.** The toggle only narrows.

## 13. Delta bug review

Six defects were found and fixed this session. Five were in the harness, which is the
point of having done the harness first.

| # | Defect | Where | Found by |
| --- | --- | --- | --- |
| 1 | Phase 5 exited 0 unconditionally, so a FAIL on Guard 2's central claim read as a pass | `interim-v120-phase5.ps1` | migrating it to the runner |
| 2 | Phase 2 exited with the FAIL count as its exit code; phase 6 ignored VOIDs entirely | phases 2 and 6 | same |
| 3 | A row-level VOID still let a phase exit PASS | the new runner itself | the self-test, on its first run |
| 4 | The tripwire fault injection could not inject: `nft` refuses to delete a referenced set | `interim-v130-toolchain.ps1` | reading the test before running it |
| 5 | The second evidence channel was silently lost for any `interim-v130-` phase | `interim-v120-job.ps1` | same |
| 6 | A malformed `toolchain` policy section read as ON instead of denying | `clawfactory-toolchain.sh`, `clawfactory-fetchctl.js` | testing the reader across every shape |

Defects 3 through 6 were all found **before** anything was measured with the affected
code. That is the return on doing the harness first, and it is the argument for the
ordering the job imposed.

## 14. Lessons learned

`ClawFactory_Install_Lessons_Learned.md` gains **L30: a periodic refresh can re-open a
route the user just closed, and it will do it hours later.**

The failure mode is invisible to any test that finishes in under five hours, which is
every test we run. It would have been discovered by a customer, as "I turned this off
and it came back", and it would have looked like a lie rather than a bug. The rules:
a revocable thing and an additively-refreshed thing cannot share a container; the
refresh must call the revocation path unconditionally; test against the real timer; and
that test needs a control proving the refresh actually ran, or "it did not come back" is
true for the wrong reason.

The general shape, worth carrying beyond firewalls: **any control the user can turn off
must be tested against every scheduled job that could turn it back on.**

### 14.1 Two smaller ones from this session

**A fault injection that does not inject scores a false pass, and it looks exactly like
a working control.** The tripwire test deleted an nft set to prove the tripwire notices.
`nft` refuses to delete a set a rule references, so the delete would have been rejected,
the chain would have stayed intact, and the tripwire would have correctly passed, which
the test would have recorded as a miss. Every fault injection now needs its own control
proving the fault landed. This is L29 pointed at the harness rather than at the product.

**Test the gate you just built by breaking something it actually measures.** The first
attempt to prove the version gate refuses a reused version injected a comment line into
the `.iss`. Inno strips comments, so the compiled bytes were identical and the gate
correctly reported a byte-for-byte rebuild. Changing a file bundled *verbatim* produced
the real refusal. A test that changes something the artifact does not carry is not a
test of the artifact.

---

## 15. Recommendations for the next session

Ordered by what would cost most to relearn later, not by size.

1. **Guard 4's shape is decided by the card #197 answer in section 9.** Do not design
   around it before reading that section. If the override is honoured, a root-owned
   outbound proxy closes the address-scoping residual and the provider-key exfiltration
   residual together, and that is the single highest-value structural change left in v1.
   If it is not, address-scoping is permanent for v1 and Guard 4 has to be something else
   entirely.

2. **`AUX_HOSTS` is now two lists in two places, and only one of them is in `setup.ps1`.**
   The provider half stays there; the toolchain half lives inside
   `clawfactory-toolchain.sh`. Anyone adding a hostname must decide which half it belongs
   to, and the wrong choice is silent: a toolchain host added to `AUX_HOSTS` becomes
   unrevocable, and a provider host added to the toolchain list becomes switchable, which
   would let a user brick their own agent. Worth a comment at both sites, and there is
   one, but it is worth knowing before touching either.

3. **A build-time guard against the backtick class would be cheap.** The cfv-161 failure
   (a backtick inside a double-quoted here-string emitting a real control character into
   generated shell) cost a whole VM run, and this session re-checked it by hand. The
   check is about fifteen lines: scan the here-string regions of `setup.ps1` and fail on
   any backtick followed by `n`, `r`, `t`, `a`, `b`, `0`, `v` or `f`. It was left out
   deliberately because the job said not to add gates, but it belongs in the next one
   that touches the build.

4. **The remaining phases still carry `interim-v120-` in their names** while validating
   1.3.1. The prefix is now purely historical and mildly misleading. Renaming is
   mechanical but touches every driver reference, so it wants its own small commit rather
   than riding a feature.

5. **`released-versions.tsv` needs a row for anything shipped outside `build_release.ps1`.**
   The gate can only see what it wrote. If an artifact ever reaches a customer by another
   route, the ledger silently stops being a complete record, and the failure mode is that
   it keeps looking authoritative.

## 16. Out of scope, confirmed untouched

No Guard 4. `AUX_HOSTS` was split, not deleted. No outbound proxy, no provider-key
injector, and nothing built on the #197 answer. No Studio restyle beyond the items in
section 6. No marketing copy beyond the panel. No tag, no publish, no Inno licence
purchase. `SECURITY.md:114` left alone. Step 7, full assembled-build validation, not run:
it comes after Guard 4.
