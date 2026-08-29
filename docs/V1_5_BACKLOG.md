# v1.5 backlog

Written 2026-08-29, so that v1.5's certain contents stop living in chat memory and
handoff prose. Every number on this page was re-derived from the tree on the day it was
written; where a prior record is quoted, it is quoted as a prior record and the
re-derivation is shown beside it.

Nothing here is a decision about scope. The **Certain** section is certain only in the
sense that each item requires a rebuild anyway, so shipping v1.5 without it costs a
second rebuild. The **Undecided** section is explicitly undecided and carries no
recommendation.

---

## Certain

### 1. The mojibake, card `#296`

**What it is.** Windows PowerShell 5.1 decodes a `.ps1` with no byte-order mark using
the system ANSI codepage, not UTF-8. A file saved as UTF-8 without a BOM therefore has
every multi-byte character rendered as its individual bytes reinterpreted as ANSI. An em
dash (`E2 80 94`) becomes three garbage characters.

**The shipped scripts that are UTF-8 without a BOM.** Re-derived 2026-08-29 by scanning
every `.ps1` named in a `Source:` line of the `.iss` `[Files]` section, testing the first
three bytes for `EF BB BF` and counting bytes outside the printable-ASCII range. Ten
`.ps1` files are shipped. **Five carry non-ASCII bytes with no BOM:**

| File | Non-ASCII lines | Customer-visible? |
|---|---|---|
| `resources/rename-agent.ps1` | 5 (lines 4, 10, 21, 25, 29) | **Yes.** Lines 21, 25 and 29 are the `MessageBox` body and title |
| `resources/bootstrap.ps1` | 6 (lines 8, 18, 114, 128, 199, 226) | **Yes.** Lines 128 and 226 |
| `resources/launcher.ps1` | 10 | No. All ten are comments |
| `resources/post-install.ps1` | 3 (lines 158, 187, 220) | No. All three are comments |
| `setup.ps1` | 1 (line 58) | No. Comment |

The other five shipped `.ps1` (`clawfactory-grants.ps1`, `clawfactory-stop.ps1`,
`switch-provider.ps1`, `uninstall.ps1`, `smoke-test.ps1`) carry no non-ASCII bytes at
all and are clean.

**Count of shipped files affected: 5.** This matches the count in the box D completion
close-out and was re-derived independently rather than copied from it.

**The customer-visible locations.** Counted by non-ASCII character, not by line, since a
single line can carry two em dashes:

| Where it lands | Source | Occurrences |
|---|---|---|
| The **"Rename Your Assistant" dialog body**, opened from the Start Menu shortcut of that name | `rename-agent.ps1:21` (2), `rename-agent.ps1:25` (2) | 4 |
| The **title bar of that same dialog** | `rename-agent.ps1:29` (1) | 1 |
| A written `agent.md` inside the sandbox, in the stub-agent explanation | `bootstrap.ps1:128` (1) | 1 |
| A `WARN` line reaching the console and `%ProgramData%\ClawFactory\install.log` | `bootstrap.ps1:226` (1) | 1 |

**Count of customer-visible occurrences: 7**, across 2 files and 4 distinct surfaces.
Each occurrence is a single em dash, `E2 80 94`, three bytes. This also matches the prior
record and was re-derived independently.

**Not affected.** Neither uninstall dialog, measured both ways across two independent
invocations in box D. The `.iss` itself carries zero non-ASCII bytes. The four bundled
`.md` files are read by markdown viewers, not by PowerShell, so their non-ASCII content
is not mojibake and is not in scope.

**Severity.** Cosmetic. Nothing about the sandbox, the firewall, the guards, the gateway
or containment is implicated. The meaning survives; it looks broken. It is worst in the
`rename-agent` dialog, whose only job is to explain a product decision to a customer.

### 2. `README.md` findings that could not be closed

`README.md` is bundled (`.iss:46`) and carries its own Start Menu shortcut (`.iss:186`).
The badge and gate-count corrections made on 2026-08-29 reach a customer only at the next
build. See `docs/POST_RELEASE_DOC_CORRECTIONS_v1.4.4.md`.

**Nothing in `README.md` was left uncorrected.** Every self-describing number in it was
re-derived and is either corrected or confirmed. The open item is not a finding but a
delivery: the corrected file has to be compiled into an artifact before it is true for
anyone who installed v1.4.4.

One related item is genuinely open and is **not** in `README.md`:

- **`resources/launcher.ps1:14`** still opens with `# launcher.ps1 - desktop shortcut
  entry point.` No `[Icons]` entry has invoked it since the desktop icon was repointed at
  `ClawChat.exe`. It was deliberately not corrected on 2026-08-29 because `launcher.ps1`
  is a shipped script and editing it changes shipped bytes. **v1.5 changes shipped bytes
  anyway, so correct it then.**

### 3. The tenth build gate

**Specification only. Do not implement in the session that wrote this page.**

**Name.** `encoding`. It becomes the tenth entry in the `gatesPassed` array written into
the build stamp at `scripts/build_release.ps1`, alongside `soul`, `bundle`,
`interpolation`, `worktree`, `studio`, `version`, `persona`, `workspace-soul` and
`rootfs`.

**What it asserts.** For every `.ps1` file named in a `Source:` line of the `.iss`
`[Files]` section: **either the file's first three bytes are `EF BB BF`, or the file
contains no byte outside the range `0x09, 0x0A, 0x0D, 0x20-0x7E`.** A file that satisfies
neither fails the build.

**Why that shape and not "must have a BOM".** Requiring a BOM on every shipped `.ps1`
would fail five files that are correct today and would churn bytes for no reason. The
defect is not the absence of a BOM; it is the combination of a BOM's absence with content
that needs one. The gate is written as that combination.

**Why not "must be ASCII".** That would be a stricter and simpler gate, but it forbids a
legitimate future in which a dialog carries a non-ASCII character deliberately and the
file is saved with a BOM to carry it. The gate should permit the correct thing, not only
the minimal thing.

**What a failing input looks like.** `resources/rename-agent.ps1` exactly as it stands on
2026-08-29: first three bytes are `23 20 72` (`# r`), not `EF BB BF`, and line 21 contains
the byte sequence `E2 80 94`. The gate must name the file, the line and the byte offset,
and it must say which of the two conditions failed, because "no BOM" and "has non-ASCII"
are separately actionable and the fix differs.

**What a passing input looks like.** Two shapes must both pass, and the gate is not
correct until both have been confirmed to:

1. `resources/uninstall.ps1` as it stands: no BOM, no non-ASCII byte. Passes on the
   second condition.
2. Any file whose first three bytes are `EF BB BF`, regardless of what follows. Passes on
   the first condition.

**Calibration, which is not optional.** This gate is a probe for a text-encoding defect,
and the file that holds the gate is itself a `.ps1`. `docs/FAILURE_CATALOGUE.md` entry
10.4 records that the first sweep written to measure this very defect contained the
defect: it held the character it was searching for, as a literal, in a file saved the
same way. **The gate must be written to match on byte values, never on a literal
non-ASCII character in its own source**, and it must be canaried by planting one em dash
in a copy of a clean shipped script and confirming the gate fails on it, before any clean
result from it is believed.

**Where it runs.** Before compilation, with the other pre-build gates. It is a lint on
source text and has no dependency on the worktree or bundle gates, so it can run early;
placing it immediately after the interpolation gate groups the two source-text lints
together.

### 4. A mechanical staleness gate

**Specification only. Do not implement in the session that wrote this page.**

**The problem it solves.** On 2026-08-29 four self-describing numbers in `README.md` were
checked by hand. One was wrong. It had been wrong through five releases, because nothing
re-derives it and a human reading the sentence has no reason to doubt it. Every number
corrected by hand on that day will drift again.

**What it is.** A script that reads the tree, derives each number below from its source,
compares it to the number written in the prose, and fails on a mismatch. **It re-derives;
it never rewrites.** Same discipline as every build gate: fail on drift, never
auto-correct, because a silent rewrite of a prose sentence is worse than a stale one.

**Whether it is a build gate.** Open. It should run in CI or as a `-Check` mode on
demand. Wiring it into `build_release.ps1` would block a release on a documentation
typo, which may or may not be wanted. Decide when implementing.

**The numbers it must derive, and the tree source of each:**

| Number in prose | Where the prose is | Tree source it must be derived from |
|---|---|---|
| Build-gate count ("nine pre-build gates") | `README.md` build section | Count of `^# --- Pre-build gate:` headers in `scripts/build_release.ps1`, cross-checked against the length of the `gatesPassed` array literal in the same file. **Both, and they must agree** |
| Version badge (`v1.4.4`) | `README.md` line 3, twice on the same line | `#define MyAppVersion` in `ClawFactory-Secure-Setup.iss`, cross-checked against the last row of `released-versions.tsv` |
| Smoke-check count ("19 checks") | `README.md` smoke-test section | Count of `Check '` invocations in `smoke-test.ps1` that are **not** inside the `if ($AgentChecks ...)` block. The opt-in count (7) is a second, separately derived number |
| Numbered smoke-check list (items 1 to 19) | `README.md` smoke-test section | The `Check '<name>'` strings in `smoke-test.ps1`, in source order. The gate must compare the **list**, not only its length, because a reordering is invisible to a count |
| Installer size ("~440 MB") | `README.md` installation step 1 | The size column of the last row of `released-versions.tsv` |
| OpenClaw version pin ("2026.4.27") | `README.md` components section | The pinned version literal in the installer scripts |
| Bundled-file count, wherever asserted | any doc | Count of `Source:` lines in the `.iss` `[Files]` section |
| Agent count ("four agents") | `README.md`, `CLAUDE_ClawFactory.md`, `rename-agent.ps1` dialog | The agent list written by `resources/bootstrap.ps1` |

**A note on where it must read from.** The bundled-file count must come from the `.iss`,
not from a doc that lists bundled files, and the version must come from the `.iss` define,
not from a badge that another doc copied. The whole value of the gate is that it does not
consult prose. A staleness gate that derives one prose number from another prose number
is `docs/FAILURE_CATALOGUE.md` Class 10.

---

## Carried, not scheduled

These are open conditions, not v1.5 work items. They are here so that v1.5 planning does
not rediscover them as new.

### `G2.6`, card `#305`

The post-approval payload-binding comparison, the end-to-end "the approved bytes are the
bytes that arrived" check, **has never been measured on any release of this product, on
any machine.** The surrounding mechanism is proven and enumerated by name: enqueue,
approval, single-use approval, payload hash binding at approval time, receipt, staging
purge, and refusal of a replayed approval.

The reason it was never measured is **a rig transport limitation, stated in those
terms**, and not a product finding: the broker correctly refuses cleartext against a plain
sink, and the bundled runtime will not trust a throwaway authority against an encrypted
one, so nothing ever arrived and there was nothing to compare. Closing it needs a rig that
can terminate a real encrypted transport with an authority the bundled runtime trusts.

### `#261`, intermittent GitHub-family fetches

With the toolchain toggle on, a GitHub-family fetch may intermittently fail and succeed on
retry. Measured across eight hosts: four at 12/12, `api.github.com` at 6/12. **The
mechanism is INFERRED and is labelled so in the sentence that makes the claim.** The split
is measured; the cause is not. It does not affect the provider route, which measured 12/12
with a control at 0/12 in the same run.

---

## Undecided

**These are held open pending the first external install and are not to be decided from
inside a build session.** No recommendation is attached to any of them, deliberately.
A build session sees the product from inside its own construction and is the worst
available vantage point for judging what a person who has never seen it needs.

- **The Studio chat panel.** UNDECIDED.
- **The remaining "not in this release" Studio panels. There are SEVEN of them, not six.**
  UNDECIDED. The count is re-derived from `docs/RELEASE_NOTES_v1.4.4.md:29` and
  `docs/RELEASE_v1.4.4_GITHUB_BODY.md:31`, both of which say seven of Studio's eleven
  panels are not in this release, and from `validation/MANUAL_CHECKS_studio.md` section 9.
  **This exact off-by-one has now occurred twice.** The v1.4.4 release-prep close-out
  section 1.2 is titled "The card names six not-in-this-release panels. There are seven",
  and the handoff document that produced this backlog reproduced the same six. The number
  is written here so the third occurrence has somewhere to be checked against.
- **The skills model.** UNDECIDED.
