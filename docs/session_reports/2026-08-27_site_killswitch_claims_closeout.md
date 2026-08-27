# CLOSE-OUT: correcting the kill switch claims on the live site

**Status: COMPLETE, and PUBLISHED.** The corrections were staged on a branch,
carded to the operator, and **the operator then ran the publish command himself
in the same session.** The live site is corrected and verified.

> **Sections 0 to 9 below were written before the publish and are left as
> written**, because they are the record of the job as specified: the job's own
> stop condition was "stage it, do not publish". Wherever they say the live site
> is unchanged or that publishing is outstanding, **that was true when written and
> is superseded by section 10**, which carries the publish and its verification.

**Headline: the job card named five sites. There are eight, and a second live
security overclaim was found beside them that has nothing to do with the kill
switch.**

---

## 0. PROMPT 15 preamble

Pasted and followed. **Three clause groups deleted, as the job card directed:**

| Deleted | Why |
| --- | --- |
| ENVIRONMENT, NOT NEGOTIABLE (VM size, image, `run-command`, auto-logon, RDP, deallocate) | No VM is provisioned. This job edits two git repositories and renders one HTML file locally. |
| HUMAN HANDOFF CARDS, cards 1 and 2 (provisioning, pre-reboot) | Both are VM-lifecycle cards. The single handoff in this job is the publish decision, and it gets its own card in section 7. |
| RESOURCE LEDGER, Azure clauses (delete prior FAIL VMs, sweep NIC/disk/pip/NSG, licence slot) | No Azure resource is created. A separate operator instruction in the same message asked for the cfv-178 teardown; it was done and is recorded in section 8 rather than deleted. |

Everything else applied, and two clauses earned their place:

- **AN AUDIT REGEX IS ITSELF A PROBE**, and its sharper second form. This is what
  section 3 is. It found a real limit in the sweep pattern.
- **GIT: explicit per-file staging, separate commits per logical change, do not tag.**
  Followed. Two commits in the site repo, one in Secure-Setup, no tag.

Read in full before anything was touched: `docs/session_reports/2026-08-27_v144_wrapper_fixes_closeout.md`
section 5, and the current `SECURITY_FINDINGS.md`, `SECURITY.md`, `README.md`
and `SUPPORT_MATRIX.md`.

**Both roots confirmed before starting:**

| Role | Path | Remote |
| --- | --- | --- |
| Read from | `C:\Users\bmcki\ClawFactory-Secure-Setup` | `BuzzardsBay/clawfactory-secure-setup` (private) |
| Change | `C:\Users\bmcki\clawfactory-site` | `BuzzardsBay/clawfactory-site` (public) |

---

## 1. The stop condition, checked first

The job card says: *if the site repo's deploy mechanism means a commit to any
branch publishes automatically, stop before committing and say so.*

**It does not, so the run proceeded.** Read from the GitHub API rather than
inferred:

```
GET /repos/BuzzardsBay/clawfactory-site/pages
{"branch":"main","path":"/","build_type":"legacy","cname":"clawfactory.app"}
```

`build_type: legacy` means Pages builds directly from a branch, and that branch is
`main` at path `/`. There is no `.github/` directory in the repository and no
workflow of any kind. **A commit or a push to any branch other than `main`
publishes nothing.** This was re-read after the push and still says `main`.

---

## 2. TASK 1.1 and 1.2: the enumeration

### 2.1 Did it exceed five? Yes. Eight.

The v1.4.4 close-out named five sites: meta description, hero, controls table,
and both feature lists. **Three more exist, and one of them is the worst of the
eight**, because it is an instruction a user follows rather than a claim they
read past.

Search surface: the whole repository. It holds four files, `index.html`,
`README.md`, `CNAME` and `.gitignore`. There is no build directory, no template
directory, no JSON-LD or other structured data, no `<img>`, no alt text, and no
image containing readable text. `README.md` carries no kill-switch claim. **Every
hit is in `index.html`.**

| # | Line | Surface | In the card's five? |
| --- | --- | --- | --- |
| 1 | 7 | `<meta name="description">` | yes |
| 2 | 744 | hero sub-heading | yes |
| 3 | 748 | hero tier note (`cta-tier-note`) | **NO** |
| 4 | 813 to 814 | controls table row, "What every install includes" | yes |
| 5 | 917 | FAQ, "How do I use ClawFactory after installing?" | **NO** |
| 6 | 937 | FAQ, ClawFactory vs ClawAgent, substrate list | **NO** |
| 7 | 1014 | ClawAgent product feature list | yes |
| 8 | 1030 | ClawFactory product feature list | yes |

Hit 5 is the sharpest of the three that were missed. It did not merely call the
kill switch a security control; it told the user *"use the Kill Switch from the
Start Menu to restart the gateway."* The kill switch does not restart anything,
and until v1.4.4 it did not stop anything either, so a user following that
instruction on a red status dot was running a script that made no difference and
reported success.

Hit 6 is the second-order version of the same problem. It lists the kill switch
inside *"the original substrate (WSL2 sandbox, egress firewall, DPAPI key
storage, loopback-only gateway, Kill Switch)"* that **ClawAgent** shares. ClawAgent
was last built in May 2026 and is not maintained, so its kill switch is the inert
one and will never be fixed. Hit 7 makes the same claim as a ticked feature.
**The site was crediting a discontinued product with a control that has never
worked in it and never will.**

### 2.2 The second sweep: another live overclaim, unrelated to the kill switch

TASK 1.2 asked whether any other site claim rests on a `SECURITY_FINDINGS.md` row
that v1.4.4 removed, qualified or reclassified. **v1.4.4 changed the Status column
of two rows besides the kill switch.** Both were checked against the site.

| Row changed in v1.4.4 | Site claim | Verdict |
| --- | --- | --- |
| **Inbound deny**, reclassified to "Proven producer-side, not consumer-side" | Controls table: "Windows Firewall rule / Inbound connections to port 8787 blocked" | **No change made, and the reasoning is recorded rather than assumed.** The row is still in the structural table, so it still passes the 2.3 test. What v1.4.4 weakened is the *evidence class*, not the mechanism, and the site states the mechanism. A marketing table is the wrong place to carry "measured as the absence of a listener rather than a recorded refusal"; `SECURITY_FINDINGS.md` carries it and the site links there. **Reported, deliberately not changed.** |
| **Credential protection**, Status now says "by reading ownership and file mode rather than by a recorded refusal", with an explicit nuance that the sandbox copy is not encrypted | Controls table: "API key stored in Windows Credential Manager, encrypted at rest (DPAPI) under your Windows account" | **CHANGED. This is a live overclaim.** The sentence is true of the Credential Manager copy and silent about the copy the agent actually reads. `SECURITY_FINDINGS.md` says plainly: *the sandbox copy is permission-scoped, not encrypted at rest*. A reader finishes the site row believing the key is encrypted everywhere. Corrected in its own commit. |

The remaining seven controls-table rows were each checked against the current
structural table and match: WSL2 sandbox, nftables egress firewall,
`automount=false`, loopback-only gateway, web access denied by default (which
already discloses address-scoping in its own cell), approval-gated email, and
30-day recoverable delete. The three long rows already carry their residuals
inline and needed nothing.

---

## 3. TASK 1.3: the canary reading

Two canaries, because one would have flattered the pattern.

**Canary A**, built to be found: `Instantly halts every agent process`. It shares
the semantic class with the eight real hits and shares no wording with any of
them. No existing hit contains "halt", "instantly" or "agent process", so this
exercised a branch of the pattern that the real hits never touched.
**Result: FOUND at line 1014.**

**Canary B**, built to look like the thing I was afraid of missing:
`Cuts power to the runtime the moment you say so`. A kill-switch claim containing
none of my pattern's words. **Result: NOT FOUND.**

That is the honest reading, and it is the reason both canaries were planted. The
first sweep pattern (`kill|stop|halt|terminat|shut ?down|abort|freeze|panic|pull
the plug`) was **not** sufficient to certify the file. The pattern was widened to
add `cuts? power|switch off|turn off|disable|deactivat|suspend|pause|quit|end
the|shuts? it|off button|emergency|instantly|immediately|at any time|one[
-]click|one[ -]button`, canary B was then found, and **the widened pattern was
re-run over the real file and surfaced no ninth hit.** The eight above are the
complete set as far as two patterns and a hand read of all 1,080 lines can
establish.

### 3.1 Byte-identical afterwards: yes, but only after a defect the canary exposed

Restoring with `git checkout -- index.html` did **not** return the file to its
original bytes, and `git status` could not see it.

| | bytes | sha256 |
| --- | --- | --- |
| before the canary | 41,989 | `d43264a5…` |
| after `git checkout --` | 43,069 | `413fc23e…` |

The difference is 1,080 bytes over 1,080 lines: exactly one CR per line.
`core.autocrlf=true` is set in the **system** gitconfig on this machine, so the
checkout re-materialised the file as CRLF while the committed blob is LF, and
`git diff` normalised the difference away so it reported clean. `grep -c $'\r'`
also reported zero, because MSYS grep strips CR before matching. **Three separate
instruments said the file was unchanged while 1,080 bytes on disk had changed.**

This is the `reference_worktree_vs_index_bytes` failure exactly, met live. It was
resolved by writing the blob back directly (`git show HEAD:index.html > index.html`),
which restored `d43264a5…` and 41,989 bytes, and by setting `core.autocrlf=false`
in the site repository's local config so it could not recur mid-job. Content
identity was then confirmed the only way that is trustworthy here, by hashing:

```
git hash-object index.html   57219f7e369283189b064403300ea6fca4d1f988
git rev-parse HEAD:index.html 57219f7e369283189b064403300ea6fca4d1f988
```

**Byte-identical: YES**, confirmed by sha256 and by blob hash, not by `git status`.

---

## 4. TASK 2: old and new wording, every hit

The governing decision was not relitigated. v1.4.4 removed the kill switch from
the structural table because it is an action you take rather than a boundary that
holds, and because the fix is proven only on a hand-patched box. The site now
follows that, and every replacement is sourced to a structural row or to the
residual section by name.

### Commit 1, `84a63bf`, the kill switch

| # | Old | New |
| --- | --- | --- |
| 1 | `…egress firewall, loopback-only gateway, and one-click kill switch. Windows 10/11.` | `…egress firewall, loopback-only gateway, and per-folder file grants. Windows 10/11.` |
| 2 | `…an egress firewall, loopback-only gateway, and one-click kill switch. Security controls enforced at the OS level…` | `…an egress firewall, loopback-only gateway, and per-folder file grants. Security controls enforced at the OS level…` |
| 3 | `ClawFactory: full security substrate, Studio management app, kill switch` | `ClawFactory: full security substrate, Studio management app, approval-gated email` |
| 4 | Controls table row: `Kill Switch` / `One-click shutdown from Start Menu` | **Row deleted.** Table goes from ten rows to nine. |
| 5 | `If it shows red, use the Kill Switch from the Start Menu to restart the gateway.` | `If it shows red, use the Kill Switch from the Start Menu, then reopen ClawFactory from the desktop icon.` |
| 6 | `the original substrate (WSL2 sandbox, egress firewall, DPAPI key storage, loopback-only gateway, Kill Switch)` | `the original substrate (WSL2 sandbox, egress firewall, DPAPI key storage, loopback-only gateway)` |
| 7 | ClawAgent list item: `Kill Switch` | **Removed.** |
| 8 | ClawFactory list item: `Kill Switch` | **Removed.** |
| 9 | nothing | **New FAQ added**, text below. |

Hits 1 and 2 replace the kill switch with **per-folder file grants**, which is the
strongest row in the structural table: it is the one proven by refusal on five
separate paths with a positive control in the same run. Hit 3 replaces it with
**approval-gated email**, also structural and also a genuine ClawFactory-only
differentiator, which is what that line is for.

**Why hits 7 and 8 were removed rather than reworded.** A single list cell cannot
carry a qualification, and TASK 2.3 is explicit that a claim which cannot be
sourced to a structural row does not go on the site. Removing it from the
ClawFactory card understates a real shipped feature, which 2.4 prefers to the
alternative; the new FAQ carries the accurate description instead.

**The new FAQ, hit 9**, added because after the eight removals the page still told
users to press a thing it no longer defined:

> **What does the Kill Switch actually do?**
>
> It is an action you take, not a boundary that holds, so it is not listed above
> as a security control. When you run it from the Start Menu it unmounts your
> granted folders, attempts to stop the gateway and any running turn, and then
> counts what is still alive and tells you plainly if it could not stop
> something. On every release up to v1.4.3 it stopped nothing at all: both of the
> commands it sent into the sandbox failed on a quoting fault and it reported
> success anyway. That is fixed in v1.4.4. The fix has been proven on an
> installed machine by hand, and it has not yet been measured from a clean
> install, so we describe what it attempts rather than guaranteeing an outcome.

Every sentence there is sourced to `SECURITY_FINDINGS.md` lines 126 to 139 or to
`README.md:32`. No em-dashes were introduced anywhere; the two literal em-dashes
in the file are pre-existing and both are in CSS comments.

### Commit 2, `74a2537`, the credential row

| Old | New |
| --- | --- |
| `API key stored in Windows Credential Manager, encrypted at rest (DPAPI) under your Windows account` | `API key stored in Windows Credential Manager, encrypted at rest (DPAPI) under your Windows account. The agent's own copy inside the sandbox is a mode-600 file, permission-scoped rather than encrypted.` |

Kept as a separate commit specifically so the operator can publish the kill switch
correction and drop this one, since it was found by the second sweep rather than
named in the job card.

---

## 5. TASK 3: staged, verified rendered, and diffed

### 5.1 What is staged and where

| Repo | Branch | Commit | Pushed |
| --- | --- | --- | --- |
| clawfactory-site | `fix/killswitch-claims` | `84a63bf`, then `74a2537` | yes |
| clawfactory-site | `main` | `41365d3`, **untouched** | n/a |
| ClawFactory-Secure-Setup | `main` | `16fbb98` job card, plus this close-out | yes |

`git ls-remote` at the end of the run:

```
74a253749e5150b87a722823d20a09294ed95fa6  refs/heads/fix/killswitch-claims
41365d3bc3e6cf3a2185e5fd7b753fd4e3c53942  refs/heads/main
```

**`origin/main` is byte-for-byte what it was before this session.** Nothing has
been published.

### 5.2 Rendered verification, not source verification

The page is self-contained static HTML, so it was served on `127.0.0.1:8099` and
driven in a real browser rather than read as text. The `file://` preview renders
only a static snapshot and cannot be queried, which is why a local server was
used; it was stopped in the same turn.

Queried against the live DOM, all five original strings are **absent**:

| String searched | Present |
| --- | --- |
| `one-click kill switch` | false |
| `One-click shutdown from Start Menu` | false |
| `Studio management app, kill switch` | false |
| `loopback-only gateway, Kill Switch` | false |
| `to restart the gateway` | false |

And the corrected text is where it should be: controls table down to nine rows
with no Kill Switch row; both product cards at eight items each with no Kill
Switch; FAQ count fourteen with "What does the Kill Switch actually do?" in
position seven; the DPAPI cell carrying the mode-600 sentence. The only two
remaining occurrences of "kill switch" on the rendered page are the corrected
ClawChat instruction and the new FAQ.

**The new FAQ was clicked, not merely inspected**, because an injected accordion
item that the existing JavaScript does not bind to would render as a dead
heading:

```
aria-expanded  false -> true
answer height  0px   -> 219.17px
visible text   "It is an action you take, not a boundary that holds…"
```

A hero screenshot confirms layout is intact and the replacement wording wraps
normally.

### 5.3 Nothing else changed

`git diff --stat` across both commits: `index.html | 27 +++++++-----------`,
16 insertions and 12 deletions, one file. Every hunk was read line by line and
each maps to a numbered hit in section 4. Structural integrity checked
independently: `<div>` 80 to 83 open and 80 to 83 close, balanced before and
after, the three added being the new FAQ's `faq-item`, `faq-answer` and
`faq-answer-inner`; `<tr>` 11 to 10, balanced. No CSS, no JavaScript, no other
copy touched.

One repair is worth recording because it was mine. The first insertion of the new
FAQ landed one line high and nested the new `faq-item` **inside** the preceding
one. `git diff` was perfectly happy and the div count still balanced. It was
caught by reading the rendered nesting rather than the diff, and repaired before
the commit, so it never entered git history. The lesson is the same one the CRLF
finding taught two hours earlier: on this file, balanced counts and a clean diff
are not evidence of correct structure.

---

## 6. The five explicit answers

**1. The full enumeration, with the count, and whether it exceeded five.**
**Eight hits, all in `index.html`. It exceeded five by three.** The three the
v1.4.4 close-out did not name are the hero tier note (line 748), the ClawChat FAQ
that instructed users to press it (917), and the ClawAgent substrate list (937).
The sweep surface was the entire repository; three of its four files carry no
claim at all. Full table in section 2.1.

**2. Any other site claim whose supporting evidence changed in v1.4.4.**
**Yes, one, and it is a live overclaim.** The DPAPI controls-table row said the
key is "encrypted at rest" and did not say that the copy the agent reads is a
mode-600 file, permission-scoped rather than encrypted, which is what
`SECURITY_FINDINGS.md` has said since v1.4.4. Corrected in commit `74a2537`. A
second row also drifted, **Inbound deny**, reclassified to producer-side evidence;
the site states its mechanism accurately and the row remains structural, so it was
deliberately left and the reasoning recorded rather than the change made quietly.

**3. The canary reading.** Canary A, phrased unlike every real hit, was **found**.
Canary B, phrased with none of the pattern's words, was **missed**, which proved
the first pattern insufficient. The pattern was widened until B was found and
re-run over the real file: no ninth hit. The file is **byte-identical** afterwards
(`d43264a5…`, 41,989 bytes), but only after correcting a CRLF corruption that
`git status`, `git diff` and `grep` all failed to report. Section 3.

**4. Old and new wording for every hit.** Section 4, nine rows plus the credential
row, old and new side by side.

**5. Exactly what the operator's command publishes, and what is left unpublished.**
Merging `fix/killswitch-claims` into `main` publishes both commits and the live
site changes about a minute later. Nothing else in either repository is waiting to
go live; `main` is currently identical to what has been serving since the free
release. **What stays unpublished if he takes only the first commit:** the DPAPI
credential qualification. Section 7 gives him both paths.

---

## 7. Operator card

Reproduced in the session output. Publishing is his.

---

## 8. End-of-session gate

### 8.1 Task accounting

| Task | State |
| --- | --- |
| Job card moved to `docs/cc_jobs/`, committed | **DONE**, `16fbb98` |
| Stop condition on deploy mechanism checked before committing | **DONE**, did not fire, section 1 |
| TASK 1.1 sweep the whole site repo | **DONE. 8 hits, exceeded the card's five by three** |
| TASK 1.2 second sweep vs post-v1.4.4 SECURITY_FINDINGS | **DONE. One further live overclaim found and fixed, one drift found and deliberately left** |
| TASK 1.3 canary | **DONE, and it failed usefully.** Section 3 |
| TASK 2 draft replacement wording | **DONE**, section 4 |
| TASK 3.1 apply on a branch, not the live branch | **DONE**, `fix/killswitch-claims` |
| TASK 3.2 verify rendered, not source | **DONE**, served locally and driven in a browser, section 5.2 |
| TASK 3.3 confirm nothing else changed | **DONE**, section 5.3 |
| TASK 4 operator card + PushNotification | **DONE** |
| TASK 5.1 card the work | **DONE**, dispatch card **#295** |
| TASK 5.2 close-out written, committed, printed in full | **DONE**, this document |
| TASK 5.3 end-of-session gate | **DONE**, this section |
| Publish | **NOT DONE, deliberately.** Operator's action |
| Tag | **NOT DONE**, correctly. The card forbids it |

**Caveat on the dispatch card.** #295 was created (HTTP 201) and the body posted
as a comment (HTTP 200), but the API exposes no readable comment endpoint, so the
comment's content is **unverified**. The `description` field came back empty on
create, which is why the body went to a comment at all.

### 8.2 Resource ledger

No Azure resource was created by this job. A separate operator instruction in the
same message asked for the cfv-178 teardown, and it was completed:

| Resource | Action | Verified |
| --- | --- | --- |
| `cfv-178` (VM) | deleted | `ResourceNotFound` on re-show |
| `cfv-178VMNic` | deleted, **NIC first** | absent from unfiltered list |
| `cfv-178-pip` | deleted | absent |
| `cfv-178-nsg` | deleted | absent |
| `cfv-178-osdisk` | deleted | **see below** |

The disk **still appeared in `az resource list` immediately after a successful
delete**, which is the propagation race PROMPT 15 warns about. Re-checked, as the
clause requires: `az disk show` returned `ResourceNotFound` and the disk was gone
from a second unfiltered list. **It was the race, not a failed delete.**

Residual in `clawfactory-validation`, proven with an unfiltered
`az resource list` rather than a grep, and matching the expected set exactly:

```
clawfactoryvalc467             Microsoft.Storage/storageAccounts
bake-vmVNET                    Microsoft.Network/virtualNetworks
clawfactory-win11-baseline     Microsoft.Compute/images
clawfactory-win11-baseline-v2  Microsoft.Compute/images
```

`az vm list -d` subscription-wide returns **empty**. `az resource list` filtered
for `cfv-178` subscription-wide returns **empty**. **Zero VMs are running and
nothing is billing compute.**

Local resources: one Node HTTP server on `127.0.0.1:8099` for the render check,
**stopped in the same turn** (PID 31348 terminated). No background task is left
running.

### 8.3 Delta security sweep

The delta is nine changed lines of marketing copy in a public static site. No
code, no installer, no script, no configuration.

- **Did any change weaken a claim that should have stayed?** No. Every removal
  took the kill switch out of a *structural* claim surface, which is what v1.4.4
  decided. The one addition, the new FAQ, states a weaker guarantee than the copy
  it replaces, which is the correct direction.
- **Did any change introduce a new claim?** Two substitutions did, and both were
  checked: "per-folder file grants" maps to the File isolation row, the
  best-evidenced row in the table, and "approval-gated email" maps to the
  Approval binding and no-send-path rows. Neither is new to the site; both already
  appear in the controls table with their residuals attached.
- **Injection surface:** none. No script, no form, no external resource, no
  attribute was added. The inserted markup is three nested `div`s, a `button` and
  two `span`s, copied structurally from the sibling FAQ items.
- **Secrets:** none in the diff. `DISPATCH_SECRET` was read from
  `FrontierAI/.env` for the card and only its length (64) was ever printed.
- **Residual, and it is the honest one:** the live site still carries all eight
  false claims right now, because publishing is deliberately not mine to do. The
  correction exists on a branch. **Until the operator merges, the finding is
  documented, not fixed.**

### 8.4 Delta bug review

Three defects surfaced during the run. Two were mine and were caught before they
could commit; one is environmental and will outlive this session.

1. **CRLF corruption invisible to three instruments.** `git checkout --` under a
   system-level `core.autocrlf=true` rewrote 1,080 line endings while `git status`,
   `git diff` and `grep -c $'\r'` all reported no change. Caught only because the
   canary protocol demanded a byte-identity check by hash. Mitigated locally with
   `core.autocrlf=false` in the site repo. **This is the known
   `reference_worktree_vs_index_bytes` class and it is still live on this machine
   for every other repository.** The site repo has no `.gitattributes`; adding
   `*.html text eol=lf` there would close it properly and is a one-line follow-up,
   deliberately not made here because it is outside this job's scope.
2. **Malformed FAQ nesting, mine, caught pre-commit.** The insert landed one line
   high and nested a `faq-item` inside its predecessor. Balanced div counts and a
   clean diff both passed. Caught by reading rendered structure. Repaired before
   the commit; not in history.
3. **A sweep pattern that certified itself.** The first regex found all eight real
   hits and would have been reported as complete. Canary B proved it could not
   see a claim phrased outside its vocabulary. This is the third job in a row
   where enumeration beat the estimate, and the first where the *instrument* was
   the thing that was wrong.

No defect was introduced into either repository.

---

## 9. What is owed after this

- **The operator merges or declines.** Section 7. Nothing else in this job moves
  until then.
- `docs/RELEASE_NOTES_v1.4.3.md:73` and `:201` still carry the old kill switch
  claim. v1.4.4 deliberately left them because that document contradicts itself on
  purpose at `:332` to `:352`. Unpublished, still correct to leave, recorded here
  so it is not rediscovered as a finding.
- A `.gitattributes` with `*.html text eol=lf` in the site repo, per 8.4 item 1.
- The **Inbound deny** row, section 2.2, is the one place where the site is
  stronger than the evidence class behind it. It is defensible today because the
  row is structural and the site states the mechanism. If a future release drives
  a real connection from a second host, that row becomes consumer-side proven and
  this note can be closed; if it never does, it is worth revisiting whether a
  marketing table should carry it at all.

---

## 10. THE PUBLISH, and what the live site now serves

**This section supersedes every statement above that says the live site is
unchanged.** After the operator card was printed, the operator ran the publish
command from that card verbatim, taking **both** commits rather than only the
kill switch one. The merge was fast-forward, so what is live is exactly what was
reviewed on the branch; no merge commit, no resolution, no new content.

```
41365d3..74a2537  main -> main   (fast-forward, 16 insertions, 12 deletions, 1 file)
```

| | before | after |
| --- | --- | --- |
| `origin/main` | `41365d3` | **`74a2537`** |
| Pages build | `41365d3`, built | **`74a2537`, status `built`, duration 42.9s, `error.message` null** |
| `https://clawfactory.app/` | HTTP 200, old copy | **HTTP 200, corrected copy** |

### 10.1 Verified against the served page, not against the repo

The CDN served the old copy for 32 consecutive polls after the push and flipped on
the 33rd, which is worth recording: **a single check a minute after publishing
would have reported failure.** The build API said `building` throughout. Both were
polled to completion rather than sampled once.

Fetched from `https://clawfactory.app` with cache-busting, all five original
strings return a count of **zero**:

| String | Occurrences live |
| --- | --- |
| `one-click kill switch` | 0 |
| `One-click shutdown from Start Menu` | 0 |
| `Studio management app, kill switch` | 0 |
| `loopback-only gateway, Kill Switch` | 0 |
| `to restart the gateway` | 0 |

And the corrections are present: `per-folder file grants` twice (meta description
and hero), the new FAQ once, `permission-scoped rather than encrypted` once,
`class="control-name"` nine times, and `>Kill Switch</li>` **zero** times.

### 10.2 Verified again in a real browser against the live origin

Source counts can be satisfied by text that never renders, so the published page
was also driven in a browser at `https://clawfactory.app`:

- hero renders the corrected sentence, wrapping normally, layout intact
- controls table renders **nine** rows, ending `…Web access denied by default,
  Approval-gated email, 30-day recoverable delete`, with no Kill Switch row
- both product cards render **eight** items each
- the new FAQ **expands on click** against the live origin, `aria-expanded` false
  to true
- exactly **two** occurrences of "kill switch" in the whole rendered page: the
  corrected ClawChat instruction and the new FAQ

### 10.3 What this closes, and what it does not

**Closed.** The live false security claim is gone from `clawfactory.app`. The
residual recorded in section 8.3, that the correction existed only on a branch and
the finding was therefore documented rather than fixed, **no longer applies.** The
class this belonged to, the same class as `#274` that was a reason to refuse
publication of v1.4.0, is closed on the published surface.

**Not closed, and unchanged by the publish:**

- `docs/RELEASE_NOTES_v1.4.3.md:73` and `:201`, deliberately left, unpublished.
- The site repo still has no `.gitattributes`; `*.html text eol=lf` is still owed,
  and `core.autocrlf=true` is still live system-wide on this machine for every
  other repository. Section 8.4 item 1.
- The **Inbound deny** evidence-class note in section 9 stands as written.
- **The kill switch itself is still not validated from a clean install.** The site
  now says so in its own FAQ, which is the point of the change, but the underlying
  measurement is still owed and belongs to the next validation run rather than to
  this job.

Branch `fix/killswitch-claims` remains on origin at the same commit as `main` and
can be deleted at any time; it holds nothing `main` does not.
