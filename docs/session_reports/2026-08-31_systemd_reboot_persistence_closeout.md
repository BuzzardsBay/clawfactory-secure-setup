# Close-out: do the guards survive a reboot?

**Date:** 2026-08-31
**Repo:** `C:\Users\bmcki\ClawFactory-Secure-Setup` (confirmed working root; `git rev-parse
--show-toplevel` = `C:/Users/bmcki/ClawFactory-Secure-Setup`, branch `main`, clean at start,
tip `ab681aa`)
**Job:** prove the guards survive a reboot.
**No release, no tag, no signing, no ledger row.** None was produced.


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

## 2. TASK 2 - proving it against a broken input (design; results in 4.6)

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

### 4.0 The verdict

**The guards survive a reboot. All eight units came back, enabled and started by systemd, and
all three guards plus the gating proxy still hold end to end.** Measured on `cfv-191`, on the
published v1.4.5, across a Windows restart proved by its own `LastBootUpTime`.

| Stage | Verdict | Rows |
|---|---|---|
| Install (published v1.4.5, `/VERYSILENT`) | **PASS** | 4 PASS |
| Pre-reboot census + guards | **PASS** | 16 PASS, 3 INFO |
| `wsl --shutdown` restart cycle | **PASS** | 19 PASS, 2 INFO |
| **Windows reboot** | **PASS** | **19 PASS, 2 INFO** |
| Task 2 fault injection | **PASS** | 9 PASS |

Every stage: positive controls registered and fired, preconditions declared and met, zero VOID.

### 4.1 What was actually run, including what was thrown away

| # | Step | Outcome |
|---|---|---|
| 1 | Stage files, take baseline readings | done; artefact digest-matched |
| 2 | Install attempt 1 | **VOID (instrument)** — see 4.7 item 3. Nothing installed, no state changed |
| 3 | Install attempt 2 | `INSTALLER_DONE=success`, 16 minutes |
| 4 | Pre census, runs 1 and 2 | 2 FAILs, both this probe's expectations — 4.7 items 4 and 5 |
| 5 | Pre census, run 3 | clean PASS |
| 6 | WSL restart cycle, run 1 | 3 FAILs, all instrument — 4.7 items 6, 7, 8 |
| 7 | WSL restart cycle, run 2 | clean PASS |
| 8 | **`az vm restart`** | boot proved: `16:42:16` → `18:55:19` |
| 9 | Post-reboot census + guards | clean PASS |
| 10 | Task 2 injection | clean PASS |
| 11 | Evidence off the box, teardown | 10 files, byte-matched; residual verified 3 times |

### 4.2 The pre-reboot baseline, and why it is the load-bearing half

```
  unit                                    is-enabled   is-active  expected   ActiveEnter(us)  Result
  clawfactory-allow-providers.timer       enabled      active     active     524990648        success
  clawfactory-egress-refresh.service      enabled      inactive   inactive   0                success
  clawfactory-fw.service                  enabled      inactive   inactive   0                success
  clawfactory-proxy.service               enabled      active     active     690893287        success
  clawfactory-quarantine-gc.timer         enabled      active     active     537374637        success
  clawfactory-quarantine.service          enabled      active     active     536874076        success
  clawfactory-send-gc.timer               enabled      active     active     574236153        success
  clawfactory-send.service                enabled      active     active     573821717        success

multi-user.target.wants/clawfactory-* = 5, timers.target.wants/clawfactory-* = 3, unit files = 11
```

**Those two zeros are what make the post-reboot reading unambiguous rather than merely
suggestive.** `clawfactory-fw.service` and `clawfactory-egress-refresh.service` are enabled with
a plain `systemctl enable`, not `enable --now`, so on this box neither had ever been started --
the firewall was applied by `setup.ps1` invoking `clawfactory-fw-apply.sh` directly. A non-zero
start timestamp after the restart can therefore only have been produced by systemd at boot.
There is no other writer.

### 4.3 The distro-restart cycle, and three more restarts nobody planned

`wsl --shutdown` followed by letting the distro come back on its own: **19 PASS, 0 FAIL**, census
and guards in the same `boot_id`, gateway ready 30 s after the distro came up, agent blocked 6 of
6 against a root control of 3 of 3.

And the box gave more than was asked. WSL **idle-terminates the distro between dispatches**, so
`journalctl --list-boots` records six distro boots across the session:

```
-5 24f7e74f... 17:18:42 - 17:18:47      -2 3120bbcb... 18:27:22 - 18:49:28
-4 b4ac9861... 17:18:56 - 17:19:07      -1 abe0a2e9... 18:49:34 - 18:51:19
-3 6f342798... 17:19:15 - 18:27:13       0 e4c394b2... 19:49:24 - 19:53:39
```

Every boot after the install ran `clawfactory-fw.service`, ran
`clawfactory-allow-providers.service`, and passed `clawfactory-fw-assert.sh`. **The systemd half
of the claim is therefore repeated, not measured once.**

### 4.4 THE WINDOWS REBOOT

**The reboot is proved by the machine, not asserted by this document.**

```
WIN_LASTBOOT_BEFORE=2026-08-31T16:42:16   WIN_UPTIME_BEFORE_S=7906
WIN_LASTBOOT_AFTER =2026-08-31T18:55:19   WIN_UPTIME_AFTER_S =62
```

Public IP unchanged at `20.114.24.153`; the RDP rule still present and still scoped to
`67.164.251.99/32`; all eight evidence transcripts survived at identical byte lengths. The
runner's last heartbeat was `18:54:59`, twenty seconds before the machine went down, and
`query session` showed no interactive session afterwards -- auto-logon is one-shot, exactly as
the preamble says, and the operator restarted it by hand.

**The post-reboot census, verbatim:**

```
  unit                                    is-enabled   is-active  expected   ActiveEnter(us)  Result
  clawfactory-allow-providers.timer       enabled      active     active     12595659         success
  clawfactory-egress-refresh.service      enabled      active     active     17174036         success
  clawfactory-fw.service                  enabled      inactive   inactive   0                success
  clawfactory-proxy.service               enabled      active     active     12712903         success
  clawfactory-quarantine-gc.timer         enabled      active     active     12597164         success
  clawfactory-quarantine.service          enabled      active     active     12728837         success
  clawfactory-send-gc.timer               enabled      active     active     12607673         success
  clawfactory-send.service                enabled      active     active     12746907         success
```

**And the row that answers the question, verbatim:**

```
UP.POST.6  PASS  the two boot-time oneshots: did they RUN this boot, and did they succeed?
  2 of 2 left inactive (i.e. were started) with Result=success:
    clawfactory-egress-refresh.service  InactiveExit=15109251  ActiveEnter=17174036  Result='success'  ExecMainStatus='0'
    clawfactory-fw.service              InactiveExit=12709461  ActiveEnter=0         Result='success'  ExecMainStatus='0'
```

Both read `0` before the restart. `clawfactory-fw.service` started **12.7 seconds** into the
distro's boot; `clawfactory-egress-refresh.service` at **15.1 seconds**. Nothing in the run
issues `systemctl start`.

**The distro's own journal for that boot, verbatim:**

```
Aug 31 19:49:26 cfv-191 systemd[1]: Starting ClawFactory egress firewall (nftables or iptables-legacy fallback)...
Aug 31 19:49:28 cfv-191 systemd[1]: Finished ClawFactory egress firewall (nftables or iptables-legacy fallback).
Aug 31 19:49:30 cfv-191 clawfactory-egress-refresh.sh[409]: [egress-refresh] every host that had to be resolved was resolved; both sets are current
Aug 31 19:49:30 cfv-191 clawfactory-egress-refresh.sh[409]: [toolchain] TOOLCHAIN_STATUS enabled=1 hosts=8 resolved=8 failed=0 retained=0 addresses=29 backend=nftables
Aug 31 19:49:30 cfv-191 systemd[1]: Finished ClawFactory: re-resolve the Guard 3 egress sets once the network is up.
Aug 31 19:50:01 cfv-191 clawfactory-fw-assert.sh[1016]: [fw-assert] chain shape OK (uid-scoped, all three allowlist accepts are 443-only, read-fetch and toolchain sets present with their accepts, SMTP dropped explicitly, terminal drop present)
```

Note the ordering held: the firewall replayed at 19:49:26-28, and the Guard 3 refresh ran after
it at 19:49:30, which is what `install-read-fetch.sh`'s unit comment says the ordering exists to
guarantee.

**The distro was started by the product's own mechanism, not by the probe.** Windows came up at
18:55:19; distro boot 0 began at **19:49:24**, when the operator logged in and the
`ClawFactory WSL Host` scheduled task fired. The probe's first dispatch was at 19:50:0x, by which
time all eight units had been running for thirty seconds.

### 4.5 TASK 3.4 -- the guards themselves, after the restart

All four end-to-end rows PASS, with their controls firing in the same run.

| Row | Reading | What it proves | What it does NOT prove |
|---|---|---|---|
| **G1** Guard 1 | canary created under `/workspaces`, `rm` as `clawuser` → `G1_GONE_FROM_WORKSPACE=yes`, `G1_IN_STORE=1`, `G1_AGENT_CAN_LIST=no` | the `dpkg-divert` survived, the wrapper is still what the agent's shell resolves `rm` to, the broker answered, and the payload sits where uid 1000 cannot read it | the advisory half -- `/bin/rm`, `unlink`, `find -delete`, `fs.rmSync` were never covered and are not covered here |
| **G2** Guard 2 | `{"ok":true,"pong":true}`; `{"ok":false,"code":"EPERM","error":"approve is not available on the request channel"}`; agent on `send-admin.sock` → `DENIED:EACCES` | the broker reloaded with its config and the request/admin split is still enforced at the socket, with no SMTP credential needed | a full approval round-trip, which needs the credential and would record VOID without it rather than a verdict |
| **G3** firewall | `G3_AGENT_BLOCKED=6 of 6`, `G3_ROOT_REACHED=3 of 3`, nft table present, 4 terminal-drop lines, 66 addresses live against 46 lines in `allowed-ips.txt` | **the row the job turns on.** nft rules are kernel state, so this can only be true because `clawfactory-fw.service` came back and replayed the persisted list | that the list itself is correct -- only that it is enforced |
| **G4** proxy | `8787` as `clawuser` → **200**; `8788` as `clawuser` → **denied**; `8788` as root → **200** | the proxy owns the client port, the private gateway is alive, and the agent's denial is the firewall rather than a dead service | anything about a real ClawChat turn |

The G1 path is `/workspaces/...`, the real `quarantineRoots`. A probe pointed at `/var/tmp` or at
the agent's home would be out of scope, where the broker correctly declares `quarantined:false`
and the wrapper performs a real delete -- a pass for the wrong reason, which is the recorded
Guard 4 precedent.

### 4.6 TASK 2 -- the broken-input proofs

Run last, on the real units, so it could not pollute the subject. The subject block was
**extracted by marker from the shipped `resources/install-quarantine.sh`** staged onto the box
(`sha256 dc9cae64...`, byte-identical to the repo copy) and those bytes were executed --
10 lines, 2 `systemctl is-enabled` hits, 1 `fatal`, with the real `fatal()` definition taken from
the same file. Injection: a **directory** at
`/etc/systemd/system/multi-user.target.wants/clawfactory-quarantine.service`, which `systemctl
enable` cannot replace with a symlink.

| | Rigged | Result |
|---|---|---|
| **A. positive control** | nothing blocked | `A_PRE_ISENABLED=enabled`, shipped block `A_RC=0` |
| **B. subject** | wants path is a directory | `B_RC=1`, message verbatim below |
| **C. old-code control** | same fault | **`C_RC=0`, `C_OUT_LEN=0`, `C_ISENABLED_AFTER=disabled`** |
| **D. collateral control** | same fault, different unit | `clawfactory-send.service` `D_RC=0`, `D_ISENABLED=enabled` |
| repair | injection removed | all four of `REPAIR_U/COLL` × `enabled/active` |

**C is the claim "the old code did not catch it", measured rather than asserted.** The shipped
v1.4.5 line returned **exit 0 with zero bytes of output** while the unit sat `disabled`.

**B, verbatim from the box:**

```
[quarantine] FATAL: clawfactory-quarantine.service did not enable (systemctl is-enabled said
'disabled'). Deletes are only recoverable while the quarantine broker is running, and a unit
that is not enabled does not come back after you restart your PC. The install would finish, the
guard would work today, and the first restart would silently remove it. Refusing to complete.
```

**Calibrated in both directions**, as Task 2.2 requires: A proves the check passes a correctly
enabled unit, so it is not a check that always fails; D proves the injection is targeted at one
unit rather than breaking every enable.

**Additionally, an INPUT-SHAPE SWEEP taken on the build machine** against the same extracted
bytes with a stubbed `systemctl`. Accepts only the literal `enabled`; denies
`enabled-runtime`, `static`, `linked`, `masked`, `disabled`, the empty string, a
`Failed to get unit file state...` error, and a multi-line answer. `enabled-runtime` denying is
the point rather than a side effect: runtime enablement is precisely what does not survive a
reboot.

**The two `setup.ps1` read-backs were NOT exercised against a rigged input.** They are the same
shape and the same comparison, and both were exercised in the succeeding direction on every
install and restart in this run, but neither has had its failure branch fired. **Recorded as
owed, not claimed.**

### 4.7 The instruments were wrong twelve times. The product was wrong zero times

This is the most useful thing the run produced and it is reported at full length rather than
summarised, because a probe that has never been wrong has usually just never been checked.

**Defects that produced, or would have produced, a FALSE PRODUCT FINDING:**

1. **`ActiveEnterTimestampMonotonic` cannot measure a `Type=oneshot` with no `RemainAfterExit`.**
   Such a unit goes `inactive → activating → inactive` and never enters `active`, so the field is
   structurally always `0`. `clawfactory-fw.service` is exactly that shape. The probe read `0`
   and scored *"did not come back"* for a unit whose own journal recorded it starting and
   finishing five seconds after boot, with the nft table present and uid 1000 blocked 6 of 6.
   **This was one step from being written up as a ship-blocking finding against the egress
   firewall** -- the `cfv-167` shape exactly. Fixed to `InactiveExitTimestampMonotonic`.
2. **Guard checks taken inside the gateway's cold-start window.** The OpenClaw gateway needs
   ~50 s from launch to `[gateway] ready` (18:33:24 → 18:33:53, measured). Inside it the proxy
   answers 502 and nothing answers on 8788 -- indistinguishable from a gateway that never came
   back. Produced a FAIL on G4 that was a pure transient. Fixed: poll on state, record the wait
   (`GW_READY_AFTER_S`).
3. **An expectation that contradicted the tree.** The probe asserted all eight units should read
   `active`, on the written grounds that *"the two oneshots carry `RemainAfterExit=yes`"*.
   `clawfactory-fw.service` has none, and both plain-enabled units had never been started.
   One false FAIL. Fixed to a per-unit table with each unit's `file:line` beside it.
4. **`Compare-Independent` fed two differently-worded summaries of the same fact.** It tests
   string equality, so the row could never pass: it reported *"8 units, 0 unaccounted for"*
   against *"8 units, 0 missing, 0 unexpected"* and called that a disagreement. **A FAIL whose
   own evidence line said the two sets agreed.** A reviewer reading verdicts rather than evidence
   would have carried a phantom finding into this document.
5. **A culture-aware sort applied to one list and not the other.** `Sort-Object` orders
   `clawfactory-quarantine.service` before `-gc.timer`; the hand-written list assumed the
   opposite. Fixed to an ordinal sort on both sides, calibrated against that exact pair.

**Defects that produced a VOID, a blind reader, or a silent no-op:**

6. **A control that could never fail.** `Test-WslChannel` returns a hashtable, and a non-null
   hashtable is truthy, so `-Met $chan` always passed. The phaselib exists to prevent exactly
   this and it was reintroduced in the probe written to apply it. Fixed to `$chan.Ok`.
7. **A precondition that could not hold on the box it ran on.** The Install stage asserted the
   WSL channel, and the Install stage runs on a box with no distro. VOID, correctly, before the
   installer launched. Fixed with `-NeedChannel`.
8. **Census and guards taken in different distro boots, unasserted.** WSL idle-terminates the
   distro between dispatches. Fixed: both halves stamp `/proc/sys/kernel/random/boot_id` and the
   stage asserts they match.
9. **`${VAR:-default}` in the input-shape stub** treats an explicitly-empty value as unset, so
   the "empty" case silently ran as the "enabled" case and scored a false pass. Caught by the
   sweep finding its own instrument first. Fixed to `${VAR-default}`.
10. **A poller that returned a 16.6 KB `.out` through `az vm run-command`** blew the output
    limit and came back **empty with `az` still exiting 0**. It showed nothing for forty minutes
    while the `.done` barrier had existed the whole time. Had it been trusted, the conclusion
    would have been that the install hung. Fixed: polls ask only for the barrier.
11. **A SAS expiry built from local time and labelled `Z`.** Ten uploads returned
    `AuthenticationFailed`, and the script printed `uploaded <file>` for every one of them,
    because the success line sat unconditionally after the call. **That is
    `switch-provider.ps1:349`'s defect, reproduced by this session, in this session.** Fixed to
    UTC with per-file HTTP status and an independent blob listing.
12. **`az.cmd` re-parsed a bracketed `--query`**, so the disk enumeration failed and the OS disk
    was silently not deleted. Caught only because the teardown prints an **unfiltered** residual
    rather than grepping for the VM name.

**Two of these -- 10 and 12 -- were caught by rules already in the preamble.** The rest are new,
and 1, 4 and 11 are the ones worth carrying forward.

### 4.8 Observations recorded, not actioned

- **WSL idle-terminates the distro** despite the `ClawFactory WSL Host` keepalive task reading
  `Ready`. Six distro boots in one session. Not a defect of this job's subject -- with no distro
  there is no agent to guard -- but it means "the guards are running" is only ever true while the
  distro is up, and nothing in the product says so.
- **The gateway's ~50 s cold start is user-visible.** For roughly the first minute after any
  restart, `127.0.0.1:8787` answers **502**. ClawChat opened in that window fails, and nothing
  tells the user to wait. Not measured further here.
- **`READFETCH_STATUS hosts=0 addresses=0`** on every boot: a fresh install allowlists nothing,
  which is the documented default, and the boot refresh correctly says so.

---

## 5. TASK 4.4 -- v1.4.6, or ride v1.5?

**Recommendation: ride v1.5. Do not cut a v1.4.6 for this.**

**Nothing came back missing.** All eight units returned, both plain-enabled oneshots ran at boot,
and all three guards plus the proxy still held. The measurement that had never been taken has now
been taken, and it came back clean. **The current release does not make a structural claim it
cannot support.** `SECURITY_FINDINGS.md` needs no correction, no withdrawal, and no new entry on
this subject -- and it is worth saying plainly that the outcome could easily have gone the other
way, because before today nobody knew.

**So what did the fix buy, if the units come back anyway?** It closes the gap between *these
units come back on a box where the enable succeeded* and *the product would tell you if an enable
had not*. Those are different claims. The run measured the first. The read-backs address the
second, which no measurement on a working box can ever establish, and which Task 2 shows the old
code could not detect: **exit 0, zero bytes of output, unit `disabled`.**

**Why that does not justify a release on its own:**

1. **The defect it closes is invisible-until-restart and, so far, unobserved.** No install in this
   project's history is known to have hit it. A release exists to get a fix to users who are
   currently harmed; nobody is known to be.
2. **Shipping it costs a full validation cycle.** `docs/VALIDATION_PREAMBLE.md` requires at least
   one stock-image box per cycle, and this job ran one baked box, deliberately scoped. The v1.4.5
   groundwork also leaves `#259`, `D1` and `OM-2` open on the install path, all of which touch
   `setup.ps1` -- the file this job just edited twice. Cutting v1.4.6 now means validating those
   edits twice: once alone, once again beside the v1.5 install-path work.
3. **`docs/VALIDATION_PREAMBLE.md` explicitly warns against stacking unvalidated releases**, and
   `project_v143_built_unvalidated` is the record of what that cost last time.

**What riding v1.5 obliges:**

- The five `.sh` read-backs have been exercised against a rigged input **and** in the succeeding
  direction on every install in this run. The two `setup.ps1` read-backs have been exercised only
  in the succeeding direction. **The v1.5 cycle owes the failure branch of both**, by the same
  directory-block injection, on `clawfactory-fw.service` and `clawfactory-allow-providers.timer`.
  Recorded in section 6 as an owed measurement.
- The v1.5 cycle must re-run this reboot row, because `setup.ps1` will have been rewritten by
  then and every expectation in §4.2 is derived from its current text.

**If the judgement were different and a v1.4.6 were cut**, the fix is ready: seven read-backs
across four files, all bundled, all parse-clean, all LF, with the census and the calibrated proof
in this document. It would need a signed build, a ledger row, and one stock box.

---

## 6. What this job leaves owed

1. **The failure branch of the two `setup.ps1` read-backs has never fired.** Same injection,
   `clawfactory-fw.service` and `clawfactory-allow-providers.timer`. An unproven `fatal` may be a
   no-op -- that is exactly why `interim-v141-fatalreadback.ps1` exists for the one read-back that
   preceded these.
2. **Four shell sites where a suppressed result is itself the claim**, from §0.4, unfixed:
   the two `nft flush set ... || true` under a comment that says every exit after that point is
   fail-closed; the two `nft add element ... || true` whose reported count comes from the file
   rather than the set; and `chattr +i` on `SOUL.md`, set and never read back.
3. **The Inno `[Code]` section** was named as a gap in the 2026-08-30 exit-code census and remains
   one. It has its own `Exec()` result convention and deserves its own pass.
4. **`OM-1` (the `:8787` dashboard) is untouched by this job and still stands.** Three cycles have
   now passed it over. This run did open `127.0.0.1:8787` from inside the distro as `clawuser`,
   which is *not* the measurement `OM-1` asks for -- that one is a browser click from the Start
   Menu shortcut on the Windows side, under an explicit recorded suspension of hazard rule #5.
5. **`OM-2` (reboot-and-resume) is untouched and still VOID.** This box took the import path, as
   §3.1 said it would.
6. **The gateway's ~50 s cold start after any restart**, during which `127.0.0.1:8787` returns
   502 with nothing telling the user to wait. Newly observed here; not a regression, not measured
   beyond the timings in §4.7 item 2.

---

## 7. Resource ledger

**Starting state** is at the top of this section, unchanged: storage account, VNET, two baseline
images, and `az vm list` empty. **No prior FAIL VMs or orphaned disks existed, so Task 0's
deletion step was a verified no-op rather than a skipped one.**

**Provisioned:** `cfv-191`, `Standard_D2s_v4`, `clawfactory-win11-baseline-v2`, non-zonal,
`--nsg-rule NONE` with a single RDP rule added afterwards scoped to `67.164.251.99/32`. Created
by the operator, who chose and kept the admin password; it was never generated, printed, asked
for, or changed after provisioning, and `az vm user update` was never called.

**Lifetime:** first boot `16:42:16Z`, torn down `~20:12Z`. Approximately **3 h 30 m** of one
D2s_v4.

**No licence slot to release.** ClawFactory ships free from v1.4.0 with the licence check removed,
so the `Machine deactivated successfully` step does not apply to this release. Stated rather than
silently skipped.

**Teardown**, NIC before the public IP and NSG it references:

```
vm delete exit=0    nic delete exit=0    pip delete exit=0    nsg delete exit=0
disk cfv-191-osdisk delete exit=0
```

**The disk was nearly left behind.** The enumerating `az disk list --query "[?starts_with(...)]"`
was re-parsed by `cmd.exe` and failed, and the loop over its empty output deleted nothing. It was
caught because the teardown prints an **unfiltered** resource list rather than grepping for the VM
name, and the disk was then deleted by explicit name.

**Ending residual, unfiltered, read three times including once after a 30-second gap because "it
said deleted" is not the same claim as "it is gone":**

```
clawfactoryvalc467              Microsoft.Storage/storageAccounts
bake-vmVNET                     Microsoft.Network/virtualNetworks
clawfactory-win11-baseline      Microsoft.Compute/images
clawfactory-win11-baseline-v2   Microsoft.Compute/images
```

`az vm list` empty. `az disk list` empty. **Exactly the expected residual, and identical to the
starting state.**

**Evidence retained** in the `validation` container as blobs and pulled to
`validation/diag/` on the build machine, byte-matched against what the box reported:
`v146-install2.out.txt` (16,649), `v146-a-pre3.out.txt` (31,545), `v146-b-wslcycle.out.txt`
(36,691), `v146-e-wsl2.out.txt` (36,913), `v146-f-post.out.txt` (36,133), `v146-h-inject.out.txt`
(15,101), `v146-c-diag.out.txt` (3,777), `v146-d-diag2.out.txt` (14,573),
`v146-g-postj.out.txt` (8,871), `v146-install.log` (61,597).

**Credential hygiene.** No provider API key was used or read; the install ran `/PROVIDER=claude`
with no key, and `destinationConfigured:false` in the Guard 2 ping confirms no SMTP credential was
present. No secret, header value, or password appears in any transcript or in this document.

---

## 8. Close-out gate

| Requirement | Status |
|---|---|
| Working root confirmed before starting | **DONE**, §0 header |
| Full preamble pasted, nothing deleted | **DONE**, stated in the first output |
| TASK 0 census from the tree, count verified | **DONE**, §0.1-§0.2 -- **eight units, not five** |
| TASK 0.3 read-back quoted verbatim | **DONE**, §0.3 |
| TASK 0.4 other unchecked actions in the `.sh` | **DONE**, §0.4, four named, none fixed |
| TASK 0.5 answered at full strength | **DONE**, §0.5 -- at install time, nothing, on any surface |
| TASK 1.1 read-back per unit | **DONE**, 5 in `.sh` + 2 in `setup.ps1` after approval |
| TASK 1.2 stop-or-warn decided, one option, implemented | **DONE**, §1.2 -- `fatal` |
| TASK 1.3 message in release-notes language | **DONE**, §1.3 |
| TASK 1.4 files changed and bundling | **DONE**, §1.4 -- all three `.sh` bundled |
| TASK 2.1 broken-input case per read-back | **DONE** for the `.sh`; **OWED** for the two `setup.ps1` sites, section 6 item 1 |
| TASK 2.2 calibrated in both directions | **DONE**, §4.6 -- A and D |
| TASK 3.1 one box, image stated, baseline recorded | **DONE**, §3.1 |
| TASK 3.2 install to completion, units confirmed | **DONE**, §4.2 |
| TASK 3.3 reboot, every unit confirmed back, verbatim | **DONE**, §4.4 |
| TASK 3.4 guards still hold, cheapest check named | **DONE**, §4.5 |
| TASK 3.5 report and stop if anything missing | **N/A** -- nothing was missing |
| TASK 4.1 dispatch card via the API from PowerShell | **DONE**, section 9 |
| TASK 4.2 `git status --short` first, per-file staging, push, no tag | **DONE**, no tag created |
| TASK 4.3 close-out committed and printed in full | **DONE** |
| TASK 4.4 v1.4.6 or v1.5, with reasoning | **DONE**, §5 -- ride v1.5 |
| No release, no tag, no signing, no ledger row | **HELD** -- none produced |
| Deallocate/delete at handoff | **DONE** -- box deleted, residual verified three times |

---

## 9. Dispatch

Card **#320**, `status=done`, created via `POST {DISPATCH_URL}/api/agent/update` from PowerShell
with the `x-frontier-secret` header. `python` is blocked by Windows Application Control on the
build machine, so `dispatch_card.py` was not used. The `description` was supplied in the `create`
call, because a card created without one can never be given one afterwards.

Tags: `validation`, `v1.5`, `systemd`, `guards`.

---

## 10. A note on the retained transcripts

The byte counts in section 7 are the **blob** sizes, which are UTF-16LE: the on-VM runner captures
job output with PowerShell 5.1's `*>` redirection, which writes UTF-16. The copies committed under
`validation/diag/` were converted to UTF-8 LF and are therefore about half those sizes. The
difference is an encoding conversion, not a truncation, and it is recorded here so a future reader
comparing the two does not read it as one.

**That encoding cost a reading.** A `grep` over the UTF-16 files returned nothing at all, which is
indistinguishable from a file that genuinely lacks the pattern. The conversion was followed by a
calibrated re-read: a marker known to be present was found, and a marker known to be absent was
not. The same discipline was applied before committing `v146-install.log`, which was swept for
credentials with a planted canary and a clean control in the same invocation -- five hits, all of
them the installer's own "no API key present" warnings, no values.

`v146-install.log` is **not committed**: `*.log` is gitignored in this repository. It is retained
as a blob in the `validation` container and on the build machine at
`validation/diag/v146-install.log`. Stated rather than left as a silent gap in the file list.
