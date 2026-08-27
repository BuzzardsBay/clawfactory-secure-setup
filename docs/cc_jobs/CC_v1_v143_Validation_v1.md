# CC JOB: v1.4.3 full release validation

Repo root: `C:\Users\bmcki\ClawFactory-Secure-Setup`. `cd` there and confirm first.

Read in full before anything else, in this order:

1. `docs/session_reports/2026-08-26_v143_line_endings_closeout.md` — its **section 10.4** is the
   authoritative scope for this job.
2. `docs/session_reports/2026-08-26_v142_uninstaller_fixes_closeout.md`
3. `docs/session_reports/2026-08-26_v141_validation_closure_closeout.md`

**Two releases have been built since the last artifact anyone ran on a box.** v1.4.1 was
measured on cfv-175 and cfv-176. v1.4.2 and v1.4.3 have never been installed anywhere. v1.4.3
changed bytes inside ten files that ship in the installer, including four Windows-side `.ps1`,
a `.vbs` executed by a scheduled task, and a markdown file delivered into the distro.

**So prior matrix passes do not transfer.** They were measured against a different binary. This
job re-runs the matrix in full against v1.4.3 and adds section 10.4's new items. Do not
cherry-pick rows on the argument that a change was small. If you believe a row genuinely cannot
be affected, say so with the reasoning and let it be a stated deviation rather than a silent
omission.

## What this job is NOT

No tag. No GitHub release. No publish. No rebuild, re-sign or version bump. No `#261` work. No
`SP.8` change, `#277` is still after the shipping decision. No `#278`, `#280`, `#281`, `#283`.
No FrontierAI work.

**Zero outbound email is authorised.** Do not run `phase3b` or any probe that transmits.
`phase3b` sends twice, in test 3 and in test 6. `#198` stays VOID and is recorded as a
receiving-provider outcome: Guard 2's delivery path is already proven end to end, a real message
was accepted by Gmail with a `250 OK`, and the failure is Microsoft's inbound filtering rather
than a ClawFactory behaviour. Do not spend a send re-testing that.

---

## PROMPT 15 preamble

Paste the full block from `FrontierAI_CC_Prompt_Library.md` here and follow it, **VM clauses
included**. The v1.4.2 prompt left this block empty and it should not have. If the copy you
read ends before PROMPT 15, it is stale. Stop and say so.

---

## The artifact

| | |
| --- | --- |
| version | v1.4.3 |
| signed sha256 | `b2cd6408e5d6fe39116c6e5c559f7de6cf86b2ac2d7a4a8e9093e399edb8c6a1` |
| signed bytes | 440609096 |
| unsigned, as the ledger records | `60f4e817f45147ba9b2d1c55b1ca43271b4eb589591735427f9ae518f29365e7` |
| build commit | `de4da85`, `origin/main` at `38edb66` |
| Studio | unchanged at 1.3.2, pin `ac59375…` |

Verify on the build machine, verify the uploaded blob by download and re-hash, and re-derive on
the box after transfer. Three derivations, as the last two runs did. If any differ, stop.

---

## TASK 0. Plan, cost, and the stale defaults

Azure spend is a live constraint. The cfv-175 run ended early on a spend notice.

0.1 State your plan before provisioning: how many boxes, which items on which box, estimated
hours. Prefer the fewest boxes. Say plainly if the uninstall-then-reinstall cycle and the
install-variant rows need their own clean boxes.

0.2 **Stale defaults have wasted a box in each of the last three runs. Sweep for them before
provisioning, not after.** Known and expected:

- `validation/interim-v140-relgate-box.ps1` defaults still point at an older artifact. Update to
  the v1.4.3 digest and byte count above.
- `interim-v120-phase1.ps1` pins `$PIN.version`. It was 1.4.0 during the v1.4.1 run and is
  presumably 1.4.2 or older now. It must read **1.4.3**.
- The by-hand checklist quotes Studio version strings. Studio is unchanged at **1.3.2**, so
  those stay as they are. Confirm rather than assume.

Then go further than the list: enumerate every pin, digest, version literal and default artifact
path in `validation/` and report which are current and which are stale. That enumeration is the
deliverable, not the three fixes.

0.3 Verify the starting estate is clean, delete any preserved FAIL VMs and OS disks by explicit
name, and upload the v1.4.3 artifact. Report an unfiltered list.

---

## TASK 1. The matrix, rows 1 to 14, against v1.4.3

Full re-run. Every phase reports N of N with its controls firing. A phase whose positive control
does not fire does not report a result.

Row 4 requires `-Provider later`. Row 2 requires the licence host blocked, with the prior
artifact as its control. Rows 5 to 7 require `-ExtraFiles validation\sp-prefix-fw.sh`, which
v1.4.3 made structural; confirm it stages rather than trusting that.

`SP.8` will FAIL. It is the documented address-scoping residual, not a regression. Do not adjust,
retire or invert it.

---

## TASK 2. The headline: keep-Linux uninstall, then a reinstall that completes

This is the single item that turns the v1.4.1 NO into a yes. Section 14.1.

2.1 Install v1.4.3 clean.

2.2 Uninstall through the real dialog, choosing **No**. The v1.4.2 changes live entirely inside
that branch; the RemoveAll path exercises none of them.

2.3 Verify by read-back against a held before-state that `clawuser`, `/etc/clawfactory`,
`/usr/bin/openclaw`, all 11 units, all 17 helpers, the allow-providers drop-in directory,
`/usr/local/bin/clawfactory-send` and both enablement symlink sets are gone. The before-state is
what makes the after-state mean anything, and the reader needs a control proving it can still
detect something that IS present.

2.4 **Reinstall, and confirm it completes.** On v1.4.1 this aborted at
`Failed to create clawuser (exit=1)`.

2.5 Read `%TEMP%\ClawFactory-Uninstall.log` and confirm `CLAWFACTORY_TEARDOWN_OK` with a
`READBACK` line showing `units=0 sbin=0 enabled=0 left=[ ]`.

2.6 **The negative half, without which 2.5 proves nothing.** Inject a fault so the teardown
cannot complete, and confirm the log records failure and the user-facing dialog appears. A
success marker that has never failed is indistinguishable from one that cannot.

2.7 Section 14.3: after the keep-Linux uninstall, `systemctl list-unit-files 'clawfactory-*'`
returns nothing enabled, and `clawfactory-fw.service` is neither present nor failed at the next
boot.

---

## TASK 3. The RemoveAll branch, re-run in full

Section 14.4. All 16 rows. `DoRemoveAll = True` for `/SILENT` and for the dialog's default
button. `PIN.version` reports **1.4.3**, not 1.4.2 as the carried-forward text says. The dialog
that selects this branch was rewritten, so the branch cannot be assumed unaffected.

---

## TASK 4. What v1.4.3 changed, measured on the box

These are new and none has ever been observed running.

4.1 **Section 14.8, bundled bytes on the installed box are the committed bytes.** For every file
under `{app}` and `{app}\resources` with a counterpart in the `.iss` `[Files]` section, assert
`CR=0` and assert the SHA-256 matches the blob at commit `de4da85`. Ten of these would have
failed against every release up to v1.4.2. **The negative half:** confirm the same probe reports
a mismatch when handed a deliberately altered copy.

4.2 **Section 14.9, `orchestrator-prompt.md` reaches the distro with CR=0.** This is the one
delivered file whose bytes change. Read `~/.openclaw/agents/orchestrator/agent.md` as `clawuser`,
assert `CR=0`, and assert the byte count is 65 lower than v1.4.2 would have produced. Control:
assert the file is non-empty and carries the substituted SOUL digest, so an absent or truncated
file cannot read as a pass.

4.3 **Section 14.10, `wsl-keepalive.vbs` runs from its LF form.** The build-machine rig proved
VBScript parses LF, but deliberately never reached `sh.Run`. On the box: confirm the
`ClawFactory WSL Host` scheduled task starts, no console window flashes at logon, and a WSL
session is held afterwards. Control: confirm the probe can detect the task's absence.

4.4 **Section 14.11, the four Windows-side `.ps1` execute from their LF form.** Run
`smoke-test.ps1`, `clawfactory-stop.ps1` and `switch-provider.ps1 -Provider <name>` from
`{app}\resources`, and confirm `clawfactory-grants.ps1` dot-sources cleanly from `launcher.ps1`.
An AST parse is not an execution.

4.5 **Section 14.6, the launcher on a box with the gateway down.** v1.4.2 changed it from
silently doing nothing to starting the gateway. It is the only install-and-run-path change in
either release.

4.6 Section 14.12: the `Worktree pin` build gate is not a runtime control. Do not spend a phase
looking for it on the box.

---

## TASK 5. Operator handoffs

Expect at least two: an RDP login to start each install, one after any reboot, the uninstall
dialog by hand, the rendered-dialog check, and check 10.

5.1 Section 14.5, the rendered dialog: no mid-sentence wrap, not wider than the screen, Yes still
the default button. Quote the wording as the operator actually saw it.

5.2 **Never run an automated probe while the operator is on the box.** That collision produced a
false FAIL on cfv-175 that had to be re-derived. Say in the card that nothing else is running.

5.3 Every card: `PushNotification`, exact steps with real values substituted, success quoted
literally so he compares strings rather than judging, what a FAIL looks like, somewhere to record
it. The whole checklist in the card, never a path to a file on the box.

---

## TASK 6. Standing traps

1. Never call `az vm user update` after provisioning.
2. One `az vm run-command` at a time, subscription-wide. A second returns `Conflict`.
3. A single reachability attempt is a coin flip against a rotating pool. Take several, report the
   count.
4. `az vm run-command` runs as SYSTEM and cannot touch WSL.
5. A binary string scan of the installer is blind. Inno compresses the code section.
6. `/mnt/c` is absent by design.
7. `python` is blocked on the build machine. Dispatch writes go through PowerShell with
   `x-frontier-secret`, one endpoint, `POST /api/agent/update`.
8. An errored `az` command's empty output is not evidence. Check exit codes.
9. `Invoke-RestMethod` on a JSON array makes `$r.cards` an array of nulls, which is truthy.

---

## TASK 7. Teardown

By explicit name, proven with an unfiltered subscription-wide listing. "It said deleted" is not
"it is gone". Report VM count, disks, NICs, public IPs, NSGs, and the exact scope of any RDP
rule created.

---

## TASK 8. The fitness-to-publish statement

Write it fresh. This is the deliverable the publish decision rests on, and it is the fourth
attempt at it.

State, in order: what is proven and would survive an audit, what is VOID or unmeasured and why,
what stands in the way, and a yes or no.

Two rules, and they are the point. Every claim carries verbatim evidence in a fenced block.
Anything argued rather than measured is labelled INFERRED in the sentence that makes the claim.
If yes, it must be a yes with no argued premise inside it.

Address explicitly:

- Whether the two previously unvalidated releases are now fully covered, or whether anything from
  v1.4.2 or v1.4.3 remains unmeasured.
- `#261` as a written, accepted condition of shipping, in the terms a reader of the release notes
  would need. Prior measurement, labelled as prior. Make no recommendation for or against
  publishing on it.
- `#198`, VOID by design this run, with the reason.

---

## TASK 9. Cards, close-out, gate

9.1 Move `#284`, `#285`, `#286`, `#287`, `#288` to the state their evidence supports. All five are
`Review`. Validated is `done`; anything less is not. Verify final states from the board after
writing.

9.2 Close-out to `docs/session_reports/YYYY-MM-DD_v143_validation_closeout.md`, committed with the
session files, printed in full and unprompted. Both repos pushed. **No tag.**

9.3 End-of-session gate in full: task accounting, resource ledger, delta security sweep, delta bug
review.

9.4 If this run ends early for any reason, write and print an honest incomplete-state close-out
naming exactly what remains.

---

## Challenge this prompt

Written by someone who cannot see the repo. If an instruction is wrong about the code, ambiguous,
or would break something outside its scope, stop and report rather than building what was meant.
In particular: if the plan in TASK 0 shows this cannot be done in the boxes and hours available,
say so before provisioning rather than discovering it half way.
