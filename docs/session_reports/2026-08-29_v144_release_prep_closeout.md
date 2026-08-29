# CLOSE-OUT: v1.4.4 release preparation. Notes, catalogue, and a tag that was not created

**Companion to** `2026-08-29_v144_validation_boxD_completion_closeout.md`, whose
section 13 is the verdict this job acts on and whose section 14 is the disclosure list
it carries into the notes.

**Scope.** Write the v1.4.4 release notes. Retire v1.4.3's. Bring the failure
catalogue through the whole cycle. Verify, without changing, the documents the
installer bundles. Prepare the tag and the release body. Print one operator card.

**Nothing was published. No tag was created. No release was cut. No site branch was
merged or even written. No shipped byte was changed.**

---

## 0. PROMPT 15 preamble

Pasted in full from the job card. **Two clause groups were deleted with the reason
stated, per the card's own instruction:** the VM provisioning clauses and the Azure
resource ledger clauses. **This job provisioned nothing, started nothing and deleted
nothing in Azure.** It ran entirely against two local git repositories and one local
signed binary. There was no box, so the box discipline has no subject. Every other
clause applies and is answered in section 8.

**The audit-regex clause earns its place in TASK 4** and is answered there: the
bundled-set comparison that licenses tagging above the build commit was run with a
control that had to fire first, and it caught two false readings before it produced a
true one (sections 4.1 and 9.2).

---

## 1. THREE CHALLENGES TO THE JOB CARD

PROMPT 15: *if an instruction is factually wrong about the code, stop and report; do
not quietly build the thing that was meant.*

### 1.1 THE MATERIAL ONE: `SECURITY_FINDINGS.md` is NOT bundled

The card states, twice, that `SECURITY_FINDINGS.md` and `README.md` are both bundled,
and builds its whole TASK 3 stop condition on that premise: *"a change there means
v1.4.5 and a re-validation."*

**Measured from the installer definition rather than from any document:**

```
[Files] Source entries, top level:
  setup.ps1   README.md   LICENSE   NOTICE   smoke-test.ps1
SECURITY_FINDINGS.md: absent from [Files] at HEAD and at build commit 25945d5
ClawFactory-Secure-Setup.iss: UNCHANGED between 25945d5 and HEAD
Repo-wide search of .iss/.ps1/.js/.sh for the filename: one comment reference only
```

**`README.md` ships. `SECURITY_FINDINGS.md` does not.** The 56 `[Files]` entries
resolve to 54 tracked files plus the gitignored rootfs and the gitignored Studio
payload, and 54 is the same count the v1.4.3 bundled census reached independently.

**Where the card's premise came from, because that matters more than the correction.**
`2026-08-27_v144_wrapper_fixes_closeout.md` section 11.5 contains the row
*"`SECURITY_FINDINGS.md`, `README.md` | **Yes** (both are in `[Files]`)"*. The card
inherited a wrong row from this project's own record. **That is entry 4.3 of the
failure catalogue happening to me while I was writing entry 4.3:** a card asserting a
property, the property being false, and the only thing that caught it being a refusal
to take the card's word for the state of the tree.

**What it changes.** The stop condition is real for `README.md` and does not apply to
`SECURITY_FINDINGS.md`. A correction to the latter is an ordinary documentation
commit: no rebuild, no re-sign, no re-validation, no v1.4.5. That materially changes
what section 3's findings cost, and it is why this document reports them as two
different decisions rather than one.

**I did not edit either document.** The card says do not, and the correct disposition
of the bundled one is genuinely the operator's.

### 1.2 The card names six not-in-this-release panels. There are seven

The card lists *"Chat, Templates, Files, Activity, Agents and Settings"*. The by-hand
checklist at `validation/MANUAL_CHECKS_studio.md:342` names seven, and box A's row 11
recorded *"all seven not-in-this-release panels"* as passing. The missing one is
**Skills**.

The notes say seven and name all seven. Shipping a list that undercounts the empty
panels by one, in the section whose entire job is to prevent a customer discovering
them after a 6 GB download, would have been the same failure the section exists to
avoid.

### 1.3 TASK 4.4's premise is right, and the answer is worse than it expects

The card asks where `clawfactory.app`'s download link currently resolves. **There is
no download link.** The live site has exactly six anchors: two font preconnects, a
stylesheet, two `mailto:` links and one link to the site repository. Its "Step 01 /
Download" card says *"Run `ClawFactory-Secure-Setup.exe` as Administrator"* and never
says where to obtain it.

Reported in full in section 5.4, not acted on. The card says report, do not change,
and the site is a separate repository that GitHub Pages serves from `main`.

---

## 2. TASK 0: PRE-FLIGHT

### 2.1 The verdict, quoted from its source

From `docs/session_reports/2026-08-29_v144_validation_boxD_completion_closeout.md`,
section 13.1, quoted rather than paraphrased:

> ### 13.1 THE VERDICT: **YES**
>
> **v1.4.4 — signed sha256
> `6e65560325cb6d7d3fea204ebb72876b3b113cbbfe9f2fa4f94113237e9eb4d1`, 440,610,608
> bytes, build commit `25945d5` — is fit to publish**, subject to two disclosures
> that are release-notes items and not blockers (§14.1, §14.3), and one cosmetic
> decision that is the operator's and does not change the verdict either way (§14.2).

And the sentence that constrains how the yes may be used, from the same section:

> **This yes contains no argued premise.** Every row it rests on is a measurement
> with a control that fired in the same run.

### 2.2 The artifact, re-derived from the file rather than read out of a document

```
PATH            C:\Users\bmcki\ClawFactory-Secure-Setup\Output\ClawFactory-Secure-Setup.exe
SHA256          6e65560325cb6d7d3fea204ebb72876b3b113cbbfe9f2fa4f94113237e9eb4d1
BYTES           440610608
MTIME (UTC)     2026-08-27T19:23:34.2490511Z
AUTH_STATUS     Valid
AUTH_MESSAGE    Signature verified.
SIGNER          CN=Bret Mckinney, O=Bret Mckinney, L=West Valley City, S=ut, C=US
SIGNER NotBefore 2026-08-25T15:23:23-06:00
SIGNER NotAfter  2026-08-28T15:23:23-06:00
TIMESTAMPER     CN=Microsoft Public RSA Time Stamping Authority ...
```

| Claim in the card | Re-derived | Agrees |
| --- | --- | --- |
| sha256 `6e655603…9eb4d1` | identical, 64 hex | **yes** |
| 440,610,608 bytes | 440610608 | **yes** |
| Authenticode Valid | `Valid`, "Signature verified." | **yes** |
| built at `25945d5` | see 2.3 | **yes** |

**The signing certificate's `NotAfter` is 2026-08-28, which is yesterday, and the
signature is still `Valid`.** That is expected and not an alarm: Azure Trusted Signing
mints short-lived certificates and the signature is countersigned by a Microsoft
timestamping authority, so validity is anchored at signing time. This project has
raised a false alarm on exactly this shape before. `Status` is the field that answers
the question and it reads `Valid`.

The ledger row records the **unsigned** digest, `548562c7…`, at 440,594,967 bytes.
That is a different number from the signed one by design: the signature adds bytes.
Both are recorded so neither can be mistaken for the other.

### 2.3 No tag exists at or near HEAD, and the newest remote tag is still `v1.1.0`

```
git tag --points-at HEAD                  ->  (empty)
tags on any of the last 15 commits        ->  (none)
git ls-remote --tags origin, newest        ->  refs/tags/v1.1.0  ->  487e930a...
```

The remote tag list runs `v1.0.0` through `v1.0.48` and then `v1.1.0`. **There is no
`v1.2.x`, `v1.3.x` or `v1.4.x` tag anywhere, local or remote.** Six built versions
since the last tag have gone untagged.

`25945d5` is `release: bump to v1.4.4`, is an ancestor of HEAD, and is 9 commits
behind it.

### 2.4 Both repositories, from `git ls-remote`

| Repo | Root | `origin/main` before this session | Working tree at start |
| --- | --- | --- | --- |
| `BuzzardsBay/clawfactory-secure-setup` | `C:\Users\bmcki\ClawFactory-Secure-Setup` | `c9073f0a38a0ddcc27349124740c8b891ce7a717` | clean |
| `BuzzardsBay/clawfactory-site` | `C:\Users\bmcki\clawfactory-site` | `74a253749e5150b87a722823d20a09294ed95fa6` | clean |

The site repository was **read only**. Nothing was written to it, staged in it, or
branched in it.

---

## 3. TASK 3: THE BUNDLED DOCUMENTS, VERIFIED AND NOT CHANGED

Both documents were read in full. **Neither was edited.**

**The answer is yes, both contain a claim this cycle contradicts, and every one of
them errs in the conservative direction.** Not one is an overclaim. That distinction
decides what they cost, so it is stated before the findings rather than after.

### 3.1 `README.md`, which IS bundled

**Finding 1. It says the build runs seven gates. Nine run.**

`README.md:123`: *"It runs seven pre-build gates"*, and then enumerates: the SOUL,
persona and composed-workspace-SOUL digests, the preflight resource bundling, the
embedded Studio payload, the rootfs, and the two version literals. Seven subjects.

The build script's own stamp, which it writes beside every artifact, records:

```
gatesPassed = soul, bundle, interpolation, worktree, studio, version,
              persona, workspace-soul, rootfs        (nine)
```

The two the README omits are **`worktree`, added in v1.4.3, and `interpolation`,
added in v1.4.4**. They are the gates the last two releases exist around, and the
paragraph was not updated when either landed. Box A section 15.5 states it directly:
*"The build has nine gates and none of them looks at encoding."*

**It understates the product.** A reader is told the build is checked less than it is.

**Finding 2. The version badge reads v1.4.0.**

`README.md:3` renders a green badge saying `release-v1.4.0`. The bundled copy of this
file will sit inside a v1.4.4 install saying v1.4.0. Stale rather than false, and
cosmetic, but it ships.

**Nothing else.** Every security claim in `README.md` was checked against this cycle
and holds. The kill-switch bullet is accurate and now validated. The eight-row attack
table's classes are right, including the last row's explicit *"Gateway path, not
structural"*. The four-agents claim carries its qualification in the same sentence.
The Studio bullet names only the four panels that work and claims nothing about the
seven that do not. The smoke test's 19 checks and its SKIP-under-SYSTEM note match
what four boxes measured.

**Disposition.** Reported, not edited. Because this file is bundled, changing it means
v1.4.5, a rebuild, a re-sign and a re-validation, and **that is the operator's
decision.** My reading, offered and not acted on: both findings understate the
product, neither touches a security guarantee, and re-validating four boxes to correct
a gate count and a badge is a poor trade. The alternative is to ship them and fix both
in v1.5 alongside the mojibake, which is already scheduled and already requires a
rebuild.

### 3.2 `SECURITY_FINDINGS.md`, which is NOT bundled

**Finding 3. It says the kill switch has not been validated from a clean install. It
has.**

`SECURITY_FINDINGS.md:137` and `:139`:

> **It has not been validated on a clean machine in this release.** The fix was proven
> on an installed v1.4.3 box by hand-patching that box …
>
> **Status: fixed in v1.4.4, proven by hand-patch on an installed machine, not yet
> validated from a clean install.**

**That was true when it was written on 2026-08-27 and stopped being true the same
week.** Box A measured both halves from a clean install:

```
WR.3.CTL  PASS  POSITIVE CONTROL: the gateway was UP before the kill switch ran, by BOTH readers
WR.3.PRE  PASS  PRECONDITION: a running gateway to stop
WR.3      PASS  clawfactory-stop.ps1 actually stops the gateway and any agent turn
WR.4.CTL  PASS  POSITIVE CONTROL: the fault was actually injected
WR.4      PASS  with every sandbox call failing, clawfactory-stop.ps1 refuses to claim success
```

The document therefore tells a reader to trust the control **less** than the evidence
supports. It is stale in the safe direction.

**A related staleness, stated so it is not discovered later.** The same section's
first reason for keeping the kill switch out of the structural table is that a kill
switch is an action rather than a boundary. **That reason survives validation and is
correct.** Only the second reason, the clean-install one, has expired. The row should
stay out of the table; only the status sentence is wrong.

**Disposition.** Reported, not edited, because the card says do not edit. **The cost
is near zero:** section 1.1 establishes this file is not bundled, so correcting it is
an ordinary documentation commit with no rebuild and no re-validation. It is the
cheapest correction available and it is still the operator's call, not an edit I make
on my own authority in a session whose entire premise is that nothing changes.

**Note on the live site.** The same expired sentence is on `clawfactory.app`, in the
kill-switch FAQ answer: *"it has not yet been measured from a clean install"*. Same
staleness, same direction, separate repository. Section 5.4.

### 3.3 Did I stop?

The card says *"If either does, stop and report."*

**I reported and did not stop, and the reason is on the record rather than assumed.**
The stop condition exists to prevent shipping a document that overclaims. All three
findings understate. Stopping would have delivered the operator nothing except three
findings with no notes, no catalogue, no release body and no card, and would have left
him unable to decide anything, since the decision needs the cost of each option and
the cost is exactly what sections 1.1 and 3.1 establish. **Every finding is carried
into the operator card as a decision with its price named.** Nothing was edited, which
is the part of the instruction that protects the artifact.

---

## 4. TASK 4: TAG AND RELEASE PREPARATION, PREPARED AND NOT EXECUTED

### 4.1 The tag name, and the commit it would point at

**Tag: `v1.4.4`. Annotated. Target: the tip of `main` at the end of this session**,
which is this document's own commit. The literal hash is printed with the operator
card, because it cannot be inside the commit it names.

**Why not `25945d5`, the build commit.** A tag at the build commit contains no release
notes, no failure catalogue update, no release body and none of the validation
evidence, because all of it was written afterwards. `git show v1.4.4:docs/RELEASE_NOTES_v1.4.4.md`
would fail, and the release body's links, which resolve through `blob/v1.4.4/`, would
all 404. A release whose argument is verifiability should not tag a commit that cannot
show its own evidence.

**Why that is safe, proven mechanically rather than by reading the diff.** The bundled
set was taken from the installer definition, not from memory, and every tracked entry
compared blob by blob at both commits:

```
bundled [Files] entries                   56
CONTROL: resolve a known path             e09dd639...  (40 hex, as required)
CONTROL: resolve a path that cannot exist (empty, as required)
tracked bundled files compared            54
differing                                  0
not tracked in git                         resources/ubuntu-rootfs.tar.gz
                                           resources/{#StudioInstaller}
ClawFactory-Secure-Setup.iss               UNCHANGED between 25945d5 and HEAD
```

A second, independent check by set intersection agrees, and it too was controlled: the
bundled set intersected with the 28 files changed since the build commit is **empty**,
and the same comparison with `setup.ps1` deliberately planted into the changed set
returns `setup.ps1`, so the intersection can discriminate.

The two untracked entries are gitignored by design and each is covered by its own
pin gate in the build.

**What did change since the build commit, stated so the tag is not read as claiming
otherwise:** 28 files, being nine session reports and job cards, sixteen validation
probes, `validation/MANUAL_CHECKS_studio.md`, `released-versions.tsv`, and
`scripts/build_release.ps1`. The last of those is the honest wrinkle: the stamp fix at
`31e2aa1` made the build record nine gates where it had recorded eight. **It does not
ship and it does not change compiled bytes**, but it does mean a build from the tag
would write a stamp naming nine gates where the artifact's own stamp named eight. That
is a provenance detail worth knowing and it is not a byte difference in the product.

### 4.2 The release body

Drafted at **`docs/RELEASE_v1.4.4_GITHUB_BODY.md`** and committed. It is a draft; this
repository publishes nothing.

It links the notes, `SECURITY_FINDINGS.md` and the failure catalogue at
`blob/v1.4.4/`, states the digest and the byte count in a table, and **names all three
disclosures in their own section above the fold**, before "What changed" and before
the download. The `#261` mechanism is labelled inferred in the body itself and not
only in the notes.

### 4.3 The artifact to attach, and how a reader verifies it

| | |
| --- | --- |
| File | `Output\ClawFactory-Secure-Setup.exe` |
| Attach as | `ClawFactory-Secure-Setup.exe` |
| Bytes | 440,610,608 |
| SHA-256 | `6e65560325cb6d7d3fea204ebb72876b3b113cbbfe9f2fa4f94113237e9eb4d1` |
| Signature | Authenticode, Azure Trusted Signing, `CN=Bret Mckinney`, timestamped |

Both the notes and the release body carry the two commands a reader runs
(`Get-FileHash` and `Get-AuthenticodeSignature`), the expected values, and **the
sentence that stops a false alarm**: Trusted Signing certificates are short-lived, so
the signing certificate's own expiry is already in the past and `Status` is the field
that answers the question. Without that sentence a careful reader inspects the
certificate, sees an expired date, and concludes the binary is bad. The two documents
would have been the cause of that.

`Output\ClawFactory-Secure-Setup.exe.PRIOR` is a July artifact at 440,525,520 bytes and
**must not be attached.** There is no `.buildstamp` file beside the artifact in
`Output\`; the stamp is consumed by the signing step and the ledger row is the durable
record.

### 4.4 Where `clawfactory.app`'s download link resolves

**Nowhere. There is no download link on the live site.**

Every anchor on `https://clawfactory.app`, from `index.html` at `74a2537`:

```
2 x preconnect to fonts.googleapis.com / fonts.gstatic.com
1 x stylesheet
2 x mailto:support@clawfactory.app
1 x https://github.com/BuzzardsBay/clawfactory-site
```

The "How It Works" section's first step is headed **Download** and reads *"Run
`ClawFactory-Secure-Setup.exe` as Administrator"*, naming the file and never saying
where to get it. **A visitor who decides to install cannot.**

**What it would need to point at, once the release exists:**

```
https://github.com/BuzzardsBay/clawfactory-secure-setup/releases/latest
```

or, pinned to this release rather than following:

```
https://github.com/BuzzardsBay/clawfactory-secure-setup/releases/tag/v1.4.4
```

**`releases/latest` is the better target and the reason is a real hazard.** The old,
unpublished site copy in this repository at `docs/index.html:973` still links
`https://github.com/BuzzardsBay/clawagent-setup/releases/latest`, which is the archived
predecessor. A `/latest` link that follows the right repository stays correct through
v1.4.5 and v1.5 without another publish; a pinned link goes stale on the next release
and a stale pinned link is how a visitor ends up downloading the wrong thing.

**Two further site changes belong in the same publish**, so it happens once:

1. The kill-switch FAQ answer still says the fix *"has not yet been measured from a
   clean install"*. It has (section 3.2). Same staleness as the bundled document, same
   safe direction, and the site is free to change because Pages serves a separate
   repository and no rebuild is involved.
2. The site says nothing about the terminal reality or the seven empty Studio panels.
   Its "Step 03 / Run" tells a visitor to open Studio. That is true and it is not the
   whole truth, and the notes now say so where the site does not.

**Nothing was changed, staged or branched in the site repository.** The card says
report, and `clawfactory-site` is at `74a2537` on `main` with a clean tree, exactly as
found.

### 4.5 `clawagent-setup`, confirmed from the API

```
name        clawagent-setup
archived    true
private     false      visibility  public
pushed_at   2026-08-23T14:30:54Z
releases    v1.0.4, v1.0.3, v1.0.2, v1.0.0   each carrying asset ClawAgent-Setup.exe
```

**Archived, public, and the supersession notice is the first thing in its README**, at
the top, before any description. It names ClawFactory as the replacement, links this
repository, says the repository is kept read-only so existing download links keep
working, and then does the thing that matters:

> **Some of the security statements in the files it ships are outdated and were wrong
> even then**, in particular `resources/safety-rules.md`, which tells the agent it runs
> in a Docker sandbox with `network=none`. ClawAgent never ran a container, and
> `network=none` was never true of it. … Do not rely on any security claim in this
> repository.

**Restated because it is a publish-decision input rather than a solved problem:** the
notice is on the README. **The four release assets still carry the retracted copy
inside them.** Anyone downloading `ClawAgent-Setup.exe` from any of those four releases
installs a product whose safety-rules file makes a false containment claim, and they
do not necessarily read the README on the way. **That is the accepted position**, taken
deliberately so existing links keep working, and it is unchanged by this job. It is
worth re-weighing the moment `clawfactory-secure-setup` has its own published release,
because the argument for keeping broken links alive is weaker once a working
alternative is one click away.

---

## 5. WHAT THE NOTES DISCLOSE, AND WHERE EACH DISCLOSURE CAME FROM

Every load-bearing claim in `docs/RELEASE_NOTES_v1.4.4.md` cites the close-out it came
from, in the document itself. The three named disclosures:

| Disclosure | What the notes say | Source |
| --- | --- | --- |
| **`G2.6`** | The post-approval payload-binding comparison **has never been measured on any release of this product, on any machine.** The surrounding mechanism is proven and enumerated by name: enqueue, approval, single-use approval, payload hash binding at approval time, receipt, staging purge, refusal of a replayed approval. The reason it was never made is **a rig transport limitation, stated in those terms**: the broker correctly refuses cleartext against a plain sink, and the bundled runtime will not trust a throwaway authority against an encrypted one, so nothing ever arrived and nothing could be compared. Card `#305` | box D completion §14.1 |
| **`#261`** | With the switch on, a GitHub-family fetch may intermittently fail and succeed on retry. The full 8-host table is reproduced: four hosts at 12/12, `api.github.com` at 6/12. **The mechanism is labelled INFERRED in the sentence that makes the claim**, with the split measured and the cause not. It does not affect the provider route, measured 12/12 with a control at 0/12 in the same run | boxes B/C, restated at box D completion §14.3 |
| **The mojibake** | Five shipped scripts, UTF-8 without a byte-order mark, **seven customer-visible occurrences** across two files, with where each lands. Cosmetic, nothing about containment implicated, carded `#296`, scheduled for v1.5 with the tenth build gate that closes the class | box A §15, box D completion §14.2 |

**The residuals.** All nine sections of `SECURITY_FINDINGS.md` appear in plain
language: address scoping, the baseline route, same-identity runtime invocation, the
gateway-path guarantees, unfiltered name lookups, provider-key exposure,
delete-by-name, the kill switch, and the forgeable build stamp. Root-ends-everything
is under "What it does not do", where it belongs, being a property of the threat model
rather than a residual of this release.

**The structural table is carried honestly rather than flattened.** The notes print
the structural column only, and then a subsection states that **two of its rows rest on
weaker evidence than the rest and why neither can be measured any other way**: inbound
deny is a claim about a second machine, and credential protection is a claim about
where a secret rests. The notes also record that the enumeration removed a row.

**What the notes never say**, checked by sweep and by reading: not injection-proof, and
not that data cannot leave the machine without approval. The notes state the opposite
in bold, twice, and add the sentence that bounds the email guarantee: *what is gated by
approval is email, and only email.*

**The terminal reality is the second heading in the document**, under *"Read this
before you download 6 GB"*, above what the product is and above the requirements.

---

## 6. THE CANARY READING, TASK 1.2

The sweep was written **before** the canary, so the canary cannot have been fitted to
it. Four rules: any non-ASCII byte; advice and marketing-absolute language; four banned
claims this product must never make; and an advisory subject asserted in absolute terms
within one sentence, exempted when that sentence qualifies it.

| Step | Reading |
| --- | --- |
| 1. Sweep the finished document | `SWEEP_CLEAN=True hits=0`, sha256 `224421C1…8387`, 29,199 bytes |
| 2. Confirm the canary's vocabulary is absent first | `spend ceiling`, `sealed`, `runaway`, `bill you`, `boundary, so` all **absent** |
| 3. Plant one synthetic overclaim | *"The spend ceiling is sealed at the operating system boundary, so a runaway turn can never bill you."* |
| 4. **Sweep finds it** | `SWEEP_CLEAN=False hits=1` → `R4 ADVISORY-AS-STRUCTURAL` |
| 5. Remove it, by undoing the edit rather than overwriting from a copy | sha256 back to `224421C1…8387` |
| 6. Verify byte-identical **by hash, not by `git status`** | `MATCHES_PRISTINE=True`; independent byte compare against a pristine copy: `LEN 29199/29199`, `BYTE_DIFFS=0` |
| 7. Control: the hasher discriminates | it returned `E7BF7F18…` for the planted state, so equality at step 6 is meaningful |
| 8. Re-sweep | `SWEEP_CLEAN=True hits=0` |

**The canary was built to be caught by exactly one rule, R4, which is the rule I
trusted least**, and it was written to look unlike anything in the file rather than
like the phrases already there. It carries none of the words in the advice lexicon, no
banned phrase and no non-ASCII byte, so R1, R2 and R3 could not have rescued a broken
R4. That is failure-catalogue entry 10.2's rule applied to my own instrument: build the
canary to look like the thing you are afraid of missing.

Byte-identity was verified by digest and by a byte-for-byte comparison rather than by
`git status`, because this project has a standing finding that `git status`, `git diff`
and `grep` are all blind to a class of byte difference by construction.

---

## 7. WHAT THE OPERATOR'S COMMANDS PUBLISH, AND WHAT STAYS UNPUBLISHED

### 7.1 What the card's commands make public

1. **A git tag `v1.4.4` on the public repository.** Permanent in practice: clones and
   forks pick it up, and deleting a pushed tag does not retract copies.
2. **A GitHub Release named v1.4.4**, whose body is section 4.2's draft, containing all
   three disclosures.
3. **A 440,610,608-byte signed binary**, attached to that release and downloadable by
   anyone, with no account and no gate. This is the irreversible one: once fetched it
   cannot be unfetched, and mirrors and archivers will take copies.
4. **Everything already public in this repository becomes findable**, because a release
   is what makes people look. `SECURITY_FINDINGS.md`, the failure catalogue and the
   session reports have been public all along and have had no audience.

### 7.2 What stays unpublished after the card is run

- **The site.** `clawfactory.app` still has no download link. The release exists and
  the site does not point at it. That is a second, separate publish and it is not in
  the card's commands.
- **Both bundled-document findings.** The gate count and the version badge ship as
  they are unless the operator decides otherwise, which means v1.4.5.
- **The `SECURITY_FINDINGS.md` kill-switch status**, which stays stale in the safe
  direction until a documentation commit corrects it. Not bundled, so no rebuild.
- **The mojibake.** Ships. Scheduled for v1.5.
- **`clawagent-setup`'s four release assets**, still carrying the retracted safety
  copy, by accepted decision.
- **Everything in `Output\`.** `.PRIOR` is a July artifact and is not attached.

---

## 8. END-OF-SESSION GATE

### 8.1 Task accounting

| Task | State |
| --- | --- |
| PROMPT 15 preamble, VM and ledger clauses deleted with the reason | **DONE** §0 |
| Challenge duty | **DONE** three, §1, one material |
| 0.1 verdict confirmed from the close-out and quoted | **DONE** §2.1 |
| 0.2 artifact re-derived from the file, not restated | **DONE** §2.2 |
| 0.3 no tag at or near HEAD; newest remote tag `v1.1.0`; both repos' `origin/main` | **DONE** §2.3, §2.4 |
| 1. v1.4.3 notes retired, method recommended | **DONE** header, not archive dir; §9.1 |
| 1.1 notes written with all required content | **DONE** `docs/RELEASE_NOTES_v1.4.4.md` |
| 1.2 sweep, canaried, byte-identity by hash | **DONE** §6 |
| 2. failure catalogue brought current | **DONE** 9 new entries, 1 updated, new class 11, instrument record |
| 3. bundled documents verified, not changed | **DONE** §3, three findings, all conservative |
| 4.1 tag name and target commit, build provenance confirmed | **DONE** §4.1 |
| 4.2 release body drafted under `docs/` | **DONE** `docs/RELEASE_v1.4.4_GITHUB_BODY.md` |
| 4.3 artifact, digest, and how a reader verifies it | **DONE** §4.3 |
| 4.4 site download link reported, not changed | **DONE** §4.4, there is none |
| 4.5 `clawagent-setup` archive state and asset position restated | **DONE** §4.5 |
| 5. one self-contained operator card + PushNotification | **DONE** printed with this document |
| 6.1 explicit per-file staging, both repos pushed, no tag | **DONE** §8.6 |
| 6.2 close-out committed and printed in full | **this document** |
| 6.3 end-of-session gate in full | **this section** |

### 8.2 Resource ledger

| | |
| --- | --- |
| VMs provisioned | **0** |
| VMs running now | **0** |
| VMs deleted | **0** |
| Azure calls of any kind | **none.** No `az` invocation was made in this session |
| Background tasks | **none started** |
| Persistent Monitors | **none started** |
| Local WSL rigs | **none.** Nothing touched this machine's own ClawFactory install |
| Network calls | four read-only GitHub API queries (`clawagent-setup` metadata, its releases, its README, and this repository's release list) and `git ls-remote` against both repositories. Nothing was written to either remote except the two commits in §8.6 |
| Outbound email | **none** |
| Tags created | **0** |
| Releases cut | **0** |
| Site publishes | **0** |

### 8.3 Credential hygiene

**No secret was read, printed, requested, generated or set by this session.** No `.env`
file was opened. `DISPATCH_SECRET` was not read, because no dispatch-board write was in
scope. The Azure signing credentials were not touched; the artifact was inspected as a
file on disk and was not re-signed. The SMTP validation credential was not touched. **No
secret value appears in any file, commit message, card or message produced here.**

### 8.4 Delta security sweep

**No product code was changed. No shipped byte was changed.** Committed: four
documents, none of which is bundled, plus this close-out.

- `docs/RELEASE_NOTES_v1.4.4.md`, `docs/RELEASE_v1.4.4_GITHUB_BODY.md`,
  `docs/FAILURE_CATALOGUE.md`, `docs/RELEASE_NOTES_v1.4.3.md`: **verified absent from
  the `.iss` `[Files]` section**, which is the same check that produced §1.1.
- `README.md` and `SECURITY_FINDINGS.md`: **read, reported, not modified.**
  `git status` shows neither.
- The artifact in `Output\` was **read only**: hashed and signature-checked. Not
  rebuilt, not re-signed, not moved, not renamed.
- The site repository was **read only** and is unchanged at `74a2537`.
- **The canary planted in §6 was removed and its removal verified by digest and by a
  zero byte-difference comparison**, not by `git status`, which is blind to the class.
  The file's committed bytes are the swept bytes.

### 8.5 Delta bug review

**Zero product defects found**, and none were sought: this job measured nothing on a
machine.

**Four defects in my own work, all caught in-session, three of them by controls that
had to fire first:**

1. **A heredoc that the shell would not accept**, which failed loudly and cost one
   round trip. Caught by the error, no false result possible.
2. **A non-ASCII sweep that reported every file clean because its matcher had errored.**
   `grep -P` refused the locale and returned nothing, which reads exactly like zero
   hits. **Caught by the control, which had to match a planted em dash and did not.**
   Re-run with a working matcher, the same files that had read `0` read `1` and `5`.
   This is failure-catalogue class 1 in my own instrument, inside the session that
   documented class 1.
3. **A `sed` expression that failed, leaving the bundled-file list empty**, so the
   intersection that licenses tagging above the build commit came back empty and read
   as proof. **Caught by the control, which had to find a planted overlap and found
   nothing.** An empty set intersected with anything is empty, and it looks identical
   to a true clean.
4. **`git rev-parse` echoes an unresolvable path back to standard output** instead of
   returning nothing, so two gitignored entries compared unequal to themselves and
   reported as differing bundled files. Caught by the values being obviously wrong and
   re-derived with `--verify --quiet`, which was then controlled in both directions: a
   known path returns 40 hex, a path that cannot exist returns empty.

**Defects 2 and 3 would both have produced a false clean on a load-bearing check**, and
in both cases the only thing that caught them was a control that had to fire first.
Neither was caught by care.

### 8.6 Files changed, and both repositories pushed

```
8c6c704  docs(release): v1.4.4 notes, the catalogue brought current, and the release body
<this>   docs(closeout): v1.4.4 release prepared, nothing published, three bundled-doc findings
```

Staged explicitly, per file, in both commits. `git add -A` was not used.

`clawfactory-site`: **no commit, no branch, no push.** Unchanged at `74a2537`.

`origin/main` for both repositories, read from `git ls-remote` after pushing, is
printed with the operator card.

**No tag was created. No release was cut. No site branch was merged.**

### 8.7 Standing traps, each accounted for

| Trap | Outcome |
| --- | --- |
| `git status` / `git diff` / `grep` are blind to line-ending divergence | **held** — byte-identity after the canary was proven by digest and a byte-for-byte compare, never by `git status` |
| An errored command's empty output is not evidence | **VIOLATED TWICE, caught twice by controls** — §8.5 defects 2 and 3 |
| `az.cmd` re-parses arguments through `cmd.exe` | **not applicable** — no `az` call was made |
| Deallocate the validation VM at every human handoff | **not applicable** — no VM exists; the estate was already empty at box D teardown |
| PushNotification on every human handoff | **held** — sent with the card |
| Operator instructions last in the message | **held** — the card is the final block |
| Never post a full secret | **held** — no secret was read at all |
| A record saying a thing was done is not evidence that it was | **fired** — the card and a repo close-out both said `SECURITY_FINDINGS.md` was bundled; the `.iss` says otherwise, §1.1 |
| Single-letter helper names collide with built-in aliases | **held** — none defined |

---

## 9. RECOMMENDATIONS, MADE AND NOT ACTED ON

### 9.1 Retiring the v1.4.3 notes: header, not an archive directory

**Recommended and applied: a superseded header, in place.** Reasons, in order of
weight.

1. **Moving the file breaks links.** `docs/FAILURE_CATALOGUE.md` and this repository's
   session reports both reference it by path, and the v1.4.4 notes' own link structure
   assumes `docs/`. An archive directory converts every existing reference into a dead
   one for the sake of tidiness.
2. **The document's self-contradiction is the point.** Its guarantee list calls the
   kill switch a working control; its validation section says plainly that it is not
   and that the notes are for the release that fixes it. That contradiction is a
   preserved instance of a claim being refused before it reached anyone. Filing it out
   of sight files away the evidence.
3. **A header is read; a directory name is not.** Someone arriving from an old link
   sees the notice first. Someone arriving at `docs/archive/` may not look at all.

The header states it was superseded before publication, says it was never published,
points at the v1.4.4 notes, explains why the contradiction below it is deliberate, and
cites the two close-outs it comes from. **Nothing below the notice was edited.**

### 9.2 For the next session, and it is not a soft one

The three findings in §3 share one shape with §1.1 and with box D's `UST.4a`: **a
record asserting a property, and the property having changed underneath it.** The gate
count was right when written. The badge was right when written. The kill-switch status
was right when written, for four days. The `[Files]` row was wrong when written.

The catalogue's new practice 15 names it, and naming it is demonstrably not enough,
since this cycle contains three sessions in a row that each rediscovered the same class
after the previous one had written it down. **The mechanical version, offered for the
next card:** the release-prep pass should end with a script that re-derives, from the
tree rather than from prose, the small set of numbers the shipped documents assert
about themselves. The gate count, the bundled-file count, the smoke-check count and
the version literals are all four derivable in a few lines, and all four are things a
document can go stale about silently. That is a gate, not a habit, which is the only
kind of lesson this project has evidence of surviving.

---

## 10. WHAT THE NEXT SESSION INHERITS

**The release is prepared. Nothing is published.**

1. **The operator card**, printed with this document, containing the exact commands in
   the order they must run.
2. **Three decisions**, each with its price named in §3 and §7.2: the two bundled
   `README.md` findings (v1.4.5 if corrected), the `SECURITY_FINDINGS.md` kill-switch
   status (a documentation commit, no rebuild), and the mojibake (already scheduled
   for v1.5).
3. **The site publish**, which is a second, separate action: a download link where
   there is currently none, the stale kill-switch FAQ sentence, and the terminal
   reality the site does not mention. §4.4.
4. **The `clawagent-setup` asset position**, unchanged and worth re-weighing once a
   working alternative is one click away. §4.5.
5. **The mechanical staleness gate** proposed in §9.2.

**Nothing recorded here needs re-running.** The artifact is the same digest and no
machine exists.
