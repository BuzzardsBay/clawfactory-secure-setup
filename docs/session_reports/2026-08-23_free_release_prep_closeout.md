# CLOSE-OUT: free-release preparation, card #265

Session 2026-08-23. Licensing removal, the licence swap, and the honest copy audit.
No VM was provisioned. No build was signed, tagged or published.

Repositories touched: `ClawFactory-Secure-Setup` (25 files + `NOTICE`),
`ClawFactory-Studio` (5 files + `NOTICE` + `.gitattributes`), and
`clawfactory-site` (`index.html`, **left uncommitted on purpose**, see section 8).

---

## 1. Task accounting

| Task | State |
| --- | --- |
| 1. Licence census, and removal | **DONE with evidence.** Section 2. |
| 2. Licence file swap to Apache-2.0 | **DONE.** Section 3. |
| 3. Honest copy audit, every public surface | **DONE.** Section 4, table in 4.2. |
| 4. `SECURITY_FINDINGS.md` partition + v2 roadmap | **DONE.** Section 5. |
| 5. `clawagent-setup` recommendation | **DONE, report only, nothing changed.** Section 6. |
| Guard 4 | Out of scope by instruction. Nothing done, nothing carried. |

Nothing was silently dropped. Two items are deliberately left for the final build
job and are named in section 7 rather than done here.

---

## 2. Task 1: the licence-check census, and what was removed

### 2.1 The census, by execution

`grep -ril` over `*.ps1 *.iss *.js *.json *.ts *.mjs` tree-wide, plus a targeted
symbol sweep, plus the same sweep across the Studio repo.

| Site | What it was | Removed |
| --- | --- | --- |
| `ClawFactory-Secure-Setup.iss` | 3 consts (incl. `https://api.clawfactory.app/activate`), 3 vars, `SanitizeLicenseKey`, `GetStableMachineId`, `ValidateLicenseKey`, `ReadStoredLicenseKey`, `BuyButtonClick`, the `LicensePage` wizard page, the Buy button, the `/SILENT` gate, 3 call sites | yes, 175 lines |
| `resources/uninstall.ps1` | HKLM read + **outbound `POST /deactivate`** at step 7 | yes; steps 8, 9 renumbered to 7, 8 |
| `scripts/azure-validate.ps1` | `/LICENSE=` arg, machine-id capture, **outbound `POST /deactivate`** | yes |
| `validation/job3-teardown.ps1` | **outbound `POST /deactivate`** + the whole machine-id recovery apparatus that existed only to feed it | yes |
| `validation/job3-validate.ps1` | `-LicenseKey`, machine-id capture and threading | yes |
| `validation/job3-probe.ps1` | `-LicenseKey`, `/LICENSE=` | yes |
| `validation/interim-v120-phase1.ps1` | `-LicenseKey`, `/LICENSE=` (**the live harness**) | yes |
| `validation/interim-v120-validate.ps1` | `-LicenseKey` passthrough | yes |
| `validation/diag/g4-probe.ps1` | `-LicenseKey` passed to phase1 | yes |
| `validation/wrapper-builder.ps1` | `-LicenseKey` in the built command | yes |
| `validation/test-wrapper-render.ps1` | 3 structural assertions riding on the `-LicenseKey` token | re-pointed, see 2.4 |
| **`setup.ps1`** | **zero references.** Verified by count. | n/a |
| Studio | zero licence-check code | n/a |

**The single most important finding: the licence check was install-time only.**
`setup.ps1`, 211 KB and the entire install body, contained the string `licen` zero
times. There was no agent-side check, no gateway check, no periodic re-verify. The
comment at the old `.iss:605` claimed `ReadStoredLicenseKey` was used "by
post-install for re-verify on launch"; it was called nowhere, and had been false
since v1.0.30.

### 2.2 The failure paths as they were, named from the code

- **Interactive**: `NextButtonClick` called `ValidateLicenseKey`, a 10s WinHTTP POST
  to `api.clawfactory.app/activate`. Anything but HTTP 200 containing `"valid":true`
  returned False and a `MsgBox` blocked Next. **The install could not start.**
  Network errors, timeouts and a down server all failed closed, so an offline user
  could not install.
- **Silent**: the same call inside `InitializeWizard`, then `Abort` on failure. The
  install died before any page rendered.
- **Uninstall**: best-effort `POST /deactivate`, try/catch, non-fatal. Advisory.
- **Agent runtime**: nothing at all.

### 2.3 The middle option, assessed rather than assumed

Making `ValidateLicenseKey` return True without the WinHTTP call *does* remove the
outbound call, so it is not disqualified by the "stopped checking but still calls
home" test. It is disqualified by a different one: it leaves a wizard page demanding
a key, a Buy button pointing at a purchase page, and an error dialog naming machine
slots, all of it dead. A reader auditing the source finds a licence client that
pretends to validate. For a release whose deliverable is honesty that is worse than
either end state. **Rejected. Full removal chosen and executed.**

### 2.4 The one entangled test, and how its strength was preserved

`validation/test-wrapper-render.ps1` asserted that `-LicenseKey` sits on the same
physical line as the redirect. Its real subject is the cfv-149 defect (a multi-line
concatenation inside an array literal, which split the probe command from its
redirect and lost a whole run's evidence), not the token. All three assertions were
re-pointed to `-SeedKeyTarget`, which now occupies the same last-argument position.

**Calibrated, not assumed.** The re-pointed assertion was verified by reinjecting the
real defect (probe command and redirect as separate array elements) and re-running:

```
CALIBRATION_EXIT=1
FAIL  cmdLines has exactly 4 elements (cfv-149 produced 6)
FAIL  probe line contains the redirect on the SAME line
FAIL  on that line, -SeedKeyTarget precedes the redirect (one command)
FAIL  line 3 writes JOB3_DONE
```

The file was reverted clean afterwards (`git status` empty for it). Full suite with
the real file: **ALL RENDER TESTS PASSED, exit 0.**

A first calibration attempt used the wrong defect shape (a `+` continuation in an
assignment, which is valid PowerShell and produces a *correct* wrapper). It returned
exit 0, which was the right answer rather than a blind test, and it is recorded here
because a calibration that passes for the wrong reason is exactly the failure this
discipline exists to catch.

### 2.5 Proof that no outbound licence call remains, by execution

**The instrument I discarded, and why.** The obvious proof was to scan the compiled
`.exe` for `api.clawfactory.app`. Calibrated first: the shipped v1.3.5 binary returns
**zero hits for `api.clawfactory.app`, `clawfactory.app`, `LicenseKey` and
`WinHttpRequest`**, all four of which are demonstrably in it. Inno compresses the
`[Code]` section. Confirmed by compiling a throwaway installer carrying a unique
marker string under both `lzma2` and `Compression=none`: invisible in both.
**The artifact string scan is a blind instrument. Recorded VOID with that reason and
not used.** A naive run of it would have produced a clean-looking false pass.

**The instrument used instead: the Pascal compiler.** ISCC resolves the whole `[Code]`
unit, so any surviving reference to a removed licence symbol fails the compile. This
is stronger than grep, which can only see the text it was asked about.

Calibration, run first:

```
$ ISCC dangling.iss          # a stub whose only body is Result := ValidateLicenseKey('CF-TEST')
Error on line 10 ... Unknown identifier 'ValidateLicenseKey'
Compile aborted.
ISCC_EXIT=2
```

Measurement, on the real file after all edits:

```
$ ISCC ClawFactory-Secure-Setup.iss
Successful compile (61.281 sec).
ISCC_EXIT=0
```

Supporting facts, each established by execution rather than by reading the diff:

- `grep -i licen ClawFactory-Secure-Setup.iss` returns exactly one line, the
  `Source: "LICENSE"` bundle entry.
- `grep WinHttpRequest ClawFactory-Secure-Setup.iss` returns exactly **one** hit,
  `LiveCheckKey`, which GETs the chosen provider's model list and goes nowhere else.
- `grep -i "licen|deactivat" resources/uninstall.ps1` returns nothing.
- All 10 edited PowerShell files parse clean under
  `[System.Management.Automation.Language.Parser]::ParseFile`.
- The only outbound primitives left in shipped resources are
  `resources/launcher.ps1` (a localhost `/status` poll) and `LiveCheckKey` above.

**What this proof does NOT cover, stated plainly.** It is a source-and-compiler
proof, not a packet capture. Running the installer far enough to reach where the call
used to be means installing, which cannot be done safely on the operator's own
machine and belongs on a throwaway VM. Full assembled-build validation is the final
job (card #197) and is out of scope here by instruction. The probe that job should
run is specified in section 7.

---

## 3. Task 2: the licence swap

**PolyForm Perimeter 1.0.0 to Apache License 2.0.** PolyForm existed to prevent free
resale of a paid product; that premise is gone. The reasoning recorded in the commit
and in the README: attribution is the mechanism by which a free release builds a
reputation, Apache-2.0 requires it, and its patent grant makes organisations
comfortable evaluating the code. PolyForm signals a commercial product with the
commerce removed.

Nothing in the tree argued against the swap.

**Applied byte-identically.** `LICENSE` is the verbatim canonical Apache-2.0 text,
LF, brackets intact:

```
cfc7749b96f63bd31c3c42b5c471bf756814053e847c10f3eb003417bc523d30  Secure-Setup/LICENSE
cfc7749b96f63bd31c3c42b5c471bf756814053e847c10f3eb003417bc523d30  Studio/LICENSE
cmp: LICENSE identical
cmp: NOTICE  identical
```

That digest is the widely published digest of the canonical file, so the match is
checkable against a third party rather than only against itself. `NOTICE` carries the
copyright and is likewise byte-identical in both repos. Both are pinned `text eol=lf`
in both `.gitattributes` files, because a CRLF checkout would break the digest match
(this repo has been bitten by exactly that class of defect before). `NOTICE` was added
to the installer's `[Files]` so it ships beside `LICENSE`.

**Studio's footer**, which has been wrong once before: the *built* bundle in
`backend/public` still said "MIT licensed" while the source said PolyForm. Source now
says `Frontier Automation Systems LLC · Apache-2.0`. The shipped Studio 1.3.0 artifact
still carries the old string, and that is section 7's problem, not a silent gap.

Also swapped, everywhere the old licence was asserted as current fact:
`README.md` badge and License section, `CONTRIBUTING.md` (which also called this a
"commercial product"), `PERSONAS.md` (4 sites), `SUPPORT_MATRIX.md` (2 sites),
`docs/index.html` footer, both Studio `package.json` files, and the public site footer.
Historical close-outs that record "PolyForm" as a past fact were left alone; they are
records, not claims.

**The Inno Setup licence position, reported not acted on.** Two facts, both
established by execution, and they are in tension.

The licence text installed on this machine
(`C:\Program Files (x86)\Inno Setup 6\license.txt`) reads:

> "Permission is granted to anyone to use this software for any purpose, including
> commercial applications, and to alter and redistribute it, provided that the
> following conditions are met..."

followed by four attribution and non-misrepresentation conditions, all of which a
normal Inno-built installer satisfies. **There is no non-commercial term in the
licence file.**

But the binaries do carry one. `ISCC.exe` and `Compil32.exe` both contain the UTF-16
string **"Non-commercial use only"**, sitting beside "Update entitlement ended" and
"Update entitlement ended but updated anyway". So Inno 6.7.x has paid entitlement
tiers and this machine runs the free one, which the product labels non-commercial.
Scan calibrated in both directions before it was trusted: a string the banner
certainly prints matched, and a planted sentinel that must be absent did not. An
ASCII-only scan initially found nothing, which is why the calibration mattered.

This corrects my own first reading of it in this session, not the standing note,
which had it right: the *banner* asserts non-commercial while the *licence text*
permits commercial use.

**Why it matters less now, not more.** The tension existed because ClawFactory was
sold. A free, Apache-2.0 release plausibly sits inside the non-commercial tier the
installed build is labelled for, so the free-release decision narrows this rather
than widening it. It gates nothing, it is the operator's call, and it is not a
release blocker.

---

## 4. Task 3: the honest copy audit

### 4.1 Surfaces enumerated

`README.md`, `SECURITY.md`, `SECURITY_FINDINGS.md`, `CONTRIBUTING.md`,
`SUPPORT_MATRIX.md`, `PERSONAS.md`, `docs/index.html`, the installer welcome and
acknowledgement pages, the API-key page copy, `resources/safety-rules.md`,
`resources/orchestrator-prompt.md`, `resources/clawfactory-fetchctl.js`,
`resources/clawfactory-toolchain.sh`, the Studio Web access / Approvals /
Recently-deleted / SMTP panels and footer, `CHANGELOG.md`, the GitHub repo
descriptions for all three repos, and the live site `index.html`.

### 4.2 The claim audit

| Claim as written | Surface | Mechanism | Evidence | What changed |
| --- | --- | --- | --- | --- |
| "Switching this off stops skill installation" | Studio Web panel, `fetchctl` usage text, `toolchain.sh` switch-off message | Advisory. The wording implied structural. | **Contradicted by a passing test.** cfv-169 `SK.3`, positive control fired in the same run: `openclaw skills install` exits 0 with the toggle off, `clawhub.ai` shares `216.150.1.1` with `openclaw.ai`, a permanent base host. | **Rewritten on all three surfaces.** Now says it stops GitHub and npm, and explicitly does *not* stop skill installation, and why. |
| "the `browser` tool is **structurally denied**" | `orchestrator-prompt.md`, `setup.ps1` comment | Gateway-path, not structural. Door 2 bypasses it. | Denial itself validated consumer-side (ERROR/ABSENT, not a no-op), cfv-0719p. | Reworded to name it as gateway-path, in the same class as the spend cap, with the egress allowlist named as the structural backstop. Both sites. |
| "restate the **five agents** you coordinate" | `orchestrator-prompt.md` | No mechanism. Simply false. | `setup.ps1` creates 4 agent dirs; 3 siblings are listed in the prompt itself. | "the three sibling agents you coordinate". |
| "Nothing leaves your machine without your permission" | live site, step 3 | False. The forbidden sentence shape. | The agent talks to a hosted model on every turn. | Replaced with the sandbox/grants statement plus the hosted-model boundary. |
| "Nothing leaves your machine except the API calls you configure" | live site, privacy section | Technically caveated, but headline reads as a data claim. | As above. | Replaced: names the provider call and says it carries whatever the agent read. |
| "It cannot read your files" | live site FAQ | False once a grant exists, and Studio's grant feature is described on the same page. | Grants mount Windows folders into `/workspaces`. | "It reads a Windows folder only when you grant that folder to it in Studio, and nothing else on your drives." |
| "ClawAgent: same security substrate ... same security" | live site FAQ | False. | `clawagent-setup` last pushed 2026-05-12; it has none of Guards 1 to 3, no gating proxy, no Studio. | Rewritten to say what ClawAgent is and what it does not have. |
| "allowlist ... your chosen AI provider's API plus the update sources" | live site FAQ (x2), `SECURITY.md` #2 | True but understated: address-scoped, and five provider endpoints are added unconditionally. | `setup.ps1:1394` base list; `AUX_HOSTS` at `setup.ps1:2188` is unconditional. | Address-scoping caveat added on the site; `SECURITY.md` now enumerates the real unrevocable set. |
| "50 GB free disk (Ubuntu rootfs + **Docker images** + ...)" | `README.md` | No mechanism. Docker was removed. | SECFIX_CLOSE_DOORS decision A. | Removed. |
| "rootless Docker" x5 | `PERSONAS.md` | Same. | Same. | Removed. |
| "Pricing: ClawFactory $149 / ClawAgent $49"; "One-time purchase" x3; "Is this a subscription?" | `README.md`, live site | n/a | Product is free. | Removed / rewritten to free and Apache-2.0. |
| "Four pre-staged agents ... each gets a role-specific `agent.md`" | `README.md` | Literally true, implies four working agents. | scout / builder / publisher are stubs (Phase 0 recon). | Kept, with "only the orchestrator carries a real working prompt; the other three are scaffolding". |
| Smoke test "Four `agent.md`" vs "all 5 agents" | `README.md` | Both true, looked contradictory. | `smoke-test.ps1:99` and `:169`; the fifth identity is `main`. | Clarified in place, no number changed. |
| Ten `[setup.ps1 line N](setup.ps1#LN)` deep links | `SECURITY.md` | The claims are true; **every anchor is wrong.** | `Step-EgressFirewall` cited at 347, actually 1390; `Step-WireProviderKey` 806 vs 3268; `Step-ApplySafetyRules` 764 vs 2787; and so on for all ten. `Step-ConfigureWslConf` is not even the real function name. | **All ten removed**, function names kept. A link that lands in the wrong place is a claim that cannot be traced. Function name typo fixed. |
| "Supported versions 1.0.x" | `SECURITY.md` | Stale. | Product is 1.3.5. | 1.3.x. |
| Badge "v1.0.45"; `SECURITY_FINDINGS` "applies to v1.0.45" | `README.md`, `SECURITY_FINDINGS.md` | Stale by 20 releases. | `.iss` MyAppVersion. | Both current. |
| Repo description: "rootless Docker ... MIT licensed" | GitHub, `clawfactory-secure-setup` | Two false facts. | As above. | Updated (repo is private; safe to change). |
| Guards 1, 2 and 3 absent entirely | `README.md`, `SECURITY.md`, `SECURITY_FINDINGS.md`, live site, installer | Under-claiming, which is its own accuracy failure. | The guards ship. | Added to all five, in the ratified wording. |
| "runs entirely on your machine" | Studio footer | Reads as a data claim next to a licence. | The agent talks to a hosted model. | "the sandbox runs on your machine; your agent talks to a hosted AI model". |
| "no telemetry" | `README.md` | **Was false while the licence call existed.** | The installer POSTed a machine GUID to `api.clawfactory.app` on every install. | Now true, and the README says so explicitly: no telemetry, no licence server, no account. |

**Claims removed for lack of evidence, rather than hedged:** the ten `setup.ps1`
line anchors; the `$149` / `$49` pricing table and the one-time-purchase framing; the
ClawAgent security-parity claim; "Docker images" and "rootless Docker" in six places;
"structurally denied" for the browser tool; "five agents".

### 4.3 The ratified sentences, shipped unsoftened

All three, plus the boundary, now appear on the installer welcome page, in the README
under "The three things it promises", and in the live-site controls table. The
acknowledgement checkbox now includes "anything my agent can read it can send to the
hosted AI model I chose". The existing Studio panel wording for email and deletion
already matched and was left alone; the Web access panel's ratified footnote was
already correct and was **not** touched, only the separate switch-breakage sentence
above it.

---

## 5. Task 4: `SECURITY_FINDINGS.md`

Rewritten. It now opens by saying it is for someone deciding whether to trust the
product, and it is explicitly partitioned:

- **Structural guarantees** (9 rows): file isolation, egress allowlist, inbound deny,
  no send path at the agent's identity, approval binding, quarantine hold, credential
  protection, safety-rules integrity, kill switch.
- **Gateway-path guarantees** (4 rows): spend cap, chat gating, safety-rules
  enforcement at turn time, and the browser-tool denial, which is newly listed here
  rather than being implied to be structural.

**Residuals, in plain language, all seven the job named:**

1. Same-identity runtime invocation (Door 2), accepted for v1, with actor model and
   harm ceiling.
2. Address scoping. Enforcement by address, not hostname. Anything co-hosted with
   something reachable is reachable. Permanent for v1, with the measured skill-install
   consequence written out.
3. The baseline route. The real unrevocable set is named host by host: nine base
   hosts, five unconditional provider endpoints, plus the chosen provider, plus eight
   default-on software-source hosts. **The job's brief said "ten hostnames"; the repo
   shows twenty-two on a default install**, and the document states the repo's number.
4. DNS is not gated.
5. Provider-key exfiltration. The gateway holds the credential and runs as the
   agent's uid.
6. Guard 1 covers deletion by name, not destruction. The hold is structural, the
   routing is not.
7. The build stamp is forgeable: advisory against an attacker, structural against
   process drift.

Plus **"Root ends everything"**, stated as the shape of the model rather than as a
defect, because "the agent is sandboxed" invites a stronger reading than is true.

**v2 roadmap entry added**, naming separate-identity agent isolation as the single
change that closes the most residuals on the page (Door 2, provider-key exposure, and
the promotion of all four gateway-path guarantees to structural), tracked as item #25
in `v1.1_backlog.md`. Door 2 now has a stated future rather than an accepted silence.

---

## 6. Task 5: `clawagent-setup`. Recommendation: **archive it, and do not make the
free release depend on it**

Nothing was changed. Visibility untouched, as instructed.

**What is in it** (read via the GitHub API, not from a local clone):

- Public. Last pushed **2026-05-12**, three months stale. Four releases, latest v1.0.4.
- `resources/ClawChat.exe`, **11.7 MB, committed into the repository as a blob.**
- `LICENSE` is MIT, which now disagrees with both other repos.
- `README.md` says "Security substrate: **Same as ClawFactory**" and "Upgrade to
  ClawFactory ... Available at https://clawfactory.app", which is the paid framing.

**What is embarrassing rather than merely unfinished.** Its shipped
`resources/safety-rules.md` tells the agent:

> "You run in Docker sandbox with network=none by default."

Docker was removed from the product line, and `network=none` was never true. Its
`resources/orchestrator-prompt.md` carries "Tool allowlist (**enforced by gateway**)"
and "Tool denylist (**enforced by gateway**)" over six names that are not real
OpenClaw tool names, so a `tools.deny` of them would be a no-op. That is the exact
overclaim this repository spent a release correcting, sitting in public under Bret's
GitHub account, with a downloadable installer next to it. It also instructs the agent
to "restate the five agents", the same fiction fixed here today.

**Recommendation: archive the repository** (read-only, releases still resolvable so
existing download links do not 404), and add one line to its README saying it is
superseded by ClawFactory and is no longer maintained. Reasoning:

- Free release inverts the privatise-it question but does not answer it. The reason to
  keep it public would be that it is a second free product. It is not: it is an old
  build whose security copy is now known-false, and a reader who finds it first will
  reasonably conclude that this is how the author writes security claims.
- Deleting or privatising it breaks existing links and looks like concealment, which
  is worse for a release whose deliverable is credibility.
- Archiving is honest, reversible, and cheap. If ClawAgent is ever wanted as a real
  free product it gets rebuilt from the current substrate, not resurrected.

**Alternative if archiving is unwanted:** fix the three false files in place first
(`safety-rules.md`, `orchestrator-prompt.md`, `README.md`) and cut a v1.0.5. That is
a small job but it is a *job*, and it is not this one.

---

## 7. Left for the final build job (card #197), named rather than done

1. **Studio must be rebuilt and repinned.** The Studio *source* now says Apache-2.0,
   drops "runs entirely on your machine", and drops "stops skill installation". The
   pinned `ClawFactory-Studio-Setup-1.3.0.exe` still carries the old strings.
   `scripts/build_release.ps1` carries a block stating that the pin is knowingly stale
   and naming the **three-part** change that must happen together: repin the digest,
   move `stops skill installation` and `PolyForm Perimeter 1.0.0` from the phase6
   PRESENT list to its stale/ABSENT list, and add the new strings to PRESENT. Doing
   the first without the other two turns a green phase6 into a test of the wrong copy.
   Nothing in phase6 or the pin was edited here, deliberately: changing a test to
   expect copy that no artifact produces would be worse than leaving it accurate.
2. **The packet-capture proof of section 2.5.** On the validation VM, before install,
   arm a capture or an nft counter for `api.clawfactory.app` and for the address it
   resolves to, then run the silent install to completion. Expected: zero packets and
   no DNS query for that name, with the positive control being any *other* install-time
   host (`openclaw.ai`) showing traffic in the same capture. Without that control the
   result is a silence that proves nothing.
3. **Version.** Both literals were bumped 1.3.5 to **1.4.0**, because 1.3.5 is already
   recorded in `released-versions.tsv` and the version gate refuses a second digest
   against a recorded version. The final job may pick a different number; it just
   cannot be 1.3.5.
4. **The live site.** See section 8.

---

## 8. The live site: edited, deliberately NOT committed and NOT pushed

`clawfactory-site` is public and Pages publishes on push, so pushing it is publishing.
The edits are in the working tree of `C:\Users\bmcki\clawfactory-site` and are
**uncommitted on purpose**, so they cannot ride out on an unrelated push. 22 added
lines, 10 removed.

Review and publish, when the operator chooses:

```bash
cd /c/Users/bmcki/clawfactory-site && git diff index.html
```

```bash
cd /c/Users/bmcki/clawfactory-site && git add index.html && git commit -m "Free release: Apache-2.0, remove purchase copy, correct four security claims" && git push
```

---

## 9. Resource ledger

| Resource | State |
| --- | --- |
| Azure VMs | **None provisioned this session.** Nothing is billing. |
| Scheduled tasks, PM2 processes, scratch DBs | none created |
| `scratchpad/calib/*.iss` + 2 tiny calibration `.exe` | in the session scratchpad, ~1 MB, disposable |
| `scratchpad/build/compile-probe.exe` (440 MB, x2 compiles) | **deleted after each verdict was captured.** `build/` now holds only `iscc.log`. |
| `Output\ClawFactory-Secure-Setup.exe` (the validated 1.3.5 artifact) | **untouched.** Both probe compiles were directed to the scratchpad via `/O`, never to `Output`. |
| Git branches | none created; work is on `main` in both repos |
| Dispatch card | #265, created `in_progress` at session start, moved to `done` at close-out |

---

## 10. Delta security sweep

Secrets scan over this session's own diff in all three repos, added lines only,
pattern covering `sk-*`, `xai-*`, `AIza*`, `ghp_*`, PEM headers, and
`password=` / `secret=` assignments:

```
ClawFactory-Secure-Setup : 0
ClawFactory-Studio       : 0
clawfactory-site         : 0
CALIBRATION (planted)    : 1   <- the pattern fires on a planted credential
```

**Nothing this session touched widened a permission or added an unscoped credential.**
The only permission-shaped changes are removals: an outbound POST endpoint deleted in
three places, and an HKLM read deleted. `nft` rules, uid scoping, file modes, the
immutable flag, the turn gate, the broker's root ownership and the quarantine's
ownership were not touched at all.

**Nothing weakened a test.** The one test that had to change kept its strength and its
replacement was calibrated against the real defect (2.4). `interim-v120-phase6.ps1`
and the Studio digest pin were deliberately left alone (section 7.1). The harness now
does strictly less network work than before, because it no longer activates a licence
slot on every run.

**A side effect worth recording:** every validation run since JOB 3 activated
`CF-TEST-TEST-TEST-TEST` against a fresh machine GUID and never released it. Only the
legacy `job3-teardown.ps1` ever deactivated, and the current harness does not call it.
Those slots are leaked server-side. Cleaning them up is licence-API housekeeping,
outside this repo and out of scope, but the leak stops now because the call is gone.

---

## 11. Delta bug review

Re-read my own diffs. Fixed in session:

- The `.iss` wizard would have lost a page: `ProviderPage` was parented to
  `LicensePage.ID`. Re-parented to `WelcomePage.ID` and the page-number comments
  renumbered 1 to 5.
- `validation/diag/g4-probe.ps1` passed `-LicenseKey` to `interim-v120-phase1.ps1`,
  which after the edit no longer accepts it. It would have thrown at runtime. Caught
  by the residual sweep, not by the compile.
- Two harness header comments still described the removed deactivate step
  (`job3-teardown.ps1:7`, `job3-validate.ps1:38`). Corrected. Code that disagrees with
  its own comment is a defect in a security product, because the comments are the
  audit trail.
- The `setup.ps1` comment at the tool-policy step asserted the browser denial was
  structural, which contradicted the prompt file after it was corrected. Fixed so the
  two agree.

Carded, not fixed here: nothing. The two open items are the build-job couplings in
section 7, which are sequencing rather than bugs.

---

## 12. Recommendation triage

**Fold into the final build job (card #197):** the Studio rebuild and three-part
repin; the packet-capture proof with its positive control; confirming the version
number.

**Card separately:** archive `clawagent-setup` with a superseded note (section 6);
publish the site edits (section 8); licence-API slot cleanup and eventual teardown of
the Stripe / price objects / licence API deployment, all of which are outside the repo
and were out of scope by instruction.

**Rejected with reason:** repinning Studio here (would assert copy no artifact
produces); editing `interim-v120-phase6.ps1`'s expected strings here (same reason);
scanning the compiled binary as absence proof (instrument proven blind, section 2.5);
the no-op licence stub (section 2.3).
