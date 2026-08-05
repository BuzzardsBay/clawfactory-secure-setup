# Interim clean-box validation, v1.2.0. Close-out.

**This is an interim validation of a build carrying Guards 1 and 2 only. It is NOT the
release gate.** Guard 3, Guard 4, the guardrail config pass and the honest-copy pass are
all unbuilt. Step 7 of the build sequence, full validation on the assembled build, still
happens after those land. Nothing in this document should be read by a later reader,
including a later CC session, as clearing v1.2.0 to ship.

**Result: the install FAILED at the Phase 1 checkpoint. The guard suite did not run.**
The failure is the output of this session, per the job's own stop rule.

- Date: 2026-08-05
- Artifact: `ClawFactory-Secure-Setup.exe`, v1.2.0, 440,575,752 bytes,
  sha256 `6f378d3ad731739e09a086e68eb898dcd446c3e6337ec8e118134ea183624bf9`
- Digest verified before anything else, locally and again on the VM after transfer. Match.
- Authenticode: Valid, `CN=Bret Mckinney`. The Authenticode TIMESTAMP test was NOT run
  here; it is decoupled, needs a date after 2026-08-06 19:31Z and no VM, and sits on the
  pre-launch checklist.
- VM: `cfv-153`, created 15:37 and deleted 16:37 MDT. Ledger reconciles, see section 8.
- Dispatch card: #215.

---

## 1. The finding, stated plainly

**On a clean Windows 11 box, installing v1.2.0 with the shipping installer installs
NEITHER Guard 1 NOR Guard 2.** The install aborts partway with:

```
[2026-08-05 22:29:30] [INFO] Step 15e [Guard 1]: Installing the delete quarantine (broker + retention timer + rm wrapper).
[2026-08-05 22:29:31] [ERROR] Install failed: Exception calling "Start" with "1" argument(s): "The filename or extension is too long"
[2026-08-05 22:29:31] [ERROR] at Invoke-WslBash, setup.ps1: line 671
                              at Step-InstallQuarantine, setup.ps1: line 2683
                              at Invoke-WithRollback, setup.ps1: line 628
[2026-08-05 22:29:31] [INFO] INSTALLER_DONE=failure reason=... "The filename or extension is too long"
```

### Mechanism

`Invoke-WslBash` (setup.ps1:659-671) base64-encodes the entire script it is given and
passes it as a single command-line argument:

```powershell
$enc = [Convert]::ToBase64String(...)                    # whole script, base64
$psi.Arguments = "-d $WslDistro -u $User --cd ~ -- bash -lc `"echo '$enc' | base64 -d | bash -l`""
$proc = [System.Diagnostics.Process]::Start($psi)        # <-- throws here
```

`Step-InstallQuarantine` (setup.ps1:2660-2683) builds its script by base64-embedding eight
resource files INTO that script. So the payloads are base64-encoded twice: once into the
bash script, then again by `Invoke-WslBash` onto the command line. Windows
`CreateProcess` caps a command line at 32,767 characters.

Measured across every step that uses this pattern:

| Step | Files | Inner base64 | Resulting command line | vs 32,767 limit |
|---|---|---|---|---|
| 15b `Step-InstallTurnGate` | 4 | 12,860 | 17,208 | ok, 15,559 to spare |
| 15d `Step-InstallChatProxy` | 3 | 21,460 | 28,676 | **ok, only 4,091 to spare** |
| 15e `Step-InstallQuarantine` (Guard 1) | 8 | 63,472 | **84,692** | **OVER by 51,925** |
| 15f `Step-InstallSend` (Guard 2) | 11 | 115,388 | **153,912** | **OVER by 121,145** |

Three consequences, all load-bearing:

1. **Guard 1 cannot install.** Deterministic, not environmental. It will fail on every
   Windows machine, every time.
2. **Guard 2 cannot install either.** It never even executed this run, because 15e throws
   first and `Invoke-WithRollback` aborts. Its payload is over the limit by nearly four
   times the limit itself, so fixing only 15e would move the failure to 15f, not resolve it.
3. **`Step-InstallChatProxy` is 4,091 characters from the same cliff.** It passes today by
   luck, not by design. Any growth in `clawfactory-proxy.js` or `install-chat-proxy.sh`
   silently converts a working install into a failing one. It should be treated as part of
   the same defect, not left to be discovered later by a customer.

### Why this was not caught before

Guard 1's close-out recorded it as shipped but **not clean-box tested**, and Guard 2's
section 5 suite ran against the dev box, where the components were already present by
other means. This session is the first time either guard has been installed by the
shipping installer on a clean machine. The very first attempt failed. That is the value
this job delivered, and it is the reason the job existed: to prove the install path still
works after the persona rewrite, the six new gates and the version change.

The defect is NOT caused by any of those three changes. It is a latent property of
`Invoke-WslBash` that Guard 1 and Guard 2 were the first payloads large enough to trigger.

### Not fixed here, deliberately

Per the job's scope rule, a defect found by validation gets its own job so the fix is not
entangled with the evidence that found it. No product code was changed in this session.
The shape of the fix is not in doubt: the script must reach the distro as a FILE rather
than as a command-line argument, which is the same conclusion the validation channel
reached independently (section 5).

---

## 2. Phase 1, corrected results

The probe initially reported four FAILs. **Three of them were my harness bugs, not product
failures**, and are corrected below with the evidence that settles each. Reporting them as
product defects would have manufactured three defects and buried the one that matters.

| Check | Reported | Corrected | Evidence |
|---|---|---|---|
| P1.0 baseline recorded | INFO | INFO | clean box, no ClawFactory, no distro |
| P1.1 artifact hash re-derived on VM | INFO | INFO | `6f378d3a...` matches the pin |
| P1.2 Step-Preflight passed | FAIL | **PASS** | `Preflight: all 30 security resources present.` Probe read the wrong log path. |
| P1.3 30 resources on disk, independent enumeration | PASS | PASS | 30/30, enumerated by the probe, not by the installer |
| P1.3c CONTROL absent resource not found | PASS | PASS | discriminates |
| P1.5 `install-result.txt` reports success | FAIL | **FAIL** | `INSTALLER_DONE=failure`. **This is the real defect.** |
| P1.6 transcript captured | FAIL | **PASS** | log present at `C:\ProgramData\ClawFactory\install.log`, 22,676 B |
| P1.CHAN file-based WSL channel discriminates | PASS | PASS | subject `id -u`=0, control `/bin/false` rc=1, expansion intact |
| PIN 1of7 persona | PASS | PASS | `0557d070...` |
| PIN 2of7 SOUL (Windows side) | PASS | PASS | `e7021260...` |
| PIN 2of7 SOUL in distro | PASS | PASS | matches |
| PIN 2of7 root-owned `/etc/clawfactory/soul.sha256` | PASS | PASS | matches |
| PIN 3of7 composed workspace SOUL | FAIL | **PASS** | `[injected-soul] frozen + pinned: 441b6279...` matches exactly. Probe guessed three fixed paths and missed the file. |
| PIN 4of7 rootfs | INFO | INFO | tarball lands in `{tmp}` and is removed, so its hash is not re-derivable post-install. Recorded as the weaker claim rather than dressed up. |
| PIN 5of7 embedded Studio payload | PASS | PASS | `b701bfb7...` |
| PIN 6of7 version reports 1.2.0 | PASS | PASS | uninstall key |
| PIN 7of7 bundle completeness | PASS | PASS | all 30 shipped |

**Corrected tally: 13 PASS, 1 FAIL, 3 INFO.** The single FAIL is the install itself.

All seven build-time pins were satisfied. Six were verified by execution on the installed
machine. The seventh, rootfs, is attested by the install log rather than re-derived, and
that limitation is stated rather than glossed.

**Phase 1 item 6, the reboot check, was NOT run.** Confirming that units, timers, sockets
and firewall rules return with correct ownership after a reboot is not meaningful when the
units in question were never installed.

---

## 3. Phases 2, 3 and 4: not run

| Phase | Status | Reason |
|---|---|---|
| 2. Guard 1 routing, including the never-run test | **NOT RUN** | Guard 1 is not installed. There is no broker, no `rm` wrapper, and no `pathPrepend` entry to exercise. |
| 3. Guard 2 full section 5 suite on a real install | **NOT RUN** | Guard 2 is not installed. Step 15f never executed. |
| 4. Structural properties | **NOT RUN** | Depends on the Guard 2 firewall and credential surfaces, which are absent. |

The probes for all three phases were written, parse-checked and are committed with this
close-out. They are ready to run unchanged against a build whose install completes.

---

## 4. Did any claim anywhere in the product become untrue?

**Yes. This is the most important line in this document.**

Any customer-facing statement that v1.2.0 delivers recoverable deletes (Guard 1) or
approval-gated email (Guard 2) is **untrue of the shipping installer as built**. Not
weakened, not partially true: on a clean machine, neither guard is present at all, and the
install reports failure.

This does not mean the guards are wrong. Their mechanisms were validated on the dev box and
those results stand on their own terms. It means the guards **do not reach the customer**,
which for shipping purposes is the same as not having them.

Two specific claims to correct or withhold until a build installs cleanly:

- The Guard 1 promise that deletes are recoverable for 30 days. On this build a delete is
  permanent, because the wrapper that would intercept it does not exist. This is the exact
  failure mode `Step-InstallQuarantine` guards against in its own error text: *"Deletes
  would be permanent while the product says they are recoverable - do not ship this
  install."* That guard fired correctly. It refused the install rather than shipping a
  false promise, which is the behaviour we want.
- The Guard 2 claim below must not be made about a shipped v1.2.0 build until the install
  lands the broker.

---

## 5. Structural versus advisory, as installed

Carried forward from the Guard 2 build close-out section 6.3, **updated with what this
session found**. The change is not a nuance:

> **As installed by the shipping v1.2.0 installer, Guard 1 and Guard 2 are neither
> structural nor advisory. They are absent.** Every property below describes the guards as
> designed and as validated on the dev box. None of them is true of a clean install of this
> build.

Structural when installed, and these remain the load-bearing claims:

- No send capability at uid 1000. No credential, no transport, no socket that executes.
- The agent cannot approve. Two independent mechanisms, either sufficient alone: 0750
  root:root on the control tool, and 0600 root:root on the admin socket.
- Approved bytes are the sent bytes. Attachments staged root-owned at request time, read
  performed as the agent via `setpriv`, so check and copy are one operation.
- Single use, hash-bound.
- No route to SMTP for uid 1000 at any destination, including loopback.
- The credential is unreadable by the agent and never appears in argv, logs, receipts or errors.

Broker-enforced, NOT firewall-enforced, and it must always be described that way:
destination scoping. The nft chain begins `meta skuid != 1000 return`, so the broker's
reach is emergent rather than granted. There is no port-scoped exemption for the broker and
none should ever be added.

### Every known bypass, named

1. **The agent can exfiltrate to the model provider.** The gateway runs as uid 1000 and
   holds the provider credential; anything the agent can read can leave over the
   allowlisted 443 route. No v1 guard touches this. Card #197.
2. **Full-path `.mjs` / direct execution (Door 2).** Agent and gateway share a uid. Standing
   v1 structural residual, accepted and documented.
3. **Co-hosted addresses re-open 443, never an SMTP port.** Scoped residual. Was to be
   re-measured in test 9b this session; not measured, because Guard 2 is not installed.
4. **Allowlisted addresses persist up to six hours** after a host is removed from source.
   Card #194.
5. **Nothing enforces `read_fetch`.** Declarative only in v1; must not be described as a
   control until Guard 3 wires it up.
6. **A user who approves without reading is not protected.**
7. **NEW, from this session: PATH-based delete interception is advisory by construction.**
   Guard 1 intercepts deletes via `tools.exec.pathPrepend` placing a wrapper `rm` ahead of
   `/bin/rm`. `/bin/rm`, `/usr/bin/unlink`, `node fs.unlinkSync` and shell truncation all
   bypass it. This was already understood as a disclosed limit; this session was to have
   measured it rather than assumed it, and did not get to. It is recorded here as
   still-unmeasured so it does not silently become an assumed number.
8. **NEW, from this session: the installer's own delivery path is a single point of
   failure for every guard.** All four security steps push their payload through one
   `Invoke-WslBash` command-line channel with no size guard. Any guard that grows past the
   limit disappears from the product at install time, and until this run nothing tested for
   it.

---

## 6. The honest claim sentence

Unchanged in wording, but it may **not** be attached to a shipped v1.2.0 build until the
install actually lands the broker:

> Your agent can write an email. It cannot send one. Every message waits for you, and
> approving it sends exactly that message, once.

And the boundary, which must accompany it wherever the mechanism is described:

> This covers email. It is not a claim that no data can leave your machine: your agent
> talks to a hosted AI model, and anything it can read it can send there.

The sentence this project must never write, here or anywhere: that data cannot leave the
machine without approval. It can, and that is inherent to any local agent calling a hosted
model. Guard 2 gates email. It does not gate egress.

---

## 7. Carried-forward tests, so nothing blocked here gets lost

| Test | Owner | Status | Why |
|---|---|---|---|
| Phase 1.6 reboot: units, timers, sockets, firewall return with correct ownership | Phase 1 | CARRIED | guard units never installed |
| Guard 1 real agent turn, unprompted deletion routes to quarantine | Phase 2.1 | CARRIED | **still never executed; the claim remains INFERRED** |
| Guard 1 shell-primitive bypass, measured not assumed | Phase 2.2 | CARRIED | probe written, ready |
| Guard 1 restore path, sha256 verified before write, ownership | Phase 2.3 | CARRIED | probe written, ready |
| Guard 1 store cap and free-space guard refuse loud, no eviction | Phase 2.4 | CARRIED | probe written, ready |
| Guard 1 no purge API anywhere including Studio | Phase 2.5 | CARRIED | probe written, ready |
| Guard 2 section 5 tests 1 to 14 on a real install | Phase 3 | CARRIED | probe written, ready |
| Card #198 external delivery to a third-party mailbox | Phase 3 | **BLOCKED, carried** | never reached. Bret was to enter a real app password himself in the Studio panel; the install never produced a Studio SMTP panel to enter it into. **Not substituted with a local sink.** |
| Card #199 discoverability from the shipped SOUL and persona | Phase 3 | CARRIED | probe written, ready |
| Studio approval card and Recently-deleted panel driven to completion | Phase 3 | CARRIED | first build to carry either; untested |
| Agent-cannot-approve against the installed Studio | Phase 3 | CARRIED | probe written, ready |
| Structural: SMTP blocked at every destination with 443 control | Phase 4.1 | CARRIED | probe written, ready |
| Structural: block holds across the shipped refresh | Phase 4.2 | CARRIED | probe written, ready |
| Structural: chain-shape tripwire fires on a widened accept | Phase 4.3 | CARRIED | probe written, ready |
| Structural: credential unreadable and absent from every surface | Phase 4.4 | CARRIED | probe written, ready |
| Structural: kill switch cancels pending and purges staging | Phase 4.5 | CARRIED | probe written, ready |
| Structural: 1, 3 and 4 re-run after reboot | Phase 4.6 | CARRIED | probe written, ready |
| Authenticode timestamp check | pre-launch | NOT RUN BY DESIGN | decoupled; needs a date after 2026-08-06 19:31Z, no VM |

---

## 8. Resource ledger

| Resource | Created | Disposed | Proof |
|---|---|---|---|
| VM `cfv-153` (Standard_D2s_v4, westus2) | 2026-08-05 15:37 MDT | **DELETED** 16:37 MDT | teardown proof: `CLEAN -- no resource matching 'cfv-153' remains` |
| `cfv-153-osdisk`, `cfv-153-pip`, `cfv-153-nsg`, `cfv-153VMNic` | with the VM | DELETED | each deleted by explicit name |
| License slot `02d0ebea-...` | at install | DEACTIVATED | `success=True msg=Machine deactivated successfully.` |
| Blob container `validation` in `clawfactoryvalc467` | 2026-08-05 15:46 | **RETAINED** | created by this harness; holds the run's artifacts and evidence. Deliberate: reused by the re-run. |
| Sweep list | during run | de-registered | `0 still registered` |

Total VM lifetime approximately one hour. Nothing left running.

---

## 9. Deviations from the job prompt, both verified live before deviating

1. **VM size.** The prompt specifies `Standard_D2s_v5`. Live quota for the DSv5 family in
   westus2 is **limit=0, current=0**, so that size cannot provision at all. Used
   `Standard_D2s_v4` (limit=10), which is what every recent green run used and what
   `scripts/azure-validate.ps1` already documents.
2. **Image.** The prompt specifies `clawfactory-win11-baseline`. Used
   `clawfactory-win11-baseline-v2`, which carries the newer WSL and is what the last two
   green runs (cfv-151, cfv-152) used.

Neither deviation contributed to the failure: the install got to step 15e and died on a
string-length limit that is independent of host size and base image.

---

## 10. Harness work, and three bugs it found in itself

A new harness was written for this job because the JOB 3 shape does not fit it. JOB 3 is
fire-and-forget: arm, reboot, poll one sentinel, retrieve, tear down. This job needs a hard
checkpoint after Phase 1, a human-in-the-loop step in Phase 3 where Bret types an SMTP app
password into Studio himself, and Studio GUI surfaces driven to completion. So the VM stays
up between phases and the driver feeds an on-VM runner.

New files, all committed:

| File | Role |
|---|---|
| `validation/interim-v120-validate.ps1` | driver: preflight, provision, stage, arm, poll, retrieve, evidence gate |
| `validation/interim-v120-runner.ps1` | on-VM job watcher in the interactive session |
| `validation/interim-v120-job.ps1` | submit a phase to the runner and bring its evidence back |
| `validation/interim-v120-wslchan.ps1` | the file-based WSL channel and its self-test |
| `validation/interim-v120-phase1.ps1` | Phase 1 probe |
| `validation/interim-v120-phase2.ps1` | Phase 2 probe, ready to run |
| `validation/interim-v120-phase3.ps1` | Phase 3 probe, ready to run |
| `validation/interim-v120-phase4.ps1` | Phase 4 probe, ready to run |

### The channel

The job's rule is file-based only, no nested `wsl.exe -- bash -c`. The obvious file channel,
`bash /mnt/c/...`, **cannot** be used: the installer deliberately writes
`[automount] enabled=false` and verifies it section-aware, because the P0 file-isolation
guard depends on the agent having no automatic view of the Windows filesystem. A probe
needing `/mnt/c` would only work on a broken install. So the payload goes the other way,
over the 9p server that exposes the distro to Windows: LF-only bytes written to
`\\wsl$\Ubuntu\tmp\...`, executed by Linux path, output redirected to a file. Every job runs
a channel self-test first, with a control that must fail.

The channel worked. `P1.CHAN` passed: subject reported uid 0, the `/bin/false` control
reported rc=1, and variable expansion stayed intact.

Incidentally confirmed: `az vm run-command` runs as SYSTEM and cannot touch WSL at all
(`WSL_E_LOCAL_SYSTEM_NOT_SUPPORTED`). That is why the interactive runner is mandatory rather
than a convenience, and it is worth knowing before someone tries to simplify the harness.

### Three harness bugs, all mine, all caught before they became false findings

1. **Silent upload failure.** The `validation` container did not exist in
   `clawfactoryvalc467` (the account carries `installers` and `logs`). All four uploads
   failed, and because an az failure does not stop the script (L6) the driver printed
   "uploaded" four times before the VM reported `ContainerNotFound`. Fixed: create the
   container idempotently, then verify every upload by exit code AND by asking the service
   for the blob's actual byte count.
2. **Wrong log path.** The probe looked for `...\ClawFactory\logs\setup.log`; setup.ps1
   writes `...\ClawFactory\install.log`. Two FAILs manufactured for a log that was present
   and complete. Fixed: resolve by search across candidates.
3. **Guessed pin path.** The workspace-SOUL check tried three fixed paths, missed the real
   file, and reported FAIL for a pin the installer had satisfied exactly. Fixed: `find` the
   file instead of guessing.

A fourth bug was caught by reading rather than by running: the Phase 3 lifecycle block was
drafted as a double-quoted PowerShell here-string carrying bash with `\$1` and `$SEND`. The
here-string escape character is the backtick, not the backslash, so `\$1` would have reached
bash as a bare backslash and `$SEND` would have expanded to an empty PowerShell variable.
It would have run, printed results, and meant nothing. Rewritten as a literal here-string
with one explicit placeholder substitution.

All three bug classes share one shape, and it is the same shape as L20, L21 and L22: the
transport mangles the payload, and the output still looks like a measurement.

### A third instance of a known trap

`validation/job3-teardown.ps1` carries the `[CmdletBinding()]` plus `-File` bug that empties
`$PSScriptRoot` inside param defaults; it died on `Split-Path` before doing any work. Worked
around with an explicit `-OutDir`. The script was not modified, since it is not this job's
code. This is now the third known instance, after `build_release.ps1` (fixed) and
`sign_installer.ps1` (latent).

---

## 11. Recommended next job

One job, not two, because fixing 15e alone just moves the failure to 15f:

1. Change `Invoke-WslBash` to deliver its script as a FILE rather than as a command-line
   argument, and add a loud size guard so this class fails at build time rather than on a
   customer's machine.
2. Re-run this validation unchanged. All four phase probes are committed and ready.

The re-run needs a fresh VM and roughly the same hour. Card #198 still needs a real
account with an app password, entered by Bret on the VM.

---

## 12. End-of-session gate

- Digest verified before any other work. Match. No other binary was used.
- Every block assertion that ran carried a paired control. The one channel assertion that
  gates all others (`P1.CHAN`) passed with its control failing correctly.
- No product code changed. No tag. No publish. No Inno licence purchased.
- Three harness bugs found and fixed; one caught by review before it ran.
- One ship-blocking product defect found, quantified, and left unfixed by design.
- Resource ledger reconciles: one VM created, one VM deleted, zero running.
- Card #215 moved to done with the finding recorded.
