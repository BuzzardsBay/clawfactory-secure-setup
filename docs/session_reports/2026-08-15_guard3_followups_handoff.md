# Handoff: Guard 3 follow-ups, 2026-08-15

Written for whoever drafts the next work package. Self-contained: assumes no access
to this repo and no memory of the session.

Full detail, with verbatim evidence, is in
`docs/session_reports/2026-08-15_guard3_followups_closeout.md`. This document is the
part you need to decide what to build next.

---

## 1. State in one paragraph

Four things were asked for. Three are done and pushed. The fourth, a user-facing
toggle that closes the agent's route to GitHub, npm and the skill hub, is built and
its firewall behaviour is thoroughly validated, but it **cannot ship** because
switching it off currently stops the agent working, which is not what the product
says it does. Nothing was tagged or published, so no artifact carrying any of this
reached a user.

| Item | State |
| --- | --- |
| Validation harness hardening | **Done**, proven against deliberately broken inputs |
| Version discipline: ledger plus build gate | **Done**, proven in both directions |
| Studio copy: footnote, banner, header | **Done**, shipped in Studio 1.3.0 |
| Toolchain access toggle | **Blocked**, see section 3 |
| Card 197 (provider `baseUrl` override) | **Answered**, and it reopens a door, see section 4 |

Output commits: Secure-Setup `cb759de`, Studio `229ad26`.
Artifact built but **not released**: v1.3.3, signed, `5bef35dc...`.

---

## 2. What is now true that was not before

These are settled and should be treated as foundations, not revisited.

**The validation harness cannot report a pass it did not earn.** A phase runner now
enforces, mechanically rather than by author discipline: no positive control means no
PASS; a control that did not fire in the same run voids the phase and downgrades its
results; a missing precondition records VOID with a named reason instead of a product
verdict; a search for absences must first prove its target is searchable. Proven by
injecting each fault deliberately and watching it fire, 10/10, with paired controls
showing each guard discriminates rather than firing unconditionally.

**A version number identifies exactly one payload.** A repo-tracked ledger records
every shipped artifact, and the build gate refuses to sign a build whose version
already appears against a different digest. Proven both directions. It then fired for
real three times in this session, on its author, and was obeyed each time rather than
worked around.

**The Studio home route no longer claims a retired component is unreachable.** That
false banner caused a working Studio to be diagnosed as broken across three earlier
sessions.

---

## 3. The blocker, and the decision that is yours

### What was measured

On a clean install of v1.3.3, the toggle behaves correctly in every structural
respect. 27 checks passed, 7 of 7 positive controls fired:

- switch ON, the software sources are reachable for the agent uid
- switch OFF, the addresses genuinely leave the nft set AND the hosts become
  unreachable
- **switch OFF survives a real five-hourly refresh**, run against the shipped systemd
  unit, with a control proving the refresh actually ran and added other addresses
- the switch is reversible
- the agent cannot change it through any of ten channels
- the chain-shape tripwire fires when the accept rule is removed

One check failed:

> With the switch OFF, a real agent turn is refused with
> `clawfactory_gate: { blocked: true, state: "gate_error" }`, after about 4.5 minutes.

### Why that is a blocker rather than a bug to note

The panel tells the user that switching off "stops skill installation, and stops your
agent fetching code from GitHub and npm" and "does not affect the AI provider". The
measured truth is that **the agent stops working entirely**. The user makes their
decision on the strength of that sentence, so a control whose stated consequence
understates its real one is worse than no control at all.

### What is already established, so nobody repeats it

A read-only diagnostic on the same box established:

- The turn gate and spend check name **zero** network endpoints in their own source.
- The gate runs **fine** when invoked directly as root.
- The proxy logged `chat turn BLOCKED (gate_error)` on both attempts.

Conclusion: the gate is sound in isolation. The stall is **downstream, in the
gateway**, which runs as uid 1000 and is therefore subject to the firewall chain. A
long block followed by a gate timeout and a fail-safe refusal fits the timing.

**The precise host was not isolated, and was deliberately not guessed.**

### Important context for interpreting this

The same test **passed** on the previous build, but only because the toolchain hosts
were still reachable through a defect. Fixing the toggle is what exposed this
dependency. So this is not a regression introduced by the toggle; it is a
pre-existing coupling that the broken toggle had been hiding.

### The decision

Not a technical call. Three options, and the right one depends on what you want v1 to
promise:

**A. Finish it as advertised.** Identify the gateway's turn-time dependency and, if it
is infrastructure (a pricing or model-metadata lookup, say), move that one host to the
always-open set where it belongs. The toggle's user-facing meaning survives intact.
Cost: one VM run to identify, one to re-validate, plus the by-hand Studio pass. Risk:
if the dependency turns out to be the skill hub itself, this option evaporates and you
are into B or C having spent the time.

**B. Narrow the toggle and reword.** Govern GitHub and npm only, leave the skill hub
always-open, and rewrite the panel copy to match. Cost: similar, but the feature
promises less. Note the copy currently names skill installation first, so this is a
real reduction in what the user is being offered.

**C. Drop the toggle from v1.** Keep the harness, the version gate and the Studio copy,
all of which are finished. The always-open baseline stays as it is, and the existing
ratified claim sentence already names the software sources explicitly, so nothing
becomes dishonest by dropping it. Cost: none. What is lost is user control over a
route that is currently open by default anyway.

**A recommendation, for what it is worth:** spend one VM run identifying the host
before choosing. The answer collapses the decision, and without it you are choosing
between B and C on a guess. The identification is cheap and the code to do it exists.

---

## 4. Card 197, and why it reopens a door

The question was whether the bundled provider plugin honours a
`models.providers.*.baseUrl` override. If it does, a root-owned outbound proxy could
hold the provider key and enforce hostnames, closing two long-standing residuals at
once (address-scoping, and provider-key exfiltration) and settling Guard 4's shape.

The first probe returned **no**. That answer is wrong as a general claim, and the
reason matters: the shipped configuration has **no `models.providers` section at
all**, so the probe created the key it then tested.

What the plugin actually reads, found in its own code:

```
baseUrl: readStringValue(model.baseUrl)
```

So a `baseUrl` override **is** supported, at `model.baseUrl`, a property of the model
definition rather than a providers map.

**Consequence: a root-owned outbound proxy is NOT ruled out for Guard 4, and
address-scoping must not be recorded as permanently unavoidable for v1.** The first
probe's bare "no" would have closed that door and pointed Guard 4 elsewhere.

Next step is one focused probe: set `baseUrl` on the model definition the agent
actually uses, repeat the presence-only listener test, and see whether the plugin
calls the local endpoint. The listener code exists and records presence only, never a
credential value.

---

## 5. Traps worth carrying into the next prompt

Each of these cost real time this session.

**There are three places a hostname can enter the always-open firewall set**: the
install-time base list, the auxiliary list at install, and the auxiliary list in the
refresh script. A host that must be revocable has to be absent from **all three**.
Missing one is silent, and the symptom is a switch that reports success and closes
nothing.

**A revocable set must be seeded early and rebuilt from policy later.** Seeding it at
firewall time is safe because it is flushed and rebuilt on every subsequent run.
Putting the same addresses in the additively-refreshed provider set is not, because
nothing can ever remove them. Getting this backwards fails in one direction; leaving
the addresses out entirely fails in the other, and the second failure looks like a
21-minute install hang rather than a firewall problem.

**Flush-and-rebuild loses an accumulated address pool.** The provider set accumulates
over hours of additive refreshes; a set that is rebuilt each run holds only one
lookup's worth. Hosts with rotating pools (`api.github.com` alternates between two
addresses) then become intermittently unreachable while the switch reads on.
Mitigated by resolving several times and taking the union, which keeps revocability.

**`az vm run-command` runs as SYSTEM and cannot touch WSL.** Every WSL-level probe has
to go through the interactive session's job runner. This is easy to forget and fails
with a confusing error.

**A fault injection that cannot inject scores a false pass.** `nft` refuses to delete
a set that a rule still references, so a "delete the set and check the tripwire fires"
test silently tests nothing. Every fault injection now needs its own control proving
the fault landed.

---

## 6. What is NOT verified, and must not be described as passing

- **The reboot pass** for the toggle. Deliberately not run: the pre-reboot control
  already fails, so a post-reboot run would re-measure a known-broken control.
- **The by-hand Studio panel checks.** Deliberately not run: they verify panel copy
  that is now known to be wrong and must change. A checklist exists at
  `validation/MANUAL_CHECKS_studio.md`, about five minutes, no timers on anything in
  it. Run it once the copy is final, not before.

Neither is a shortfall against the work package; both are deferred because verifying
a sentence that is about to be rewritten produces a result that means nothing.

---

## 7. Suggested shape for the next work package

1. **Decide A, B or C** from section 3, ideally after one identification run.
2. If A or B: fix, revise the panel copy to match reality, rebuild, re-run
   `validation/interim-v130-toolchain.ps1`, then the reboot pass, then the by-hand
   Studio checks on the final copy.
3. **Independently**, run the card 197 follow-up. It is small, read-only, and it
   determines Guard 4's entire shape, so it should not wait behind the toggle.
4. Anything built should assume the hardened harness: phases must register a positive
   control, and a phase that measures nothing now exits 4 rather than 0.

---

## 8. Ledger

Three VMs created, three deleted, resource group verified back to its exact starting
state by unfiltered listing. Four builds recorded in the released-artifact ledger
(1.3.0, 1.3.1, 1.3.2 superseded; 1.3.3 built and signed but not released). No SMTP
credential was requested, used or revoked. The provider API key never crossed a tool
boundary or entered a transcript. No tag, no publish.
