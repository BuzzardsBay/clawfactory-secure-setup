# The manual-check register

**What this is.** The complete list of validation checks that need a person, why each one
does, and the rule that they are taken **together, once, at the end of a run** rather than
one interruption at a time.

**Why it exists.** Across the v1.4.3, v1.4.4 and v1.4.5 cycles the human checks were
scattered through the run order, so each one cost a separate interruption at an
unpredictable moment. Box A alone cost five touches across two days. Nothing enumerated
them in one place, so nobody could see that four of the five could have been one.

`validation/MANUAL_CHECKS_studio.md` is the worked procedure for the ten Studio panel
checks and is **not** superseded by this file. This is the register; that is the script for
one entry in it.

---

## The rule

**A measurement that needs a person costs one interruption for all of them, not one each.**

1. The automated run completes end to end without stopping. Every check that a machine can
   take is taken before the operator is asked for anything.
2. The human checks are then presented **once**, as a single card, in the order below.
3. The box is **deallocated** if the operator is not immediately available, and restarted
   for the batch. With the runner now restarting itself (`cfv-arm-persistence.ps1`) that
   restart costs no login.
4. Anything that cannot be batched — because it destroys state the automated run still
   needs, or because its subject expires on a timer — is named as such here, with the
   reason. **A probe whose subject expires on a timer is staged immediately before the
   operator acts, never in advance.**

---

## Register

Ordering constraints are load-bearing and are stated per row. `M-9` destroys the install
and is last of all; `M-8` wedges the machine if the hazard is real and is therefore last
before teardown of a box being torn down anyway.

| ID | Check | Why a person | Batchable | Order constraint | Last taken |
| --- | --- | --- | --- | --- | --- |
| **M-1** | Ten Studio panel checks (matrix row 11), per `MANUAL_CHECKS_studio.md` | Rendered text and layout read by eye. The strings are in the shipped `app.asar` and can be scanned, but "the card renders and says this" is a visual claim | **Yes** | After any provider switch would confound the panel reading, so **before** `WR.5`/`WR.6` | v1.4.4 box A, all ten PASS |
| **M-2** | `rename-agent.ps1` modal click | Blocks on a modal `MessageBox`; an unattended phase hangs rather than fails | **Yes** — folds into M-1, it is a click inside that pass | Inside M-1 | v1.4.4 box A |
| **M-3** | Enter the real SMTP app password in Studio → Approvals → Email settings | **Irreducibly human: a credential the operator owns.** It must never enter a script, a transcript or this session's context | **Yes** | Before any Guard 2 send-path row; those rows record VOID without it | v1.4.4 box D |
| **M-4** | Keep-Linux uninstall dialog #1, choose **No**, quote the copy back | The subject *is* the rendered dialog. Answering it is a click; reading it is the measurement | **Yes** | After the before-state read-back (`uninstate -Mode Before`) | v1.4.4 box D |
| **M-5** | Uninstall dialog #2 after a fault injection, choose **No**, quote the incomplete-teardown copy | Same; the negative half of M-4 | **Yes** | After `teardownfault -Mode Inject` | v1.4.4 box D completion |
| **M-6** | Inno's own uninstall confirmation, choose **Yes** | Same | **Yes** | Immediately precedes M-4 | v1.4.4 box D completion |
| **M-7** | "No console window flashes at logon" (v1.4.3 close-out §14.10) | An observation that only a human present at a logon can make. `wsl-keepalive.vbs` runs under `wscript` at `vbHide=0` specifically to prevent it | **Yes**, but it must be observed at a **real interactive logon** | At the first interactive logon of the batch — so the batch's own login *is* this check | **DEFERRED three cycles.** Never taken |
| **M-8** | **`OM-1`** — open `http://127.0.0.1:8787` from the Start Menu shortcut, capture the screen, with a gateway `/status` 200 from a non-browser path immediately before **and after** | The finding is what a first-run user sees. Requires an explicit, pre-recorded one-time suspension of hazard rule #5 | **Yes**, but **last on a box being torn down anyway** — if the hazard is real this wedges the machine | Last before teardown, after every other verdict is in | **NEVER TAKEN.** Skipped three cycles |
| **M-9** | RemoveAll uninstall branch dialog | Destroys the install | **Yes**, but strictly **last of all** | After everything, including M-8 | v1.4.4 box A |
| **M-10** | ~~Set the VM admin password at `az vm create`~~ | **REMOVED 2026-09-01 by operator decision.** The session generates it inside the provisioning command, so the value is never seen, printed or stored. *"I don't see a reason for me to enter the passwords and get into the VMs if you can do it yourself."* A validation VM has no inbound path, holds nothing, and is deleted within hours — a password nobody knows is the correct design for a box nobody logs into | — | — | **No longer a touch** |
| **M-11** | Create the GitHub Release / publish | **Irreducibly human: a public action** | **No** — belongs to the release job, not the validation run | Post-validation | v1.4.5 |

---

## What is NOT on this list, and why

**Every other check in the suite is automatable and is automated.** The register is short
because the suite is largely machine-taken already. The three items that *looked* like
human checks and are not:

- **Starting the on-VM runner.** Was a human step on every box of every cycle. It is not a
  measurement — it is transport. Closed by `cfv-arm-persistence.ps1`.
- **Restarting the runner after a reboot.** Same, and worse: it cost 54 minutes of dead
  wall-clock on `cfv-191`, where Windows came back at 18:55:19 and nothing ran until the
  operator logged in at 19:49:24. Closed by the same mechanism.
- **Reading a `.out` a poller could not retrieve.** Was diagnosed by hand more than once.
  Closed by `Receive-CfvJobOutput`, which retrieves in bounded chunks and asserts the
  reassembled byte count against the box's own.

---

## What this would have done to the last three cycles

| Cycle | Touches taken | Under this register | Removed |
| --- | --- | --- | --- |
| **v1.4.3** (`cfv-178`, 1 box; 4 planned) | 1 spent before the run stopped on its second ship-blocker; ~12 planned | **0** | the runner start, and now the provisioning touch |
| **v1.4.4** (boxes A, B, C, D + completion) | **13–15** across four sessions | **1**: a single end-of-run batch carrying M-1…M-6 and M-9 | 12–14 |
| **v1.4.5** (E, F, `cfv-191`, publish) | **7+**: 3 on `cfv-191` alone (create, start runner, restart runner) | **1**: M-11, the release | 6+ |

**Two classes were removed, and they are not the same kind of win.**

- **The runner start and every restart** — pure transport. No measurement got cheaper; it
  simply stopped needing a person. Closed by `cfv-arm-persistence.ps1`.
- **The provisioning password** (M-10) — removed by an operator *decision* on 2026-09-01,
  not by an engineering change. It was never a measurement at all.

**What remains is only ever what a person must see or authorise:** the by-eye checks, a
live credential, and a public action.
