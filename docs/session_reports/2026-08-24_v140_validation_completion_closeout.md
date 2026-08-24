# CLOSE-OUT: v1.4.0 release validation, completion run, card #266

Session 2026-08-24, on cfv-174. Resume of the incomplete run recorded in
`2026-08-23_v140_release_validation_closeout.md`. No rebuild, no re-sign, no version bump,
no tag, no publish.

**STATUS: COVERAGE COMPLETE. The artifact is NOT fit to publish, and this time the reason is
a finding rather than a gap.**

Every row the previous session left open is now closed or recorded VOID with a named reason.
Matrix row 11 passed in full for the first time on this build. Row 10 ran for the first time
across six cards. And the run surfaced three product defects that were not previously
recorded, one of which is a false claim about a safety control in a release whose entire
purpose was to make the claims honest.

The whole validation estate is torn down. Nothing is billing.

---

## 1. The artifact, verified twice before anything was installed

| | |
| --- | --- |
| signed sha256 | `257f30ff6284a3645144b70822a9c55c342d4f90df179e00705dae3c52e6c390` |
| signed bytes | 440,613,512 |
| ledger (unsigned) | `67c3b21a7e9abc2be8475aa32a6abe58729772ff0c893c7480ea7db6397201ef` |
| Authenticode | Valid, `CN=Bret Mckinney` |

Checked on the build machine before provisioning, and re-derived ON THE BOX after transfer:
`OK staged; artifact=257f30ff... size=440613512`. Same binary the previous session built.
Nothing in this session touched the build.

---

## 2. Task 0: the checklist audit, and the check that was still absence-only

Check 1 was converted to a presence check last session. I verified its quoted paragraph
character for character against `frontend/src/pages/web/WebAccessPage.tsx` in the shipped
Studio source. It matches. **Here it is as it now reads, with the positive control visible:**

> **Now compare the paragraph beside it against this, word for word:**
>
> > Your agent can reach the skill hub, GitHub and npm. Switching this off stops your agent
> > fetching code from GitHub and npm. It does not stop skill installation: the skill hub
> > shares a network address with ClawFactory's own site, which stays reachable and which
> > this switch does not cover. It does not affect the AI provider your agent talks to.
>
> - [ ] 1d. Matches, word for word.
>
> **THIS IS A PRESENCE CHECK, NOT AN ABSENCE CHECK, AND THE DIFFERENCE IS THE POINT.** An
> earlier draft of this check only asked you to confirm the old claim was GONE. A panel with
> no breakage text at all, or a half-edited sentence, would have sailed through it.

The positive control is the transcription itself: the operator must find that exact
paragraph present, so an empty card, a truncated sentence or a half-edited one all fail. The
absence of the old claim survives as one of three named failure modes rather than as the
only assertion.

### The sweep found a second one, and it was the worse of the two

**Check 6 was absence-only.** It asked the operator to confirm the home page does NOT say
"Studio backend unreachable". A page that failed to render, rendered blank, or never loaded
satisfies that perfectly, and a renderer that silently drew nothing is precisely the failure
the entire by-hand exercise exists to catch.

It now carries four positive assertions first, taken from the shipped source: the heading,
the `ClawFactory Studio v1.3.1` status pill with `Running as a desktop app`, and the opening
words of two paragraphs. The absence is still asserted, after them, and the file states that
it means nothing until they pass.

**Audit of all seven, one assertion at a time:**

| Check | Shape | Action |
| --- | --- | --- |
| 1 | was absence-only, converted last session | verified against shipped source, unchanged |
| 2 | presence, word for word | unchanged |
| 3 | presence | expected strings quoted literally; named as the control for 4 and 5 |
| 4 | presence of a refusal | its positive control (check 3) now stated rather than implied |
| 5 | mixed | expected strings quoted; the surviving seeded entry made an assertion |
| 6 | **bullet was absence-only** | four positive assertions added ahead of it |
| 7 | presence both sides, plus a named wrong version | unchanged |

### A third defect in the same file, and this one the operator had already reported

Check 6 told the operator to click the lobster to reach the home route. **The lobster is not
a link.** In `App.tsx` it is a bare `<span>` beside a plain `<h1>`, and the nav has no Home
entry, so once you leave the home route there is no click path back.

He had reported this before. It is in
`docs/session_reports/2026-08-22_v135_matrix_completion_closeout.md`, section 6, item 5, with
the remedy spelled out: *"the check doc should say to use the nav or a restart instead."* It
was never carded, so nothing tracked it. Two days later this session rewrote that exact file
as its first task and left the instruction in place, because the audit was scoped to
absence-only assertions and never checked the file against the known-defects list in the
prior close-out. He hit it again with his own hands, mid-check, and had to tell me he had
already raised it.

That is the process lesson worth keeping: **a finding recorded only in a close-out will be
rediscovered by a human doing it the hard way.** Everything found this session is carded.

---

## 3. What was staged, and how, so the next session does not ask the operator to retype it

The previous session handed over a box on which Studio was not configured. Almost none of it
needed a person. `validation/interim-v140-stagebox.ps1` now does it from root, and every
value is READ BACK after writing so the handover card quotes measurements rather than
intentions.

| Panel value | Root tool that sets it | Measured result |
| --- | --- | --- |
| SMTP credential AND the authorised send destination | `clawfactory-sendctl credential-set`, JSON on STDIN | `configured 127.0.0.1:2525 as clawfactory-validation`, destination authorised in the SAME operation |
| Credential file mode | (side effect of the above) | `mode=600 owner=root:root`, measured |
| Read-fetch allowlist | `clawfactory-fetchctl add` | `www.iana.org` |
| Toolchain switch | `clawfactory-fetchctl toolchain on` | `ON`, 28 live addresses |
| Live pending approval card, with attachment hash | `clawfactory-send` as `clawuser` | `MANUAL-HASH-CHECK`, sha256 `f8e9046c...16f93`, verified against the source bytes |
| Expired approval card | queue then force `expiresAt` into the past | 21 expired cards visible |
| Studio identity | Windows-side hash | `app.asar` = `5c4ffbf4...e2d85`, equal to the build pin |

`credential-set` writes the credential and calls `setSendDestination` in one operation, so a
single call sets both of the first two bullets of the brief. That is worth knowing: the
credential and the policy cannot drift apart by construction.

**One value could only be set through the UI, and it is the one that matters:** the REAL
SMTP app password. That is deliberate and correct, not a gap. The password is typed by the
operator into `Approvals -> Email settings` and never enters a script, a transcript or this
context. Everything else the panels display is root-writable.

**Timed subjects are staged immediately before the ping**, in a separate script, and the
remaining window is printed in minutes for the card to quote. `interim-v140-stagecards.ps1`
must also run AFTER phase 4, because `S.5` exercises the kill switch and kill cancels every
live request: a card staged earlier would be destroyed by the test rather than by its timer.

**A premise in the brief was stale and is corrected here.** Section 4.2 asks for a live
approval, an expired request and a staged attachment hash so that "checks about the approve
and deny controls" and "the expired-card checks" have subjects. **Matrix row 11's seven
checks contain no such checks.** They are Web access, home route and footer only. The
approve/deny/expired/hash-reveal checks belong to `interim-v120-panels.ps1`, a different
hand-driven smoke that was run at cfv-160. The subjects were staged anyway, offered to the
operator as a clearly-labelled extra, and nothing in row 11 depended on them.

**The throwaway validation account is `clawfactory.validation.0805@gmail.com`.** Recorded
here at the operator's request so the next session stops asking. The address is recorded;
the app password is not and never should be. The panel is at `Approvals -> Email settings`
(`/approvals/smtp`), NOT under Settings. Send-from and Username are both the full address.

---

## 4. Which rows a sink cleared, and which genuinely needed a real credential

The previous close-out's own correction was that only `S.4leak` and phase 3b need a real
credential. **That was close but not right, and the difference was found by measurement.**

**Cleared by the sink credential alone, no operator involved:**

`S.4`, `S.5`, `S.5c`, `G2.0`, `G2.1`, `G2.2`, `G2.2c`, `G2.4`, `G2.5`, `G2.5b`, `G2.7`,
`G2.10`, `G2.10c`, `G2.11`, `G2.12`.

**Needed the real credential, and got it:**

| Row | Result |
| --- | --- |
| `S.4leak.POSTREBOOT` | **PASS**, scanned against the real secret, zero hits on every surface |
| `S.4ctl.POSTREBOOT` | **PASS**, the scanner finds the secret where it legitimately lives, so zero is not blindness |

**Recorded VOID with the reason named:**

| Row | VOID reason |
| --- | --- |
| `G2.13` | measured against the sink before the real credential was saved. Not re-run: with a real Gmail credential configured, phase 3's lifecycle tests would attempt genuine outbound sends, and the operator authorised saving a credential, not sending. `S.4leak` is the same claim by the same method over an overlapping surface set and it PASSED |
| `G2.198` | external delivery to a third-party mailbox. Needs one outbound send, which was offered explicitly and not requested |
| `G2.3` | see section 5 |
| `G2.6` | see section 5, and then see why it no longer matters |

**A row this session refused to let the sink fake.** `S.4leak` and `G2.13` scan the box for
the credential's literal value. With a synthetic sink credential configured, both would have
found zero hits and reported PASS: a synthetic test wearing a real verdict. Both probes now
detect a loopback credential and record VOID with that reason, which is what they already
did when no credential existed at all.

---

## 5. Guard 2's delivery path, which has never been measured on any build

Three separate things went wrong here, and only the third is the product.

**First, the parser.** Phase 3 came back with `G2.3` VOID and `G2.4`, `G2.5`, `G2.6` FAIL.
None of them was Guard 2. `clawfactory-send` prints plain `key=value` lines, not JSON:

```
status=pending
requestId=2026-08-24T16-52-10-769Z-35b86e7b
payloadHash=a6f0...
```

The `requestId` read survived because it had a `key=value` fallback. The `payloadHash` read
did not, so it returned `$null` on every run this suite has ever had, and test 3 took its
missing-precondition branch reporting *"no requestId from test 1"* -- naming the value that
WAS there rather than the one that was not, which is why nobody chased it. The same
JSON-only assumption sat in the lifecycle probe's `idof()`, so tests 4, 5 and 6 ran their
deny, replay and swap commands with an EMPTY request id and were scored on the errors.

Fixed, calibrated against the real output, the JSON the admin socket returns, and text
containing neither (which must yield nothing). Only the extraction changed; every assertion
is byte-for-byte as it was. On the re-run `G2.4`, `G2.5`, `G2.5b`, `G2.7` and `G2.3b` all
flipped to PASS. **This is why the oldest phase 3 evidence on the build machine records
`G2.3` as `UNTESTED`, a verdict word the current phase runner does not permit.**

**Second, the transport.** With the parser fixed, `G2.3` produced a real answer:

```
{"ok":false,"code":"ESMTP",
 "error":"127.0.0.1:2525 does not offer STARTTLS; refusing to submit in cleartext"}
```

and the receipt recorded it honestly: `"sent": false, "outcome": "smtp_error"`, with the
approval stamped `approved`, its `boundHash` bound, and staging purged.

`send-smtp.js` refuses cleartext submission on any port but 465. Phase 3's sink speaks plain
SMTP. **The product is right and the test rig has never been able to accept a message from
it.** That refusal is itself a security property behaving correctly and is recorded as
`ST.1` PASS.

I tried to give it a sink it would accept. `interim-v140-sinktls.ps1` built a throwaway CA
and a STARTTLS sink and asked node by execution:

```
NODE_TLS_VERDICT=REJECTED unable to verify the first certificate;
if the root CA is installed locally, try running Node.js with --use-system-ca
```

This node build reads its own bundled store, so no locally-issued certificate can ever
satisfy the broker. And a real provider would accept the submission but its copy cannot be
read back. **So the transport-based version of this test is unrunnable in both directions**,
and `ST.2`, `ST.3`, `ST.6` are VOID with that reason rather than as Guard 2 failures.

**Third, and this is the part that matters: the property does not need a transport.**

`clawfactory-sendd.js` reads `a.stagedPath` both in `recomputeHash` at approve time and when
it builds the message. The source path is recorded and never read again. So
`interim-v140-swapstruct.ps1` measures it on the filesystem, and it is a **PASS with every
control firing**:

| Row | Verdict | Evidence |
| --- | --- | --- |
| `SS.1` | PASS | staging is `mode=700 root:root`; the agent's write into it does not land, with a control proving the agent can write elsewhere |
| `SS.2` | PASS | after the agent rewrites its own source post-enqueue, the staged copy still reads `A-bytes APPROVED` |
| `SS.2b` | PASS | A and B really do hash differently, so the comparison discriminates |
| `SS.3` | PASS | **the control**: mutating the STAGED copy as root is caught, `{"ok":false,"code":"EHASH","error":"the payload changed after it was previewed; approval voided"}` |

`SS.3` is the whole test. "The hash still matched" is what a check that never fires also
reports, so the probe injects the fault it is looking for and requires the refusal.

**The substance of `G2.6` -- the single most important assertion in the Guard 2 job -- is
proven for the first time in this project's history.** The transport-based row stays VOID
because it is honestly unmeasurable; the claim it exists to defend is measured and holds.

---

## 6. The matrix, every row at its true state

| # | Test | State | Where |
| --- | --- | --- | --- |
| 1 | Clean install, all resources, all pins, five-page wizard | **PASS** | cfv-174 phase 1, 15 PASS / 4 INFO of 19 |
| 2 | Install completes with `api.clawfactory.app` unreachable | **PASS** | cfv-173, previous session, 7/7 |
| 3 | Provider gate healthy plus blocked CONTROL | **PASS** | cfv-170, previous session |
| 4 | Provider gate skipped with a stated reason under `-Provider later` | **PASS** | cfv-171, previous session |
| 5 | `SP.*` no toolchain address enters after a switch | **PASS** | cfv-170, previous session |
| 6 | `SP.*` toggle OFF, GitHub and npm unreachable after a switch | **PASS** | cfv-170, previous session |
| 7 | CONTROL for 6: toggle ON, reachable | **PASS** | cfv-170, previous session |
| 8 | `TC.3` real agent turn with the toggle OFF | **PASS** | cfv-174 post-reboot, `TC.3.POSTREBOOT` |
| 9 | `TC.1,2,4,5,6,7,8` regression | **PASS except `TC.1c`** | cfv-174, 29 PASS / 1 FAIL of 30, 7/7 controls fired |
| 10 | **Reboot pass** | **RUN. Not clean: one product FAIL** | see below |
| 11 | **The seven MANUAL panel checks by hand** | **PASS, all seven** | cfv-174, by the operator |
| 12 | Harness self-test | **PASS** | staged on the box; build machine unchanged |
| 13 | Zero malformed verdict rows | **PASS** | every phase counted N of N across nine phases |
| 14 | Step 7, full assembled-build validation | **PASS on the mechanism, VOID on delivery** | sections 5 and 7 |

### Row 10, which had never run across cards #245, #257, #258, #265 and #266

**It ran. It is not blank and it is not deferred.** Two legs:

```
phase 4 -PostReboot          PhaseVerdict=PASS, 8 of 8
  S.1.POSTREBOOT      PASS   No route to SMTP for uid 1000 at any destination
  S.1ctlA/B/C         PASS   all three controls fired
  S.4.POSTREBOOT      PASS   mode=600 owner=root:root, measured
  S.4leak.POSTREBOOT  PASS   scanned against the real secret
  S.4ctl.POSTREBOOT   PASS   scanner is not blind

toolchain -PostReboot        PASS=29 FAIL=1 VOID=0, controls 7/7, preconditions 1/1
  TC.1c.POSTREBOOT    FAIL   With the switch ON, the software sources are reachable
```

**The egress block survives a full Windows reboot.** That is the security direction and it
holds. `TC.1c` is the functional direction and it does not. It is a real product defect,
diagnosed in section 7.

### Row 11, closed

All seven passed, observed in the operator's own screenshots rather than paraphrased:

| Check | Result | Quoted from what he saw |
| --- | --- | --- |
| 1 | PASS | card present, `Switch off` button, paragraph matches word for word including "It does not stop skill installation" |
| 2 | PASS | footnote matches, carrying "allowing a site also allows anything else served from the same address" |
| 3 | PASS | `Your agent can now read docs.python.org.` |
| 4 | PASS | `Enter the site name only, with no https:// in front, no port and no page path. For example: docs.python.org` for the scheme and for the port; `Wildcards are not accepted. Name each site you want to allow.` for the wildcard |
| 5 | PASS | `docs.python.org is no longer reachable.` |
| 6 | PASS | heading, `ClawFactory Studio v1.3.1` pill with `Running as a desktop app`, both paragraphs, no "Studio backend unreachable", `v1.3.1` separated from `Templates` |
| 7 | PASS | `Frontier Automation Systems LLC . Apache-2.0` left; `Wraps OpenClaw 2026.4+ . the sandbox runs on your machine; your agent talks to a hosted AI model` right |

**One thing he reported that did not match, quoted as he reported it.** The card told him to
expect `On. 28 network addresses reachable`. His panel read **`On. 25 network addresses
reachable.`** That is my defect, not the product's: the count comes from re-resolved DNS and
drifts between refreshes, so it was never a fixed value to quote. The check should have said
"a nonzero count". Not a check failure.

Corroborated independently: the installed `app.asar` hashes to `5c4ffbf4...e2d85`, equal to
the build pin, so "1.3.1" is not merely a string the bundle renders.

### Phase 5, now that the bridge was live

```
PhaseVerdict = VOID (incomplete). Nothing FAILED.
G2.8f    PASS  Test 8 sixth channel: the agent cannot reach approve through the Studio IPC bridge
G2.8f.1  PASS  processes=4 names=ClawFactory Studio
G2.8f.2  PASS  studioOwnedListeners=0
G2.8f.5  PASS  PAIRED CONTROL: Windows-side engine call reaches the send broker
G2.8f.3ctl VOID CONTROL: is the WSL-to-Windows network path open at all?
```

13 PASS, 1 VOID, and **the headline passed**. The VOID is the phase's own honesty rule firing
exactly as its header describes: without that control it cannot tell "nothing is listening"
from "the firewall dropped it", so it refuses to pick the flattering explanation. The
headline is carried by `G2.8f.2` and `G2.8f.4a/4b`, which do not depend on it.

---

## 7. Product findings

### F1. The Web access toggle still claims it stops skill installation. CARD #274

`WebAccessPage.tsx` `onToggleToolchain` sets a banner reading, on OFF:

> `Skill installation is now off, and your agent can no longer fetch code from GitHub or npm.
> Its AI provider is unaffected.`

Three lines above, the same panel says **"It does not stop skill installation"**. Both are on
screen simultaneously. cfv-169 measured the banner's version FALSE by completing a real
`openclaw skills install` with the switch off, because `clawhub.ai` shares an address with
the permanently-allowed `openclaw.ai`.

Found by a calibrated scan of the shipped `app.asar` (positive and negative controls both
behaved), which enumerated exactly two `skill install` sites in the bundle: the corrected
paragraph and this uncorrected pair of notices. **Then observed live** by the operator on
cfv-174 when he toggled the switch during the panel checks.

The v1.4.0 claim audit corrected the paragraph and the site and missed the transient
notices, because the search was shaped like the old sentence rather than like the claim.
That is the canary lesson from PROMPT 15, landing again.

The same claim also survives in two non-GUI places in the shipped installer:
`resources/install-read-fetch.sh` line 243, which writes *"Switching it off in Studio stops
skill installation, GitHub and npm"* into the install log the user can read, and the
`toolchain._note` in `resources/egress-policy.json`.

### F2. The toolchain route is dead after a reboot while the panel says it is on. CARD #276

Measured, with the run's own control:

```
after reboot:   TC.1a PASS enabled=true; TC.1b PASS 28 live, 28 persisted;
                TC.1.CTL PASS provider reachable and un-allowlisted refused, same run;
                TC.1c FAIL github and npm reachable=False
later, same run: TC.5 PASS set repopulated to 28; github and npm reachable again=True
```

Root cause from source. `clawfactory-toolchain.sh` section 4 persists resolved addresses
with the comment *"Persist, so the boot path rebuilds the same set ... fw-apply.sh reads it
at boot"*. The boot path REPLAYS that file verbatim and does not re-resolve; only the
resolver re-resolves, on the five-hourly refresh or on a toggle. GitHub and npm sit behind
rotating pools, which the script already knows: `RESOLVE_PASSES` exists because *"a single
lookup misses half of a rotating pool, and the host is then intermittently unreachable while
the switch reads ON."*

**Security direction is fine.** A stale set is narrower than intended, never wider, and the
deny held across the reboot.

**Two real costs.** Functionally, after every reboot, skill installs, npm and GitHub fail for
up to five hours with an unexplained network timeout deep inside WSL, which is exactly the
support-problem failure mode the panel copy was written to prevent. And in honesty terms,
the panel displays a live address count while the route is dead, when the Studio home page
promises each panel *"shows you what is actually in force rather than what was intended"*.

**The scope is wider than the toolchain.** `clawfactory-read-fetch.sh` carries the identical
comment and the identical replay, and resolves each host ONCE with no multi-pass loop. So a
site the user explicitly allowed in the Web access panel can be unreachable after a reboot
while the panel still lists it. That is Guard 3's headline feature failing quietly on the
user's own choice. **Not separately measured on cfv-174**: the seeded `www.iana.org` was not
probed for reachability after the reboot, and `TC.7a` only proves an add DURING a run works.
Recorded as a comment on card #276.

### F3. Templates and Settings are dead ends naming a retired backend. CARD #275

The operator hit this trying to reach the SMTP panel. Settings renders:

> `Couldn't load settings. This panel is not wired in the desktop shell scaffold yet. Studio
> is being rebuilt as a native app; the Workspace (grants) panel is fully functional.
> (GET /api/settings)`

There is no HTTP backend in the packaged app; it was retired, which is why the identical
"Studio backend unreachable" banner was REMOVED from the home route rather than reworded.
These two were missed by that sweep. **Templates is the first nav item** and Settings is
among the likeliest early clicks, so a new customer's first impression can be an error
naming an internal scaffold and a dead API. Templates was already recorded in the v1.3.5
close-out, section 6 item 4, and never carded.

### F4. No way back to the home route. CARD #273

Covered in section 2. Reported by the operator in a previous session, recorded, never
carded, and hit again by hand.

### `SP.8` stays failing, and it is not a regression

`SP.8` asserts that with the toolchain toggle OFF the skill hub is unreachable. It FAILs,
because `clawhub.ai` shares an address with the permanently-allowed `openclaw.ai`. That is
the address-scoping residual already documented in `SECURITY_FINDINGS.md`.

**It is recorded here as a known-stale check against a documented residual, and it is NOT a
regression.** It is not retired in this session: retiring a check in the same session that
produces a publish decision is the wrong order. Carded.

**One correction to the previous close-out's reading, and it argues for keeping the check.**
That close-out concluded `SP.8`'s premise was stale because "this release removed the claim
the check tests". Only half of it was removed. The paragraph was corrected; the toggle
notices still assert it (finding F1). So against the paragraph the premise is stale, and
against the notice `SP.8`'s FAIL is a correct and current finding. It should not be retired
until F1 is fixed.

---

## 8. Instrument defects found this session, and how each was caught

Seven. Every one was caught by a number that did not fit being checked against raw evidence
rather than explained, or by reading a probe before running it.

1. **`S.4` printed `0600 root:root` as a hardcoded literal**, not a measurement, beside a
   verdict derived from a different signal entirely. Caught by reading. Now emits a
   parseable `CREDSTAT` line and quotes what it measured. Calibrated against four rigged
   inputs: mode 644 now produces FAIL with `mode=644` in the evidence, which the literal
   could never do.
2. **`S.4` treated a missing credential file as a product failure.** With no file the agent's
   read fails ENOENT not EACCES, so the boundary was never exercised. Now VOID.
3. **A sink credential would have turned `S.4leak` and `G2.13` into synthetic passes.**
   Caught by reasoning about what the sink would do before configuring it. Both now detect
   the loopback host and VOID.
4. **Phase 3 read the CLI as JSON**, so the approve path has never run in any run of this
   suite. Caught because three FAILs and a VOID all pointed at the same missing value, and
   the transcript printed `payloadHash=` empty. Section 5.
5. **`G2.198`'s VOID reason was self-contradictory** the moment a sink credential existed:
   "no real SMTP credential configured (credentialPresent=True)". Now names which case holds.
6. **My own `stagecards` asar check asked through `/mnt/c`** and returned nothing, which
   looked exactly like "Studio is not installed". PROMPT 15 says plainly that `/mnt/c` is an
   empty stub because automount is off by design. Caught by a Windows-side diagnostic that
   found Studio immediately at the pinned digest. The same script also carried the JSON-only
   request-id parser I had fixed in phase 3 minutes earlier and failed to fix in my own new
   file.
7. **The job dispatcher retrieved the PRE run's results and reported them as the post-reboot
   run's.** `phase4` and `phase6` write `<probe>-results-postreboot.json` under `-PostReboot`;
   the dispatcher only ever asked for `<probe>-results.json`, so it restated a stale verdict
   table with no error anywhere. Caught because the row IDs read `.PRE` for a job whose own
   transcript said `pass=POSTREBOOT`, and because tests that `-PostReboot` skips appeared as
   having run. **Stale evidence presented as current is worse than missing evidence, because
   nothing about it looks wrong.** Fixed, and the fix proved itself on its first use
   (`results file: phase4-results-postreboot.json`). A third naming pattern
   (`toolchain-results-POSTREBOOT.json`, uppercase) was then found by reading the phase
   before running it rather than by watching a retrieval come back empty.

---

## 9. Deviations and things deliberately not done

**No `az vm user update` was called by me at any point.** `validation/interim-v140-relgate-box.ps1`
provisions and stages without knowing the admin credential, because it arms nothing. It
asserts `AutoAdminLogon` is unset rather than setting it, and the read-back confirmed it
empty. The cost was paid as planned: two operator logins, one to start the install and one
after the reboot. No credential of his was overwritten and none stopped working.

**The v1.2.0 driver's credential dependency was NOT fixed.** It remains carded. Changing the
harness that produces the results this job is about to trust is the wrong order.

**Phase 3 was not re-run after the real credential was saved**, because its lifecycle tests
would have attempted genuine outbound sends. The operator authorised saving a credential.
The single outbound send needed for `G2.3` and `#198` was offered explicitly, in writing,
with its exact scope (one message, from the throwaway account to itself), and was not
requested. Both rows are VOID.

**Not done, and out of scope by instruction:** no tag, no publish, no GitHub release, no
rebuild, no re-sign, no version bump, no Guard 4, no card #197, no FrontierAI work, no fix
to `TC.1a/b/c`, `G1.7` or `G1.7c`. The Inno Setup position is unchanged and is the
operator's call.

---

## 10. Fitness to publish

**NO. This artifact is not fit to publish as the v1.4.0 public free release.**

Unlike the previous close-out, the reason is no longer missing coverage. Coverage is
complete. The reason is two findings.

**What is proven and would survive an audit:**

- The build: seven gates, signed, ledger recorded, digest re-verified on the box.
- No outbound licence call, from two independent directions, with controls firing.
- Matrix rows 1 to 9 and 12 to 14, plus row 11 in full and row 10 for the first time.
- Guard 2's structural invariant: no route to SMTP for uid 1000, before and after a reboot,
  with all controls firing.
- Guard 2's approve path: single-use, hash-bound, deny and expiry refusals, the agent unable
  to approve through six channels including the Studio IPC bridge.
- **`G2.6`, the most important Guard 2 claim, proven for the first time**, structurally, with
  the tamper-detection control firing.
- The credential is unreadable by the agent and its value leaks to no surface, scanned
  against the real secret with a control proving the scanner is not blind.
- The shipped copy in the installed `app.asar`, 20 of 20 present and 9 of 9 absent, plus all
  seven by-hand panel checks.

**What stands in the way, in the order it should be cleared:**

1. **Card #274. The product tells the user a safety control does something it does not do.**
   The toggle notice says skill installation is off; it is not, and that was measured false
   ten days ago. This is an overclaim in the flattering direction, on the primary
   user-facing safety switch, in the release whose stated purpose was to remove exactly that
   class of claim from the site and the product. Shipping it would repeat, inside the
   product, the thing the site pass was done to fix.

2. **Card #276. A control reports a state that is not in force.** After every reboot the
   panel shows a live address count while the route is dead, for up to five hours, and the
   same defect applies to the user's own allowlist. The security direction is safe, so this
   is not a hole; it is a false statement plus a functional regression with a support cost.

**Cost to close.** #274 is a two-string edit in `WebAccessPage.tsx` plus the same claim in
two Secure-Setup files. #276 is a boot-path change so the resolver runs instead of replaying,
covering both `toolchain-ips.txt` and `read-fetch-ips.txt`. Both then need: a Studio rebuild
and re-sign, the three-part repin, an installer rebuild and re-sign, a version bump to
v1.4.1, and a validation box. **Roughly one build session and one validation session**, and
the validation is now materially cheaper than it was, because the box configures itself from
root and the panel checklist is executable.

**A defensible alternative, which is the operator's call and not mine.** #276 self-heals and
is security-safe, so it could ship documented as a known issue. **#274 cannot**, because it
is a false claim about what a safety control does. If only #274 were fixed, the honest
answer changes to yes-with-a-documented-residual.

**What it IS fit for today:** an internal or validation build. Nothing found in two sessions
argues against the installer, the guards, or the binary. The installer is green, the guards
hold, and the security claims that were tested all held. The problems are in what the
product SAYS about itself, which is the one thing this release was supposed to have fixed.

---

## 11. Resource ledger

| Resource | State |
| --- | --- |
| cfv-174 | **TORN DOWN.** vm, nic, pip, nsg, disk, each by explicit name, every call exit 0 |
| RDP rule | one rule, `67.164.251.99/32`, port 3389, created by read-back and confirmed still present after the reboot. No wider rule |
| Throwaway CA | installed for one test and REMOVED, removal verified: `CA_STILL_PRESENT=no`, `SINK_STILL_RUNNING=no`. The box did not enter the reboot pass trusting a test CA |
| Starting estate | verified clean before provisioning: storage account, VNET, two baseline images, zero VMs |

**FINAL STATE, unfiltered, after teardown:**

```
clawfactoryvalc467              Microsoft.Storage/storageAccounts
bake-vmVNET                     Microsoft.Network/virtualNetworks
clawfactory-win11-baseline      Microsoft.Compute/images
clawfactory-win11-baseline-v2   Microsoft.Compute/images
```

VMs across the ENTIRE subscription: none. **Nothing is billing.**

---

## 12. Cards

| Card | State |
| --- | --- |
| #266 | this job. Moved `blocked` to `in_progress` at session start, `done` with this close-out |
| #273 | NEW. Studio home route unreachable once you navigate away |
| #274 | NEW, priority 1. Web access toggle notices still claim the switch stops skill installation. **Publish blocker** |
| #275 | NEW, priority 1. Templates and Settings are dead ends naming a retired backend |
| #276 | NEW, priority 1. Toolchain and read-fetch routes dead after a reboot while the panel says otherwise. **Publish blocker** |
