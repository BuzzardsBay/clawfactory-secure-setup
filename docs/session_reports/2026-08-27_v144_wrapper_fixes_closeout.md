# CLOSE-OUT: v1.4.4 wrapper fixes, the coverage gap behind them, then build and sign

**Status: COMPLETE.** Written incrementally so an interrupted session would have
left an honest record; the in-progress markers have been resolved. Anything not
measured says so.

**Headline: both blockers are fixed and PROVEN ON A BOX with controls that fired,
the documentation blocker is corrected, the coverage gap behind all three is
closed at two levels, and v1.4.4 is built and signed. It is NOT validated.**

**No fitness-to-publish verdict appears in this document, by instruction. This
build will not have been validated.**

---

## 0. PROMPT 15 preamble

Pasted and followed, VM clauses included. **No clause was deleted.**

The job card's stop condition on this point did not fire. The copy at
`C:\Users\bmcki\OneDrive\Desktop\Claude Prompts\FrontierAI_CC_Prompt_Library.md`
is 925 lines and carries PROMPT 15 at line 645 with its notes at 878. It is
current, so the run proceeds.

Both required reports were read in full before any code was touched:
`2026-08-27_v143_validation_closeout.md` (1181 lines) and
`2026-08-27_v143_runner_closeout.md`.

---

## 1. State at the time of writing

| Task | State |
| --- | --- |
| Job card moved to `docs/cc_jobs/`, committed | **DONE**, `4c3ee45` |
| TASK 1, prove both fixes on cfv-178 | **DONE. Both PASS**, controls fired. Took three passes; found a third defect, in this session's own fix. Section 4A |
| TASK 2.1 kill switch | **FIXED**, `6b48a41` |
| TASK 2.2 switch-provider | **FIXED**, `e26a562` |
| TASK 2.3 SECURITY_FINDINGS | **FIXED**, `c2cb37b`. Enumeration in section 5 |
| TASK 3.1 coverage enumeration | **DONE**, section 6 |
| TASK 3.2 extend coverage | **DONE**, `cec07a6` |
| TASK 3.3 AST sweep as a build gate | **DONE**, `e923480` + `1d56f2f`. Both canary readings in section 7 |
| TASK 4 version, build, sign, ledger | **DONE.** v1.4.4 built and signed, Authenticode Valid, nine gates green. Section 11 |
| TASK 5.1 cards, commits, push | **DONE.** Cards `#289`–`#292`. `origin/main` at `1d56f2f` |
| TASK 5.2 `#284`–`#288` left in Review | **DONE** — untouched |
| TASK 5.3 close-out | this file |

`origin/main`, from `git ls-remote origin main`, at the build commit:

```
31e2aa1e4eb34585904f54863cd2381bf52c3f51	refs/heads/main
```

Ten commits this session, one logical change each, explicit per-file staging, no
`git add -A`, no worktree, **no tag**.

---

## 2. TASK 1: staged, calibrated, and waiting on a keyboard

`cfv-178` was started from its deallocated state.

```
az vm start -g clawfactory-validation -n cfv-178   ->  START_EXIT=0
az vm show  -d  ->  VM running   4.154.56.193
```

**Cost of the window.** Standard_D2s_v4 in westus2 is roughly **$0.10 per hour**
of compute while running; the OS disk bills whether or not it runs. The intended
window is one to two hours, so **about $0.10 to $0.20**. Money is not the
constraint here and never has been; operator availability is.

### 2.1 The box came back with no interactive session, as expected

Read through `az vm run-command`, which runs as SYSTEM:

```
APPDIR_EXISTS=True
RES|clawfactory-stop.ps1|2581          <- the shipped v1.4.3 bytes
RES|switch-provider.ps1|20141          <- the shipped v1.4.3 bytes
JOBS_EXISTS=True
HEARTBEAT=2026-08-27T17:23:32          <- stale, from before the deallocate
quser : No User exists for *
AutoAdminLogon=
WSL_LIST_RC=-1
Running WSL as local system is not supported.
Error code: Wsl/WSL_E_LOCAL_SYSTEM_NOT_SUPPORTED
```

That last pair is the PROMPT 15 clause reproducing itself first-hand: every WSL
probe needs the interactive session, auto-logon is not armed, and no amount of
`run-command` gets round it. Hence the card at the end of this session.

### 2.2 What is staged, hash-verified at the far end

```
STAGED C:\cfv\patch\clawfactory-stop.ps1 sha256=F19E9C7769A02EEED1E32117F371424AF23AB86BF98AC9D3A020CEAAA22DE314 size=8647   MATCH=True
STAGED C:\cfv\patch\switch-provider.ps1  sha256=AF5C78E4FCF8461414CDD9965B64ECF7861760FB55E4E497A77AD93044A4932B size=21388  MATCH=True
STAGED C:\cfv\jobs\t1.job.ps1            sha256=3042FAFACB6EF6618E2EE34829323CD7D86CC676BDCFCC81958D889346A8A700 size=10682  MATCH=True
```

The job runs nine sections. Its shape is the point: **for each fix, the control
is the SHIPPED v1.4.3 script and it must FAIL in the same run.**

| § | What runs | Expected |
| --- | --- | --- |
| S0 | bring the gateway up | precondition, two readers must agree |
| S1 | **CONTROL** shipped `switch-provider.ps1 -Provider ollama` | must FAIL, `VariableIsUndefined` |
| S2 | **CONTROL** shipped `clawfactory-stop.ps1` | must FAIL: syntax error, exit 0, gateway STILL UP |
| S3 | apply the v1.4.4 candidates, box only, originals backed up | hashes reported |
| S4 | **SUBJECT** v1.4.4 `switch-provider.ps1` | completes, firewall applied, honest Ollama line |
| S5 | **POSITIVE CONTROL** for the fail-closed toolchain guard | must REFUSE |
| S6 | gateway back up | precondition |
| S7 | **SUBJECT** v1.4.4 `clawfactory-stop.ps1` | gateway DOWN by both readers |
| S8 | **FAULT INJECTION** same script, distro that does not exist | must refuse to claim success, exit non-zero |
| S9 | restore the box to shipped v1.4.3 | hashes reported |

Two readers, never one: HTTP where **only 2xx counts as up**, and a process count
taken inside the distro. Port 8787 is the root-owned gating proxy and answers 502
while the gateway behind it is dead, which is the reader defect that voided a
phase on 2026-08-27.

### 2.3 The quoting claim was calibrated locally first, on a synthetic target

PROMPT 15 requires a probe to produce a known-correct result on a rigged input
before it reports on a real one. `cmd /c echo <arg>` prints an argument exactly as
it survived PowerShell's native command-line construction:

```
--- OLD payload (v1.4.3) as it arrives at the child ---
"if pkill -u clawuser -f "[o]penclaw agent" 2>/dev/null; then echo "(killed running agent turn(s))"; else echo "(no running agent turns)"; fi"

--- NEW payload (v1.4.4) as it arrives at the child ---
"if pkill -u clawuser -f '[o]penclaw agent' 2>/dev/null; then echo CF_TURNS_KILLED; else echo CF_TURNS_NONE; fi"
```

The old argument is wrapped in double quotes with its own double quotes **not
escaped**, so it terminates at `-f "` and bash is handed a fragment — which is
exactly the reported `syntax error near unexpected token '('`. The new one is a
single intact argument. **The root cause is PowerShell's argument quoting, not
wsl.exe's re-quoting**, which is a small correction to the mechanism recorded in
the v1.4.3 close-out; the fix is the same either way.

All three payloads the fixed script builds were then enumerated from its AST:

```
PAYLOAD 1: has-double-quote=False  len=110
PAYLOAD 2: has-double-quote=False  len=51
PAYLOAD 3: has-double-quote=False  len=163
PAYLOAD_COUNT=3 (expected 3)
```

---

## 3. TASK 2.1: the kill switch, and the defect underneath it

Commit `6b48a41`. Two defects, not one.

**The quoting** is described above and is the smaller half. **The larger half is
that the script reported success for a step that failed.** It discarded both exit
codes and printed its banner unconditionally. That is the shape of `#286`, where
the uninstaller discarded its teardown's output and logged success regardless.

The fix is not "capture the exit code". Exit codes are captured, but the closing
summary is decided by a **verification taken after the stop**: a count of the
agent's processes inside the sandbox. Three states, and the output says which:

* verified and zero -> the success message, per claim;
* verified and non-zero -> named as still running, with `wsl --shutdown` as the fallback;
* unverified -> **no claim in either direction**, and exit 2.

`CF_VERIFY_OK` is printed only when `pgrep` actually exists, so an unverified
state cannot read as zero. The reader is a process count and not an HTTP probe
for the 8787 reason above.

`Invoke-StopWsl` **refuses** a payload containing a double quote rather than
escaping it. A silent escape would work and would let the next author reintroduce
the shape without noticing; a refusal is visible.

## 4. TASK 2.2: switch-provider, and the sentence the job card asked for

Commit `e26a562`. The four sites are escaped as `` `$baseHosts ``.

**Say so in the close-out, as instructed:** `3818bc0` fixed a real and serious
defect — the provider switch re-seeding seven toolchain hostnames into the set
nothing can revoke, silently defeating the user's toggle while the panel reported
it as off. **The fix's own explanatory comments broke the script**, for every
provider, and nothing noticed because nothing had ever executed it. **That is the
third time in this cycle that the artifact of a fix caused the next defect.** It
is why this session's response to it is a build gate rather than four backticks.

The minor at the old line 155 is fixed in the same commit: it printed
`[x] Ollama running with model llama3.1:8b` unconditionally, on cfv-178
immediately after the shell said `ollama: command not found`. It now asks the
sandbox whether the model is present and reports the answer, and the firewall
change still applies either way.

---

## 4A. TASK 1 RESULTS. Both fixes proven on cfv-178, and a third defect found

**It took three passes, and the two failures are the most useful part of this
section.** TASK 1 exists to find what reading cannot, and it did: not in the
product, but in this session's own fix.

### 4A.1 Blocker 2, switch-provider. **PASS**, first pass

**CONTROL — the shipped v1.4.3 script, which must fail:**

```
S1_EXIT=1
S1_CONTROL_FIRED=True  (expected True)
```

**SUBJECT — the v1.4.4 script, same box, same provider:**

```
S4_EXIT=0
S4_NO_STRICTMODE_DEATH=True
Switching active provider to: ollama
  [x] egress allowlist updated (backend auto-detected)
  [x] openclaw config updated (model=ollama/llama3.1:8b, profile=ollama:default)
Switched to ollama. Gateway restarted automatically; switch is live.
```

**And the firewall change actually landed**, measured either side with a control
that fires:

```
S4_BEFORE|FW_ALLOWED_V4=37   FW_TOOLCHAIN_V4=27  FW_ALLOWED_FILE_LINES=46  FW_SEED_HOSTS=9  FW_CTL_FAKESET=ok_fake_set_not_found
S4_AFTER |FW_ALLOWED_V4=30   FW_TOOLCHAIN_V4=27  FW_ALLOWED_FILE_LINES=39  FW_SEED_HOSTS=9  FW_CTL_FAKESET=ok_fake_set_not_found
```

The allowlist dropped by 7 addresses and the persisted `allowed-ips.txt` by 7
lines, which is the old provider's endpoints leaving as ollama needs none. The
toolchain set is **untouched at 27**, which is the property `3818bc0` existed to
protect. The control fired: a set that cannot exist is not found, so these counts
mean something.

**The minor fix proved itself on a real failure, not a rigged one.** Ollama could
not install on this box — it needs `zstd`, which is not in the allowlist:

```
>>> Installing ollama to /usr/local
ERROR: This version requires zstd for extraction.
bash: line 1: ollama: command not found
WARNING: Ollama is NOT installed in the sandbox, so the agent will have no model
to talk to. The install step above failed; the firewall change below still
applies. Install Ollama and run this script again.
```

```
S4_OLLAMA_CLAIMED_OK=False
S4_OLLAMA_SAID_ABSENT=True
```

v1.4.3 printed `[x] Ollama running with model llama3.1:8b` at exactly that point.

### 4A.2 The fail-closed toolchain guard still refuses. **PASS**

Without a positive control, "the guard did not fire" and "the guard is not wired
up" look identical. So `clawfactory-toolchain.sh` was shadowed to report a **base**
host as a toolchain host, and a refusal was required:

```
S5_SHADOW_SAYS=openclaw.ai
S5_GUARD_REFUSED=True
S5_AFTER_REFUSAL|FW_ALLOWED_V4=30  FW_TOOLCHAIN_V4=27  FW_ALLOWED_FILE_LINES=39
S5_SHADOW_REMOVED
S5_RESTORED_SAYS=clawhub.ai api.clawhub.ai api.github.com github.com raw.githubusercontent.com objects.githubusercontent.com codeload.github.com registry.npmjs.org
```

It refused, and the firewall was **unchanged** by the refused run — fail-closed,
measured rather than reasoned. The shadow was removed and the real script verified
to answer with its eight real hosts again.

**One observation, and it is a diagnosability gap rather than a security one.**
`S4_TOOLCHAIN_GUARD_RAN=False`: the guard's *success* line never reaches the
transcript, while its *refusal* does. `Invoke-WslBashBlock` assigns the WSL call to
`$null`, so the payload's **stdout is discarded**; the guard echoes its
confirmation to stdout and its FATAL to stderr with `>&2`, and only stderr
survives. So the guard can report that it stopped something and cannot report that
it checked. That is the mirror image of this session's theme and it is carded, not
fixed here.

### 4A.3 Blocker 1, the kill switch. **PASS on the third pass**

**CONTROL — the shipped v1.4.3 script, which must fail:**

```
S2_BEFORE http=200 procs=1
S2_EXIT=0
S2_AFTER  http=200 procs=1
S2_CONTROL_FIRED=True  (expected True: bash syntax error, exit 0, gateway STILL UP)
```

**SUBJECT, third pass, with the reader calibrated in BOTH directions in the same
run:**

```
S2_PGREP_PRESENT=True  RAW=[1]  PARSED=True  N=1
S2_CALIBRATION_POSITIVE=True    <- a RUNNING gateway must read as a positive count

S4_BEFORE http=200 procs=1
S4_EXIT=0
  Granted folders:   unmounted (0 folder(s)). The agent can no longer see them.
  Gateway and turns: stopped (0 OpenClaw processes running as the agent).
Everything is stopped. Your folder grants are preserved and will be re-mounted
next time you start ClawFactory (use Revoke to remove a grant permanently).
S4_AFTER  http=502 procs=0
S4_GATEWAY_DOWN_BOTH_READERS=True
S4_CLAIMED_STOPPED=True
S4_EXIT_IS_ZERO=True
S4_NO_SYNTAX_ERROR=True

S5_PGREP_PRESENT=True  RAW=[0]  PARSED=True  N=0
S5_CALIBRATION_ZERO=True        <- a STOPPED gateway must read as exactly 0
S5_SYSTEMD=inactive
```

**Fault injection, because stopping the gateway is only half the fix:**

```
S6_FAULT_PLANTED=True
S6_EXIT=2
S6_FAULT_LANDED=True      (COULD NOT RUN THIS STEP appeared)
S6_REFUSED_TO_CLAIM=True  (the success banner did not)
```

**Idempotence:**

```
S7_EXIT=0   run again with the gateway already down: still "Everything is stopped", still true
```

**The box was restored to its shipped v1.4.3 bytes:**

```
S8_RESTORED sha256=E5303BEF6459E1890D5CCC9BC875F7B6886994C1D98B40A537D71BF50E09655E size=2581
S8_FINAL http=502 procs=0
```

### 4A.4 The third defect: this session's own verifier, wrong twice

Pass 1 and pass 2 both produced this, over a stop that had **genuinely
succeeded** — the job's independent readers measured `http=200 procs=1` before and
`http=502 procs=0` after, and `systemctl is-active` said `inactive`:

```
  Gateway and turns: COULD NOT BE VERIFIED. No claim is made either way.
                     (verifier said: CF_VERIFY_OK CF_PROCS=)
```

Both versions assigned a shell variable from a command substitution:

```
n=$(pgrep -u clawuser -c -f '[o]penclaw' 2>/dev/null); echo CF_PROCS=$n     # pass 1
n=$(pgrep -u clawuser -f '[o]penclaw' | wc -l);        echo CF_PROCS=$n     # pass 2
```

Isolated on the box, as clawuser and as root, gateway up and down: **`n` comes
back empty every time**, while the identical pipeline run through the same
`wsl.exe` channel *without* the assignment reports the count correctly. `$?`
survives this channel — `CF_GW_RC=0` parsed fine in the same script — and a
variable assigned from `$( )` does not. That is the documented inline-WSL-probe
failure mode, and I walked into it twice before isolating it instead of guessing
again.

**The fix that worked** emits the count as the payload's only output and parses it
PowerShell-side, with the `pgrep`-presence check as a separate call. The presence
check is not decoration: with `pgrep` missing, its error goes to `/dev/null` and
`wc -l` prints 0, so a missing tool would read as "nothing is running" — this
file's own false negative, inverted.

**What this says about the fix's design, which is the reason to record it at
length.** Through two wrong readers the script never claimed success. It said it
could not verify, and exited non-zero. A false "could not verify" is a bug and it
was fixed. A false "everything is stopped" is the defect that shipped for four
months. **The discipline that this rewrite added caught the rewrite's own bug**,
which is the strongest available evidence that the discipline is real and not
decorative.

Two smaller instrument notes:

* My `H()` section-header helper in the TASK 1 job collided with PowerShell's
  built-in `h` alias for `Get-History`, which outranks functions in command
  resolution. Every section banner threw. Cosmetic — the measurements print with
  `S<n>_` prefixes and were unaffected — and checked against the committed harness
  phase, whose nine helper names are all collision-free.
* An `az` parameter containing a `|` was re-parsed by `cmd.exe` and became a pipe.
  The standing az.cmd trap, cost one round trip.

---

## 5. TASK 2.3: the structural table, enumerated

The job card is explicit that the enumeration is the deliverable and the one
corrected row is not. So: every row of the structural table, and whether it has
evidence behind it or is there by assumption.

### 5.1 What the row was, and what it should say now

The row read *"Kill switch, so you can stop everything immediately | Terminates
the real agent process | **Proven.**"* It terminated nothing, on every release.

**Decision: the row is REMOVED from the structural table** and given a residual
section of its own. Two reasons, and the first survives validation:

1. **A kill switch is an action you take, not a boundary that holds.** The table's
   own header says these guarantees "hold regardless of what the agent does" and
   "a hostile agent cannot route around these". A stopped process running as the
   agent's identity can be started again by that identity. What the kill switch
   can honestly guarantee is that when you run it, it tells you the truth about
   what it managed to stop — which is a different kind of claim.
2. **This build will not have been validated when the document ships.** The fix is
   proven by hand-patching an installed box with the shipped script as a failing
   control. That is real evidence and it is not a clean-install measurement, and a
   claim does not enter that table on the strength of a hand-patched box.

A row saying "not proven" inside a table whose header promises proven structural
guarantees would contradict the table rather than qualify it. Removal plus a named
residual is the honest shape.

### 5.2 The enumeration, which found the row was not the only problem

The paragraph above the table said: *"Every claim in the structural table below was
proven consumer-side: by asking the agent itself to cross the boundary and
recording its actual output."* **That sentence was false for three rows, not one.**

| # | Row | Evidence behind it | Verdict |
| --- | --- | --- | --- |
| 1 | **File isolation** | Consumer-side, the agent's own output: refused an ungranted file by direct path, by directory listing, through a symlink, through `../../..`, and via filesystem-wide search; `/etc/shadow` denied; positive control read a granted file in the same run | **Evidenced, consumer-side.** Strongest row in the table |
| 2 | **Egress allowlist** | Consumer-side and repeatedly: non-allowlisted hosts, raw IPs, non-standard ports and arbitrary resolvers blocked, across the `SP.*` and `TC.*` phases through v1.4.1 | **Evidenced, consumer-side**, with the scoping residual already stated |
| 3 | **Inbound deny** | **Producer-side only.** The gateway binds loopback, no listening surface is exposed, the Windows inbound block is present. `PHASE2_5_MOUNT_2026-07-14.md:156` flagged this in July in as many words: *"the rule exists" (producer). Not "a connection from another host is actually refused" (consumer).* No run has ever driven a connection from a second host | **Assumption-adjacent.** Real evidence, weaker class than the sentence claimed. **Status column now says so** |
| 4 | **No send path at the agent's identity** | Consumer-side and strong: `clawuser` to SMTP 465/587/25 gives ETIMEDOUT, with a control that CONNECTED (`220 smtp.gmail.com ESMTP`) proving the reader worked | **Evidenced, consumer-side** |
| 5 | **Approval binding** | Measured: a mutated payload is rejected, and a replayed approval returns `ESTATE request is already sent` | **Evidenced** |
| 6 | **Quarantine hold** | Measured at the identity level: `runuser -u clawuser -- rm -rf /var/lib/clawfactory/quarantine` gives Permission denied, and the directory cannot even be listed. The hold is the claim; the *routing* is already disclosed as advisory | **Evidenced** for the hold, as the row already says |
| 7 | **Credential protection** | **Ownership and file mode, not a refusal:** `mode=600 owner=root:root`, measured. Worth recording that `S.4` once printed `0600 root:root` as a hardcoded literal rather than a measurement — the same defect class as the kill switch, caught and fixed in the v1.4.0 completion run | **Assumption-adjacent by method**, and unavoidably so: the agent is provisioned its own key by design, so a consumer-side test would not be a refusal in any case. **Status column now says so** |
| 8 | **Safety-rules integrity** | Consumer-side: the agent cannot write, chmod, or delete-and-recreate the file | **Evidenced, consumer-side** |
| 9 | ~~**Kill switch**~~ | **None. Never executed on an installed machine by any current phase.** Present by assumption for the entire life of the product | **REMOVED** |

**The transferable finding is not row 9.** It is that a universal sentence
("every claim … was proven consumer-side") was carried over a table containing
rows that cannot be proven that way at all. Rows 3 and 7 were always weaker than
the sentence; nobody noticed because nobody read the sentence as a claim about
each row. The paragraph now states the exception and both Status columns carry
their own method, so the claim and the evidence sit in the same cell.

### 5.3 Where the table is mirrored, and what was done

| Location | Claim | Action |
| --- | --- | --- |
| `SECURITY_FINDINGS.md:44` | the structural row | **Removed**, residual section added |
| `SECURITY_FINDINGS.md` Door 2 residual | "and is still stopped by the kill switch" | **Removed** — untrue when written |
| `SECURITY.md:19` | kill switch listed among OS-enforced structural controls | **Corrected** |
| `README.md:32` | "stops the gateway and the agent processes" | **Corrected** |
| `SUPPORT_MATRIX.md:46` | "kills the agent **containers**" | **Corrected.** Also stale: Docker was removed in 2026-07 |
| `docs/RELEASE_NOTES_v1.4.3.md:73, :201` | the claim, twice | **Left.** The same document already contradicts itself deliberately at :332–:352, which states the defect plainly and says the notes are for the release that fixes it. Unpublished, and rewriting v1.4.3's notes is outside this job |
| `docs/index.html` and the **live site** | kill switch presented as a security control, in the meta description, the hero, the controls table and both feature lists | **NOT changed.** The live site serves from a separate repository and publishing is an irreversible public action. **This is an operator decision and it is listed in section 10** |

---

## 6. TASK 3.1: the coverage table, derived from the harness

Not from memory. A script reads the `.iss` `[Files]` section for the shipped set,
then searches two harness generations for each name and classifies every hit as
execution or as payload-rendering.

```
SHIPPED_PS1_COUNT=10
CURRENT_HARNESS_FILES=59  LEGACY_PROBE_FILES=5
```

| wrapper | payload sites | CURRENT suite | LEGACY probes | renders payload only |
| --- | --- | --- | --- | --- |
| `setup.ps1` | 50 | **EXECUTES** | -- | yes |
| `post-install.ps1` | 3 | -- | -- | -- |
| `bootstrap.ps1` | 7 | -- | -- | -- |
| `rename-agent.ps1` | 0 | -- | -- | -- |
| `launcher.ps1` | 3 | -- | -- | -- |
| `clawfactory-stop.ps1` | 1 | -- | **EXECUTES** | -- |
| `clawfactory-grants.ps1` | 4 | **EXECUTES** (dot-source) | EXECUTES | -- |
| `switch-provider.ps1` | 7 | -- | -- | **yes** |
| `uninstall.ps1` | 4 | -- | -- | -- |
| `smoke-test.ps1` | 10 | -- | **EXECUTES** | -- |

CURRENT = `validation\`, the phase-runner suite every run since v1.2.0 uses.
LEGACY = `scripts\probe-v10*.ps1` and `azure-probe.ps1`, the retired v1.0.x
one-shot probes.

**The instrument was canaried before it was trusted.** Planting a harness file
that executes `clawfactory-stop.ps1` flips its CURRENT column from `--` to
`EXECUTES`, so a `--` is a measurement and not a blind spot. The canary also
caught the instrument passing **vacuously**: the first run reported
`LEGACY_PROBE_FILES=0` because of a bad `Get-ChildItem -Include` glob, so every
`--` in that column meant "nothing was searched". The file count is now printed
and an empty set warns in the output.

### 6.1 The finding that is worse than "never executed"

`switch-provider.ps1` was never executed, and `validation/sp-prefix-fw.sh` states
its own nature in its first line: *"GENERATED, DO NOT EDIT. The firewall block of
resources/switch-provider.ps1 as it stood at commit 9710c5a, rendered."* That is
the gap the job card describes, and it is real.

But **the kill switch was executed** — by `scripts/probe-v1039-validation.ps1:237`
and `scripts/probe-v1047-validation.ps1:250`, on boxes, in July:

```powershell
if (Test-Path $ks) { W ((& powershell -NoProfile -ExecutionPolicy Bypass -File $ks 2>&1 | Select-Object -Last 8 | Out-String)) }
```

It ran, and nothing asserted on the result. It kept the **last eight lines**. The
script printed its two bash syntax errors early and its four-line false success
banner last, so — **INFERRED from the script's line ordering, not from a retained
transcript** — the tail those probes preserved was precisely the part that was
untrue, and the part that would have exposed it was discarded by the slice.

**So the lesson is not "execute the wrappers". It is "execute them and assert on
something that can fail."** Both the new build gate and the new phase are built to
that standard: every row asserts on a named string or a measured state.

---

## 7. TASK 3.3: the new build gate, and both canary readings

The v1.4.3 session's AST sweep was a scratchpad instrument and was deliberately
not committed, so it was **rebuilt from its description and re-canaried from
scratch** rather than lifted. It is now the ninth pre-build gate in
`scripts/build_release.ps1`, named `Interpolation gate` in the style of the
existing eight.

### 7.1 Canary reading 1 — it FAILS on a planted defect, naming file and line

One instance planted in a shipped script, in the real shape (a bare variable in a
here-string comment), then the real build script run:

```
SOUL pin OK: e70212603f2f91e6abf6db576c9535b1aaad60506e2fb075c199f18160db7941
Bundle check OK: all 34 preflight resources are in [Files].
Fail : build_release.ps1: UNDEFINED INTERPOLATION in shipped scripts. PowerShell expands these;
they are not prose. Escape each as `$name, or reword so no dollar sign appears --
resources\switch-provider.ps1:194 $plantedCanaryVar inside a DoubleQuotedHereString
(file sets StrictMode: this is FATAL at runtime)
BUILD_EXIT=1
```

File, line, variable, string kind, and the runtime consequence. Exit 1, before
ISCC is invoked. The planted line was then restored with `git checkout --`.

**It did not pass on the first attempt, and that is recorded rather than tidied
away.** Two defects in the instrument, both fixed in `1d56f2f`:

1. `$Matches` was read after a second `-match` had already overwritten it, so the
   `.ps1` filter yielded `$null` and the gate tried to parse the repository root
   as a file.
2. The remediation advice was built inside a double-quoted string, where the
   backtick escaped the dollar and the text printed as `Escape each as ,`.

Both are the class the gate exists to catch. "The canary passed" and "the canary
passed first time" are different claims, and only the first is true.

### 7.2 Canary reading 2 — it does NOT fire on a clean tree, or on things that look like the defect

Against the real pre-fix `switch-provider.ps1`, it reproduces the v1.4.3 reading
exactly:

```
File                       Line Var        Kind
switch-provider.PREFIX.ps1  182 $baseHosts DoubleQuotedHereString
switch-provider.PREFIX.ps1  185 $baseHosts DoubleQuotedHereString
switch-provider.PREFIX.ps1  194 $baseHosts DoubleQuotedHereString
switch-provider.PREFIX.ps1  235 $baseHosts DoubleQuotedHereString
TOTAL = 4
```

Against a synthetic file built to look like **what I was afraid of missing**
rather than what I had already found — six shapes and five negative controls:

```
canary-strict.ps1    9 $shapeOneUndefined   DoubleQuotedHereString   <- bare var in a here-string COMMENT
canary-strict.ps1   15 $shapeTwoUndefined   DoubleQuotedHereString   <- executable position
canary-strict.ps1   19 $shapeThreeUndefined           DoubleQuoted   <- single-line double-quoted string
canary-strict.ps1   23 $shapeFourUndefined  DoubleQuotedHereString   <- $() sub-expression
canary-strict.ps1   28 $shapeFiveUndefined  DoubleQuotedHereString   <- member access
canary-strict.ps1   33 $shapeSixUndefined   DoubleQuotedHereString   <- nested method call
TOTAL = 6
```

**6 of 6 planted shapes found. 0 of 5 negative controls fired** — an escaped
`` `$name ``, `$env:` drive qualification, a `param()` variable, a single-quoted
here-string, and automatic variables are all correctly silent.

And on the real fixed tree, all ten shipped scripts: **TOTAL = 0**.

### 7.3 What the gate cannot catch

Written into the gate's own comment block so its OK line is never read as more
than it is:

* A variable assigned **somewhere** in the file but not yet assigned at the point
  of use. "Defined anywhere" is the test, not "defined by now".
* A variable a dot-sourced library defines. That is the false-**positive**
  direction, not a miss; there are none today.
* A shell variable correctly escaped as `` `$x `` but semantically wrong. The gate
  checks that PowerShell will not eat it, not that bash wants it.
* Anything outside the `.iss` `[Files]` set — the validation harness and the build
  scripts are not swept.
* **The sibling defect it deliberately does not look for:** a bash payload
  carrying its own double quotes, which PowerShell fails to escape when building a
  native command line. That is what made the kill switch inert, it is a different
  shape, and `clawfactory-stop.ps1` refuses such a payload at runtime instead.

### 7.4 Two deliberate departures from the specification

Both stated in the gate's comment block, both measured before being taken.

1. **It runs BEFORE the worktree pin gate.** A source lint that only ever sees
   committed bytes cannot be canaried without committing the defect it exists to
   catch. Running it first means a planted instance in a dirty tree reaches it.
2. **It sweeps all ten shipped scripts, not only the seven that set StrictMode.**
   Without StrictMode the same shape is not fatal — it silently interpolates an
   **empty string** into a shell payload, which is how a probe once turned
   `grep -q "$ip"` into `grep -q ""` and matched everything. Measured both ways
   before widening: the tree reads TOTAL = 0 either way, so the wider scope costs
   nothing today and closes the blind spot for tomorrow. StrictMode status is
   reported per finding instead of used as a filter.

---

## 8. TASK 3.2: what was added to coverage

`validation/interim-v144-wrappers.ps1`, committed at `cec07a6`, under the phase
runner so the mechanical rules apply.

| Row | Wrapper | Assertion |
| --- | --- | --- |
| WR.1 | `smoke-test.ps1` | its own `N pass, N fail, N skip` summary line, with that line's presence as the control |
| WR.2 | `launcher.ps1` | `[STARTED]`, not `[ALREADY_RUNNING]`, against a genuinely down gateway |
| WR.3 | `clawfactory-stop.ps1` | gateway down by **two** readers, with a precondition that it was up by both |
| WR.4 | `clawfactory-stop.ps1`, fault-injected | must **refuse** to claim success; fault-landed control included |
| WR.5 | `switch-provider.ps1 -Provider ollama` | builds its payload and completes; firewall reader controlled |
| WR.5b | same | does not print an earned-looking Ollama line when Ollama is absent |
| WR.6 | the fail-closed toolchain guard | must **refuse** when a base host is made to look like a toolchain host |
| WR.7 | `post-install.ps1 -Provider later` | executes; the no-credential branch |
| WR.8 | `bootstrap.ps1` | executes; documented idempotent |
| WR.9 | `clawfactory-grants.ps1` | dot-sources and defines its functions, with a malformed-library control |

**The two that cannot be run, and their named substitutes** — recorded as INFO
rows carrying their reason, because a wrapper that was skipped and one that passed
must never look the same in a results file:

* **`rename-agent.ps1`** blocks on a modal `MessageBox` and never returns without a
  human click, so an unattended phase that ran it would **hang rather than fail**.
  It also builds no payload for another interpreter, so it is outside the defect
  class. **Substitute:** AST parse plus an assertion on the message text, and one
  by-hand click in the operator checklist.
* **`uninstall.ps1`**: running it is the destruction it performs, ending the
  install the phase is measuring. **Substitute:** it is already covered on its own
  box by `interim-v141-uninstall.ps1`, through the real dialog, against a held
  before-state.

WR.5 and WR.6 sit behind `-RunProviderSwitch`: switching to ollama replaces the
active provider and would confound any later phase on the same box. Ollama is the
only provider needing no credential, which is why it is the one used.

---

## 9. TASK 5.3 answer 5: the full validation scope for v1.4.4

**Stated plainly, because the job card asks for it plainly: this is the full
matrix plus sections 14.1 through 14.12 plus the new wrapper coverage. It is not a
re-run of what broke.**

The premise is the one this whole cycle was built on and it has not weakened: **a
rebuild changes the binary, and prior measurements do not transfer across a
rebuild.** Every v1.4.3 measurement was taken against `b2cd6408…`. v1.4.4 is
different bytes. Nothing carries over, including the rows that passed.

Three separate debts stack here, and it is worth being explicit that this is not
one release's worth of work:

1. **v1.4.4's own changes** — two shipped scripts, one new build gate, one new
   phase.
2. **v1.4.3's coverage, which was never completed.** Its run stopped on the second
   ship-blocker: matrix rows 2, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14 were **not
   run**, and neither was TASK 2 or TASK 3.
3. **v1.4.2, still substantially unmeasured.** Its changes live almost entirely in
   the keep-Linux uninstall branch, and none of that branch has been measured on
   any release. Of its six change areas only the launcher change was ever tested.

### 9.1 Cost, in boxes

| Box | Install variant | Carries |
| --- | --- | --- |
| **A** | normal, `-Provider claude` | Matrix rows 1, 3, 5–14. Sections 14.8, 14.9, 14.10, 14.11, 14.6. **The new `interim-v144-wrappers.ps1` phase, with `-RunProviderSwitch` LAST** because it replaces the provider. Then the RemoveAll branch, 16 rows, last of all |
| **B** | `-Provider later` | Matrix row 4 |
| **C** | licence host blocked, prior artifact as control | Matrix row 2 |
| **D** | normal | TASK 2 in full: install, keep-Linux uninstall through the real dialog, read-back against a held before-state, reinstall, teardown log, the fault-injected negative half, next-boot check. The rendered dialog rides here |

**Four boxes. Roughly 11 to 15 hours of wall clock and about 12 operator touches**
— the same shape the v1.4.3 run costed, because it is the same matrix plus one
phase. **It does not fit in one unattended session**, and the constraint is
operator availability at an RDP keyboard, not money: four `Standard_D2s_v4` boxes
plus disks is a few dollars.

**One addition to that plan, from this session.** The new wrapper phase should run
on box A **before** the RemoveAll branch and **after** everything else, with
`-RunProviderSwitch`, because WR.5 leaves the box on ollama. Adding it does not
add a box.

**`SP.8` is expected to FAIL.** It is the documented address-scoping residual, not
a regression. Do not adjust, retire or invert it.

---

## 10. Waiting on the operator

1. **Whether to delete `cfv-178`.** The command is printed in section 11 rather
   than run. It costs money either way and the call is his.
2. **The live site.** `clawfactory.app` presents the kill switch as a security
   control in five places — meta description, hero, controls table, and both
   feature lists — and it serves from a separate repository. The repo-side claims
   are corrected; the published ones are not, and publishing is an irreversible
   public action.
3. **`docs/RELEASE_NOTES_v1.4.3.md`** still carries the claim at two lines while
   contradicting itself deliberately further down. Unpublished. Whether v1.4.4 gets
   its own notes is a separate decision.

---

## 11. TASK 4: version, build, sign, ledger

### 11.1 The bump, and Studio

Three version literals, all of them, commit `25945d5`: `ClawFactory-Secure-Setup.iss`
(the `#define` the installer stamps itself with), `setup.ps1` (`$InstallerVersion`,
which the version gate cross-checks against the `.iss`), and
`validation/interim-v120-phase1.ps1` (`PIN.version`, which was two releases stale
when the v1.4.3 run began and had to be found by enumeration rather than by the
brief).

**Studio did not change and should not have.** It is at **1.3.2**, pin
`ac5937516e7edbb5aac00433bfa6e5074449cbc28b132883099391639e1e7dca`, the same
binary v1.4.3 embedded. Nothing in this release touches it, and the build gate
verified it rather than assuming it.

### 11.2 Every gate, by name, with its verdict

```
SOUL pin OK:            e70212603f2f91e6abf6db576c9535b1aaad60506e2fb075c199f18160db7941
Bundle check OK:        all 34 preflight resources are in [Files].
Interpolation gate OK:  10 shipped .ps1 files parse, and none interpolates a variable the file never defines.
Worktree pin OK:        all 54 tracked [Files] resources are byte-identical to their committed form.
  (2 skipped and named: ubuntu-rootfs.tar.gz and ClawFactory-Studio-Setup-1.3.2.exe are gitignored,
   sourced at build time, and covered by their own pin gates)
Studio pin OK:          ac5937516e7edbb5aac00433bfa6e5074449cbc28b132883099391639e1e7dca
Version OK:             1.4.4 (.iss and setup.ps1 agree)
Ledger OK:              released-versions.tsv carries 11 prior artifact row(s)
Persona pin OK:         0557d07004d4d067d8cd9e7cee7b2a3a783e0ac8ff4c492c0c152d7e35ff63a0
Workspace SOUL pin OK:  441b6279f6613c313e87e9e9e034f97a220540cddbf1cf738bb9a86c37a5a257 (6677 bytes composed)
Rootfs pin OK:          1483cc5c1dce13064f774834cbffdff226559fd522a67a381a8ea77d63fb4109
```

**Nine gates, all PASS**, and the third one is new. Its OK line is the second of
its two canary readings: the FAIL direction was proven by planting a defect
(section 7.1) and this is the clean-tree direction, taken by the real build script
on the real tree rather than by a scratchpad copy.

### 11.3 The artifact

| | |
| --- | --- |
| version | **v1.4.4** |
| build commit | `25945d5`; the ledger and stamp fix that followed is `31e2aa1` |
| **unsigned sha256** (what the ledger records) | `548562c72d5261bc62d590df03746ea2bb52134a413e10d137b590e589fdcdea` |
| unsigned bytes | 440,594,967 |
| **signed sha256** | `6e65560325cb6d7d3fea204ebb72876b3b113cbbfe9f2fa4f94113237e9eb4d1` |
| signed bytes | 440,610,608 |
| Authenticode | **Valid** |
| subject | `CN=Bret Mckinney, O=Bret Mckinney, L=West Valley City, S=ut, C=US` |
| issuer | `CN=Microsoft ID Verified CS AOC CA 03, O=Microsoft Corporation, C=US` |
| Studio | unchanged, 1.3.2, pin `ac59375…` |

**The signed digest is not stable and that is expected**: signing embeds a
countersigned timestamp, so it differs on every run over identical input. Observed
directly here — the same unsigned bytes produced `26c88d4e…` and then
`6e655603…`. The ledger records the unsigned digest for exactly this reason.

The certificate's `NotAfter` is one day out. That is **normal** for Trusted
Signing, which mints three-day certificates daily, and is not an expiry warning.

### 11.4 A rebuild, and what it proved

The first build stamped **eight** gates while nine had passed: `gatesPassed` is a
hand-maintained list and `interpolation` was not added to it. The stamp is the
artifact's provenance record, so it was corrected and the build re-run. The
re-run reported:

```
Ledger OK: 1.4.4 rebuilt byte-for-byte identically to its recorded artifact.
  unsigned sha256: 548562c72d5261bc62d590df03746ea2bb52134a413e10d137b590e589fdcdea
  gates passed: soul, bundle, interpolation, worktree, studio, version, persona, workspace-soul, rootfs
Ledger: this exact version and digest are already recorded; nothing appended.
```

Which is the right answer twice over: `build_release.ps1` is not in the `.iss`
`[Files]` set and cannot change the compiled bytes, and the ledger is idempotent
for an identical rebuild. **One `1.4.4` row exists**, not two.

**An instrument failure worth recording, because it nearly shipped an unsigned
binary.** The first attempt at that rebuild was invoked as
`build_release.ps1 | Select-Object -First 40`. The pipeline closed part-way
through `signtool`, and the result was a compiled artifact with its build stamp
still on disk and `Authenticode: NotSigned` — while the visible console output
looked like an ordinary successful build. It was caught by calling
`Get-AuthenticodeSignature` on the file rather than by reading the transcript,
which is the same rule as "read probe stderr, not just the phase transcript",
applied to a build. Do not put a build through a pipeline that can close early.

### 11.5 TASK 4.4: what changed between v1.4.3 and v1.4.4, and what it alters

| Change | Ships in the artifact? | Alters behaviour? |
| --- | --- | --- |
| `resources/clawfactory-stop.ps1` rewritten | **Yes** | **Yes.** It now stops the gateway and any running turn, which it never did, and it reports per claim what it measured instead of a fixed banner. New non-zero exits: 1 when something is still running, 2 when it could not verify |
| `resources/switch-provider.ps1`, four escaped `$baseHosts` | **Yes** | **Yes.** The script runs at all, for every provider. It was inert before |
| `resources/switch-provider.ps1`, the Ollama line | **Yes** | **Yes**, in the honest direction: a warning replaces an unconditional success line when Ollama is absent. The firewall change still applies either way |
| `setup.ps1`, `.iss` version literals | **Yes** | No. The stamped version string only |
| `SECURITY_FINDINGS.md`, `README.md` | **Yes** — both are in `[Files]` | No runtime behaviour. They are what the user is told |
| `SECURITY.md`, `SUPPORT_MATRIX.md` | No, not bundled | No |
| `scripts/build_release.ps1`, the ninth gate | No, not bundled | No runtime behaviour; it constrains future builds |
| `validation/interim-v144-wrappers.ps1`, `interim-v120-phase1.ps1` | No, not bundled | No |

**Three shipped behaviour changes, all in the two scripts this job was written to
fix, and all in the direction of the product doing what it says.** No security
boundary was moved: the firewall, the sandbox, the guards and the gateway path are
untouched by this release.

### 11.6 TASK 4.5: the delete command, printed rather than run

`cfv-178` has served its purpose and is **deallocated, not deleted**:

```
az vm deallocate -g clawfactory-validation -n cfv-178   ->  exit 0
VM deallocated
```

Deleting it costs money either way and the call is the operator's. Note that
`az vm delete` does **not** remove the OS disk, NIC, public IP or NSG, so the
sweep is explicit and **NIC first**, because it references the public IP and the
NSG:

```bash
az vm delete   -g clawfactory-validation -n cfv-178 --yes
az network nic delete    -g clawfactory-validation -n cfv-178VMNic
az network public-ip delete -g clawfactory-validation -n cfv-178PublicIP
az network nsg delete    -g clawfactory-validation -n cfv-178-nsg
az disk delete -g clawfactory-validation -n <the OS disk name> --yes
```

Then re-read with an unfiltered `az resource list -g clawfactory-validation`,
because "it said deleted" and "it is gone" are different claims. The expected
residual is four resources: the storage account, the VNET, and the two baseline
images.

---

## 12. TASK 5.4: end-of-session gate

### 12.1 Task accounting

| Task | State |
| --- | --- |
| Job card moved and committed | **DONE** `4c3ee45` |
| TASK 1 prove both fixes on cfv-178 | **DONE, both PASS**, with controls that fired. Section 4A |
| TASK 2.1 kill switch | **DONE** `6b48a41` + `00ee9ff` |
| TASK 2.2 switch-provider | **DONE** `e26a562` |
| TASK 2.3 SECURITY_FINDINGS + enumeration | **DONE** `c2cb37b`. Section 5 |
| TASK 3.1 coverage enumeration | **DONE**. Section 6 |
| TASK 3.2 extend coverage | **DONE** `cec07a6` |
| TASK 3.3 AST sweep as a build gate, canaried both ways | **DONE** `e923480` + `1d56f2f`. Section 7 |
| TASK 4 version, build, sign, ledger | **DONE** `25945d5` + `31e2aa1`. Section 11 |
| TASK 5.1 cards, commits, both pushed, no tag | **DONE.** Cards `#289`–`#292`. **No tag was created** |
| TASK 5.2 `#284`–`#288` stay in Review | **DONE** — untouched |
| TASK 5.3 close-out | this file |
| TASK 5.4 end-of-session gate | this section |

**Studio repo: nothing to push.** No Studio change was made; it is unchanged at
1.3.2 and this job did not touch that repository.

`origin/main`, from `git ls-remote origin main`: `31e2aa1` at the time of the
build commit; the final value is printed with this close-out's own commit.

### 12.2 Resource ledger

| | |
| --- | --- |
| VMs started | **1** — `cfv-178`, started from deallocated, used for TASK 1, **deallocated again, exit 0** |
| VMs provisioned | **0** |
| VMs deleted | **0** — deliberately. The delete command is printed in 11.6 for the operator |
| Running window | roughly **19:52 to 20:20 local**, under one hour. Standard_D2s_v4 at about $0.10/hour of compute, so **under $0.15** |
| Licence slots | none consumed. No install was performed; the box already carried one |
| Starting estate | unchanged: storage account, VNET, two baseline images, plus `cfv-178` and its disk |

**Credential hygiene.** No password was generated, printed, requested or set. `az
vm user update` was **not** called. The operator's RDP password never entered this
session. The only credential read was `DISPATCH_SECRET`, single-key from
`C:\Projects\FrontierAI\.env`, used as a header value and never printed.

### 12.3 Delta security sweep

Scoped to what this session changed.

* **`clawfactory-stop.ps1`** gains no privilege. It runs the same `wsl -u clawuser`
  calls it always ran, plus one read-only process count. `Invoke-StopWsl` **refuses**
  a payload containing a double quote, which narrows what the file can express
  rather than widening it. The new non-zero exits are read by nothing: the Start
  Menu shortcut and two retired diagnostic probes are its only callers.
* **`switch-provider.ps1`** changes four comment lines and one success message.
  The firewall payload is byte-identical apart from the escaped dollars, and the
  fail-closed toolchain guard was **exercised on a box and refused** (4A.2). The
  Ollama branch's new failure path does not skip the firewall step.
* **`SECURITY_FINDINGS.md` and `README.md` are bundled**, so this release ships
  changed user-facing security claims. Every change **removes or qualifies** a
  claim; none adds one.
* **The new build gate** cannot weaken an artifact: it only refuses builds.
* **The new validation phase does not ship.** It shadows
  `clawfactory-toolchain.sh` in WR.6 and restores it in the same phase; that is
  test-only, on a validation box, and behind `-RunProviderSwitch`.
* **No new network destination, no new listening surface, no new file written
  outside `C:\ProgramData\ClawFactory` and the sandbox.**

**One finding carried forward rather than fixed:** `Invoke-WslBashBlock` discards
its payload's stdout, so the toolchain guard cannot report that it *ran* — only
that it refused. Diagnosability, not containment. Carded.

### 12.4 Delta bug review

Bugs found in this session's own work, all fixed before the build:

1. **The interpolation gate read `$Matches` after a second `-match` overwrote it**,
   and failed the build with a confusing message about an unreadable path. Found by
   its own canary. `1d56f2f`.
2. **The same gate's remediation advice printed as `Escape each as ,`**, because a
   backtick escaped the dollar inside a double-quoted string. Same commit.
3. **The kill switch's verifier was emptied by the WSL channel, twice.** Found by
   TASK 1 on a running box, isolated rather than guessed at on the third attempt.
   `00ee9ff`.
4. **The build stamp listed eight gates while nine ran.** Found by reading the
   stamp the build printed. `31e2aa1`.
5. **A pipeline that closed early left an unsigned artifact looking like a
   successful build.** Found by checking Authenticode rather than the transcript.
   Not a code change; the rule is recorded in 11.4.
6. **`H()` collided with the `Get-History` alias** in the TASK 1 job. Cosmetic,
   bounded by checking every helper name in the committed phase against
   `Get-Alias`.

**Two of these six are the exact defect class this job was written to fix**, found
in the fixes themselves. That is not a comfortable observation and it is the honest
one: the gate and the canary discipline are load-bearing precisely because this
class is easy to write and impossible to see by reading.

### 12.5 No fitness-to-publish verdict

By instruction, and it would be unsupportable in any case: **v1.4.4 has not been
installed on a clean machine.** The scope of what that would take is section 9.

