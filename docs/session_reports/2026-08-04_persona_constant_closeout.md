# Persona as a Build-Time Constant -- close-out

**Date:** 2026-08-04
**Track:** v1 fast-security-harness. Simplification job, net deletion of code.
**Depends on:** `613e6d5` (pushed), card #211 done. Met.
**Runs before:** the first gated build. No build was cut here.
**Dispatch card:** #212.
**Repos touched:** ClawFactory-Secure-Setup only. Studio not changed, nothing to push there.

---

## 0. Result

The injected workspace SOUL is now a build-time constant: `resources/safety-rules.md` plus
`resources/persona.md`, composed in a fixed order with line endings pinned in `.gitattributes`, with
its SHA-256 a literal in `setup.ps1` enforced by a fifth build gate.

`resources/freeze-injected-soul.sh` lost **259 lines and gained 61**. The marker parsing, the
pin-presence branch, the `DEFAULT_PERSONA` fallback, the adopted-copy audit trail, the
`CLAWFACTORY_PERSONA_RESET` escape hatch and both multi-option refusal messages are gone, because
the states they existed to handle can no longer occur.

**The verification also caught a latent build-blocker unrelated to persona.** See section 6.1. It is
the most consequential thing in this close-out.

---

## 1. Verification before deleting (section 2 of the job)

### Q1. What the scaffolded persona actually contains

1809 bytes of OpenClaw's stock template. The marker sat at line 37 of an 82-line file, so persona was
lines 38 to 82. Scoped to the **persona region only**, not the whole file:

| Check | Result |
| --- | --- |
| identity tokens (`clawuser`, agent ids, role names) | none |
| absolute filesystem paths | none. Only `/concepts/soul`, a docs-site URL in a markdown link |
| tool, exec or plugin directives | none |
| YAML frontmatter (machine-readable) | none |

Section headings were "Core Truths", "Boundaries", "Vibe", "Continuity". Entirely flavour.

### Q2. Nothing reads the persona region

`CLAWFACTORY-SAFETY-END` appears exactly once in the whole product: its own definition in the freeze
script. Not in the OpenClaw package, not in `/usr/local/sbin`, not in `/etc/clawfactory`.

| Consumer | Finding |
| --- | --- |
| OpenClaw | Whole-file bootstrap injection. `DEFAULT_SOUL_FILENAME`, `soulPath`, fixed basename set `AGENTS.md HEARTBEAT.md IDENTITY.md SOUL.md TOOLS.md USER.md`. Never parses the marker |
| turn gate | Hashes the whole file |
| `rename-agent.ps1` | Does not touch SOUL. Its only "persona" hits are the words "personal-assistant renaming" in user copy |
| Studio | Touches `~/.openclaw/SOUL.md` (the **factory** SOUL) and its `.sha256` sibling only. `grep -rn "workspace/SOUL\|workspace-soul"` across the backend returns nothing |
| plugin loading | Bootstrap basenames only, per `bundled/bootstrap-extra-files/HOOK.md` |

### Q3. What breaks

Nothing. No consumer, no load-bearing content. Two consequences stated rather than hidden: the stock
flavour text is replaced by ClawFactory's own, which is the decision; and an existing box's persona
is replaced on the next freeze. Since no authoring path has ever existed, the only way a box could
hold custom persona is the adoption bug this job deletes.

### Q4. The evolve-this-file language, confirmed

Upstream template lines 41 and 45; live frozen file **lines 74 and 78**, exactly where the prior
session found them:

```
If you change this file, tell the user, it's your soul, and they should know.
_This file is yours to evolve. As you learn who you are, update it._
```

The agent was being instructed to edit a `root:root 444 +i` file. Removed in the new persona, and
verified absent on the box in every validation run.

---

## 2. What was built

### 2.1 The constant

`resources/persona.md`, 2013 bytes, `eol=lf`. It states how to work, and it states plainly that the
boundaries above it are enforced outside the conversation and are not the agent's to reinterpret. It
does not tell the agent to edit anything.

The composed file is exactly:

```
HEADER (314 bytes, literal in both the freeze script and the build gate)
resources/safety-rules.md          (4277 bytes)
SEPARATOR (73 bytes, literal in both)
resources/persona.md               (2013 bytes)
                                 = 6677 bytes, sha256 441b6279...
```

### 2.2 Three literals, one new gate

| Literal | Covers | Enforced at build by | Enforced at install by |
| --- | --- | --- | --- |
| `$expectedSoulHash` | `safety-rules.md` | gate 1 (existing) | `Step-ApplySafetyRules` |
| `$expectedPersonaHash` | `persona.md` | **gate 5 (new)** | `Step-FreezeInjectedSoul` |
| `$expectedWorkspaceSoulHash` | the **composed** file | **gate 5 (new)** | the freeze script, against its own composed output |

`build_release.ps1` now prints six OK lines. Same shape as the others: fail on drift, never
auto-correct.

### 2.3 What was deleted (3.3)

Marker parsing, the branch on pin presence, `DEFAULT_PERSONA`, the adopted-copy trail, the reset
escape hatch, and the two multi-option refusal messages. Not left dormant, removed.

### 2.4 Read-while-immutable (3.4)

The prior session's ordering requirement is satisfied in a stronger form: **nothing is read from
`$WS` at any point**, so the unlink-and-replace window has no read to race. The post-freeze
`cmp` against the staged copy and the symlink check are retained. Test 7 proves the window stayed
closed, with the same paired control that originally found it.

### 2.5 Operator messages re-read (3.6)

Every message on this path was re-read after the change. The freeze script now has exactly one
refusal, for a composed-file digest mismatch, and it says the only true thing: nothing was installed,
and the fix is to rebuild from a clean checkout rather than editing files on the machine. There is no
longer any instruction to re-run a deleted script, and no promise that a bare `-Resume` fixes
anything. `setup.ps1`'s throw from the prior session still applies and is still accurate.

---

## 3. Validation (section 4)

File-based channel throughout. Every block assertion carries a control that must fail in the same
run. Real step bodies (`Step-ApplySafetyRules` and `Step-FreezeInjectedSoul`) extracted from
`setup.ps1` by AST and dot-sourced, so `$PSScriptRoot` resolves to the harness directory.

| # | Test | Result |
| --- | --- | --- |
| 1 | Fresh install, no workspace SOUL | **PASS.** ws = pin = literal `441b6279`, `root:root 444`, `lsattr` shows `i`, gate 0 |
| 2 | Re-run on a healthy box | **PASS.** Byte-identical, pin unchanged, gate 0 |
| 3 | Arbitrary text before the freeze | **PASS.** Overwritten. `CANARY-PERSONA-9f3b2` occurrences: 0 |
| 4 | Remnant from a faulted run | **PASS.** Overwritten. `CANARY-REMNANT-7c1a4` occurrences: 0 |
| 5 | Tampered persona resource at build time | **PASS.** Build refuses; restored and passes |
| 6 | Tampered frozen file at rest | **PASS.** Gate returns 3 `soul_mismatch`; control restores to gate 0 |
| 7 | clawuser write / unlink / rename | **PASS.** rc=1,1,1 with control rc=0,0,0 |
| 8 | Restart, then re-run 1, 6, 7 | **PASS.** All three reproduce |

### Test 3, the one that matters most

```
  ws=92b967773064c2e71e8bab8f4fdaa615d7d4a555093c24eda663448e46a3af14 pin=441b6279...
RESULT: returned normally, no throw.
  ws==literal  : YES
  pin==literal : YES
  --- canary survival (SUBJECT: must be absent) ---
    'CANARY-PERSONA-9f3b2' occurrences: 0
    'IGNORE ALL PRIOR RULES' occurrences: 0
  --- CONTROL: a string that IS in the file (must be non-zero) ---
    'CLAWFACTORY' occurrences: 2
  --- evolve-this-file language (SUBJECT: must be absent) ---
    'yours to evolve' : 0
    'may evolve'      : 0
  --- CONTROL: persona text that MUST be present ---
    'Who You Are'     : 1
```

The controls are what make the zeroes mean anything: the same grep on the same file returns non-zero
for strings that are present.

### Test 7, after two probe defects were found and fixed

The first version reported `write_rc=0` for an operation that had clearly failed, because `$?` was
the exit code of a `sed` in the pipeline rather than of `setpriv`. That is the probe class this
project has been bitten by before, and it produced a control that did not fail. It was rewritten to
capture rc with no pipeline on the command under test:

```
=== TEST 7 SUBJECT: clawuser against the frozen file (every rc MUST be non-zero) ===
  rc=1   echo X >> .../SOUL.md      Operation not permitted
  rc=1   rm -f .../SOUL.md          cannot remove: Operation not permitted
  rc=1   mv .../SOUL.md .../x       cannot move: Operation not permitted
=== PAIRED CONTROL: identical ops on a non-immutable sibling (every rc MUST be 0) ===
  rc=0   echo X >> .../cf-ctl.md
  rc=0   mv .../cf-ctl.md .../cf-ctl2.md
  rc=0   rm -f .../cf-ctl2.md
  control file gone: YES
```

### Test 8 scope, stated precisely

`wsl --shutdown` plus distro restart, which is the WSL VM boundary that immutability, the pin files
and systemd state actually cross. The keepalive task that `--shutdown` drops was re-triggered.
**A full Windows reboot was NOT performed**, because rebooting the founder's physical machine is not
something to do unasked. If a Windows-reboot result is wanted it belongs in the build session on a
VM.

---

## 4. Task accounting

| Item | Status |
| --- | --- |
| Dispatch card at session start, done at close-out | DONE. Card **#212** |
| `613e6d5` pushed first | DONE. Already pushed at the end of the prior session; confirmed clean before starting |
| Q1 dump the persona, identify load-bearing content | DONE. None found |
| Q2 does anything read the persona region | DONE. Nothing does. Gateway, turn gate, `rename-agent.ps1`, Studio and plugin loading all checked |
| Q3 what breaks | DONE. Nothing |
| Q4 evolve-this-file language, confirm lines 74 and 78 | DONE. Confirmed, then removed |
| 3.1 persona as a resource, fixed order and encoding | DONE |
| 3.2 workspace pin as a build-time constant, fifth gate, both directions | DONE |
| 3.3 remove the adoption path entirely | DONE. Net deletion |
| 3.4 read while immutable, prove the window stayed closed | DONE. Stronger: no read at all |
| 3.5 strip the evolve-this-file language, confirm on the box | DONE. Verified in every run |
| 3.6 re-read every operator message | DONE |
| Validation 1 to 8, file-based, paired controls, AST, snapshot and restore | DONE |
| Lessons entry updated to record the supersession | DONE. **L25 addendum** |
| Task accounting, ledger, security sweep, bug review, recommendations | DONE |
| Cut a build | OUT OF SCOPE. Not done |
| Change `sign_installer.ps1` | OUT OF SCOPE. Not touched |
| User-authorable persona, Studio surface, re-freeze command | OUT OF SCOPE. **Deferred to v1.5** |
| Guard 3, Guard 4, Studio restyle, customer marketing copy | OUT OF SCOPE. Not touched |
| Presence-only items, card #210 | OUT OF SCOPE. Not touched |
| Full Windows reboot for test 8 | **DEFERRED** to the build session, reason in section 3 |

---

## 5. Resource ledger

**Live box at session end, verified by digest, restored to the session-start snapshot:**

```
factory = cd0199d52b9e4787f9be6fe53fb5a71726978006bc09f973f09f352bb9452bde
f-pin   = cd0199d52b9e4787f9be6fe53fb5a71726978006bc09f973f09f352bb9452bde   f match = YES
ws      = 03f29043ca6e890cd52fe38190a85414804ce10a46ef79e18313c803a51957a2
ws-pin  = 03f29043ca6e890cd52fe38190a85414804ce10a46ef79e18313c803a51957a2   w match = YES
ws stat = root:root 444 lsattr=----i---------e-------
leftovers in /etc/clawfactory: none
leftovers in workspace:        none
launch gate: exit 0
```

The box is deliberately back on the PRE-change constant, not the new one, because the instruction was
to restore by digest. A real install of this build produces `441b6279`, which is what tests 1, 2, 3,
4 and 8 demonstrated before the restore.

**Created on the box and removed:** `/etc/clawfactory/persona.md`,
`/etc/clawfactory/.workspace-soul.staged`, and the `cf-ctl.md` / `cf-ctl2.md` control files. All
confirmed absent.
**Left in place:** `/root/cf-persona2-snapshot/` (this session) and `/root/cf-persona-snapshot/`,
`/root/cf-audit-backup/` from prior sessions. Remove with `rm -rf /root/cf-*` when no longer wanted.
**WSL was restarted once** (`wsl --shutdown`), and the `ClawFactory WSL Host` keepalive task was
re-triggered afterwards.

**Repo, tampered and restored, each verified by digest:** `resources/persona.md` (append, restored to
`0557d070`), `setup.ps1` (`$expectedWorkspaceSoulHash` zeroed, restored).

**Scratchpad only:** `v1.sh`, `v2.sh`, `p2/` (harness, case, check, tamper, t7, snap, final).

**Azure:** none used. **Cost:** nothing compiled, nothing signed, no build cut.

---

## 6. Delta security sweep

### 6.1 The pre-existing build-blocker this job uncovered

**`$expectedSoulHash` was computed on a Windows working-tree rendering, not on the content git
stores.** Proven:

```
blob at HEAD (as stored, LF) : e70212603f2f91e6abf6db576c9535b1aaad60506e2fb075c199f18160db7941
that same blob rendered CRLF : 8f5531a36e46af8143ffe59ae4112a83a28b3513c473562578ee81c408c07eb6
old literal in setup.ps1     : 8f5531a3...   <- the CRLF rendering
```

`resources/safety-rules.md` had **no `.gitattributes` rule**, so its checkout form followed
`core.autocrlf`. On this machine that is `true`, giving CRLF and matching the literal. **On any clone
that checks out LF** (every Linux and macOS clone, and any Windows clone with `autocrlf=input` or
`false`) the file would hash to `e7021260`, and `Step-ApplySafetyRules` would have thrown *"the
safety rules have been altered since the build was signed"* on a completely clean checkout. The
build gate added in `ab180d4` would have failed there too.

This shipped from `ab180d4` and was invisible because only one machine ever built. It is fixed by
pinning both resources to `eol=lf` and recomputing the literal, so working tree, blob and digest now
agree everywhere. It was found only because section 3.1 demanded reproducible line endings.

### 6.2 Did any claim become untrue through this deletion

**One, and it was fixed in the same change.** The marker text says "everything below is persona
(workspace-owned)". Persona is no longer workspace-owned in any sense: it is a build-time constant.
The marker is gone; the separator that replaced it says "the text below is fixed at build time in
v1", which is true.

Checked and still true: `SECURITY.md`, `SECURITY_FINDINGS.md`, `README.md`, the post-install
checklist line reworded last session ("SOUL.md frozen root-owned + immutable; a changed hash refuses
the turn"), and the `[R6]` header. None of them described persona as user-owned or editable, so none
needed changing. No customer-facing copy was touched.

### 6.3 Posture

**Stronger.** An entire input class is gone rather than guarded: the marker-absent branch, remnant
absorption, agent-edit absorption, the first-freeze adoption residual, and the `chattr -i` read race
cannot occur. The workspace pin now chains to a literal in signed source, the same anchor as the
factory pin, which is the shape L24 established.

**New surface: none.** `/etc/clawfactory/persona.md` is root-owned 444 in a root-owned directory,
removed by `uninstall.ps1:402`. The staged file is unchanged in nature.

**Weaker anywhere: no.**

**Residual, stated:** the composition exists in two implementations, bash in the freeze script and
PowerShell in the build gate. Kept deliberately trivial, two constant strings around two file bodies.
A drift fails the build at gate 5 and fails the install at the script's own digest check, so it
cannot ship silently, but it is a maintenance hazard worth naming.

No secret, key, token or password appears in any changed file or in this close-out.

---

## 7. Delta bug review, from an end-to-end diff read

Read the complete diff across seven files.

**Found and fixed during the work:**

- **A lone CR inside a `setup.ps1` comment**, pre-existing at line 2380: `{app}` + `CR` + `esources`,
  where `{app}\resources` was meant. Harmless to the shipped installer, which parses clean either
  way, but it broke AST extraction and cost a test run with the message *"The term 'esources' is not
  recognized"*. Repaired to a real backslash; `setup.ps1` now contains **zero** lone CRs. This is the
  L20/L21 class showing up in a comment.
- **Two probe defects of my own**, both in section 3: the `$?`-after-a-pipeline bug in test 7, and a
  test 6 control that landed on the cold-meter path and so returned 4 instead of 0. Both rewritten
  and re-run rather than explained away.
- **`Write-Host "Persona pin OK"` was printing after the composite check**, so a composite failure
  hid the fact that the persona check had passed. Moved to immediately after its own check.
- **My own `.iss` edit corrupted a line** by collapsing `\\r` into a carriage return, producing
  `{app}` + CR + `esources`. Caught by reading the bytes back, repaired with `chr(92)` construction.
  Exactly the defect I had just fixed in `setup.ps1`, reintroduced by the same escaping trap one
  command later.

**Checked and correct:**

- `persona.md` is bundled in `[Files]` **and** listed in `Step-Preflight`'s `$required` (now 30), so
  the pairing gate covers it. Verified with the same `[regex]::Escape` the gate itself uses.
- Raw bytes are streamed for `persona.md`, deliberately not CRLF-normalised, because the digests are
  over repo bytes. The freeze script itself is still LF-normalised in transport, because it executes
  through a shebang.
- `set -e` interactions: the three `[ -r ... ] || { ...; exit 1; }` guards are safe; no bare
  `[ ... ] &&` statement exists in the new code.
- `chattr -i` before `rm -f "$WS"` is retained, so a re-run over an immutable file works.
- The empty-`$EXPECT` guard means a caller that forgets to pass the digest fails loudly rather than
  pinning something unverified.

**No unresolved bug found in the diff.**

---

## 8. Next-session recommendations

1. **Cut the build.** Five gates, six OK lines, and now no untested branch anywhere in the SOUL path.
   Note 6.1: this will be the first build whose SOUL literal matches what git actually stores, so if
   it is ever built on a non-Windows machine that now works too.
2. **Add `resources/orchestrator-prompt.md` and any other digest-bearing resource to
   `.gitattributes`.** 6.1 was found in `safety-rules.md`; the same class applies to any file whose
   bytes feed a pinned digest. Worth a five-minute sweep before the build.
3. **v1.5 persona feature.** A supported edit path that re-composes, re-freezes and re-pins, plus a
   Studio surface. The constant makes this straightforward: the composition is one function and the
   pin is one literal.
4. Unchanged from prior sessions: close the advisory build-gate bypass after the first build,
   capture the OpenClaw scaffold digest at install time if the first-freeze question ever returns,
   card #210 (Ollama), and the remaining presence-only items.

---

## 9. Git

`git status --short` run first. Explicit per-file staging, no `git add -A`, no `git worktree add`,
committed to `main` in the single working tree and pushed.

| File | Why |
| --- | --- |
| `resources/persona.md` | New. The constant |
| `resources/freeze-injected-soul.sh` | The deletion |
| `setup.ps1` | Three literals, persona streaming, preflight entry, lone-CR repair |
| `scripts/build_release.ps1` | Gate 5 |
| `ClawFactory-Secure-Setup.iss` | Bundle `persona.md` |
| `.gitattributes` | Pin both resources to `eol=lf` |
| `resources/safety-rules.md` | Renormalised to LF (content unchanged; the blob was already LF) |
| `ClawFactory_Install_Lessons_Learned.md` | L25 addendum |
| `docs/session_reports/2026-08-04_persona_constant_closeout.md` | This close-out |

Studio: not changed, nothing to push.
