# CC JOB: v1.4.4 wrapper fixes, the coverage gap behind them, then build and sign

Repo root: `C:\Users\bmcki\ClawFactory-Secure-Setup`. `cd` there and confirm first.

Read in full before anything else:

1. `docs/session_reports/2026-08-27_v143_validation_closeout.md`
2. `docs/session_reports/2026-08-27_v143_runner_closeout.md`

Three blockers, all found on cfv-178. Two have been shipping since v1.0.

## What this job is NOT

No tag. No GitHub release. No publish. No validation run beyond what TASK 1 specifies on the
existing box. No `#261` work. No `SP.8` change. No FrontierAI work. **Zero outbound email.**

---

## PROMPT 15 preamble

Paste the full block from `FrontierAI_CC_Prompt_Library.md`. Keep the VM clauses: TASK 1 uses an
existing box. If the copy you read ends before PROMPT 15, it is stale. Stop and say so.

---

## TASK 1. Prove the fixes on cfv-178 before spending a build

`cfv-178` is deallocated, not deleted, and it is the only installed instance where both defects
reproduce. Diagnose before build: a fix verified on a running box is worth more than a fix
verified by reading, and this costs one start and one deallocate.

1.1 Start `cfv-178`. Report the cost of the window you intend to keep it up for.

1.2 Hand-patch the two files **on the box only**, not in the repo, and confirm each fix works:

- The Kill Switch: with the gateway up, run it and confirm the gateway is actually down
  afterwards. `http=200 procs=1` before, and both readers agreeing it is down after. Use the
  200-versus-502 discriminator the validation run established: 502 means the root-owned proxy is
  answering while the gateway behind it is down, and any-HTTP-response-means-up is the reader
  defect that already cost a VOID.
- `switch-provider.ps1`: run it for a provider needing no credential and confirm it completes
  and applies its firewall change. Confirm the fail-closed guard that refuses to write a
  toolchain host into the allowlist still refuses.

1.3 Report both results with verbatim evidence, and a control in each case. Then revert the
box-side patches or note that the box is about to be deleted anyway.

1.4 Deallocate. Do not delete yet: TASK 4 may want it.

---

## TASK 2. The three blockers

2.1 **Kill Switch, `resources/clawfactory-stop.ps1:27,30`.** Both WSL lines die on a bash syntax
error, the script exits 0, and it prints that the gateway is stopped and any running agent turn
is killed. The folder-unmount half does work. In the repo since `d9b6d36`, the initial v1.0
release.

Fix it. Then fix the second defect underneath it: **the script reported success for a step that
failed.** Exit 0 on a failed WSL invocation is the same shape as `#286`, where the uninstaller
discarded its teardown's output and logged success unconditionally. Capture the invocation's
result, check it, and make the printed message conditional on what actually happened.

2.2 **`switch-provider.ps1:182,185,194,235`, plus `:155`.** Four unescaped `$baseHosts`, all
inside comments, inside an expandable here-string, under `Set-StrictMode 3.0`. The script dies
before applying anything, for every provider. It fails closed and the firewall is verified
intact.

Introduced by `3818bc0`, the commit that fixed the Guard 3 toolchain re-seed. **The fix's own
explanatory comments broke the script.** Say so in the close-out; it is the third time in this
cycle that a fix's artifact caused the next defect.

2.3 **`SECURITY_FINDINGS.md` lists the kill switch in the structural table as proven.** That is
false as written, and the structural table is the one marketing claims are allowed to match.
This is the most serious of the three from a credibility standpoint.

Correct it. After 2.1 the claim may become true, but a claim is structural only once it has been
measured on a box, and this build will not have been validated when the document ships. Decide
what the row should say in that state and justify it. Then enumerate the class: every other row
in the structural table, and whether each has evidence behind it or is there by assumption. That
enumeration is the deliverable, not the one corrected row.

---

## TASK 3. The coverage gap, which is why these shipped

`interim-v135-switchprovider.ps1` extracts the firewall block as rendered bash and runs that. It
has never executed `switch-provider.ps1` itself. **The suite tests the payload and has never run
the wrapper that builds it.** Both blockers lived in that gap, and section 14.11 found two on its
first outing.

`post-install.ps1`, `rename-agent.ps1` and `bootstrap.ps1` are still in it.

3.1 Enumerate every shipped PowerShell wrapper that builds a payload for another interpreter, and
report for each whether any phase executes the wrapper, executes only its rendered payload, or
does neither. Derive this from the harness, not from memory.

3.2 Extend the by-hand or automated coverage so the next validation run executes each wrapper, not
only its output. Where a wrapper cannot be run without a credential or an irreversible effect, say
so and state what the safe substitute is.

3.3 **Commit the AST sweep as a permanent check.** The validation session built a static check that
finds unescaped interpolation inside expandable here-strings under StrictMode, and it found all
four sites with correct line numbers and nothing else across every shipped script. That is worth
more than the fix. Add it as a build gate in `scripts/build_release.ps1`, named in the style of the
existing nine.

Canary it in both directions before trusting it: plant one instance of the defect in a shipped
script, confirm the gate FAILS naming that file and line, restore, and confirm it passes on a clean
tree. Report both readings. State what the gate cannot catch.

---

## TASK 4. Version, build, sign, ledger

4.1 Bump to **v1.4.4**. Never edit or delete a ledger row.

4.2 State whether Studio changed. It should not; it is clean at 1.3.2.

4.3 Run `build_release.ps1`. Report every gate by name with its verdict, including the worktree pin
and the new one, plus the unsigned digest, the signed sha256, the byte count, and the Authenticode
subject.

4.4 State exactly what changed between v1.4.3 and v1.4.4, and whether any change alters behaviour.

4.5 Once the build is signed, `cfv-178` has served its purpose. Print the delete command in the
close-out for the operator rather than running it. It costs money either way and the call is his.

---

## TASK 5. Cards, commits, close-out

5.1 Card each blocker and the coverage gap separately. Separate commits per logical change,
explicit per-file staging, both repos pushed, `origin/main` from `git ls-remote`. **No tag.**

5.2 `#284`–`#288` stay in `Review`. v1.4.2's uninstall work is still substantially unmeasured:
TASK 2 and TASK 3 of the v1.4.3 validation were never reached.

5.3 Close-out to `docs/session_reports/YYYY-MM-DD_v144_wrapper_fixes_closeout.md`, committed,
printed in full, unprompted. Every claim carries verbatim evidence. Anything reasoned rather than
measured is labelled INFERRED in the sentence that makes the claim.

Answer these explicitly:

1. The TASK 1 on-box results for both fixes, with their controls.
2. The structural-table enumeration from 2.3: which rows have evidence and which do not.
3. The wrapper coverage table from 3.1, and what 3.2 added.
4. The new gate's two canary readings.
5. **The full validation scope for v1.4.4.** A rebuild invalidates every measurement taken against
   v1.4.3, and v1.4.2's headline items were never reached. So this is the full matrix plus
   sections 14.1 through 14.12 plus the new wrapper coverage, not a re-run of what broke. Say so
   plainly and cost it in boxes.

**Do not write a fitness-to-publish verdict.** This build will not have been validated.

5.4 End-of-session gate in full: task accounting, resource ledger, delta security sweep, delta bug
review.

---

## Challenge this prompt

Written by someone who cannot see the repo. If an instruction is wrong about the code, ambiguous,
or would break something outside its scope, stop and report rather than building what was meant.
