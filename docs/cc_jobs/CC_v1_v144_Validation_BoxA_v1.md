# CC JOB: v1.4.4 validation, BOX A

Repo root: `C:\Users\bmcki\ClawFactory-Secure-Setup`. `cd` there and confirm first.

Read in full before anything else:

1. `docs/session_reports/2026-08-27_v144_wrapper_fixes_closeout.md` — its **section 9** is the
   authoritative box plan and this job is box A of four.
2. `docs/session_reports/2026-08-27_v143_validation_closeout.md`
3. `docs/session_reports/2026-08-27_site_killswitch_claims_closeout.md`

**This is one box of four.** Boxes B, C and D are separate sessions on separate days. Do not
attempt them here and do not provision more than one VM.

Nothing has been measured against v1.4.4. Three debts stack: v1.4.4's own changes, v1.4.3's
matrix which stopped on a ship-blocker at row 1, and v1.4.2's keep-Linux uninstall work which has
never been measured on any release. Box D carries the third. Box A carries the first and most of
the second.

## What this job is NOT

No tag. No GitHub release. No publish. No rebuild, re-sign or version bump. No `#261` work. No
`SP.8` change. No `#278`, `#280`, `#281`, `#283`, `#293`, `#294`. No FrontierAI work.

**Zero outbound email.** Do not run `phase3b` or any probe that transmits. It sends twice, in
test 3 and in test 6. `#198` stays VOID as a receiving-provider outcome; Guard 2's delivery path
is already proven end to end.

---

## PROMPT 15 preamble

Paste the full block from `FrontierAI_CC_Prompt_Library.md`, **VM clauses included**. If the copy
you read ends before PROMPT 15, it is stale. Stop and say so.

---

## The artifact

| | |
| --- | --- |
| version | v1.4.4 |
| signed sha256 | `6e65560325cb6d7d3fea204ebb72876b3b113cbbfe9f2fa4f94113237e9eb4d1` |
| signed bytes | 440610608 |
| unsigned, as the ledger records | `548562c72d5261bc62d590df03746ea2bb52134a413e10d137b590e589fdcdea` |
| build commit | `25945d5`, stamp fix `31e2aa1` |
| Studio | unchanged at 1.3.2, pin `ac59375…` |

Three derivations before anything is installed: build machine, blob storage by download and
re-hash, and on the box after transfer. If any differ, stop.

The signed digest is not reproducible across signing runs; the ledger records the unsigned one.
Do not treat a differing signed digest on a fresh sign as a defect.

---

## TASK 0. Plan, cost, and the stale-default sweep

Stale defaults have cost a box in four consecutive runs. Sweep before provisioning.

0.1 State the plan before `az vm create`: the box, the phase order, estimated hours, and the
operator touches you expect. Section 9 of the v1.4.4 close-out gives the shape.

0.2 `interim-v140-relgate-box.ps1` defaults to an older artifact. Update to the v1.4.4 signed
digest and byte count above. `interim-v120-phase1.ps1` `$PIN.version` was bumped to 1.4.4 in
`25945d5`; confirm rather than assume.

Then go wider: enumerate every pin, digest, version literal, seed host and default artifact path
in `validation/`, and report which are current and which are stale. The enumeration is the
deliverable, not the two fixes. Canary it: plant one stale value of a shape you have not already
found, confirm the sweep reports it, remove it.

0.3 Upload the artifact and verify the blob by download and re-hash, not by a service property.

0.4 Verify the starting estate with an unfiltered subscription-wide list. `cfv-178` and its four
orphans were deleted; the expected residual is the storage account, the VNET and two baseline
images.

---

## TASK 1. Phase order, because two phases change box state

Run in this order and state it in the close-out:

1. Matrix row 1, clean install with `-Provider claude`.
2. Matrix rows 3, 5 to 14.
3. Sections 14.8, 14.9, 14.10, 14.11, 14.6.
4. `interim-v144-wrappers.ps1` **with `-RunProviderSwitch`**, second to last, because WR.5
   switches the box to ollama and would confound anything after it.
5. The RemoveAll uninstall branch, 16 rows, last of all, because it destroys the install.

Rows 2 and 4 are boxes C and B. Do not attempt them.

A phase whose positive control does not fire does not report a result.

---

## TASK 2. The v1.4.4 changes, which have never run on a clean install

Everything below was proven on a hand-patched cfv-178 with the shipped script as a failing
control. That is real evidence and it is not a clean-install measurement, which is why the kill
switch was removed from the structural table rather than marked proven.

2.1 **The kill switch, from a clean install.** Gateway up by two readers, run it, gateway down by
two readers. Use the 200-versus-502 discriminator: 8787 is the root-owned gating proxy and answers
502 while the gateway behind it is dead, so any-HTTP-response-means-up is a reader defect that has
already voided a phase.

2.2 **The kill switch refuses to claim success when it cannot verify.** Fault-inject so the
verification cannot run, and require exit non-zero with no success banner. A success path that has
never failed is indistinguishable from one that cannot.

2.3 **`switch-provider.ps1` completes**, applies its firewall change, and leaves the toolchain set
untouched. Measure the allowlist either side with a control that fires.

2.4 **The fail-closed toolchain guard refuses.** Shadow the resolver so a base host is reported as
a toolchain host and require a refusal, with the firewall unchanged by the refused run.

2.5 **The Ollama honesty line.** With Ollama absent, the script must warn rather than print an
earned-looking success line, and must still apply the firewall change.

2.6 The new wrapper phase's other rows: WR.1, WR.2, WR.3, WR.4, WR.7, WR.8, WR.9. `rename-agent.ps1`
blocks on a modal dialog and is an operator click, not an unattended row.

---

## TASK 3. The v1.4.3 sections, carried forward

3.1 **14.8**, bundled bytes on the box are the committed bytes. Every `[Files]` entry under `{app}`
and `{app}\resources` asserts `CR=0` and a SHA-256 matching the blob at the v1.4.4 build commit.
**The negative half:** a CR counter that always returns zero would pass every file identically, so
plant a CR and require the counter to report it.

3.2 **14.9**, `orchestrator-prompt.md` reaches the distro with `CR=0`, with a control asserting the
file is non-empty and carries its substituted digest.

3.3 **14.10**, `wsl-keepalive.vbs` runs from its LF form: the scheduled task starts, no console
window flashes at logon, a WSL session is held. Control: the probe can detect the task's absence.

3.4 **14.11**, the Windows-side `.ps1` files execute from `{app}\resources`. An AST parse is not an
execution.

3.5 **14.6**, the launcher against a genuinely down gateway logs `[STARTED]`, not
`ALREADY_RUNNING`. The precondition needs both readers agreeing the gateway is down.

3.6 14.12: the worktree pin and interpolation gates are build-time. Do not spend a phase looking
for them on the box.

---

## TASK 4. Operator handoffs

Expect an RDP login to start the install, one after any reboot, the by-hand panel checks, the
`rename-agent.ps1` click, and the RemoveAll uninstall dialog.

4.1 **Never run an automated probe while the operator is on the box.** That collision produced a
false FAIL that had to be re-derived. Say in the card that nothing else is running.

4.2 Every card: `PushNotification`, exact steps with real values, success quoted literally so he
compares strings rather than judging, what a FAIL looks like, somewhere to record it. Whole
checklist in the card, never a path to a file on the box.

4.3 The by-hand checklist quotes Studio version strings. Studio is unchanged at **1.3.2**, so those
stay. Confirm against the built bundle rather than assuming.

---

## TASK 5. Standing traps

1. Never call `az vm user update` after provisioning.
2. One `az vm run-command` at a time, subscription-wide. A second returns `Conflict`.
3. `run-command` runs as SYSTEM and cannot touch WSL.
4. A single reachability attempt is a coin flip against a rotating pool. Take several, report the
   count.
5. A binary string scan of the installer is blind. Inno compresses the code section.
6. `/mnt/c` is absent by design.
7. `python` is blocked on the build machine. Dispatch writes go through PowerShell with
   `x-frontier-secret`, one endpoint, `POST /api/agent/update`.
8. An errored `az` command's empty output is not evidence. Check exit codes.
9. A resource may still list immediately after a successful delete. Re-check before calling it a
   failed delete.
10. A variable assigned from `$( )` inside an inline WSL payload comes back empty on this channel.
    Emit the value as the payload's only output and parse it PowerShell-side.
11. Do not put a build or a signing step through a pipeline that can close early.

`SP.8` will FAIL. It is the documented address-scoping residual. Do not adjust, retire or invert
it.

---

## TASK 6. Teardown

By explicit name, NIC before public IP and NSG, proven with an unfiltered subscription-wide list.
Report VM count, disks, NICs, public IPs, NSGs, and the exact scope of any RDP rule created.

---

## TASK 7. Close-out

No fitness-to-publish verdict. Box A is one of four and a verdict on partial coverage would rest
on an unmeasured premise. Instead:

7.1 State every row measured, its verdict, and its evidence.

7.2 State exactly what boxes B, C and D still owe, so the next session inherits a spec rather than
reconstructing one.

7.3 Anything argued rather than measured is labelled INFERRED in the sentence that makes the claim.

7.4 Close-out to `docs/session_reports/YYYY-MM-DD_v144_validation_boxA_closeout.md`, committed,
printed in full, unprompted. Both repos pushed. **No tag.**

7.5 Cards: `#284`–`#292` move only as far as box A's evidence supports. A card whose fix is proven
on one box of four is not `done` if its scope spans the others. Say which and why.

7.6 End-of-session gate in full: task accounting, resource ledger, delta security sweep, delta bug
review.

7.7 If the run ends early for any reason, write and print an honest incomplete-state close-out
naming exactly what remains.

---

## Challenge this prompt

Written by someone who cannot see the repo. If an instruction is wrong, ambiguous, or would break
something outside its scope, stop and report rather than building what was meant. If the TASK 0
plan shows box A does not fit in one session, say so before provisioning.
