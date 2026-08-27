# CC JOB: correct the kill-switch claims on the live site

Two repos. Read from `C:\Users\bmcki\ClawFactory-Secure-Setup`, change
`BuzzardsBay/clawfactory-site`, which serves `clawfactory.app`. Confirm both roots before
starting.

Read first: `docs/session_reports/2026-08-27_v144_wrapper_fixes_closeout.md`, section 5.

## Why this is its own job

The site presents the kill switch as a security control in at least five places. That claim has
been false since the initial release: the script's WSL lines died on a syntax error, it exited
0, and it printed that the gateway and any running turn were stopped. Measured `up(200)` before
and `up(200)` after, with the shipped script as the failing control.

The repo-side claims were corrected in v1.4.4. The published ones were not. This is a live false
security claim, and it is the same class as `#274`, which was a reason to refuse publication of
v1.4.0.

## What this job is NOT

No tag. No release. No rebuild. No validation. No publish: the change is staged and the operator
executes it. No `#261` work. No FrontierAI work.

---

## PROMPT 15 preamble

Paste the full block from `FrontierAI_CC_Prompt_Library.md`. Delete the VM, handoff-card and
Azure ledger clauses with a note saying why. Everything else applies.

---

## TASK 1. Enumerate the class, do not fix the five

The v1.4.4 close-out names five sites: meta description, hero, controls table, and both feature
lists. **Treat that as a starting point, not the list.** Three of the last four jobs found a card
understated its own scope, and the fix was enumeration every time.

1.1 Sweep the entire site repository for any claim about the kill switch, stopping, killing,
halting, or terminating the agent. Include HTML, markdown, JSON-LD or other structured data, meta
tags, alt text, image text where readable, and anything in a build or template directory. Report
the count and every hit with file and line.

1.2 Widen once more: sweep for any claim on the site that describes a **security control** and
check each against `SECURITY_FINDINGS.md` as it now stands after v1.4.4. Report any other claim
whose supporting row was removed, qualified, or reclassified in that release. The kill switch is
unlikely to be the only one that drifted, because the site and the findings document are
maintained separately.

1.3 Canary the sweep. Plant one synthetic claim phrased differently from every hit you found,
confirm the sweep finds it, remove it, and confirm the file is byte-identical afterwards. A
pattern shaped like the sentences you already have proves nothing about the one you missed.

---

## TASK 2. Decide what each site claim should say

2.1 The governing decision was made in v1.4.4 and should not be relitigated: the kill switch was
**removed from the structural table** and given its own residual section. A kill switch is an
action you take, not a boundary that holds, and the fix is proven only on a hand-patched box
rather than a clean install.

2.2 So the site must not present it as a security control or a containment guarantee. It may
describe what it does, in the terms the corrected `README.md` and `SECURITY_FINDINGS.md` now use.
Quote those files and match them. Where the site says something they do not, the site is wrong.

2.3 **Structural versus advisory is sacred.** Marketing claims match only the structural column.
If a claim cannot be sourced to a structural row with evidence behind it, it does not go on the
site.

2.4 Draft the replacement wording for every hit. No em-dashes. Understate rather than overstate.
Report old and new side by side.

---

## TASK 3. Stage the change

3.1 Apply the changes in the site repo on a branch, committed, **not pushed to whatever the live
site deploys from**. State how the site deploys, what branch or action publishes it, and what
exactly would go live.

3.2 Verify the rendered result rather than the source: build or preview the site locally if it
can be done, and confirm the corrected text appears where expected and the old text appears
nowhere. If it cannot be previewed locally, say so and state what the operator should check after
publishing.

3.3 Confirm nothing else on the page changed. Diff, and report it.

---

## TASK 4. The operator card

Publishing is an irreversible public action and it is the operator's.

Print one self-contained card: what changed, the old and new wording for each hit, the exact
commands or clicks that publish it, what he should see on the live page afterwards, and what a
failure looks like. Real values substituted. Send a `PushNotification`.

**Stop there.** Do not publish.

---

## TASK 5. Cards, close-out

5.1 Card this work. Explicit per-file staging in both repos. **No tag. No push to the live
branch.** Report what was pushed and where, with `origin` hashes read from `git ls-remote`.

5.2 Close-out to `docs/session_reports/YYYY-MM-DD_site_killswitch_claims_closeout.md` in
Secure-Setup, committed, printed in full, unprompted.

Answer explicitly:

1. The full enumeration from TASK 1.1 and 1.2, with the count, and whether it exceeded five.
2. Any other site claim whose supporting evidence changed in v1.4.4.
3. The canary reading from 1.3.
4. Old and new wording for every hit.
5. Exactly what the operator's command publishes, and what is left unpublished.

5.3 End-of-session gate in full: task accounting, resource ledger, delta security sweep, delta
bug review.

---

## Challenge this prompt

Written by someone who cannot see either repo. If an instruction is wrong, ambiguous, or would
break something outside its scope, stop and report rather than building what was meant. In
particular: if the site repo's deploy mechanism means a commit to any branch publishes
automatically, stop before committing and say so.
