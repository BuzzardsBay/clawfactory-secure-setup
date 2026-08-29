# CLOSE-OUT: pre-publication sweep of `clawfactory-secure-setup`

**Date:** 2026-08-29
**Working root:** `C:\Users\bmcki\ClawFactory-Secure-Setup` (confirmed: `git rev-parse --show-toplevel`)
**HEAD at start and end:** `611f594f145d4506f9a3951e06d18d965662e222`
**Remote:** `https://github.com/BuzzardsBay/clawfactory-secure-setup.git`
**Dispatch card:** id 312, status `blocked`, priority 1

---

## REVISION 1 - 2026-08-29, same day, after the original verdict

**The verdict below was downgraded from HISTORY IS CONTAMINATED to SAFE AFTER CLEANUP IN
THE CURRENT TREE.** The original text is kept in place rather than rewritten, because an
audit record that silently changes its own finding is worth less than one that shows what
changed and why.

**What changed.** The original classification of the credential as *live* rested on a stated
inability to exclude reuse "from inside this repository". The operator supplied the fact that
resolves it: **he has never used that username and password.** That is knowledge only he
holds, and it is the correct source for it.

**Corroborating evidence from the repo, found after the attestation and consistent with it:**
`scripts/azure-validate.ps1` **never reads `C:\Users\bmcki\.azure-clawfactory-creds`.** A
tree-wide grep returns only the `CLAUDE_ClawFactory.md` doc line and this close-out. The
script prompts for the password at provisioning time with `Read-Host -AsSecureString`
(line 173) and passes it to `az vm create --admin-password` (line 194). There is therefore
**no code path by which that file's value could have reached any VM.** Whatever password the
`cfv-*` boxes actually received was typed at the prompt, not read from that file.

**Consequence.** The string is not a live secret and never was one. It is a plaintext
password-shaped value for an account that was never created with it. The prompt's criterion
for the third verdict - "a live secret exists in a commit that is not `HEAD`" - is no longer
met.

**What does NOT change.** The home IP, the subscription id and the rest of the personal and
infrastructure information in Task 1.1 are all still present, and they are in historical
commits as well as in `HEAD`. Redacting them in the current tree does not remove them from
history. That residue is **accepted, not fixed**, and it is accepted precisely because none
of it is a credential - which is the same reasoning that makes a history rewrite the wrong
trade in Task 3.2, and that reasoning is unchanged.

**One residual worth a line:** publishing a never-used password still discloses something
small about how the operator constructs passwords. It is not a blocker; it is a reason to
prefer removing the line over leaving it.

---

## REVISION 3 - 2026-08-29 20:06Z, THE REPOSITORY IS PUBLIC

**The operator made the repository public.** His decision and his action; this session did not
run the command and did not change the visibility. Confirmed: `"private": false`,
`"visibility": "public"`, `updated_at 2026-08-29T20:06:46Z`. Published **after** the Revision 2
cleanup landed, so the current tree a stranger reads carries neither the credential line nor
the operator's IP. The IP rotation had not yet been attempted; per Revision 2d that was a
mitigation to attempt, not a gate.

### 3a. The thing the job existed for: verified working

Anonymous, unauthenticated `curl`, no token:

```
releases/latest  -> HTTP 200, redirects to /releases/tag/v1.4.4
repo root        -> HTTP 200
.../releases/latest/download/ClawFactory-Secure-Setup.exe -> HTTP 200
```

**The `clawfactory.app` ClawFactory download button now resolves for a stranger.** That was
the whole point, and it is closed.

### 3b. The GitHub-side surfaces, swept now that they are visible

Task 1.4 item 7 listed these as un-swept because they are not in the git object database.
Swept on publication:

| Surface | State | Verdict |
|---|---|---|
| Issues | 0, any state | clean |
| Pull requests | 0, any state | clean |
| Wiki | `has_wiki: true`, but `git ls-remote ...wiki.git` -> **Repository not found** | no content; the HTTP 200 is GitHub's "create the first page" shell |
| Actions runs | **41**, and their logs are now public | **all 41 are GitHub's built-in `pages build and deployment`.** No workflow file has ever been committed to `.github/workflows/` at any commit, so there is no custom CI and no log that could carry a build secret. Benign. |
| Description | Product copy: "Free, open-source hardened OpenClaw installer for Windows..." | clean |
| Topics / homepage | none set | clean |
| Releases | one, `v1.4.4`, 1 asset, not draft | as intended |
| Forks / stars | 0 / 0 | nothing mirrored yet at time of check |

### 3c. One premise worth correcting for next time

The operator's reasoning was *"no one is going to see it in the next hour anyway."* That is
not how a new public repository behaves: GitHub emits public repo events to a firehose that
archival services, code-search indexers and automated secret scanners consume within minutes,
and GitHub's own secret scanning begins on visibility change. The practical assumption should
be that the repository is enumerable and archivable from the moment of the flip, not after a
grace period.

**It changes nothing here**, and that is because of the order the work happened in, not luck:
the credential was reclassified as never-used, and the cleanup commit removed both it and the
IP from the current tree *before* the flip. The only thing exposed at publication is what
Revision 2 already accepted - the IP in superseded commit versions. But the corollary does
matter for the overnight modem plan: **anything archived in the first minutes holds the
pre-rotation history regardless of what the address becomes later.** That lowers the value of
the rotation further; it does not raise the risk, which was already assessed as low in 2d.

---

## REVISION 2 - 2026-08-29, the cleanup executed, and an operator correction the verdict earned

### 2a. The cleanup, done

- **`CLAUDE_ClawFactory.md` untracked** (`git rm --cached`) and added to `.gitignore` with a
  comment recording why. **The file remains on disk** at its original path; only git has
  stopped tracking it.
- **The operator's public IP redacted to `<operator-ip-redacted>`: 28 occurrences across 13
  tracked files.** Thirteen, not the twelve originally reported - this close-out itself had
  become the thirteenth carrier by quoting the address three times while documenting it.
  Verified with a control: the subject grep returns 0, and a positive control for the
  replacement token returns 28. `git ls-files --eol` reports `i/lf w/lf` for all 13, so no
  line-ending drift.

### 2b. The correction, and what it is worth

The operator's objection, in his words: *"That IP is in 12 files that are already committed.
Redacting it now fixes the current tree but the old commits still hold it, and those become
readable the moment the repo goes public. The verdict says safe after cleanup, and on the
credentials it's right, but not on this."*

**He is right about the label.** In fairness to the record, Revision 1 did state the substance
- "they are in historical commits as well as in `HEAD` ... That residue is accepted, not
fixed". But the verdict *name* the prompt supplies carries the gloss "Nothing in history needs
touching", and applying that name to a state where personal information demonstrably does
remain in history papers over exactly the thing a reader would want flagged. A correct body
under a misleading heading is a defect, because the heading is what gets quoted.

**And his fix is better than either option this session offered.** The choice presented was
rewrite history (destroying the v1.4.4 provenance chain) or accept the exposure. He supplied a
third: change the fact the data describes, so the historical record becomes inert. A leaked
password is neutralised by rotating the password; a leaked dynamic IP is neutralised the same
way. That the same move was not proposed here is a genuine gap in the analysis.

### 2c. Where it needs qualifying, measured rather than asserted

**Baseline, taken now, using the repo's own method** (`api.ipify.org`, per
`validation/interim-v140-relgate-box.ps1:159`, cross-checked with `ifconfig.me/ip` as box D
did): both readers return **the exposed value**, unchanged, and agree with each other.

1. **"A few minutes" is likely to be too short.** Residential ISPs hand out addresses on DHCP
   leases keyed to the modem, and a brief power-cycle usually re-acquires *the same* lease
   because it has not expired. Hours, or overnight, materially improves the odds. This is a
   probabilistic mechanism, not a command that returns success - which is why step 3 is not
   optional.
2. **The deterministic lever, if the outage does not work,** is changing the WAN-side MAC the
   ISP sees - swapping or reconfiguring the router/modem. Not always possible with an
   ISP-supplied gateway.
3. **VERIFY, DO NOT ASSUME.** Re-read `api.ipify.org` afterwards and compare against the
   baseline above. An unverified assumption that the address rotated is worse than no attempt,
   because it retires a real concern on a guess. Same discipline as every other measurement in
   this document: the control must actually fire.
4. **It kills the forward risk, not the retrospective one.** Once the address changes, the
   value in history points at whoever holds it next, and the *current* home network is no
   longer identified - that is the whole of the practical risk and it is genuinely closed. What
   survives is that the record still says this address was the operator's on given dates in
   August 2026; anyone holding historical ISP-geolocation data for those dates could still
   place him. That is a small, decaying residue rather than a live exposure, and it is one more
   reason the current-tree redaction in 2a was worth doing on its own.

### 2d. Publication gate - stated too strongly, and revised on evidence

**Originally written:** *"Do not publish until the re-read in 2c step 3 returns an address
different from the baseline."*

**That was too strong, and the evidence for why came from this repository's own history.**
The address was measured live and recorded on **eleven distinct dates between 2026-08-13 and
2026-08-29** - 13th, 17th, 20th, 21st, 23rd, 24th, 25th, 26th, 27th, 28th, 29th - and is
identical in all of them (`git log -S`, over public refs). **Seventeen days, eleven
measurements, one value.** That is direct local evidence that this ISP's lease renews to the
same address rather than a guess about a named provider's behaviour. An overnight outage is
worth trying and may well work, but the odds are not the near-certainty the original wording
implied, and a hard gate on a probabilistic mechanism could postpone the release indefinitely.

**Revised position: attempt the rotation, verify it, and publish either way.**

The residual if it does not rotate is smaller than the gate implied:

- It is personal information, not a credential, and it is already redacted from the current
  tree, so it appears only in superseded commit versions.
- **The `/32` references do not describe the operator's own network posture.** In every
  close-out the address is the *source* scope of an Azure NSG rule - the address permitted to
  reach a validation VM's RDP port. It says nothing about any port being open at his home. A
  reader who mistakes a source allowlist for an inbound posture would be reading it wrong.
- The address is disclosed to every site he visits and every mail server he touches. Its
  publication in a git history is a durability and name-association problem, not a novel
  disclosure.
- It decays on its own: the value stops describing his network the moment the lease does
  eventually roll - a modem swap, a re-provisioning, an extended outage - after which the
  historical record points at whoever holds it next.

**What remains a genuine gate: nothing.** The credential is reclassified as never-used, the
current tree is clean, and the IP rotation is a mitigation to attempt rather than a
precondition. The verdict is **SAFE AFTER CLEANUP IN THE CURRENT TREE**, with the residue in
2b/2c explicitly accepted.

---

## VERDICT (Task 3.1) - AS ORIGINALLY WRITTEN, SUPERSEDED BY REVISIONS 1 AND 2 ABOVE

**HISTORY IS CONTAMINATED.**

A live credential exists in commits that are not `HEAD`, and also in `HEAD` itself.

| | |
|---|---|
| File | `CLAUDE_ClawFactory.md` |
| Line in `HEAD` | 1279 |
| Redacted form | ``- **Creds:** `C:\Users\bmcki\.azure-clawfactory-creds` (clawadmin / [REDACTED - 22-char mixed-case password with a punctuation character])`` |
| Commits carrying it | 9, spanning **2026-05-11 -> 2026-08-29** |
| Earliest | `831b3e095f945b6922deab4b3af9df76d2546d4d` (2026-05-11, "docs: update CLAUDE.md and backlog to May 2026 state") |
| Latest | `877ee511d5c2e39b0f71fb4901c593d0f5fe9648` (2026-08-29) - this is the blob `HEAD` carries |
| Occurrences elsewhere | **zero**. Nine blob versions, all of the same one file. |

The value is a plaintext Azure VM local-administrator username/password pair. It is
classified **live**, not dead, for three reasons: it is a password the operator chose and
still stores at `C:\Users\bmcki\.azure-clawfactory-creds`; the same `clawadmin` username is
the default admin user in every validation script in the tree, so the pair is what the next
provisioning run would reach for; and password reuse against the operator's other accounts
cannot be excluded from inside this repository.

Mitigating, and verified rather than assumed: **`az vm list -g clawfactory-validation`
returns nothing** (exit 0, empty). No currently provisioned machine accepts it. The blast
radius today is the credential itself and any reuse of it, not a reachable host.

This verdict is not a product defect and nothing in the shipped artifact is affected.

---

## PROMPT 15 preamble - clauses applied and clauses deleted

Pasted from `docs/VALIDATION_PREAMBLE.md`, the authoritative copy in this repository. The
following clause groups were deleted because they provably do not apply to a job that
provisions nothing and installs nothing:

- **ENVIRONMENT, NOT NEGOTIABLE** - deleted. No VM, no `az vm run-command`, no WSL, no RDP,
  no `/var/tmp`, no `-OutDir`, no deallocation. (One read-only `az vm list` was run, to
  classify the credential above; that is not a provisioning step.)
- **HUMAN HANDOFF CARDS** - deleted. This job has one human decision at the end and it is
  the verdict itself, not a mid-run stop with a staged command.
- **RESOURCE LEDGER** - deleted. No resource group is touched, no VM or disk is created or
  swept, no licence slot is consumed.
- **MEASUREMENT DISCIPLINE, phase runner** - the `interim-v120-phaselib.ps1` requirement is
  deleted: there is no install to phase. **The calibration principle inside it was kept and
  is the whole of Task 1.3.**
- **VERSION AND BUILD** - deleted. No build, no signing, no ledger row, no tag.

Applied in full: **CLOSE-OUT IS A GATE**; **PRE-FLIGHT**; **IF THIS PROMPT IS WRONG, SAY SO**
(see Prompt corrections, below); **AN AUDIT REGEX IS ITSELF A PROBE** - which is the
governing clause for this job and which caught two defects in this session's own sweep
before the sweep was permitted to report; **CREDENTIAL HYGIENE** - no secret value is printed
in this document or was printed in chat; **GIT**; and the clause that `python` is blocked, so
the dispatch card went over the API from PowerShell with `x-frontier-secret`.

---

## TASK 0 - what would become public

### 0.1 Current visibility, verbatim from the GitHub API

```
{"archived":false,"created_at":"2026-04-27T16:19:36Z","default_branch":"main","fork":false,
 "full_name":"BuzzardsBay/clawfactory-secure-setup","private":true,"pushed_at":"2026-08-29T18:15:33Z",
 "size":10134,"visibility":"private"}
```

`"private": true` / `"visibility": "private"`. The sweep is therefore a precaution and not a
post-mortem, and the job proceeds.

### 0.2 Size of the exposure

| Measure | Value |
|---|---|
| Commits reachable from public refs | **464** |
| First commit | `d9b6d362596d9eabce7d62f03532091d36345ac5`, **2026-04-27 09:08:11 -0600**, "Initial release: ClawFactory Secure Setup v1.0" |
| Files in the current tree (`git ls-files`) | **355** (349 distinct blobs; 6 files share content with another) |
| Distinct blob versions readable across public history | **1034**, 67,641,942 bytes |
| Tags | 22 (`v1.0.0` ... `v1.4.4`) |
| Branches on the remote | 2 - `main`, and `claude/gracious-pasteur-0Qhmd` (a stale pointer at `3ed3d1e`, wholly contained in `main`, 365 commits behind) |
| Published release | v1.4.4, 2026-08-29, one asset `ClawFactory-Secure-Setup.exe` |

**Not public, and this matters.** `refs/stash` holds one stash containing
`signing/metadata.json` (the generated Azure Trusted Signing metadata: endpoint,
`clawfactory-signing`, `clawfactory-cert` - resource names, no credentials) and **245 vendored
Microsoft binaries under `signing/tools/`** (~130 MB: `nuget.exe`, the Windows SDK BuildTools
nupkg, `Microsoft.ArtifactSigning.Client`, `mfc140.dll`, and so on). A stash is not pushed and
GitHub never receives it. Every count in this document is over the **public** object set, not
the local object database, and the two differ by 251 blobs. Had the sweep been run over
`--all` and reported naively, it would have declared a Microsoft redistribution problem that
does not exist.

### 0.3 What a stranger could read

Top level of the current tree:

| Area | Files | What it is |
|---|---|---|
| `docs/session_reports/` | **86** | Every close-out and handoff since 2026-07-13. Internal. See Task 2. |
| `validation/` | 78 | The probe suite, the phase runner, runbooks, manual checklists |
| `validation-runs/` | **69** | **Committed evidence**: per-run `REPORT.md`, probe JSON, `.log`, `.out`, `install-run-stdout.txt`/`stderr`, `diag-hunt.out`, `quota.json`, `install-duration.txt`. This directory is in `.gitignore` now; the 69 files predate that and remain tracked. |
| `resources/` | 55 | Shipped payload, incl. `ClawChat.exe` and the systemd units |
| `scripts/` | 15 | Build, sign, azure-validate, diagnostics |
| `docs/cc_jobs/` | 5 | **Verbatim job prompts written by the operator** |
| `docs/reference/` | 3 | `EMAIL_APPROVAL.md`, `HOSTNAME_WRITE_CENSUS.md`, `OPENCLAW_VERSION_POLICY.md` |
| `reports/` | 1 | `AZURE_SIGNING_WIRED_20260706.md` - subscription id, signing account, cert profile |
| Root `.md` written for internal use | 20 | `CLAUDE_ClawFactory.md` (115 KB - the operator's own working context file, incl. section 20 "Payment - Stripe", "Mercury bank account", personal-site paths, and the credential above), `ClawFactory_Install_Lessons_Learned.md`, `CC_Git_Hygiene_Both_Repos.md`, `Weekly_Work_Log.md`, `v1.1_backlog.md`, two `ClawFactory_Session_Handoff_*.md`, `REPORT.md` and six `REPORT_v1.0.3x.md`, `SECURITY_FINDINGS.md`, `PERSONAS.md`, `SUPPORT_MATRIX.md` |
| Genuinely outward-facing | 7 | `README.md`, `LICENSE`, `NOTICE`, `SECURITY.md`, `CONTRIBUTING.md`, `CHANGELOG.md`, `.github/ISSUE_TEMPLATE/*`, `docs/index.html` + `docs/CNAME` (the live site source) |

Logs, transcripts and evidence committed at any point: the 69 files in `validation-runs/`
listed above, plus `validation-runs/install-sh-review/install.sh.{current,prior,diff}`. No
`.env`, `.pfx`, `.p12`, `.pem`, `.key`, `.crt`, `.cer`, `id_rsa`, `secrets/` or
`credential*` file has ever existed at any path in this repository, in any commit.

### 0.4 Content readable only in history

- **685** distinct blob versions are reachable from public refs but are **not** in `HEAD`'s
  tree. That is the mass of superseded file versions a stranger can read with
  `git log -p`, and it is where the older copies of the credential live.
- Exactly **2** paths were ever removed from public history, both benign:
  `docs/CNAME` (removed and later re-added) and `validation/MANUAL_CHECKS_v131.md`
  (renamed to `validation/MANUAL_CHECKS_studio.md`).
- Restated plainly: **463 of the 464 commits are not `HEAD`**, and everything any of them
  ever contained is readable. Nothing was hidden by a later deletion, because almost nothing
  was ever deleted - the exposure is superseded *versions*, not removed *files*.

---

## TASK 1 - the sweep, over the full history

**Method.** Every object in the local database was enumerated
(`git cat-file --batch-all-objects`), yielding 1285 blobs, and each was extracted to disk and
scanned as a file. The set was then intersected with `git rev-list --objects --remotes --tags`
to isolate the **1034 blobs that would actually become public**, discarding the 251
stash-only and dangling objects. Scanning blobs rather than commits means each unique
version is examined exactly once instead of 464 times, and a file deleted in a later commit
is still scanned. Twelve pattern classes were run; the class set is recorded in
`patterns.txt` in the session scratchpad and reproduced by class below.

### 1.1 / 1.2 Hit list with classification

| # | Class | Found | Classification | Detail |
|---|---|---|---|---|
| 1 | **Provider API keys / tokens** | Prefix strings only | **Harmless** | `sk-ant-`, `sk-proj-`, `xai-`, `AIza` appear in `ClawFactory-Secure-Setup.iss` (the wizard's format-validation code), `CHANGELOG.md` and `docs/session_reports/API_KEY_WIZARD_2026-07-19.md`. The only "full-length" matches are the installer's own placeholders: `sk-ant-api03-XXXXXXXXXXXXXX`, `sk-proj-XXXXXXXXXXXXXXXXXXXX`, `xai-XXXXXXXXXXXXXXXXXXXX`. **Zero real key material in the public set.** |
| 2 | **Private keys / certificates** | **None** | - | Zero matches for `-----BEGIN ... PRIVATE KEY-----`, `-----BEGIN CERTIFICATE-----`, `PuTTY-User-Key-File`. No `.pfx`, `.p12`, `.pem`, `.key`, `.crt`, `.cer` ever committed. |
| 3 | **Passwords** | **ONE** | ~~**LIVE SECRET**~~ -> **DEAD: never used** (see Revision 1) | `CLAUDE_ClawFactory.md:1279`, redacted at the top of this document. Nine blob versions, nine commits, 2026-05-11 -> 2026-08-29. Classified live when written; downgraded on the operator's attestation that the pair was never used, corroborated by `scripts/azure-validate.ps1` having no read path to that file. |
| 3b | Other password-shaped literals | 3 | **Dead / synthetic** | `password":"CFV-SYNTHETIC-SINK-NOT-A-SECRET-2026"` (a probe's deliberate sink), `apiKey": "<REDACTED>"` and `token": "<REDACTED>"` (already redacted in `CLAUDE_ClawFactory.md`), `Token="6595b64144ccf1df"` (a well-known Microsoft assembly publicKeyToken). |
| 3c | **The validation SMTP app password** | **Not present** | - | Searched explicitly. Twenty-eight distinct prose references to it exist across the close-outs, every one of them recording that it was typed by Bret into the Studio panel by hand and entered no transcript, log or file. **The value itself appears nowhere.** Consistent with PROMPT 15: it is a deliberately KEPT throwaway and was not requested here. |
| 4 | **`.env` files or their contents** | **None** | - | No `.env` path in any commit; zero `NAME_SECRET=value` / `*_PASSWORD=value` / `*_TOKEN=value` assignments in the public set. `C:\Users\bmcki\FrontierAI\.env` is *named* in `CLAUDE_ClawFactory.md` as a path; no content of it is present. |
| 5 | **Azure subscription id** | `43010359-...-10f6544b2978` | **Personal / infrastructure information** | `HEAD`: `CLAUDE_ClawFactory.md`, `REPORT.md`, `reports/AZURE_SIGNING_WIRED_20260706.md`, `docs/session_reports/HANDOFF_2026-08-20_card258.md`, and four `validation-runs/phase1-bake-*/log.md`. Not a credential on its own - it is not usable without an authenticated principal - but it is a durable identifier of the operator's Azure tenancy and an aid to anyone targeting it. |
| 6 | **Resource group / VM / storage / signing names** | Many | **Personal / infrastructure information** | RG `clawfactory-validation` (westus2); storage account **`clawfactoryvalc467`** in 20+ files; images `clawfactory-win11-baseline` and `-v2`; signing account `clawfactory-signing`, cert profile `clawfactory-cert`, service principal `clawfactory-signing-sp`, endpoint `eus.codesigning.azure.net`; **~180 distinct `cfv-*` VM, NIC, NSG, pip and disk names**; admin usernames `clawadmin` and `cfvadmin`. All resources are torn down; the names remain a complete map of the operator's validation estate. |
| 7 | **IP addresses** | 188 distinct | Mostly **harmless**, one **personal** | Harmless: `0.0.0.0`, `127.0.0.1`, RFC-5737 documentation addresses, ASN.1 OIDs that merely look like IPs (`1.3.6.1`, `2.5.29.19`), public resolvers (`1.1.1.1`, `8.8.8.8`, `9.9.9.9`), and the resolved allowlist sets for Anthropic (`160.79.104.10`), GitHub (`140.82.*`, `185.199.*`), Cloudflare (`104.16-21.*`, `172.6*`) and Canonical (`91.189.*`, `185.125.*`). Dead: ~30 ephemeral Azure `20.*`/`4.*`/`40.*` addresses of destroyed validation VMs, and `172.26.136.101` (a WSL NAT address). **Personal: `<operator-ip-redacted>`** - labelled in the material itself as "build machine public IP" and used as the RDP `/32` scope. See row 8. |
| 8 | **Operator's home network address** | `<operator-ip-redacted>` | **PERSONAL INFORMATION** | Present in **12 files in `HEAD`**, all under `docs/session_reports/`: `2026-08-05_interim_validation_v1_2_0`, `2026-08-17_guard4_ground_truth`, `2026-08-19_switchprovider_and_validation`, `2026-08-23_v140_release_validation`, `2026-08-24_v140_validation_completion`, `2026-08-25_v141_validation`, `2026-08-26_v141_validation_closure`, `2026-08-27_v144_validation_boxA`, `2026-08-28_v144_validation_boxBC`, `2026-08-28_v144_validation_boxD`, `2026-08-29_v144_validation_boxD_completion`, `HANDOFF_2026-08-20_card258`. Several of them state in prose that it is the operator's own machine. This is the operator's residential IP, published against his real name, and it is the single worst item here after the credential. It is not a *secret* - it is *personal information*, and the distinction does not make it safe to publish. |
| 9 | **Hostnames / machine names** | **None sensitive** | - | Zero `DESKTOP-*`, `WIN-*` or `*.local` machine names. Every "hostname" hit is the product's own egress-allowlist vocabulary. The build machine's NetBIOS name (`Bret`) appears nowhere. |
| 10 | **Email addresses** | 38 distinct | Mixed | **Personal:** `bmckinney1215@gmail.com` (also the author of 463 of 464 commits, so it is unavoidably public in the commit metadata), `bret@bretmckinney.com`, `hello@avitalresearch.com`. **Business, already public:** `support@clawfactory.app`, `licenses@clawfactory.app`, `hello@clawfactory.app`, `security@frontierholdingsllc.com`. **Validation mailboxes, throwaway:** `clawfactory.validation.0805@gmail.com`, `clawfactory.validation@hotmail.com`, `clawfactory.validation@outlook.com`, `agent@clawfactory.local`. **Harmless:** `*@example.com`, `*@example.invalid`, SSH KEX algorithm identifiers, and `128x128@2x.png`. |
| 10b | **Cross-project disclosure** | `hello@avitalresearch.com` | **Personal / commercial** | It is the destination of the `support@clawfactory.app` forwarder, so a support email to ClawFactory publicly resolves to the operator's separate Avital Research venture. It is already in `CONTRIBUTING.md` and thrown in three error strings in `setup.ps1`, i.e. it already ships. Publishing does not change that; it is recorded so the choice is deliberate. |
| 11 | **Absolute paths containing the operator's username** | 41 distinct | **Personal information** | In text, across 118 blobs: `C:\Users\bmcki\ClawFactory-Secure-Setup`, `...\ClawFactory-Studio`, `...\ClawChat`, `...\clawfactory-site`, `...\clawagent-setup`, `...\clawfactory-license-api`, `...\BretMcKinney-Site`, `...\FrontierAI`, `...\FrontierAI\.env`, `...\OneDrive\Desktop\Claude Prompts`, `...\.azure-clawfactory-creds`, `...\ClawAgent-asset-archive-2026-08-29`, plus `%TEMP%` diagnostic paths. Beyond the username itself, this enumerates **four other private projects** by local path. |
| 11b | Username in a **shipped binary** | `resources/ClawChat.exe` | **Personal, already public** | `HEAD`'s copy (`38c31ac`) contains **866** occurrences of `C:\Users\bmcki\.cargo\registry\...` - Rust panic-path strings baked in at compile time. This binary ships inside `ClawFactory-Secure-Setup.exe`, which is already downloadable from the v1.4.4 release, so making the repository public discloses nothing new. It is recorded because a rebuild is the only fix and that fix belongs in a release, not here. |
| 12 | **Third-party names, client references, Jason** | **NONE** | - | Zero matches for `Jason` - case-insensitive, whole word, over all 1034 public blobs and all 464 commits. Zero client-shaped names. **This class is genuinely clean.** For calibration: the same search over the sibling `FrontierAI` working tree returns hits immediately, which confirms the term is one this operator's material does use - just not in this repository. |
| 13 | **Azure SAS tokens** | **None** | - | `.gitignore` warns that run-scoped wrappers "bake in SAS-signed installer URLs". Those wrappers live under `validation-runs/` and were never committed. Every `blob.core.windows.net` occurrence in the public set is a PowerShell string built from `$StorageAcct`/`$sas` **variables**; no literal `sig=` or `sv=` value exists anywhere. |
| 14 | Commit metadata | 3 identities | **Personal, unavoidable** | `Bret McKinney <bmckinney1215@gmail.com>` (463), `Claude <noreply@anthropic.com>` (1), committer `GitHub <noreply@github.com>` (2). |

**Summary: one live secret, zero dead secrets of consequence, a substantial amount of
personal and infrastructure information, and nothing else.**

### 1.3 Canary - the sweep measured against itself

Per PROMPT 15, "AN AUDIT REGEX IS ITSELF A PROBE", and its sharper second form: the canary
must look like the thing you are afraid of missing, not like the things you already know are
there. Twelve canaries were planted, one per class, each in a shape that does not appear
anywhere in the real material.

Method: four tracked files were byte-copied to the scratchpad and their SHA-256 recorded;
three canary lines were appended to each; the twelve class patterns were run over them;
the files were restored from the byte copies (`cp`, never `git checkout --`, which on this
machine silently rewrites line endings); the hashes were recomputed and compared.

**First run - TWO CLASSES FAILED.**

| Class | Canary shape | Result |
|---|---|---|
| `C2_PRIVKEY` | `-----BEGIN RSA PRIVATE KEY-----` | **FAIL, 0 matches.** The pattern's first alternative begins with `-`, so `grep` consumed the whole pattern as a command-line option instead of a pattern. The class had been silently searching for nothing. |
| `C3_PWQUOTED` | `SmtpPassword = "qhwk zjro tvbm dlxs"` | **FAIL, 0 matches.** The pattern was lower-case and the run was case-sensitive, so `SmtpPassword`, `AdminPassword`, `ApiKey` and every other CamelCase credential name were invisible to it. |

Both defects were fixed - `grep ... --` to terminate option parsing, and `-i` throughout - and
the classes re-run. **Second run: 12 of 12 canaries detected.**

```
C1_KEYS       canary_found=1  PASS      C7_IPV4       canary_found=1  PASS
C2_PRIVKEY    canary_found=1  PASS      C8_HOSTNAME   canary_found=1  PASS
C3_PWQUOTED   canary_found=1  PASS      C9_EMAIL      canary_found=1  PASS
C4_ENVASSIGN  canary_found=1  PASS      C10_USERPATH  canary_found=1  PASS
C5_AZGUID     canary_found=1  PASS      C11_NAMES     canary_found=1  PASS
C6_AZNAMES    canary_found=3  PASS      C12_SAS       canary_found=1  PASS
```

Every result in Task 1.1 above was produced by the **corrected** patterns. The pre-canary
"zero private keys" reading was worthless and is not the one reported.

**Reversal proof, by hash and not by `git status`** - `core.autocrlf=true` is in this
machine's SYSTEM config, so `git status` cannot see a line-ending rewrite:

```
BEFORE                                                  AFTER
4c56cc14...e42499d1  docs/FAILURE_CATALOGUE.md          4c56cc14...e42499d1
b90af2a5...8f6caa69  README.md                          b90af2a5...8f6caa69
a9c8f6fd...4bb96738  validation/interim-v120-phase1.ps1 a9c8f6fd...4bb96738
055012fa...99384fad  resources/post-install.ps1         055012fa...99384fad
```

`diff` of the two SHA-256 manifests: identical, all four files. No canary payload token
survives anywhere in the tree. (`grep CANARY-` still returns hits - those are the product's
*own* pre-existing `CANARY-A2-<hex>` probe markers in `validation/job3-probe.ps1` and four
close-outs, an unlucky collision with my label and not my content; none of the twelve unique
payload strings remain.) `git status --short` was empty before the canary and is empty after.

**And the canary's own limit, honestly stated.** *The live credential found in this session
was not found by any of the twelve patterns.* `(clawadmin / <value>)` is a bare parenthetical
pair with no `password=`, no colon, no quotes, and no keyword adjacent to the value. It was
found by **reading** `CLAUDE_ClawFactory.md` section 20.6 while chasing the Azure subscription
id. A canary certifies the pattern against the shape of the canary; my `C3` canary was
`SmtpPassword = "..."`, so it certified `C3` against exactly the shape `C3` already handled.
The real secret was a shape I had not imagined, and the regex missed it. That is the single
most important sentence in this report.

### 1.4 What the sweep cannot catch

1. **Secrets that do not look like secrets.** Proven, not theorised - see immediately above.
   A high-entropy blob with no keyword near it, a value in a table cell, a password embedded
   in prose, or a credential split across two lines will pass every pattern here. The only
   control for this class is reading, and 67 MB was not read.
2. **Encoded or compressed content.** Base64, gzip, ZIP, `.nupkg`, and any binary that
   stores UTF-16 rather than ASCII. A UTF-16LE secret inside `ClawChat.exe` would not match
   a byte-oriented ASCII pattern. PROMPT 15's own clause applies: a marker search over a
   compressed payload finds nothing and reads as clean.
3. **Path attribution, not detection.** `git rev-list --objects` names each object once, so
   a blob appearing at two paths is reported under one of them. Detection is unaffected -
   every blob was scanned - but a "which file" answer can be incomplete where content is
   duplicated. Six of `HEAD`'s 355 files share a blob with another.
4. **Semantic sensitivity.** No regex can decide that section 20.3, "Payment - Stripe
   (Frontier Trading LLC) ... Payouts: Mercury bank account", or a candid close-out passage
   about a defect, is something the operator would rather not publish. Task 2 is a human
   judgement and is presented as one.
5. **What is not in this repository.** The Studio repo, `clawagent-setup`,
   `clawfactory-site` and `FrontierAI` were not swept. `clawfactory-site` and
   `clawagent-setup` are already public.
6. **Anything added after this commit.** This is a point-in-time reading of `611f594`.
7. **The GitHub side.** Issues, pull requests, wiki, Actions logs, release asset metadata,
   and the repository description and topics were not examined; several of those become
   visible along with the code.

---

## TASK 2 - the close-outs

### 2.1 Count and inventory

**86 files in `docs/session_reports/`**, 2026-07-13 -> 2026-08-29, roughly 2.1 MB. The five
largest are the v1.4.4 validation boxes (122 KB, 100 KB, 99 KB, 65 KB) and the doc-truth
close-out (61 KB). What a stranger learns from each, one line each:

- **`2026-07-13` PHASE0/PHASE1/PHASE2** - the v1.1 architecture: agents are `clawuser`
  processes and not containers, the grants substrate, the Studio Workbench.
- **`2026-07-14` SECFIX x3, CHATCOMPLETIONS_PROXY, ADVERSARIAL_SUITE, PHASE2_5_MOUNT** - six
  adversarial findings and their fixes: DNS exfiltration, an unenforced SOUL, gate coverage,
  a false Docker claim; plus the gating proxy design and the mount-namespace fix.
- **`2026-07-15`/`-16`/`-17` GATEWAY_8C x3, VALIDATION_v1039-v1044, CONFIRM_v1044/45,
  GATEWAY_OWNERSHIP_FIX, AZURE_CLEAN_VALIDATION x2, CLEAN_VALIDATION_v1039** - the full
  install-failure lineage, including six consecutive RED release gates before v1.0.45.
- **`2026-07-18`/`-19` DOOR2_CLOSURE, DOOR2_RECONCILE** - that the agent and the gateway share
  one uid, accepted and documented rather than fixed, deferred to v2.
- **`2026-07-19` GRANT_VERIFY_ZERO_TERMINAL** - the grant mechanism is safe, *and* that interop
  is not explicitly disabled, the Studio grant API is unauthenticated on loopback, and replay
  skips the deny-list.
- **`2026-07-19` API_KEY_WIZARD, RELEASE_v1047, version_pin_tool_policy, egress_persistence** -
  the wizard's design, the OpenClaw pin, and that `tools.deny=[browser]` is gateway-path and
  not structural.
- **`2026-07-20`/`-21`/`-22` job2_f2, job3b, job3c, ship_a_site, site_migration, ship_b,
  site_content** - the combined installer, its clean-box validation, and two passes of
  correcting claims on the live marketing site.
- **`2026-07-28` -> `2026-08-05` guard1, guard2, persona_constant, post_audit,
  self_certifying_audit, soul_persona, first_gated_build, interim_validation_v1_2_0,
  rootfs_provenance** - the guard builds, and the finding that **the build gates are
  advisory: `ISCC.exe` plus `sign_installer.ps1` bypasses all of them**.
- **`2026-08-13` -> `2026-08-19` studio_scope, studio_smoke x2, guard3 x5, guard4_ground_truth,
  harness_and_race, provider_route x2, switchprovider** - Guard 3's rework, the TC.3 blocker,
  the empty-verdict gap in the harness, and a switch-provider defeat of Guard 3.
- **`2026-08-22` -> `2026-08-29` v135_matrix, free_release_prep, v140 x2, v141 x4, v142,
  v143 x3, site_killswitch_claims, v144 x6, doc_truth_and_clawagent_hazard, release_prep** -
  the free release, and a verdict of **NO** on v1.4.1 and again on v1.4.3, with the reasons.
- **Handoffs (12)** - `HANDOFF_*`, `*_handoff.md`, `*_PLANNING_HANDOFF.md`: mid-job state,
  including the operator's home IP and what he was asked to do by hand.

Read together they teach a stranger: the real security posture including what is advisory
rather than structural, every defect found and whether it was fixed or accepted, the
operator's Azure estate and his home IP, and his working method - including the several
places where a session got a wrong answer and had to be corrected.

### 2.2 Recommendation

**Publish them, after the two redactions named below, and do not move them out of the
repository.**

The reasoning, in order of weight:

1. **This repository's whole claim is auditability.** `.gitattributes` says it outright: the
   product's claim is that a stranger can audit the source that produced the artifact. A
   repository that ships `FAILURE_CATALOGUE.md` publicly with every release, and a
   `SECURITY_FINDINGS.md` that names its own unfixed residuals, cannot coherently hide the
   evidence behind them. `FAILURE_CATALOGUE.md` is already the *index* to these documents;
   publishing the index and withholding the record is the worst of both.
2. **For a credibility release, the record is the asset.** Almost no small security product
   can show six consecutive RED gates, two `NO` verdicts on its own releases, a documented
   uid-sharing weakness it chose to accept rather than paper over, and a written finding
   that its own build gates are bypassable. That is not embarrassing; it is the strongest
   evidence available that the green results mean something.
3. **Redacting them wholesale would cost more than it buys.** Eighty-six documents, 2.1 MB,
   dense cross-references, and 12 of them carrying the home IP. A blanket redaction pass
   would be a large diff over the repository's most-cited internal record, would break the
   cross-references the catalogue depends on, and would leave the *unredacted* originals in
   history anyway - so it would buy nothing that the history rewrite in Task 3 is not already
   declining to do.
4. **Moving them out is worse than redacting.** It breaks every `docs/session_reports/...`
   reference in `FAILURE_CATALOGUE.md`, `V1_5_BACKLOG.md` and the close-outs themselves,
   it leaves them all in history regardless, and it converts the product's central claim into
   a gesture.

Two things must change before they are published, and both are narrow:

- **The home IP, `<operator-ip-redacted>`, in 12 files** - this is personal information about a
  private individual at his home address, published under his real name. It has no audit
  value whatsoever: `<operator public IP, redacted>` carries exactly the same meaning in
  every one of the 12 places it appears. Replace it.
- **`CLAUDE_ClawFactory.md`** - this is not a session report. It is the operator's private
  working context file: the credential, the subscription id, Stripe pricing, the Mercury
  payout account, the local paths of four other projects. It was never written to be read
  by anyone else and nothing about the audit claim requires it. Remove it from the tree
  (`git rm --cached` and add to `.gitignore`), or move it outside the repository.

Everything else in the 86 - the defects, the residuals, the wrong turns, the operator's
methods - should ship as it stands.

---

## TASK 3 - the verdict, in full

### 3.1 Verdict

**SUPERSEDED BY REVISION 1: the verdict is SAFE AFTER CLEANUP IN THE CURRENT TREE.** The
files to change are the table immediately below, which was originally written to argue that a
current-tree cleanup would be *insufficient*. With the credential reclassified as never-used,
that same table is now the sufficient list. Nothing in history needs touching - and the
personal information that does remain in history is accepted rather than fixed, for the
reasons in 3.2.

*Original text, retained:* **HISTORY IS CONTAMINATED**, as stated at the top. The credential
is named there, redacted, with its 9 commits. No attempt was made to fix it, per the prompt.

For completeness, the *other* two verdicts and why neither applies: it is not SAFE TO PUBLISH
AS IS, because of the credential and the home IP. It is not SAFE AFTER CLEANUP IN THE CURRENT
TREE either - a current-tree cleanup would be exactly this list -

| File | Why |
|---|---|
| `CLAUDE_ClawFactory.md` | line 1279 credential; subscription id; Stripe/Mercury; four private project paths |
| 12 x `docs/session_reports/*` (listed in Task 1.1 row 8) | operator's home IP |
| `REPORT.md`, `reports/AZURE_SIGNING_WIRED_20260706.md`, `docs/session_reports/HANDOFF_2026-08-20_card258.md`, 4 x `validation-runs/phase1-bake-*/log.md` | Azure subscription id |

- but it would not be sufficient, because the credential is in eight commits besides the one
`HEAD` reads from, and a current-tree edit does not reach them.

### 3.2 What a history rewrite would break, and the recommendation

Removing the credential from history requires rewriting it (`git filter-repo` or equivalent).
**Rewriting changes every commit hash from the affected commit forward.** The earliest
affected commit is `831b3e0`, 2026-05-11, so **every one of the roughly 430 commits after it
would get a new hash**, including:

- **`25945d5`** - "release: bump to v1.4.4", the build commit named in the release record.
- **`9111e9b`** - the commit tag `v1.4.4` points at, published 2026-08-29 with the signed
  `ClawFactory-Secure-Setup.exe` asset.

What that breaks, concretely: **all 22 tags** would need to be force-moved or would dangle;
the **published v1.4.4 release would name a commit that no longer exists**, destroying the
one link between the shipped signed binary and the source that produced it - which is the
exact claim this product makes and the reason `.gitattributes` and the build gates exist;
`released-versions.tsv`, the close-outs, the release notes and the failure catalogue all cite
commit hashes in prose and would every one of them become wrong; the stale
`claude/gracious-pasteur-0Qhmd` branch and any clone would diverge irrecoverably; and the
local stash would be orphaned. A rewrite trades a rotatable password for the permanent loss
of the provenance chain.

**Recommendation, one path: rotate the credential and accept the historical exposure.**

- The password is trivially rotatable and, per the live check, currently protects nothing -
  the resource group is empty. Change it wherever the operator uses it, primarily
  `C:\Users\bmcki\.azure-clawfactory-creds` and anywhere it was reused, **before** the
  repository is made public, and treat the string in history as burned. A burned password is
  a non-event; a broken release provenance chain is permanent.
- Then do the current-tree cleanup in the 3.1 table - not because it removes the secret from
  history, it does not, but because the *current* tree is what a reader sees first and it
  should not advertise the value.
- Do **not** publish a fresh repository and retire this one. It would achieve the same
  history-erasure as a rewrite, with the same loss of provenance, plus the loss of 464
  commits of audit trail, all 22 tags, and the v1.4.4 release record - for a password.

Nothing in this recommendation was acted on. No file was changed, no history was touched.

### 3.3 The command, not run

The operator would make the repository public with:

```bash
gh repo edit BuzzardsBay/clawfactory-secure-setup --visibility public --accept-visibility-change-consequences
```

**I have not run this command and have not changed the repository's visibility.** It remains
`"private": true`. Visibility is an irreversible outward-facing action and it is the
operator's alone. Recommended order: rotate the credential, then clean the current tree, then
run the command.

---

## Prompt corrections (PROMPT 15: "IF THIS PROMPT IS WRONG, SAY SO")

1. **"both download buttons" - half right, and the two halves fail differently.**
   `docs/index.html:990` points at `BuzzardsBay/ClawFactory-Secure-Setup/releases/latest`;
   that repository is private, so it 404s for a stranger, exactly as stated. But
   `docs/index.html:973` points at `BuzzardsBay/clawagent-setup/releases/latest`, and that
   repository is **public**. It does not 404. It resolves to release `v1.0.4`, which has
   **zero assets** - the ClawAgent assets were removed in this repo's own most recent
   close-out. So the ClawAgent button lands on a release page with nothing to download.
   Both download paths are broken; making *this* repository public fixes only one of them.
2. **The stash changes the arithmetic.** A sweep over `--all` sees 1285 blobs including 245
   vendored Microsoft signing binaries and the generated `signing/metadata.json`. None of
   those would become public. Only the 1034 blobs reachable from `--remotes --tags` matter,
   and every count in this document uses that set.
3. **`signing/metadata.json` is worth naming even though it is safe.** It sits in the stash
   with the Trusted Signing endpoint, `clawfactory-signing` and `clawfactory-cert`. It
   contains no credential, and it is not public - but if that stash is ever committed it
   becomes an infrastructure disclosure, and `.gitignore` is the only thing preventing it.

---

## TASK 4 - close-out mechanics

- **4.1 Dispatch card** - posted via `POST {DISPATCH_URL}/api/agent/update` from PowerShell
  with the `x-frontier-secret` header, action `create`. Returned **card id 312**, status
  `blocked`, priority 1. `python` is blocked by Windows Application Control on this machine
  and was not used. The secret was read from `C:\Users\bmcki\FrontierAI\.env` and never
  printed; only its length was reported.
- **4.2 Git** - `git status --short` was run first and was empty. Explicit per-file staging
  of this one file. No `git add -A`. Pushed to `origin/main`. **No tag.**
- **4.3** - this document, committed and printed in full, unprompted.

### What this session changed

| Changed | Not changed |
|---|---|
| This close-out, added | Repository visibility - still **private** |
| | Any shipped byte |
| | Any commit in history |
| | The credential (deliberately: rotation is the operator's) |
| | The home IP in 12 close-outs (deliberately: awaiting the operator's decision on Task 2.2) |

Four files were temporarily modified by the canary and restored byte-for-byte, verified by
SHA-256; they are not in this commit and their hashes are unchanged.

---

## ADDENDUM (Revision 1) - what the credentials were actually for, and two off-repo finds

Established after the original close-out, while answering the operator's question. **None of
this is in the repository, so none of it changes the publication verdict** - it is recorded
because it is the answer to "what are these for" and because the second file was not known to
exist.

**1. `C:\Users\bmcki\.azure-clawfactory-creds`** (`admin_user=clawadmin`, 22-char password,
written 2026-05-06 12:45). The Windows local administrator account for the Azure validation
VMs - the account an operator RDPs into a `cfv-*` box with, and the one auto-logon uses.
`scripts/azure-validate.ps1:194` passes `--admin-username $AdminUser --admin-password $pw` to
`az vm create`, with `$AdminUser` defaulting to `clawadmin`. **But the script never reads this
file**; it prompts (line 173). The file was a note to self, and per the operator the value was
never used. Verified identical to the `CLAUDE_ClawFactory.md:1279` value by direct comparison
with a control that correctly reported DIFFER on a deliberately altered copy.

**2. `C:\Users\bmcki\.clawtest-vm-creds`** (8-char user, 9-char password, written 2026-05-06
08:29) - **not Azure at all.** It is the login for a **local VirtualBox VM named `ClawTest`**.
Evidence: `validation-runs/v1.0.4-20260506T145651Z/REPORT.md:64` records
`VBoxManage guestcontrol run` under that username, describing it as "a split-token admin";
and `C:\Users\bmcki\VirtualBox VMs\ClawTest\` exists. Independent corroboration that it is not
an Azure credential: the password is 9 characters, and Azure's Windows rule is a 12-character
minimum, enforced client-side at `scripts/azure-validate.ps1:181` - `az vm create` would have
rejected it. This is the v1.0.4 validation attempt of 2026-05-06, before the move to Azure.
**Checked against all 1034 public blobs: zero hits, with a positive control returning 179.**

   **The `ClawTest` VM still exists on disk.** It is the one credential file deliberately NOT
   deleted with the other nine: binning it alone would lock the operator out of a disk image he
   still has.

   **Corrected twice, both figures having been reported wrongly first:**

   - **Footprint is 72,039,842,431 bytes (67.1 GB), not 19.4 GB.** The first number sized only
     `ClawTest.vdi`. The folder also holds three snapshot disks
     (`Snapshots\{7dbbdb04...}.vdi` at 31.9 GB, `{b458051d...}.vdi` at 9.4 GB, and a small
     third) and three saved-memory `.sav` files totalling 11.2 GB. Registered snapshots:
     *"Clean Windows 11 - ready to test"*, *"WSL1 installed ready to test clawfactory fix"*,
     and *"Clean-Win11"* - the last described in its own metadata as the
     *"Post-cleanup baseline 2026-05-06 ... used as revert target for validation loop"*.
   - **State is `saved`, not powered off.** `VBoxManage showvminfo` reports
     `VMState="saved"` - suspended with its RAM written to those `.sav` files, which is why
     they exist. Saved is not running.

   **Nothing is running, here or in Azure.** Stated explicitly because "still exists" was
   misread as "still active", which is this close-out's wording problem and not the operator's:
   `Get-Process VirtualBox*,VBox*` returns **none**; `lastStateChange` is
   **2026-05-06T14:49:38Z** and the newest `Logs\VBox.log` is **2026-05-06 09:21**, so it has
   been untouched for nearly four months; it is a local VirtualBox guest on the operator's own
   PC, so it bills nothing and is not internet-exposed; and `az vm list` **with no
   resource-group filter, across the whole subscription**, returns zero rows, so no Azure VM
   exists in any state. The only cost of `ClawTest` is disk.

   **Consequence for the removal command:** a machine in `saved` state cannot simply be
   unregistered and deleted - the saved state must be discarded first, or VirtualBox refuses.
   The command handed to the operator therefore runs `discardstate` before
   `unregistervm --delete`.

**3. Eight SAS-token files**, `.cfa-10{2,3,4}-sas.txt` and `.cfv-1{18,19,20,21,22}-sas.txt` in
the profile root. Each holds one read-only download URL for an installer build in
`clawfactoryvalc467/installers`, e.g.
`https://<account>.blob.core.windows.net/installers/ClawFactory-Secure-Setup-1.0.22.exe?se=...&sp=r&spr=https&sv=2026-04-06&sr=b&sig=...`
- scoped `sp=r` (read), `sr=b` (single blob), `spr=https`. **All expired**; the latest is
`se=2026-05-12`, three and a half months before this session. These are exactly the
"SAS-signed installer URLs" `.gitignore` warns about; confirmed **none is tracked by git**.

**Disposition.** Files 1 and 3 are dead and were recommended for deletion; the delete command
was refused by this session's tool-permission classifier and was therefore handed to the
operator to run rather than worked around. **He ran it: all nine are confirmed gone** - a
re-check found `.azure-clawfactory-creds` absent and zero `.cf*-sas.txt` remaining.

**File 2 and the `ClawTest` VM: deleted on the operator's instruction, 2026-08-29.** Recorded
because the documented removal command was wrong and needed two repairs in flight:

1. `unregistervm ClawTest --delete` **failed** with `VBOX_E_OBJECT_IN_USE` - *"Cannot close
   medium ...{b458051d}.vdi because it has 1 child media"*. The three disks form a chain
   (`ClawTest.vdi` -> `{b458051d}.vdi` -> `{7dbbdb04}.vdi`) and VirtualBox will not release a
   parent while a child is open. The VM was left unregistered but 67.1 GB stayed on disk - a
   half-done state that looks finished if the exit code is not checked. It exits 1; PROMPT 15's
   "check the exit code of EVERY call" is what caught it.
2. The repair is `closemedium disk <uuid> --delete` **leaf-first**: `{7dbbdb04}`, then
   `{b458051d}`, then the base. All three returned exit 0 and `list hdds` then returned nothing.
   A residual sweep removed the three `.sav` memory files (11.2 GB), four `.nvram` files, the
   `.vbox` definitions and the logs.

**Verified by free space, not by the absence of an error:** C: went from 1,414.0 GB to
1,481.1 GB free, a delta of **67.1 GB**, matching the measured footprint. `list vms` returns
nothing, the folder is gone, and `.clawtest-vm-creds` is gone. Note also that the PowerShell
5.1 `NativeCommandError` noise around each `closemedium` was progress output on stderr, not a
failure - the recorded trap about not redirecting a native command's stderr under
`ErrorActionPreference` applies exactly here, and the exit codes are what were read.

### The one thing the operator must do before anything else

~~Rotate the `clawadmin` password.~~ **Superseded by Revision 1: there is nothing to rotate.**
The pair was never used, no VM exists, and no script reads the file. The remaining steps are
the Task 2.2 redactions, then the command in 3.3 - run by the operator, not by this session.
