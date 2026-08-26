# CLOSE-OUT: v1.4.2 uninstaller fixes, built and signed

Session 2026-08-26. Cards `#284`, `#285`, `#286`, `#287`, plus the dialog-copy
contradiction. No VM, no validation run, no tag, no GitHub release, no publish.

**STATUS: COMPLETE. All ten tasks done.** The v1.4.1 fitness verdict was NO for one
measured reason: the keep-Linux uninstall branch tells the user they can reinstall later,
and a reinstall on that branch was measured to abort. That branch is fixed.

**The cause of `#284` WAS established, and reproduced with a control.** It is not a
plausible fix to a silent truncation. Section 3 states it in one checkable sentence.

**The mandated dependency census found a second live site the prompt did not know about**
(`resources/launcher.ps1`), carrying the identical defect in a worse position. Section 4.

**No fitness-to-publish verdict is written here.** This build is unvalidated and any
fitness statement would rest on an unmeasured premise.

---

## 0. PROMPT 15 preamble

Read in full from `C:\Users\bmcki\OneDrive\Desktop\Claude Prompts\FrontierAI_CC_Prompt_Library.md`.
**PROMPT 15 is present at line 645 of 925; the library is NOT stale.**

Clauses deleted as provably inapplicable, and why:

| Clause | Why deleted |
| --- | --- |
| ENVIRONMENT, NOT NEGOTIABLE | No VM was provisioned. Every `az` clause has no subject. |
| HUMAN HANDOFF CARDS | No point in this job needs a human. Nothing was staged for an operator. |
| RESOURCE LEDGER (Azure half) | No VM, no disk, no NIC, no pip, no NSG, no licence slot. The non-Azure half is honoured in section 11. |
| MEASUREMENT DISCIPLINE (phase-runner half) | `interim-v120-phaselib.ps1` drives on-VM phases. The rigs here run on the build machine. The *rules* it enforces were applied by hand and are shown firing throughout. |

Everything else applies and was followed: pre-flight, challenge-the-prompt, calibrate before
measuring, controls that must fail, audit-regex canaries, credential hygiene, git, close-out
as a gate.

---

## 1. Task accounting

| Task | State |
| --- | --- |
| PROMPT 15 preamble | **DONE** — read in full, present at line 645, four clauses deleted with reasons above |
| 1.1 Establish intended behaviour from the code, enumerate the class | **DONE** — 10 surfaces, section 2 |
| 1.2 State plainly which is wrong | **DONE** — both, separably, section 2.2 |
| 1.3 Report before changing | **DONE** — reported in-session before the first edit |
| 2 Pre-flight, all four | **DONE** — section 12; the census is what changed the job |
| 2 `git status --short` both repos | **DONE** — both clean, nothing unpushed at start |
| 3.1 Capture output and exit code, log a failure as a failure | **DONE** — section 5 |
| 3.2 Decide what an uninstall does when teardown fails | **DONE** — recommendation given and implemented, section 5.2 |
| 3.3 Do `#286` before `#284` | **DONE** — and it did not name the cause; the digest comparison did |
| 4.1 Reproduce and read what the teardown returns | **DONE** — three rigs, section 3 |
| 4.2 Explain the boundary specifically | **DONE** — the mechanism explains it exactly, section 3.3 |
| 4.3 Fix it, one checkable sentence | **DONE** — section 3.1 |
| 4.4 Say so if the cause is not established | **N/A** — it was established and reproduced |
| 5.1 `XDG_RUNTIME_DIR`, both lines side by side | **DONE** — section 6.1 |
| 5.2 Verify processes gone before `deluser` | **DONE** — section 6.2 |
| 5.3 Do not swallow under `2>/dev/null` | **DONE** — redirect removed |
| 6.1 Installer-derived enumeration, count vs teardown | **DONE** — section 7, gap = 6 units and 5 helpers |
| 6.2 Disable before deleting, consistently | **DONE** — all 11, section 7.3 |
| 6.3 Audit the enumeration with a canary | **DONE** — canary found, then removed, file byte-identical |
| 7.1 Apply the TASK 1 conclusion | **DONE** — section 8 |
| 7.2 State the reinstall expectation, labelled | **DONE** — INFERRED, section 8.2 |
| 7.3 Fix the 8.4 wrapping defect | **DONE** — one logical line per paragraph |
| 8 RemoveAll impact per change | **DONE** — section 9 |
| 9 Version, build, sign, ledger | **DONE** — section 10 |
| 10.1 Commits, both repos pushed, no tag | **DONE** — section 11.1 |
| 10.2 Cards to the state the evidence supports | **DONE** — all four to `Review`, not `done` |
| 10.3 Close-out, committed, printed in full | **DONE** — this file |
| 10.4 End-of-session gate | **DONE** — section 11 |

---

## 2. TASK 1: the contradiction

### 2.1 What the code intends, from the code

The keep-Linux switch's own contract, `resources/uninstall.ps1:9-11` as it stood before this
session:

```
    # Explicit opt-out of distro removal. Useful for /REMOVEALL=0 silent
    # uninstall (e.g. an IT pilot deploy where the Ubuntu image is shared
    # with other tooling).
    [switch]$KeepLinuxEnvironment
```

The stated purpose is **distro sharing**, not data retention. And the branch body contains no
preservation path whatsoever — every removal is unconditional:

```
rm -rf /usr/local/lib/clawfactory /var/lib/clawfactory 2>/dev/null
rm -rf /etc/clawfactory 2>/dev/null
rm -rf /usr/lib/node_modules/openclaw 2>/dev/null
deluser --remove-home clawuser 2>/dev/null
```

**The class of surfaces, enumerated rather than sampled** — a tree-wide sweep of every `.md`,
`.html`, `.iss` and `.ps1` for uninstall claims, excluding session reports and validation runs:

| Surface | Claim | True of the code? |
| --- | --- | --- |
| `resources/uninstall.ps1:9-11` param contract | opt out of **distro** removal, for a shared image | **yes** |
| `resources/uninstall.ps1:91` dialog | "agent configs stay on disk" | **NO** — `deluser --remove-home clawuser` |
| `resources/uninstall.ps1:91` dialog | "Your conversation history … stay[s] on disk" | true, but true of **both** branches — it is Windows-side `%APPDATA%\ClawChat`, which neither branch touches, so presenting it as a NO-branch benefit misleads |
| `resources/uninstall.ps1:92-93` dialog | "You can re-install ClawFactory later and reuse the existing distro" | intended yes, **measured NO** on cfv-176 |
| `resources/uninstall.ps1:439` log line | "In-distro ClawFactory artifacts removed" | **NO** — asserted unconditionally |
| `setup.ps1:841-843` comment | "The checkbox in the uninstall UI remains the authority" | yes |
| `docs/index.html:931` site FAQ | ClawChat history "is not deleted automatically — remove that folder manually" | **yes**, consistent; no change needed |
| `SUPPORT_MATRIX.md:47` | the YES branch unregisters the distro "including all chat history and credentials" | **yes** |
| `CHANGELOG.md:175` | 9-step reversal | yes |
| `README.md`, `SECURITY.md`, `SECURITY_FINDINGS.md` | **no uninstall claims at all** | n/a |

Confirmed by execution that neither branch touches the Windows-side history:

```
$ grep -rn "ClawChat" resources/uninstall.ps1 ClawFactory-Secure-Setup.iss | grep -i "del|remove|APPDATA"
(no output)
```

### 2.2 Which was wrong

**Both, and they are separable. I am not picking the convenient one.**

- **The copy was wrong about agent data.** The code has one coherent intent, stated in its own
  contract and implemented without exception: keep the distro *shell*, remove ClawFactory
  entirely from inside it. The dialog's data-retention promise had nothing behind it. → copy fix.
- **The code was wrong about the reinstall promise.** That claim is supposed to be true, and
  would have been if the teardown had completed. → code fix, `#284` + `#287`.

TASK 4's scope was therefore unchanged, and the job proceeded as written.

---

## 3. TASK 4: `#284`, the mechanism

### 3.1 The one checkable sentence

> **The shipped `uninstall.ps1` was CRLF on the build machine, so every line of the teardown
> reached bash inside WSL ending in a carriage return; running as root the CR lands only on
> each line's last word — always the `2>/dev/null` redirect target, which root can create — so
> every *simple* command still ran correctly, but the first line needing a *reserved* word,
> `if [ -f … ]; then`, saw `then␍` instead of `then`, and bash abandoned the remainder of the
> script with a syntax error.**

Anyone can check it: `printf 'echo A\r\nif true; then\r\n echo B\r\nfi\r\n' | bash`.

### 3.2 Why the rig disagreed with production, established by digest

The close-out for cfv-176 recorded the extracted script as `sha256 3ded3520c217ad…`. Extracting
the same here-string byte-exactly through the PowerShell AST:

```
SHIPPED-AS-PARSED: len=5428 CR=74 LF=74
sha256(UTF8 bytes) = 78bad2971052b715a5ad56c3c4004bdaad36953624dc0a93558bb6c2ae417995
LF-NORMALISED    : len=5354 sha256 = a9c097804c517343d1990db8db939ac101b8b66a59c9f76bb83a5afadf826702
LF + trailing LF : 5355 bytes  sha256 = 3ded3520c217ad6787d6fde3983811d8b18d2848a47626c097bf3e134e7bf155
```

**`3ded3520…` is the LF form.** The rig normalised the line endings on the way out — `sed`/
`Get-Content` on Windows both do — and therefore ran a script that production never ran. That
is the entire difference between "the script is correct" and "the script was cut short".

The state that produced it, measured:

```
$ git ls-files --eol resources/uninstall.ps1
i/lf    w/crlf  attr/text eol=lf      resources/uninstall.ps1

worktree : 25961 bytes  LF=466  CR=466      <- what Inno compiles
HEAD blob: 25495 bytes  LF=466  CR=0        <- what is committed
```

`git status` was clean throughout, because `text eol=lf` makes git normalise on *comparison*.
The rule was added after this file was first checked out, and **git never re-normalises an
existing working copy**. So the repo was right, the commit was right, and the bytes Inno
bundled were wrong — invisibly.

### 3.3 Reproduced, with a control, before the fix was written

Production shape, driven through the identical invocation
`wsl.exe -d Ubuntu -u root -- bash -lc "echo <b64> | base64 -d | bash"`:

```
=== MODE=ctl-lf    bytes=393 CR=0  (root) ===
invocation exit code: 0
MARKERS PRESENT: MARK_A_SIMPLE,MARK_B_SIMPLE_REDIR,MARK_C_LAST_BEFORE_IF,MARK_D_INSIDE_IF,MARK_E_AFTER_IF,MARK_F_TERMINAL_OK

=== MODE=subj-crlf bytes=403 CR=10 (root) ===
invocation exit code: 2
STDERR> bash: line 1: set: +
STDERR> : invalid option
STDERR> bash: line 11: syntax error: unexpected end of file
MARKERS PRESENT: MARK_A_SIMPLE,MARK_B_SIMPLE_REDIR,MARK_C_LAST_BEFORE_IF

COUNT of /dev/null<CR> BEFORE cleanup (expect 1): 1     <- root CAN create it; that is why the first half runs
COUNT of /dev/null<CR> AFTER  cleanup (expect 0): 0
real /dev/null after cleanup: CHARDEV_INTACT

CTL.LF   : all 6 markers present           = True   (MUST be True)
SUBJ.CRLF: simple commands before first if = True   (expected True)
SUBJ.CRLF: anything from the if onward ran = False  (expected False)
RIG VERDICT: PASS
```

And on the **real payload**, not a synthetic one, with a discriminating control:

```
=== payload_lf.sh ===
  SYNTAX_OK
=== payload_crlf.sh ===
  SYNTAX_FAIL
  /var/tmp/cfsyn2-crlf.sh: line 59: syntax error near unexpected token `$'do\r''
```

**Two of my own hypotheses were wrong along the way and are recorded rather than deleted.** The
first rig ran unprivileged and produced *zero* markers, refuting "CRLF only breaks reserved
words": unprivileged, `2>/dev/null␍` is a permission-denied redirect and the command never runs
at all. The second rig held its output path in a shell variable, so the CR landed inside the
*filename* and no marker was findable — a rig defect, not a finding. Production has no such
variable; every path is a literal mid-line. Only the third rig had production's shape.

### 3.4 The boundary this explains, exactly

`set +e` cannot rescue it: a parse error is fatal regardless, and `set +e␍` had itself already
failed as an invalid option. The split matches the cfv-176 measurements line for line:

| Measured on cfv-176 | Explained by |
| --- | --- |
| `UN.K.3h FAIL … clawfactory-* counted 12` (before: 14) | exactly the 2 unit files named *before* the first `if` were removed |
| `UN.K.3f FAIL … /usr/local/sbin/clawfactory-* counted 7` (before: 17) | exactly the 10 helpers named before the first `if` |
| `TR.3 FAIL enabled before=6 after=4` | the 2 the second half would have disabled |
| `UN.K.3g` / `UN.K.3j` FAIL | `/etc/clawfactory` and `/usr/bin/openclaw` are both after the first `if` |

### 3.5 The fix

LF-normalise before transport — which is what **every other** PowerShell→WSL transport in this
product already did. Correctness no longer depends on any clone's line endings, and a CR
surviving normalisation is asserted rather than assumed. Both files were also rewritten to LF
on disk so the bundled bytes match the reviewed bytes:

```
resources\uninstall.ps1      CR before=655   CR after=0
resources\launcher.ps1       CR before=250   CR after=0
git ls-files --eol  ->  i/lf  w/lf   (both)
```

---

## 4. The second site the census found

PROMPT 15 requires a dependency census whenever something is removed or gated: *enumerate EVERY
site the thing appears, tree-wide*. Run over every PowerShell→WSL bash transport:

```
NORMALISES CR:  bootstrap.ps1:50,158   post-install.ps1:41   switch-provider.ps1:104
                clawfactory-grants.ps1:55   setup.ps1:673   + all six $lfB64 lambdas
DOES NOT:       resources/uninstall.ps1:441      <- card #284
                resources/launcher.ps1:124       <- NOT IN THE PROMPT
```

`launcher.ps1` is worse in one respect: the single payload it is ever handed opens with

```
if curl -fsS --max-time 2 http://127.0.0.1:8787/status >/dev/null 2>&1; then
```

so on a CRLF build it died on its **first** line rather than half way through, and the
gateway-start fallback started nothing — invisibly, because both streams are read into `$null`.
In practice the gateway is normally already up via systemd and the keep-alive task, so this is a
fallback that was never observed to be needed.

**Fixed here rather than carded**, because leaving it is precisely the failure mode `#285`
records: applying a fix to one member of a class and not its siblings. It is the only change in
v1.4.2 that touches the install/run path, and section 9 names what validation owes it.

---

## 5. TASK 3: `#286`, the defect that hid the others

### 5.1 What it was

```
$null = & wsl.exe -d Ubuntu -u root -- bash -lc "echo $enc | base64 -d | bash" 2>&1
Write-Log INFO 'In-distro ClawFactory artifacts removed; Ubuntu distro left registered.'
```

Output discarded, exit code never read, success asserted on the next line. The
`syntax error: unexpected end of file` that would have named `#284` in one line went into
`$null`.

### 5.2 The decision, and the recommendation behind it

**Bret's view was: complete the uninstall, log the failure loudly, and tell the user in the UI
what was left behind and how to remove it. I agree and implemented exactly that.** The repo does
not disagree: `uninstall.ps1`'s own header already states the principle —

```
# Exit codes are advisory only; Inno proceeds with its own file/icon
# cleanup regardless. We always exit 0 unless something fundamentally
# unexpected happens.
```

An uninstall that **aborts** leaves the user unable to remove the product, which is worse than an
incomplete removal. An uninstall that **reports success having removed nothing** is what shipped.
The third option is the only defensible one.

Implemented: output and exit code captured, every line logged with an `[in-distro]` prefix, the
teardown prints a `READBACK` line and a terminal marker, and the caller **requires** the marker
rather than assuming it. On failure the Windows side still completes, `Write-Log ERROR` fires,
and a MessageBox tells the user what remains and gives them the exact command.

### 5.3 What the teardown now reports

```
[uninstall] READBACK units=$N_UNITS sbin=$N_SBIN enabled=$N_ENABLED left=[$LEFT ]
CLAWFACTORY_TEARDOWN_OK        (or CLAWFACTORY_TEARDOWN_INCOMPLETE)
```

Enablement is counted from `.wants` symlinks on disk rather than from `systemctl list-unit-files`,
so a systemctl that cannot run reads as an error instead of silently reading as zero.

---

## 6. TASK 5: `#287`

### 6.1 The two lines, side by side

```
BEFORE, the gateway stop (teardown line 1):
    sudo -u clawuser bash -c 'systemctl --user stop openclaw-gateway 2>/dev/null; ...' 2>/dev/null

ALREADY CORRECT, fifteen lines below, in the same script:
    sudo -u clawuser XDG_RUNTIME_DIR=/run/user/1000 systemctl --user daemon-reload 2>/dev/null

AFTER:
    sudo -u clawuser XDG_RUNTIME_DIR=/run/user/1000 systemctl --user stop openclaw-gateway
    sudo -u clawuser XDG_RUNTIME_DIR=/run/user/1000 systemctl --user disable openclaw-gateway
```

The `2>/dev/null` is gone. That redirect is why a two-line defect survived to a release.

### 6.2 Stopping the gateway can still fail for other reasons

So the teardown now verifies rather than hopes, escalates once, re-verifies, and reports:

```
CF_PROCS=$(pgrep -u clawuser 2>/dev/null | wc -l)
if [ "$CF_PROCS" != "0" ]; then
    echo "[uninstall] clawuser still owns $CF_PROCS process(es) after the gateway stop; terminating them"
    pkill -u clawuser 2>/dev/null
    ... bounded poll on STATE, then pkill -KILL, then poll again ...
fi
if [ "$CF_PROCS" != "0" ]; then
    echo "[uninstall] ERROR: clawuser still owns $CF_PROCS process(es); deluser is expected to fail with exit 8" >&2
fi
# NOT 2>/dev/null.
deluser --remove-home clawuser
```

`pgrep -c` was deliberately **not** used: it prints `0` *and* exits 1 when there is no match, so
`$(pgrep -c … || echo 0)` yields the two-line string `"0\n0"` and the test reads it as non-zero —
a false alarm on the healthy path. `pgrep … | wc -l` always prints one number and exits 0.

---

## 7. TASK 6: the installer-derived enumeration

### 7.1 Method, deliberately prefix-agnostic

Union of three methods over `setup.ps1` and `resources/install-*.sh`, none anchored on the string
`clawfactory-`: literal destinations under `/etc/systemd/system/`, arguments to
`systemctl enable`, and the literal lists in `for u in …` loops that install units by variable
name.

### 7.2 The comparison, which is the deliverable

```
INSTALLER CREATES (11)                      NAMED BY THE v1.4.1 TEARDOWN (5)
  clawfactory-allow-providers.service         clawfactory-egress-refresh.service
  clawfactory-allow-providers.timer           clawfactory-proxy.service
  clawfactory-egress-refresh.service          clawfactory-quarantine-gc.service
  clawfactory-fw.service                      clawfactory-quarantine-gc.timer
  clawfactory-proxy.service                   clawfactory-quarantine.service
  clawfactory-quarantine-gc.service
  clawfactory-quarantine-gc.timer           GAP = 6
  clawfactory-quarantine.service
  clawfactory-send-gc.service
  clawfactory-send-gc.timer
  clawfactory-send.service
```

Plus `/etc/systemd/system/clawfactory-allow-providers.service.d/10-guard2-assert.conf`, a
drop-in directory the teardown never named at all.

Helpers: **the installer creates 17 files under `/usr/local/sbin`; the teardown named 12.** The
five that survived every uninstall: `clawfactory-allow-providers.sh`, `clawfactory-fw-assert.sh`,
`clawfactory-sendctl`, `clawfactory-sendctl.js`, `clawfactory-sendd.js` — plus
`/usr/local/bin/clawfactory-send`.

**The enumeration cross-validates against the cfv-176 measurement exactly:** the held
before-snapshot recorded `SBIN_CLAWFACTORY_COUNT=17`, and the installer-derived count is 17.

**And it resolves the one number that did not reconcile.** cfv-176 recorded
`UNIT_FILES_CLAWFACTORY=14` against my 11. Measured on a live install rather than reasoned about:

```
$ ls -1 /etc/systemd/system/clawfactory-* | xargs -n1 basename | sort
10-guard2-assert.conf
clawfactory-allow-providers.service
clawfactory-allow-providers.service.d:      <- ls expands the DIRECTORY and lists its contents
clawfactory-allow-providers.timer
...
count: 13
```

`ls` on a glob that matches a directory lists what is *inside* it. The 14 was 11 units plus the
`.d` directory header, its one `.conf`, and the blank separator line. (This local install is an
older build — no `clawfactory-egress-refresh.service`, 12 sbin helpers — so it corroborates the
mechanism and the shape, not the v1.4.1 baseline.)

### 7.3 6.2: disable before deleting, for all eleven or for none

v1.4.1 added the egress-refresh disable specifically so systemd would not be left with an enabled
unit pointing at a deleted script, then deleted `clawfactory-fw.service`'s script while leaving
that unit enabled — measured `enabled` with `active=failed`. The teardown now disables and stops
**all eleven up front**, and only then removes unit files, drop-ins and the scripts they invoke.

Batch form validated rather than assumed, because a batch that aborts on the first missing unit
would reintroduce exactly this defect on a partial install:

```
CTL_BEFORE_enabled=enabled     (control: the rig can produce a known-correct 'enabled')
batch exit=5
  OUT> Removed /etc/systemd/system/multi-user.target.wants/cfrigunit-present.service.
  OUT> Failed to stop cfrigunit-absent.service: Unit cfrigunit-absent.service not loaded.
SUBJ_AFTER_enabled=disabled    (the present unit IS disabled despite the missing one listed first)
CLEANUP_units_left=0  wants_left=0
```

One further ordering consequence, checked rather than assumed: step 1 now stops the quarantine
broker *before* the teardown's many `rm` calls, and `rm` is Guard 1's diverted node wrapper.
`resources/clawfactory-quarantine-rm.js` settles it — *"ROOT PASSES THROUGH, ALWAYS AND FIRST … the
system cannot be bricked by a broker outage."* The teardown runs as root, so `rm` never touches
the socket.

### 7.4 6.3: the enumeration was canaried

Shaped like what I feared missing rather than like what I knew was there — a unit with a
**different prefix**, a **`.socket`** (a type not present anywhere), installed through the
**variable-name loop** rather than by a literal path:

```
=== BASELINE ===                     COUNT=11
=== WITH CANARY (ocwarden-relay.socket injected into install-send.sh's for-loop) ===
  ... 11 units ...
  ocwarden-relay.socket
  CANARY FOUND = True
=== REMOVE CANARY ===
  canary still referenced: 0 (must be 0)
  file restored byte-identical to HEAD: True
```

---

## 8. TASK 7: the dialog

### 8.1 The new copy

```
Also remove the Ubuntu Linux distro that ClawFactory created?

ClawFactory is removed from this machine either way: the agent, its configuration and plugins, clawuser's home directory, the OpenClaw runtime, and every ClawFactory service and firewall rule.

YES also unregisters the Ubuntu distro and deletes its disk image (about 6 GB). Choose this unless something else on this machine uses that distro.

NO leaves the now-empty Ubuntu distro registered, so anything else that shares it keeps working. You can install ClawFactory again later and it will reuse the distro.

Your ClawChat conversation history is stored on Windows, under %APPDATA%\ClawChat, and neither choice deletes it.
```

Every claim is now true of the code after sections 3, 6 and 7. **Deviation 8.4 is fixed by
removing the defect class rather than re-tuning it:** each paragraph is a single logical line and
`MessageBox` does its own wrapping, so no hard break can land mid-sentence. The param contract
comment was extended to say the same thing in the code.

### 8.2 The reinstall promise — INFERRED

**I cannot measure this here; there is no box.** So, labelled in the sentence that makes the
claim: **INFERRED** — after these fixes a keep-Linux uninstall should complete, remove `clawuser`,
and leave a reinstall able to create it, because the truncation that stopped the teardown before
`deluser` is fixed structurally, the gateway stop that made `deluser` exit 8 now carries
`XDG_RUNTIME_DIR`, and the surviving processes are verified gone before `deluser` runs. That is an
argument from three fixed causes, not a measurement.

**This is the specific thing the validation job must prove:** install → keep-Linux uninstall →
verify the distro is clean by read-back → **reinstall, and confirm it completes**.

---

## 9. TASK 8: the branch that already passes

RemoveAll passed 16 of 16 on cfv-176 and is the default for both `/SILENT` and the dialog's
default button. Per change:

| Change | Touches RemoveAll? |
| --- | --- |
| Dialog copy rewrite | **YES** — the dialog chooses the branch |
| Param contract comment | no (comment only) |
| `XDG_RUNTIME_DIR` gateway stop (`#287`) | no — inside the `else` |
| Unit disable block, unit-file + helper removal (`#285`) | no — inside the `else` |
| `deluser` process guard (`#287`) | no — inside the `else` |
| Read-back + terminal marker (`#286`) | no — inside the `else` |
| LF-normalise the transport (`#284`) | no — inside the `else` |
| Incomplete-teardown MessageBox | no — inside the `else` |
| `launcher.ps1` normalisation | **YES**, but the install/run path, not uninstall at all |
| Version bump | both, cosmetically |

**Failure-mode walk on the dialog — what breaks if it works exactly as specified?** It is now
honestly framed as a question about the *distro* rather than about *data*, which is likely to send
**more** users down the NO branch. That is the correct outcome and also the reason the copy could
not be fixed on its own: fixing it in a release without `#284`/`#285`/`#287` would have increased
traffic onto the broken branch. The Yes/No polarity is unchanged (Yes = RemoveAll) and
`MessageBoxDefaultButton::Button1` is unchanged, so the default button and the silent default still
select the same branch. The residual risk is cosmetic: longer paragraphs make a wider dialog, and
nobody has yet seen it rendered.

**What the validation job must re-run on RemoveAll as a result:**

1. The full RemoveAll uninstall, all 16 rows — the dialog that selects it changed.
2. `Resolved DoRemoveAll = True` for `/SILENT` **and** for the dialog's default button.
3. The rendered dialog, read on screen: no mid-sentence wrap, dialog not wider than the screen,
   Yes still the default.
4. `PIN.version` reports **1.4.2**.
5. **New, from section 4:** the Start Menu launcher on a box where the gateway is down — this is
   the one change that alters install/run behaviour, from "silently does nothing" to "starts the
   gateway".

---

## 10. TASK 9: version, build, sign, ledger

### 10.1 Version

Two sites, the only two that carry it: `ClawFactory-Secure-Setup.iss:9` and `setup.ps1:56`.
`setup.ps1` carries `-text diff` — its bytes are protected from EOL renormalisation because a SOUL
digest is baked into it — so it was edited byte-exactly:

```
occurrences of the version line: 1 (must be 1)
bytes before=214311 after=214311 delta=0 (must be 0)
CR count now: 0 (must be 0)
parse errors: 0
line 56 now: $InstallerVersion      = '1.4.2'
```

### 10.2 Studio: UNCHANGED

No commit was made in the Studio repo this session. It is clean at `9282c42` and in sync with
`origin/main`. **Studio stays at 1.3.2**, the `#define StudioInstaller` pin is unchanged, and the
by-hand checklist's quoted version strings stay as they are.

### 10.3 Every build gate, by name, with its verdict

```
SOUL pin OK:            e70212603f2f91e6abf6db576c9535b1aaad60506e2fb075c199f18160db7941
Bundle check OK:        all 34 preflight resources are in [Files].
Studio pin OK:          ac5937516e7edbb5aac00433bfa6e5074449cbc28b132883099391639e1e7dca
Version OK:             1.4.2 (.iss and setup.ps1 agree)
Ledger OK:              released-versions.tsv carries 9 prior artifact row(s).
Persona pin OK:         0557d07004d4d067d8cd9e7cee7b2a3a783e0ac8ff4c492c0c152d7e35ff63a0
Workspace SOUL pin OK:  441b6279f6613c313e87e9e9e034f97a220540cddbf1cf738bb9a86c37a5a257 (6677 bytes composed)
Rootfs pin OK:          1483cc5c1dce13064f774834cbffdff226559fd522a67a381a8ea77d63fb4109
Build stamp OK:         produced by scripts/build_release.ps1 v1.4.2 at 2026-08-26T19:33:29.6591286Z
```

All green. Compiled with Inno Setup 6.7.1 (which still prints `Non-commercial use only` — the
known standing licensing exposure, unchanged by this session).

### 10.4 The artifact

```
LEDGER ROW (unsigned digest, as the ledger records):
1.4.2   ClawFactory-Secure-Setup.exe   unsigned
        28c04add21950e5bc573adcaef1235f6fecb2a3199dc5392b3b0e249c452b0b2   440594602   2026-08-26

SIGNED ARTIFACT AS PRODUCED:
SIGNED_SHA256 = 0e8c8e582275a87944b12c48c921c8424e376d6fa6b3bef3dae61ad9b8ee4ed6
BYTES         = 440610256
AUTHENTICODE  = Valid
SIGNER        = CN=Bret Mckinney, O=Bret Mckinney, L=West Valley City, S=ut, C=US
TIMESTAMP     = CN=Microsoft Public RSA Time Stamping Authority, ...
```

The v1.4.1 row is untouched, as is every row before it. The ledger records the **unsigned** digest
deliberately: signing embeds a countersigned timestamp, so the signed digest differs on every run
over identical input.

**9.4 honoured: no build gate was tested by editing a comment.** Inno strips comments, so the
compiled bytes would be identical and the gate would correctly report a byte-for-byte rebuild.
The gates were exercised by the real change instead.

### 10.5 Exactly what changed between v1.4.1 and v1.4.2

The validation job needs this list:

1. `resources/uninstall.ps1` — the keep-Linux teardown payload is LF-normalised before transport
   (`#284`); its output and exit code are captured, logged and checked against a terminal marker
   (`#286`); the gateway stop carries `XDG_RUNTIME_DIR` and its stderr is no longer discarded, and
   `clawuser`'s processes are verified gone before `deluser` (`#287`); the removal list is
   installer-derived — 11 units disabled-then-deleted, 17 helpers, the allow-providers drop-in
   directory, `/usr/local/bin/clawfactory-send` (`#285`); a failed teardown now shows the user a
   dialog naming what is left.
2. `resources/uninstall.ps1` — the uninstall dialog's copy, and the `-KeepLinuxEnvironment`
   contract comment.
3. `resources/launcher.ps1` — `Invoke-WslSilentScript` LF-normalises its payload.
4. Both files rewritten LF-on-disk so the bundled bytes match the committed bytes.
5. `ClawFactory-Secure-Setup.iss` + `setup.ps1` — version 1.4.1 → 1.4.2.
6. `released-versions.tsv` — one appended row.

**Nothing else. No security control was added, removed, weakened or re-scoped. Studio is
byte-identical to v1.4.1's.**

---

## 11. TASK 10.4: end-of-session gate

### 11.1 Commits and push

```
0fbd192  release: record v1.4.2 in the artifact ledger
a31b19a  version: installer 1.4.1 -> 1.4.2
32dd4e9  fix(launcher): the same missing LF-normalisation, found by the #284 census
0fb5dd8  fix(uninstall): the keep-Linux teardown ran half of itself and reported success

$ git ls-remote origin main
0fbd192847d7b68172db452bf253ab4f19d805ee   refs/heads/main
```

Studio: clean at `9282c42`, in sync, nothing to push. Explicit per-file staging throughout, no
`git add -A`, no worktree, **no tag created**, no release, no publish.

**Stated plainly rather than glossed:** the four cards are one commit, not four. They interleave in
a single function, and `#285`'s unit list is unreachable code without `#284`'s fix, so a per-card
commit would have recorded a state that provably cannot execute.

### 11.2 Cards

| Card | Was | Now | Why |
| --- | --- | --- | --- |
| `#284` | `queued` | **`Review`** | fixed and the cause reproduced; **built and unvalidated is not `done`** |
| `#285` | `queued` | **`Review`** | same |
| `#286` | `queued` | **`Review`** | same |
| `#287` | `queued` | **`Review`** | same |

Each carries a comment stating the fix, the evidence and the commit. Read back from the API's own
response, not assumed: `"status":"Review"` on all four. No other card was touched — no `#261`, no
`#277`/`#278`/`#280`/`#281`/`#283`, no `#198`.

### 11.3 Resource ledger

| Resource | State |
| --- | --- |
| VMs provisioned | **none** — no Azure resource was created, started, or deleted this session |
| Azure spend caused | **none** |
| Background tasks | one, the release build; completed exit 0; **none running now** |
| Persistent Monitors | **none started** |
| Local WSL rigs | four; residue removed and read back — see 11.6 |
| Outbound email | **none.** No probe that transmits was run |

### 11.4 Delta security sweep

- **No security control was added, removed, weakened or re-scoped.** Every change is to the
  uninstall path plus one no-op-until-now launcher fallback.
- **Two controls are made stronger:** the teardown now removes six units, five helper binaries and
  a drop-in directory it previously left on a machine whose owner uninstalled the product, and it
  no longer leaves `clawfactory-fw.service` enabled with its script deleted.
- **One control's ordering was changed and checked**: the quarantine broker is now stopped before
  the teardown's `rm` calls. Verified safe from the wrapper's own source — root passes through and
  never contacts the broker socket.
- **`/etc/clawfactory` still carries both SOUL pins, the persona and the egress policy**, and is
  still removed wholesale; no credential is involved (the API key is in Windows Credential Manager).
- **No credential value entered any transcript, commit or file.** The Dispatch secret was reported
  by length only (64); the `.env` was never printed.
- **The new failure MessageBox prints no path beyond the log location and no secret.**

### 11.5 Delta bug review

- **PowerShell AST parse: 0 errors** on `resources/uninstall.ps1`, `resources/launcher.ps1`,
  `setup.ps1`.
- **Control-character sweep, done on the AST rather than by grep** — a text grep cannot tell a
  backtick-in-a-comment from a backtick escape in an expandable string, and my first attempt
  reported 11 hits that were all prose. Structural result:

```
resources\uninstall.ps1  hits = 0
resources\launcher.ps1   hits = 0
setup.ps1                hits = 4   (lines 263, 288, 852, 1140 -- all 0x00)
```

  All four are the pre-existing backtick-zero NUL-strip idiom applied to `wsl.exe`'s UTF-16LE
  output, e.g. `setup.ps1:263`:

```
        # wsl.exe emits UTF-16 LE; strip the null bytes that show as
        # gibberish in the log if we don't.
        $clean = ($out -replace "`0", '' -replace "`r?`n+", ' | ').Trim(' |')
```

  Deliberate, correct, **none introduced this session.**
- **The sweep was canaried in both directions**: a file containing a `#` comment mentioning a
  backtick, a single-quoted string containing one, and a double-quoted string containing one
  produced **exactly 1 hit — the double-quoted string.**
- **`bash -n` on the shipped payload**: LF `SYNTAX_OK`, CRLF `SYNTAX_FAIL`. A discriminating
  control; my first attempt's `BASH_N_RC` read 0 in both cases and was discarded rather than
  leaned on.
- **No `TODO`, `FIXME`, `XXX` or `HACK` introduced** — 0 added lines matching, over the four-commit
  diff.
- **Line endings of every file touched: CR=0.**

### 11.6 Deviations and judgement calls, stated

**11.6.1 I used Bret's local WSL Ubuntu for four rigs.** The standing rule is that ClawFactory
*validation* never touches the local desktop and stays headless on Azure. These were not validation
— they were shell-semantics rigs with no VM available and no ClawFactory subject — but they did run
on his machine and two of them **mutated it**: one created `/dev/null␍` as root, and one created,
enabled and disabled two synthetic `cfrigunit-*` systemd units. Both were cleaned up and the
cleanup read back:

```
cfrig marker files in /var/tmp : 0   (must be 0)     <- 6 were left by the first two rigs and removed
cfsyn scratch in /var/tmp      : 0   (must be 0)
cfrigunit unit files           : 0   (must be 0)
cfrigunit wants symlinks       : 0   (must be 0)
stray /dev/null<CR>            : 0   (must be 0)
real /dev/null is a chardev    : yes
--- CONTROL: this reader can see something that IS there ---
/etc/hostname present          : yes  (must be yes)
clawfactory units still present: 11   (Bret's own install, untouched)
```

No ClawFactory unit, file, credential or config on that machine was read, written or stopped.

**11.6.2 The four cards are one commit.** Reasoned in 11.1.

**11.6.3 `launcher.ps1` is a scope extension.** The job was "uninstaller fixes"; this is the
install/run path. Fixed anyway, for the reason in section 4, in its **own** commit so it can be
reverted independently of the uninstaller work.

**11.6.4 Three of my own instruments were wrong before they were right, and are recorded.** MSYS
`sed`/`cat`/`grep` silently strip CR in text mode, which made an early digest comparison read as a
match when the files differed — the AST extraction is what settled it. `Write-Output` inside a
PowerShell function is captured by the assignment, which silently emptied two rigs' results. And
the first CR rig had the wrong shape twice. Each was caught by a control that refused to report.

**11.6.5 The build machine's working tree still diverges from the index for 105 other files.**
`git ls-files --eol` found 107 files `i/lf w/crlf`; two are now fixed. Of the remainder, the ones
that are transported into WSL are normalised at their transport sites, and the digest-bearing files
carry explicit `eol=lf` pins and were already LF. **Recommended, not done here** (it is outside
"uninstaller fixes" and would touch the install path): re-materialise the working tree so the bytes
Inno bundles equal the bytes that were reviewed.

---

## 12. Pre-flight, as required before any code was written

1. **Comprehension.** Restated as: change `resources/uninstall.ps1` only. Checked against the repo
   rather than the prompt — and the check was what found `launcher.ps1`, so the restatement was
   wrong and the repo corrected it.
2. **Dependency census.** Section 4. Two sites tree-wide, one of them unknown to the prompt. Also
   the installer-derived unit/helper enumeration, section 7.
3. **Failure-mode walk.** Section 9 for the dialog. For the teardown: if the new code works exactly
   as specified, it removes strictly more than before — including `clawfactory-send`, whose Guard 2
   credential file lives in `/etc/clawfactory` and was already being removed, so no new class of
   user data is destroyed. For `launcher.ps1`: it changes from doing nothing to starting the
   gateway; the payload self-guards by returning exit 0 when `:8787/status` already answers.
4. **Input-shape sweep** on the new values read. `$LASTEXITCODE`: present/absent/non-zero — a
   non-zero *or* a missing marker both mean incomplete, and both are logged. The `READBACK` line:
   present, absent (logged as "see the log"), malformed (never matched, so the marker check fails
   closed). `pgrep` output: empty, numeric, and the error case — the `pgrep -c` exit-1 trap in
   section 6.2 is exactly this sweep finding a fault before it shipped. `CLAWFACTORY_TEARDOWN_OK`
   is required by exact match, never by substring, so a paraphrase cannot satisfy it.

---

## 13. Lessons

**13.1 A clean `git status` is not a claim about the bytes on disk.** With `text eol=lf`, git
normalises on comparison, so a stale CRLF working copy compares equal to an LF index for ever. The
repo was right, the commit was right, and the shipped file was wrong — with no signal anywhere.
`git ls-files --eol` is the reading that shows it.

**13.2 A rig that normalises its input is testing a different program.** The cfv-176 rig extracted
the script through tooling that strips CR, so it ran the LF form and proved the LF form correct —
which was true and irrelevant. The digests were sitting in the close-out the whole time; comparing
them took two minutes and named the cause.

**13.3 Reproduce at the right privilege level.** The unprivileged rig showed CRLF breaking
*everything*, which contradicted the measured evidence and looked like a refutation. Root was the
missing variable: it can create `/dev/null␍`, so the simple commands survive and only reserved
words die. The same defect has two completely different signatures either side of a uid check.

**13.4 The census is worth more than the fix it was requested for.** It was mandated for one card
and found a second shipped site with the same two-line defect in a worse position.

**13.5 Derive removal lists from the thing that creates, never from the thing that removes.** The
teardown named 5 of 11 units and 12 of 17 helpers because it had grown by accretion. Deriving from
the installer produced a count that matched the measured on-box `SBIN_CLAWFACTORY_COUNT=17`
exactly, and explained the one number that had never reconciled.

**13.6 An audit that returns hits you have to hand-wave is not an audit.** The text-based
control-character sweep returned 11 hits, all prose in comments. Parsing the AST returned 4, all
real and all deliberate. PROMPT 15 already says this: where the question is enumeration rather than
detection, parse the AST.

---

## 14. What the validation job must measure

1. **The headline: keep-Linux uninstall, then a reinstall that COMPLETES.** Install → uninstall
   choosing No → verify by read-back that `clawuser`, `/etc/clawfactory`, `/usr/bin/openclaw`, all
   11 units, all 17 helpers and both enablement symlink sets are gone → **reinstall and confirm it
   finishes**. This is the single thing that turns the v1.4.1 NO into a yes.
2. **The teardown reports honestly.** `CLAWFACTORY_TEARDOWN_OK` present in
   `%TEMP%\ClawFactory-Uninstall.log`, with the `READBACK` line showing `units=0 sbin=0 enabled=0
   left=[ ]`. And the negative half: with a fault injected, confirm the log says failure and the
   user-facing dialog appears — a success marker that cannot fail is not a check.
3. **`#285` specifically**: after a keep-Linux uninstall, `systemctl list-unit-files 'clawfactory-*'`
   returns nothing enabled, and `clawfactory-fw.service` is neither present nor failed at the next
   boot.
4. **The RemoveAll branch, re-run in full** — all 16 rows, `DoRemoveAll = True` for `/SILENT` and
   for the dialog default, and `PIN.version` = 1.4.2. The dialog that selects it changed.
5. **The dialog rendered on screen**: no mid-sentence wrap, not wider than the screen, Yes still
   the default button.
6. **The launcher on a box with the gateway down** — the one install/run-path change in v1.4.2.
7. **A CR canary on the shipped artifact**: extract `resources/uninstall.ps1` from the installed
   `{app}\resources` and assert the transported payload has CR=0, so a future stale checkout cannot
   silently reintroduce this.

**No fitness-to-publish verdict is offered.** This build has not been validated, and one would rest
on an unmeasured premise.
