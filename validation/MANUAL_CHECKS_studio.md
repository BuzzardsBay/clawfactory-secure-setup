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

Open **ClawFactory Studio** from the Start menu, then click **Web access** in the top
nav.

---

## 1. The switch is present, and it says what breaking it costs

On the Web access panel, find the card headed **"Software sources ClawFactory needs"**.

- [ ] The card is there.
- [ ] It carries a **Switch off** button (so the switch currently reads ON).
- [ ] The text beside it says switching it off **stops your agent fetching code from
      GitHub and npm**.
- [ ] The text says it **does NOT stop skill installation**, and gives the reason: the
      skill hub shares a network address with ClawFactory's own site.
- [ ] The same text says it **does not affect the AI provider**.

**READ THIS BEFORE TICKING, because this check changed direction.** It used to require
the sentence "stops skill installation". That sentence was measured FALSE on cfv-169: a
real `openclaw skills install` completes with the switch off, because `clawhub.ai`
resolves to an address it shares with `openclaw.ai`, which is a permanent base host no
toggle can revoke. The claim was stronger than the mechanism, so v1.4.0 removed it.

So: if the panel still says the switch **stops skill installation**, that is a **FAIL**
now. It is the old copy, and it would mean the shipped Studio is not the rebuilt one.

The breakage sentence about GitHub and npm is still load-bearing and still mandatory.
Turning the switch off breaks real features, and the failure shows up as a network
timeout deep inside WSL that cannot be made to name this panel. A missing or reworded
GitHub-and-npm sentence is a **FAIL**, even if the switch works.

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
