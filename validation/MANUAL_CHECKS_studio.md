# By-hand Studio checks (Studio panel render verification)

Seven checks, all in ClawFactory Studio on the VM over RDP.

**Updated 2026-08-23 for v1.4.0 and Studio 1.3.1.** Checks 1 and 6 were stale:
check 1 asked you to confirm a sentence this release deliberately REMOVED, and
check 6 named the old version numbers. Check 7 is new. Every close-out before
this one called these "five checks" while the file has always held six; the
count is now stated once, here, and it is seven.

**Why by hand.** Every other test in this run reads the underlying artefact through the
root channel. These seven are about what a person actually SEES, and a renderer that
silently failed to draw a control would pass every structural check while shipping a
panel nobody can use. Studio is never asked whether it worked; you are.

**Time: about six minutes.** Nothing here has a timer, so there is no rush once you are
in, and no need to do it in one sitting.

---

## Before you start

Open **ClawFactory Studio** from the Start menu.

### A. The SMTP credential, FIRST, before any of the checks below

Go to the **send / approvals** setup and enter the throwaway Gmail app password.

**This is first on purpose.** It and the panel checks are both Studio actions, and if a
check surfaces something and Studio gets closed to chase it, the credential never lands and
four blocked rows stay blocked: `S.4`, `S.4leak`, `S.5` and phase 3b. Doing it first means
the trip is worth its full value even if everything after it goes sideways.

The password is never typed into a script, a transcript, or anything I can see. You enter it
into the panel yourself and it goes to a root-owned broker.

### B. Then the checks

Click **Web access** in the top nav and work through 1 to 7 below.

### C. When you are done, LEAVE STUDIO RUNNING

Phase 5 measures the Studio IPC bridge and it VOIDed on this box with `processes=0`,
refusing to report five vacuously-true passes about a bridge that was not there. It re-runs
against a live Studio and costs you nothing extra. Just tell me it is open.

---

## 1. The switch is present, and it says what breaking it costs

On the Web access panel, find the card headed **"Software sources ClawFactory needs"**.

- [ ] The card is there.
- [ ] It carries a **Switch off** button (so the switch currently reads ON).

**Now compare the paragraph beside it against this, word for word.** It should match:

> Your agent can reach the skill hub, GitHub and npm. Switching this off stops your agent
> fetching code from GitHub and npm. It does not stop skill installation: the skill hub
> shares a network address with ClawFactory's own site, which stays reachable and which
> this switch does not cover. It does not affect the AI provider your agent talks to.

- [ ] Matches, word for word.

Punctuation note so you do not fail it on nothing: the apostrophe in "ClawFactory's"
renders as a curly quote. That is expected.

**THIS IS A PRESENCE CHECK, NOT AN ABSENCE CHECK, AND THE DIFFERENCE IS THE POINT.** An
earlier draft of this check only asked you to confirm the old claim was GONE. A panel with
no breakage text at all, or a half-edited sentence, would have sailed through it. An absence
check with no positive control is exactly the shape the automated harness has spent a month
removing, and here it is worse, because a human running the check is the one place the phase
runner cannot catch it. So the check is now the same shape as check 2: transcribe and
compare.

Three ways this fails, all of them **FAIL**:

- The paragraph says the switch **stops skill installation**. That is the OLD copy. It was
  measured false on cfv-169, where a real `openclaw skills install` completed with the switch
  off because `clawhub.ai` shares an address with the permanently-allowed `openclaw.ai`. Its
  presence means the shipped Studio is not the rebuilt one.
- The GitHub-and-npm sentence is missing or reworded. That one is load-bearing: switching off
  breaks real features and the failure surfaces as a network timeout deep inside WSL that
  cannot be made to name this panel. Without the sentence the control ships as a support
  problem.
- The paragraph is absent, truncated, or says only some of it.

## 2. The footnote is the ratified text, word for word

At the bottom of the panel, compare against this. It should match exactly:

> A site you have not added is not reachable. Your agent can always reach the AI provider
> it talks to. It can also reach the software sources ClawFactory needs, which are GitHub
> and npm, unless you switch them off above. Matching is by network address rather than by
> name, so allowing a site also allows anything else served from the same address.
> Removing a site takes effect immediately.

- [ ] Matches, word for word.

The clause that matters most is **"allowing a site also allows anything else served from
the same address"**. The previous version omitted it and only mentioned the provider,
which understated the residual in the direction that flatters us. If that clause is
absent, it is a **FAIL** regardless of how the rest reads.

## 3. Add a destination, and see the panel say so

- [ ] Type `docs.python.org` into the box and click **Allow**.
- [ ] A green line appears saying your agent can now read it.
- [ ] The site appears in the list below, with a **Remove** button.

## 4. Bad input is refused, and the message is usable

Try each of these and click Allow. Each should be **refused with a readable message**,
not accepted and not a stack trace:

- [ ] `https://example.com` (has a scheme)
- [ ] `*.example.com` (a wildcard)
- [ ] `example.com:8443` (has a port)

## 5. Remove it again

- [ ] Click **Remove** on `docs.python.org`.
- [ ] It disappears from the list and the panel says it is no longer reachable.

Leave the list **empty** when you are done, so the box is back in its shipped state.

## 6. The home route and the header

- [ ] Click the lobster or navigate to the home page.
- [ ] It does **NOT** say "Studio backend unreachable" anywhere. That sentence was
      false in the shipped product (there is no backend; it was retired) and it is what
      caused a working Studio to be declared broken twice. Its presence is a **FAIL**.
- [ ] The page shows the running version as **1.3.1** (Studio's own version, which is
      deliberately NOT the same as the ClawFactory installer's version, which is 1.4.0).
      If it still says 1.3.0, the shipped payload is the OLD Studio and that is a **FAIL**.
- [ ] In the top bar, the version and the word **Templates** are visibly **separated**,
      not run together as `v1.3.1Templates`. Narrow the window if you want to check it
      holds at smaller widths.

## 7. The footer, which carries two corrected claims

At the very bottom of any Studio page:

- [ ] The left side reads **Frontier Automation Systems LLC** and **Apache-2.0**.
      If it says **PolyForm Perimeter 1.0.0** or **MIT licensed**, that is a **FAIL**:
      both are old, and MIT in particular was a stale string in a built bundle that
      disagreed with its own source for months.
- [ ] The right side says the sandbox **runs on your machine** AND that your agent
      **talks to a hosted AI model**.

The second half is the one that matters. It used to read "runs entirely on your machine",
which sitting next to a licence reads as a claim about your DATA, and that claim is false:
every turn goes to the hosted model you chose, carrying whatever the agent read. If the
hosted-model half is missing, that is a **FAIL**.

---

## What to tell me

Just the numbers that failed, if any, and what you saw instead. If everything passed,
"all seven pass" is enough.

**Do not** switch the software-source toggle off as part of this. The automated suite
toggles it in both directions and leaves it on deliberately, and a manual flip in between
would make those results hard to read.
