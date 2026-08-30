# Pre-v1.4.5 groundwork — the census, the WSL1 decision, and the rule that closes the class

**Date:** 2026-08-30
**Repo:** `C:\Users\bmcki\ClawFactory-Secure-Setup`, branch `main`, clean at start (`dd03fa1`)
**Follows:** `docs/session_reports/2026-08-30_first_external_install_failure_closeout.md`, card `#315`
**Scope:** everything doable before the external machine's `install.log` arrives. Read-only,
documentation, specification. **`setup.ps1` was not modified.** Evidence in §7.2.
**Job state at close:** Tasks 1, 2, 3, 4 and 5 **COMPLETE**.

**Then the log arrived, and §9 is the addendum.** It settles the root cause with no inference
left, answers the reproduction's decisive row from the field, and adds three defects — D6, D7 and
D8 — found in the failure path rather than in the diagnosis. **No build was started.**

**Four things here contradict the prompt or the close-out this builds on: §2.3, §4.5, §5.4 and
§6.4 — plus one of my own claims corrected in §9, where I had reasoned that the missing
`ProgramData` directory proved a fallback had fired. It had not; the log existed all along.
All of them are reported rather than smoothed over.**

---

## 0. PROMPT 15 preamble — clauses deleted, and why

The paste block from `docs/VALIDATION_PREAMBLE.md` was pasted into this job in full. **Two
groups of clauses were deleted, both because no box is provisioned in this job and every
clause in them has no subject.**

**Deleted — the `ENVIRONMENT, NOT NEGOTIABLE` VM clauses:** `Standard_D2s_v4` / DSv5 quota,
the baseline image and resource group, one `az vm run-command` at a time, run-command runs as
SYSTEM and needs the interactive auto-logon session, `/var/tmp` not `/tmp`, `/mnt/c` as an
empty stub, the RDP `/32` rule, `-OutDir` on teardown, checking every `az` exit code,
deallocate at every handoff. **Why:** this job provisions nothing, runs nothing inside WSL,
and opens no network path. There is no VM to size, reboot, dispatch to, or deallocate.

**Deleted — `HUMAN HANDOFF CARDS`, Card 1 and Card 2 in their entirety, and the RESOURCE
LEDGER's Task 0 / sweep / licence-slot clauses.** **Why:** Card 1 is *"at provisioning"* and
Card 2 is *"before every reboot"*; neither event occurs. Task 0 deletes prior FAIL VMs before
provisioning; nothing is provisioned. There is no install, so there is no licence slot to
release.

**Retained and load-bearing, listed because each one changed what this session did:**

- **`CALIBRATE BEFORE MEASURING` and `AN AUDIT REGEX IS ITSELF A PROBE`.** The census script
  is a probe. It was calibrated against six planted canaries and one clean control before any
  count in this document was allowed to stand. §3.4 and §3.5.
- **`A CANARY ONLY CERTIFIES THE PATTERN AGAINST THE SHAPE OF THE CANARY`,** and its second
  half, *"where the question is enumeration rather than detection, parse the AST instead of
  matching text."* The census is an AST walk with a taint model, not a grep, for exactly that
  reason. The canaries were then built in shapes the target file does not already contain.
- **`IF THIS PROMPT IS WRONG, SAY SO BEFORE EXECUTING IT`** and **the pre-flight
  `DEPENDENCY CENSUS`.** Task 3's premise did not survive reading the code. §5.4.
- **`A CITATION PROVES THE PROVENANCE OF A SENTENCE, NOT THE PROVENANCE OF THE ARTEFACT.`**
  Task 4's whole finding is an instance of it: the close-outs that cite
  `clawfactory-win11-baseline` describe what the image is *for*; the bake script describes
  what the image *is*, and the two disagree.
- **`GIT`.** `git status --short` first, explicit per-file staging, no `git add -A`, no tag.
- **The Dispatch API clause.** `python` is blocked by Windows Application Control; the card
  went out over PowerShell with `x-frontier-secret`.

I did not delete the `MEASUREMENT DISCIPLINE` phase-runner clauses, but they had no subject
either: no phase ran, so no verdict vocabulary was used and `validation/interim-v120-phaselib.ps1`
was not invoked. Recorded rather than deleted, because a later reader should be able to see
that the absence was noticed.

---

## 1. TASK 1 — the held commits, pushed

### 1.1 What was about to become public, reported before pushing

```
$ git status --short
(clean)

$ git log origin/main..HEAD --oneline
dd03fa1 docs(closeout): fix an internal section cross-reference (calibration is 5.3, not 6.2)
958d337 docs(closeout): first external install failure -- five defects traced, fix designed, reproduction staged
90c42a5 docs(catalogue): Class 13 -- a validation fleet identical in the dimension that decided the outcome
86b1481 validation: the regression rig for the first external install failure, written before the fix
```

Four commits, four files, 1,503 insertions and 7 deletions:

| File | Change |
|---|---|
| `docs/FAILURE_CATALOGUE.md` | +85 / −7 — the Class 13 entry, and one corrected sentence in the header |
| `docs/session_reports/2026-08-30_first_external_install_failure_closeout.md` | +852, new |
| `validation/interim-v145-pendingreboot.ps1` | +334, new |
| `validation/interim-v145-runner.ps1` | +232, new |

**What that publishes**, stated plainly because the repository is public: that the first
person outside this project to install v1.4.4 could not, that it failed 88 seconds in, that
the message he got named a Linux user account, that five defects were traced to it, that the
four boxes which passed were four copies of one sample, and that the reboot-and-resume
subsystem has never run to completion in any recorded validation of this product.

A secret scan over the full diff returned three hits, all of them prose *forbidding* the
handling of a password (`"Do not generate an admin password, do not print one…"`). No key,
token, subscription id, IP or credential.

### 1.2 Pushed, and verified from the public repository rather than from the push return

```
$ git push origin main
   d10ebfe..dd03fa1  main -> main
```

Then, anonymously, from `raw.githubusercontent.com`, in a scratch directory, with no
credentials on the request — and compared against the **git blob**, not the working tree, so
that the comparison cannot be fooled by a line-ending rewrite:

```
http=200  bytes=69957   docs/FAILURE_CATALOGUE.md
  "## Class 13: a validation fleet identical in the one dimension that decided the outcome"  (line 1037)
  remote sha256 = 5554a780aa1961bd7258c1aca56bdb0ccd79f04b35cd8aa7c6ca991cde9c9820
  local  sha256 = 5554a780aa1961bd7258c1aca56bdb0ccd79f04b35cd8aa7c6ca991cde9c9820   MATCH

200  remote=1f0e1a619b343926  local=1f0e1a619b343926  MATCH  docs/session_reports/2026-08-30_first_external_install_failure_closeout.md
200  remote=c19952933f2d3130  local=c19952933f2d3130  MATCH  validation/interim-v145-pendingreboot.ps1
200  remote=069c3928d843829e  local=069c3928d843829e  MATCH  validation/interim-v145-runner.ps1
```

### 1.3 Nothing else rode along

```
local  HEAD = dd03fa176a2d6d1894b89aa540d2fae676beb374
origin main  = dd03fa176a2d6d1894b89aa540d2fae676beb374
ahead/behind = 0  0
git status --short = (empty)
```

Four commits offered, four commits landed, working tree clean before and after.

---

## 2. TASK 2 — the exit-code census: method

### 2.1 What the census is looking for

D2 is *"an exit code accepted as proof that a state exists."* The census subject is every
site where a **return code, a return value, or a truthy result** is the evidence for a claim
about the world. That includes the inverse shape, which is more common in this file: a
`if ($rc -ne 0) { throw }` concludes failure from non-zero and, by falling through, concludes
**success from zero** — that fall-through is the claim, and the question is whether anything
checks it.

### 2.2 Why an AST, and what the taint model does

Per the preamble, enumeration means parsing rather than matching. `validation/census-exitcode-proof.ps1`
(committed with this job) walks the PowerShell AST and:

- **seeds** on `$LASTEXITCODE`, `$?`, and any member access named `ExitCode`;
- **taints** any variable assigned an expression containing a seed, iterated to a fixed
  point;
- **taints** any function whose own `return` carries a seed (so `Test-WslFunctional` and
  `Invoke-WslBash` become tainted, transitively), also to a fixed point;
- then reports every `if` clause, `while`, `do/while`, `do/until` and `switch` whose
  condition contains a tainted expression, with its enclosing function and the first
  statement of the taken branch;
- and separately reports every function that `return`s a bare status token, because
  `return 'wsl2'` is a return value used as evidence just as much as an integer is.

It over-reports on purpose. A census that misses is worse than a census that has to be read.

**One guard worth recording.** `TernaryExpressionAst` does not exist in Windows PowerShell
5.1's parser, and 5.1 is what runs `setup.ps1` (Inno launches `powershell.exe`). The script
resolves the type by name and skips the search if absent, rather than assuming; a ternary in
`setup.ps1` would be a parse error, not a missed hit. `pwsh` is not installed on this machine
(`which pwsh` → not found; `$PSVersionTable.PSVersion` → 5.1.26100.9168), so this is not a
hypothetical.

### 2.3 A note on what the prompt asked for versus what the code supports

The prompt frames the census as *"find every other instance before a user does."* That is the
right frame. But two of the biggest findings below are not `if ($rc -eq 0)` at all — they are
**`|| true` in shell** (§4.2) and **a claim printed unconditionally beside a checked exit
code** (§4.3). Restricting the census to PowerShell `if` statements would have found neither.
The census was extended accordingly and §4 says how the files were chosen.

---

## 3. TASK 2 — the census of `setup.ps1`

### 3.1 The counts

| | |
|---|---|
| Raw AST hits | **65** |
| False positives of the taint model | **16** |
| In dead code (`Enable-WindowsFeaturesForWsl`, defined and never called) | **1** |
| **Live sites** | **48** |
| — **verified** | **26** |
| — **unverified but harmless** | **8** |
| — **unverified and load-bearing** | **14** |
| Functions returning a bare status token | 7 (`Test-WslFunctional` ×4, `Install-WslDistroWithFallback` ×3) |

The 16 false positives are conditions the taint reached through an unrelated assignment and
which test no exit code at all: `567`, `758`, `997`, `1048`, `1138`, `1146`, `1152`, `1162`,
`1842`, `1846`, `2022`, `2027`, `2694`, `2702`, `3236`, `3343`. Two of them —
`1842` and `1846` — deserve naming as the **counter-example**: they check that the firewall
script text still contains `toolchain_ipv4` and `/usr/sbin/nft` *before running it*, which is
checking the state directly rather than trusting a result. That is what the load-bearing
sites below do not do.

### 3.2 The 14 unverified and load-bearing sites

*Load-bearing = a later step assumes the state and will fail confusingly or silently if it is
absent.*

| Line | Function | What the code concludes from the code | What would have to be true for that to be sound | Verified before the next step depends on it? |
|---|---|---|---|---|
| `266` | `Update-WslEngine` | `$rc -ne 0` → WARN; `$rc -eq 0` → the WSL engine is now usable | that `wsl --update` exiting 0 means no restart is pending. It does not: on the external machine it exited 0 **and printed** *"Changes will not be effective until the system is rebooted"* | **No.** `$out` is captured, logged, and never referenced again. The only function that understands DISM's 3010 is dead code. **This is D1.** |
| `488` | `Install-WslDistroWithFallback` | `$rImp.ExitCode -eq 0` → *"WSL2 import from bundle succeeded"*, `return 'wsl2'` | that `wsl --import` exiting 0 means a registered, bootable distro exists | **No.** Nothing between the `return` and `New-ClawUserAndSetDefault`. **D2.** |
| `502` | same | `$rInst.ExitCode -eq 0` → *"WSL2 install succeeded"*, `return 'wsl2'` | same, for `wsl --install --no-launch` | **No.** On the external machine this returned 0 **in the same second** the import failed — a network install of Ubuntu in under a second. **D2, the highest-severity defect in the product.** |
| `526` | same | `$rFb3.ExitCode -ne 0` → throw; else *"WSL1 fallback install succeeded"*, `return 'wsl1'` | same again, for the WSL1 path | **No** — and this one is also a security item. §5. |
| `850` | `Step-EnsureWsl` | `$rList.ExitCode -eq 0 -and $rList.StdOut` gates the computation; on failure `$distroExisted` stays `$false` and `wsl-state.txt` is written `false` | that a failed `wsl --list` means no pre-existing distro | **No, and the default is the destructive one.** `false` tells the uninstaller the distro is ClawFactory's to remove. On the external machine this call took **sixty seconds** — the shape of a call about to fail. **New in this census.** |
| `923` | `Step-EnsureWsl` | `$kernelOk = ($procStatus.ExitCode -eq 0)` from `wsl --status` → take the import branch instead of the reboot-and-resume branch | that `wsl --status` exits non-zero in a features-enabled-reboot-pending state | **No.** This is the branch the external machine took and **the premise the whole D1 diagnosis turns on.** It is `PR.C1` in `validation/interim-v145-pendingreboot.ps1` and is not yet measured. |
| `968` | `Step-EnsureWsl` | identical, `$procStatus2.ExitCode -eq 0` → *"WSL kernel loaded without reboot"* | identical | **No.** Same shape, second site. |
| `1309` | `Step-SetDefaultUser` | `$rDefaultBoot.ExitCode -ne 0` → fall back to a root boot and WARN | that a `clawuser` boot failing is recoverable by booting as root | **No.** The install proceeds with the default user possibly still root, and nothing re-checks it. `Assert-WslAutomountDisabled` runs next and checks automount, not the user. |
| `1852` | `Step-EgressFirewall` | `$rc -ne 0` → ERROR, **no checkpoint, and `return` rather than `throw`** | that continuing without a firewall is survivable | **Yes, but twenty-one steps later.** `install-send.sh:194` runs `clawfactory-fw-assert.sh \|\| fatal` and `Step-InstallSend` throws. Between them the entire OpenClaw install, gateway bring-up, turn gate and SOUL freeze run with no egress control. The preamble's *"WHEN is it needed"* question, unanswered in the tree. |
| `2697` | `Step-ConfigureOpenClaw` | `$rc -ne 0` → WARN | that a missing default model is cosmetic | **No.** The agent has no model and the install reports success. |
| `2717` | `Step-ConfigureOpenClaw` | `$rc -ne 0` → WARN | that a missing auth profile is cosmetic | **No.** `Step-WireProviderKey` then writes the key into `auth-profiles.json` for a profile id that `openclaw.json` does not know about. |
| `2922` | `Step-InstallTurnGate` | `$rc -ne 0` → throw; `$rc -eq 0` → the gated shim is installed and working | that `install-turn-gate.sh` exits non-zero if the shim does not work | **No — and the installer's own check was written and then downgraded.** Its last block is *"Verify passthrough (a non-agent subcommand must still work)"* and on failure it prints `WARN` to stderr and exits 0. The product's claim that no caller can launch an ungated turn rests on this integer. |
| `3142` | `Step-InstallQuarantine` | `$rc -eq 0` → Guard 1 is installed | that `install-quarantine.sh` proves both halves of `systemctl enable --now` | **Half.** Its live socket ping, run *as the agent uid*, is excellent and proves **running now**. Nothing proves **enabled at boot** — `systemctl enable --now … \|\| true`, never read back. §4.2. |
| `3190` | `Step-InstallChatProxy` | `$rc -eq 0` → the gating proxy owns 8787 | same | **Half**, identically. Its health probe through the proxy *as clawuser* is the right probe; `systemctl enable --now clawfactory-proxy … \|\| true` at `install-chat-proxy.sh:87` is not read back. |

### 3.3 The 26 verified and the 8 harmless, named so the reader can check the arithmetic

**Verified** (something checks the state directly — usually the bash payload's own last act
under `set -e`, which is the pattern done right): `282`, `289` (`Test-WslFunctional` is the
instrument; its third call, `-d Ubuntu -u root -- true`, is the check D2 needs), `874`, `888`,
`898`, `930`, `975` (all `Test-WslFunctional` calls), `1217` (`Assert-WslAutomountDisabled`
— an `awk` over the real file, section-scoped), `1247` (followed immediately by that assert),
`1289`, `1304`, `1364`, `1386`, `1947`, `1981`, `2430` (`$rc` warns; the `/status` poll at
`~2600` throws, and `2585`'s comment says explicitly that the poll is the authority and the
block exit is not), `2691`, `2751` (payload ends with `bash -n`, a source, and two `type`
checks), `2795`, `2891` (payload ends comparing `sha256sum` against the pin), `2987`,
`3051`, `3092`, `3271` (the exit code **is** the TCP connect result), `3384`, `3416`.

**`3051`, `install-send.sh`, is the strongest instrument in the product and should be the
template for the rest.** It ends with a live socket ping performed as the agent account
*and* a **paired negative control** asserting the agent cannot reach the approval socket,
with `fatal "SECURITY: … Refusing to complete the install."` if it can. A positive probe
alone would prove reachability and nothing about isolation.

**Unverified but harmless** (nothing downstream depends on the conclusion): `507`, `556`,
`614`, `952`, `1894`, `1980`, `2817`, `3393`. `556` is worth one sentence: the throw is
correct, the *message* is not — `Failed to pre-create clawuser stub (exit=-1)` names a Linux
account for a `wsl.exe` that could not launch a distro. That is D5's territory, not this
census's.

### 3.4 Calibration — the canaries, and the byte-identity proof

Per `AN AUDIT REGEX IS ITSELF A PROBE`, and per its sharper second half, the canaries were
built in shapes **`setup.ps1` does not already contain**, verified absent first:

```
PowerShell-level $?          : 0   (4 textual hits, all inside bash here-strings)
reversed operands "0 -eq"    : 0
switch on an exit code       : 0
exit code in a property bag  : 0
```

Planted at the end of the real `setup.ps1`, in two rounds.

**Round 1 — shapes expected to be found, plus a clean control:**

| | Shape | Result |
|---|---|---|
| C1 | `if (0 -eq $cProc.ExitCode)` | **FOUND** (`seed`) |
| C2 | `& cmd.exe /c "exit 0"` then `if ($?)` | **FOUND** (`seed`) |
| C3 | `switch ($cProc.ExitCode) { 0 { … } }` | **FOUND** (`switch`, `seed`) |
| C4 | `$cState = @{ rc = $cProc.ExitCode }` then `if ($cState.rc -eq 0)` | **FOUND** (`var:$cState`) |
| D1 | `if ($cName -eq "widget")` — **clean control** | **NOT REPORTED** ✅ |

Total moved **65 → 69**: exactly the four canaries, so the clean control did not inflate the
count and nothing else shifted.

**Round 2 — shapes expected to be missed, planted after round 1 was removed and the file
proved identical:**

| | Shape | Result |
|---|---|---|
| C5 | exit code written to a file, read back later, then tested | **MISSED** |
| C6 | exit code passed across a parameter binding into another function | **MISSED** |

Total stayed at **65**. Both misses are exact.

**Removal, proved by hash and not by `git status`:**

```
after round-1 removal : bytes=214311  sha256=26e1593d…0573b7   matches original: YES
FINAL bytes           : 214311  (orig 214311)
FINAL  sha256         : 26e1593db3351c961df6c9a43c08483e73111af7da48ccf1d94c8260420573b7
ORIG   sha256         : 26e1593db3351c961df6c9a43c08483e73111af7da48ccf1d94c8260420573b7
BYTE-IDENTICAL        : YES
committed blob sha256 : 26e1593db3351c961df6c9a43c08483e73111af7da48ccf1d94c8260420573b7
git status --short    : (empty)
```

`git status` was empty at every stage, including with 1,144 bytes of canary appended to a
tracked file — which is the point of not using it. The removal was a `truncate` back to the
recorded original byte length, so byte identity is structural rather than hoped for, and the
worktree hash matching the git blob hash additionally confirms `setup.ps1` is LF in both
(`git ls-files --eol` → `i/lf w/lf`), so the `core.autocrlf` hazard did not apply here even
though the guard against it did.

### 3.5 What the census cannot catch

Measured, not asserted — C5 and C6 above are the empirical statement of it.

1. **A value that crosses a boundary the AST cannot follow.** Written to a file and read
   back; passed across a parameter binding; round-tripped through JSON, the registry, an
   environment variable, or the checkpoint file. The taint model follows assignments and
   function returns inside one file, and nothing else.
2. **Anything outside PowerShell `if`/`while`/`switch`.** `|| true` in shell, an unchecked
   `spawnSync` in Node, and `Write-Host "[x] done"` printed beside a checked exit code are
   all the same defect and none of them is a decision site. §4 covers them by other means,
   by hand, which is weaker.
3. **Intent.** The census cannot tell a sound use from an unsound one. `clawfactory-sendd.js`
   is full of `r.status === 0` and every one is correct, because there the exit code of a
   `setpriv … /usr/bin/test -r` **is** the state being asked about. Only reading settles it,
   which is why §3.1 reports 65 raw and 48 live and does not pretend they are the same
   number.
4. **Cross-file reasoning.** It cannot see that `setup.ps1:3142`'s `$rc` is only as good as
   `install-quarantine.sh`'s last twenty lines. Every "verified downstream" verdict in §3.3
   is a human judgement about a second file.
5. **Absence.** It enumerates checks that exist. It cannot report a state nobody thought to
   check at all — which is what D1 actually is: not a wrong condition, a **missing** one.

---

## 4. TASK 2.3 — the other shipped scripts

### 4.1 Which files, and how they were chosen

The scope rule: **the pattern bites where a script sequences install steps or makes a claim
to a user.** From `ClawFactory-Secure-Setup.iss`'s `[Files]` section, the shipped executable
content is 9 PowerShell files, 13 shell files and 12 Node files.

- **All 9 shipped `.ps1`** — `resources\{post-install,bootstrap,rename-agent,launcher,clawfactory-stop,clawfactory-grants,switch-provider,uninstall}.ps1`
  and `smoke-test.ps1` — through the same AST census. **68 raw hits.**
- **All 13 shipped `.sh`** by hand, for the two shapes the AST cannot see: every
  `|| true` / `|| :` that swallows a state change, and every `systemctl enable` without a
  read-back. `openclaw-install.sh` is vendored upstream (37 `|| true` sites) and was
  **excluded from adjudication**, named here so the exclusion is visible rather than silent.
- **All 12 shipped `.js`** by grep for `spawnSync` / `execFileSync` / `.status === 0`.

Not covered, and why: the `.service`/`.timer` units (declarative, no exit codes), the static
resources, `adversarial-suite.ps1` and `validation/*` (instruments, not shipped), and the
Inno `[Code]` section, which is a separate language with its own `Exec()` result convention
and deserves its own pass. **That last one is a gap in this census and is recorded as one.**

### 4.2 Shell — the strongest cross-file finding

**Five systemd units are enabled with the result discarded, and only the "running now" half
is ever tested.**

```
install-quarantine.sh:140  systemctl enable --now clawfactory-quarantine.service     >/dev/null 2>&1 || true
install-quarantine.sh:141  systemctl enable --now clawfactory-quarantine-gc.timer    >/dev/null 2>&1 || true
install-send.sh:190        systemctl enable --now clawfactory-send.service           >/dev/null 2>&1 || true
install-send.sh:191        systemctl enable --now clawfactory-send-gc.timer          >/dev/null 2>&1 || true
install-chat-proxy.sh:87   systemctl enable --now clawfactory-proxy                  >/dev/null 2>&1 || true
setup.ps1:1830             systemctl enable clawfactory-fw.service                   2>/dev/null || true
```

`enable --now` makes two claims. The socket pings and health probes that follow prove the
first. **Nothing in the product proves the second for Guard 1, Guard 2 or the gating proxy.**

`install-read-fetch.sh:379-386` is the counter-example, and its comment is the argument:

> *"READ BACK. `systemctl enable` is routinely written here with `|| true`, which means a unit
> that failed to install looks identical to one that did."*

It reads back `systemctl is-enabled` and `fatal`s on anything but `enabled`. Three files
should do what the fourth already does.

**Two `nft flush set … || true` in the exposure direction.** `clawfactory-read-fetch.sh:72`
and `clawfactory-toolchain.sh:144`, each sitting directly under:

> `# --- 1. Flush first. Every exit after this point is fail-closed. -------------`

The set's existence is checked; the flush's success is not. If the set exists and the flush
fails, the previously-allowed addresses remain live while the script adds the new list and
reports the new count — a revoked host stays reachable while the panel says it was revoked.
Low probability, wrong direction, and **the code contradicts its own comment**, which the
preamble names as a defect in a security product because the comments are the audit trail.

**`install-turn-gate.sh`'s final verification is a WARN**, already counted at `setup.ps1:2922`.

### 4.3 The other shipped PowerShell — 5 load-bearing after adjudication

- **`switch-provider.ps1:349`.** `if ($fwExit -ne 0) { Write-Warning … }` and then,
  **unconditionally**, `Write-Host "  [x] egress allowlist updated (backend auto-detected)"`.
  The green tick prints whether or not the firewall changed. After a provider switch that can
  mean no route to the new provider, the old provider's addresses still allowed, and a user
  who has been shown a check mark for both. **This is D2's shape on a customer-facing
  surface.**
- **`switch-provider.ps1:148`.** The `auth-profiles.json` key write warns and continues; the
  gateway keeps the old key.
- **`clawfactory-grants.ps1:588`, `Sync-GovernorMirror`.** `if ($r.ExitCode -eq 0) {
  $script:CF_LastMirroredCaps = $payload }`. The bash is `;`-chained with no `set -e` and its
  **last** command is `chmod 644`, so **the exit code reports the chmod, not the
  `base64 -d > /etc/clawfactory/governor.json` that does the work.** On a failed write the
  redirect has already truncated the file, `chmod` succeeds, the caps are cached as mirrored,
  and the module never retries. The consequence is fail-**closed** —
  `clawfactory-turn-gate.sh:50-53` emits `spend_config_missing` / `spend_config_bad` and
  blocks the turn — which is the right direction and still leaves the user permanently
  blocked with no self-heal after changing a cap in Studio.
- **`bootstrap.ps1:279`.** Per-agent auth-profile fan-out warns and continues.
- **`post-install.ps1:228`** and the remainder are harmless.

**Two verified worth naming as good practice.** `uninstall.ps1:607` computes
`$teardownOk = ($rc -eq 0) -and ($teardownOut -contains 'CLAWFACTORY_TEARDOWN_OK')` — the
exit code **plus** a terminal sentinel, which is entry 2.1's fix and the reason it holds.
`switch-provider.ps1:388/395` looks like the pattern and is not: its payload's last act is a
40 × 3s poll of `/status`, so `$ocExit -eq 0` really does mean the gateway answered. *(One
copy defect there, filed not fixed: the failure branch says "did not confirm health within
12s" for a loop that runs 120s.)*

### 4.4 Node — a null result, reported as one

**Zero load-bearing instances across the 12 shipped `.js` files.** The exit codes checked in
`clawfactory-quarantined.js:81`, `clawfactory-sendd.js:98` and `:134` are
`spawnSync('setpriv', […, '/usr/bin/test', …])` results, where the exit code **is** the
permission question being asked. `clawfactory-sendd.js`'s `stageAttachment` goes further and
makes the check and the read the *same operation*, closing the TOCTOU window rather than
testing around it. The one unchecked `spawnSync` — `clawfactory-quarantinectl.js:170`'s
`chown` after a restore — is documented in place as expected-to-fail on drvfs and genuinely
does not change the outcome.

This is worth stating rather than padding the finding list: the layer written most recently
and most deliberately does not have the defect.

### 4.5 Where §3 and §4 contradict the prompt

The prompt says *"D2 was not a one-off."* Correct. It also implies the pattern is uniform
across the product. It is not: `setup.ps1`'s early install steps have it badly, the guard
installers written in 2026-08 mostly do not, and the Node layer does not have it at all. The
distribution is **chronological** — the older the code, the worse it is — which suggests the
practice has already improved and the remaining sites are debt rather than habit. That
changes how the v1.5 work should be framed and is why §7's backlog entry orders by severity
rather than by file.

---

## 5. TASK 3 — the WSL1 fallback

Full specification is in `docs/V1_5_BACKLOG.md` § *v1.4.5-A*. This section carries the
verification and the correction.

### 5.1 Verified from the code: which controls are systemd, and which are not

**Eleven systemd units**, taken from `resources/uninstall.ps1:420`'s `CF_UNITS` list and each
one traced to where it is defined and installed:

| Unit | Control | Defined / installed |
|---|---|---|
| `clawfactory-quarantine.service` | **Guard 1** delete broker | `resources/clawfactory-quarantine.service` → `install-quarantine.sh` |
| `clawfactory-quarantine-gc.service`, `.timer` | Guard 1 retention | same |
| `clawfactory-send.service` | **Guard 2** approval-gated send broker | `resources/clawfactory-send.service` → `install-send.sh` |
| `clawfactory-send-gc.service`, `.timer` | Guard 2 retention | same |
| `clawfactory-proxy.service` | **Blocker 1** chatCompletions gating proxy | `resources/clawfactory-proxy.service` → `install-chat-proxy.sh` |
| `clawfactory-fw.service` | egress allowlist re-applied at boot | written inline `setup.ps1:1817`, enabled `1830` |
| `clawfactory-allow-providers.service`, `.timer` | provider-address re-add | `setup.ps1:2233`, `2243` |
| `clawfactory-egress-refresh.service` | **Guard 3** boot refresh | `install-read-fetch.sh:~370` |

Plus **`openclaw-gateway.service`** as a *user* unit under `systemctl --user`, requiring
`loginctl enable-linger` and `dbus-user-session` (`setup.ps1:1349-1362`), and
`/etc/wsl.conf`'s `[boot] systemd=true` (`setup.ps1:1239`), which WSL1 does not read.

**Three controls do NOT depend on systemd**, and the prompt asked to say so:

1. **The live nftables/iptables chain.** `Step-EgressFirewall` applies it directly with
   `nft -f`; only its survival across a restart is `clawfactory-fw.service`.
2. **`/etc/wsl.conf`'s `[automount] enabled=false` / `[interop] enabled=false`** — the P0
   file-isolation guard, verified by `Assert-WslAutomountDisabled` (`setup.ps1:1217`).
3. **The gated `openclaw` shim** at `/usr/bin/openclaw` — a filesystem substitution.

### 5.2 What a WSL1 install would actually lack

If it completed: Guard 1, Guard 2, Guard 3's boot refresh, Blocker 1, the firewall's reboot
persistence, the provider-address re-add, and the gateway itself. That is every broker and
every scheduled control. The `[boot] systemd=true` line written by `Step-ConfigureWslConf`
would be inert, and `setup.ps1:529`'s *"Some features (systemd, networking) behave
differently on WSL1"* would be describing the absence of most of the product's security
model as a difference in behaviour.

### 5.3 Every other mention of WSL1, `$variant`, or a distro-version branch

`$variant` is assigned at exactly three sites — `882`, `926`, `971` — and each is followed by
one `Write-Log INFO "WSL variant installed: $variant"` and nothing else. **It is never
persisted, never branched on, never read again.** Removing the fallback leaves no dangling
branch, and the fact that it leaves none is itself the point: the installer discovers it is
on WSL1 and does nothing differently.

Complete tree-wide census (excluding `docs/session_reports/`, `reports/`, `validation-runs/`,
which are history):

| Site | What | Action |
|---|---|---|
| `setup.ps1:432, 436, 438` | comments describing the fallback | delete with it |
| `setup.ps1:506-530` | the branch | delete |
| `setup.ps1:831, 879` | comments naming "with WSL1 fallback" | reword |
| `setup.ps1:882/926/971` + `883/927/972` | `$variant` assign + log | keep or drop the return value; nothing reads it |
| `resources/launcher.ps1:196` | comment explaining why the launcher probes HTTP rather than `systemctl is-active` — *"returned inactive on systemd-less WSL installs (WSL1 fallback or systemd-disabled)"* | **keep code and comment.** The HTTP probe is right independently and "systemd-disabled" stays reachable |
| `resources/uninstall.ps1:420` | comment *"uses iptables on WSL1"* | reword — the iptables-legacy backend remains reachable on a WSL2 kernel without nftables (`setup.ps1:1681`) |
| `validation/uninstall-teardown-extract.sh:4` | same comment, extracted copy | reword with it |

No `wsl --list --verbose` parse, no `--set-version` read-back, no `$variant` consumer
anywhere. Removal is clean.

### 5.4 **The correction. A WSL1 install does not ship insecure — it cannot complete.**

§4.3 of the prior close-out says *"A WSL1 install would produce a ClawFactory with none of
its security controls."* Read against the code, that is not what happens, and the operator's
decision was taken on that premise.

A WSL1 install dies, in this order:

1. **`Step-PreinstallGatewayRuntime`** (`setup.ps1:3743`) polls
   `http://127.0.0.1:8787/status` thirteen times over 120s and `throw`s *"Gateway did not
   respond after 120 seconds"*. The gateway is started **only** through `systemctl --user`
   (`setup.ps1:2540-2546`). **There is no `nohup`/`setsid` fallback anywhere in `setup.ps1`
   or `resources/gateway-wait.sh`** — verified by grep, zero hits.
   `resources/launcher.ps1:205-206` says *"Layered fallback: systemd --user → openclaw
   gateway start → nohup setsid openclaw gateway run. Same logic as setup.ps1's
   Step-PreinstallGatewayRuntime."* **That comment is stale.** The launcher has the layered
   fallback (`launcher.ps1:166-176`); the installer does not.
2. **`Step-FreezeInjectedSoul`** (`3753`) runs `freeze-injected-soul.sh`, whose
   `chattr +i "$WS"` at line 104 is unguarded under the `set -e` at line 29.
3. **`Step-InstallQuarantine`** (`3754`): `install-quarantine.sh` has no start path for the
   broker other than the systemd unit (`ExecStart` in
   `resources/clawfactory-quarantine.service`, and grep finds no `nohup`/`setsid`/
   `start-stop-daemon` in the installer), so its 30-second socket ping ends in
   `fatal "broker did not answer a ping from $AGENT_USER within 30s"` → `exit 1` →
   `setup.ps1:3142` throws.

**So the real defect is different, and worse in one specific way.** A user on a machine
without virtualization spends roughly twenty minutes, then gets a message about a *gateway
health probe* or a *broker socket*, on a machine whose actual problem is that WSL2 is
unavailable. **Nothing tells them that.** It is the same defect class as
`Failed to pre-create clawuser stub` — a failure reported twenty minutes and four subsystems
away from its cause — reproduced in the branch that exists to handle the case.

**The decision to remove stands, and the argument for it is stronger, not weaker.** The
security-claims argument is partly wrong; the diagnosis argument is entirely right, and
removal converts a twenty-minute misleading failure into an immediate accurate one. It also
removes a branch whose success log line describes a state the product cannot actually reach.

**One premise is inherited rather than measured, and it is the same premise both the original
claim and this correction rest on:** that WSL1 has no systemd. It is not in dispute, but it
has never been measured on any box in this project — which is precisely the kind of gap
Task 4 is about, and it is recorded rather than quietly assumed on both sides.

---

## 6. TASK 4 — the rule, the records, and the correction

### 6.1 The preamble clause (4.1)

Added to `docs/VALIDATION_PREAMBLE.md` **inside the fenced paste block**, between
`AN AUDIT REGEX IS ITSELF A PROBE` and `RESOURCE LEDGER`, so it travels with PROMPT 15 into
every future job: **`A BASELINE IMAGE IS A SET OF INSTALL STEPS ALREADY COMPLETED`**. It
requires a written record per image, at least one stock-image box per cycle, and a run plan
that names which rows the baked boxes cannot answer.

**And the `ENVIRONMENT` clause that names `-v2` was amended rather than left standing.** A
paste block saying *"Image clawfactory-win11-baseline-v2"* next to a clause saying *"not only
that image"* is the same defect at smaller scale, and the preamble's own rule — *"where two
instructions arrive in the same reply, check them against each other before executing
either"* — applies to a document as much as to a reply. The environment line now scopes
itself to the baked boxes and defers explicitly.

### 6.2 The written records (4.2) — `docs/reference/BASELINE_IMAGES.md`

**The bake provenance IS recoverable from the tree.** My first pass concluded it was not,
because no file named for the purpose exists; that was wrong and the correction is worth
recording as a method note. It is in two places that do not announce themselves:
`validation-runs/phase1-bake-20260506-144034/` (`configure-vm.ps1`, `pre-sysprep-cleanup.ps1`,
`sysprep.ps1`, `log.md`) and `REPORT.md` at the repository root.

**`REPORT.md` is the record, and it is overwritten at every rebake.** Commit `962a189`
(2026-06-10) rewrote it in place, +121/−108, so the file today describes **only** the v2 bake
and the v1 bake's report survives only in git history. That is the structural reason nobody
noticed: there is exactly one baseline described at any time, and no per-image manifest.

**Azure metadata, read live** (`az image show`, 2026-08-30; subscription id redacted — this
document is public):

| | `clawfactory-win11-baseline` | `clawfactory-win11-baseline-v2` |
|---|---|---|
| Generation / state | V2 / Generalized | V2 / Generalized |
| Captured from | `bake-vm` | **`cfv-133`** |
| Tags | none | none |

`cfv-133` is a **validation-box name, not a purpose-built bake machine**, and it appears
nowhere else in this repository. `-v2` was captured from a VM provisioned from `-v1`, so it
inherits everything `-v1` did.

**What `clawfactory-win11-baseline` has already performed** — verbatim from its bake script:

```powershell
Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux -All -NoRestart
Enable-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -All -NoRestart
wsl --install --no-distribution --web-download
Add-MpPreference -ExclusionPath "C:\Program Files\ClawFactory"
Add-MpPreference -ExclusionPath "C:\ProgramData\ClawFactory"
Add-MpPreference -ExclusionPath "C:\Users\Public\Desktop\ClawFactory.lnk"
winget install Microsoft.PowerShell ... ; winget install Microsoft.VCRedist.2015+.x64 ...
```
then `Remove-Item C:\Windows\Panther`, `Stop-Service wuauserv`,
`Set-Service wuauserv -StartupType Disabled`, remove all removable AppX, then
`sysprep /generalize /shutdown /oobe /quiet /mode:vm`.

**And what the bake log actually confirms**, which is a different question:
`PASS: WSL=Enabled VMP=Enabled`; `## Task 5 — Reboot / PASS`;
`PRE_SYSPREP_CLEANUP_DONE (Panther cleaned, wuauserv disabled, AppX removed)`. The two
`winget` installs did **not** happen — `Note: winget not available in RunCommand context`.
The three Defender exclusions were attempted and **no result was ever recorded, on any run.**

**Therefore a box on `-v1` cannot measure:** feature enablement; any pending-reboot state
from feature enablement (the bake enabled *and then rebooted*); any pending reboot from
Windows Update (`wuauserv` disabled, so
`HKLM:\…\WindowsUpdate\Auto Update\RebootRequired` cannot be set — and that key is one of the
two secondary signals D1's design proposes to read); any Defender interaction with the
installer's three principal write targets, if those exclusions survived sysprep; anything
touching the Store appx surface.

**`-v2` adds one step:** `msiexec /i wsl.2.7.8.0.x64.msi /quiet /norestart` → exit 0, no
reboot required, then the same cleanup and sysprep verbatim. **Therefore it additionally
cannot measure** `Update-WslEngine` doing any work, or any engine-acquisition path. On these
boxes `wsl --update` says *"already installed"* and exits 0 without touching the engine or
any optional feature — which is precisely the call that, on the external machine, installed
the engine, enabled `VirtualMachinePlatform` and printed the reboot sentence.

**One thing the fleet does cover, and it should be said:** neither image has a distro, so
`wsl --import` of the bundled rootfs *is* exercised — the step that failed first externally.

**Three things have never been read back on any box** and the next cycle can settle all three
in one `az vm run-command` before the installer is copied: whether the Defender exclusions
survived sysprep; whether `wuauserv` is still disabled on a *provisioned* box; and whether
either image's `VirtualMachinePlatform` reads `Enabled` **today** (the claim rests on one
measurement on `cfv-133` in June and the bake script's own `RESULT:` line in May — both
strong, neither current).

### 6.3 The catalogue entry (4.3) — Class 14

`docs/FAILURE_CATALOGUE.md`, entry **14.1**, *"The bake performed the install step, then
generalized the evidence away."* It is its own class rather than an addition to 13: Class 1
is a control that tested nothing, Class 9 is a phase believed to have run that had not; this
is a phase that ran **correctly, once, as part of building the instrument**, after which the
instrument made it unrunnable. The results afterwards were not false — they were true answers
to a narrower question, and nothing in the record shows the question getting narrower.

Rules **24** and **25** were added to the numbered list at the end of the catalogue.

### 6.4 **The correction to entry 13.1, which is the third contradiction in this job**

13.1 and its close-out attribute the gap to `clawfactory-win11-baseline-v2` — the June
rebake — reasoning that *"the fix for the old bug created the new one, on the one path
nothing measured after that."* The prompt for this job repeats it.

**It is wrong, and it is wrong in the direction that makes the finding larger.**

`REPORT.md`'s own "Before" block, measured on `cfv-133` — a box built from the **original**
image — records:

> *Optional features `Microsoft-Windows-Subsystem-Linux` and `VirtualMachinePlatform` = **Enabled**.*

Four and a half weeks before `-v2` existed. And the v1 bake log records
`## Task 5 — Reboot / PASS`. So:

- The pending-reboot state has been unreachable since **2026-05-06**, not 2026-06-10.
- It is unreachable on **both** images. **Falling back to `-v1` would not have caught it.**
- `-v2` did not create the blind spot. It removed the last remaining first-run WSL step from
  a fleet that had already lost the feature-enablement step — which is also why the
  2026-05-21 run could still stumble into reboot-and-resume (via `wsl --install` exiting
  non-zero, not via a pending reboot) and no run after 2026-06-10 could.

The general lesson survives and sharpens: **the blindness arrived with the first bake, not
with the rebake that removed the friction.** Any image built by running install steps and
then generalizing has this property from version one. It does not creep in later.

### 6.5 Card `#259` is now higher priority than it was (4.4)

The pressure that produced `baseline-v2` was operational — twelve manual touches and roughly
25 hours per cycle — and **that pressure has not gone away.** The new preamble clause makes
every cycle strictly more expensive: it adds at least one stock-image box, and a stock-image
box is the *most* manual kind, because it is the one that reboots, and
`az vm run-command` runs as SYSTEM where WSL refuses to run, so a human has to log in over
RDP after every restart.

So the clause creates exactly the incentive that produced the problem. **The only durable
answer is `#259`, the unattended validation harness**, and it should be treated as a
prerequisite for the cycle after v1.4.5 rather than as a nice-to-have. Without it, the
predictable outcome is a future session baking `baseline-v3` with the reboot already taken,
for the same good operational reason, and this document being read afterwards.

---

## 7. Git, dispatch, and the setup.ps1 proof

### 7.1 Files changed

```
$ git status --short          # before staging
 M docs/FAILURE_CATALOGUE.md
 M docs/V1_5_BACKLOG.md
 M docs/VALIDATION_PREAMBLE.md
?? docs/reference/BASELINE_IMAGES.md
?? validation/census-exitcode-proof.ps1
```

| File | Change |
|---|---|
| `docs/VALIDATION_PREAMBLE.md` | new clause `A BASELINE IMAGE IS A SET OF INSTALL STEPS ALREADY COMPLETED` inside the paste block; `ENVIRONMENT` image line amended to defer to it |
| `docs/reference/BASELINE_IMAGES.md` | **new** — the per-image step records, what each bake log confirms vs attempts, what each image cannot measure, and the 13.1 correction |
| `docs/FAILURE_CATALOGUE.md` | new Class 14 / entry 14.1; rules 24 and 25 |
| `docs/V1_5_BACKLOG.md` | new `v1.4.5` section (WSL1 removal spec + the six in-scope census sites); item 7, the census findings marked v1.5 |
| `validation/census-exitcode-proof.ps1` | **new** — the census instrument, with its calibration record in the header |
| `docs/session_reports/2026-08-30_pre_v145_groundwork_closeout.md` | **new** — this file |

Explicit per-file staging, no `git add -A`, separate commits per logical change, **no tag**.

### 7.2 `setup.ps1` is unmodified at close — the evidence

```
$ sha256sum setup.ps1
26e1593db3351c961df6c9a43c08483e73111af7da48ccf1d94c8260420573b7 *setup.ps1

$ git show HEAD:setup.ps1 | sha256sum
26e1593db3351c961df6c9a43c08483e73111af7da48ccf1d94c8260420573b7 *-

$ git diff --stat HEAD -- setup.ps1
(no output)

$ git ls-files --eol setup.ps1
i/lf    w/lf    attr/-text      setup.ps1

bytes = 214311   (identical to the value recorded before the canaries were planted)
```

The worktree hash equals the committed blob hash, so the file is byte-identical to what
`HEAD` holds **and** the LF/CRLF question is answered rather than assumed. It was modified
twice during §3.4's calibration and restored twice by truncation to the recorded original
byte length; both restorations were proved by hash, not by `git status`, which was empty
throughout including while 1,144 bytes of canary were appended.

### 7.3 Dispatch

Both writes went through `POST /api/agent/update` with `x-frontier-secret` from PowerShell
(`python` is blocked by Windows Application Control), and both were **verified by re-reading
`GET /api/cards`**, not by trusting the write:

```
#316  status=done  comments=0  descLen=3633  tags=validation,v1.4.5,census,documentation
      "Pre-v1.4.5 groundwork: exit-code census (14 load-bearing), WSL1 removal spec,
       baseline-drift rule -- x-ref #315"

#315  status=todo  comments=1  descLen=3497   (comment_count 0 -> 1)
      "PRODUCT SHIP-BLOCKER: first external install of v1.4.4 failed; 5 defects traced,
       fix designed, reproduction blocked on one operator action"
```

`#315` is left at **`todo`, deliberately** — it is blocked on the external machine's
`install.log`, not on anything this session could do. The comment added to it carries both
corrections from §5.4 and §6.4 and restates what is still blocked, so the next reader of that
card sees the corrections without needing this document.

---

## 8. What is owed next

1. **The two artefacts from the external machine** — `C:\ProgramData\ClawFactory\install.log`
   and the Task Manager virtualization reading. Unchanged from the prior close-out; the log
   is free and probably decisive on its own. **D1 cannot be built until it arrives.**
2. **The reproduction**, `validation/interim-v145-pendingreboot.ps1`, still blocked on one
   operator action (the admin password at provisioning).
3. **The v1.4.5 build**, scoped in `docs/V1_5_BACKLOG.md` § *v1.4.5*: D2, D3, D4, D5, the
   WSL1 removal and `setup.ps1:850`, with D1 conditional on item 1.
4. **The three unread-back baseline facts** in §6.2, settleable in one `az vm run-command` on
   the first box of the next cycle.
5. **Card `#259`, the unattended harness** — reprioritised, §6.5.
6. **`OM-1` in `docs/VALIDATION_PREAMBLE.md` remains open.** This session provisioned no box
   and did not take the `:8787` measurement. The entry stands.
7. **One gap in this census, named rather than hidden:** the Inno `[Code]` section of
   `ClawFactory-Secure-Setup.iss` was not covered. It is a different language with its own
   `Exec()` result convention, and `Exec()`'s `ResultCode` out-parameter is exactly the shape
   this census exists to find. It deserves its own pass.

---

## 9. ADDENDUM — the external machine's artefacts arrived, and settle it

**Added later on 2026-08-30, after this job's tasks were complete.** Jason sent four files.
Read directly from `C:\Users\bmcki\Downloads\`, not from anyone's summary of them:

| File | Bytes | sha256 (first 16) |
|---|---|---|
| `install.log` | 5,045 | `abdd5575963d8ea1` |
| `checkpoint.json` | 101 | `95b77638ce07dc5e` |
| `install-result.txt` | 76 | `d901ca2a7b1bdc5c` |
| `wsl-state.txt` | 8 | `426e1dd405b288e3` |

**The log exists.** §8's item 1 and the prior close-out both treated it as possibly lost. It was
in `C:\ProgramData\ClawFactory` the whole time; `C:\ProgramData` is hidden in Explorer by
default. The code argument that it *must* exist — `Write-Log` writes the file before the console
under `$ErrorActionPreference='Stop'` — held.

### 9.1 The four claims put to me, each checked against the file

**All four verified.**

1. **The import failed with `HCS_E_SERVICE_NOT_AVAILABLE`.** Confirmed, and the line above it is
   more direct still:
   ```
   [wsl --import v2] The operation could not be started because a required feature is not installed.
   [wsl --import v2] Error code: Wsl/Service/RegisterDistro/CreateVm/HCS/HCS_E_SERVICE_NOT_AVAILABLE
   ```
   The Host Compute Service was not running — the state a pending reboot leaves behind.

2. **`wsl --install` printed the contradiction and returned 0.** Confirmed, and the two lines are
   adjacent in the file:
   ```
   [wsl install out] The requested operation is successful. Changes will not be effective until the system is rebooted.
   [2026-08-30 11:11:18] [INFO] WSL2 install succeeded.
   ```
   **D2 caught in the act.** The sentence that refutes the claim is the line immediately above the
   claim. It was captured to disk by `setup.ps1:498-501` and read by nothing.

3. **`WSL_E_DISTRO_NOT_FOUND` proves no distro was created.** Confirmed.

4. **Forty-one minutes.** Confirmed: failure at `11:11:19`, rollback answered at `11:52:37`.
   41 minutes 18 seconds.

### 9.2 What the log adds beyond what was asked

**A. `PR.C1` is answered, and the reproduction is redundant.** At `11:11:18` the log reads
`WSL2 kernel loaded but Ubuntu missing - installing Ubuntu only.` That string is inside the
`if ($kernelOk)` branch at `setup.ps1:924`, and `$kernelOk` is set at `923` from
`wsl --status`'s exit code. **So `wsl --status` exits 0 while `VirtualMachinePlatform` is
`EnablePending`.** That is `PR.C1`, the single row the entire reproduction was designed to
measure, answered from the field rather than from a rig. `cfv-183` was torn down on that basis —
VM, NIC, public IP, NSG and OS disk, verified by re-reading the group, back to the four-resource
residual.

**B. D1 is confirmed from the artefact rather than inferred.** `wsl --update`'s captured output
contains, verbatim:

> `Installing Windows optional component: VirtualMachinePlatform | The requested operation is successful. Changes will not be effective until the system is rebooted.`

Captured at `setup.ps1:256`, normalised at `263`, written to the log at `264`, and never
referenced again. The installer recorded the reason it was about to fail, in English, one second
before it failed.

**C. D3's preflight bit is a measured false positive, and this settles the gate question.**
The WARN fired at `11:09:53` — and Task Manager on that machine reads **Enabled**. So
`Win32_Processor.VirtualizationFirmwareEnabled` read falsey on a machine where hardware
virtualization is on and working. **Had that check been a hard gate, it would have refused to
install on a perfectly capable computer.** §4.3 of the prior close-out argued against gating on
it from first principles; it is now argued against from a measurement, on the only machine that
has ever exercised it.

**D. New defect — D8. The most valuable diagnostic line in the file is nearly unreadable.**

```
[wsl:root out] T h e r e   i s   n o   d i s t r i b u t i o n   w i t h   t h e   s u p p l i e d   n a m e .
```

`Update-WslEngine` strips `wsl.exe`'s UTF-16LE null bytes at `setup.ps1:263`. `Invoke-WslBash`'s
`[wsl:root out]` / `[wsl:root err]` path (`setup.ps1:765-772`) does not. The nulls also make
`grep` classify `install.log` as a **binary file**, which silently suppresses matches — it
suppressed one of mine while checking the rootfs digest, and would suppress a support engineer's.
The fix is the same null-strip that line 263 already performs.

**E. The digest gate worked, and it is the one thing that did.** The logged rootfs hash
`1483cc5c…4109` is 64 characters, equals the pin at `setup.ps1:467`, and equals `sha256sum` of
`resources/ubuntu-rootfs.tar.gz` in this repository. Recorded because a failure report should say
what held as well as what broke.

**F. `setup.ps1:850`'s destructive default did not fire here.** The `wsl --list` took the full 60
seconds (`11:09:53` → `11:10:53`) but *succeeded*, so `distroExistedPreInstall=False` was recorded
truthfully and `wsl-state.txt` reads `false` correctly. The census finding at §3.2 stands as a
latent risk rather than as something that bit — which is the right way to record it.

**G. `checkpoint.json` confirms §9.3's rollback analysis with no inference:**

```json
{ "completedSteps": [ "Preflight" ] }
```

### 9.3 Two further defects, from the failure path rather than the diagnosis

**D6 — `Invoke-Rollback` announces work it has no mechanism to do.** `setup.ps1` contains **31
distinct `Save-Checkpoint` names**. `Invoke-Rollback` has **2** cases, `FirewallRule` and
`EnsureWsl`; the other 29 fall to `default { }`. This install completed only `Preflight`, so
answering `Y` to *"Installation failed. Run automatic rollback? (y/N)"* produced exactly this and
nothing else:

```
[2026-08-30 11:52:37] [ERROR] Running rollback for completed steps...
[2026-08-30 11:52:37] [INFO] Undoing: Preflight
```

**It logged that it was undoing a step and undid nothing, because there is no case for that step.**
Class 2, on a user-facing prompt. `C:\Program Files\ClawFactory` remaining populated is separately
*correct* — Inno owns that directory and only its uninstaller removes it, and nothing in
`setup.ps1` should — but the prompt implies otherwise and the user reasonably concluded the
rollback was broken.

**D7 — accepting the rollback is the one path that never tells you where the log is.**
`Invoke-WithRollback` prints the log path only in the `else` branch:
`Write-Log INFO "Rollback skipped. Log: $LogFile"`. He accepted, so he was never shown it.
Combined with `Failed to pre-create clawuser stub (exit=-1)`, which names neither a cause nor a
file, **the failure path told him nothing he could act on.**

**And the number that belongs next to D7: forty-one minutes.** That is how long a real person sat
in front of an error message about a Linux user account before deciding what to do. It is the only
measurement this project has of what a bad error message actually costs, and it should be quoted
whenever the cost of clear failure text is weighed against the effort of writing it.

### 9.4 What this changes

- **Root cause: pending reboot. Confirmed, not inferred.** BIOS is ruled out by the Task Manager
  reading, and the firmware bit that suggested it is a measured false positive (C).
- **D1 is unblocked and specifiable now.** The condition it must detect is exactly the state the
  log records, and `PR.C1` — the assumption D1's design turned on — is answered.
- **The reproduction is closed as redundant**, not skipped. `cfv-183` is gone and the resource
  group is back to its four-resource residual.
- **D6, D7 and D8 are new** and are added to `docs/V1_5_BACKLOG.md` § *v1.4.5*.
- **No build was started.** `setup.ps1` remains untouched; §7.2's evidence still holds at close.
