# Close-out: do the guards survive a reboot?

**Date:** 2026-08-31
**Repo:** `C:\Users\bmcki\ClawFactory-Secure-Setup` (confirmed working root; `git rev-parse
--show-toplevel` = `C:/Users/bmcki/ClawFactory-Secure-Setup`, branch `main`, clean at start,
tip `ab681aa`)
**Job:** prove the guards survive a reboot.
**No release, no tag, no signing, no ledger row.** None was produced.

> **STATUS: IN PROGRESS.** Sections 0, 1 and 2 are complete and were written before any VM
> existed. Section 3 is the run plan, recorded before `az vm create` as the convention
> requires. Section 4 and the ending ledger are filled in as the run proceeds. If this
> document is read while these words are still here, the run did not finish.

---

## 0. TASK 0 — the census, taken from the tree

### 0.0 Method

Read from the tree, not from `2026-08-30_pre_v145_groundwork_closeout.md` §4.2. That
close-out's finding is what prompted this job; its numbers are treated as a claim under test,
which §0.2 settles.

Three sweeps, all by execution:

1. `grep -rn "systemctl enable"` tree-wide over `*.sh`, `*.ps1`, `*.js`, `*.iss`, `*.md`,
   excluding `.git` and `docs/`.
2. `grep -rn "/etc/systemd/system"` over `resources/` and `setup.ps1`, to find unit files
   written by a route that does not say `systemctl enable` on the same line.
3. `grep -n '\.sh' ClawFactory-Secure-Setup.iss` to establish which of those files ship.

### 0.1 Every unit the product installs

**Thirteen `.sh` files ship** (`ClawFactory-Secure-Setup.iss` lines 71-124). `openclaw-install.sh`
is vendored upstream and is excluded from adjudication, named here so the exclusion is visible.

| # | Unit | Installed by | Enable site | Error suppression | Read-back afterwards? |
|---|---|---|---|---|---|
| 1 | `clawfactory-quarantine.service` | `install-quarantine.sh:133` | `install-quarantine.sh:140` | `>/dev/null 2>&1 \|\| true` | **NO** |
| 2 | `clawfactory-quarantine-gc.timer` | `install-quarantine.sh:137` | `install-quarantine.sh:141` | `>/dev/null 2>&1 \|\| true` | **NO** |
| 3 | `clawfactory-send.service` | `install-send.sh:183` | `install-send.sh:190` | `>/dev/null 2>&1 \|\| true` | **NO** |
| 4 | `clawfactory-send-gc.timer` | `install-send.sh:187` | `install-send.sh:191` | `>/dev/null 2>&1 \|\| true` | **NO** |
| 5 | `clawfactory-proxy.service` | `install-chat-proxy.sh:44` | `install-chat-proxy.sh:87` | `>/dev/null 2>&1 \|\| true` | **NO** |
| 6 | `clawfactory-egress-refresh.service` | `install-read-fetch.sh:356` | `install-read-fetch.sh:379` | `>/dev/null 2>&1 \|\| true` | **YES - `install-read-fetch.sh:384-387`, `fatal`** |
| 7 | `clawfactory-fw.service` | `setup.ps1:2199` (heredoc into bash) | `setup.ps1:2212` | `2>/dev/null \|\| true` | **NO** |
| 8 | `clawfactory-allow-providers.timer` | `setup.ps1:2625` | `setup.ps1:2772` | `2>/dev/null \|\| true` | **NO** |

Two further `systemctl enable` sites exist and are **not** ClawFactory units. Both are
`ollama`, both `|| true`, both reached only when the local-model provider is selected:
`setup.ps1:2270` and `resources/switch-provider.ps1:153`. They are named so the enumeration is
complete; they are not guards and are out of scope.

One more, adjacent and worth stating: `setup.ps1:2925`
`systemctl --user enable openclaw-gateway.service 2>&1 || true`. It is followed at
`setup.ps1:2935` by a read-back - but of **`is-active`**, which is a different question, and
the block's own comment calls it *"a soft, best-effort check"* with the Windows-side `/status`
poll as the authority. `/status` is also a running-now measurement. **The gateway's own
lingering enablement is therefore never read back either**, by the same reasoning as the eight
above. It is upstream's unit rather than the product's and it is not one of the three guards,
so it is recorded and not fixed here.

Three units carry **no `[Install]` section** and are correctly never enabled directly -
`clawfactory-quarantine-gc.service`, `clawfactory-send-gc.service`, and
`clawfactory-allow-providers.service`. Each is pulled by its timer. A read-back on these would
read `static` and would be wrong to demand.

### 0.2 The count. The prior finding is wrong, in the direction that makes it larger

`2026-08-30_pre_v145_groundwork_closeout.md` §4.2 is headed **"Five systemd units are enabled
with the result discarded"** and then prints a block of **six** lines. Its own heading and its
own evidence disagree. The job brief inherited the five.

**The verified count is eight ClawFactory units enabled across five files, of which seven have
no read-back.** The prior close-out's six-line block omitted two:

- **`clawfactory-allow-providers.timer` (`setup.ps1:2772`)** - absent from the block entirely.
- **`clawfactory-egress-refresh.service` (`install-read-fetch.sh:379`)** - present in the prose
  as the counter-example but not counted as a unit, which is what turns eight into six.

And the block counted `clawfactory-fw.service` as a line while the heading counted units, which
is what turns six into five.

**The omission that matters is `clawfactory-fw.service`.** Section 0.5 explains why.

### 0.3 The pattern being copied, verbatim

`resources/install-read-fetch.sh:378-388`, with its comment, quoted rather than paraphrased:

```sh
systemctl daemon-reload 2>/dev/null || true
systemctl enable clawfactory-egress-refresh.service >/dev/null 2>&1 || true
# READ BACK. `systemctl enable` is routinely written here with `|| true`, which
# means a unit that failed to install looks identical to one that did. The panel
# now tells the user their sites are reachable after a restart, so the thing
# that makes that true has to be verified rather than attempted.
EGRESS_ENABLED="$(systemctl is-enabled clawfactory-egress-refresh.service 2>&1 || true)"
if [ "$EGRESS_ENABLED" != "enabled" ]; then
    fatal "clawfactory-egress-refresh.service did not enable (systemctl is-enabled said '${EGRESS_ENABLED:-<empty>}'). Without it, the Web access panel would report a live address count after a reboot while the addresses it names are stale. The firewall itself is unaffected and still denies, so this is an honesty failure rather than an exposure, but it is not shippable."
fi
note "boot refresh installed and enabled: clawfactory-egress-refresh.service, ordered after clawfactory-fw.service"
```

**Challenging the brief: is this the right pattern to copy?** Yes for its *shape* - read the
state, compare against the literal `enabled`, `fatal` on anything else - and the shape is what
section 1 copies. But the brief calls it the file that "already performs the read-back" without
noting the asymmetry that the census exposes:

> **The one unit with a read-back declares `After=clawfactory-fw.service`, and
> `clawfactory-fw.service` has no read-back.** `install-read-fetch.sh`'s own unit comment says
> *"ORDERING IS THE POINT. clawfactory-fw.service replays the persisted addresses and must go
> first, so the deny is in force before anything here runs."* The product verifies the
> dependent unit and not the dependency it says the ordering depends on.

That is not a reason to copy a different pattern. It is a reason the fix cannot stop at the
three `.sh` files the brief scopes it to, which sections 1.5 and 4.4 return to.

### 0.4 Beyond `systemctl enable` - the same question in the shell scripts

The exit-code census of 2026-08-30 covered PowerShell by AST. This is the shell half, by hand,
over the **twelve non-vendored shipped `.sh` files**. Raw `|| true` / `|| :` count per file:

```
openclaw-shim.sh          0     install-quarantine.sh     4
clawfactory-turn-gate.sh  0     clawfactory-fw-assert.sh  0
install-turn-gate.sh      1     install-send.sh           4
freeze-injected-soul.sh   1     clawfactory-read-fetch.sh 10
install-chat-proxy.sh     4     install-read-fetch.sh     2
gateway-wait.sh           5     clawfactory-toolchain.sh  8
```

**39 raw sites.** Most are sound: `chown`/`chmod` on a file whose content was already asserted,
`rm -f` of a scratch path, a rollback step that must not itself abort a rollback. The ones where
the suppressed result **is** the state being claimed:

1. **The seven `systemctl enable` sites of 0.1.** The subject of this job.

2. **`clawfactory-read-fetch.sh:72` and `clawfactory-toolchain.sh:144` -
   `nft flush set ... 2>/dev/null || true`**, each sitting directly under the comment
   `# --- 1. Flush first. Every exit after this point is fail-closed. ---`. The set's *existence*
   is checked; the flush's *success* is not. If the set exists and the flush fails, the
   previously-allowed addresses stay live while the script adds the new list and reports the new
   count - a revoked host remains reachable while the panel says it was revoked. **This is the
   exposure direction and the code contradicts its own comment.** Carried forward from the prior
   census, re-confirmed here, **not fixed in this job** (it is Guard 3 revocation, not unit
   persistence, and mixing them would make both harder to prove).

3. **`clawfactory-read-fetch.sh:247` and `clawfactory-toolchain.sh:350` -
   `nft add element ... || true` inside the apply loop.** An address that fails to add is skipped
   silently, and the `note` two lines later reports `addresses=$(wc -l < "$IPS_FILE")` - the count
   from the **file**, not from the **set**. So the number the user is shown is the number
   intended, not the number applied. The direction is fail-closed (a missing element denies), so
   this is an honesty defect rather than an exposure, and it is the same shape as the one
   `install-read-fetch.sh`'s own comment was written about. **Recorded, not fixed here.**

4. **`freeze-injected-soul.sh:104` - `chattr +i "$WS"` is not checked, and the verification that
   follows does not read the immutable bit.** The block after it asserts three real things -
   not a symlink, bytes match what was staged, ownership is `root` - and then prints
   `lsattr` in a `note` **without asserting it**. The immutability of `SOUL.md` is the structural
   half of SOUL protection; the code sets it and never confirms it. `chattr` is a real failure
   candidate: it returns non-zero on filesystems without the attribute. On the ext4 rootfs this
   product imports it will succeed, which is why nothing has surfaced it. **Recorded, not fixed
   here** - it is a different guard and deserves its own calibrated proof.

5. **`install-turn-gate.sh:47` - the final verification is a `WARN` and the script exits 0.**
   Already counted at `setup.ps1:2922` in the 2026-08-30 census. Unchanged.

6. **`install-quarantine.sh:23` and `install-send.sh:26` - `NODE=$(command -v node) || true`.**
   Both are checked two lines later with an explicit `[ -n "$NODE" ] || fatal`. Sound.

**Nothing else in the twelve suppresses a result that is also a claim.** Items 2, 3 and 4 are
the shell-side backlog this job leaves standing, and they are stated here rather than in a
sentence in a chat window.

### 0.5 On a machine where one of these units failed to enable, what would the user see?

**At install time: nothing. On any surface. On any of the seven.** Verified by execution:
`grep -rn "is-enabled"` over `*.ps1`, `*.sh` and `*.js`, excluding `validation/` and `docs/`,
returns **two hits, both inside `install-read-fetch.sh`'s own read-back**. The only other
`is-enabled` calls in the repository are in `scripts/egress-persistence-probe.ps1` and
`scripts/probe-gateway-install.ps1` - diagnostic instruments, neither shipped.
`smoke-test.ps1` (which *is* bundled, `.iss:61`) checks `http://127.0.0.1:8787/status` and a
Windows firewall rule and **never asks systemd anything**. The Studio guard panels reach the
brokers over their unix sockets, which answers *running now*.

**After a restart, it splits three ways, and the split is the finding.**

- **Noisy when used, silent otherwise - Guard 1, Guard 2, the proxy.** These fail in the right
  direction. `clawfactory-quarantine-rm.js:244` is explicit: *"FAIL LOUD, DO NOT FALL BACK.
  Falling through to the real rm here would turn every broker outage into a silent permanent
  delete."* So a missing Guard 1 broker produces
  `rm: cannot remove 'x': quarantine service unreachable`. A missing Guard 2 broker fails the
  enqueue. A missing proxy leaves nothing listening on `127.0.0.1:8787`, so ClawChat cannot
  connect - and cannot fall through to an ungated gateway either, because the real gateway was
  moved to `8788`. **But none of these says a protection is missing.** They say an operation
  failed. A user reads "quarantine service unreachable" as a bug, retries, and eventually
  reaches for `/bin/rm`, which the wrapper never covered.

- **Silent, no direction - the two GC timers.** `clawfactory-quarantine-gc.timer` not returning
  means quarantined files are never reaped and the store grows without bound; nothing reports it.
  `clawfactory-send-gc.timer` not returning means staged attachment bytes linger, and its own
  unit comment is careful that enforcement does not depend on it - the broker re-checks expiry
  under the store lock. So this one is genuinely cosmetic, and it is the only one of the eight
  that is.

- **Silent, and in the exposure direction - `clawfactory-fw.service`.** This is the one the
  prior finding omitted. `nft` rules are kernel state and do not survive a distro restart;
  `clawfactory-fw.service` is a `Type=oneshot` `WantedBy=multi-user.target` unit whose entire
  job is to replay `/etc/clawfactory/allowed-ips.txt` into a fresh table on every start. It is
  the only thing that does. **If it is enabled, egress persistence holds; if the enable was
  swallowed, the box comes back with no ClawFactory table at all, `uid 1000` has an
  unrestricted route out, and every surface in the product goes on reporting the allowlist it
  persisted to disk** - because every surface reads the file, not the chain. There is no error,
  no warning and no failed operation. The guard is not degraded; it is absent, and the product
  says it is present.

**Stated at full strength, which is what Task 0.5 asks for: a ClawFactory install whose
firewall unit failed to enable is indistinguishable, from inside the product, from one whose
firewall unit enabled correctly - until the machine is restarted, after which it is still
indistinguishable, and by then the agent has an open network.**

---

## 1. TASK 1 - the fix

### 1.1 What was added

Three files, one read-back per unit, following `install-read-fetch.sh`'s shape: read
`systemctl is-enabled`, compare against the literal string `enabled`, abort on anything else.
The check confirms the unit **is enabled**, never that `systemctl enable` returned zero - the
`|| true` on the enable line is left exactly as it was, deliberately, so that the read-back is
the only thing making the decision.

- `resources/install-quarantine.sh` - a two-unit loop after line 141, covering
  `clawfactory-quarantine.service` and `clawfactory-quarantine-gc.timer`.
- `resources/install-send.sh` - the same shape after line 191, covering
  `clawfactory-send.service` and `clawfactory-send-gc.timer`.
- `resources/install-chat-proxy.sh` - appended after the existing health probe, covering
  `clawfactory-proxy.service`.

Placement differs for the proxy on purpose. In the two broker installers the read-back sits
immediately after the enable, before the socket ping, matching the exemplar. In the proxy
installer it sits **after** the 120-second health window, because that window is what gives the
`--now` half its chance to succeed and because the failure branch has to perform the same
rollback the health-check failure performs (see 1.2).

### 1.2 Stop the install, not warn. And why

**Recommended and implemented: `fatal`.** Three reasons, in order of weight.

1. **A warning would land where 0.5 shows nothing reads.** The only place a warning could go
   is `C:\ProgramData\ClawFactory\install.log`. No shipped surface reads that file for guard
   state, and the user is not sent to it. A warning is a `WARN` in a log for a control that is
   absent - which is the "silently absent structural control" this job exists to close, wearing
   a different hat.

2. **Stopping is already this product's convention for exactly these four scripts, and the
   customer-language messages already exist.** Every one of the four is invoked by a
   `Step-Install*` function that throws on a non-zero exit:
   `setup.ps1:3433` (Guard 2), `:3474` (Guard 3), `:3524` (Guard 1), `:3572` (the proxy). Each
   throw carries a sentence written for a user, not for a maintainer. Making the read-back
   `fatal` reuses that path rather than inventing one, and it means no `setup.ps1` change is
   required for the message to reach the user correctly.

3. **The abort direction has been measured and it is fail-closed.**
   `validation/interim-v141-fatalreadback.ps1` row `FR.R6` measured a box left by exactly this
   kind of abort: `uid 1000` blocked on 6 of 6 attempts to `1.1.1.1:443` while root reached it
   on 3 of 3. An install that stops does not leave the agent with an open route.

**The trade-off, stated rather than hidden.** A `fatal` converts a rare, invisible, permanent
degradation into a visible, total install failure. Some users who would have had a
mostly-working product will now have none. That is the correct trade for a security product and
it is the same trade `install-read-fetch.sh` already made, on a unit whose failure is *milder*
than these - its own message concedes *"this is an honesty failure rather than an exposure"*.
Guard 1, Guard 2 and the proxy are not honesty failures.

**One place the trade needed care: the proxy rollback.** The natural instinct is to `fatal`
without rolling back, leaving the working-but-unlinked proxy in place - that state is
fail-closed. It was rejected. The two existing failure branches in `install-chat-proxy.sh` both
`systemctl disable --now` the proxy, remove the drop-in and restart the gateway on `8787`, and
`setup.ps1:3572`'s throw tells the user **"The installer rolled the gateway back to 8787;
ClawChat turns would be UNGATED - do not ship this install."** A third failure branch that did
not roll back would make that customer-visible sentence false about the machine it describes,
which is the defect class `docs/VALIDATION_PREAMBLE.md` names as the reason comments and
messages are the audit trail. **The new branch performs the identical rollback**, so the message
stays true and the box returns to the state it was in before the step.

### 1.3 The messages

Written in release-notes language, naming the protection and what its absence means. Each also
names the unit and quotes what `is-enabled` actually said, so the log is diagnosable.

> `clawfactory-quarantine.service did not enable (systemctl is-enabled said '<x>'). Deletes are
> only recoverable while the quarantine broker is running, and a unit that is not enabled does
> not come back after you restart your PC. The install would finish, the guard would work today,
> and the first restart would silently remove it. Refusing to complete.`

> `clawfactory-send.service did not enable (systemctl is-enabled said '<x>'). Email approval is
> enforced by a root-owned service the agent cannot reach, and a unit that is not enabled does
> not come back after you restart your PC. The install would finish, approval would work today,
> and the first restart would silently remove it. Refusing to complete.`

> `clawfactory-proxy.service did not enable (systemctl is-enabled said '<x>'). Every ClawChat
> turn is checked against your spend cap and your safety rules by this proxy, and a unit that is
> not enabled does not come back after you restart your PC -- chat would simply stop working,
> with no gate and no gateway on 127.0.0.1:8787. Rolling back and refusing to complete.`

The sentence *"a unit that is not enabled does not come back after you restart your PC"* is
deliberately repeated verbatim across all three. It is the one fact the user needs and it should
read the same wherever it appears.

### 1.4 Files changed, and whether they are bundled

| File | Bundled? | Where |
|---|---|---|
| `resources/install-quarantine.sh` | **YES** | `ClawFactory-Secure-Setup.iss:98` |
| `resources/install-send.sh` | **YES** | `ClawFactory-Secure-Setup.iss:114` |
| `resources/install-chat-proxy.sh` | **YES** | `ClawFactory-Secure-Setup.iss:87` |

All three additionally travel a second route: `setup.ps1` base64-drops each one into the distro
at install time (`setup.ps1:3428`, `:3519`, `:3567`) after LF-normalising it, so the bundled
copy is the copy that runs. All three read `i/lf w/lf attr/text eol=lf` under
`git ls-files --eol`, before and after the edit.

**Byte hygiene, checked rather than assumed.** A non-ASCII byte scan was run over all three, in
one invocation with both calibration halves: a planted two-byte UTF-8 canary reported 2
non-ASCII bytes and a clean ASCII control reported 0, so the scanner works in both directions.
Against `HEAD` vs the working tree: `install-quarantine.sh` 3 -> 3 (pre-existing, untouched),
`install-send.sh` 0 -> 0, `install-chat-proxy.sh` 0 -> 0. `bash -n` passes on all four scripts
including the untouched `install-read-fetch.sh` control.

### 1.5 What was NOT changed, and the recommendation that goes with it

**`setup.ps1` was not edited.** The brief scopes it out unless the census shows the defect lives
there, "in which case report before editing". Section 0.1 shows it does, at two sites, and 0.5
shows one of them is the **most consequential of the eight**:

| Site | Unit | If the enable is swallowed |
|---|---|---|
| `setup.ps1:2212` | `clawfactory-fw.service` | **The egress firewall does not exist after any restart.** `uid 1000` gets an unrestricted route out, and every panel keeps reporting the persisted allowlist. Silent. |
| `setup.ps1:2772` | `clawfactory-allow-providers.timer` | Provider addresses are never re-resolved, and the Guard 2 `fw-assert` tripwire drop-in never runs again. Silent. |

**Recommendation: fix both, in this job.** The change is the same few lines per site, inside the
existing bash heredocs, and both heredocs already end in a step whose PowerShell caller checks
`$rc`. The alternative - leaving the single most exposure-relevant unit of the eight unverified
while fixing five milder ones - would make this job's own close-out say that the product
verifies the dependent unit and not the dependency, which 0.3 already has to say once.

**Trade-off:** `setup.ps1` is ~3,600 lines, is the file every other job also edits, and a change
there is a change to the file the D1 rewrite will touch in v1.5. The two edits are additive and
inside heredocs that no other subsystem reads, so the collision risk is low, but it is not zero.

---

## 2. TASK 2 - proving it against a broken input (design; results in 2.3)

### 2.1 The injection, and why it has this shape

Reused from `validation/interim-v141-fatalreadback.ps1`, which built and calibrated it for the
one read-back that already existed. Its reasoning applies unchanged:

> The real failure this read-back was written for is not "the unit file failed to write" and not
> "systemd is dead" - either of those kills the install ninety steps earlier. The real failure is
> narrow: `systemctl enable` returns nonzero, `|| true` swallows it, and the unit is left NOT
> ENABLED while every preceding line reports success.

The mechanism is a **directory** placed at the path the enable needs for its symlink,
`/etc/systemd/system/multi-user.target.wants/<unit>`. `systemctl enable` cannot replace a
directory with a symlink, so it fails; `|| true` swallows it exactly as it would in the field;
`is-enabled` answers something that is not `enabled`. The mechanism is injected and is stated as
injected; the observable failure is the real one.

### 2.2 Calibrated in both directions, which is the whole point

A read-back that always failed would pass a one-sided test and would also break every install.
Four assertions per unit, in the same run:

| | What is rigged | Required answer |
|---|---|---|
| **A. Positive control** | nothing blocked | `enable` rc 0, `is-enabled` = `enabled`, **shipped block exits 0** |
| **B. Subject** | wants path is a directory | `enable` rc non-zero, `is-enabled` is not `enabled`, **shipped block exits non-zero and prints the shipped message verbatim** |
| **C. Old-code control** | wants path is a directory | the **pre-change** enable line alone exits **0** and prints nothing - this is the claim that the old code did not catch it, measured rather than asserted |
| **D. Collateral control** | wants path is a directory for unit X | a **different** ClawFactory unit still enables normally in the same directory - the injection must be targeted at one unit, or it proves nothing about this check |

**The subject text is extracted from the shipped `resources/install-*.sh` at run time, not
retyped into the probe.** `docs/VALIDATION_PREAMBLE.md` records that the v1.4.3 suite ran bash
payloads *extracted from* the wrappers rather than the wrappers themselves and that both v1.4.3
blockers lived in that gap. Here the shipped artefact **is** a bash script, so the probe reads
the block out of the real file by marker and executes those bytes.

Nothing about this can be constructed on the build machine: it needs systemd, a real
`multi-user.target.wants`, and the real units. **It is therefore deferred to the box of Task 3**,
explicitly, and runs there **after** the reboot measurement so that it cannot pollute the
subject of section 3. That ordering is deliberate and is not the order of the brief.

---

## 3. TASK 3 - the measurement, recorded BEFORE `az vm create`

### 3.1 One box, and which image

**`clawfactory-win11-baseline-v2`, `Standard_D2s_v4`, resource group `clawfactory-validation`,
name `cfv-191`.**

**Why a baked image is correct here, per Task 3.1's own test - "if the state under test can
exist on a baked image, use one and say so".** The state under test is *eight systemd units,
inside a freshly imported Ubuntu distro, after a Windows restart*. Neither baseline image
carries a distro at all (`docs/reference/BASELINE_IMAGES.md` section 2 item 8: *"No distro is
present on either image, so `wsl --import` of the bundled rootfs is exercised"*), so the entire
subject is created by the install on either image. The baked image changes nothing about it.

**What `-v2` has already done, from `docs/reference/BASELINE_IMAGES.md`, so the clause is
satisfied by record rather than by claim:**

- Inherits `clawfactory-win11-baseline` (2026-05-06): `Microsoft-Windows-Subsystem-Linux` and
  `VirtualMachinePlatform` **Enabled**, **a reboot taken after enabling them**, `wuauserv`
  stopped and disabled at capture (**measured `Running`/`Manual` on a provisioned box,
  2026-08-31 - the generalize/specialize cycle restores it**), AppX stripped, and three Defender
  exclusions that **were confirmed to survive sysprep**: `C:\Program Files\ClawFactory`,
  `C:\ProgramData\ClawFactory`, `C:\Users\Public\Desktop\ClawFactory.lnk`.
- Adds (2026-06-10): `wsl.2.7.8.0.x64.msi` installed quiet, engine 2.7.8.0, kernel 6.18.33.1-1.

**Which rows this box therefore cannot answer**, named in the run plan as the clause requires:

1. **Nothing about the feature-enablement or engine-acquisition path.** `Step-EnsureWsl` will
   take the import branch. This box cannot speak to `OM-2` and does not try.
2. **Nothing about Windows Defender's real behaviour** against the install
   (`BASELINE_IMAGES.md` `OM-B1`): the three write targets are excluded on this fleet and are
   not on a real machine.
3. **Whether a stock box even reaches the eight units.** The v1.4.5 groundwork record is that a
   stock first-run box can land in a state where the install cannot complete, in which case
   there are no units to persist. **That is a different measurement, on a different subject, and
   this job does not claim it.** It is stated here so the row this job produces is correctly
   scoped: *the eight units, on a box whose WSL2 engine installed correctly.*

**No second stock box.** This is a one-row job, not a validation cycle, and Task 3.1 says one
box. The scoping in the paragraph above is the substitute and it is a weaker one; it is recorded
as weaker rather than presented as equivalent.

### 3.2 The artefact

`Output\ClawFactory-Secure-Setup.exe` on the build machine -
sha256 `2fe7dad18c9eab8c005e8ee4bf9a25a6ca08bb761c11d9baf111e3eac0145e87`, 440,619,864 bytes.
Matched against `docs/session_reports/2026-08-31_d1_record_correction_closeout.md:713-714`
(`signed sha256`, `signed bytes`) and against the published release asset recorded at that
document's line 770 (`asset=ClawFactory-Secure-Setup.exe size=440619864 state=uploaded`).
**This is the published v1.4.5, identified by digest and not by filename.**

The measurement is therefore of **the release that is live now**, without the section 1 fix.
That is correct and intended: section 1 catches a failed enable at install time; section 3 asks
whether the units that *did* enable come back. They are different claims and the second one has
never been taken.

### 3.3 Sequence

| # | Step | Human? |
|---|---|---|
| 0 | Resource-group starting state, unfiltered | done, section 5 |
| 1 | Operator creates `cfv-191`, sets the admin password | **Card 1** |
| 2 | Driver scopes an RDP rule to a single /32 and reports the VM's public IP | no |
| 3 | Operator RDPs in and starts the on-VM job runner | **Card 2** |
| 4 | Upload phaselib + probe + the v1.4.5 exe to blob; pull them onto the box | no |
| 5 | Install v1.4.5, `/VERYSILENT` | no |
| 6 | **PRE census**: all eight units `is-enabled` + `is-active`, verbatim | no |
| 7 | `wsl --shutdown`, restart the distro, re-census - the systemd half alone | no |
| 8 | `az vm restart` - the real reboot | no |
| 9 | Operator logs back in and restarts the runner (auto-logon is one-shot) | **Card 3** |
| 10 | **POST census**: the same eight, verbatim, with start timestamps vs boot time | no |
| 11 | **Guards still hold**: cheapest end-to-end check for each of the three | no |
| 12 | Task 2's four-way calibrated injection, on the real units | no |
| 13 | Teardown, NIC first, unfiltered residual | no |

Step 10's timestamps are load-bearing. The first `wsl.exe` command after the reboot starts the
distro, which starts systemd, which starts the units - so "I did not start them by hand" has to
be *shown*, by comparing each unit's `ActiveEnterTimestamp` against the distro's boot time
rather than against the probe's clock.

### 3.4 What the three end-to-end guard checks will be, and what each proves

Chosen for cheapness; each names what it proves and, as importantly, what it does not.

- **Guard 1 - recoverable delete.** Create a file in a granted workspace as `clawuser`, `rm` it,
  assert the file is gone from the workspace **and** present in the root-owned store, and that
  `clawuser` cannot read the store. Proves the broker is not merely listening but still holds
  its configuration and its store path, and that the `dpkg-divert` wrapper is still first on the
  exec PATH after a restart. Does not prove the advisory half (`/bin/rm`, `unlink`) - that was
  never claimed.
- **Guard 2 - no send at uid 1000.** As `clawuser`, enqueue a send request over
  `/run/clawfactory/send.sock` and assert it comes back **pending approval**, not sent; then
  assert `send-admin.sock` is `0600 root:root` and unreachable as `clawuser`. Proves the broker
  reloaded its store and that the approval boundary is still a boundary. A socket ping alone
  would not: a broker that answers `ping` with an empty or unreadable store is a running
  process, not a guard.
- **Guard 3 / the firewall - the one 0.5 says fails silently.** As `clawuser`, attempt TCP 443
  to an address that is not in any allowlisted set and require it to be **denied**, with a root
  attempt to the same address in the same run that must **succeed**. Without the root half,
  "the agent is blocked" and "the box has no network" are the same reading. Then read the live
  `nft` table and compare its element count against `/etc/clawfactory/allowed-ips.txt` - a held
  copy compared against what the product reports, rather than a second reading of the same file.

Plus the proxy: `GET http://127.0.0.1:8787/status` **as `clawuser`**, which is the reachability
ClawChat actually gets, with a `clawuser` attempt to `8788` in the same run that must be
dropped.

### 3.5 If anything does not come back

That is the finding and it outranks the fix. It gets reported and the run stops there, per the
brief.

---

## 4. Results

*(filled in as the run proceeds)*

---

## 5. Resource ledger

**Starting state, unfiltered, `az resource list -g clawfactory-validation -o table`, read
2026-08-31 before anything was provisioned:**

```
Name                           ResourceGroup           Location    Type                               Status
-----------------------------  ----------------------  ----------  ---------------------------------  ---------
clawfactoryvalc467             clawfactory-validation  westus2     Microsoft.Storage/storageAccounts  Succeeded
bake-vmVNET                    clawfactory-validation  westus2     Microsoft.Network/virtualNetworks  Succeeded
clawfactory-win11-baseline     clawfactory-validation  westus2     Microsoft.Compute/images           Succeeded
clawfactory-win11-baseline-v2  clawfactory-validation  westus2     Microsoft.Compute/images           Succeeded
```

`az vm list -g clawfactory-validation` returned empty. **This is exactly the expected residual -
the storage account, the VNET and the two baseline images, and nothing else. There were no prior
FAIL VMs or orphaned disks to delete.** Task 0's deletion step was therefore a no-op, verified
rather than assumed.

*(ending state appended at teardown)*
