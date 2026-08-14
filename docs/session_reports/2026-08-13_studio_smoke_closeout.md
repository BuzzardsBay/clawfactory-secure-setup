# Studio panel smoke test. Close-out, 2026-08-13.

Dispatch card #243. Track: v1 fast-security-harness. Half-session validation.

Input to the session: `0fd3ce6` (the wiring scope), card #242 done, and the interim
validation's artifact `d429e12e...`. That artifact is **not** what was smoked; see section 2.

---

## 1. Why this session existed, and what the scope session got right

The scope session established that all three Studio guard panels are wired end to end,
in source and inside the packaged `app.asar`: page to bridge to IPC to engine to the
seven PowerShell functions to the root ctl, with matching reply shapes throughout.
Nothing was missing.

It also established that D4, the interim validation's finding that Studio ships as a
scaffold, was wrong on all three of its observations. That finding had shaped three
sessions and an estimate of three to three and a half sessions of wiring work.

Nobody had clicked the panels. This session did.

---

## 2. Task 1. The parse defect, and the rebuild

### 2.1 The defect

`send-engine.ts:104` builds a two-statement PowerShell expression. `grants-engine.ts:113`
wrapped it in `( )`, the grouping operator, which takes exactly one pipeline.

This was not an edge case. Every caller of `invokeEngineWithInput` is at least two
statements **by construction**, because the whole contract of that function is to read a
secret from stdin and then act on it. So the only function it exists to serve could never
work. Guard 2 has exactly one credential intake path, and this was it: no SMTP account
could be configured from the shipped UI at all.

It failed at PARSE time, before the engine was ever dot-sourced, and the renderer
reported that the send service did not respond. That is why it survived: the symptom
names the broker, and the broker was fine.

### 2.2 The fix, proven three ways with a control in each

`$( )`, the subexpression operator, takes any number of statements.

| Proof | Subject | Control that must fail |
| --- | --- | --- |
| Parse | the generated script, `$( )` form: **0 parse errors** | same script, `( )` form: **5 parse errors**, same parser, same process |
| Shape | run against a stub engine over real stdin: single JSON object, `host` and `port` cross intact | the reply must not start with `[` (a leaked statement would make it an array), and must not contain the password, which was verified present in the input first |
| Payload | `-InputObject $(` **present** in the new signed `app.asar` | **absent** from the previously pinned `b701bfb7`, while `-InputObject (` is present in **both**, because `invokeEngine` legitimately uses grouping and was not touched |

Panel markers: all twelve present in both builds, so the fix dropped nothing. Positive
control `Workspace` in both, negative sentinel in neither.

The parse harness itself had a bug on first run: `Check` used `Write-Output` and `return`,
so the caller captured the report text along with the error count and the verdict logic
read garbage. Fixed by reporting on the host stream. Recorded because it is the same class
as the sixteen harness bugs the interim session found: it produced output that looked like
a real result.

### 2.3 One thing fixed beyond the parse defect, and why

`sign_installer.ps1` gained a build-stamp gate on 2026-08-05, after the last Studio build.
It refuses any binary that `build_release.ps1` did not stamp, so the ClawFactory installer
cannot be compiled with `ISCC.exe` and signed anyway.

Studio's four binaries can **never** carry that stamp. They come from electron-builder, and
`build_release.ps1` consumes the finished Studio installer as an input, so it cannot have
produced the files being signed. The gate therefore enforced nothing on Studio; it simply
made a signed Studio build impossible, and the fallback is an **unsigned payload shipped to
customers**, which is strictly worse.

The sign hook now passes `-SignWithoutBuildStamp` with the reasoning written into it. No
ClawFactory gate is weakened. Studio provenance is enforced where it actually lives, in
`build_release.ps1`'s `$studioPinned` digest, which refuses to embed a Studio installer whose
bytes were not deliberately validated and repinned by hand.

This is scope creep of a specific and narrow kind: without it, Task 1 could not be completed
at all. It is recorded rather than absorbed.

### 2.4 Artifacts

| | Value |
| --- | --- |
| Studio installer | sha256 `62402ff65b5623414faae2e804d98c9c658aab5468090b9f226a3e1998f891d9` |
| Studio bytes | 100,028,736 |
| Studio commit | `8b4e238` |
| ClawFactory installer | sha256 `29acdf95c6c12d4ef6e6b248527ae74b77c0bd46aca10db9a8c66c661bea2ae1` |
| ClawFactory bytes | 440,583,848 |
| Gates | all seven passed: soul, bundle, studio, version, persona, workspace-soul, rootfs |
| Authenticode | `Valid`, `CN=Bret Mckinney`, timestamped, both artifacts |

`$studioPinned` moved from `b701bfb7...` to `62402ff6...`, and
`validation/interim-v120-validate.ps1` was repinned from `d429e12e...` to `29acdf95...`.

**Left deliberately, and recorded rather than fixed:** `ClawFactory-Studio-Setup-1.1.0.exe`
is now a filename carrying a **third** distinct set of bytes. The digest is the authority
and the gate keys on it, so this is a confusion hazard rather than a security one, but the
filename should be versioned. The scope session recommended bumping it in this pass; that
was not done here because it drags in `App.tsx:37`, which this job explicitly excluded.

---

## 3. Task 2. The panels

VM `cfv-160`, `Standard_D2s_v4`, image `clawfactory-win11-baseline-v2`, artifact
`29acdf95...`. Install re-verified the artifact hash on the box before running.

### 3.1 The install

**12 PASS, 0 FAIL, 0 VOID, 5 INFO.** Identical shape to the interim run. All 30 preflight
resources present by independent enumeration with the absent-resource control correctly
failing, all seven build pins re-derived on the installed machine, installed version reports
1.2.0, WSL channel self-test discriminates.

### 3.2 Do the panels work? Yes, all three.

Stated plainly, because that is what the session was for.

| Panel | Verdict |
| --- | --- |
| **Recently deleted** | **Works.** Lists the entry, restores it, file returns byte-exact |
| **Email settings** | **Works.** Saves the credential, shows back what it should, hides what it should |
| **Approvals** | **Works.** Card renders in full, approve sends, deny discards |

No panel showed the error banner D4 reported. No panel was unwired. The banner belongs to the
home route, exactly as the scope session concluded from source.

### 3.3 Recently deleted

A real agent turn, asked in plain language to delete a named file, routed it into quarantine.
The agent's own reply told the user the file "can be restored any time via Studio, Recently
deleted", which is the route being tested.

The panel listed it with the correct name, the original path, `65 B`, and "kept 30 more days".
Restore was clicked from the panel.

Verified through the root channel, not from Studio:

| Check | Result |
| --- | --- |
| Present at the original path | yes |
| sha256 | `e67a1f28...`, exact match to the value recorded before the agent touched it |
| Size | 65 bytes |
| Content | the run's unique marker, read back verbatim |
| Quarantine index after restore | empty, entry consumed |
| CONTROL | a never-restored path correctly reads absent |

**One thing that was nearly recorded wrong.** The restored file reads mode `777`, and the
first pass recorded ownership as correct without checking what `777` meant. A control settled
it: a file the agent creates in the same directory reads `664`, so the mount does not blanket
everything to `777`. That looked like restore widening permissions.

It is not. A second control, writing a file from **Windows** into the same granted folder,
reads `777` as well, which is what the deleted file was. `chmod 600` sticks, so modes are
genuinely settable and `777` is not a floor. Restore reproduced the original faithfully. The
PASS stands, now with evidence under it instead of an assumption.

### 3.4 Email settings

**This is the path the Task 1 fix exists for**, and it saved with no error on the first
attempt.

| Check | Result |
| --- | --- |
| Credential saved from the panel | `configured: true` |
| Panel has true data to show | from-address and `smtp.gmail.com:587` returned |
| Secret returned to the renderer | **no**, and no secret-shaped field at all |
| Credential file | `root:root 600` |
| uid 1000 reading it | `Permission denied` |
| CONTROL | a deliberately 644 file reads 644, so `600` is a real reading |

7 PASS, 0 FAIL.

### 3.5 Approvals

The card shows everything, without expanding anything: both recipients, the destination
`smtp.gmail.com:587`, `queued by clawuser`, a live countdown, the **whole body** in its own
block, and the attachment with name, size and hash under the line "these exact bytes were
copied when the message was queued". That is the staging guarantee stated where the user is.

**Approve.** The broker transmitted it and the provider accepted it:

```
[sendd] sent 2026-08-14T00-26-38-893Z-4c5ed0a7
        (250 2.0.0 OK 1786667704 98e67ed59e1d1-394e921709dsm209870a91.0 - gsmtp)
```

Worth being precise about what that proves. The recipient domain was `example.invalid` and
cannot exist, but the SMTP connection goes to `smtp.gmail.com`, taken from the configured
credential. So the provider authenticated, accepted the message and issued a queue id, and
will bounce it later. The approval executed, a receipt was written, and the credential the
human typed is confirmed working by that `250`.

**Deny.** Nothing was sent. The staged attachment bytes were gone from `staging/`, verified by
searching for the exact bytes with a control proving the search was not blind (the same bytes
were still findable in the workspace). No receipt was written. The request record survives in
`pending/`, `root:root 600`, carrying `state: denied`, the bound hash and the decision time,
and uid 1000 is refused when it tries to read it.

**A probe defect, recorded because the harness is committed.** `verify-deny` originally also
required the body to be absent from the store and recorded a FAIL when it was not. The product
never claimed that: the documented promise is that deny "discards the staged attachments",
which it did. The assertion was stronger than the claim. Fixed, and the retained audit record
is now asserted positively rather than treated as a leak.

### 3.6 The expired request, which was not planned and was worth more than the plan

An approval window lapsed while the human was away. Rather than discard it, the expiry was
treated as a test of a documented claim nobody had checked.

Security properties held completely: nothing was sent, staging was purged, and the record
carries `state: expired`, `approval: {state: none, boundHash: null}`.

But the panel showed **"Nothing waiting"**. `EMAIL_APPROVAL.md` section 7 told users that "an
expired request stays visible and is marked as such". It does not. The broker omits expired
requests from the list the panel reads, so an expired request and one that was never queued
look identical in the interface.

This is a documentation defect, not a security one, and it is the kind that matters: a user
who steps away and comes back is told by the product that nothing ever happened.

---

## 4. Task 3. The sixth channel

Test 8 asks whether the agent can approve its own send, across five channels that all live
inside WSL. A wired Studio adds a sixth the suite never covered: the Electron IPC bridge on
the Windows side, whose chain ends at a root-only socket.

`validation/interim-v120-phase5.ps1`. **13 PASS, 1 NOTE, 0 FAIL.** Run against a Studio that
was actually running, with four live processes, because against a closed Studio every result
would be vacuously true.

Two properties were proven separately, because they fail independently. A listener with closed
interop is still reachable over the network; closed interop with a listener is still reachable
over the network.

| Claim | Evidence |
| --- | --- |
| Studio owns no listening socket | 0 of 29 listening sockets belong to any Studio process. CONTROL: the enumeration found 29, so it is not blind |
| No remote-debugging surface | 9222, 9229, 5858 all closed. This is the one surface that would hand a caller the renderer, so it is named rather than swept |
| No Studio-adjacent port reachable from clawuser | debug ports and the old backend range all refused |
| The Windows filesystem is not visible to uid 1000 | `WINDOWS_VISIBLE=no`, `MNTC_IS_MOUNT=no`, 0 entries. CONTROL: the same test finds a path that IS there |
| Interop is genuinely off | `BINFMT=ABSENT`; `powershell.exe`, `wsl.exe`, `cmd.exe` all absent from PATH and all fail to execute |
| **PAIRED CONTROL** | the same engine call, from Windows, returns `{"ok":true,"pending":[]}` |

That last row is what makes the rest mean anything. The bridge is live from Windows, so every
refusal above is a statement about **who is asking**, not about a dead path.

**The NOTE, recorded rather than smoothed over.** clawuser could not reach RDP on the Windows
host either. RDP was definitely listening, since the session driving Studio was running over
it. So the network path is closed by nft as well, and the refusals are **over-determined**:
this phase does not claim which mechanism did it. Had the control succeeded, "no listener"
would have been load-bearing on its own. It is honest to say both are true and neither was
isolated.

**Answering the question as posed.** The job asked, if the answer is that closed interop makes
the bridge unreachable by construction, to prove that rather than assert it. Closed interop is
proven directly, by `BINFMT=ABSENT` and by three named binaries failing to execute with a
control showing execution works. It is not the only thing standing in the way, which is the
stronger result.

**One observation, not a hole.** `wslpath` is present and translates `/tmp` to
`\\wsl.localhost\Ubuntu\tmp`. It is a path translation utility and grants no access to
anything; recorded so a later reader does not rediscover it as a surprise.

### 4.1 A phase 1 probe that cannot answer its own question

Phase 1 measures automount with `[ -d /mnt/c ]` and reported `MNT_C_PRESENT=yes` alongside
`AUTOMOUNT_LINE=enabled=false`, which reads as contradiction. It is not: the directory exists
as an empty stub while nothing is mounted on it. A directory test cannot distinguish "Windows
is exposed to the agent" from "an empty folder exists", and only the first is a security
claim. Phase 5 measures reachability instead. Phase 1's probe is left as-is, and recorded.

---

## 5. Task 4. The documentation status note

`docs/reference/EMAIL_APPROVAL.md`. The hedge is gone, replaced with what was observed and the
machinery that was checked underneath each observation rather than taken from the interface.

Two corrections to the body of that document, both to the text rather than to the product:

1. **Section 7, expired requests.** Corrected to say they disappear from the panel and that an
   expired request is indistinguishable there from one that was never queued.
2. **Section 4, receipts.** Corrected to say a receipt is an outcome record: expired requests
   produce one carrying `sent: false`, denied requests produce none, and the denial is recorded
   on the request itself.

These are documentation fixes inside the file Task 4 owns, not product changes. The mechanism
was not touched.

The truncated attachment hash is recorded in the status note as observed behaviour, without a
judgement attached.

---

## 6. Revised scope estimate

The scope session estimated three to three and a half sessions of Studio work. **What actually
remained was one defect fix and one validation pass, and both are now done.**

| Prior estimate item | Status after this run |
| --- | --- |
| Wire the three panels | **Unnecessary.** They were wired. Confirmed by use, not by reading |
| Route the desktop shell to them | **Unnecessary.** Routing worked on the first click |
| Build or restore a Studio backend | **Unnecessary, and it would have been wrong.** The architecture has no listener by design, and adding one would have created the network surface phase 5 just proved absent |
| B1, the SMTP save defect | **Done.** Task 1 |
| Validation pass on the panels | **Done.** Task 2 |
| Extend test 8 for the IPC bridge | **Done.** Task 3 |
| B2, the `App.tsx:37` version literal | Still open, deliberately out of scope |

The estimate was not merely too large. One of its line items, building a backend, would have
introduced a security regression, because the property that makes the bridge unreachable is
precisely that there is nothing listening.

---

## 7. Carried-forward test table

| Id | Test | Verdict | Note |
| --- | --- | --- | --- |
| P1.* | Clean install, resources, seven pins | **12 PASS / 0 FAIL** | unchanged shape from the interim run |
| PNL.1 | Granted workspace is a live mount | PASS | |
| PNL.WARM | Agent answers before a load-bearing turn | PASS | new; see 9.2 |
| PNL.2 | Agent deletion routes into quarantine | PASS | real turn, natural language |
| PNL.3 | Restore from the panel is byte-exact | PASS | sha256 and length match |
| PNL.3b | Restored ownership and mode | PASS | now evidenced by a Windows-origin control |
| PNL.4 | SMTP credential saves from the panel | PASS | **was impossible before Task 1** |
| PNL.4b | Summary carries from-address and host | PASS | |
| PNL.4c | Secret not returned to the renderer | PASS | not even masked |
| PNL.5 | Credential file `root:root 600` | PASS | |
| PNL.5b | uid 1000 cannot read it | PASS | |
| PNL.6 | Real agent-initiated send queued | PASS | |
| PNL.7 | Approval executed and wrote a receipt | PASS | provider queue id in the journal |
| PNL.7b | Approved request left the pending queue | REVIEW | terminal records stay in `pending/` by design |
| PNL.8 | Deny discards staged attachment bytes | PASS | assertion corrected, see 3.5 |
| PNL.8b | Denial recorded in a root-only audit record | PASS | |
| G2.8f.1 | Studio running, bridge live | PASS | precondition |
| G2.8f.2 | No Studio process owns a listening socket | PASS | 0 of 29 |
| G2.8f.2b | No remote-debugging port | PASS | |
| G2.8f.3 | No Studio-adjacent port reachable from clawuser | PASS | |
| G2.8f.3ctl | Is the WSL-to-Windows path open at all? | **NOTE** | closed by nft too, so refusals are over-determined |
| G2.8f.4a | Windows filesystem not visible to uid 1000 | PASS | reachability, not directory existence |
| G2.8f.4b | No Windows binary executes from uid 1000 | PASS | |
| G2.8f.5 | **PAIRED CONTROL**, same call from Windows | PASS | proves the refusals are about the caller |
| G2.8f | Sixth channel verdict | **PASS** | 13 PASS / 1 NOTE / 0 FAIL |

**Defects found and left, per instruction:**

| # | Defect | Severity |
| --- | --- | --- |
| D-a | Expired requests vanish from Approvals with no trace. Documented as staying visible | user-facing, doc corrected, product left |
| D-b | Studio footer says "MIT licensed"; the licence decision was PolyForm | customer-facing copy |
| D-c | Studio header reads `v0.1.0` against an installed product reporting 1.2.0 (`App.tsx:37`) | cosmetic, known |
| D-d | Attachment hash on the approval card is truncated to 16 characters with no way to see the full value | minor |
| D-e | `ClawFactory-Studio-Setup-1.1.0.exe` now names a **third** distinct payload | build hygiene |
| D-f | Phase 1's `/mnt/c` probe is a directory test, so it cannot answer the question it implies | harness |
| D-g | `invokeEngine` still uses `( )`. Correct for its current single-statement callers, latent for any future multi-statement one | latent |

---

## 8. Resource ledger

| Resource | Created | Disposed | Evidence |
| --- | --- | --- | --- |
| VM `cfv-160` | 2026-08-13 16:06 local | **deleted** 19:02 local | teardown proof below |
| `cfv-160-osdisk` | with the VM | deleted | named explicitly in teardown |
| `cfv-160VMNic` | with the VM | deleted | named explicitly in teardown |
| `cfv-160-pip` | with the VM | deleted | named explicitly in teardown |
| `cfv-160-nsg` | with the VM | deleted | named explicitly in teardown |
| NSG rule `allow-rdp-from-operator` | during the run | deleted with the NSG | scoped to a single `/32`, never `0.0.0.0/0` |
| License slot | on install | **released** | `Machine deactivated successfully` |
| Blobs in `validation` container | staged | retained | evidence, not billable compute |

Teardown proof, unfiltered: the only resources remaining in `clawfactory-validation` are the
storage account, the VNET and the two baseline images. **No resource matching `cfv-160`
remains, and the sweep list is empty.**

Total VM lifetime roughly **3 hours**, all of it in use. Nothing was left running at any
handoff.

**Credential hygiene.** The SMTP app password was typed by Bret into the Studio panel and
never entered a script, a transcript, or the model's context. A throwaway account was used
rather than a live one, after the question was raised. It authenticated to the provider for
real during the approve test, so it must be revoked; that is flagged to Bret and is his
action.

---

## 9. Lessons learned

`ClawFactory_Install_Lessons_Learned.md` gained **L28: three weak signals that agree with
each other feel like proof and are not.**

The interim validation was the most rigorous session this project has run, and it still
produced a confident wrong diagnosis about scope. D4 rested on three observations: an error
banner, a port scan finding no listener, and a `v0.1.0` version string. Each was true. Each
was consistent with "Studio is a scaffold". None of them tested it, because each measured a
proxy rather than the thing, and because they agreed they were read as mutual corroboration.

The shape to recognise is a conclusion assembled from several independent-looking weak
signals that agree with each other. What those three shared was "I have not run the thing",
so they failed together while looking convergent.

This project already owns the discipline that would have caught it and applied it everywhere
else in the same session: every block assertion carries a control that must fail. The
scaffold hypothesis made a directly testable prediction, that opening the Approvals panel
shows an error banner. Nobody opened it.

### 9.1 The same shape appeared twice more in this session, and both were caught by controls

Worth recording, because it shows the discipline working rather than only the failure it was
written about.

- **The restored file's `777`.** Recorded as correct ownership on the first pass without
  checking what the number meant. A control turned it into an apparent defect, restore
  widening permissions. A second control turned it back into a non-event. Two observations
  agreeing (`777` on the restored file, `664` on a nearby file) looked like a finding, and the
  thing that settled it was asking what the file's own origin implied.
- **The denied body still in the store.** The probe recorded a FAIL. The product had done
  exactly what it documents. The assertion was stronger than any claim the product makes, and
  a FAIL against an invented requirement is a harness defect that reads as a product defect.

Both are the L28 shape at small scale: a conclusion that felt supported, from measurements
that were individually true and collectively did not test the claim.

### 9.2 A harness defect that would have produced a false product verdict

The first `prep-quarantine` run issued a load-bearing agent turn without warming the agent.
The turn gate refused it fail-safe with `gate_error`, nothing was deleted, and the run recorded
`FAIL: agent deletion routed into quarantine`. On its face that is Guard 1 failing on a clean
box, which is the most alarming result this suite can produce.

It was L17, the first turn after an idle being cold. Phases 2 and 3 both warm first; the new
script did not, because it was written fresh rather than by copying a phase that already knew.
Now fixed with a warm plus retry that distinguishes a cold start from a persistent refusal,
and reports the second as a real finding rather than absorbing it.

The generalisable point: **a new probe inherits none of the hard-won preconditions of the ones
beside it.** Every one of those preconditions was added because something lied once.

---

## 10. Out of scope, confirmed untouched

No Guard 3, no Guard 4, no Studio restyle, no new panels, no marketing copy, no tag, no Inno
licence. `SECURITY.md:114`'s reference to the genuinely unwired Permissions page was left
alone, as instructed.
