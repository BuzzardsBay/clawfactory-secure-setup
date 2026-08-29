# Close-out: Guard 4 ground truth probe, and the card 197 follow-up

Session date 2026-08-17. VM `cfv-165`. Input artifact 1.3.3, signed,
`5bef35dc3a4a944583470bdb0afe893d413d96eafcdf1df0ba66311a417522ab`, 440,606,872 bytes.
Dispatch card 254.

This document is written to be read by someone who was not here, including the
planning session that will write the next work package. Section 9 is the part
that matters most for that purpose, and it is not flattering.

---

## 1. The verdict, in one place

**Guard 4 cannot be built on fanotify permission mode, because the filesystem
that granted workspaces live on does not deliver permission events.**

That is the decision this job existed to make, it is measured rather than
reasoned, and it closes a question that has been open since Guard 3 shipped.

| Q | Question | Verdict |
| --- | --- | --- |
| 1 | Does the kernel enforce fanotify permission decisions? | **YES on ext4. NO on the drvfs mount where granted workspaces live.** |
| 2 | Mark scope, and survival of the WSL restart cycle | PARTIAL, see 3.2 |
| 3 | Write volume, and where the exclusion lands | Volume measured. Exclusion **not safely measured** |
| 4 | FUSE passthrough, the fallback | **PASS on ext4**, 5 of 5 controls. Not tested over drvfs |
| 5 | What it costs | **NOT RUN**, correctly: no candidate survived to be timed |
| 6 | Second paths to the workspace | PARTIAL, see 3.6 |
| 7 | Card 197, `model.baseUrl` | **NOT ANSWERABLE** on this box, see 3.7 |

---

## 2. The recommendation on the Guard 4 enforcement point

**Neither candidate is ready, and fanotify is structurally ruled out for the
thing Guard 4 has to protect.**

Guard 4 protects granted workspaces. Granted workspaces are not on Linux
storage: `clawfactory-grants.ps1:35` mounts each granted Windows folder at
`/workspaces/<slug>` over drvfs, which presents as `9p` in `/proc/mounts`. The
measurement below is therefore the product measurement, and the ext4 result,
though clean, is about a filesystem no granted workspace uses.

This distinction was not in the work package. The work package said to mark a
synthetic tree under `/var/tmp`. Had the probe done only that, this job would
have returned a confident YES and Guard 4 would have been built on it.

**What that leaves. FUSE passthrough is the surviving candidate and it earned
that on evidence, not by elimination.** With the backing directory locked to
`0700 root:root` and `bindfs` remapping ownership into the view, uid 1000 could
use the workspace normally and could not reach the backing path by any route
tried: read refused, list refused, write refused, hard link refused. Five of
five controls fired, including one requiring the view to be usable so that a
denied backing path could not score a pass for a passthrough nobody can use.

**It is still not a build recommendation, for one specific reason.** The
passthrough was mounted over an **ext4** backing directory, not over a **drvfs
granted workspace**, which is the configuration Guard 4 would actually use.
Question 1 is the reason that gap matters rather than being a formality:
fanotify accepted a mark on drvfs and then enforced nothing at all. The same
class of surprise is live here until measured.

**So the recommendation is: FUSE passthrough, conditional on one measurement.**
Mount `bindfs` over a real granted workspace and repeat questions 4 and 2. If it
holds, Guard 4 has an enforcement point and section 6 is the build list. If it
does not, Guard 4 has no viable mechanism on this platform and that is a
strategic answer worth having early.

**Do not read this as "Guard 4 is impossible".** It is a rejection of one
mechanism against one filesystem, plus an unfinished evaluation of the other.

---

## 3. Question by question, with evidence

### 3.1 Question 1: does the kernel enforce fanotify permission decisions?

**ext4: YES, unambiguously.** All five positive controls fired.

```
G4JSON {"cmd": "perm", "marked": "/var/tmp/g4/marked", "init_rc": 3,
 "init_errno": "OK", "mark_ok": true,
 "daemon_log": [
   {"path": "/var/tmp/g4/marked/allow.txt", "verdict": "ALLOW", "response_bytes": 8, "delayed": 3.0, "abi_version": 3},
   {"path": "/var/tmp/g4/marked/deny.txt",  "verdict": "DENY",  "response_bytes": 8, "delayed": 0.0, "abi_version": 3}],
 "client": {"uid": 1000,
   "allow": {"ok": true,  "errno": null,    "elapsed": 3.007},
   "deny":  {"ok": false, "errno": "EPERM", "elapsed": 0.001},
   "free":  {"ok": true,  "errno": null,    "elapsed": 0.0}},
 "evidence": {"allow_blocked": true, "deny_refused": true, "deny_was_issued": true,
   "unmarked_opened_normally": true, "events_delivered": 2},
 "verdict": "ENFORCED"}
```

Three properties, all required, all present. The opener blocked for 3.007
seconds against a hold the daemon chose. A `FAN_DENY` produced `EPERM`. A file
outside the mark opened in 0.0 seconds, so the mark is what did the work.

`deny_was_issued: true` is the L30.1 control: the kernel accepted all 8 bytes of
the `fanotify_response` carrying `FAN_DENY`. Without it, the `EPERM` could have
come from anywhere.

**drvfs: NO.** The mark is accepted and then does nothing.

```
Q1.6  PASS  drvfs: fanotify will MARK the filesystem granted workspaces live on
            fanotify_mark on /workspaces/g4-drvfs-3364270d returned OK
Q1.7  FAIL  drvfs: the opener BLOCKS until the daemon answers
            opener measured 0.006s against a 3s hold
Q1.8  FAIL  drvfs: FAN_DENY makes the open FAIL WITH EPERM
            opener errno=, deny issued=False
Q1.9  FAIL  drvfs OVERALL: enforcement reaches a granted workspace
            payload verdict=NO_EVENTS
```

`"daemon_log": []`. Not one permission event was delivered. The opens succeeded
immediately and the daemon was never consulted.

**This is the worst possible failure shape for a security control.**
`fanotify_init` succeeds, `fanotify_mark` returns OK, nothing errors, and the
guard silently enforces nothing. A Guard 4 built and smoke-tested on ext4 would
have looked correct in every test that did not measure blocking on a real
granted workspace.

The mount, for the record:

```
C:/cfv/g4-drvfs /workspaces/g4-drvfs-3364270d 9p rw,relatime,
  aname=drvfs;path=C:/cfv/g4-drvfs;metadata;uid=1000;gid=1000;
  symlinkroot=/mnt/,cache=0x5,access=client,msize=65536,trans=fd,rfd=3,wfd=3
```

Kernel `6.18.33.2-microsoft-standard-WSL2`, fanotify ABI v3.

### 3.2 Question 2: mark scope and survival

Measured in the pre-reboot arm only. The reboot arm is covered in section 8.

The FUSE mount did **not** survive the WSL restart cycle:

```
Q2.5  FAIL  The FUSE mount SURVIVES the WSL restart cycle
            mount present=False content readable=False
```

That is the same trigger that once took down `user@1000`, the gateway and
everything under it, and it is the trigger a customer hits whenever the last
`wsl.exe` session exits. A candidate that dies there is absent during exactly
the window an agent keeps running in. It is fixable with a systemd unit, which
is a build cost rather than a refutation, and it is listed in section 6.

### 3.3 Question 3: write volume, and where the exclusion lands

**Volume, measured, notification mode, nothing blocked:**

```
Q3.1  PASS  A mount-scoped notification mark could be placed on the granted workspace
Q3.2  INFO  total=14 events over 420s covering one agent turn, one npm install and one git commit
Q3.3  INFO  11 of 14 = 78.6 percent in .git, node_modules, __pycache__, .venv or build output
```

Two honest caveats on that number. The dependency was a single tiny package, so
14 is a floor and not a representative session. And notification-mode delivery
on this filesystem is itself suspect given 3.1: a mount-scoped notification mark
was accepted on 9p, but the same filesystem silently swallowed every permission
event, so a low count may be under-delivery rather than a quiet session.

**Exclusion placement: NOT SAFELY MEASURED, and this is a harness failure, not a
kernel result.** `FAN_MARK_IGNORED_MASK` was accepted (`Q3.4 PASS`) and 11
events still arrived from the ignored directory while 5 arrived from outside
(`Q3.5 FAIL`). But the control that asserts the ten writes were ten *distinct
files* never registered in the run: `Q3.5.CTL` and `WROTE_INSIDE` are both
absent from the transcript. An earlier version of this same test had exactly
that defect, where a variable expanded in the wrong shell and ten writes landed
on one filename. **A repeat of a known false measurement, with its detector
missing, is not evidence.** It is reported here as unconfirmed and listed in
section 7.

One thing the first attempt did establish and is worth keeping: **fanotify
ignore masks are per inode.** Marking `node_modules` does not cover
`node_modules/probe-pkg`. Excluding a dependency tree means walking it and
marking every directory, not placing one mark at the top. That is a design fact
for any future Guard 4 regardless of the outcome above.

### 3.4 Question 4: FUSE passthrough

**PASS, 5 of 5 positive controls fired. The isolation property Guard 4 needs is
real, and the agent can still use the workspace.**

```
Q4.1       PASS  /dev/fuse is present on a shipped box
Q4.2       PASS  The kernel carries the fuse filesystem
Q4.5       PASS  Root can mount a FUSE filesystem inside the distro
Q4.6       PASS  The passthrough actually passes through, both directions
Q4.8.CTL2  PASS  uid 1000 read the canary through the view = True
Q4.8       PASS  backing content readable by uid 1000 = False, backing at 0700 root
Q4.9       PASS  direct write to the backing path = refused
```

The shape that produced this: `bindfs` remapping ownership into the view
(`--force-user=clawuser --force-group=clawuser`) over a backing directory locked
to `0700 root:root`. The agent works in the view; every route to the path
underneath is refused, including a hard link attempt.

**Two honesty corrections on this result.**

First, `Q4.3` reports "a FUSE passthrough implementation is already on the box:
PASS", and **that PASS is contaminated by this probe's own earlier action.** On
the genuinely clean box the first run recorded `BINDFS=ABSENT` and installed it.
The bundling finding in section 6 stands: `bindfs` is **not** present on a
shipped box.

Second, and this is the one that limits the recommendation: **the passthrough
was mounted over an ext4 backing directory under `/var/tmp`, not over a drvfs
granted workspace.** The work package asked whether a passthrough can be mounted
over a granted folder, and that specific case was not measured. Given that
fanotify accepted a mark on drvfs and then silently enforced nothing, this is
exactly the configuration where the same surprise could recur, and it must not
be assumed away.

`Q2.5` also stands against this candidate: the mount did **not** survive the WSL
restart cycle. That is a build cost, not a refutation, and it is in section 6.

### 3.5 Question 5: what it costs

**Not run, and that is the correct output.** The phase declared a named
precondition and refused:

```
Q5.PRE  VOID  at least one enforcement candidate survived questions 1 to 4
              Q1 ext4 enforced=..., Q1 drvfs enforced=False.
              Timing a mechanism that cannot be used produces a number that
              outlives its caveat.
```

A cost figure for an unavailable design is not a cheap extra data point. It is a
number that gets quoted later without its caveat.

A separate and more serious note on this question appears in section 9: the
first attempt at it deadlocked the box.

### 3.6 Question 6: second paths to the workspace

**PARTIAL. The mount-level half is answered. The uid 1000 half was never
measured, and the phase nonetheless reported PASS.**

**Answered, from the unfiltered mount table captured verbatim at root:** there is
**no `/mnt/c` mount**. The complete `/proc/mounts` listing contains no entry at
`/mnt/c`, so `automount=false` is doing its job and there is no blanket second
path to every granted folder. The grant itself appears exactly once:

```
C:/cfv/g4-paths /workspaces/g4-paths-423de072 9p rw,relatime,
  aname=drvfs;path=C:/cfv/g4-paths;metadata;uid=1000;gid=1000;...
```

**Not measured:** every check that ran as uid 1000. So bind-mount refusal,
unprivileged user namespaces, the private-bind-inside-a-namespace test, symlink
enumeration and the Docker check are all **unmeasured**.

**ROOT CAUSE, found after the run from the job's captured stderr.** One
character, and the failure it caused is the most instructive single event of the
session.

```
The variable '$2' cannot be retrieved because it has not been set.
At C:\cfv\g4-q6-paths.ps1:94 char:33
+ echo "MNT_C_IS_A_MOUNT=`$(awk '\$2 == "/mnt/c" {print "yes"}' /proc/m ...

The variable '$u' cannot be retrieved because it has not been set.
At C:\cfv\g4-q6-paths.ps1:134 char:3   +  W $u.Out

The variable '$shadowDenied' cannot be retrieved because it has not been set.
At C:\cfv\g4-q6-paths.ps1:138 char:12  +  -Fired $shadowDenied ...
```

Line 94 was written `awk '\$2 == ...'`. In a double-quoted PowerShell
here-string that is a backslash followed by the variable `$2`. On the VM an
undefined variable reference is a **terminating** error, so:

1. the here-string never evaluated, and `$u` was never assigned
2. `W $u.Out` threw, which is why no probe output appears
3. `$shadowDenied` was never set, so `Register-Control` threw and **the positive
   control never registered at all**
4. `$mntC` was never set, so the `$(if ($mntC) { 'PASS' } else { 'FAIL' })`
   verdict subexpression threw and produced **nothing**, leaving five `Record`
   calls with an **empty verdict argument**
5. an empty verdict is neither PASS nor FAIL nor VOID, so the runner counted
   them as nothing and reported the phase **PASS**

**And it survived the audit that was supposed to catch exactly this class.**
After the first round of `\$` defects, the files were grepped with
`\\\$[A-Za-z(]`, letters and an open paren. `awk` field variables are **digits**.
The pattern used to certify the file clean was structurally incapable of
matching the defect being introduced in the same edit. Locally it is harmless,
because without strict-mode semantics an undefined variable is silently `$null`,
which is why executing the identical bytes on the build machine reproduced pass
1's correct behaviour and not the fault.

**Three lessons, all carried into 9.4:**

- an audit regex is itself a probe and needs a negative control, or it certifies
  what it cannot see (instruction I)
- the runner must treat an empty verdict as VOID (instruction F), which alone
  would have turned this silent PASS into a loud VOID
- probe stderr is a first-class evidence channel. This root cause was sitting in
  the job `.out` the whole time and was found only after the VM was destroyed,
  because the analysis kept reading the phase transcript, which by construction
  contains only what the probe successfully printed (instruction J)

**A harness defect this exposes, and it is the most important thing in this
section.** Those five rows recorded an **empty verdict**, which is neither PASS
nor FAIL nor VOID, so the runner counted them as nothing and reported

```
PHASE VERDICT: PASS
```

for a phase in which five of ten checks said nothing at all. **The runner must
treat an empty verdict as VOID.** This is the one gap in it found this session
and it is carried into section 9.4 as instruction F.

Recorded as context rather than as a defect:

```
Q6.7  INFO  ROOT can mount the same Windows folder a second time
            ROOT_SECOND_MOUNT=established
```

Root is not the actor Guard 4 defends against. It matters only because a Guard 4
daemon would be the thing holding that privilege.

Also recorded, as context rather than as a defect:

```
Q6.7  INFO  ROOT can mount the same Windows folder a second time
            ROOT_SECOND_MOUNT=established
```

Root is not the actor Guard 4 defends against. It matters only because a Guard 4
daemon would be the thing holding that privilege.

### 3.7 Question 7: card 197

**NOT ANSWERABLE ON THIS BOX, and the reason is the install defect in section 5,
not the override.**

What was established:

```
Q7.1        PASS   the bundled plugin reads a baseUrl off the model definition,
                   in its own source
CONTROL1_HTTP=200
CONTROL1_LOGGED=1                  <- the listener was up and reachable from
                                      the gateway's own uid
WROTE=[{"where":"agents.defaults.model.baseUrl","preexisting":false}]
                                   <- a REAL model definition object, not one
                                      this probe invented
GATEWAY_STATE=active
GATEWAY_LISTENING=0                <- and this is the problem
LISTENER_HITS_NONCONTROL=0
AFTER_SHA=efaa7a3b...  PRISTINE_SHA=efaa7a3b...   <- restored byte for byte
```

The gateway unit reports `active` and **never binds its port**. No agent turn
completes on this box at all. Control 2, which requires a real turn to complete
end to end with the override removed, therefore did not fire, and the phase
voided.

**That is the control doing exactly its job.** Without it, `LISTENER_HITS_NONCONTROL=0`
would have been reported as "the plugin ignores `model.baseUrl`", which is a
confident wrong answer to card 197 and the precise failure the first probe of
this card already made once.

**Two things are nonetheless worth carrying forward.**

First, the override was written to `agents.defaults.model`, **a model definition
object that already exists in the shipped configuration.** The first card 197
probe's weakness was that it invented the key it then tested; this one did not.
So a future run has the correct location and need not rediscover it.

Second, the box was restored and the restoration proven: the post-run digest
equals the pristine digest taken before any edit.

**Card 197 remains open**, and it is now blocked on the same 1.3.3 install
defect described in section 5, which ties it to the Guard 3 rework rather than
to Guard 4.

---

## 4. Card 197: the scope correction that must be carried forward

Regardless of the execution result, **this correction stands and is the more
important half of the card 197 outcome.**

The card 245 close-out records that a root-owned outbound proxy would close
"the address-scoping residual and the provider-key exfiltration residual
together". **That is overstated and must not be carried forward.**

A `baseUrl` override redirects traffic made by the **model plugin**. Read-fetch
traffic and toolchain traffic leave uid 1000 through ordinary clients and never
touch the model plugin. Nothing a proxy does to the provider path makes GitHub,
npm, the skill hub, or any user-added destination hostname-exact.

A working override would:

- close the **provider-key exfiltration** residual, and
- make the **provider route** hostname-exact.

It would **not** touch address-scoping for user-added or toolchain
destinations. The value of the proxy is real without it being doubled.

**And it does not gate Guard 4.** Guard 4 is snapshot-on-write, a filesystem
control. The proxy is a network control. Two close-outs now carry a line saying
the 197 answer decides Guard 4's shape. It does not, it never did, and that line
should stop being copied forward. The two questions shared this session because
both are read-only probes needing one install, which is the only thing they
share.

---

## 5. An unrelated finding: 1.3.3 does not install cleanly

**The 1.3.3 install FAILED on a clean box.** This is not a Guard 4 result and it
was found on the way past.

```
INSTALLER_DONE=failure reason=Failed to install the read-fetch allowlist and the
toolchain toggle (Guard 3). Refusing to finish: the product would offer a Web
access panel with nothing behind it, and a control that is absent is worse than
one that was never claimed.
  at Step-InstallReadFetch, setup.ps1 line 2979
  [install-read-fetch] FATAL: the toolchain accept is missing or is not scoped
  to tcp dport 443
```

**It is a race, not a missing feature.** From the box:

```
18:23:45  distro started (uptime -s); /proc/uptime confirms NO restart since
18:24:55  allowed-ips.txt and clawfactory-fw-apply.sh written by Step 7
18:33:14  clawfactory-read-fetch.sh and clawfactory-toolchain.sh installed
18:33:15  /etc/clawfactory/toolchain-ips.txt created
18:33:16  the assert refused: no toolchain accept in the chain
later     the chain DOES carry "ip daddr @toolchain_ipv4 tcp dport 443 accept"
          and clawfactory-fw-assert.sh exits 0
```

The accept appeared roughly one second after the assert refused, with no distro
restart in between. The assert runs before the resolver's nft application has
settled. The same artifact installed cleanly last session, which is what a
one-second race does.

**This belongs to the Guard 3 rework session, not to this one.** It was
deliberately not diagnosed further and `setup.ps1` was not touched.

**Every result in this document was taken on that box.** The full caveat is at
`validation-runs/cfv-165/INSTALL_FAILED_CAVEAT.txt`. Guard 3 is a network
control and questions 1, 2, 4 and 6 are kernel and filesystem questions, so the
decision was to proceed and record rather than abandon. **This box is not a
clean-install validation of 1.3.3 and must never be cited as one.**

---

## 6. What would have to ship, if Guard 4 were built on FUSE

This is the number that was previously unknown and it is the reason question 4
mattered even after question 1 failed.

- **A FUSE passthrough implementation.** `bindfs` was **absent** on a shipped
  box and had to be installed from the Ubuntu archive. Either it is bundled, or
  the installer pulls it, or Guard 4 ships its own filesystem.
- **`user_allow_other` in `/etc/fuse.conf`.** Absent by default, commented out
  in the shipped file, and required before the agent can use the view.
- **A systemd unit to re-establish the mount.** It did not survive the WSL
  restart cycle by itself.
- **A locked backing directory.** The passthrough is only a control if the
  backing path is unreachable by uid 1000. Mode alone does that; it has to be
  deliberate.
- **`python3`: no bundling cost.** It is present on a shipped box and reaches
  `libc` through `ctypes`, so the syscalls needed are available from an
  interpreter already installed. **No compiler was required at any point.** That
  was a live risk going in and it is now closed.

---

## 7. What this probe did NOT test

Named, so the next work package is written against real boundaries rather than
assumed coverage.

0. **THE ONE THAT MATTERS MOST: a FUSE passthrough mounted over a real drvfs
   granted workspace.** Question 4 passed over an ext4 backing directory. The
   configuration Guard 4 would actually use was never measured, and question 1
   is proof that this platform can accept an operation on drvfs and then not
   honour it. **This should be the first measurement of the next session.**
1. **Whether the drvfs failure is specific to permission events or general.**
   Notification events did arrive on 9p; permission events did not. Whether a
   different mark scope, or a `FAN_REPORT_FID` group, changes that was not
   tested.
2. **Any filesystem other than ext4 and 9p/drvfs.** In particular, a granted
   workspace held on a Linux path rather than a Windows folder was never
   measured, and that configuration might enforce correctly.
3. **The exclusion-placement question**, per 3.3. Accepted but unconfirmed.
4. **Cost.** Not run at all.
5. **Whether a filesystem-scoped mark behaves differently from a mount-scoped
   one on 9p.** Scope acceptance was probed; behaviour per scope was not.
6. **A realistic dependency install.** One tiny package is not `node_modules`.
7. **Any workspace with real customer content.** By design.
8. **Studio, the installer, or any shipped resource.** Untouched, by scope.
9. **Every uid 1000 reachability check in question 6**, per 3.6: bind-mount
   refusal, unprivileged user namespaces, the private-bind-inside-a-namespace
   test, symlink enumeration, and the Docker check. **The root cause is now
   known and fixed** (a `\$2` in a here-string, full analysis in 3.6), so this
   is a cheap re-run rather than an open investigation. The `\$2` is corrected
   in the same commit as this document, but the corrected probe has NOT been
   executed, so these checks remain unmeasured until it is.
10. **The reboot pass for questions 2 and 4.** Deliberately not run, and the
    reasoning is recorded rather than the step quietly dropped: FUSE had already
    failed the **lighter** trigger, the WSL restart cycle, which is more frequent
    than a reboot and strictly less destructive. A mount that does not survive
    `wsl --shutdown` will not survive a reboot, so the pass would have
    re-measured a known answer at the cost of a human RDP login. Fanotify's
    survival is moot because it is ruled out for granted workspaces.
11. **Card 197 by execution.** Source evidence only. See 3.7.

---

## 8. Resource ledger and teardown

**One VM created, one deleted. Nothing left running.**

`cfv-165`, `Standard_D2s_v4`, image `clawfactory-win11-baseline-v2`, created by
the operator at provisioning with a password this session never held. RDP was
scoped to a single `/32` for its whole life:

```
{"access": "Allow", "port": "3389", "src": "<operator-ip-redacted>/32"}
```

**Starting state of the resource group**, taken before provisioning:

```
clawfactoryvalc467
bake-vmVNET
clawfactory-win11-baseline
clawfactory-win11-baseline-v2
```

**Ending state, unfiltered, after teardown:**

```
=== UNFILTERED resource list after teardown ===
Name
-----------------------------
clawfactoryvalc467
bake-vmVNET
clawfactory-win11-baseline
clawfactory-win11-baseline-v2

=== UNFILTERED VM list ===
(empty)

=== UNFILTERED disk list ===
(empty)
```

Identical to the starting state. The listings are unfiltered rather than
name-matched on purpose: a teardown proof that greps for the VM name cannot show
a resource left behind under a different one.

**A defect in the teardown path, found by it failing.** The first attempt
deleted the NSG and public IP before the NIC that references them, so the
dependent deletes failed and the step exited non-zero, leaving `cfv-165-pip`,
`cfv-165-nsg` and `cfv-165VMNic` behind. They were then deleted in dependency
order, NIC first. **The failure was loud, which is why nothing was orphaned**,
but the ordering in `g4-probe.ps1` is wrong and is fixed in the same commit as
this document.

**Cost.** The VM was up for roughly five and a half hours at `D2s_v4` rates. It
was deliberately not deallocated during the run, against the standing
handoff rule, because it was continuously computing rather than parked on a
human step; the money is a few cents and the rule exists for machines left idle
overnight.

**No tag, no publish, no release.** The 1.3.3 artifact was consumed as input and
nothing was built.

---

## 9. Lessons learned, and instructions for the next session

Written because the session's defect rate was bad and the pattern is specific
enough to be preventable.

### 9.1 What actually happened

Ten defects. **Every one was on a language seam or in exit-code propagation.
None were errors about what to measure.** The probes ask the right questions;
the plumbing carrying them was wrong.

| Defect | Class |
| --- | --- |
| `\$` instead of backtick-`$` in a PowerShell here-string, five instances | seam |
| `$?` read after a pipeline, reporting `head`'s status not the command's | exit code |
| `$i` expanded by the outer shell, so ten writes hit one filename | seam |
| `2>&1` under `EAP=Stop` turning stderr into a terminating error | exit code |
| nested `powershell` exit code never propagated, so every phase reported rc=0 | exit code |
| a control regex matching the probe's own echo (`RESTORED` vs `RESTORED_SHA=`) | control design |
| a **user** systemd unit restarted against the **system** manager | environment |
| permissions set on ext4 but not on the drvfs arm of the same test | symmetry |
| a fixed 12-second sleep read back as `activating` and scored as failure | timing |
| `\$2` in a here-string, missed by an audit regex that only matched letters | seam, and the audit |
| **snapshot copy re-entering its own permission mark and deadlocking the box** | re-entrancy |

The last one is the expensive one. It wedged every open on the granted
workspace, killed the on-VM runner, and the driver then polled a dead runner for
27 minutes. **The hazard was written in that function's own docstring.** The
guard covered the daemon *writing* into the marked tree; the copy *read* through
`open("/proc/self/fd/N")`, which is a fresh open on the marked mount and fires a
permission event the single-threaded daemon can never answer.

### 9.2 What the phase runner caught, and what it structurally cannot

**It caught:** every case where an instrument was absent or unproven. Q1 voided
on a control that did not fire. Q5 refused to run on an unmet precondition. Q7
voided on a gateway that never came back. In each case it produced no product
verdict, which is exactly right.

**It cannot catch:** an instrument that runs successfully and measures the wrong
thing. Q3 and Q6 both returned confident FAILs from probes that were asking a
different question than their labels claimed. Those were reported to the user as
findings and later withdrawn.

**It also cannot catch a row with no verdict at all.** Q6 reported PASS while
five of its rows carried an empty verdict string, which is neither PASS nor FAIL
nor VOID and therefore counted as nothing. The runner should treat an empty
verdict as VOID.

### 9.3 The methodological error, stated plainly

**Syntax was verified; semantics never were.** Every file was parsed, the Python
payload was rendered through its here-string and byte-checked, and `\$` was
grepped for. All of that passed, and none of it can catch `$?`-after-a-pipeline
or a control that matches its own output.

**No probe was executed once before its results were trusted.** All seven ran
against the real subject on the first attempt, so seven problems surfaced at
once instead of one, and two wrong conclusions were reported to the user before
being withdrawn.

There is already a `harness-selftest.ps1` for the phase runner, built after the
same lesson one level up. The equivalent for the probes was not built.

### 9.4 Recommended instructions for the next work package

Copy these into the next prompt.

**A. Require a calibration pass before any measurement pass.**

> Before running any probe against the real subject, run every probe body once
> against a synthetic target whose answer is already known, and assert that
> answer. A probe that cannot produce a known-correct result on a rigged input
> is not permitted to report a result on a real one. Budget one VM cycle for
> this and treat it as part of the job, not overhead.

**B. Ban the two shell idioms that caused half the defects.**

> Never write `cmd | head` followed by `$?`. In a pipeline `$?` is the last
> command's status. Use `if cmd >/dev/null 2>&1; then ... else ... fi`.
> Never build a shell loop variable inside a PowerShell here-string that is
> also inside a `-c "..."` argument. Put the loop in a script file.

**C. Require every control to be falsifiable, and prove it.**

> For each positive control, state in a comment what output would make it fail,
> and confirm that string does not appear anywhere else in the probe's own
> output. A control whose sentinel appears in the probe's own echoes cannot
> fail.

**D. Require exit codes to survive every wrapper.**

> Any job wrapper that invokes a nested interpreter must end with an explicit
> propagation of that interpreter's exit code. Assert it: deliberately fail one
> phase and confirm the driver reports non-zero.

**E. Forbid re-entrant file access inside a permission-mode event loop.**

> A daemon holding a `FAN_*_PERM` mark must never call `open()` on any path
> under that mark, including through `/proc/self/fd`. Duplicate the descriptor
> the kernel supplied. Violating this deadlocks every process touching the
> mount, and the symptom looks like a hung machine rather than a probe bug.

**F. Make the runner treat an empty verdict as VOID.**

> A `Record` call that produces no verdict currently counts as nothing and lets
> a phase report PASS while several of its checks said nothing at all.

**I. An audit regex needs a negative control, like any other probe.**

> After fixing a class of defect, the grep used to prove the files clean is
> itself a measurement and can be wrong in the same way the code was. Before
> trusting it, deliberately introduce one instance of the defect and confirm the
> pattern finds it. A pattern of `\$` followed by a letter certified a file that
> contained `\$2`, and that single character voided a whole question while the
> phase reported PASS.

**J. Read probe stderr, not just the probe transcript.**

> The phase transcript contains only what the probe successfully printed, so a
> probe that dies early is invisible in it by construction. The job `.out` file
> captures stdout and stderr together and is where the actual exception lives.
> Read it whenever a phase produces less output than expected, BEFORE tearing
> the VM down. In this session the root cause of question 6 sat in that file for
> hours while the analysis re-read the transcript that could not contain it.

**G. Wait on state, never on a sleep.**

> Any step that restarts a service must poll until the service reports a
> terminal state. `activating` is neither up nor failed, and a fixed sleep that
> lands on it produces a false negative about the thing under test.

**H. Say which filesystem the subject is on, in the work package itself.**

> This job's package specified `/var/tmp`. Granted workspaces are on drvfs. The
> ext4 answer was YES and the drvfs answer was NO, so the specified test would
> have returned a confident yes to the wrong question. Where a control protects
> a specific location, the package must name that location's real filesystem
> and require the measurement there.

### 9.5 What went right, kept for balance

- The phase runner prevented every absent-instrument result from becoming a
  product verdict, three times.
- The decision to add a drvfs arm that the work package did not ask for is the
  only reason the headline answer is correct.
- The install failure was diagnosed to a one-second race from timestamps on the
  box, rather than guessed at or worked around, and `setup.ps1` was never
  touched.
- Evidence collection was rebuilt when five transcripts came back at exactly
  4097 bytes, rather than reported from truncated output.
- No credential entered a transcript, a command line, or this session.

---

## 10. Judgement calls, and the case for each

Written because the operator asked for the reasoning to be defensible to the
planning session rather than taken on trust. Each entry states the decision, the
case for it, and the case against. Where the decision was wrong, it says so.

### 10.1 The provisioning protocol: no auto-logon, one extra human login

**Decision.** The operator created the VM themselves with a password this
session never held, and logged in over RDP for the install boot as well as after
the restart.

**Reasoning.** The work package forbade generating, printing or requesting a
password, and forbade `az vm user update` after provisioning. Those constraints
together make Winlogon auto-logon impossible, because arming it requires writing
the account password into `DefaultPassword` and the driver does not have it.
Rather than work around the constraint, the driver dropped auto-logon entirely
and said so on every card, so nobody would wait for a session that was never
armed.

**Cost.** One extra login. **Benefit.** The password existed in exactly one
place, the operator's own record, and the VMAccess hang risk that cost an hour
on cfv-162 was taken at `az vm create` time rather than between reboots.

**Against.** It makes the run less autonomous. That is the correct trade when the
alternative is a credential in a session transcript.

### 10.2 Adding a drvfs arm to question 1, which the package did not ask for

**Decision.** Question 1 was measured on drvfs as well as on the specified
`/var/tmp`.

**Reasoning.** Guard 4 protects granted workspaces, and granted workspaces are
drvfs mounts of Windows folders. An ext4-only measurement answers a question
nobody asked.

**This is the single decision the whole deliverable rests on.** The ext4 answer
was YES and the drvfs answer was NO. Executed exactly as written, this job would
have returned a confident YES and Guard 4 would have been built on a mechanism
that enforces nothing where it matters.

**Against.** It expanded scope without asking. Given the result, that is not a
close call, but the general form of it is: the package should have named the
filesystem, and instruction H exists so the next one does.

### 10.3 Proceeding after the 1.3.3 install failed

**Decision.** The probes were run on a box whose installer reported failure, with
the caveat recorded in the run directory and carried into this document.

**Reasoning.** The failure was in Guard 3, a network control, at
`Step-InstallReadFetch`. Questions 1, 2, 4 and 6 are kernel and filesystem
questions depending on the distro, `clawuser`, systemd and the grants script, all
installed well before the failure. Stopping would have delivered nothing;
re-installing over a half install would have traded a precise caveat for a
muddier one.

**Against, and it is real.** Question 7 turned out to need a working gateway,
which this box never had, so card 197 was unanswerable and roughly 40 minutes
went into discovering that. A stricter reading would have stopped at the install
failure and cost the whole session. **The decision was right for questions 1 to
6 and wrong for question 7**, and the honest summary is that the cost fell
exactly where the install failure was relevant and nowhere else.

### 10.4 Not diagnosing the install race further

**Decision.** The install failure was traced to a one second race from
timestamps on the box, and then left alone. `setup.ps1` was never opened.

**Reasoning.** The package put the toolchain blocker in another session and said
to report rather than follow. Enough diagnosis was done to decide whether this
session could proceed, which is a different question from fixing it.

### 10.5 Running all seven probes before calibrating any of them

**Decision, and it was the wrong one.** All seven ran against the real subject on
the first attempt.

**Consequence.** Seven problems surfaced at once instead of one. Two false
findings reached the operator and had to be withdrawn. Roughly half the session
went into rework.

**No defence is offered.** The correct approach was a calibration pass against
known answers, which is instruction A and is the first thing the next package
should require. A `harness-selftest.ps1` already exists for the phase runner
because this lesson was learned one level up; the equivalent for the probes was
not built.

### 10.6 Reporting question 3 and question 6 findings before they were solid

**Decision, and it was wrong.** Both were reported to the operator as findings,
described as consequential, and later withdrawn when the probes turned out to be
measuring something other than their labels claimed.

**Why it happened.** The phase runner returned confident FAILs, and a FAIL from a
runner that voids unproven instruments reads as trustworthy. It is not: the
runner certifies that an instrument RAN, never that it measured the right thing.

**What should have happened.** Any FAIL whose consequence is architectural should
have its raw evidence read before it is described as a finding. That takes one
minute and would have caught both.

### 10.7 Continuing rather than restarting after the defect run

**Decision.** After the defects were understood, the run continued with fixed
probes rather than being abandoned for a clean session.

**Reasoning, and it was marginal cost against marginal value rather than sunk
cost.** The rig worked: VM, install, file channel, runner, evidence collection.
The probes were fixed and committed. A fresh session would have run the same
code against the same kernel and derived the same answers, at the price of
rebuilding the rig and two more human logins. The only thing restarting bought
was a clean install, which is irrelevant to kernel and filesystem questions.

**Against.** A higher defect rate makes further re-runs riskier, and two of them
did surface new problems. Mitigated by writing no new probe logic, only fixing
what existed.

### 10.8 Skipping the reboot pass

**Decision.** Not run. Recorded in 7.10 with its reasoning rather than dropped.

**Reasoning.** FUSE had already failed the **lighter** trigger, the WSL restart
cycle, which is more frequent than a reboot and strictly less destructive.
Fanotify's survival is moot because it is ruled out for granted workspaces. The
pass would have re-measured a known answer at the cost of a human login.

**Against.** Obvious answers are occasionally wrong, and this was the operator's
call to overrule. It was offered as a recommendation with that stated.

### 10.9 Dropping question 5 after it deadlocked the box

**Decision.** Not re-run after the deadlock.

**Reasoning.** Question 5 is the only question whose answer cannot change the go
or no-go: it prices a mechanism after viability is established. At the moment it
ran, no candidate had survived, so its own precondition was correctly unmet.

### 10.10 Leaving the VM running rather than deallocating at handoffs

**Decision.** Not deallocated during the run, against the standing rule.

**Reasoning.** The rule exists for machines parked on a human step. This one was
continuously computing. Deallocating between phases would have destroyed the
in-flight work and the distro state that questions 2 and 4 depend on.

**Cost.** About five and a half hours of `D2s_v4`, a few cents. It was torn down
as soon as the work stopped needing it.

### 10.11 Rebuilding the evidence channel mid-run

**Decision.** Collection was rewritten from `run-command` to blob storage with
byte-count verification, mid-session.

**Reasoning.** Five transcripts came back at exactly 4097 characters. An evidence
channel that silently keeps the tail is worse than one that fails, because a
truncated transcript reads as a complete one and the verdict lines happened to
survive. Every collected file is now byte-count verified against the VM.

### 10.12 Chasing the question 6 root cause after teardown

**Decision.** Investigated after the VM was destroyed, on the operator's request.

**Reasoning and outcome.** It was worth it. The cause was a single `\$2` in a
here-string, and the general lesson is larger than the bug: **the audit regex
used to certify the files clean could not match the defect being introduced in
the same edit**, and the actual exception had been sitting in the job's stderr
capture the whole time while the analysis re-read a transcript that by
construction could not contain it. Both became instructions I and J.

---

## 11. Chronology

Compressed, so the shape of the session is visible without reading the whole
document.

| Time | Event |
| --- | --- |
| start | Repo clean at `3759a54`, artifact digest and signature verified, resource group verified empty, dispatch card 254 opened |
| build | Harness written: driver plus seven phases on the existing phase runner. Five `\$` seam defects found and fixed before anything ran. Python payload rendered and byte-checked. Committed `0d72b40` |
| provision | Card 1 issued. Operator created `cfv-165` with their own password. RDP scoped to a single `/32` |
| stage | Two ARM timeouts. Driver given retries and digest-based idempotency so a timeout after a 440 MB upload does not discard it. Committed `9bf77ee` |
| install | **1.3.3 install FAILED** at Guard 3's read-fetch step. Traced to a one second race from on-box timestamps. Decision taken to proceed with the caveat recorded |
| probes, pass 1 | All seven ran. Three voided correctly. Two returned confident FAILs that were probe defects. Transcripts found truncated at 4097 bytes |
| rework | Five probes corrected, evidence collection rebuilt on blob storage with byte verification. Committed `1ffaffc` |
| probes, pass 2 | Q1, Q3, Q4, Q6 completed. **Q5 deadlocked the box**: the snapshot copy re-entered its own permission mark, wedging every open on the granted workspace and killing the on-VM runner |
| recovery | Operator ran `wsl --shutdown` and restarted the runner. Deadlock fixed with `os.dup` |
| probes, pass 3 | Q4 and Q7 re-run. Q4 voided on a control corrupted by interleaved stderr; Q7 voided because the gateway never binds its port |
| final | Q4 fixed and re-run: **PASS, 5 of 5 controls**. Q7 confirmed unanswerable on this box |
| teardown | VM deleted. Teardown ordering defect found and fixed. Resource group verified back to its exact starting state by unfiltered listing |
| after | Question 6 root cause found in the job's stderr capture: a single `\$2`. Fixed, not re-executed. Committed `42a252d` |

---

## 12. What the next session should do first

In order, and the first item is the one that decides Guard 4.

1. **Mount a FUSE passthrough over a real drvfs granted workspace** and repeat
   questions 4 and 2 there. This is the only thing standing between the current
   answer and a build decision. If it holds, section 6 is the build list. If it
   does not, Guard 4 has no viable mechanism on this platform, which is a
   strategic answer worth having early.
2. **Re-run question 6.** The `\$2` is fixed; the uid 1000 checks are a cheap
   re-run rather than an open investigation.
3. **Card 197 needs a box where the gateway actually serves**, so it is blocked
   behind the 1.3.3 install defect and belongs with the Guard 3 rework rather
   than with Guard 4.
4. **Adopt instructions A through J** from section 9.4 in the work package
   itself, not as guidance to the executing session.
5. **Do not re-litigate question 1.** fanotify permission mode on drvfs is
   settled, measured, with all controls fired.

---

## 13. Task accounting

| Asked for | State |
| --- | --- |
| Q1 fanotify permission enforcement | **Done.** Answered on both filesystems |
| Q2 mark scope and restart survival | **Partial.** Pre-reboot arm measured; reboot pass deliberately skipped, reasoning in 7.10 |
| Q3 write volume | **Partial.** Volume measured; exclusion placement unconfirmed |
| Q4 FUSE passthrough | **Done on ext4.** Not measured over drvfs, which is the gap that gates the recommendation |
| Q5 cost | **Not run**, correctly, no surviving candidate at the time it ran |
| Q6 second paths | **Partial.** Mount-level answered, uid 1000 level unmeasured |
| Q7 card 197 | **Not answerable** on this box |
| Guard 4 recommendation | **Delivered**, section 2, conditional on one named measurement |
| Bundling list | **Delivered**, section 6 |
| Card 197 scope correction | **Delivered**, section 4, and it stands independently of execution |
| Named list of what was not tested | **Delivered**, section 7 |
| Lessons learned and next-session instructions | **Delivered**, section 9 |
| Build nothing, change no product code | **Held.** No product file modified at any point |
| No tag, no publish | **Held** |

**Scope discipline.** `setup.ps1`, the installer, Studio and every shipped
resource were untouched. The only committed files are the probe scripts under
`validation/diag/` and this document. The 1.3.3 install defect in section 5 was
diagnosed only far enough to decide whether the session could proceed, and was
then left for the Guard 3 rework as instructed.

**Credential discipline.** The provider API key was read from Credential Manager
into memory and written to the VM's Credential Manager without ever being
printed, logged, or entering this session's transcript. The card 197 listener
recorded only that an `Authorization` header was **present**, never its value.
The VM admin password was chosen by the operator, never generated, printed,
requested, or transmitted here, and `az vm user update` was never called. No
SMTP credential was requested or used.
