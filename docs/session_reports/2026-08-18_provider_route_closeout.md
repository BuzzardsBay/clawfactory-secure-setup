# Close-out: the provider route missing from the egress allow-list

Session 2026-08-18. Dispatch card #257. Input artifact 1.3.4, signed
`ee6a5cd0232d7eb039182fe45e967cf2407e4ccd70f2e06540e06c93b89b5214`, 440,607,456
bytes, Authenticode Valid, verified byte for byte on disk before anything was
read or changed.

**STATUS: COMPLETE. Tasks 1, 2 and 3 all done. NO FIX WAS APPLIED, and that is
the correct outcome rather than an unfinished one.**

---

## 1. The three answers worth reading first

**The reported defect does not reproduce, and all four candidates are refuted by
measurement.** On `cfv-168`, a clean install of the same 1.3.4 artifact through
the same harness with the same `/PROVIDER=claude`, `@allowed_ipv4` held 24
addresses INCLUDING `160.79.104.10`, the 443-scoped accept was present above the
terminal drop, and a real agent turn completed in 48 seconds with the model
replying `PROVROUTEOK`. A drop instrument calibrated in both directions in the
same run logged **zero** drops during that turn.

**The one procedural difference between the two runs was replayed, and it changes
nothing.** cfv-167 flipped the toolchain toggle off and back on before its turns;
part A never touched it. Part B replayed exactly that sequence. Toggle OFF: turn
succeeded in 21 seconds, 0 drops. Toggle ON: turn succeeded in 20 seconds, 0
drops. The provider address stayed in the set across both flips.

**The leading explanation for cfv-167 is now the instrument rather than the
product, and it is offered as a labelled hypothesis rather than a finding.** The
calibration used here has a half the previous one did not: the log rule must stay
SILENT for an address that is in the allowlist. An `nft log` rule placed ABOVE the
allowlist accept instead of below it faithfully names every packet the agent
sends to the provider, including the ones that are then accepted, and a
calibration that only points at a must-be-dropped target cannot tell the two
placements apart. That would render a working provider route as "78 to 91 packets
dropped to `160.79.104.10`". I cannot verify it: that VM is gone and its probe was
never committed. It is the hypothesis that fits, not a measured fact.

---

## 2. Pre-flight

**Prompt library.** PROMPT 15 is present at
`C:\Users\bmcki\OneDrive\Desktop\Claude Prompts\FrontierAI_CC_Prompt_Library.md`
line 645 and runs to the end of the file, carrying the close-out gate, the four
pre-flight checks, the calibrate-before-measuring rule, the
instruction-challenge clause, the measurement and shell rules, the handoff cards,
the resource ledger and the credential rules. Not truncated, not stale.

**The correction the job asked for, in one line.** The previous job instructed
the deletion of a superseded prompt file that does not exist on this machine.
Nothing was deleted and nothing should have been. Not investigated further.

**Comprehension.** Restated and checked against the repo rather than the prompt,
which is where two of the four candidates died before any VM existed.

**Dependency census.** Run tree-wide, reported in full in
`docs/session_reports/2026-08-18_provider_route_source_read.md` section 1. Five
sites seed or refresh a provider hostname, four resolve and one replays a
persisted file. The WHEN half is section 5 of that artefact: every seed site
precedes the first moment a turn can be requested.

**Failure-mode walk.** The candidate fix, mirroring the toolchain path's three
unioned passes into the provider path, works exactly as specified and still does
not close the gap, because an address set cannot follow a name that moves. The
second candidate, an install-time reachability check, would correctly refuse
installs on a box whose provider is unreachable for an unrelated reason such as a
corporate proxy. Both stated before building rather than discovered after.

**Input-shape sweep.** No shipped code reads a new value this session. The probe
reads three, and each is given a control that separates present from absent from
unreadable: an nft set listing (a bogus set name must return nonzero), a kernel
log buffer (marked by line offset, so a wrapped buffer under-reports rather than
misreports), and a resolver answer (a real name and an `.invalid` name, both
required).

**Instruction challenge, and one deliberate deviation.** PROMPT 15 says not to
call `az vm user update` after provisioning and to hand the operator a card so
they set the admin password themselves. Those clauses exist for runs where a
human must reach the box over RDP. This run has no human step: no RDP rule is
opened at all (`--nsg-rule NONE`), nothing reboots after the install, and every
measurement goes through `az vm run-command` and the on-VM job runner. The proven
harness generates the password in memory, never prints it and never writes it,
and its `az vm user update` call is checked because an unchecked one cost cfv-162
an hour. Substituting a hand-driven password flow into a proven harness under
ship-blocker pressure, to satisfy a clause aimed at a case that does not arise,
is the kind of improvisation the job warns against. Recorded, not applied
silently.

## 3. Task 0 and the resource ledger

Starting state of `clawfactory-validation`, unfiltered, before anything was
provisioned: the storage account `clawfactoryvalc467`, the VNET `bake-vmVNET`,
and the two baseline images `clawfactory-win11-baseline` and
`clawfactory-win11-baseline-v2`. Exactly the expected residual and nothing else.
Zero VMs in the subscription, so no prior FAIL VMs, disks, NICs, public IPs or
NSGs to sweep.

`cfv-168` provisioned for this session: `Standard_D2s_v4`,
`clawfactory-win11-baseline-v2`, machine_id `bbc62062-20bb-492e-9be3-ecf31c9e38f7`.
Closing state in section 11.

## 4. Task 1: the source read, at zero cost

Delivered in full with file and line for every claim at
`docs/session_reports/2026-08-18_provider_route_source_read.md`, commit `55c3f81`,
answering all six of the job's questions. It did not close the question, but it
removed the tidy answer and narrowed the VM run from a survey to one
discriminating measurement. The headline results:

- **Five seed or refresh sites**, four of which resolve. All four resolve the
  provider hostnames exactly ONCE and none of them unions.
- **`api.anthropic.com` is in `AUX_HOSTS` at both copies** (`setup.ps1:2144` and
  `setup.ps1:2230`) and in `$providerHosts` under `/PROVIDER=claude`. It appears
  in no toolchain list.
- **The gateway dials `api.anthropic.com` by default, not by configuration.** The
  `Endpoint` field at `setup.ps1:118` is defined for all six providers and
  referenced by nothing: six hits tree-wide, all definitions, zero uses. That
  dead field reads like the thing that configures the dial target and is not.
- **Nothing flushes `@allowed_ipv4` during install.** On the nftables backend the
  read-fetch and toolchain resolvers call `fw-apply` only on the iptables-legacy
  branch. `install-send.sh` re-applies once and immediately repopulates through
  the shipped refresh, deliberately and with a comment saying why.
- **The provider seeding code is byte identical to the pre-split build.** A diff
  of `setup.ps1` across the whole Guard 3 split shows the provider resolution loop
  and both `AUX_HOSTS` blocks unchanged; only the toolchain block was added.

## 5. Task 2: the VM run

`cfv-168`, clean install of 1.3.4, `INSTALLER_DONE=success` in 15 minutes, 17
steps logged, 7 warnings, **0 errors**, 34 resources on disk.

### 5.1 The instrument, and the calibration that gated it

A rate-limited `log` rule inserted immediately before the terminal drop. Its
placement was read rather than assumed: the probe prints every rule before the log
line and every rule after it, and the accepts are all above.

```
ip daddr @allowed_ipv4 tcp dport 443 accept
ip daddr @read_fetch_ipv4 tcp dport 443 accept
ip daddr @toolchain_ipv4 tcp dport 443 accept
ip daddr 127.0.0.1 tcp dport 11434 accept
limit rate 200/second log prefix "CFDROP:"
counter packets 12 bytes 716 drop
```

Calibrated in BOTH directions, in both parts, before either was allowed to report
anything:

| Direction | Part A | Part B |
| --- | --- | --- |
| NAMES an address that must be dropped | `172.66.157.237` (example.org), 6 hits | `104.20.26.136` (example.org), 6 hits |
| Stays SILENT for an address in the allowlist | `104.16.212.131`, 0 hits | `160.79.104.10`, in_set=1, TCP CONNECTED, **0 hits** |

The kernel line the calibration produced, verbatim, showing that the instrument
reports protocol and port and not only address:

```
CFDROP:IN= OUT=eth0 SRC=172.26.136.101 DST=172.66.157.237 LEN=60 TOS=0x00 PREC=0x00
TTL=64 ID=62292 DF PROTO=TCP SPT=56944 DPT=443 WINDOW=64240 RES=0x00 SYN URGP=0
```

The second row is the one that matters and it is new this session. It is what
separates a log rule placed below the accepts from one placed above them.

### 5.2 Measurement 1: the set immediately after install, before any additional refresh

`@allowed_ipv4` = **24 addresses**, read with `SET_READ_RC=0`, against a control
where a nonexistent set name returned `rc=1` and 0 addresses, so "24" is a
membership count and not an artefact of a failed listing.

```
91.189.91.46     91.189.91.47     104.16.212.131   104.16.213.131
104.18.18.80     104.18.19.80     104.18.41.241    104.20.28.246
104.20.45.190    104.21.13.122    160.79.104.10    162.159.140.245
172.64.146.15    172.66.0.243     172.66.150.169   172.66.152.176
172.67.167.244   185.125.189.186  185.125.189.187  185.125.189.188
185.125.190.23   185.125.190.24   185.125.190.75   216.150.1.1
```

All with `expires 5h53m`, against a 6h element timeout, so the box was minutes
old. `/etc/clawfactory/allowed-ips.txt` held 22 lines and `160.79.104.10` is the
FIRST of them, so the address also survives a reboot through the boot replay path.

The refresh unit had run once at install: `LastTriggerUSec=Tue 2026-08-18 21:22:26
UTC`, `Result=success`, `NRestarts=0`, timer `enabled` and `active`.

### 5.3 Measurement 2: forward resolution, in-distro, five passes each

Controls first: `openclaw.ai` resolved to 1 address and a `.invalid` name to 0, so
an empty provider result could be told from a dead resolver.

| Host | Pass 1 to 5 | Union |
| --- | --- | --- |
| `api.anthropic.com` | `160.79.104.10` every time | **1** |
| `console.anthropic.com` | `160.79.104.10` every time | 1 |
| `api.openai.com` | `162.159.140.245 172.66.0.243` every time | 2 |
| `auth.openai.com` | `104.18.41.241 172.64.146.15` every time | 2 |
| `api.x.ai` | `104.18.18.80 104.18.19.80` every time | 2 |

Every one of the eight resolved provider addresses read `in_allowed=1`. Nothing
rotated, in-distro, on a clean box.

### 5.4 Measurements 3 and 4: the address actually dialled, and the difference

The agent was warmed first (L17). Then, with the calibrated instrument live:

```
{"id":"chatcmpl_8b41aaf9-...","object":"chat.completion","model":"openclaw/main",
 "choices":[{"message":{"role":"assistant","content":"PROVROUTEOK"},
 "finish_reason":"stop"}],"usage":{"total_tokens":21123}}
TURN_SECONDS=48
TOTAL_DROP_LINES=0
```

**The set difference is empty because the drop log is empty.** No address was
dialled and refused. The terminal drop counter over the life of the box read 12
packets and 716 bytes, which is background noise, not a stalled model call.

### 5.5 Measurement 5: which step populated the set

From the installer transcript, with a searchability control proving the log was
searchable before any absence was claimed:

```
Step 7 [R3]: Installing WSL egress firewall (clawuser-scoped, provider=claude).
Allowlist hosts: api.anthropic.com archive.ubuntu.com deb.nodesource.com
  docs.openclaw.ai esm.ubuntu.com nodejs.org openclaw.ai ports.ubuntu.com
  ppa.launchpad.net security.ubuntu.com
active backend: nftables
```

Ten hosts, the provider first. The shipped refresh script on disk carries
`AUX_HOSTS="api.anthropic.com console.anthropic.com api.openai.com
auth.openai.com api.x.ai"`, root-owned `-rwxr-xr-x 1 root root`, and a control
grep for a toolchain host in that assignment returned 0.

### 5.6 Measurement 6: a turn after one refresh cycle

The SHIPPED unit was started, not a simulation. `UNIT_RESULT=success`, set went
24 to 24 addresses, `fw-assert` reported chain shape OK inside the same journal,
and the following turn returned `POSTREFRESHOK`. The refresh adds nothing because
nothing was missing.

### 5.7 Part B: the cfv-167 sequence replayed

| Step | Result |
| --- | --- |
| `fetchctl toolchain off` | `{"ok":true,"enabled":false,"changed":true}`, toolchain set 0 addresses, **`@allowed_ipv4` still 24, `PROV_STILL_IN_SET=1`** |
| SUBJECT turn, toggle OFF | **`TOGGLEOFFOK` in 21s. 0 total drops, 0 provider drops.** cfv-167 recorded 91 |
| `fetchctl toolchain on` | `{"ok":true,"enabled":true,"changed":true}`, toolchain set 26 addresses, `@allowed_ipv4` still 24 |
| CONTROL turn, toggle ON | **`TOGGLEONOK` in 20s. 0 total drops, 0 provider drops.** cfv-167 recorded 78 |

## 6. Which candidate the evidence supports

**None of the four.** Stated plainly because the job asked whether the evidence
could fit more than one: it fits none of them, and that is a stronger result than
picking between them.

| Candidate | Verdict | The measurement that settles it |
| --- | --- | --- |
| **A**, single-pass resolution against a rotating pool | **REFUTED** | The premise is true and the consequence does not follow. The provider path does resolve once and never unions, at all four resolving sites, while the toolchain path resolves three times. But `api.anthropic.com` returned one address on 5 of 5 in-distro lookups and on 11 of 11 from the build machine across four resolvers. A pool of one cannot be missed by one lookup |
| **B**, a provider host lost in the `AUX_HOSTS` split | **REFUTED** | Answered from source with no VM, then confirmed on the box: all eight resolved provider addresses read `in_allowed=1` |
| **C**, the set was never populated, or the first turn raced it | **REFUTED** | 24 addresses immediately after install, seeded by Step 7 with the provider host named first in the transcript, against a control that separates zero from unreadable |
| **D**, the gateway dials a name that is not in the seed list | **REFUTED** | Forward resolution of the seeded name yields exactly the address the previous session saw refused, and the turn completes to that address with zero drops |

**What the evidence does support is that the cfv-167 observation was not a
property of the artifact.** The same artifact, harness, image, size and provider
produced a working provider route on the first try and on all four turns.

## 7. The full seeded address pool versus the address actually dialled, verbatim

Requested by the job, so both sides are printed rather than summarised.

**Seeded pool**, `@allowed_ipv4` immediately after install: the 24 addresses in
section 5.2. The provider member is `160.79.104.10`.

**Address actually dialled**: not observable through the drop log, because the
drop log recorded nothing during any of the four turns. The nearest direct
evidence is part B's discrimination control, which opened a TCP connection from
uid 1000 to `160.79.104.10:443` and reported `PROV_TCP=CONNECTED` with
`DISCRIM_HITS=0`, in the same run in which the same instrument named
`104.20.26.136` six times.

**The difference is empty.** On cfv-167 that difference was reported as 78 to 91
packets to `160.79.104.10`. Here it is nothing, from an instrument that proved in
the same run that it can name a refusal.

## 8. Does the install verify the agent can reach its model, and a recommendation

**No, and nothing in the install comes close.**

- The final gate (`setup.ps1:3586`) polls `http://127.0.0.1:8787/status` for a
  200. It is a loopback call that never leaves the box and would pass on a machine
  with the provider route completely closed.
- The key wizard's `v1/models` request (`ClawFactory-Secure-Setup.iss:378-390`)
  runs from Windows, in Inno's `[Code]`, outside WSL and outside the
  clawuser-scoped chain, so it cannot see this class of defect even in principle.
  It is also skipped entirely on silent installs.
- `smoke-test.ps1` checks 20 to 26 do run real agent turns and would catch it, but
  they run from a post-install scheduled task rather than as a gate, and their own
  header records that they need a valid provider key, so on a keyless box their
  failure carries no signal.

**Recommendation: add one, and add it regardless of this session's negative
result.** The precedent is already in the product:
`install-read-fetch.sh:213-217` refuses to finish the install when Guard 3's set
or its 443-scoped accept is absent, on the stated grounds that a set nothing
enforces is a list rather than a control. The provider route is the one thing
whose absence bricks the product outright and it is the only one of the three with
no gate. The check must run **as clawuser, inside WSL, after the last firewall
write**, because every existing check fails exactly that test. A TCP connect to
the provider host on 443 as uid 1000 is sufficient and costs no tokens. It turns a
silent brick into a loud install failure, and this session is itself the argument
for it: three sessions and two VMs went into answering a question one install-time
assertion would have answered on the box, at the moment it mattered.

**The residual on the other candidate fix, stated in the honest form.** Multiple
resolve passes reduce the miss rate. They do not eliminate it, because an address
set cannot follow a name that moves, and no number of lookups turns address
matching into hostname matching. That applies here unchanged, and it is one reason
not to reach for it now: it would be a real but unmeasurable improvement applied
to a path that this session could not make fail.

**The failure-triggered re-resolve, assessed from the code rather than from
expectation.** The host list the refresh resolves is `AUX_HOSTS`, a literal inside
`/usr/local/sbin/clawfactory-allow-providers.sh`, written by root at
`setup.ps1:2200` and `chmod +x` at `setup.ps1:2281`, root-owned in
`/usr/local/sbin`, and the agent runs as uid 1000. So a trigger that re-runs that
script gives the agent **no influence over what gets resolved**: at most it can
cause the same five root-owned names to be looked up again. The trigger itself
would have to be root-owned too, or it becomes a clawuser-writable path into a
root action, which is a worse problem than the one it solves. Reported, not built.

## 9. Why no fix was applied, and what the next session needs

**The job's rule is explicit and it was followed.** A fix may be written only if
the root cause is confirmed by measurement AND the fix mirrors the validated
toolchain pattern. The root cause is not confirmed; the symptom did not occur.
Writing the three-pass union into the provider path now would be shipping a change
to a path that measured healthy, justified by a defect that did not reproduce,
under ship-blocker pressure. That is precisely the move the job forbids.

**What the next session needs, in priority order:**

1. **The install-time reachability check**, section 8. It is the durable fix
   whichever way cfv-167 is eventually explained, and it is the thing that stops
   this question being asked a fourth time.
2. **A decision on whether cfv-167 is worth chasing further.** My view: no, not
   directly. That box is gone and its probe was never committed, so nothing can be
   re-measured. What CAN be done is cheap and general: never again run a drop
   instrument without the silence half of the calibration. That is now encoded in
   `validation/interim-v134-providerroute.ps1` and
   `validation/interim-v134-providerroute-b.ps1` and should be the house pattern.
3. **The two findings from the source read**, neither of which is this
   ship-blocker and both of which are real:
   - On the nftables backend the `AUX_HOSTS` addresses are never persisted to
     `allowed-ips.txt` (`setup.ps1:2148` versus `setup.ps1:2166`). Harmless when a
     provider was selected at install, because `$providerHosts` covers it. With
     `-Provider later` the provider route survives no ruleset re-apply and waits
     for the timer.
   - `switch-provider.ps1:170` still carries all seven toolchain hostnames and
     line 224 persists them into `allowed-ips.txt`. Running the shipped Start Menu
     item "Switch AI Provider" therefore re-seeds the toolchain hosts into
     `@allowed_ipv4`, where nothing removes them, and it survives reboot. **That
     silently and permanently defeats Guard 3**, in the third place nobody looked,
     which is the hazard `clawfactory-toolchain.sh:67-72` warns about by name.
4. **TC.3 can now be re-run**, because its control can now pass. It was not re-run
   here, per the job.

## 10. Task 3: TC.3 re-specified, and not re-run

Done, commit `eba2ba9`. The control turn now executes in section 1 while the
toggle is still ON, is recorded as its own row `TC.1d` because a turn that cannot
complete with the toggle ON is a ship-blocker in its own right and must not be
visible only as the VOID reason of another row, and gates the subject through
`Require-Precondition`. If the control does not complete, `TC.3` records VOID with
a named reason and the toggle-OFF turn is **not run at all**. A comment in the file
says not to re-run it until the provider route works, since until then the control
cannot pass and the test cannot say anything.

Not re-run in this session, per the job. Part B is not TC.3: it is the same
sequence driven by a diagnostic probe with a calibrated drop instrument, and its
result is that both halves pass.

## 11. Resource ledger, closing state

Every child resource deleted by explicit name, NIC first because it references
the pip and the nsg. Licence slot released with the same machine_id the install
activated.

```
targets -> nic: cfv-168VMNic | pip: cfv-168-pip | nsg: cfv-168-nsg | disk: cfv-168-osdisk
license slot deactivate (bbc62062-20bb-492e-9be3-ecf31c9e38f7):
  success=True msg=Machine deactivated successfully.
```

Proven with an UNFILTERED resource list rather than a grep for the VM name:

```
clawfactoryvalc467             storageAccounts    Succeeded
bake-vmVNET                    virtualNetworks    Succeeded
clawfactory-win11-baseline     images             Succeeded
clawfactory-win11-baseline-v2  images             Succeeded
```

Exactly the expected residual, identical to the starting state in section 3.
Nothing said "deleted" and then lingered; there was no propagation race to
re-check. Zero VMs.

**One small thing worth a line rather than an investigation.** The teardown
reported "10 still registered" on de-registering from `validation-runs/ACTIVE_VMS.txt`.
That file is an append-only safety net for killed drivers and it accumulates rows
for VMs that were later torn down; the unfiltered listing above is the
authoritative claim and it says zero. The sweep list is stale, not the
subscription.

## 12. Confirmation that nothing here widened anything

**Nothing in this session made the agent able to reach anything it could not reach
before.** Concretely:

- **No shipped file was changed.** The only edits are two new probe files, a
  re-specified validation test, a driver artifact repin, and documentation. `git
  diff` touches nothing under `resources/`, nothing in `setup.ps1`, and nothing in
  the `.iss`.
- **The only write to the box was a `log` rule.** A log action accepts nothing and
  drops nothing. It was removed in both parts (`INSTRUMENT_REMOVED=1`) and the
  shipped chain-shape tripwire passed afterwards (`FW_ASSERT_RC=0`), which is an
  independent confirmation rather than my own assertion.
- **The refresh unit was started, which is the product's own five-hourly path run
  early.** It grants nothing the product would not have granted itself within five
  hours, and it added zero addresses (24 before, 24 after).
- **The toolchain toggle was left ON**, its shipped default, verified by
  `fetchctl list` at the end of part B.

## 13. A credential-hygiene incident, reported because it is mine

An `az storage blob list` call of mine used a parenthesised `--query`. The
`az.cmd` wrapper re-parsed it under `cmd.exe`, the command failed, and the failure
message echoed the whole command line back, **including the `clawfactoryvalc467`
storage account key in full**. That value is now in this session's transcript. I
did not repeat it and it is not in this file or in any commit.

This is the L2/L7 trap, and the lesson is already written down: paren-free
`--query`, `--scripts "@file"`, read both streams. I broke it by reaching for an
ad-hoc query instead of letting the harness do the work.

**Recommendation: rotate the key, after teardown rather than during a run**, since
rotating mid-run invalidates the SAS URLs a live driver is holding. Bret's call:

```
az storage account keys renew -g clawfactory-validation -n clawfactoryvalc467 --key key1
```

The exposure is bounded: the key reaches a private validation storage account in
Bret's own subscription, whose only contents are validation evidence blobs and
staged installers, and the transcript is not published. It is still a key in a
transcript, which is the thing the rule exists to prevent.

## 14. Judgement calls

**One VM, not two.** The job authorised the VM run only if task 1 left the
question open. It did, so the run happened; but task 1 had narrowed it to one
discriminating measurement, so the run was scoped to that plus the job's list of
six rather than a full validation.

**Part B was added mid-run rather than deferred.** When part A returned "does not
reproduce", the honest close-out would have been that sentence alone. But there
was exactly one known procedural difference between the two runs and the box was
already live and billing. Testing it cost four minutes and converted "did not
reproduce" into "did not reproduce, and the one thing that differed was tried".
Deferring it would have handed the next session a VM run to redo the cheap half of.

**No 1.3.5 build.** Nothing shipped changed, so there is nothing to build and no
ledger row to spend.

**The misplaced-instrument hypothesis is labelled, not asserted.** It fits every
number in the cfv-167 table and it is the only explanation I have that does. It is
still not a measurement, that VM is gone, and saying otherwise would be exactly
the attribution error this whole sequence exists to correct.

## 15. Git

Commits on `main`: `55c3f81` (the source read), `eba2ba9` (the calibration-gated
probe and the TC.3 re-specification), `cc3d1e2` (the in-progress close-out and the
driver repin), `04f52dd` (part B), plus this close-out. Explicit per-file staging
throughout, no `git add -A`, no worktree, no tag. Studio untouched, so nothing to
push there.
