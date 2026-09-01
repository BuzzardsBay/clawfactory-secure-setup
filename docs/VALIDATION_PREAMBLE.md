# ClawFactory validation preamble (PROMPT 15)

**This file is the authoritative copy, outright.** Not a copy pending a pointer somewhere
else. Any ClawFactory job that pastes a validation preamble pastes it from here, and any
disagreement between this file and any other copy is resolved in favour of this one,
without consulting the other.

**There is no FrontierAI repository copy to defer to.** The text below did not come from
the FrontierAI repository and there is nothing in that repository to reduce to a pointer.
It came from `C:\Users\bmcki\OneDrive\Desktop\Claude Prompts\FrontierAI_CC_Prompt_Library.md`:
a file **outside version control**, on a silently syncing OneDrive path, with no history, no
review and no way for a session to tell whether the copy it read is the current one. That
file is to be reduced to a one-line pointer at this repository path, in a separate session.
Until it is, treat any text it holds as superseded by this file.

**Why it moved.** PROMPT 15 governs ClawFactory but lived somewhere a ClawFactory session
has no reason to look and no way to verify. Two sessions have now failed to find it. On
2026-08-17 a session could not find it at all and recorded that it had applied the close-out
gate and the pre-flight checks from the conventions of recent close-outs instead, flagging
that any PROMPT 15 requirement not inferable from those conventions had not been applied. On
2026-08-29 a job brief named `C:\Projects\FrontierAI\FrontierAI_CC_Prompt_Library.md`, where
no such file exists, and the session found the real copy only by reading the 2026-08-17
close-out that had recorded the same failure. **A governing document that two sessions could
not locate was not governing anything.** Now it is in the repository it governs, under
version control, where a `git log` can answer what changed and when.

**Provenance of the text below.** Copied verbatim on 2026-08-29 from that file, from the
`## PROMPT 15` heading through the end of its `### Notes on using PROMPT 15` section. The
fenced block is the paste block; the notes after it are guidance about using it. Nothing
was reworded, reordered or abridged.

**How to use it.** Paste the fenced block into a ClawFactory job prompt. Delete only
clauses that provably do not apply to that job, and state in the job's first output which
you deleted and why.

---

## PROMPT 15 -- CLAWFACTORY VALIDATION RUN PREAMBLE (paste into any prompt with a VM run)

Use when: any ClawFactory CC job that provisions an Azure VM, installs an artifact, and
validates it. This is not a standalone job. It is the boilerplate that has been retyped or
half remembered in every validation session since June, and every clause below was learned
by losing a run to it.

Paste as a block into the prompt. Delete only clauses that provably do not apply, and say
in the prompt which you deleted and why.

````
CLOSE-OUT IS A GATE, NOT A DELIVERABLE ON REQUEST

The session is not finished until the close-out exists, is committed, and has been PRINTED
IN FULL, unprompted. The operator should never have to ask for it. If it was not printed,
the job did not end, it stopped.

- Write it to docs/session_reports/YYYY-MM-DD_<job>_closeout.md and commit it with the
  session's files.
- Print it in full at session end. Not a summary of it, not a path to it, not an offer to
  produce it.
- If the session is running long or is about to be cut off, write and print an HONEST
  INCOMPLETE-STATE close-out instead of a complete-looking one. An error-terminated session
  still writes one.
- If the job failed, the close-out is more important, not less.

PRE-FLIGHT, BEFORE WRITING ANY CODE

Report all four. This costs minutes and each one is here because skipping it cost a VM run.

1. COMPREHENSION. Restate what will change, in which files, and what depends on each. Then
   check that restatement against the repo rather than against the prompt.

2. DEPENDENCY CENSUS, whenever anything is removed, gated, disabled, or made
   conditional. Two questions, both answered by execution:
   - WHO uses it? Enumerate EVERY site the thing appears, tree-wide, and report the count
     and each hit. Removing a hostname from two of the three places it was seeded shipped
     a toggle that silently did nothing, and the third site was the one that persisted to
     disk and survived reboot.
   - WHEN is it needed? Walk the install sequence and the boot sequence and name every
     window where the thing is required but not yet present. A change correct at steady
     state can be fatal during a window: removing toolchain hosts left uid 1000 with no
     route between the firewall step and the resolver step, and the install spent 21
     minutes timing out before it failed.

3. FAILURE-MODE WALK. For the change being made, name what breaks if it works exactly as
   specified. Not what breaks if it is buggy. TC.3 was not a bug: the switch did precisely
   what it was told to do, and what it was told to do stopped the agent working. The panel
   copy promised a milder consequence than the real one, which is worse than no control at
   all.

4. INPUT-SHAPE SWEEP for any new value that is read. Test the reader against present,
   absent, empty, malformed, wrong-type and hostile. Decide and STATE what each means. An
   absent key may legitimately read as a default; a MALFORMED one is a fault and a fault
   denies. Code that disagrees with its own comment is a defect in a security product,
   because the comments are the audit trail.

IF THIS PROMPT IS WRONG, SAY SO BEFORE EXECUTING IT

The prompt is written by someone who cannot see the repo. It will sometimes be wrong.

- If an instruction is factually wrong about the code, STOP and report. Do not quietly
  build the thing that was meant.
- If an instruction is ambiguous, STOP and ask. Do not pick a reading and proceed.
- If following an instruction would break something outside its scope, STOP and report.
  A specified build-stamp gate once made signing Studio impossible, and the failure mode
  was an unsigned payload shipped to customers, worse than the bypass the gate closed.
- If a premise is stale, say which and what the repo actually shows. The repo is truth.
- Reporting a bad instruction is the job working, not a delay in it.

ENVIRONMENT, NOT NEGOTIABLE

- Standard_D2s_v4. DSv5 quota in westus2 is zero. Do not "upgrade" the size.
- Image clawfactory-win11-baseline-v2, resource group clawfactory-validation, for the
  baked boxes ONLY. This line is not a licence to run the whole cycle on one image -- see
  A BASELINE IMAGE IS A SET OF INSTALL STEPS ALREADY COMPLETED below, which requires at
  least one box per cycle from a stock image. Where the two clauses appear to conflict,
  that one wins.
- ONE az vm run-command invoke at a time. They queue and interfere.
- az vm run-command runs as SYSTEM and WSL refuses to run there. Every WSL test needs a
  session that is NOT SYSTEM. That is a statement about the ACCOUNT, not about interactive
  logon, and the two were conflated here for four months. See THE AUTO-LOGON CLAUSE WAS
  WRONG ABOUT ITS OWN FLEET below, which supersedes the sentence this one replaces.
- /var/tmp, never /tmp. /tmp is tmpfs and is wiped by restart.
- /mnt/c exists as an empty stub, so a directory test is NOT a valid check for Windows
  visibility.
- RDP is not open by default and needs a rule scoped to a single /32. Never 0.0.0.0/0.
- Pass -OutDir explicitly to teardown.
- Check the exit code of EVERY az call. An unchecked az vm user update hung the VMAccess
  extension and cost an hour on cfv-162.
- Deallocate at every handoff to a human. One VM once ran 64 hours for nothing.

HUMAN HANDOFF CARDS

Every point where the job needs a human, it STOPS and prints a self-contained card. The
operator must never reconstruct a step, look a value up elsewhere, or ask a separate
session what to do. A card that says what to do but not the exact command is not a card.
Each card carries: what to do, the exact commands with real values already substituted,
what success looks like, and what to do if it does not appear.

Card 1, at provisioning, before install:
- the VM name
- the public IP detected and the exact /32 the RDP rule was scoped to, AND which machine
  that address belongs to, so the operator can confirm they will be connecting from that
  machine rather than another one or a VPN
- the exact az command to set the admin password, with an obvious placeholder for the
  value, stating plainly that the operator chooses it, saves it in their password manager,
  and does not paste it back into the session or into chat
- then WAIT for confirmation before proceeding

Card 2, before every reboot:
- VM name, current public IP, admin username
- confirmation the RDP rule is still present and its /32
- the exact command to run in the interactive session, full path, copyable as one line
- what output means the runner started, and what means it did not
- whether auto-logon already produced a session, in which case the login is unnecessary
  and the card SAYS SO rather than sending someone to the console for nothing

Do not generate an admin password, do not print one, do not ask for one, and do not call
az vm user update after provisioning. The operator sets it once, at provisioning.

A probe whose subject expires on a timer cannot be staged in advance and handed to a
person. Stage it IMMEDIATELY before they act. A hand check with a ten-minute fuse expired
before the operator reached it, twice, in one session.

CARD FORMAT. THIS IS A HARD RULE, NOT A STYLE PREFERENCE

Every point where the job needs the operator, the request goes in a card built to these
rules. Analysis, reasoning and status go OUTSIDE the card. Nothing inside a card is FYI.

THE SINGLE MOST IMPORTANT RULE: every command sits in its own fenced code block, alone,
with nothing else inside that fence. Not indented. Not nested inside a larger fence. Not
mixed with prose. The operator copies commands out of the rendered code box, and a command
that shares a fence with instructions, or sits inside a nested fence, does not render as a
copyable box and cannot be copied cleanly.

- One command per fenced block. One fenced block per step. If two commands must run in
  sequence, that is TWO numbered steps with TWO fences, not one fence with two lines.
- Every command is copy-paste ready with every value already substituted. The ONLY
  placeholder ever permitted is PUT-PASSWORD-HERE.
- No prose, no comments and no # lines inside a fence. Explanation goes in the sentence
  ABOVE the fence.
- No language tag on the fence unless the content really is PowerShell or bash and the
  rendering benefits. A bare fence is fine and is safer.
- Every step says what success looks like, concretely, in the line AFTER the fence.
- Failure handling goes at the END of the card, one line per step, outside any fence.
- Send a PushNotification when a card is printed, then WAIT. Do not continue past a card.

The shape, where the fenced blocks are real fences and everything else is ordinary prose:

DO THIS

1. Create the box. Replace PUT-PASSWORD-HERE with the password from your paper.

```
az vm create -g clawfactory-validation -n cfv-190 ...
```

You should see: a table ending with "powerState": "VM running".

2. Connect to it.

```
mstsc /v:20.10.30.40
```

You should see: a Windows login prompt. Sign in as clawadmin.

Then reply: box up

If step 1 fails with a quota error, send me the message and stop.

MEASUREMENT DISCIPLINE

Use the phase runner, validation/interim-v120-phaselib.ps1. Do not roll bespoke reporting.
It enforces the rules mechanically: no registered positive control means no PASS, a control
that did not fire in the same run voids the phase, an unmet precondition records VOID with
a NAMED reason, a verdict the runner cannot read is VOID and named, and VOID exits 4 rather
than 0 or 1.

- Every block assertion carries a control that must FAIL in the same run.
- Every injected fault carries a control proving the FAULT LANDED. A fault injection that
  does not inject scores a false pass and looks exactly like a working control.
- A search for absences must first prove its target is searchable. A marker search over a
  compressed payload finds nothing and reads as clean.
- A held copy of any list is compared against what the product reports. An uncompared copy
  is a second stale list, not independence.
- A missing precondition is never a product verdict.
- The runner's verdict vocabulary is PASS, FAIL, VOID, INFO and nothing else. A phase that
  invents a word records VOID.
- Warm the agent before any load-bearing turn (L17).
- A new probe inherits NONE of the preconditions of the phases beside it.
- CALIBRATE BEFORE MEASURING. Run every probe body once against a synthetic target whose
  answer is already known, and assert that answer. A probe that cannot produce a
  known-correct result on a rigged input is not permitted to report a result on a real one.
- READ PROBE STDERR, not just the phase transcript. The transcript holds only what the
  probe successfully printed, so a probe that dies early is invisible in it by
  construction. Read the job .out whenever a phase produces less output than expected,
  BEFORE tearing the VM down.
- NAME THE REAL SUBJECT. Where a control protects a specific location, the package must
  name that location's real filesystem or path and require the measurement there. A Guard 4
  probe specified against /var/tmp answered YES on ext4 while the answer on the drvfs mount
  granted workspaces actually use was NO.

SHELL AND EXIT CODES

- Never write `cmd | head` followed by `$?`. In a pipeline `$?` is the last command's
  status. Use `if cmd >/dev/null 2>&1; then ... else ... fi`.
- Never build a shell loop variable inside a PowerShell here-string that is also inside a
  -c "..." argument. Put the loop in a script file.
- Any job wrapper invoking a nested interpreter must explicitly propagate that
  interpreter's exit code, and must ASSERT it by deliberately failing one phase.
- Wait on state, never on a sleep. `activating` is neither up nor failed, and a fixed sleep
  that lands on it produces a false negative about the thing under test.
- For each positive control, state in a comment what output would make it fail, and confirm
  that string does not appear anywhere else in the probe's own output. A control whose
  sentinel appears in the probe's own echoes cannot fail.
- A daemon holding a FAN_*_PERM mark must never call open() on any path under that mark,
  including through /proc/self/fd. Duplicate the descriptor the kernel supplied. Violating
  this deadlocks every process touching the mount and looks like a hung machine.

AN AUDIT REGEX IS ITSELF A PROBE

After fixing a class of defect, the grep used to prove the files clean is a measurement and
can be wrong in the same way the code was. Before trusting it, deliberately introduce one
instance of the defect and confirm the pattern finds it.

And the sharper version, learned the second time: A CANARY ONLY CERTIFIES THE PATTERN
AGAINST THE SHAPE OF THE CANARY. A pattern of backslash-dollar followed by a letter
certified a file containing $2. A pattern of [A-Za-z]+ found its canary and still missed
MANUAL-CONFIRM, because neither contained a hyphen. Build the canary to look like the thing
you are afraid of missing, not like the things you already know are there. Where the
question is enumeration rather than detection, parse the AST instead of matching text.

A BASELINE IMAGE IS A SET OF INSTALL STEPS ALREADY COMPLETED

Every step an image has already performed is a step the boxes built on it cannot measure.
Not a step that passed -- a step that was never asked. A baked baseline buys setup time by
deleting exactly the state the product is supposed to handle, and the boxes go on passing
while it is gone, which is why nothing surfaces it.

- Each baseline carries a WRITTEN RECORD of the steps it has already performed, updated at
  every rebake, in the same commit as the rebake. The bake script is that record; a prose
  sentence in a close-out is not. For the two images that exist the record is
  docs/reference/BASELINE_IMAGES.md. Read it before choosing the image, not after a result
  is in dispute.
- Every validation cycle includes AT LEAST ONE BOX FROM A STOCK IMAGE that has performed
  none of them. One deliberately unlike box beats four more of the same.
- Name, in the run plan, which rows the baked boxes cannot answer and which box answers
  them. A row measured only on the baked fleet is scoped to the baked fleet and says so.

The bake for clawfactory-win11-baseline enabled VirtualMachinePlatform, rebooted, disabled
Windows Update and added three Defender exclusions before capture. For four months no box
could be in the state the first external install failed in, and four boxes agreed.

RESOURCE LEDGER

- Task 0: delete all prior FAIL VMs and their OS disks before provisioning anything. Verify
  and report the starting state of the resource group first.
- az vm delete does NOT remove the OS disk, NIC, public IP or NSG. Sweep them explicitly.
  NIC FIRST, because it references the pip and the nsg.
- "It said deleted" is not the same claim as "it is gone". A disk once still listed after a
  successful delete; a re-check showed a propagation race. Re-check, and record which it
  was.
- Release the licence slot on every install. Evidence string: Machine deactivated
  successfully.
- Expected residual in clawfactory-validation: the storage account, the VNET, and the two
  baseline images. Nothing else. Prove it with an UNFILTERED resource list, not a grep for
  the VM name.
- Blobs in the validation container are retained as evidence, not billable compute.

CREDENTIAL HYGIENE

- The provider API key is read from Windows Credential Manager inside the launcher, handed
  to the driver, and never crosses a tool boundary, never appears on a command line, never
  enters a transcript. Report its length at most.
- The SMTP app password is a deliberately KEPT throwaway. Do not ask for a new one and do
  not ask for it to be revoked. If a phase needs it and it is absent, that phase is VOID.
- Any listener or proxy used in a probe records that a request arrived and whether an
  Authorization header was PRESENT. Never a header value.
- Env reads are single-key only. Never bulk-dump.

VERSION AND BUILD

- released-versions.tsv is the ledger and the version gate enforces it: a version already
  shipped against a DIFFERENT digest is refused, before signing. Obey it. Never delete a
  row to let a changed rebuild through. Bump instead.
- The ledger records the UNSIGNED digest. Signing embeds a countersigned timestamp, so a
  signed digest differs on every run over identical input.
- The ledger only sees what build_release.ps1 wrote. Anything shipped by another route
  needs a row added by hand or the ledger silently stops being a complete record while
  still looking authoritative.
- Commit released-versions.tsv with the build. An unrecorded release defeats the gate.

GIT

git status --short first. Explicit per-file staging, never git add -A. Never
git worktree add. Separate commits per logical change. Two repos, Secure-Setup and Studio,
both pushed. DO NOT TAG unless the prompt says to.

python is blocked by Windows Application Control on the build machine, so
dispatch_card.py will not run. Use the Dispatch API directly from PowerShell with
x-frontier-secret.
````

### Notes on using PROMPT 15

Read `ClawFactory_Install_Lessons_Learned.md` at the start of any session that touches
install behaviour. The preamble above is the operational residue of that file, not a
replacement for it.

The pre-flight checks and the calibration rule are the newest parts and they exist because
the last four sessions each shipped a defect that a few minutes of reading or one rigged
input would have caught. They are cheap and they are not optional. In particular the
dependency census answers two separate questions, who and when, and skipping the second is
what produced an install failure that took 21 minutes to surface 21 minutes away from its
cause.

The structural versus advisory distinction governs every claim this product makes. A
control enforced anywhere the agent's uid can influence is advisory and must never be
described otherwise. Marketing claims match the structural column only.

---

# Clauses earned in the v1.4.4 cycle

The four clauses below are not part of the PROMPT 15 text copied above. They were earned
in the v1.4.4 validation cycle (boxes A, B, C and D, the wrapper-fix build, the release
preparation, and the documentation reconciliation that followed the release) and until
2026-08-29 they existed only inside close-out documents in `docs/session_reports/`, which
is to say they governed nothing. They are added here so that a future job pastes them with
the rest of the preamble.

The first two are recorded verbatim as they were written in the close-outs that earned
them. The third is recorded together with a matching entry in
`docs/FAILURE_CATALOGUE.md`. **The fourth was added on 2026-08-29 by the documentation
reconciliation** and is the only one that governs the handoff card rather than a
measurement or a sentence.

## 1. The measurement being right does not make the expectation right

```
The measurement being right does not make the expectation right. State where each
expectation came from, and re-derive it when the thing it describes changes. When a probe
is edited to measure something new, the assertion is a separate edit and needs its own
calibration.
```

## 2. A probe is calibrated against a rigged input; a run is not

```
A probe is calibrated against a rigged input; a run is not. Before the first dispatch, read
what the box already holds that the probes will read: logs that append rather than
truncate, evidence files fetched by name, snapshots about to be overwritten. A second run
over a box that has already been run is not the same measurement as the first.
```

## 3. Chat does not assert product behaviour from memory

```
Chat does not assert product behaviour from memory. Any claim in a chat session about what
the product does, what ships, or how a user reaches it cites a repo file and line, a
validation close-out, or the installer script. Otherwise it is labelled INFERRED.

A CITATION PROVES THE PROVENANCE OF A SENTENCE, NOT THE PROVENANCE OF THE ARTEFACT.
Before citing a file as evidence of what a user sees, establish that the file cited is the
file that ships. For anything served, name the repository, branch and path the live surface
is actually built from, and confirm the deployed bytes match. Do not read the nearest local
copy with a plausible name. A stale copy answers every question you ask it, fluently and
wrongly. The same applies to any artefact with more than one copy: a bundled file versus its
repo original, a built installer versus its source, a vendored dependency versus upstream.
```

**Why this one exists.** No rule governed it before. A false premise about the chat
surface, that the desktop icon opened a chat session in Windows Terminal, was asserted in a
chat session, survived into a handoff document, and was then used as a premise in a product
argument about what a user experiences. It was caught only because the operator asked a
direct question about his own product. Every other clause in this file guards a
measurement; this one guards the sentences said between measurements, which had no guard at
all. See `docs/FAILURE_CATALOGUE.md` entry 12.1.

**Why the second paragraph exists.** Because the first one was obeyed and still produced a
false claim. On 2026-08-29 a session asserted that `clawfactory.app` carried a broken
ClawAgent download button, citing `docs/index.html:973` in this repository. The citation was
accurate: that line said exactly that. The file was a stale, unpublished copy that serves
nothing - `clawfactory.app` is built from `BuzzardsBay/clawfactory-site`, and this
repository's Pages API returns 404. The claim was repeated four times and written into a
close-out as a correction of the job brief, when the brief had been right. A cited claim is
more dangerous than an uncited one, because the citation buys confidence that the reader has
no cheap way to re-check. It was caught only when the operator said "fix the button" and
fixing it required finding it. Acting on that instruction without finding it would most
plausibly have meant re-uploading a ClawAgent installer that had been deliberately withdrawn
as unsafe. See `docs/FAILURE_CATALOGUE.md` entry 12.3.

## 4. A handoff card carries the evidence that could change the instruction

```
A handoff card carries the evidence that could change the instruction, not only the
evidence needed to approve it. A card written to get a yes or a no on a fixed sequence
cannot produce a better sequence. Enumerate the subject fully -- counts, states, sizes,
who has touched it -- even where the enumeration is not needed to answer the question
being asked, because the operator is deciding and you are not.

And where two instructions arrive in the same reply, check them against each other
before executing either. Following both literally can produce a claim that is false
about the surface it lands on.
```

**Why this one exists.** On 2026-08-29 a card asked for approval to prepend a warning to
four archived ClawAgent releases and **keep their installers downloadable so existing links
keep working**. Because the brief had said not to take the number four on faith, the card
enumerated all four assets rather than counting them, and the enumeration carried
`download_count: 0` on every one. **If nothing had ever been fetched there were no existing
links to preserve**, and the only argument for leaving a knowingly-unsafe installer
downloadable evaporated. The operator did not approve the sequence; he changed it, to
warning **and** delete, and the reason he could was that the card contained the measurement
that undercut its own premise.

The second paragraph is the same day's second lesson. The revised reply said to apply the
warning block **unchanged**, and that block contained the sentence *"The installer below
remains downloadable so existing links keep working."* Applying both instructions literally
would have published, on four public pages, a sentence false about the page it sat on --
manufacturing this catalogue's central defect class on a customer-facing surface rather
than fixing it. The conflict was caught before the first write, reported, and resolved by
replacing that one sentence.

Full record: `docs/session_reports/2026-08-29_doc_truth_and_clawagent_hazard_closeout.md`
section 6.3 and 6.5.

---


---

# Clauses earned in the 2026-09-01 harness-hardening job (card #259)

These five are **not** part of the PROMPT 15 text copied above. They were earned by the four
harness defects that the v1.4.3, v1.4.4 and v1.4.5 cycles found or nearly missed, each of
which produced or would have produced a false reading, and none of which was fixed at the
time. They are added here so a future job pastes them with the rest.

The ratio those three cycles produced is the reason this section exists: **twelve instrument
defects against zero product defects** in the last cycle alone. Every clause below guards the
instrument, not the product.

## 1. A liveness signal must be emitted by something other than the thing it reports on

```
A liveness signal must be emitted by something other than the thing it reports on. A
heartbeat stamped by the same loop that executes the work stops beating for exactly as
long as the work takes, so "alive and busy" and "dead" become one reading -- which is the
ambiguity a heartbeat exists to remove. Stamp it from a waiter, not from the worker, and
make it NAME what it is waiting on. Three states -- idle, running <job>, dead -- are three
different responses, and a signal that can only distinguish two of them will send the wrong
one a third of the time.
```

**Why this one exists.** `interim-v120-runner.ps1` stamps its heartbeat at the top of the
poll loop and executes each job synchronously inside that loop. Its own header says the
heartbeat exists "so the driver can tell *runner alive, job slow* apart from *runner dead*
-- those need different responses and guessing between them wasted a run". It cannot: during
a sixteen-minute install the heartbeat does not move. `interim-v146-runner.ps1` then recorded
the freeze in its header as expected behaviour, which turned a defect into a contract and is
the more serious half. Closed in `validation/cfv-runner.ps1`.

## 2. A channel that can silently return less than it was asked for must prove it returned all of it

```
A channel that can silently return less than it was asked for must be made to PROVE it
returned all of it. Bounding the request is necessary and not sufficient: a bound is a guess
about a limit nobody has measured, and the failure it guards against is invisible by
construction. End every payload with a tail sentinel carrying a per-dispatch nonce. A reply
without its sentinel is a NAMED CONDITION -- truncated, or the payload died before its own
last line -- and is never an empty result. Measure where the limit actually is rather than
inheriting a figure from a close-out.
```

**Why this one exists.** `az vm run-command` returns **empty above roughly 16 KB while `az`
exits zero**. A poller that asked for a 16.6 KB `.out` showed nothing for forty minutes while
the `.done` barrier had existed the whole time; trusted at face value the conclusion would
have been that the install hung. Closed by `Invoke-CfvBox`'s sentinel and
`Receive-CfvJobOutput`'s chunked retrieval, which asserts the reassembled byte count against
the count the box itself reported. `Measure-CfvOutputLimit` determines the real limit.

## 3. A shared path with no owner is an accumulation, not a workspace

```
A shared path with no owner is an accumulation, not a workspace. Scope every run to a
directory named for that run, and stamp it with who created it, from where, and when.
Otherwise markers, job files and evidence from different runs, boxes and sessions pile up in
one place, and the question "has this box already been measured, and by what" -- which
decides whether a reading means anything at all -- has no answer on the box.
```

**Why this one exists.** `C:\cfv` was flat and unscoped across every run this project has
taken. The preamble already requires knowing that *a second run over a box that has already
been run is not the same measurement as the first*; the old layout gave a driver no way to
find that out. Closed by `C:\cfv\runs\<RunId>\` and `_owner.json`. The `C:\cfv` root is kept
because eighty files in the tree reference it and a tree-wide rename is a far larger change
than the defect warrants.

## 4. The sentence that reports an outcome is emitted by the check, not by the code path

```
The sentence that reports an outcome is emitted by the CHECK, not by reaching the line after
the call. Under $ErrorActionPreference = 'Continue' -- which every driver here sets -- a
failing call writes an error and execution continues, so an unconditional success line
prints over a failure and the transcript is worse than silent: it is confidently wrong.

And a precondition is not an outcome check. `if (Test-Path $source) { upload; report }`
establishes that the SOURCE existed. It says nothing about whether the upload succeeded, and
reading it as a guard is how an audit of this exact defect reported the two live instances
clean.
```

**Why this one exists.** A SAS expiry built from local time and labelled `Z` made ten uploads
return `AuthenticationFailed`, and the script printed `uploaded <file>` for all ten. That is
`switch-provider.ps1:349`'s defect, reproduced by the session that was writing it up.
`validation/cfv-successline-census.ps1` enumerates the shape tree-wide; the second paragraph
was earned when that instrument's first calibration passed and it then reported the two known
live instances clean.

## 5. THE AUTO-LOGON CLAUSE WAS WRONG ABOUT ITS OWN FLEET

```
"Every WSL test needs the interactive auto-logon session" conflated two different claims.
wsl.exe refuses NT AUTHORITY\SYSTEM BY NAME. That is a constraint on the ACCOUNT. It is not
a constraint on interactive logon, and the last three cycles armed no auto-logon at all --
they used an operator-initiated RDP session and paid one login per boot for it.

The prohibition that actually binds is the CREDENTIAL one: arming auto-logon requires writing
a cleartext password to HKLM Winlogon DefaultPassword, and every implementation in this tree
gets that password by resetting the account with `az vm user update`, which PROMPT 15 forbids
outright. So the question was never "how do we make a one-shot survive" -- it was "how do we
get a non-SYSTEM context without a credential".

A scheduled task with an S4U principal is a non-SYSTEM context that needs no password, can be
registered by SYSTEM through run-command, and fires at every boot. Whether WSL works under
that token is a SEPARATE claim and must be measured with a control, never assumed from "not
SYSTEM".
```

**Why this one exists.** The clause it corrects said *"after any reboot a human must log in
over RDP and start the on-VM runner by hand. Not scriptable around."* The second sentence was
an inference from the credential rule, stated as a fact about Windows, and it governed three
cycles. `docs/session_reports/2026-08-27_v143_validation_closeout.md:320` records the fleet's
real state: `AutoAdminLogon=` empty, *"the driver arms no auto-logon"*. On `cfv-191` the cost
of the inference was **54 minutes of dead wall clock**: Windows came back at `18:55:19` and
nothing ran until the operator logged in at `19:49:24`.
# Open measurements owed by the next validation cycle

**This section is deliberately OUTSIDE the paste block above.** It is not boilerplate and
must not be pasted into every job. It is here because this is the file a ClawFactory
validation job opens, and an open measurement recorded only in a close-out or a v1.5
planning page governs nothing -- which is the reason this file exists at all.

**Clear an entry from this list only by measuring it, or by the product change that removes
the subject.** Do not clear one because it looks stale.

## OM-1. The `:8787` dashboard has never been opened, on any release, by rule

**Card `#311`. Owed since 2026-08-29.**

`ClawFactory-Secure-Setup.iss` `[Icons]` ships `{group}\ClawFactory Dashboard`, which runs
`cmd.exe /c start http://127.0.0.1:8787`. It is one click from the Start Menu under hover
text that invites it and warns of nothing.

**This project forbids its own sessions from opening that URL.**
`ClawFactory_Session_Handoff_2026-07-14.md:51` says *"Never open the dashboard at
127.0.0.1:8787 (restart-loop hazard)"*, and `docs/session_reports/PHASE0_RECON_2026-07-13.md`
calls it *"the hazardous `:8787` endpoint"*, *"hazard rule #5"* and *"the forbidden
dashboard"*.

**The tree supports two readings and settles neither.**

- **(a)** The hazard was real, was root-caused to a missing `.wslconfig` `vmIdleTimeout`,
  was fixed in v1.0.1, and the rule outlived its cause. The shortcut is harmless and the
  rule is stale. `CLAUDE_ClawFactory.md` records `openclaw-control-ui` issuing a restart RPC
  in that entry's list of causes explicitly **ruled out**.
- **(b)** The hazard is real and separate from the `vmIdleTimeout` bug, and the shortcut
  hands it to a first-run user.

**The finding is that nobody knows which, and the reason is the rule itself.** The surface
has gone unmeasured on every release since v1.0.1 **because opening it is forbidden**. A
standing prohibition has kept a shipped, customer-facing, one-click surface untested across
six versions.

**What the next cycle owes.** One measurement, on a validation box, under an **explicit
one-time suspension of hazard rule #5, recorded as such in the run plan before it is taken**
-- not decided at the keyboard. It must:

1. **Be taken on a box that is being torn down anyway**, last in the run order, after every
   other phase has produced its verdict. If reading (b) is right, this wedges the machine.
2. **Carry a positive control in the same run**: the gateway answering `/status` with 200
   immediately before the click, and again after, from a path that is *not* the browser.
   Without the "after", a wedge and a clean result look identical in the transcript.
3. **Record what a first-run user actually sees**, which is the half that is not in doubt.
   The dashboard is device-pairing gated (`SUPPORT_MATRIX.md:26`) and the installer ships no
   pairing flow, so the expected result even under reading (a) is a dead end. Capture the
   screen, not a description of it.
4. **Not be confused with a verdict on the shortcut.** `docs/V1_5_BACKLOG.md` item 5 asks
   for the shortcut to be **deleted** regardless of how this measures. Deleting it removes
   an invitation; it does not answer whether the surface is hazardous, and this measurement
   does not answer whether the shortcut should ship.

**If the measurement is not taken, say so in the close-out and leave this entry standing.**
A cycle that skips it has not closed it.

> **STILL OPEN after the v1.4.5 cycle, 2026-08-31.** That cycle provisioned two boxes and
> did not take this measurement: no suspension of hazard rule #5 was recorded in its run
> plan, so per the paragraph above the entry stands and the next cycle still owes it. Two
> cycles have now passed it over. Recorded here rather than only in a close-out, because a
> second silent skip is how an entry like this dies.

---

## OM-2. The reboot-and-resume path has never been reached on a first-run machine

**Owed since 2026-08-30, from `PR.C8`, which was scored VOID with a named reason.**

`Step-EnsureWsl`'s reboot-and-resume subsystem — `Invoke-WslRebootAndResume`, the
`ClawFactory-Resume` scheduled task, the resume flag, and the `$Resume` branch that completes
the install after the restart — **was not exercised on either box of the v1.4.5 cycle, by any
valid route**, and no earlier cycle reached it on a machine in the first-run state.

- On the stock box, the D1 gate did not fire (see `docs/FAILURE_CATALOGUE.md` 15.1) and
  `$kernelOk` was true after `Update-WslEngine`, so `Step-EnsureWsl` took the import path:
  reboot branch taken = 0, bundled-import = 1.
- On the baked box, the succeeding path completed and no reboot was needed.

**The claim this leaves open is stronger than "untested".** On a modern Windows 11 24H2
machine with a working `wsl --update`, the reboot-and-resume path appears to be
**unreachable by the normal first-run flow entirely**. If that is right, a whole subsystem —
including a scheduled task that runs as SYSTEM at startup — ships on every release and is
reached by nobody, which is its own finding and not a reassurance.

**NAMED CONSTRUCTION REQUIREMENT.** This row cannot be taken by choosing a different image or
a different size. It needs **a machine on which `wsl --update` cannot install the WSL engine,
so that `wsl --status` still fails afterwards and `$kernelOk` is false.** That is a real
scenario — an offline machine, a blocked Store/CDN route, a policy-restricted host — but it is
**not one an Azure VM in the standard validation configuration can be put into**, which is why
the row voided rather than failed.

Candidate constructions, none yet attempted, listed so the next cycle starts from a list
rather than from the problem:

- Block the WSL engine's download route at the NSG or with a host firewall rule *before*
  `Update-WslEngine` runs, and prove the block landed with a control in the same run.
- A policy-restricted host: the WSL MSI install path denied by AppLocker or WDAC.
- Any of the above, with the same box then unblocked so the `$Resume` branch can complete —
  otherwise the row measures only the stop and not the resume, and it must measure both.

**Do not let this disappear into a pass.** `PR.C8` is VOID, not PASS, and a cycle that does not
construct the state records it VOID again with the reason, rather than dropping the row.

