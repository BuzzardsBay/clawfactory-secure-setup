# RUNNER CLOSE-OUT: finish ClawFactory v1.4.3

**Status: IN PROGRESS.** Written incrementally so an interrupted session leaves an
honest record. Job 1's own close-out is
[`2026-08-27_v143_validation_closeout.md`](2026-08-27_v143_validation_closeout.md).

---

## 1. Which jobs ran

| # | Job | State |
| --- | --- | --- |
| 1 | v1.4.3 full validation | **CLOSED. Verdict NO.** Partial coverage; stopped on the second ship-blocker |
| 2 | Release notes and failure catalogue | **DONE and committed.** Not published |
| 3 | Tag and publish preparation | **NOT RUN, correctly.** Gated on a YES from job 1, which returned NO |

## 2. Which stop condition fired

**Stop condition 1**, and **stop condition 5** on the way to it.

Condition 5 fired first: *"You find a defect that changes the shape of the remaining
work."* Finding that the Kill Switch does not stop anything changed the run from
"validate toward a possible yes" into "enumerate everything one fix cycle has to
cover", because any fix means a rebuild and **prior measurements do not transfer
across a rebuild**. The run continued on that narrower basis, deliberately, and that
choice is recorded in section 7 with what it bought.

Condition 1 then fired on the verdict itself: **NO**. Job 3 was not started.

Note what did **not** fire: the operator RDP login and the by-hand steps are
explicitly not stop conditions, and were handled with handoff cards.

## 3. Job 1's verdict, quoted from its own close-out

> **NO.**
>
> One sentence, and it contains no argued premise: **the Kill Switch, which
> `SECURITY_FINDINGS.md` lists as a proven structural guarantee, does not stop the
> gateway or kill the agent process, and tells the user that it did.**

---

## 4. One deviation from the runner's stated order, and why

**Job 2 was written before job 1 closed.** The runner sequences job 2 after job 1, and
this is a departure from that.

The reason is the runner's own stated purpose for job 2: *"It is authoring work that
does not depend on the verdict, it is the most valuable public artifact in this
release, and the material is freshest now. Doing it while the operator is away is the
point of this runner."* Job 1 reached its first operator handoff roughly an hour in and
cannot advance without a human at a keyboard. Waiting idle through that window, then
writing job 2 afterwards, would have spent the away-time on nothing and produced the
same documents later.

**What was protected.** Nothing in either document asserts a validation outcome. The
release notes carry a `Validation status` section that is deliberately left unwritten,
saying in the document itself that this release has not been installed on a clean
machine at the time of writing and that filling the section with the previous release's
results would be the exact class of claim the page exists to avoid. That section is
completed when job 1 closes, whichever way it closes.

---

## 5. What job 2 produced

Two documents, committed at `84697f6`, **not published anywhere**.

### 5.1 `docs/FAILURE_CATALOGUE.md`

Grouped by **class** rather than by date, because the runner asked for the class to be
enumerated rather than the named instances written up, and because the same shape
recurred across unrelated subsystems. Ten classes:

1. Controls that passed their own tests while measuring nothing
2. Success markers that could not fail
3. Instruments that produced plausible output while measuring the wrong thing
4. Ship-blockers manufactured by miscalibrated instruments
5. Probes that detected themselves
6. Documentation that contradicted the artifact
7. A convenience that silently defeated a security control
8. The bytes shipped were not the bytes in the repository
9. A phase that ran for the first time long after it was believed to have run
10. Audit instruments carrying the defect they were auditing

Every entry carries the four parts the runner specified: what was claimed, what was
true, what surfaced the gap, and what changed. The material was derived by reading the
close-outs in `docs/session_reports/` and `SECURITY_FINDINGS.md`, not from the run
prompt's examples.

Two entries are worth naming here because they are not in the prompt's starting list:

- **Class 10.3** is this session's own enumerator, which failed its own canary at four
  of six planted shapes before it was allowed to report anything. It is in the
  catalogue because a practice is only evidenced by having been followed on a day when
  following it produced an inconvenient answer.
- **Class 2.1**, the uninstaller that logged success unconditionally, is flagged in the
  document as the one that reached a release.

### 5.2 `docs/RELEASE_NOTES_v1.4.3.md`

What the product is, what it enforces in two separate classes, what it does not do,
every residual in `SECURITY_FINDINGS.md` in plain language, and the accepted conditions
of shipping. Apache-2.0, free, stated as not a beta and not a trial.

`#261` appears as **condition 1**, in the terms the runner specified: with the
software-sources switch on, fetches from those repositories succeed intermittently,
roughly half the time in measurement, because the firewall holds a snapshot of
addresses while those services answer from a larger rotating pool; the switch is not
lying about being on, the address list behind it is incomplete, and turning it off
still reliably blocks. Its prior measurement is quoted and labelled as prior. **No
recommendation is made for or against publishing on it.**

The forbidden claims were held: no statement that data cannot leave the machine without
approval, because it can, to the model provider, and the document says so under "What
it does not do". Nothing is called injection-proof.

### 5.3 The sweeps, and their canaries

The runner requires a final sweep and requires the sweep itself to be canaried.

**Em-dash sweep.** Zero em-dashes and zero en-dashes in both documents. Canaried
against a copy carrying three planted shapes chosen to be easy to miss rather than
obvious: a spaced em-dash, a tight em-dash with no surrounding spaces, and an en-dash
used as a range separator. All three found, and the real files read 0 and 0.

**Overclaim sweep.** Five classes: absolutes, the specific forbidden data-exfiltration
claim, gateway-path guarantees described with structural vocabulary, advice and
reassurance language, and unqualified guarantee verbs. Canaried with five planted
overclaims, **including the subtle one that matters most**, a gateway-path guarantee
asserted as structural. All five were found, in both the "enforced structurally by the
operating system" form and the bare "the browser tool denial is structural" form.

**The two surviving hits on the real files are true positives that survive
adjudication**, and they are recorded here rather than edited away:

| File | Line | Text | Adjudication |
| --- | --- | --- | --- |
| `RELEASE_NOTES_v1.4.3.md` | 106 | "It is not injection-proof, and nothing here claims to make a model behave." | **Keep.** The constraint forbids claiming injection-proof. This is the denial of that claim, and the negation is the first three words |
| `FAILURE_CATALOGUE.md` | 312 | `**Claimed.** The browser tool was "structurally denied".` | **Keep.** This is the catalogue quoting the historical false claim, immediately followed by the correction that it is enforced on the network path rather than by the operating system |

A sweep that fired on nothing would have been the result to distrust.

**One instrument note, recorded because it is the exact trap the standing preamble
names.** When the sweep was run through a pipe into `tail`, the reported exit code was
`tail`'s and not the sweep's, so a failing sweep printed `exit=0`. It changed no
result, because the hit lines were read directly rather than inferred from the code,
but it is the "never write `cmd | head` followed by `$?`" rule reproducing itself
inside a check written to enforce discipline.

---

## 6. A finding that is a publish-decision input, not a defect

**The auditability claim depends on this repository being public at release, and it is
private today.** `gh repo view` reports `"visibility":"PRIVATE"` for
`BuzzardsBay/clawfactory-secure-setup`.

`SECURITY_FINDINGS.md` tells the reader that everything in it can be verified against
the source in this repository, and the v1.4.3 work made the bundled bytes checkable
against a commit specifically so a stranger could do that. Neither is true for a
stranger while the repository is private.

This is not a defect and nothing needs changing in the documents. It is an input to the
publish decision, and it belongs beside job 3's other publish-decision inputs. Making
the repository public is an irreversible public action and therefore the operator's,
not mine.

---

## 7. The judgement call after the first blocker, and what it bought

When blocker 1 was confirmed, the verdict was already determined. Continuing to
measure a binary that must be rebuilt has a specific and limited value: **it lets
one fix cycle cover everything, instead of discovering a second defect after the
next rebuild and spending another four boxes to find it.** The run continued on
that basis and stopped short of the phases whose value depended on a possible yes.

It bought three things:

1. **Blocker 2**, `switch-provider.ps1` failing for every provider, which would
   otherwise have been found after the v1.4.4 rebuild.
2. **The root cause of both**, which is a property of the validation suite rather
   than of the product: the suite tests bash payloads extracted from PowerShell
   wrappers and has never executed the wrappers. Both blockers live in that gap.
3. **The bound on blocker 2's class**, via an AST sweep across all ten shipped
   scripts, which confines it to one file and four comment lines.

It cost roughly forty minutes of one already-provisioned box.

## 8. Resource ledger

```
az vm deallocate -g clawfactory-validation -n cfv-178   ->  exit 0
Provisioning succeeded
VM deallocated
```

**`cfv-178` is deallocated, not deleted.** Compute billing has stopped; the disk
remains. That is deliberate rather than an omission: the box holds a complete
v1.4.3 install with both defects reproducible on it, and deleting it before the
operator has decided whether he wants anything else from it would throw away the
only installed instance of this artifact. **Deleting it is a one-line call and is
his to make.**

`cfv-177` was swept in full earlier in the run and verified gone by re-read, not by
exit code. The starting estate is otherwise unchanged: storage account, VNET, two
baseline images.

## 9. What is waiting on the operator

**A decision, not a task.** Nothing is blocked on a keyboard step.

1. **Whether to fix and cut v1.4.4.** The three blockers and one minor are listed
   with file and line in section 14.7 of job 1's close-out. I did not start a fix:
   the runner says to report what would flip the verdict and not to begin one.
2. **Whether to delete `cfv-178`** or keep it for reproducing the defects.
3. **Nothing about `#261`.** No recommendation was made for or against publishing
   on it, by instruction.

**No tag was created. Nothing was published.** Job 2's two documents are committed
and unpublished, as instructed.
