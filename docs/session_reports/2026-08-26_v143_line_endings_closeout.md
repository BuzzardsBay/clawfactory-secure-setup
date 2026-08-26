# CLOSE-OUT: v1.4.3 line-ending re-materialisation, the gate, and the build

Session 2026-08-26. Card `#288`. No VM, no validation run, no tag, no GitHub
release, no publish, no outbound email, no FrontierAI work.

**STATUS: COMPLETE. All six tasks done.**

**The finding, in one sentence:** ten files that Inno bundles into the shipped
installer did not have the bytes the repo contains, `git status` and `git diff`
both reported nothing, and six of the ten already carried the very
`.gitattributes` rule that was supposed to prevent it.

**The prompt's number was low.** It named 105 files. The divergent set is **118** —
the prior census counted only `i/lf w/crlf` and missed 13 files that are
`i/lf w/mixed`, which diverge for the same reason and with the same invisibility.

**The prompt's stated worry did not materialise, and a different one did.** No
digest-pinned file was in the divergent set, so no pin changed and `setup.ps1` was
never at risk. What the prompt could not have known is that `core.autocrlf=true`
comes from the **system** git config on this machine, which makes "use git's own
normalisation path" *destructive* on its own — it would have re-broken four
unpinned bundled files and newly broken the `.iss`. Section 5 states it.

**No fitness-to-publish verdict is written here.** This build is unvalidated.

---

## 0. PROMPT 15 preamble

Read in full from `C:\Users\bmcki\OneDrive\Desktop\Claude Prompts\FrontierAI_CC_Prompt_Library.md`.
**PROMPT 15 is present at line 645 of 925; the library is NOT stale.**

Clauses deleted as provably inapplicable, and why — the same four the v1.4.2
session deleted, for the same reasons:

| Clause | Why deleted |
| --- | --- |
| ENVIRONMENT, NOT NEGOTIABLE | No VM was provisioned. Every `az` clause has no subject. |
| HUMAN HANDOFF CARDS | No point in this job needs a human. Nothing was staged for an operator. |
| RESOURCE LEDGER (Azure half) | No VM, no disk, no NIC, no pip, no NSG, no licence slot. The non-Azure half is honoured in section 9. |
| MEASUREMENT DISCIPLINE (phase-runner half) | `interim-v120-phaselib.ps1` drives on-VM phases. Every rig here ran on the build machine. The *rules* it enforces were applied by hand and are shown firing throughout. |

Everything else applies and was followed: pre-flight, challenge-the-prompt,
calibrate before measuring, controls that must fail, canaries built to the shape
of the thing feared rather than the thing already known, credential hygiene, git,
version and build discipline, close-out as a gate.

---

## 1. Task accounting

| Task | State |
| --- | --- |
| PROMPT 15 preamble | **DONE** — read in full, present at line 645, four clauses deleted with reasons above |
| 1 Pre-flight, all four, reported before any file change | **DONE** — section 2, reported in-session before the first edit |
| 1 `git status --short` both repos, `origin/main` = `89f49db` | **DONE** — both clean, remote confirmed `89f49db`, section 2.5 |
| 2.1 `git ls-files --eol`, every direction, report the count | **DONE** — 118, not 105; section 3.1 |
| 2.2 Classify: bundled / digest-pinned / neither, derived from the `.iss` | **DONE** — section 3.2, derived by parsing `[Files]`, with `#define` expansion |
| 2.3 The bundled-set number, stated plainly | **DONE** — **10**; section 3.3 |
| 3.1 Re-materialise via git's own normalisation path | **DONE** — delete + `git checkout --`; section 4.1 |
| 3.2 Digest-pinned files handled individually | **DONE** — none were divergent; nothing re-pinned; section 3.4 |
| 3.3 Re-run and report divergence as a measurement | **DONE** — **0**; section 4.3 |
| 3.4 Assert no functional change, with a control | **DONE** — section 4.4, two-way control |
| 4.1 Build gate on bundled-vs-committed bytes | **DONE** — section 6 |
| 4.2 Named in the style of the existing gates | **DONE** — `Worktree pin OK: ...` |
| 4.3 Canary both directions | **DONE** — two failing canaries of different shapes, one passing; section 6.3 |
| 4.4 State what the gate cannot catch | **DONE** — in the code and in section 6.5 |
| 5.1 Bump to v1.4.3, never edit a ledger row | **DONE** — section 7.1; no row edited or deleted |
| 5.2 State whether Studio changed | **DONE** — it did not; section 7.2 |
| 5.3 Every gate by name, digests, bytes, Authenticode subject | **DONE** — sections 7.3–7.4 |
| 5.4 Exactly what changed, and whether behaviour changed | **DONE** — section 7.5 |
| 6.1 Card, separate commits, both repos pushed, no tag | **DONE** — section 8 |
| 6.2 Close-out committed and printed in full | **DONE** — this file |
| 6.2 The four explicit answers | **DONE** — section 10 |
| 6.3 End-of-session gate in full | **DONE** — section 9 |
| Challenge the prompt | **DONE** — three corrections, section 5 |

---

## 2. Pre-flight, before any code was written

### 2.1 Comprehension

Restated as: re-materialise 118 working-tree files, add a build gate, bump to
v1.4.3. Checked against the repo rather than against the prompt, and **the repo
corrected the restatement twice**: the divergent set is larger than the prompt
said, and the fix as specified would have been locally destructive.

### 2.2 Dependency census

Run tree-wide over every one of the ten divergent bundled files, by execution,
answering WHO consumes each file's bytes:

| Consumer class | Files | Do the delivered bytes change? |
| --- | --- | --- |
| Transported into WSL through `$lfB64`, which LF-normalises at transport | `clawfactory-proxy.js`, `clawfactory-proxy.service`, `clawfactory-quarantine.service`, `clawfactory-send.service` | **No.** Measured in 4.4 |
| PowerShell executed on Windows (`-File`, or dot-sourced) | `clawfactory-grants.ps1`, `clawfactory-stop.ps1`, `switch-provider.ps1`, `smoke-test.ps1` | **No.** Eight sibling bundled `.ps1` — including `setup.ps1`, `launcher.ps1`, `uninstall.ps1`, `bootstrap.ps1` — already ship LF and have since v1.1.0 |
| `wscript`/`cscript` on Windows | `wsl-keepalive.vbs` | **No.** Measured in 4.5, with a control |
| Transported into WSL **without** normalisation | `orchestrator-prompt.md` | **YES.** `Write-AgentMd` at `resources/bootstrap.ps1:179` base64s its argument with no `.Replace`, so today's CR bytes reach `~/.openclaw/agents/orchestrator/agent.md` verbatim |

The WHEN half: nothing is removed, gated, disabled or made conditional, so there
is no install-sequence or boot-sequence window where a thing is required but not
yet present. Every change is to bytes at rest. The single delivered-byte change
happens at bootstrap time in both the old and the new arrangement.

### 2.3 Failure-mode walk — what breaks if this works exactly as specified

The installer bundles LF where it bundled CRLF. The only observable consequence
anywhere in the product is that the orchestrator's `agent.md` lands 65 bytes
smaller, LF-terminated, with identical content — prose fed to a language model.
The four `$lfB64` payloads are bit-identical. The four `.ps1` and the `.vbs` parse
and execute identically.

For the gate: it blocks a build on a dirty checkout. That is the point, and it
names the offending file. Its cost is that a release build must now be made from
committed source — which is already how v1.4.2 was built.

### 2.4 Input-shape sweep on the gate's new reads

Decided and stated rather than left implicit:

| Shape | Meaning | Behaviour |
| --- | --- | --- |
| `git` absent, or not a git checkout | the gate's data source is missing | **FAIL.** A gate that silently skips when its input is absent is not a gate |
| bundled path not tracked by git | the two gitignored build-time binaries | **SKIP, named in the output.** Their own digest pins cover them |
| tracked by name, no index entry | corrupt state | **FAIL**, refusing to guess |
| `hash-object` returns a different count than the path list | the two lists are not comparable | **FAIL**, refusing to compare mismatched lists |
| worktree bytes != index bytes | bytes in no git object at all | **FAIL** — `WORKTREE DRIFT` |
| worktree == index, index != HEAD | staged but never committed | **FAIL** — `UNCOMMITTED BUNDLED FILES` |
| `.iss` yields zero `Source:` entries | the parser broke | **FAIL.** A gate that passes vacuously is worse than no gate |

### 2.5 Git state at session start

```
$ git status --short          (Secure-Setup)      -> clean
$ git ls-remote origin main
89f49dbecbdb53a99bde2473a08bccd1ab411f3c   refs/heads/main
$ git rev-parse HEAD          -> 89f49dbecbdb53a99bde2473a08bccd1ab411f3c    MATCH

$ git status --short          (Studio)            -> clean
$ git rev-parse HEAD          -> 9282c42cc814cc379195e1df26657bf097c4a72c
$ git ls-remote origin main   -> 9282c42cc814cc379195e1df26657bf097c4a72c    IN SYNC
```

---

## 3. TASK 2: enumerate and classify

### 3.1 The divergent set is 118, not 105

```
$ git ls-files --eol      ->  318 tracked files
   i/lf    w/lf      185     (agree)
   i/lf    w/crlf    105     <- the prompt's number
   i/lf    w/mixed    13     <- NOT in the prior census
   i/-text w/-text    12     (binary; agree)
   i/none  w/none      3     (agree)

DIVERGENT (index form != worktree form) = 118
Total CR bytes at risk across the 118    = 20,415
```

`i/lf w/mixed` means the working copy carries **both** CRLF and LF lines. It
normalises to the same LF blob on comparison, so it is exactly as invisible as
`w/crlf` and diverges for exactly the same reason. Section 11.6.5 of the v1.4.2
close-out counted only the `w/crlf` bucket. `.gitattributes` was itself one of the
thirteen.

**No file diverges in the other direction.** There is no `i/crlf` anywhere in the
repo, which is why the fix below changes zero committed bytes.

### 3.2 Classification, derived from the `.iss` rather than from a convention

The bundled set is every `Source:` entry in `[Files]`, parsed, with ISPP
`#define` references expanded so the paths are real:

```
[Files] Source entries                   : 56
  tracked in git                         : 54
  untracked (gitignored, sourced at build time):
      resources/ubuntu-rootfs.tar.gz
      resources/ClawFactory-Studio-Setup-1.3.2.exe
```

`[Setup]` carries no `SetupIconFile`, `LicenseFile`, `WizardImageFile` or
`InfoBeforeFile`, and the `.iss` contains no `#include`, so nothing else is
compiled in from a file. (The `.iss`'s own `[Code]` section *is* compiled into the
artifact; it is `i/lf w/lf` and was not divergent. It is unpinned, which mattered —
see 5.2.)

### 3.3 The finding, stated plainly

**Ten files that Inno bundles into the artifact did not have the bytes the repo
contains.**

```
i/lf w/crlf  resources/clawfactory-grants.ps1         attr=[text eol=lf]
i/lf w/crlf  resources/clawfactory-proxy.js           attr=[]
i/lf w/crlf  resources/clawfactory-proxy.service      attr=[]
i/lf w/crlf  resources/clawfactory-quarantine.service attr=[text eol=lf]
i/lf w/crlf  resources/clawfactory-send.service       attr=[text eol=lf]
i/lf w/crlf  resources/clawfactory-stop.ps1           attr=[text eol=lf]
i/lf w/crlf  resources/orchestrator-prompt.md         attr=[]
i/lf w/crlf  resources/switch-provider.ps1            attr=[text eol=lf]
i/lf w/crlf  resources/wsl-keepalive.vbs              attr=[]
i/lf w/crlf  smoke-test.ps1                           attr=[text eol=lf]
```

The other 44 tracked `[Files]` entries already agreed.

**Six of the ten carry `text eol=lf` and were still CRLF on disk.** That is not a
missing rule; it is lesson 13.1 of the v1.4.2 close-out in its purest form — the
rule was added after those files were checked out, and **git never re-normalises
an existing working copy when an attribute is added later.** Writing the rule was
never sufficient. Somebody had to re-materialise the files, and nobody did,
because nothing reported that they needed it.

### 3.4 Digest-pinned: nothing needed re-pinning

Derived from what `scripts/build_release.ps1` actually hashes, not from a naming
convention:

| Pinned file | Gate that hashes it | State before this session |
| --- | --- | --- |
| `resources/safety-rules.md` | SOUL pin, and the composed workspace-SOUL pin | `i/lf w/lf` — **not divergent** |
| `resources/persona.md` | persona pin, and the composed workspace-SOUL pin | `i/lf w/lf` — **not divergent** |
| `resources/ubuntu-rootfs.tar.gz` | rootfs pin | untracked binary; not in git |
| `resources/ClawFactory-Studio-Setup-1.3.2.exe` | Studio pin | untracked binary; not in git |
| `released-versions.tsv` | ledger gate (parsed, not hashed) | `i/lf w/lf` — **not divergent** |
| `setup.ps1` | carries every pin; protected by `-text diff` | `i/lf w/lf` — **not divergent** |

**No pin changed in this job, and no file in that table was edited except
`setup.ps1`'s version literal.** The prompt anticipated that re-materialising a
digest-pinned file could break a gate in an unforeseen way; the honest answer is
that the case never arose, because every pinned file was already correct.

`setup.ps1` specifically: the prompt names it as digest-pinned. It is more
precisely the file that *carries* the pins — no gate hashes `setup.ps1` itself.
Its `.gitattributes` rule is `-text diff`, which means git never converts its
bytes at all. It was already byte-identical to its index, so it needed nothing.
That claim was nevertheless **measured, not asserted** — see 4.2.

---

## 4. TASK 3: re-materialise

### 4.1 Method

git's own path, per 3.1 of the prompt: for each divergent file, delete it and
`git checkout -- <path>`, which re-creates it from the index under the rules in
`.gitattributes`. No hand-rolled rewrite, no `sed`, no `-replace` over file
contents. **But the rules had to change first**, for the reason in 5.2.

### 4.2 `setup.ps1` as a control, because `-text` was load-bearing

Adding `* text=auto eol=lf` gives every file an inherited `eol=lf`, including
`setup.ps1`. `git check-attr` reports `text: unset, eol: lf, diff: set` for it.
The documented behaviour is that `eol` is inert when `text` is unset — but a
security product's most critical file is not a place to trust a doc note, so it
was put through the same delete-and-checkout as the divergent files, with its
bytes held:

```
setup.ps1 before : F6A73D817C76CDC0FF5F44D443EE6068B41787CD94B32F71F0EB2C37AB18D208  214,311 B
setup.ps1 after  : F6A73D817C76CDC0FF5F44D443EE6068B41787CD94B32F71F0EB2C37AB18D208
BYTE-IDENTICAL   : True    (MUST be True)
```

`-text` wins, `eol=lf` is inert, and that is now measured rather than assumed.

### 4.3 The measurement

```
$ git ls-files --eol        (re-run)
   i/lf    w/lf      303
   i/-text w/-text    12
   i/none  w/none      3

DIVERGENT FILES NOW = 0
$ git status --short  ->  (only .gitattributes, the deliberate edit)
```

Reported as a measurement: the count is **zero**. Every one of the ten bundled
files was independently re-checked by byte hash against its index blob and all ten
matched.

### 4.4 No functional change, with its control

`git diff` is useless here by construction — it is the tool that cannot see this
defect. The comparison used instead is the SHA-256 of each file's **LF-normalised
content**, captured before any change and recomputed after:

```
files compared                       : 118
raw bytes on disk CHANGED            : 118      (every one; that was the job)
LF-NORMALISED CONTENT IDENTICAL      : 117
LF-NORMALISED CONTENT DIFFERENT      :   1  ->  .gitattributes   (the deliberate edit)
```

**The control, because a comparison that reports "no differences" without being
shown able to report differences is not evidence.** Two directions, on a real
bundled file:

```
reference (resources/clawfactory-proxy.js)     lf-sha = bb8456d9381e2fb6...
CONTROL A  a copy differing ONLY in line endings : reports IDENTICAL = True   (MUST be True)
CONTROL B  a copy with ONE character changed     : reports IDENTICAL = False  (MUST be False)
CONTROL B  byte-length delta = 0; differing byte positions = 1  (MUST be exactly 1)
```

Control A proves the comparison does not simply flag everything; control B proves
it does not simply pass everything. A one-character edit that leaves the file
length unchanged is the smallest real change it could be asked to catch.

And for the four files whose bytes are transported into WSL, the **delivered
payload** was compared directly, by running the product's own `$lfB64` lambda:

```
resources/clawfactory-proxy.js             delivered-sha before=bb8456d938 after=bb8456d938 SAME=True
resources/clawfactory-proxy.service        delivered-sha before=86b6f3791f after=86b6f3791f SAME=True
resources/clawfactory-quarantine.service   delivered-sha before=3b12f6b317 after=3b12f6b317 SAME=True
resources/clawfactory-send.service         delivered-sha before=4dbd953365 after=4dbd953365 SAME=True
```

**The one honest exception, not glossed:** `resources/orchestrator-prompt.md` is
delivered by `Write-AgentMd`, which does **not** normalise. Its bytes on disk went
4,342 -> 4,277, exactly the 65 CR bytes removed, and the file that lands at
`~/.openclaw/agents/orchestrator/agent.md` is 65 bytes smaller than it used to be.
Its content — LF-normalised digest — is unchanged. It is a markdown prompt read by
a language model, and the log line `orchestrator: source=orchestrator-prompt.md
(N chars)` will report 65 fewer characters.

PowerShell AST parse, on every `.ps1` in the bundled set that was touched:

```
resources/clawfactory-grants.ps1     parse errors = 0
resources/clawfactory-stop.ps1       parse errors = 0
resources/switch-provider.ps1        parse errors = 0
smoke-test.ps1                       parse errors = 0
setup.ps1                            parse errors = 0
resources/launcher.ps1               parse errors = 0
resources/uninstall.ps1              parse errors = 0
```

### 4.5 `wsl-keepalive.vbs`: the only Windows-executed bundled file, rigged

`.vbs` is the one bundled extension where LF could plausibly break something, and
"probably fine" is not a measurement. There are no `.bat` or `.cmd` files anywhere
in the repo, so this is the entire exposure. Rigged under `cscript //E:vbscript`
with **zero arguments**, so `WScript.Arguments(0)` throws before `sh.Run` is ever
reached — the rig has no side effects at all and starts no process:

```
=== ka_crlf   (today's shipped form, 779 B, CR=15) ===
  ka_crlf.vbs(14, 1) Microsoft VBScript runtime error: Subscript out of range

=== ka_lf     (the new form, 764 B, CR=0) ===
  ka_lf.vbs(14, 1) Microsoft VBScript runtime error: Subscript out of range     <- IDENTICAL, same line

=== ka_broken_lf  (CONTROL: LF form with one unbalanced paren injected) ===
  ka_broken_lf.vbs(13, 38) Microsoft VBScript compilation error: Expected ')'   <- MUST differ, and does
```

Subject and control produce the same *runtime* error at the same *line number*,
proving the file parsed completely and reached execution; the deliberately broken
copy produces a *compilation* error instead, proving the rig can tell a parse
failure from a run-time one. Without that third row the first two would prove
nothing.

---

## 5. Challenging the prompt: three corrections

### 5.1 The count was 105; it is 118

Stated in 3.1. The prompt inherited the number from section 11.6.5 of the v1.4.2
close-out, which counted one `git ls-files --eol` bucket and not the other.
Instruction 2.1 explicitly asked for "any direction, not only `i/lf w/crlf`", so
the prompt anticipated its own gap. All 118 were handled.

### 5.2 "Use git's own normalisation path" is, on its own, DESTRUCTIVE here

```
$ git config --system --get core.autocrlf   ->  true
$ git config --global --get core.autocrlf   ->  (unset)
$ git config --local  --get core.autocrlf   ->  (unset)
```

`core.autocrlf=true` is inherited from the **system** git config — the Git for
Windows installer's default, not anything versioned in this repo. With it set, the
checked-out form of any file lacking an explicit rule is CRLF. So a plain
delete-and-checkout of the 118 would have:

- correctly fixed the 26 files carrying an explicit `text eol=lf` (`eol` beats `autocrlf`), and
- **re-written the other 92 straight back to CRLF**, including four of the ten bundled files, and
- **newly broken `ClawFactory-Secure-Setup.iss`**, which is unpinned and happens to be LF on disk today; a re-checkout would have made it CRLF for the first time.

This is not a hypothesis. It is what happened on the first attempt (see 11.1), and
the reading afterwards was `DIVERGENT FILES NOW = 92`.

So the `.gitattributes` rule had to land first, and it had to be a **repo-wide**
one, because that is also the only form of the fix that survives the thing TASK 4
names as the threat: a fresh clone on a machine configured differently. Machine git
config does not travel with the repo; `.gitattributes` does. Added at the top of
`.gitattributes`, with every existing per-file rule left in place beneath it
(last-match-wins, so they still win, and they still document *why* each individual
file cannot tolerate a CR):

```
* text=auto eol=lf
```

`text=auto`, not a bare `text`, so git still auto-detects binaries and leaves
`ClawChat.exe`, the `.ico` and the `.png` alone — verified: all 12 `i/-text`
entries stayed `-text`. And because no tracked file has a CRLF **index** form, this
changes no committed blob at all; it changes only what a checkout produces.

Calibrated on one file before being trusted on 91:

```
BEFORE: i/lf w/crlf  attr/text=auto eol=lf   resources/wsl-keepalive.vbs
AFTER : i/lf w/lf    attr/text=auto eol=lf   resources/wsl-keepalive.vbs   bytes=764 CR=0
```

### 5.3 The prompt describes the gate's comparison two different ways

4.1 says "differs from its **committed** form". 4.4 says "it compares the working
tree against the **index**". Those are not the same check: a staged-but-uncommitted
file matches the index and does not match any commit.

The stronger reading is the correct one, and this was not academic — the first
canary run caught `setup.ps1` because the version bump was uncommitted at the time,
which is a true finding under 4.1 and a miss under 4.4. The gate as built enforces
**worktree == HEAD**, routed through the index so the two failure modes can be told
apart and reported separately. 4.4's disclosed limitation is unaffected and remains
exactly true: a file committed wrong in the first place still passes.

---

## 6. TASK 4: the gate

### 6.1 What it does

An eighth pre-build gate in `scripts/build_release.ps1`, placed immediately after
the existing Bundle check. It derives the bundled set from the `.iss` `[Files]`
section — parsed, with ISPP `#define` expansion, so it reads real paths rather than
trusting a naming convention — and for every tracked entry compares the raw on-disk
bytes against the committed blob.

The detection primitive is `git hash-object --no-filters`. `--no-filters` hashes the
file exactly as it sits on disk, skipping the clean filter, which is precisely the
step that hides this difference from `git status` and `git diff`. It compares
**bytes**, so it catches any divergence — a hand edit, a half-applied revert, an
editor save — not merely the line-ending class.

**The primitive was calibrated before the gate was built on it**, both directions:

```
--- KNOWN DIVERGENT (must report match=False) ---
resources/clawfactory-proxy.js    worktree-raw=376376cb1c2e index=f29cde6bdb20 match=False
resources/clawfactory-stop.ps1    worktree-raw=ea5e5ca76146 index=827a393ca718 match=False
resources/wsl-keepalive.vbs       worktree-raw=a569338f561c index=5af5b169ab6a match=False
--- KNOWN CLEAN (must report match=True) ---
resources/uninstall.ps1           worktree-raw=efc31b2971eb index=efc31b2971eb match=True
setup.ps1                         worktree-raw=08b117bade63 index=08b117bade63 match=True
resources/safety-rules.md         worktree-raw=d5d613d241ff index=d5d613d241ff match=True
resources/ClawChat.exe            worktree-raw=38c31acddbbb index=38c31acddbbb match=True
```

### 6.2 How it reports

Same style as the existing seven, so it reads alongside them:

```
Worktree pin OK: all 54 tracked [Files] resources are byte-identical to their committed form.
```

and on failure, one of two named modes:

- `WORKTREE DRIFT` — bytes that exist in no git object at all.
- `UNCOMMITTED BUNDLED FILES` — staged but never committed.

The two gitignored binaries are skipped **by name, in the output**, rather than
silently:

```
  Worktree pin: resources/ubuntu-rootfs.tar.gz is not tracked by git (sourced at build time, gitignored). Not compared here; its own pin gate covers it.
  Worktree pin: resources/ClawFactory-Studio-Setup-1.3.2.exe is not tracked by git (sourced at build time, gitignored). Not compared here; its own pin gate covers it.
```

`worktree` was added to the build stamp's `gatesPassed` list and the header
docstring now says eight gates.

### 6.3 Both canary readings

Run against a fully committed tree, so the only variable is the canary. Two failing
shapes rather than one, because a canary only certifies the pattern against the
shape of the canary — and the two shapes here are the two ways a bundled file can
stop being its committed self.

**CANARY 1 — line-ending drift** (the class this job exists for):

```
FAULT LANDED: resources/wsl-keepalive.vbs CR=15 (was 0)
              git diff --numstat -> []          <- EMPTY. Invisible to diff, which is the point.
EXIT: 1
  SOUL pin OK: e70212603f2f91e6abf6db576c9535b1aaad60506e2fb075c199f18160db7941
  Bundle check OK: all 34 preflight resources are in [Files].
  Fail : build_release.ps1: WORKTREE DRIFT: ... -- resources/wsl-keepalive.vbs.
RESTORED byte-identical: True
```

**CANARY 2 — a one-character in-place edit**, different file, different shape, and
one that `git diff` *can* see (so the gate is not merely re-implementing
`ls-files --eol`):

```
FAULT LANDED: smoke-test.ps1, byte length unchanged (20,983), exactly one character changed
              git diff --numstat -> [1  1  smoke-test.ps1]   <- non-empty, unlike canary 1
EXIT: 1
  SOUL pin OK: ...
  Bundle check OK: all 34 preflight resources are in [Files].
  Fail : ... would not match the repo a reader can audit -- smoke-test.ps1.
RESTORED byte-identical: True
TREE CLEAN: []
```

Each run named **only** its own injected file. Neither reached `Compiling installer
with Inno Setup...`.

**THE PASSING READING**, from the real v1.4.3 build on the restored tree:

```
pre-build tree state (MUST be clean): []
HEAD: d1ee3d42f0f6b7ec075f0cf040465d188cc3cbcb
SOUL pin OK: e70212603f2f91e6abf6db576c9535b1aaad60506e2fb075c199f18160db7941
Bundle check OK: all 34 preflight resources are in [Files].
  Worktree pin: resources/ubuntu-rootfs.tar.gz is not tracked by git ...
  Worktree pin: resources/ClawFactory-Studio-Setup-1.3.2.exe is not tracked by git ...
Worktree pin OK: all 54 tracked [Files] resources are byte-identical to their committed form.
```

A gate that has never failed is indistinguishable from a gate that cannot fail.
This one has now failed twice, for two different reasons, and passed once.

### 6.4 The one thing this gate is NOT

It is not a defence against anyone who can run the build. Like the build stamp
beneath it, it is **structural against process drift and advisory against an
adversary** — `ISCC.exe` invoked directly still bypasses it, exactly as documented
for the other seven. Nothing here changes that boundary, and it should never be
described as more.

### 6.5 What the gate cannot catch, said in the code as well as here

It compares the working tree against HEAD. **A file that was committed wrong in the
first place is byte-identical to its committed blob and passes cleanly.** The gate
proves the artifact matches the repo. It does not prove the repo is correct, it is
not a review, and it says nothing about the two gitignored binaries beyond what
their own digest pins already assert. That paragraph is in
`scripts/build_release.ps1` above the gate, not only in this document, because the
comments are the audit trail.

---

## 7. TASK 5: version, build, sign, ledger

### 7.1 Version

Two sites, the only two that carry it, confirmed by a tree-wide scan:
`ClawFactory-Secure-Setup.iss:9` and `setup.ps1:56`. Every other `1.4.2` in the
tree is either a historical comment naming the release a fix landed in, or the
v1.4.2 ledger row — both correct as they stand.

`setup.ps1` carries `-text diff`, so it was edited byte-exactly:

```
occurrences of the version line : 1 (must be 1)
bytes before=214311 after=214311  delta=0 (must be 0)
CR count now                     : 0 (must be 0)
AST parse errors                 : 0
line 56 now                      : $InstallerVersion      = '1.4.3'
```

**No ledger row was edited or deleted.** The v1.4.2 row and every row before it are
untouched; v1.4.3 is a new appended row.

### 7.2 Studio: UNCHANGED

No commit was made in the Studio repo this session. It is clean at `9282c42` and in
sync with `origin/main`, read from `git ls-remote`. **Studio stays at 1.3.2**, the
`#define StudioInstaller` pin is unchanged, the Studio pin gate reports the same
digest as v1.4.2 (`ac59375...`), and the by-hand checklist's quoted version strings
stay as they are.

### 7.3 Every build gate, by name, with its verdict

```
SOUL pin OK:            e70212603f2f91e6abf6db576c9535b1aaad60506e2fb075c199f18160db7941
Bundle check OK:        all 34 preflight resources are in [Files].
Worktree pin OK:        all 54 tracked [Files] resources are byte-identical to their committed form.   <- NEW
Studio pin OK:          ac5937516e7edbb5aac00433bfa6e5074449cbc28b132883099391639e1e7dca
Version OK:             1.4.3 (.iss and setup.ps1 agree)
Ledger OK:              released-versions.tsv carries 10 prior artifact row(s).
Persona pin OK:         0557d07004d4d067d8cd9e7cee7b2a3a783e0ac8ff4c492c0c152d7e35ff63a0
Workspace SOUL pin OK:  441b6279f6613c313e87e9e9e034f97a220540cddbf1cf738bb9a86c37a5a257 (6677 bytes composed)
Rootfs pin OK:          1483cc5c1dce13064f774834cbffdff226559fd522a67a381a8ea77d63fb4109
Build stamp written:    gatesPassed = soul, bundle, worktree, studio, version, persona, workspace-soul, rootfs
```

All green. Compiled with Inno Setup 6.7.1, which still prints `Non-commercial use
only` — the known standing licensing exposure, unchanged by this session.

Every pin except the new gate reports the **same digest as v1.4.2**, which is itself
a check: none of the pinned inputs moved.

### 7.4 The artifact

```
LEDGER ROW (unsigned digest, as the ledger records):
1.4.3   ClawFactory-Secure-Setup.exe   unsigned
        60f4e817f45147ba9b2d1c55b1ca43271b4eb589591735427f9ae518f29365e7   440593444   2026-08-26

SIGNED ARTIFACT AS PRODUCED:
SIGNED_SHA256 = b2cd6408e5d6fe39116c6e5c559f7de6cf86b2ac2d7a4a8e9093e399edb8c6a1
BYTES         = 440609096
AUTHENTICODE  = Valid
SIGNER        = CN=Bret Mckinney, O=Bret Mckinney, L=West Valley City, S=ut, C=US
TIMESTAMP     = CN=Microsoft Public RSA Time Stamping Authority, OU=nShield TSS ESN:7D00-05E0-D947, ...
```

The ledger records the **unsigned** digest deliberately: signing embeds a
countersigned timestamp, so the signed digest differs on every run over identical
input. The signing certificate's `NotAfter` is 2026-08-27 — that is **normal**, not
an alarm: Trusted Signing mints short-lived certificates daily and auto-rotates.

### 7.5 Exactly what changed between v1.4.2 and v1.4.3

Four files differ between `89f49db` and `de4da85`:

```
 .gitattributes               |  30 ++++++++++++         (not bundled)
 ClawFactory-Secure-Setup.iss |   2 +-                   (version only)
 scripts/build_release.ps1    | 112 +++++++++++++++++++   (not bundled)
 setup.ps1                    |   2 +-                   (version only)
```

And the sharper reading — of the **54 tracked bundled files**, comparing committed
blob to committed blob across the two releases:

```
COMMITTED blobs that differ between v1.4.2 (89f49db) and v1.4.3 (de4da85): 1
   setup.ps1
       -$InstallerVersion      = '1.4.2'
       +$InstallerVersion      = '1.4.3'
```

**So: apart from the version string, not one bundled file's committed bytes
changed.** The ten files that are now bundled differently were never *edited* — the
repo already held the correct bytes; the build machine's working copy did not.

**Does any change alter behaviour? No — with one stated caveat, and here is how I
know:**

1. **Only line endings changed in the bundled set.** LF-normalised content digests
   are identical for 117 of the 118 re-materialised files, the 118th being
   `.gitattributes`, which is not bundled. The comparison used carries a two-way
   control (4.4).
2. **For the four `$lfB64`-transported files the delivered payload is
   bit-identical**, measured by running the product's own transport lambda before
   and after (4.4).
3. **For the four `.ps1` files, LF is already the shipped norm** — eight sibling
   bundled `.ps1` including `setup.ps1` have shipped LF since v1.1.0 — and all parse
   with zero AST errors.
4. **For the `.vbs`, LF is measured equivalent** under `cscript`, with a control
   that must fail and did (4.5).
5. **The caveat:** `resources/orchestrator-prompt.md` reaches the distro
   unnormalised, so `~/.openclaw/agents/orchestrator/agent.md` is now 65 bytes
   smaller. Identical content; different byte count. This is the only delivered file
   in the product whose bytes change.
6. **No security control was added, removed, weakened or re-scoped**, and no
   installed unit, helper, firewall rule or credential path is touched.

Only 1 and 2 above are inference-free; 3 and 4 rest on rigs with controls; 5 is
measured. Nothing here is INFERRED.

Corroboration from the artifact itself: the ten bundled files lost 2,378 CR bytes,
and the unsigned artifact went 440,594,602 -> 440,593,444 B, a delta of -1,158 B.
Smaller than 2,378 because the payload is `lzma2/ultra64` solid-compressed, and in
the right direction.

---

## 8. TASK 6.1: cards, commits, push

### 8.1 Commits

Separate commits per logical change, explicit per-file staging throughout, no
`git add -A`, no worktree, **no tag created**, no release, no publish:

```
de4da85  release: record v1.4.3 in the artifact ledger
d1ee3d4  version: installer 1.4.2 -> 1.4.3
3c8d88c  build(gate): refuse to build when a bundled file is not its committed bytes
14990ac  fix(repo): the bytes Inno bundles were not the bytes in the repo

$ git ls-remote origin main
de4da85d4ff1de5f3a7e92a63cf006bdaeafc49d   refs/heads/main
$ git rev-parse HEAD
de4da85d4ff1de5f3a7e92a63cf006bdaeafc49d                          MATCH
```

Studio: clean at `9282c42`, in sync with its own `origin/main`, nothing to push.

**Stated plainly rather than glossed:** the version commit and the ledger commit are
two commits, not one, though the prompt groups them. The ledger row does not exist
until `build_release.ps1` has compiled and signed the artifact, so a single commit
was not physically available. v1.4.2 was released the same way.

**Also stated plainly: commit `14990ac` — "the re-materialisation" — contains
exactly one file, `.gitattributes`.** That is not an oversight. Re-materialising the
working tree changes no committed bytes, because the index was already correct;
measured across the 117 non-`.gitattributes` files, committed-blob changes = 0. The
durable half of TASK 3 is the rule, and the rule is the commit.

### 8.2 Card

| Card | State | Why |
| --- | --- | --- |
| `#288` (new) | **`Review`** | The work is done and every claim is measured, but **built and unvalidated is not `done`** |

Created via `POST /api/agent/update` with `x-frontier-secret`, action `create`, and
read back from the API's own response: `"id":288, "status":"Review"`. A comment
carrying the evidence, the canary readings and the four commit hashes was posted
with the documented `{"action":"add_comment","card_id":288,"content":...}` shape and
returned 200.

**No other card was touched** — no `#261`, no `#277`/`#278`/`#280`/`#281`/`#283`, and
none of `#284`–`#287`, which remain in `Review` from the v1.4.2 session.

---

## 9. TASK 6.3: end-of-session gate

### 9.1 Task accounting

Section 1. All six tasks plus the preamble and the challenge duty: DONE.

### 9.2 Resource ledger

| Resource | State |
| --- | --- |
| VMs provisioned | **none** — no Azure resource was created, started, stopped or deleted |
| Azure spend caused | **none from compute.** The build called Azure Trusted Signing once (`OperationId 23dba83a-...`, Succeeded in 1.01 s) |
| Background tasks | one, the release build; completed exit 0; **none running now** |
| Persistent Monitors | **none started** |
| Local WSL rigs | **none.** Nothing in this job needed WSL, and the local desktop's ClawFactory install was neither read nor written |
| Local Windows rigs | three, all in the session scratchpad: the VBS three-way, the content-comparison control pair, the control-character canary. Residue is confined to the scratchpad; nothing was written outside the repo and that directory |
| Repo mutations outside the commits | none. Two canaries were injected into tracked files and both were restored and verified byte-identical; final `git status --short` is empty |
| Outbound email | **none.** No probe that transmits was run |
| Credentials | `DISPATCH_SECRET` read single-key from `C:\Users\bmcki\FrontierAI\.env` and reported by **length only (64)**. No value entered any transcript, commit, log or file |

### 9.3 Delta security sweep

- **No security control was added, removed, weakened or re-scoped.** No installed
  unit, helper binary, firewall rule, nft set, SOUL pin, persona pin, rootfs pin,
  credential path or turn gate is touched by any change in this release.
- **One control is made stronger, structurally:** the build now refuses to produce a
  signable artifact from source bytes that are not in the repository. The product's
  public claim is that its source can be audited; until this release that claim was
  false for ten bundled files and nothing would have said so.
- **The pinned-input surface is unchanged and proven unchanged**: SOUL, persona,
  composed workspace SOUL, rootfs and Studio pins all report byte-for-byte the same
  digests as the v1.4.2 build.
- **`setup.ps1` is byte-protected and was proven so** through a delete-and-checkout
  (4.2) before anything else was trusted. Its only content change is the version
  literal.
- **The new gate handles secrets not at all** — it reads git object hashes and file
  paths, and prints only paths.
- **The gate's own failure text names file paths and nothing else.** No digest, no
  content, no environment value.
- **Attribute change reviewed for over-reach:** `* text=auto eol=lf` is deliberately
  `text=auto` rather than `text`, so binary auto-detection is preserved; all 12
  `i/-text` entries were confirmed still `-text` afterwards, and the byte-protection
  exception for `setup.ps1` still wins (`git check-attr` reports `text: unset`).
- **No credential, key, token or password appears anywhere in this session's output,
  commits, or files.**

### 9.4 Delta bug review

- **PowerShell AST parse: 0 errors** on `scripts/build_release.ps1` and `setup.ps1`
  after every edit, and on all seven bundled `.ps1` after re-materialisation.
- **Control-character sweep, done on the AST rather than by grep**, because a text
  grep cannot tell a backtick in prose from a backtick escape in an expandable
  string:

```
scripts/build_release.ps1  control escapes in expandable strings = 12
    lines 385, 431-437, 599, 604 (x2), 605
  control escapes on lines ADDED THIS SESSION = 0   (MUST be 0)
setup.ps1                  = 66, none added this session
```

  All twelve are the pre-existing workspace-SOUL composition header and the ledger's
  tab/newline handling. **None introduced.**

- **That sweep was itself canaried**, shaped like what it could plausibly miss — a
  `#` comment mentioning a backtick escape, a single-quoted string containing one,
  and a double-quoted string containing one. Result: **exactly 1 hit, the
  double-quoted string.**
- **The byte-divergence primitive was calibrated both directions before the gate was
  built on it** (6.1), and the gate itself was canaried twice failing and once
  passing (6.3).
- **No `TODO`, `FIXME`, `XXX` or `HACK` introduced** — 0 added lines matching, over
  the four-commit diff.
- **Line endings of every file changed this session: CR=0**, all five.
- **Two of my own instruments were wrong before they were right**, and are recorded
  rather than deleted — see 11.1 and 11.2. A third is in 11.3.

---

## 10. The four explicit answers

### 10.1 How many bundled files differed between repo and artifact before this job, and which

**Ten**, of the 54 tracked entries in the `.iss` `[Files]` section. All ten
`i/lf w/crlf` — the working copy carried CRs the committed blob does not have:

| File | Attribute it carried | Consequence |
| --- | --- | --- |
| `resources/clawfactory-grants.ps1` | `text eol=lf` | bundled CRLF; runs on Windows, parses either way |
| `resources/clawfactory-proxy.js` | *(none)* | bundled CRLF; LF-normalised at transport, delivered payload unaffected |
| `resources/clawfactory-proxy.service` | *(none)* | as above |
| `resources/clawfactory-quarantine.service` | `text eol=lf` | as above |
| `resources/clawfactory-send.service` | `text eol=lf` | as above |
| `resources/clawfactory-stop.ps1` | `text eol=lf` | bundled CRLF; runs on Windows |
| `resources/orchestrator-prompt.md` | *(none)* | bundled CRLF, and **delivered CRLF** into the distro |
| `resources/switch-provider.ps1` | `text eol=lf` | bundled CRLF; runs on Windows |
| `resources/wsl-keepalive.vbs` | *(none)* | bundled CRLF; runs under wscript on Windows |
| `smoke-test.ps1` | `text eol=lf` | bundled CRLF; runs on Windows |

Six of the ten already carried the rule that should have prevented it. The rule was
added after those files were checked out, and git never re-normalises an existing
working copy.

The wider set: **118** tracked files diverged in total, 105 `w/crlf` and 13
`w/mixed`. The remaining 108 are build scripts, documentation, the validation
harness and archived validation runs — outside the artifact, but divergent for the
same reason, and all now fixed.

### 10.2 The proof that nothing but line endings changed, with its control

Two independent measurements, each with a control:

**Content identity.** SHA-256 of each file's LF-normalised content, captured before
any change and recomputed after: **117 of 118 identical**, the 118th being
`.gitattributes`, the deliberate edit. Raw bytes changed for all 118, which is the
job.

*Its control*, run on a real bundled file (`resources/clawfactory-proxy.js`): a copy
differing **only** in line endings reported `IDENTICAL = True`; a copy with
**exactly one character** changed and the same byte length reported
`IDENTICAL = False`. The comparison is therefore shown able to report both answers,
and the smallest real change it could be asked to catch is caught.

**Delivered-payload identity.** For the four files carried into WSL through
`$lfB64`, the product's own transport lambda was run before and after: all four
delivered digests identical (`bb8456d938`, `86b6f3791f`, `3b12f6b317`,
`4dbd953365`).

**Plus, for the one file type where LF could plausibly matter**, the VBScript rig of
4.5: CRLF and LF forms produce the identical runtime error at the identical line,
and a deliberately broken LF copy produces a compilation error instead.

**Plus, from git itself**, the cleanest statement of all: of the 54 tracked bundled
files, exactly **one** committed blob differs between v1.4.2 and v1.4.3, and its
entire diff is `-$InstallerVersion = '1.4.2'` / `+$InstallerVersion = '1.4.3'`. The
ten files were not edited. The repo already held the right bytes.

### 10.3 The gate's two canary readings, failing and passing

**FAILING (1 of 2) — line-ending drift injected into `resources/wsl-keepalive.vbs`:**

```
FAULT LANDED: CR=15 (was 0);  git diff --numstat -> []   (empty: invisible to diff)
EXIT: 1
Fail : build_release.ps1: WORKTREE DRIFT: these bundled files would be compiled into the
installer with bytes that are NOT the bytes git holds ... -- resources/wsl-keepalive.vbs.
(never reached "Compiling installer with Inno Setup...")
```

**FAILING (2 of 2) — one character changed in `smoke-test.ps1`, same byte length:**

```
FAULT LANDED: 1 character;  git diff --numstat -> [1  1  smoke-test.ps1]
EXIT: 1
Fail : ... would not match the repo a reader can audit -- smoke-test.ps1.
```

Each named **only** its own file. Both were restored and verified byte-identical.

**PASSING — the real v1.4.3 build, tree clean and committed at `d1ee3d4`:**

```
Worktree pin: resources/ubuntu-rootfs.tar.gz is not tracked by git ... Not compared here.
Worktree pin: resources/ClawFactory-Studio-Setup-1.3.2.exe is not tracked by git ... Not compared here.
Worktree pin OK: all 54 tracked [Files] resources are byte-identical to their committed form.
```

### 10.4 The validation scope for v1.4.3

**Everything section 14 of the v1.4.2 close-out named, carried forward intact
because v1.4.3 contains v1.4.2's changes and none of them has been validated
either — v1.4.2 was never installed on a box.**

> **14.1** **The headline: keep-Linux uninstall, then a reinstall that COMPLETES.**
> Install -> uninstall choosing No -> verify by read-back that `clawuser`,
> `/etc/clawfactory`, `/usr/bin/openclaw`, all 11 units, all 17 helpers and both
> enablement symlink sets are gone -> **reinstall and confirm it finishes**. This is
> the single thing that turns the v1.4.1 NO into a yes.
>
> **14.2** **The teardown reports honestly.** `CLAWFACTORY_TEARDOWN_OK` present in
> `%TEMP%\ClawFactory-Uninstall.log`, with the `READBACK` line showing
> `units=0 sbin=0 enabled=0 left=[ ]`. And the negative half: with a fault injected,
> confirm the log says failure and the user-facing dialog appears — a success marker
> that cannot fail is not a check.
>
> **14.3** **`#285` specifically**: after a keep-Linux uninstall,
> `systemctl list-unit-files 'clawfactory-*'` returns nothing enabled, and
> `clawfactory-fw.service` is neither present nor failed at the next boot.
>
> **14.4** **The RemoveAll branch, re-run in full** — all 16 rows,
> `DoRemoveAll = True` for `/SILENT` and for the dialog default, and `PIN.version` =
> 1.4.2. The dialog that selects it changed.
>
> **14.5** **The dialog rendered on screen**: no mid-sentence wrap, not wider than
> the screen, Yes still the default button.
>
> **14.6** **The launcher on a box with the gateway down** — the one install/run-path
> change in v1.4.2.
>
> **14.7** **A CR canary on the shipped artifact**: extract
> `resources/uninstall.ps1` from the installed `{app}\resources` and assert the
> transported payload has CR=0, so a future stale checkout cannot silently
> reintroduce this.

**One correction to the carried-forward text:** 14.4 says `PIN.version` = 1.4.2. For
this artifact it is **1.4.3**. Nothing else in section 14 changes.

**What this job ADDS to that scope:**

**14.8 The bundled bytes on the installed box are the committed bytes.** This
generalises 14.7 from one file to the whole bundled set, and it is now checkable
against a public repo. On the installed machine, for every file under `{app}` and
`{app}\resources` that has a counterpart in the `.iss` `[Files]` section, assert
`CR=0` and assert the SHA-256 matches the blob at commit `de4da85`. Ten of those
files would have failed this check against every release up to and including
v1.4.2. **The negative half, without which the check proves nothing:** confirm the
same probe reports a mismatch when handed a deliberately altered copy.

**14.9 `resources/orchestrator-prompt.md` reaches the distro with CR=0.** This is
the one delivered file whose bytes change in v1.4.3. Read
`~/.openclaw/agents/orchestrator/agent.md` inside WSL as `clawuser` and assert
`CR=0` and a byte count 65 lower than the v1.4.2 build would have produced. The
control: assert the file is non-empty and contains the substituted SOUL digest, so
an absent or truncated file cannot read as a pass.

**14.10 `wsl-keepalive.vbs` actually runs from its LF form on a real box.** The rig
in 4.5 proved VBScript parses LF under `cscript`. It did **not** prove the scheduled
task works, because it deliberately never reached `sh.Run`. On the installed
machine: confirm the `ClawFactory WSL Host` scheduled task starts, that no console
window flashes at logon, and that a WSL session is held afterwards. The control:
confirm the task's absence is detectable by the same probe.

**14.11 The four Windows-side `.ps1` files execute from their LF form.** Run each of
`smoke-test.ps1`, `clawfactory-stop.ps1`, and `switch-provider.ps1 -Provider <name>`
from `{app}\resources` on the box, and confirm `clawfactory-grants.ps1` dot-sources
cleanly from `launcher.ps1`. AST parse is not execution.

**14.12 The `Worktree pin` gate is not a runtime control and needs no on-box check.**
Recorded so that no validation run wastes a phase looking for it.

**No fitness-to-publish verdict is offered.** This build has not been validated, and
one would rest on an unmeasured premise.

---

## 11. Deviations, judgement calls, and instruments that were wrong first

### 11.1 My first re-materialisation pass clobbered its own rule, and I caught it by measuring

`.gitattributes` was itself one of the 118 divergent files. The first pass deleted
all 118 — including `.gitattributes` — and then ran `git checkout --`, which
restored `.gitattributes` from the **index**, i.e. the committed version *without*
the new baseline. Everything checked out afterwards therefore used the old rules,
and the 92 unpinned files came back CRLF.

The measurement is what caught it: `DIVERGENT FILES NOW = 92` when the expectation
was 0. The fix was to write the header to the scratchpad first, re-apply it, and
exclude `.gitattributes` from the re-materialisation list — it does not need
re-materialising, because writing it LF already makes it agree with its index. The
second pass reported `DIVERGENT FILES NOW = 0`.

**Recorded rather than deleted**, because the general lesson is sharp: a rule file
that is also a subject of the operation it governs cannot be in that operation's
input list.

### 11.2 A PowerShell pipe prepended a UTF-8 BOM to git's stdin

`$paths | git hash-object --no-filters --stdin-paths` failed with
`fatal: could not open '<BOM>resources/clawfactory-proxy.js'`. PS 5.1's pipe encoding
put a BOM on the first line. Switched to passing paths as arguments, which is also
faster (two git invocations for the whole bundled set). No BOM can reach git that
way. This is the same BOM class already recorded for `Set-Content -Encoding utf8`,
in a new place.

### 11.3 A third instrument was wrong and its result was discarded

`Invoke-RestMethod` returning a JSON **array** made `$r.cards` evaluate to an array
of 277 nulls — truthy, so the fallback never fired and a "277 cards" reading was
produced from nothing. Caught by asking for a card's schema and getting
`Count, Length, Rank, SyncRoot` — the members of an array, not of a card. The board
read was redone correctly.

### 11.4 The gate is stricter than the prompt's section 4.4 describes

Deliberate, reasoned in 5.3, and the disclosed limitation is unchanged.

### 11.5 A repo-wide `.gitattributes` rule is broader than "re-materialise 118 files"

TASK 3 asked for a re-materialisation; TASK 4's premise asked for permanence against
a fresh clone. On this machine those two cannot both be satisfied without a
versioned rule, because `core.autocrlf=true` comes from the system config. The rule
is the smallest thing that satisfies both, it changes no committed blob, and every
pre-existing per-file rule was left in place beneath it rather than being
consolidated away — they still win, and they still carry the reason each individual
file cannot tolerate a CR.

### 11.6 The build machine's local ClawFactory install was not touched

No WSL command was run in this session at all. The standing rule that ClawFactory
validation never touches the local desktop is honoured trivially, because nothing
here needed a distro.

---

## 12. Lessons

**12.1 A rule is not a fix.** Six of the ten broken bundled files already carried
`text eol=lf`. Writing the attribute changes what a *future* checkout produces; it
does nothing to the copy already on disk, and git never revisits it. Every
`.gitattributes` line added to this repo since v1.1.0 needed a re-materialisation
pass behind it and never got one. When you add an EOL rule, delete and re-check-out
the files it names, in the same commit, and prove it with `git ls-files --eol`.

**12.2 The census bucket you do not look at is the one that grows.** The prior
session read `i/lf w/crlf` and reported 107. It did not read `i/lf w/mixed`, and 13
more files sat there for the whole time. Count every bucket the tool emits, not the
one you went looking for.

**12.3 `core.autocrlf` is not your repo's setting.** It came from the Git for Windows
installer, in the **system** config, and it silently decides the bundled bytes of
every unpinned file. Anything that must be reproducible across clones has to be
pinned in `.gitattributes`, because that is the only layer that travels.

**12.4 A rule file cannot be an input to the operation it governs.** Deleting
`.gitattributes` as part of a bulk re-materialisation restored the old rules mid-run
and silently reverted 92 of 118 files. The measurement caught it; the expectation
would not have.

**12.5 Build the second canary to a different shape.** One CRLF canary would have
certified a gate that only ever compared line endings. The one-character canary is
what proves the gate compares bytes. PROMPT 15 already says this and it was worth
obeying literally.

**12.6 The comparison you use to prove "nothing changed" needs to be shown capable of
saying "something changed".** Both halves. A control that only proves it can detect
differences leaves open that it flags everything; a control that only proves it can
report identity leaves open that it passes everything. Two controls, not one.

**12.7 State which claim rests on which measurement.** "No behavioural change" is not
one fact. Here it is four measurements and one measured exception, and section 7.5
lists them separately so a reader can disbelieve any one of them independently.
