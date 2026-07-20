# Secure-Setup JOB 2 F2 — close-out (adversarial suite repairs)

*2026-07-20. Authoring-only (NO cloud, NO VM). Repo (write): `ClawFactory-Secure-Setup`.
Chips: `task_09634243` (suite), `task_e965671d` (L-entry). Fix commit: `8ccfe0e`.
Model: Opus 4.8 (prompt recommended Sonnet — flagged; suite authoring verified by
`bash -n` + AST parse, model-independent). **Suite/tooling files only — no product
code, no installer, no Studio repo.***

## Baseline puzzle — RESOLVED (and the honest answer)

cfv-150 (Studio close-out `60dc10c`) graded the suite **27 PASS / 1 FAIL** vs the
"28/0" baseline, and lost T4.1–T4.3. I diagnosed **before** fixing:

- **T4.5 and all of Tier 4 entered in a single commit `cc261aa` (2026-07-14 16:29)
  and were never modified since** (`git blame`). So the current T4.5 text is exactly
  as first written.
- The T4.5 bash is **valid under LF but breaks under CRLF** — proven with `bash -n`
  (below).
- **`*.ps1` is not covered by `.gitattributes`** (which forces `*.sh`/`*.mjs`→LF),
  so on Windows (`core.autocrlf=true`) the working copy is CRLF: `git ls-files --eol`
  → `i/lf  w/crlf`. **The JOB 2 driver stages that CRLF working copy.**

**Finding, stated plainly:** the comfortable "28/0" was **never reproducibly
achieved through the JOB 2 staging path for T4.5**. T4.5 has been **latently broken
for every Windows-staged run since `cc261aa`**; single-line Wsl commands tolerate a
lone trailing CR, so only the one multi-line cell failed — and it hid behind the
green aggregate. cfv-150 was the first run to actually execute it and expose it. The
baseline number was not trustworthy for this cell; the honest per-cell result is what
matters.

## Fix 1 — T4.5 root cause (CRLF), fixed in the `Wsl` helper

Not the nested quoting (that's fine under LF). The multi-line here-string reached
bash with CRLF. **Minimal, root-cause fix:** strip CR in the `Wsl` helper before the
base64 encode, so bash always receives LF regardless of the checkout. T4.5's
**assertion is unchanged**; this also hardens *every* multi-line Wsl command.

```diff
 function Wsl([string]$Cmd, [string]$User = 'clawuser') {
+    # Strip CR before shipping bash into WSL. (*.ps1 is CRLF on Windows; a multi-line
+    # here-string with CRLF fails "unexpected end of file". Confirmed with bash -n.)
+    $Cmd = $Cmd -replace "`r", ''
     $b = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Cmd))
     return (& wsl.exe -d Ubuntu -u $User -- bash -lc "echo $b | base64 -d | bash" 2>&1 | Out-String)
 }
```

## Fix 2 — Tier-4 node dependency (dependency decision + justification)

`studio-turn-probe.mjs` drives the Studio **backend** launchers
(`agent-stream.js`/`chat.js`) and needs a Windows `node` **plus** a built/staged
Studio dist. On a clean validation VM **neither is present**: node is not on PATH
(the packaged Electron app bundles its runtime internally and doesn't expose it), and
the probe's dist path is dev-box-only
(`C:/Users/.../ClawFactory-Studio/backend/dist` or `$CLAWFACTORY_STUDIO_DIST`). On
cfv-150 the missing node **crashed** the suite (`The term 'node' is not recognized`)
and lost T4.1–T4.3 entirely — an **unvalidated claim, worse than a FAIL**.

**Neither spec option fits, and here's why:**
- **(a) rewrite to clean-box tooling (PowerShell/staged files)** — infeasible: the
  cells must import and drive JS launcher *modules*; PowerShell cannot, and the Studio
  dist isn't in the staged suite files.
- **(b) stage a pinned portable node** — pointless here: even with node, the mjs
  resolves the dist from a dev-box path / unset env var → returns
  `studio_dist_unavailable` → the cells skip anyway. Staging ~30 MB of node to
  guarantee a SKIP is a heavy test dependency for **zero** validation, and risks
  putting a JS runtime next to the thing under test.

**Decision (c):** guard on `Get-Command node`; when absent, record T4.1–T4.3 as
explicit **NOTE**s that say *why* (dev-box-only path) and point to where the **same
consumer-side gating claim IS validated on the clean VM** — **Tier 6** (ClawChat's
chatCompletions proxy: cap=0 blocked, tampered-SOUL blocked, real reply, all PASS on
cfv-150) plus the **JOB 2 functional matrix** (the Studio grant path). This removes
the node dependency, never crashes, and never silently skips. A dev box with node +
`$CLAWFACTORY_STUDIO_DIST` still runs the block unchanged.

Coverage mapping (why the NOTE is honest, not a dropped claim): T4.1/T4.2 ("turn
through Studio, cap=0, blocked") ≡ **T6.1**; T4.3 ("turn through Studio, tampered
SOUL, blocked") ≡ **T6.2**. Tier 6 tests the *actual current* customer path
(Electron→ClawChat→proxy); the Tier-4 Studio-probe cells were an earlier attempt at
the same claim through the now-legacy Express backend.

## Syntax-check evidence (dry-runnable only; no cloud)

```
LF   -> SYNTAX OK
CRLF -> /tmp/t45c.sh: line 9: syntax error: unexpected end of file   (reproduces cfv-150)
```
`Wsl` CR-strip transform verified: CR count 3 → 0. Full suite AST parse
(`[Parser]::ParseFile`): **0 errors**. The full suite was **not executed** (it fires
live agent turns and needs the VM environment — that's the cfv-151 run, not this
authoring session).

Expected cfv-151 delta: T4.5 now PASSES → **28 PASS / 0 FAIL**, with T4.1–T4.3 as
transparent NOTEs (dev-box-only; covered by Tier 6 + the JOB 2 matrix). The "28/0" is
then met *honestly* and reproducibly through the JOB 2 staging path.

## L-entries added

- **L20** — a multi-line string concat inside a PowerShell array literal parses as
  separate elements (the cfv-149 evidence-loss lesson: single-joined command lines +
  Count guard; producer-owned redundant evidence + sentinel; teardown gated on
  evidence-in-hand; simulate-before-execute). *(chip `task_e965671d`)*
- **L21** — a `.ps1` carrying multi-line bash into WSL must reach bash as LF, or strip
  CR at the boundary (this session's F2 finding; matches the existing `.gitattributes`
  rationale).

## END-OF-SESSION GATE

### 1. Task accounting
Comprehension + preamble (clean tree, suite+history read, card commented) — DONE.
Diagnosis (baseline puzzle) — DONE. T4.5 fix — DONE (`8ccfe0e`). Tier-4 node fix —
DONE. Dry-run (`bash -n` + AST) — DONE. L-entries — DONE (L20, L21). No silent drops.

### 2. Resource ledger — ZERO cloud
No VM, no provisioning, no agent turns. Local: `adversarial-suite.ps1` +
`ClawFactory_Install_Lessons_Learned.md` (`8ccfe0e`); this close-out. Transient
scratch files under `%TEMP%` for the `bash -n` reproduction (removed by WSL /tmp).

### 3. Delta security sweep
No credential values in diff or output. **No product file changed** (git status: only
the suite + the lessons doc). **Nothing widens product permissions:** the CR-strip and
node guard live entirely in the test suite; the node guard is a read-only
`Get-Command` check that stages nothing and touches no PATH. Confirmed suite/tooling
scope only.

### 4. Delta bug review
Diff re-read. The T4.5 fix targets the true root cause (CRLF), proven by `bash -n`,
not a symptom. The node guard is honest (NOTE + pointer to live coverage), not a
silent skip. One in-scope recommendation surfaced, not done: consider adding
`*.ps1 text eol=lf` to `.gitattributes` as structural defense-in-depth (renormalizes
all `.ps1`, so left as a follow-up rather than bundled into this minimal fix). No
out-of-scope edits.

## Dispatch
- Chip `task_09634243` (suite) → **done**. Chip `task_e965671d` (L-entry) → **done**.
- Card #147 → **stays blocked** — pending the `cfv-151` confirmatory run (Studio F1
  revoke-cell + this suite's 28/0) in a fresh session.

## Recommendations
1. Run **`cfv-151`** (fresh session): confirms Studio F1 (decontaminated revoke cell,
   Studio HEAD `feda808`) **and** this suite's honest 28/0 + T4.1–T4.3 NOTEs.
2. Optional hardening: add `*.ps1 text eol=lf` to `.gitattributes` so no future
   multi-line bash in a `.ps1` can regress on CRLF (belt to the code suspenders).
3. Hold JOB 3 until #147 is green.

---

## FINAL HEAD
```
8ccfe0e  fix(adversarial): F2 -- T4.5 CRLF root cause + Tier-4 node guard; L20/L21   ← suite/doc code
<this close-out sits directly on top of 8ccfe0e>
```
Repo HEAD after this close-out is printed in the session chat.
