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

```
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
- Image clawfactory-win11-baseline-v2, resource group clawfactory-validation.
- ONE az vm run-command invoke at a time. They queue and interfere.
- az vm run-command runs as SYSTEM and WSL refuses to run there. Every WSL test needs the
  interactive auto-logon session. Auto-logon is a ONE-SHOT: after any reboot a human must
  log in over RDP and start the on-VM runner by hand. Not scriptable around. Plan it into
  any run that reboots.
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
```

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

The three clauses below are not part of the PROMPT 15 text copied above. They were earned
in the v1.4.4 validation cycle (boxes A, B, C and D, the wrapper-fix build, the release
preparation, and the documentation reconciliation that followed the release) and until
2026-08-29 they existed only inside close-out documents in `docs/session_reports/`, which
is to say they governed nothing. They are added here so that a future job pastes them with
the rest of the preamble.

The first two are recorded verbatim as they were written in the close-outs that earned
them. The third is new and is recorded together with a matching entry in
`docs/FAILURE_CATALOGUE.md`.

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
```

**Why this one exists.** No rule governed it before. A false premise about the chat
surface, that the desktop icon opened a chat session in Windows Terminal, was asserted in a
chat session, survived into a handoff document, and was then used as a premise in a product
argument about what a user experiences. It was caught only because the operator asked a
direct question about his own product. Every other clause in this file guards a
measurement; this one guards the sentences said between measurements, which had no guard at
all. See `docs/FAILURE_CATALOGUE.md` entry 12.1.
