# By-hand Studio checks (Studio panel render verification)

Ten checks, all in ClawFactory Studio on the VM over RDP. This is matrix row 11.

**Updated 2026-08-27 for the v1.4.4 build.** Everything quoted below was
verified against the app.asar this build actually ships (sha256 `a64a118f...2d2a49e`),
not against the source and not against intention: 25 of 25 expected strings PRESENT,
11 of 11 retired strings ABSENT, with a positive control confirming the bundle was
readable and a negative sentinel confirming the search was not matching everything.

Five things changed since the v1.4.0 run, and each one is a defect in the previous
version of this file rather than a preference:

1. **The address count is no longer a fixed number.** Check 1c used to tell you to expect
   `On. 28 network addresses reachable` and your panel read `On. 25 network addresses
   reachable.` The count is re-resolved from DNS and drifts between refreshes, so it was
   never a value to quote. It now asserts a NONZERO count and the exact unit wording.
2. **The Studio version moved to 1.3.2**, so checks 6 and 7 quote that.
3. **Check 8 is new**: the corrected OFF notice from card #274, as a presence check with
   its text quoted word for word.
4. **Checks 9 and 10 are new**: the honest empty states from card #275, and the way back
   to the home route from card #273.
5. **Check 6 no longer tells you not to click the lobster.** It is a link now. The check
   asks you to click it.

Earlier passes: the SMTP step was removed (it asked for a credential root can write, and
blocked four rows on a person for no reason), every check says where to click and quotes
the expected text literally, and the two absence-only assertions were paired with
positive controls. See the audit note at the bottom.

**Why by hand.** Every other test in this run reads the underlying artefact through the
root channel. These seven are about what a person actually SEES, and a renderer that
silently failed to draw a control would pass every structural check while shipping a panel
nobody can use. Studio is never asked whether it worked; you are.

**Time: about nine minutes.** Nothing in checks 1 to 10 has a timer.

---

## Before you start

**Nothing is asked of you before the checks.** The box is already configured. What is set,
and what you should therefore expect to see, is in the handover card.

Open **ClawFactory Studio** from the Start menu.

**CHECK 8 ASKS YOU TO SWITCH THE SOFTWARE-SOURCE TOGGLE OFF AND BACK ON, and that is the
only place in this file that touches it.** Earlier versions said never to move it, because
the automated suite toggles it in both directions and a manual flip in between made those
results hard to read. Card #274 is about the message that appears at the moment you move
it, and there is no other way for a person to see that message. So: do checks 1 to 7
first, then check 8, and leave the switch ON when you are done. If you are running this
alongside the automated toolchain suite, say when you did check 8 so the two can be read
in order.

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
1c the exact line you see under the paragraph, copied out, e.g. On. 25 network addresses reachable.
2  PASS / FAIL   (if FAIL, the exact footnote you see)
3  PASS / FAIL   (if FAIL, what appeared instead)
4  PASS / FAIL   (if FAIL, which of the three inputs, and what happened)
5  PASS / FAIL   (if FAIL, what the list shows afterwards)
6  PASS / FAIL   (if FAIL, which bullet, and the exact text)
7  PASS / FAIL   (if FAIL, the exact footer text, both sides)
8  PASS / FAIL   (copy out BOTH messages you saw, off and on, exactly)
9  PASS / FAIL   (if FAIL, which panel, and the exact text)
10 PASS / FAIL   (if FAIL, what happened when you clicked)
Toggle left ON: YES / NO
Studio left running: YES / NO
```

---

## 1. The software-sources card, and what breaking it costs

**Where:** Studio, top nav, click **Web access**. The card is headed
**"Software sources ClawFactory needs"**.

- [ ] 1a. The card is there.
- [ ] 1b. It carries a button reading **Switch off** (so the switch currently reads ON).
- [ ] 1c. Under the paragraph there is a line of the form
      **`On. N network addresses reachable.`** — where **N is any number greater than
      zero**. Copy the line out exactly into the results block; do not judge the number.

**DO NOT EXPECT A PARTICULAR NUMBER, AND THIS IS A CORRECTION TO THIS FILE RATHER THAN
GUIDANCE.** On cfv-174 the handover card told the operator to expect
`On. 28 network addresses reachable` and his panel read `On. 25 network addresses
reachable.` That was a defect in the card, not in the product: the count comes from DNS
re-resolved on a five-hourly cycle and against hosts that answer from rotating pools, so
it legitimately differs between two readings minutes apart. Quoting a fixed number invites
a false FAIL on a healthy box, and worse, invites the next person to explain away a real
one.

**What DOES fail here:**

- The count is **zero** — `On. 0 network addresses reachable.` The switch reads on with
  nothing behind it. The panel should be showing its own amber warning in that case;
  quote both.
- The line reads **`Off. GitHub and npm are not reachable.`** — the switch is off when it
  should be on. Stop and say so; checks 3 to 5 are still fine but check 8 assumes it
  starts on.
- The unit wording differs from `network address` / `network addresses`, or the word
  `reachable` is missing. That is a copy change nobody recorded.

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

**Where:** the home route is the screen Studio opens on. If you have navigated away,
**click the lobster or the title in the top-left to get back** — see check 10, which is the
same click made into an assertion.

**This instruction is the opposite of what this file said last time, and deliberately.**
Until v1.4.1 the lobster was a bare `<span>` and the title a plain `<h1>`, and the nav
carried no Home entry, so once you left the home route there was no way back by clicking.
The operator reported it, it went into the v1.3.5 close-out (section 6, item 5) and was
never carded, and he hit it again by hand on cfv-174 while following this very file. It is
carded now (#273) and fixed in this build. If clicking the title does NOT take you home,
that is check 10 failing and it means the shipped Studio is not this build.

**First, what the page MUST show.** This is the positive control, and it is here because
the bullet after it is an absence check: a page that failed to render at all, or rendered
blank, would satisfy "does not say Studio backend unreachable" perfectly.

- [ ] 6a. The heading **ClawFactory Studio**.
- [ ] 6b. A green status pill reading **`ClawFactory Studio v1.3.2`** with
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

- [ ] 6f. The version reads **1.3.2**. This is Studio's own version and it is deliberately
      NOT the same as the ClawFactory installer's version, which is 1.4.4. **If it says
      1.3.1 or 1.3.0, the shipped payload is an OLD Studio and that is a FAIL** — and it
      means checks 8, 9 and 10 are testing the wrong artifact, so record it and stop.
- [ ] 6g. In the top bar, the version and the word **Templates** are visibly
      **separated**, not run together as `v1.3.2Templates`. Narrow the window if you want
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

## 8. The message you get at the moment you move the switch

**Where:** back on the **Web access** panel, the **Software sources ClawFactory needs**
card. This is the only check in this file that moves the toggle. Do checks 1 to 7 first.

**Why this exists.** The paragraph on this card (check 1) and the message that appears
when you *move* the switch are two different pieces of copy, and until v1.4.1 they said
opposite things — on the same screen, three lines apart. The paragraph said the switch does
not stop skill installation; the message said it does. cfv-169 measured the message false
by completing a real `openclaw skills install` with the switch off. Check 1 could never
have caught it, because check 1 only ever reads the paragraph.

- [ ] 8a. Click **Switch off**. Wait for the button to stop saying **Applying…**.
- [ ] 8b. A green message appears. Compare it against this, word for word:

> Your agent can no longer fetch code from GitHub or npm. This does not stop skill
> installation: the skill hub shares a network address with ClawFactory's own site, which
> this switch does not cover. Its AI provider is unaffected.

- [ ] 8c. The line under the paragraph now reads **`Off. GitHub and npm are not
      reachable.`**
- [ ] 8d. Click **Switch on**. A green message appears reading, word for word:

> Your agent can reach the skill hub, GitHub and npm again. Its AI provider is unaffected.

- [ ] 8e. The line under the paragraph is back to **`On. N network addresses reachable.`**
      with N greater than zero. **N will probably NOT be the number you saw at check 1c.
      That is expected** — the set is flushed and re-resolved when you switch it on.
- [ ] 8f. **Leave the switch ON.**

Punctuation note, same as check 1: the apostrophe in "ClawFactory's" renders as a curly
quote. Not a fail.

**THIS IS A PRESENCE CHECK. Copy both messages out in full**, pass or fail, so the wording
is on record. Three ways it FAILS:

- The OFF message says **`Skill installation is now off`**. That is the old, false copy and
  its presence means the shipped Studio is not this build.
- The ON message says the agent **can install skills ... again**. Also old copy, and wrong
  in the other direction: it implies the switch had stopped skill installation.
- No message appears at all, or it appears and the panel's own paragraph and status line do
  not change with it. A notice that fires without the state changing is worse than no
  notice.

## 9. The panels that are not in this release say so

**Where:** the top nav. Click each of these in turn: **Templates**, **Files**, **Activity**,
**Chat**, **Agents**, **Skills**, **Settings**.

**Why this exists.** Studio's HTTP backend was retired when it became a desktop app. Four
panels were rewired and work; the rest still called the retired transport and each rendered
its own failure banner naming an internal scaffold and a dead endpoint — e.g. *"Couldn't
load settings. This panel is not wired in the desktop shell scaffold yet ... (GET
/api/settings)"*. Templates is the FIRST nav item, so that could be a new customer's first
impression. Nothing had failed; the feature is not here.

For **each** of the seven:

- [ ] 9a. The page shows a heading naming the panel, then a line reading exactly
      **`<Panel> is not part of this release.`** (e.g. `Settings is not part of this
      release.`)
- [ ] 9b. A short sentence saying what the panel will do.
- [ ] 9c. A line containing **`Nothing here failed and nothing is misconfigured`**.
- [ ] 9d. A second card headed **`What you can use today`** listing **Workspace**,
      **Recently deleted**, **Approvals** and **Web access** as links.
- [ ] 9e. Click one of those links and confirm it goes to a working panel.

**FAIL looks like:** any of the seven still shows a red error; any of them mentions
**`scaffold`**, **`/api/`**, **`backend`** or **`unreachable`**; a blank page; or a page
that says only "Page not found."

**9e is the positive control and it is not optional.** 9a to 9d are satisfied by a page
that renders the empty state and nothing else in the app working at all. 9e proves the
shell still navigates.

## 10. The way back to the home route

**Where:** anywhere that is not the home route. Use **Settings** from check 9.

- [ ] 10a. From the Settings panel, click the **lobster** in the top-left.
- [ ] 10b. You land on the home route: the heading **ClawFactory Studio** and the paragraph
      beginning **"This is where you decide what your agent is allowed to do."**
- [ ] 10c. Go to **Web access**, then click the **words "ClawFactory Studio"** in the
      top-left (not the lobster). You land on the home route again.

**Why both halves.** The whole title block is one link, so either click should work, and
the operator's instinct on two separate boxes was to click the lobster. Testing only one of
them would leave the other unmeasured.

**FAIL looks like:** either click does nothing; the cursor does not change to a hand over
the title block; or you land somewhere that is not the home route. Before this build there
was no click path home at all — the operator had to restart Studio.

---

## Audit note: the shape of every assertion in this file

Audited one assertion at a time on 2026-08-24 (second pass, all ten checks). The rule
applied: **an absence-only assertion is not permitted to stand alone.** A page that failed
to render, rendered blank, or never loaded satisfies every "does not say X" perfectly, and
a renderer that silently drew nothing is the exact failure this by-hand exercise exists to
catch. Where an absence matters, it is kept — after a positive assertion, and stated as
meaning nothing until that passes.

| Check | Shape now | What changed this pass |
| --- | --- | --- |
| 1a–1b | presence of a card and a button | unchanged |
| **1c** | **was a presence check against a WRONG CONSTANT** | now asserts nonzero + the exact unit string, never a number. See below. |
| 1d | presence, word for word | unchanged; re-verified against the shipped `app.asar`, not the source |
| 2 | presence, word for word, with one clause named as decisive | unchanged |
| 3 | presence of two exact strings | unchanged; still named as the positive control for 4 and 5 |
| 4 | presence of a refusal, ×3 inputs | unchanged; its control (check 3) stated rather than implied |
| 5 | presence + a survival assertion on the seeded entry | unchanged |
| 6a–6d | presence, four assertions | unchanged; 6b's version string updated to 1.3.2 |
| 6e | absence, **behind 6a–6d** | unchanged shape; still states it means nothing until 6a–6d pass |
| 6f–6g | presence, plus a named wrong version | 1.3.1 → 1.3.2; the named wrong versions are now 1.3.1 and 1.3.0 |
| 7 | presence both sides, plus a named wrong licence | unchanged |
| **8** | **NEW.** presence, word for word, ×2 messages, plus a state assertion | new for card #274 |
| **9** | **NEW.** presence ×4 per panel, ×7 panels, + a navigation control (9e) | new for card #275 |
| **10** | **NEW.** two positive click assertions | new for card #273 |

**Three defects in this file were found and fixed this pass.**

1. **Check 1c asserted a constant that was never constant.** It told the operator to expect
   `On. 28 network addresses reachable`; his panel read `On. 25 network addresses
   reachable.` and he correctly reported the mismatch. The count is re-resolved from DNS
   against hosts behind rotating pools, so two readings minutes apart legitimately differ.
   A check that fails on a healthy box teaches the next person to explain away the day it
   fails on a sick one. Now: nonzero, plus the exact unit wording, plus the number copied
   out as evidence rather than judged.
2. **Check 6 told the operator not to click the lobster**, because it was not a link. He
   had already reported that; it was recorded in a close-out, never carded, and this file
   was rewritten in the same session that recorded it without the instruction being fixed.
   He then hit it again by hand. The product side is fixed (#273) and check 10 now asserts
   the click works.
3. **Check 6b and 6f quoted version 1.3.1**, which this build no longer ships. Both now
   quote 1.3.2, verified against the built bundle rather than against intention — the
   failure mode being avoided is a check that asserts copy no artifact produces, which
   turns a green run into a test of nothing.

**A note on checks 8 and 9, which are the reason this file grew.** Both cover ground no
automated probe can. Check 8's subject is a TRANSIENT message that exists only in the
instant a person moves a control; nothing in the automated suite moves it and watches. And
check 9's subject is what a new customer sees on their first click, which is a judgement
about honesty rather than a string comparison — the string comparison is there so the
judgement has something to stand on.
