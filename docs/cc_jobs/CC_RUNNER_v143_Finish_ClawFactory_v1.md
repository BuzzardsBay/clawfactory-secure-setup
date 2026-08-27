# CC RUNNER: finish ClawFactory v1.4.3

Repo root: `C:\Users\bmcki\ClawFactory-Secure-Setup`. `cd` there and confirm first.

This is a **runner**, not a single job. It sequences three jobs in one session and decides
between them from evidence rather than from a conversation with the operator. The operator is
pinged only for the things that genuinely require him. Everything else you do yourself.

Read this whole file before starting anything.

---

## The sequence

| # | Job | Source | Runs when |
| --- | --- | --- | --- |
| 1 | v1.4.3 full validation | `docs/cc_jobs/CC_v1_v143_Validation_v1.md` | always, first |
| 2 | Release notes and failure catalogue | section B below | after job 1 closes, whatever its verdict |
| 3 | Tag and publish preparation | section C below | only if job 1's verdict is YES |

Job 2 runs even on a NO verdict. It is authoring work that does not depend on the verdict, it
is the most valuable public artifact in this release, and the material is freshest now. Doing it
while the operator is away is the point of this runner.

---

## STOP CONDITIONS

**Stop the runner, write a close-out, notify, and do not continue to the next job when:**

1. Job 1's fitness verdict is **NO**. Report what would flip it. Do not start a fix.
2. Anything would cost money beyond the validation boxes already planned in job 1's TASK 0.
3. Anything would be public or irreversible: a tag, a GitHub release, a push to a public site,
   an archive. Job 3 prepares these and stops before executing them.
4. A prompt or a premise is wrong, ambiguous, or would break something outside its scope.
   Reporting a bad instruction is the job working.
5. You find a defect that changes the shape of the remaining work.
6. The session is running out of room. Write the honest incomplete-state close-out.

**Do NOT stop the runner for:** an operator RDP login, a by-hand check, or a dialog that needs
clicking. Those are normal inside job 1 and are handled with handoff cards, not by ending the
run. Ping, wait, continue.

**Never ask permission to proceed between jobs.** The conditions above are the whole decision
procedure. If none fires, move to the next job.

---

## A. JOB 1: validation

Execute `docs/cc_jobs/CC_v1_v143_Validation_v1.md` in full, exactly as written, including its
PROMPT 15 preamble and its own end-of-session gate and close-out.

When it closes, read its fitness verdict from its own close-out rather than from memory of the
run, and record which branch of this runner you are taking and why.

---

## B. JOB 2: release notes and the failure catalogue

This is the release's most credible public document and it is a better argument for trusting
this builder than the installer is. Almost nobody publishes it.

### B.1 What it is

Two documents in `docs/`, both markdown, both written to be read by a stranger who has never
seen this project:

- `RELEASE_NOTES_v1.4.3.md` — what the product is, what it does structurally, what it does not
  do, how to install it, and the accepted conditions of shipping.
- `FAILURE_CATALOGUE.md` — the full record of what was wrong and how it was found.

### B.2 Where the material comes from

Every close-out in `docs/session_reports/`, plus `SECURITY_FINDINGS.md`. Derive the catalogue
from those files by reading them, not from this prompt's examples. Enumerate the class rather
than writing up the instances named here.

Known material, as a starting point and not as the list:

- Controls that passed their own tests while measuring nothing.
- Harness bugs producing plausible output.
- A ship-blocker manufactured by a miscalibrated instrument.
- A Start Menu item that silently defeated a security control.
- A README claiming no telemetry over an installer that posted a machine GUID on every run.
- A credential-leak probe that detected its own `grep` and reported a leak that did not exist.
- A job dispatcher that restated a stale results file as current, with nothing looking wrong.
- An uninstaller that ran half of itself and logged success unconditionally.
- Ten bundled files whose bytes were not the bytes in the repository, invisible to `git status`
  and `git diff`, six of which already carried the rule that should have prevented it.
- A phase that ran for the first time after five cards claimed it had.

For each entry: what was claimed, what was true, how the gap was found, and what changed as a
result. The third of those is the interesting one and it is usually a control that fired.

### B.3 Constraints, all non-negotiable

- **No em-dashes anywhere in either document.** Check before finishing.
- **Understate rather than overstate.** If a claim needs a qualifier it gets one.
- **Structural versus advisory is sacred.** Marketing claims match only the structural column.
  Never "injection-proof". Never write that data cannot leave the machine without approval: it
  can, to the model provider.
- Apache-2.0, free, not a beta and not a trial.
- Every residual in `SECURITY_FINDINGS.md` appears in the release notes, in plain language.
- **`#261` appears as a written accepted condition of shipping**, in the terms a reader needs:
  with the software-sources switch on, fetches from GitHub and npm succeed intermittently,
  roughly half the time in measurement, because the firewall holds a snapshot of addresses while
  those services answer from a larger rotating pool. The switch is not lying about being on. The
  address list behind it is incomplete. Turning it off still reliably blocks.
- Do not name the operator's employer, any client, or any third party.
- No credential, key, token, host, IP or path from any private environment.

### B.4 Verify before finishing

Every load-bearing claim in the release notes must be checkable against a close-out or against
the code. Cite the close-out file for each. A claim you cannot source, remove.

Run a final sweep for em-dashes, for advice language, and for any claim that belongs in the
advisory column but reads as structural. Report the sweep's result and canary it: insert one
synthetic overclaim, confirm the sweep finds it, remove it.

Commit both documents. Do not publish them anywhere.

---

## C. JOB 3: tag and publish preparation, prepared but NOT executed

Runs only on a YES from job 1. Everything here is preparation. **Nothing in this section is
executed.**

C.1 Identify the exact commit the tag would point at, and confirm the artifact under test was
built from it.

C.2 Draft the GitHub release body in a file. Do not create the release.

C.3 Verify the public site's download path. `clawfactory.app` is live and serves from
`BuzzardsBay/clawfactory-site`. Report where its download link currently resolves and what it
would need to point at. Report, do not change.

C.4 Confirm `clawagent-setup` is still archived, public, and carries its supersession notice,
and restate that its release assets still contain the retracted copy. That is an accepted
position and a publish-decision input.

C.5 Print a single decision card for the operator containing: the tag name and target commit,
the artifact digest and byte count, the release body as drafted, the site change required, and
the exact commands that would execute it. He runs them or tells you to.

**Stop there.** Creating a tag, cutting a release, and changing a public site are irreversible
public actions and they are his.

---

## D. Runner close-out

One close-out for the whole runner, in addition to each job's own, at
`docs/session_reports/YYYY-MM-DD_v143_runner_closeout.md`. Committed, printed in full,
unprompted.

It states: which jobs ran, which stop condition fired if any, job 1's verdict verbatim, what
job 2 produced, whether job 3 ran, and exactly what is waiting on the operator. If it is waiting
on nothing, say that plainly.

Both repos pushed. **No tag.**
