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

- **`resources/launcher.ps1` lines 14 to 20.** A known false claim now **deliberately
  retained in shipped bytes**. It is not one line. It is a seven-line header block
  carrying four separate false assertions. Quoted verbatim, exactly as it stands in the
  file, so this entry can be read without opening it:

  ```
  # launcher.ps1 — desktop shortcut entry point.
  #
  # Wired in by the [Icons] entry in ClawFactory-Secure-Setup.iss. Runs as the
  # end user (not admin) when they double-click the ClawFactory icon. The
  # shortcut starts PowerShell with -WindowStyle Hidden, so this script must
  # never spill console output. All user-facing errors come through a Windows
  # MessageBox dialog.
  ```

  **What is false, assertion by assertion, checked against `ClawFactory-Secure-Setup.iss`:**

  | Assertion | Reality |
  |---|---|
  | "desktop shortcut entry point" | The desktop shortcut's entry point is `{app}\ClawChat.exe` |
  | "Wired in by the `[Icons]` entry" | **No `[Icons]` entry invokes this script.** There is no such entry to be wired in by |
  | "when they double-click the ClawFactory icon" | Double-clicking that icon runs `ClawChat.exe`. This script is not reached |
  | "The shortcut starts PowerShell with `-WindowStyle Hidden`" | `grep -c "WindowStyle Hidden"` over the entire `.iss` returns **0**. No shortcut has ever passed that flag in the current script |

  The last one is the worst of the four, because it is a specific, checkable, operational
  detail that is simply not in the installer at all, and it is the premise for the
  following sentence's rule that the script must never write to the console.

  **It is a candidate for release-notes disclosure as well as for correction**, and that
  is a decision, not a foregone conclusion. The case for disclosing: it is a shipped file,
  it is auditable, "no telemetry, fully auditable PowerShell" is a claim this product makes
  in its own README, and a reader auditing `launcher.ps1` against the `.iss` will find the
  contradiction in about a minute. The case against: the script is unreachable, so the
  block misdescribes something no customer executes, and disclosing it invites a reader to
  weigh a comment on dead code as heavily as a live control. **Not decided here.**

  It was deliberately not corrected on 2026-08-29 because `launcher.ps1` is a shipped
  script and editing it changes shipped bytes. **v1.5 changes shipped bytes anyway, so
  correct it then**, and decide the disclosure question at the same time.

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
| **Unsigned** installer size | any doc asserting a build size | The size column of the last row of `released-versions.tsv`. **This is the pre-signing size.** For 1.4.4 it is `440594967` |
| **Signed** installer size | any doc asserting a download size, and the release body | The `size` field of the published GitHub release asset. For 1.4.4 it is `440610608` |
| OpenClaw version pin ("2026.4.27") | `README.md` components section | The pinned version literal in the installer scripts |
| Bundled-file count, wherever asserted | any doc | Count of `Source:` lines in the `.iss` `[Files]` section |
| Agent count ("four agents") | `README.md`, `CLAUDE_ClawFactory.md`, `rename-agent.ps1` dialog | The agent list written by `resources/bootstrap.ps1` |

**A note on where it must read from.** The bundled-file count must come from the `.iss`,
not from a doc that lists bundled files, and the version must come from the `.iss` define,
not from a badge that another doc copied. The whole value of the gate is that it does not
consult prose. A staleness gate that derives one prose number from another prose number
is `docs/FAILURE_CATALOGUE.md` Class 10.

**A note on the two installer sizes, which is why they are two rows and not one.** Two
byte counts for v1.4.4 are in circulation and both are correct, of different artifacts.
Verified by execution on 2026-08-29, not inferred:

| Artifact | Size | SHA-256 |
|---|---|---|
| Unsigned, as the ledger records it | `440594967` | `548562c72d5261bc62d590df03746ea2bb52134a413e10d137b590e589fdcdea` |
| Signed, as published and as it sits in `Output\` | `440610608` | `6e65560325cb6d7d3fea204ebb72876b3b113cbbfe9f2fa4f94113237e9eb4d1` |

The published GitHub release asset and the local `Output\ClawFactory-Secure-Setup.exe` are
**byte-identical**: same size and same SHA-256. `Get-AuthenticodeSignature` on that file
returns `Status: Valid`, signer `CN=Bret Mckinney`, countersigned by
`CN=Microsoft Public RSA Time Stamping Authority`. The difference is **15641 bytes**, which
is the Authenticode signature block and its countersigned timestamp appended to the PE.
This confirms the expected explanation rather than assuming it.

**The gate must never compare one against the other**, and must fail loudly if a document
asserts a size without saying which artifact it means. The `~440 MB` in `README.md` happens
to be true of both, which is exactly the kind of coincidence that hides the ambiguity until
someone writes a precise number.

---

#### Sharpening, 2026-08-29: the complete number census, and what re-deriving it taught

**Still specification only. Nothing below was implemented.** The table above was written
from the numbers that were noticed. This section is the result of deriving **every**
self-describing number in the shipped and repository documents from the tree in one pass,
and it changes three of the derivations above.

**The complete census.** Ten numbers, each with the exact derivation the gate must use and
the value it produced on 2026-08-29.

| # | Number | Value on 2026-08-29 | Derivation, exactly |
|---|---|---|---|
| 1 | Build-gate count | **9** | The **length of the `gatesPassed` array literal** in `scripts/build_release.ps1`. See the warning below: the header count does **not** agree, and the previous spec said it must |
| 2 | Bundled-file count | **56** | `grep -c '^Source:'` over `ClawFactory-Secure-Setup.iss`, `[Files]` section only |
| 2b | Bundled **markdown** count | **4** | The `Source:` lines matching `.md"`. `README.md`, `resources/safety-rules.md`, `resources/persona.md`, `resources/orchestrator-prompt.md`. **`SECURITY_FINDINGS.md` is NOT bundled** and at least one close-out has said it is |
| 3 | Smoke-check count, default | **19** | `Check '` occurrences in `smoke-test.ps1` **before** the `if ($AgentChecks ...)` guard (line 317 today) |
| 3b | Smoke-check count, opt-in | **7** | `Check '` occurrences **at or after** that guard. Total in file: **26**. Three numbers, all correct, of different things |
| 4 | **Unsigned** installer size | **440594967** | Size column, last row of `released-versions.tsv` |
| 5 | **Signed** installer size | **440610608** | The `size` field of the published release asset, from the GitHub releases API. Confirmed equal to the length of `Output\ClawFactory-Secure-Setup.exe` |
| 6 | Version literal | **1.4.4** | `#define MyAppVersion` in the `.iss`, cross-checked against the last row of `released-versions.tsv` and against the `v1.4.4` badge on `README.md:3` (which carries it **twice on one line**) |
| 7 | Studio panel count, not-in-this-release | **7** of **11** | `docs/RELEASE_NOTES_v1.4.4.md:29`, `docs/RELEASE_v1.4.4_GITHUB_BODY.md:31`, `validation/MANUAL_CHECKS_studio.md` section 9. **Not derivable from this repository's tree** -- Studio is a separate repository. This row is a cross-document agreement check, not a derivation, and the gate must say so |
| 8 | Mojibake **file** count | **5** of 10 shipped `.ps1` | For each `.ps1` named in a `Source:` line: first three bytes are not `EF BB BF` **and** at least one byte falls outside `09 0A 0D 20-7E`. Hits: `setup.ps1`, `resources/post-install.ps1`, `resources/bootstrap.ps1`, `resources/rename-agent.ps1`, `resources/launcher.ps1` |
| 9 | Mojibake **customer-visible occurrence** count | **7** | Non-ASCII **characters** (not lines) on the four customer-reaching lines: `rename-agent.ps1:21` (2), `:25` (2), `:29` (1), `bootstrap.ps1:128` (1), `:226` (1) |
| 10 | OpenClaw version pin | **2026.4.27** | The pinned version literal in the installer scripts |

**Correction 1 to the spec above: the build-gate cross-check as written FAILS TODAY, and
the reason is not drift.** The previous spec says to count `^# --- Pre-build gate:` headers
and cross-check against the `gatesPassed` array, "**Both, and they must agree**". They do
not. The header count is **8**; the array has **9** entries. Nothing is stale: the header
at `scripts/build_release.ps1:527` reads *"the persona and the COMPOSED workspace SOUL"* --
**one header covering two gates**, `persona` and `workspace-soul`. A gate implemented from
the spec as written would fail the build on a correct tree, on its first run.

This is the second-order form of the defect the whole page is about. The rule *"derive it,
never trust the prose"* was applied, a derivation was written down, and **the derivation
itself was never run.** `docs/FAILURE_CATALOGUE.md` Class 10 is audit instruments carrying
the defect they audit; this is a *specification* carrying it. **The array is the authority;
the header count is advisory and must be reported as a warning, not a failure.**

**Correction 2: number 7 is not derivable and must not pretend to be.** Every other row
reads a file in this repository. The Studio panel count reads three documents that agree
with each other, describing a repository whose source is elsewhere. A gate that treats it
as a derivation is deriving one prose number from another prose number, which the note
above already names as Class 10. It stays in the census because the number has now been
asserted wrongly more than once -- see `docs/FAILURE_CATALOGUE.md` entry 12.2 -- but it is
an agreement check between three named files and must be labelled as one.

**Correction 3: the scanner for numbers 8 and 9 must not use `grep -P`, and must be
canaried before any clean result is believed.** Re-deriving the mojibake census on this
machine, the obvious pattern -- a `grep -cP` with a negated hex character class, run under
`LC_ALL=C` -- returned **0 for all ten shipped scripts**, i.e. a completely clean tree. It
was wrong. `grep -P` on this platform refuses under `LC_ALL=C` with *"grep: -P supports
only unibyte and UTF-8 locales"* and exits **2**, and the surrounding `|| echo 0` in the
loop turned that refusal into a reported zero. The clean result was a **failure to run,
presented as a pass**, on the exact defect class this gate exists to catch.

It was caught only because the preamble rule was applied: an em dash was planted in a copy
of a clean shipped script and the pattern was required to find it **before** the clean
result was believed. It did not. A byte-value scan (`od -An -v -tu1`, filter for values
above 126) found 3 bytes in the canary and 0 in the control, and then reproduced the
published census exactly: 10 shipped scripts, 5 affected, same files, same line numbers.

**Three requirements follow, and they are not optional:**

1. **The gate matches on byte values, never on a regex engine's character classes**, and
   never on a literal non-ASCII character in its own source (already required above, for a
   different reason -- entry 10.4).
2. **The gate carries a planted canary and a clean control, and runs both in the same
   invocation as the real scan.** A canary run separately is a second measurement of a
   different moment.
3. **A scanner that exits non-zero is VOID, never clean.** The `|| echo 0` that swallowed
   the failure is the whole defect. Any harness step that converts a non-zero exit into a
   count must be treated as absent.

#### 4b. The site download-link check. **A POST-RELEASE ASSERTION, not a derivation**

Recorded separately, deliberately. Every number in the census above is derived from bytes
in this repository. **This one is not derivable at all.** It is an HTTP reading against a
surface built from a different repository, and folding it into the staleness gate would put
a network call inside a lint and would let a transient 502 fail a documentation check.

**What it asserts.** After a release is published, and only then: a `HEAD` request to

```
https://github.com/BuzzardsBay/clawfactory-secure-setup/releases/latest/download/ClawFactory-Secure-Setup.exe
```

must return **200**, following redirects, with a `Content-Length` equal to the **signed**
size (census row 5) of the release just published.

**Why the size and not just the 200.** A 200 proves a file is served. Only the size proves
it is *this* release's file. `latest` moves; a stale CDN edge or a failed asset upload can
serve the previous release's binary under a 200 for some time. On 2026-07-21 this project
watched a CDN serve a stale page across 32 consecutive polls.

**Why it belongs to the release, not to the build.** It cannot pass before publication --
the asset does not exist -- so it can never be a pre-build gate. It is the last step of
cutting a release, after the asset is attached, and its failure mode is "the three download
buttons on `clawfactory.app` are 404ing right now", which is a release incident and not a
documentation defect.

**Failure means the obligation in item 6 was broken**, almost always by the asset having
been attached under a different filename. Fix the release, or fix the site -- in the same
window, not next week.

**This assertion has no positive control and cannot easily be given one**, because the
negative case is a real 404 against a public URL. State that limitation rather than
implying the reading is as strong as a gated measurement. The nearest available control is
to request a filename known not to exist and require **404**, in the same run, which proves
the reading distinguishes present from absent. **Do that.** A `HEAD` that returns 200 for
everything, including a name that cannot exist, is measuring a redirect, not an asset.

---

### 5. The `ClawFactory Dashboard` shortcut, card `#311`. **DELETE IT, do not fix it**

Added 2026-08-29 by the documentation-reconciliation job. Card `#311` was raised the same
day at priority 1, **product severity, not documentation severity**.

**What ships.** `ClawFactory-Secure-Setup.iss` `[Icons]`, verbatim:

```
Name: "{group}\ClawFactory Dashboard"; \
  Filename: "{sys}\cmd.exe"; \
  Parameters: "/c start http://127.0.0.1:8787"; \
  WorkingDir: "{app}"; \
  Comment: "Open ClawFactory dashboard in browser (gateway must be running)"
```

A Start Menu entry, shipped in v1.4.4, that opens the browser dashboard in one click, under
hover text that invites it and warns of nothing.

**Why it is a dead end, and this half is not in doubt.** The dashboard is device-pairing
gated — `SUPPORT_MATRIX.md:26`, grounded in the gateway's Ed25519 device-identity connect —
and **the installer ships no pairing flow and no explanation of one.** A first-run user who
clicks it reaches a surface they cannot get past, from a label promising a dashboard.

**Why deletion and not a fix.** Shipping a pairing flow is a feature, and a feature for a
surface nobody has asked for and nobody has measured. Removing five lines from `[Icons]`
costs nothing, removes a one-click dead end from the Start Menu, and leaves the dashboard
reachable by anyone who types the URL. Nothing else in the product references the shortcut.
The `Comment:` string is the only place the product advertises the dashboard at all.

**What deleting it does NOT do.** It does not close the measurement question below, and it
does not make the `:8787` surface safe or unsafe. It removes an invitation, nothing more.

**Scope note.** This changes `[Icons]`, which is shipped bytes, so it cannot be done outside
a build. v1.5 changes shipped bytes anyway.

**The open measurement question is NOT recorded here**, deliberately, because a v1.5
planning page is not what a validation cycle reads. It is in
`docs/VALIDATION_PREAMBLE.md`, under "Open measurements owed by the next validation cycle".

### 6. The site download links are coupled to the asset filename. **A RELEASE OBLIGATION**

Added 2026-08-29. This is not a v1.5 work item; it is a **standing obligation on every
future release**, recorded on the page a person cutting a release is most likely to open.

`clawfactory.app` carries **three** download buttons. Since the 2026-08-29 site change they
no longer point at the release page. All three point at the file:

```
https://github.com/BuzzardsBay/clawfactory-secure-setup/releases/latest/download/ClawFactory-Secure-Setup.exe
```

`/releases/latest/download/<name>` resolves **by filename**. If a release publishes its
asset under any other name, all three buttons return **404**. No gate catches it: the
filename lives in `BuzzardsBay/clawfactory-site`, a different repository, and nothing in
this repository's build reads it.

**The obligation, in one line:** *every release must attach its installer as exactly
`ClawFactory-Secure-Setup.exe`, or the site's three download buttons must be changed in the
same window.*

`OutputBaseFilename=ClawFactory-Secure-Setup` in the `.iss` produces that name today, so
the obligation is satisfied by not changing that line. It is written down because it is
satisfied by accident rather than by a check.

**Verified 2026-08-29**, and this is an HTTP reading, not a tree derivation: a `HEAD` on
the download URL returns `200` with `Content-Length: 440610608`, matching the published
signed asset. The corresponding **post-release assertion** is specified in item 4 below.

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
