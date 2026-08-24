# By-hand Studio checks (Studio panel render verification)

Seven checks, all in ClawFactory Studio on the VM over RDP. This is matrix row 11.

**Updated 2026-08-24 for the v1.4.0 completion run.** Three things changed and each one
is a defect in the previous version of this file, not a preference:

1. **The SMTP step is gone.** It asked the operator to type a credential that root can
   write, and it blocked four rows on a person for no reason. The sink credential is now
   configured from the root tooling before the box is handed over. Nothing about SMTP is
   asked of you.
2. **Every check now says where to click and quotes the expected text literally**, so the
   job is comparing strings rather than judging whether copy is good.
3. **The two remaining absence-only assertions were paired with positive controls.** Check
   1 was converted last session. Check 6's "does not say Studio backend unreachable" is the
   other one, and it now names what the page must positively show. See the audit note at
   the bottom.

**Why by hand.** Every other test in this run reads the underlying artefact through the
root channel. These seven are about what a person actually SEES, and a renderer that
silently failed to draw a control would pass every structural check while shipping a panel
nobody can use. Studio is never asked whether it worked; you are.

**Time: about six minutes.** Nothing in checks 1 to 7 has a timer.

---

## Before you start

**Nothing is asked of you before the checks.** The box is already configured. What is set,
and what you should therefore expect to see, is in the handover card.

Open **ClawFactory Studio** from the Start menu.

**Do not switch the software-source toggle off as part of this.** The automated suite
toggles it in both directions and leaves it on deliberately, and a manual flip in between
would make those results hard to read. Checks 1 to 7 never require you to move it.

**When you are done, LEAVE STUDIO RUNNING.** Phase 5 measures the Studio IPC bridge and it
VOIDed on the previous box with `processes=0`, refusing to report five vacuously-true
passes about a bridge that was not there. It re-runs against a live Studio and costs you
nothing extra. Just say it is open.

---

## Where to record results

Fill this in and paste it back. A number and a word is enough for a pass; for a fail, the
exact wording you saw.

```
1  PASS / FAIL   (if FAIL, the exact paragraph you see)
2  PASS / FAIL   (if FAIL, the exact footnote you see)
3  PASS / FAIL   (if FAIL, what appeared instead)
4  PASS / FAIL   (if FAIL, which of the three inputs, and what happened)
5  PASS / FAIL   (if FAIL, what the list shows afterwards)
6  PASS / FAIL   (if FAIL, which bullet, and the exact text)
7  PASS / FAIL   (if FAIL, the exact footer text, both sides)
Studio left running: YES / NO
```

---

## 1. The software-sources card, and what breaking it costs

**Where:** Studio, top nav, click **Web access**. The card is headed
**"Software sources ClawFactory needs"**.

- [ ] 1a. The card is there.
- [ ] 1b. It carries a button reading **Switch off** (so the switch currently reads ON).
- [ ] 1c. Under the paragraph there is a line reading **On.** followed by a count of
      network addresses. The handover card tells you the number to expect.

**Now compare the paragraph beside it against this, word for word:**

> Your agent can reach the skill hub, GitHub and npm. Switching this off stops your agent
> fetching code from GitHub and npm. It does not stop skill installation: the skill hub
> shares a network address with ClawFactory's own site, which stays reachable and which
> this switch does not cover. It does not affect the AI provider your agent talks to.

- [ ] 1d. Matches, word for word.

Punctuation note so you do not fail it on nothing: the apostrophe in "ClawFactory's"
renders as a curly quote. That is expected and is not a fail.

**THIS IS A PRESENCE CHECK, NOT AN ABSENCE CHECK, AND THE DIFFERENCE IS THE POINT.** An
earlier draft of this check only asked you to confirm the old claim was GONE. A panel with
no breakage text at all, or a half-edited sentence, would have sailed through it. An
absence check with no positive control is exactly the shape the automated harness has spent
a month removing, and here it is worse, because a human running the check is the one place
the phase runner cannot catch it. So the check is now the same shape as check 2:
transcribe and compare.

**Three ways this FAILS:**

- The paragraph says the switch **stops skill installation** with no "does not". That is
  the OLD copy. It was measured false on cfv-169, where a real `openclaw skills install`
  completed with the switch off because `clawhub.ai` shares an address with the
  permanently-allowed `openclaw.ai`. Its presence means the shipped Studio is not the
  rebuilt one.
- The GitHub-and-npm sentence is missing or reworded. That one is load-bearing: switching
  off breaks real features and the failure surfaces as a network timeout deep inside WSL
  that cannot be made to name this panel. Without the sentence the control ships as a
  support problem.
- The paragraph is absent, truncated, or carries only some of it.

## 2. The footnote is the ratified text, word for word

**Where:** same Web access panel, scroll to the very bottom of the panel content.

Compare against this. It should match exactly:

> A site you have not added is not reachable. Your agent can always reach the AI provider
> it talks to. It can also reach the software sources ClawFactory needs, which are GitHub
> and npm, unless you switch them off above. Matching is by network address rather than by
> name, so allowing a site also allows anything else served from the same address.
> Removing a site takes effect immediately.

- [ ] 2a. Matches, word for word.

The clause that matters most is **"allowing a site also allows anything else served from
the same address"**. The previous version omitted it and only mentioned the provider,
which understated the residual in the direction that flatters us. **If that clause is
absent, it is a FAIL regardless of how the rest reads.**

## 3. Add a destination, and see the panel say so

**Where:** same Web access panel, the box under the heading **"Allow a site"**. It shows
`docs.python.org` as grey placeholder text; that is a hint, not a value, so you still have
to type it.

- [ ] 3a. Type `docs.python.org` into the box and click **Allow**.
- [ ] 3b. A message appears reading exactly:
      **`Your agent can now read docs.python.org.`**
- [ ] 3c. `docs.python.org` appears in the list below, with a **Remove** button beside it.

**FAIL looks like:** no message; a message naming a different host; a red error; the
button spinning on **Adding...** and never settling; or the host not appearing in the list.
If you get a red error, quote it exactly.

**This check is also the positive control for checks 4 and 5.** If adding a good host does
not work here, then check 4's refusals prove nothing (everything is being refused) and
check 5 has nothing to remove. If 3 fails, say so and stop; 4 and 5 are not measurable.

## 4. Bad input is refused, and the message is usable

**Where:** the same **Allow a site** box. Type each of these and click **Allow**.

Each should be **refused with a short readable message in red**, and the host must NOT
appear in the list:

- [ ] 4a. `https://example.com` (has a scheme)
- [ ] 4b. `*.example.com` (a wildcard)
- [ ] 4c. `example.com:8443` (has a port)

**FAIL looks like:** the value is accepted and appears in the list; or the message is a
stack trace, a raw error code with no sentence, or blank. Quote whatever you see for each
of the three, pass or fail, so the wording is on record.

## 5. Remove it again

**Where:** the list on the Web access panel.

- [ ] 5a. Click **Remove** on the `docs.python.org` row.
- [ ] 5b. A message appears reading exactly:
      **`docs.python.org is no longer reachable.`**
- [ ] 5c. `docs.python.org` is gone from the list.
- [ ] 5d. **The list is NOT empty.** One entry remains, and the handover card names it. It
      was put there from the root tooling before you started, so that the panel had a
      persisted entry to render at load rather than only one it had just added itself.
      **Leave it. Do not remove it.**

**FAIL looks like:** the row stays; the message names a different host; or the remaining
entry from the card has vanished too.

## 6. The home route and the header

**Where:** click the lobster icon at the top left, or navigate to the home page.

**First, what the page MUST show.** This is the positive control, and it is here because
the bullet after it is an absence check: a page that failed to render at all, or rendered
blank, would satisfy "does not say Studio backend unreachable" perfectly.

- [ ] 6a. The heading **ClawFactory Studio**.
- [ ] 6b. A green status pill reading **`ClawFactory Studio v1.3.1`** with
      **`Running as a desktop app`** beside or beneath it.
- [ ] 6c. The paragraph beginning **"This is where you decide what your agent is allowed
      to do."**
- [ ] 6d. A paragraph containing **"Studio has no server and opens no network port."**

**Then the absence, which only means something once 6a to 6d have passed:**

- [ ] 6e. The page does **NOT** say **"Studio backend unreachable"** anywhere. That
      sentence was false in the shipped product (there is no backend; it was retired) and
      it is what caused a working Studio to be declared broken twice. Its presence is a
      **FAIL**.

**And the header:**

- [ ] 6f. The version reads **1.3.1**. This is Studio's own version and it is deliberately
      NOT the same as the ClawFactory installer's version, which is 1.4.0. **If it says
      1.3.0, the shipped payload is the OLD Studio and that is a FAIL.**
- [ ] 6g. In the top bar, the version and the word **Templates** are visibly
      **separated**, not run together as `v1.3.1Templates`. Narrow the window if you want
      to check it holds at smaller widths.

## 7. The footer, which carries two corrected claims

**Where:** the very bottom of any Studio page. Two spans, left and right.

- [ ] 7a. The left side reads **`Frontier Automation Systems LLC`** and **`Apache-2.0`**,
      separated by a dot.
      **If it says `PolyForm Perimeter 1.0.0` or `MIT licensed`, that is a FAIL.** Both are
      old, and MIT in particular was a stale string in a built bundle that disagreed with
      its own source for months.
- [ ] 7b. The right side reads **`Wraps OpenClaw 2026.4+`**, then a dot, then
      **`the sandbox runs on your machine; your agent talks to a hosted AI model`**.

The second half of 7b is the one that matters. It used to read "runs entirely on your
machine", which sitting next to a licence reads as a claim about your DATA, and that claim
is false: every turn goes to the hosted model you chose, carrying whatever the agent read.
**If the hosted-model half is missing, that is a FAIL** even if everything else on the line
is right.

---

## Audit note: which of these were absence-only, and what was done

Checked all seven, one assertion at a time, on 2026-08-24.

| Check | Shape | Action |
| --- | --- | --- |
| 1 | was absence-only; converted last session | verified against the shipped source, unchanged |
| 2 | presence, word for word | unchanged |
| 3 | presence | expected strings quoted literally; named as the control for 4 and 5 |
| 4 | presence of a refusal | its positive control (check 3) now stated rather than implied |
| 5 | mixed | expected strings quoted; the surviving seeded entry is now an assertion |
| 6 | **bullet 6e was absence-only** | 6a to 6d added as the positive control, stated as such |
| 7 | presence, both sides, plus a named wrong version | unchanged |

**Two were absence-only, not one.** Check 1 was found and fixed last session. Check 6's
"does not say Studio backend unreachable" is the second, and it was the more dangerous of
the two, because the failure it cannot see is a page that did not render, which is the
exact failure the whole by-hand exercise exists to catch.
