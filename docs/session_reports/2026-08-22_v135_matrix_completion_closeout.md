# CLOSE-OUT: v1.3.5 validation matrix completion, card #258

Session 2026-08-22, on `cfv-169`, against the already-installed 1.3.5 artifact.
No rebuild, no signing, no tag. No shipped file changed.

**Artifact under test, verified on the box rather than inherited:** signed sha256
`71aae514ca0cf00f757206416787541040383a6888379330cb930f3263bb4db6`, 440,614,960 B,
Authenticode `Valid`, countersigned timestamp good to 2026-10-22. The signing
certificate's own `NotAfter` is 2026-08-20 and that is expected, not an alarm:
Trusted Signing mints short-lived certs and the countersignature is what keeps the
artifact valid. Nothing new can be signed until it is renewed, which is why this
job carries no build.

---

## 1. The matrix, every row at its true state

| # | Test | State | Where measured |
| --- | --- | --- | --- |
| 1 | Clean install, all resources, all pins | PASS | card #258, 2026-08-19 |
| 2 | Provider gate healthy plus blocked CONTROL | PASS | card #258, 2026-08-19 |
| 3 | Gate skipped under deferred provider | **NOT RUN** | needs a second clean box with `-Provider later`; explicitly out of scope for this job and blocked behind the certificate |
| 4 | No toolchain address enters after a switch | PASS | card #258, pre and post reboot |
| 5 | Toggle OFF, sources unreachable after a switch | **PASS on npm; GitHub arm VOID (#261)** | `TC.2c` this session, pre and post reboot |
| 6 | CONTROL: toggle ON, reachable | **PASS on npm both passes; GitHub arm VOID (#261) pre-reboot, PASS post-reboot** | `TC.1c` this session |
| 7 | `TC.3` re-run | **PASS**, pre and post reboot | this session |
| 8 | `TC.1,2,4,5,6,7,8` regression | **pre-reboot 28 PASS / 2 FAIL; post-reboot 30 PASS / 0 FAIL** | this session |
| 9 | MANUAL panel checks | **PASS** | this session, by hand with the operator |
| 10 | Reboot pass | **PASS** | this session, 30/30 post-reboot |
| 11 | Harness self-test 15/15 on the box | **PASS** | this session |
| 12 | Zero malformed verdict rows | **PASS**, 110 of 110 rows counted across six phases | this session |

**Rows that had never passed in any run, across cards #245, #257 and #258, and
their state now:**

- **Test 9, the MANUAL panel checks: PASS.** First time.
- **Test 10, the reboot pass: PASS.** First time. Previously PARTIAL at best.
- **Test 11, the harness self-test on a VM: PASS.** First time; it had only ever
  run on the machine that wrote it.
- **Test 7, `TC.3`: PASS.** Previously mis-specified once and deferred twice, and
  had never produced a meaningful result.

**Test 3 remains NOT RUN** and is named as such rather than left blank. It needs a
second install with the provider deferred, which needs a second box, and the
sensible time to spend that is alongside the next build.

---

## 2. Task 1: does the toggle actually stop skill installation?

**No. A real ClawHub skill installation completes with the toolchain toggle off.**

The measurement, `SK.3`, on cfv-169:

```
POLICY_AFTER_OFF=false        TOOLCHAIN_COUNT_OFF=0      HUB_ADDR_IN_ALLOWED=1
INSTALL_OFF_RC=0
OFF_ONDISK /home/clawuser/.openclaw/workspace/skills/skill-git-scm
OFFPEER 216.150.1.1:443       OFF_DROP_TOTAL=0
```

`openclaw skills install skill-git-scm` ran as uid 1000, exited 0, the skill landed
on disk, the box held an established TLS connection to `216.150.1.1:443` for the
duration, and nothing was dropped. `216.150.1.1` is the address `clawhub.ai` shares
with `openclaw.ai`, a permanent base host in `@allowed_ipv4` that no toggle can
revoke.

**The control fired in the same run.** The identical install with the toggle ON also
exited 0 (`SK.5`, `SK.5.CTL`). Without it, a failure or success with the toggle off
says nothing: that gating is the inference cfv-166 made and cfv-167 refuted, and it
is why `SK.3` is written to record VOID rather than a finding when the control does
not fire.

Phase totals: PASS=14, FAIL=2, VOID=0, INFO=3, 19 of 19 rows counted, 7 of 7
positive controls fired, 2 of 2 preconditions met.

**Two guards on this result, both deliberate:**

- A toggle-OFF success proves nothing if it came from a local cache. The `ss` peer
  sample separates "installed over the network" from "installed from disk", and a
  success with no sampled socket records VOID rather than a finding. Here a real
  socket was observed.
- The resolution attempt that picks the install target is swept before the subject
  arm runs (`SK.2.CTL2`), so the subject is a genuinely fresh install.

### Is the shipped copy accurate as written? No. And it is on three surfaces, not two.

1. `resources/clawfactory-fetchctl.js:262`, the CLI usage text.
2. The Studio Web access panel, pinned by `scripts/build_release.ps1:163` and
   checked by `validation/interim-v120-phase6.ps1:496`. The operator confirmed the
   on-screen wording by hand this session.
3. **`clawfactory-fetchctl` itself, at the moment of switching off**, which is the
   sharpest of the three because the product asserts it and is then contradicted
   seconds later in the same transcript:

```
[toolchain] backend=nftables toolchain=OFF addresses=0
  (skill installation, GitHub and npm are denied; the provider route is untouched)
```

The GitHub and npm halves of that sentence hold. The skill-installation half does
not.

**Nothing was changed.** No panel copy edited, `openclaw.ai` not removed from
`$baseHosts`. Both are the operator's decisions, as the job specifies. For what it
is worth when that decision is made: the ratified footnote already discloses the
mechanism ("Matching is by network address rather than by name, so allowing a site
also allows anything else served from the same address"), so the gap is between the
specific claim and the general disclosure, not a wholly undisclosed residual.

### What the earlier reasoning had wrong

The open question was whether installation talks to bare `clawhub.ai` or to
`api.clawhub.ai`, because only the first shares an address with a permanent base
host. Two premises that were load-bearing turned out to be false:

- The repo's only note on the mechanism (`PHASE0_RECON_2026-07-13.md`) records
  `openclaw plugins install`, npm-registry specs only. The shipped CLI has a
  separate `openclaw skills install <slug>`, documented as "Install a skill from
  ClawHub into the active workspace". A phase built on the recon note would have
  measured a path the product does not use for skills.
- "`api.clawhub.ai` measured BLOCKED with the toggle off" was never a toggle
  verdict. It measures blocked with the toggle **ON** as well (`SK.1b` FAIL), for
  the reason in section 4.

---

## 3. `TC.3`

**PASS, both passes.**

`TC.3` is only interpretable because `TC.1d` runs first: a real agent turn completes
with the toggle **ON**, and that gates the subject through `Require-Precondition`.
Both fired.

- Pre-reboot: `TC.1d` PASS, `TC.3.PRE` precondition met, `TC.3` **PASS**.
- Post-reboot: same, `TC.3.POSTREBOOT` **PASS**.

The switch narrows the box without bricking the agent, and the model reply is the
evidence. No VOID, so the contingency the job allowed for did not arise.

---

## 4. Every GitHub result, and the #261 attribution

**Pre-reboot the suite recorded two FAILs, `TC.1c` and `TC.5`, and both reduce to
one host.** In the same probe, `registry.npmjs.org` and `raw.githubusercontent.com`
CONNECTED, the provider control CONNECTED, and the un-allowlisted control was
refused. The instrument was sound and exactly `api.github.com` was unreachable.

That was re-probed rather than attributed by resemblance, because recording a FAIL
as a known issue on an inference is how a real regression gets filed away.
`interim-v135-githubreprobe.ps1` separates the two hypotheses on mechanism:

| Hypothesis | Prediction |
| --- | --- |
| #261 pool gap | an address the pool hands out is not covered by the set, **or** the host answers differently across attempts inside one run |
| real regression | every resolved address covered, and still unreachable |

Measured: `UNCOVERED 140.82.116.6` resolved but absent from `toolchain_ipv4`, while
`COVERED 140.82.116.5` was present, and six attempts returned five CONNECTED and one
blocked. Both halves of the signature. The membership instrument was proven able to
say yes in the same read (npm's address present), so a blanket "no" was ruled out.

**So: the GitHub arms of matrix tests 5 and 6 are VOID with #261 named.** The npm
arms stand as PASS. `TC.1c` **passed post-reboot**, which is itself further evidence
of intermittency rather than a fixed state.

**A widening of #261 found this session:** `api.clawhub.ai` also measured unreachable
with the toggle ON. The rotating-pool coverage gap is not GitHub-only. It is a
reliability defect and it fails CLOSED, so it is not a security finding, but it now
affects the skill hub as well as the code hosts. Card #261 should be updated to say
so.

---

## 5. Tests 9 and 10, without softening

**Test 9, the MANUAL panel checks: PASS.** All six checks in
`validation/MANUAL_CHECKS_studio.md`, driven by hand by the operator against the
shipped copy. The card headed "Software sources ClawFactory needs" is present with
its breakage sentence; the ratified footnote matches word for word including the
address-sharing clause; `docs.python.org` was added and removed cleanly; all three
malformed inputs (`https://example.com`, `*.example.com`, `example.com:8443`) were
refused with readable messages; the home route shows v1.3.0, is free of the false
"Studio backend unreachable" sentence, and the version and "Templates" render
separated.

Nothing in these six checks has a timer, so nothing needed staging on a fuse. The
timed-subject warning in the job applies to the Guard 2 approval-card suite, which
is a different set and was not part of test 9.

**A note on the count.** Every close-out to date calls this "five MANUAL panel
checks", while `MANUAL_CHECKS_studio.md` contains six and its own summary line says
"all six pass". Checks 1 to 5 are the Web access panel and check 6 is the home
route. All six were run. The matrix row should be renamed to six.

**Test 10, the reboot pass: PASS.** A full power cycle, confirmed by
`LastBootUpTime` moving from `2026-08-22T22:02:30Z` to `2026-08-23T00:47:53Z`, and
by a fresh interactive session with the runner started by hand. The four tests the
reboot pass had been missing (`TC.2`, `TC.3`, `TC.4`, `TC.8`) all ran, and the whole
suite came back **30 PASS / 0 FAIL / 0 VOID**, 7 of 7 controls fired, 1 of 1
precondition met.

---

## 6. Findings recorded but not acted on

1. **The panel copy overstates the toggle** (section 2). Operator's decision.
2. **#261 affects `api.clawhub.ai`, not just GitHub** (section 4). Card update owed.
3. **The Studio Start Menu shortcut has a wrong target path.**
   `TARGET_EXISTS=0`; it points at
   `C:\Windows\system32\config\systemprofile\AppData\Local\Programs\...` while the
   payload is correctly in the user profile at
   `C:\Users\clawadmin\AppData\Local\Programs\ClawFactory Studio\ClawFactory Studio.exe`
   (225,597,216 B, v1.3.0.0). **The app launches anyway**, so this is not a launch
   blocker: Windows resolves the moved target on its own. The user-visible cost is a
   noticeably slow first launch. I initially leaned toward this being the root cause
   of the old "Studio no-launch" symptom and the operator's test refuted that.
4. **The Studio Templates panel errors on load**, and it is the landing tab:
   "Failed to load templates: This panel is not wired in the desktop shell scaffold
   yet ... (GET /api/templates)". The message is honest about what it is. Recorded
   separately rather than folded into test 9, since it is not the failure mode that
   test checks for.
5. **The Studio lobster is not a working home link**, which
   `MANUAL_CHECKS_studio.md` assumes it is. The check doc should say to use the nav
   or a restart instead.
6. **`TC.1a` is misnamed on a re-run.** It reads "A fresh install has the toolchain
   switch ON", but on a box that has been toggled many times it measures the switch
   state at phase start, which is a precondition rather than a product claim. Not
   changed mid-matrix, so results stay comparable.

---

## 7. Instrument defects found in this session's own harness

Recorded because every one of them was caught by a control refusing to fire rather
than by a transcript looking wrong, and because four of them cost a run each.

1. **An ad-hoc heartbeat poller fabricated a pass.** `az ... -o tsv` returns an
   array; `-match` on an array returns matching elements instead of populating
   `$Matches`, so the age parsed as empty, `[int]''` became 0, and 0 is less than 90.
   It reported the runner alive while it had never been started. Fixed with
   `[regex]::Match` over a joined string plus a parser control that must fail on a
   no-age input.
2. **Two concurrent `az vm run-command` calls**, which the service refuses. My
   error; the environment rule warns about it. It failed loudly with a Conflict
   rather than returning stale data.
3. **A subcommand-existence test built on exit codes.** `openclaw notarealnoun
   --help` exits 0, so a "yes" for `skills` meant nothing. The control failed and
   the runner voided everything it underwrote. The help text is a separate
   instrument and is where the real answer came from.
4. **Three dead ends in resolving an install target**, each non-obvious: the bare
   slug `git` is published by two owners and 409s as `AMBIGUOUS_SKILL_SLUG`; the
   fully qualified ref the hub returns in that 409 is rejected **locally** as
   "Invalid skill slug" before a socket opens; and `openclaw skills info` reads only
   locally installed skills, answering "not found" for a slug `search` had just
   returned.
5. **A here-string escaped C-style.** Inside `@"..."@` a literal dollar needs a
   backtick, not a backslash. Every `\$` emitted a stray backslash and interpolated
   an undefined variable to empty; the loop reached bash as
   `su: user  rc=" does n  swept "; done`. Rewritten with a non-interpolating
   here-string and placeholder substitution, which removes the class rather than the
   instance, plus an escaping audit calibrated against planted canaries (3 of 3
   found, 0 false positives, 0 remaining).
6. **A decision rule too narrow for its own evidence.** The #261 separator asked
   whether the *next* resolved address was in the set. It was, so it rendered
   "cannot separate" over a transcript that separated the hypotheses perfectly well:
   the gap is a property of the union of addresses, not one draw. The runner
   recorded VOID and named the reason rather than picking the plausible answer,
   which is the behaviour to keep.
7. **A card printed where the operator did not see it.** The runner-start card sat
   above status tables and read as progress reporting; the run idled about an hour.
   Convention updated: operator instructions go last in the message, always.
8. **A wrong description of runner success.** The card said the runner prints a
   polling line every 15 seconds. It prints nothing unless a job arrives and writes
   a heartbeat file every 5 seconds, so a blank window is correct.

---

## 8. Confirmation of scope

- **Nothing was widened.** No allowlist, no host list, no set membership, no panel
  copy, no `$baseHosts`. The two phases that toggle anything set it explicitly and
  restore the shipped default, verified by `SK.7` and `GR.4` with
  `clawfactory-fw-assert.sh` returning 0.
- **No shipped file changed.** `git status --short` was clean of shipped paths at
  every commit. The only files added are under `validation/` and
  `docs/session_reports/`.
- **No rebuild, no signing, no tag**, as the job requires.
- **Resource ledger:** the group held `cfv-169` plus its own five resources and the
  expected residual only (storage account, VNET, two baseline images). No prior FAIL
  VMs needed sweeping. Proven with an unfiltered `az resource list`.

**Commits this session:**

| Commit | What |
| --- | --- |
| `43719de` | task 1 discovery phase |
| `6a1ce8d` | task 1 measurement phase, and the answer |
| `cbe7b57` | task 2 GitHub re-probe, separating #261 from a regression |
| this file | close-out |

---

## 9. Carry forward

- **The Trusted Signing certificate expired 2026-08-20 and blocks the next build.**
  Waiting on it: the `15h` step-label rename, the #261 fix, and matrix test 3.
- **Matrix test 3** needs a second clean box with `-Provider later`. Pair it with
  that build rather than provisioning a box for it alone.
- **The cfv-167 turn failures remain unexplained.** A watch item, not a chase. This
  session did nothing to advance or contradict them, and the provider gate still
  does not cover that symptom: those turns failed while a TCP connect would have
  succeeded.
- **Two decisions are the operator's**, both from section 2: whether to narrow the
  panel claim, and whether to drop `openclaw.ai` from `$baseHosts` (which would
  darken the product's own site for the agent).
- **Card #261 should be widened** to record that the pool gap affects
  `api.clawhub.ai`, not only GitHub.

## 10. VM state

`cfv-169` deallocated at close. Not deleted: it carries the installed 1.3.5 artifact
and the full evidence set, and matrix test 3 plus any #261 follow-up will want a box
of exactly this shape.
