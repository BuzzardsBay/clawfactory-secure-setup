# Post-release documentation corrections, v1.4.4

**The shipped v1.4.4 artifact predates every correction on this page.** `README.md` is
bundled into the installer (`ClawFactory-Secure-Setup.iss:46`) and gets its own Start
Menu shortcut (`ClawFactory-Secure-Setup.iss:186`), so the copy a v1.4.4 customer opens
is the pre-correction copy. **The divergence between the repository's `README.md` and
the `README.md` inside `ClawFactory-Secure-Setup.exe` v1.4.4 is deliberate.** It exists
because the alternative was to leave false sentences in the repository until the next
build, and it resolves the moment v1.5 is compiled, because the build takes `README.md`
from the working tree.

This page exists because this repository has already lost time to repository bytes and
artifact bytes diverging without anyone recording it. See `docs/FAILURE_CATALOGUE.md`
Class 8, "the bytes shipped were not the bytes in the repository". An undocumented
divergence here would read to a future session as exactly that defect class. It is not
that defect class. It is a documented one.

**Scope of the divergence.** Exactly one bundled file is affected: `README.md`.
`CLAUDE_ClawFactory.md`, `SUPPORT_MATRIX.md` and `SECURITY_FINDINGS.md` are not bundled
by the `.iss` and carry no shortcut, so correcting them changes nothing a customer can
reach. No shipped `.ps1`, no `.iss` line, no resource and no digest changed in any of
the work recorded here.

**Released artifact this diverges from.**

| Field | Value |
|---|---|
| Version | 1.4.4 |
| Artifact | `ClawFactory-Secure-Setup.exe` |
| SHA-256 | `548562c72d5261bc62d590df03746ea2bb52134a413e10d137b590e589fdcdea` |
| Size | 440594967 bytes |
| Built from | `25945d5` |
| Tag `v1.4.4` at | `9111e9b` |
| Recorded in | `released-versions.tsv` |

---

## Corrections made 2026-08-29, commit `2b3dec4` (before this record existed)

`2b3dec4` landed on `main` after the tag was cut and created the divergence this page
records. It was committed without a divergence record; this section supplies it
retrospectively.

### `README.md` line 53 (BUNDLED, and has its own Start Menu shortcut)

**Old, verbatim:**

```
5. Done. Desktop icon launches a chat session in Windows Terminal.
```

**New, verbatim:**

```
5. Done. The desktop icon and the Start Menu **ClawChat** entry both open ClawChat, the chat window. ClawFactory Studio, the control panel, is a separate window.
```

**Reason.** False against the `[Icons]` section of `ClawFactory-Secure-Setup.iss`.
`{commondesktop}\ClawFactory` and `{group}\ClawChat` both carry
`Filename: {app}\ClawChat.exe`. No `[Icons]` entry names `wt.exe`, `cmd.exe` with a
shell, or `powershell.exe` as a chat surface. `grep` for `wt.exe` over the `.iss` and
`launcher.ps1` returns nothing.

### `CLAUDE_ClawFactory.md` section 14.4 (NOT bundled)

Five corrections in one section: the Windows Terminal claim, the "run by desktop
shortcut" precondition, a poll timeout documented as 15s that the param block sets to
120, and two missing steps (grant replay, ClawChat start). Not bundled, so no
divergence. Recorded here only because it is where the `README.md` claim originated.

---

## Corrections made 2026-08-29, this session

### `README.md` line 3, the version badge (BUNDLED)

**Old, verbatim:**

```
[![v1.4.0](https://img.shields.io/badge/release-v1.4.0-green)](../../releases)
```

**New, verbatim:**

```
[![v1.4.4](https://img.shields.io/badge/release-v1.4.4-green)](../../releases)
```

**Reason.** v1.4.4 is published; v1.4.1, v1.4.2, v1.4.3 and v1.4.4 all post-date the
badge. Re-derived from `released-versions.tsv`, whose last row is `1.4.4`, and from
`ClawFactory-Secure-Setup.iss:9` `#define MyAppVersion "1.4.4"`.

### `README.md`, the build-gate count (BUNDLED)

**Old, verbatim:**

```
This is the build command. It runs seven pre-build gates, compiles with Inno Setup, and signs the result. The gates check that the SOUL, persona and composed-workspace-SOUL digests pinned in `setup.ps1` match the files on disk, that every preflight-required resource is actually bundled, that the embedded Studio payload and the bundled Ubuntu rootfs are the pinned ones, and that the two version literals agree. Each one fails the build on drift and none of them auto-correct.
```

**New, verbatim:**

```
This is the build command. It runs nine pre-build gates, compiles with Inno Setup, and signs the result. The nine, in the order the script runs them, are: SOUL, bundle, interpolation, worktree, Studio, version, persona, workspace SOUL, rootfs. They check that the SOUL, persona and composed-workspace-SOUL digests pinned in `setup.ps1` match the files on disk, that every preflight-required resource is actually bundled, that no shipped `.ps1` interpolates a variable the file never defines, that the bundled bytes are the committed bytes, that the embedded Studio payload and the bundled Ubuntu rootfs are the pinned ones, and that the two version literals agree. Each one fails the build on drift and none of them auto-correct. The version gate has a second half that cannot run until after compilation: the compiled digest must not contradict a version already recorded in `released-versions.tsv`.
```

**Reason.** The count was seven; the real count is nine. Re-derived two ways, and both
agree. `grep '^# --- ' scripts/build_release.ps1` returns nine `Pre-build gate:` section
headers plus one `Same gate, second half` and one `Version gate, enforcement half`, which
are the two halves of the version gate and not separate gates. Independently, the build
stamp written at `scripts/build_release.ps1:691` records
`gatesPassed = @('soul','bundle','interpolation','worktree','studio','version','persona','workspace-soul','rootfs')`,
nine entries. The old sentence also omitted the interpolation and worktree gates from its
description of what the gates check, which is why the count and the description were both
corrected in one edit. The script's own header comment already said "nine".

### `README.md`, the smoke-check count (BUNDLED)

**Confirmed correct, not corrected.** The README says the script runs 19 checks.
`grep -c "^\s*Check '" smoke-test.ps1` returns 26. Nineteen of those run by default;
the seven numbered 20 to 26 sit inside `if ($AgentChecks -and $grantsLib -and -not
$isSystem)` at `smoke-test.ps1:314` and run only when the opt-in switch is passed. The
command block printed immediately above the count passes no switch, so 19 is the correct
number for what the README shows. A clarifying paragraph was **added** naming the seven
opt-in checks, because the README gave no hint they existed.

**Added, verbatim:**

```
> Seven further checks, numbered 20 to 26, run only with `-AgentChecks`. They
> drive real agent turns to verify the grant boundary from the agent's own point
> of view. They need a working provider key and a running gateway, they are slow,
> and they are opt-in for that reason. The 19 above are what the command shown
> here runs.
```

### `README.md`, installer size and the OpenClaw pin (BUNDLED)

**Both confirmed correct, not corrected.** The `~440 MB` at line 49 matches the
`440594967` bytes recorded for 1.4.4 in `released-versions.tsv` (440.6 MB decimal). The
`OpenClaw 2026.4.27` pin at line 28 matches the version named in `resources/post-install.ps1`
lines 178 to 186 as "our pinned version".

### `SUPPORT_MATRIX.md` (NOT bundled, no divergence)

Seven answers and three "biggest drop-off risk" lines corrected. This file had never been
revised after ClawChat was bundled and the desktop icon repointed at it, so its
non-technical personas were all being told to skip the desktop icon and use
`openclaw chat` from a Linux terminal. That is the single largest concentration of false
statements about reaching the agent found anywhere in the tree. Two further stale claims
were found and are flagged in a new header rather than corrected, because they are
outside the scope of the pass that found them: the security-researcher Q4 says the `.exe`
is unsigned, and the retail-investor Q5 places the API key's resting home in Windows
Credential Manager.

### `CLAUDE_ClawFactory.md` lines 323 and 440 (NOT bundled, no divergence)

Two surviving descriptions of `resources/launcher.ps1` as the "desktop shortcut", left
behind when section 14.4 was corrected in `2b3dec4`. Both now say the script is bundled
and that no shortcut invokes it. This is the WHO problem the census exists to catch: the
claim was fixed in one of three places it appeared.

---

## What was deliberately left alone

`resources/launcher.ps1:14` still opens with
`# launcher.ps1 — desktop shortcut entry point.` It is stale for the same reason section
14.4 was. It is left alone here because `launcher.ps1` **is** a bundled, shipped script:
editing it changes shipped bytes, which is a release decision and not a documentation
fix. It is carried into `docs/V1_5_BACKLOG.md`.

---

## How this resolves

`scripts/build_release.ps1` compiles `ClawFactory-Secure-Setup.iss`, which sources
`README.md` from the working tree. The first v1.5 build therefore ships the corrected
`README.md` and closes the divergence with no further action. This page should be marked
resolved at that point, not deleted: the record of what a v1.4.4 installation contains
outlives the divergence.
