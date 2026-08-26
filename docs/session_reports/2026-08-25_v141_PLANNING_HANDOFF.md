# PLANNING HANDOFF — ClawFactory v1.4.1, after the cfv-175 validation run

Written 2026-08-25 for a planning conversation that does not have this repo in front of it.
The authoritative record is `docs/session_reports/2026-08-25_v141_validation_closeout.md`
(commit `ba8c43c`); this file is the decision-shaped summary of it.

---

## 1. Where the product actually is

**v1.4.1 is built, signed, and validated on one clean box. It is not tagged, not released,
not published.**

| | |
| --- | --- |
| Signed artifact | `90c673ddaf0959418eef8b19b959894581003f0c5dbf0d78cfb2f52beb3ef398` |
| Size | 440,602,224 bytes |
| Authenticode | Valid |
| Build commit | v1.4.1 build, `3f91599` lineage; validation commits `f991828`, `c814533`, `80b2416`, `ba8c43c` |
| Newest tag on the remote | **`v1.1.0`** — no v1.2/1.3/1.4 tag has ever been cut |
| Validated on | `cfv-175`, Standard_D2s_v4, westus2, torn down |

**The two reasons v1.4.0 was refused publication are both fixed and measured on a running
machine, not argued from source.**

- `#274` — the product claimed a safety switch stopped skill installation. It does not.
  Corrected copy is now present in the shipped bundle, in the install log, and on the live
  GUI in both toggle directions.
- `#276` — a control reported a state that was not in force after a reboot. The route is now
  live after a real Windows reboot without waiting for the five-hourly refresh, and the
  reverse direction (a route the user *closed* staying closed across a boot) is proven too.

**Verdict recorded: NO — narrowly, and on coverage rather than on any defect found.**

---

## 2. The decision on the table

### Option A — one more short validation run, then publish

Four things are unmeasured. All four are cheap and all four are on one box:

1. **A clean uninstall.** `uninstall.ps1` changed in v1.4.1 and no uninstall was run.
2. **The install-time fatal read-back.** Deliberately break the boot-unit registration and
   confirm the install ABORTS with its named message. An unproven fatal may be a no-op.
3. **Matrix rows 2 and 4** — install completes with the licence host unreachable, and the
   provider gate under `-Provider later`. Both are properties of the install itself, so they
   need a second box; both touch install-path code that changed.
4. **Check 10**, two clicks — the Studio header link going home. `#273` currently has
   shipped-artifact evidence only.

**Cost:** roughly one `Standard_D2s_v4` for an hour, plus two short RDP logins.
**Outcome:** turns the NO into a yes with no argued premises left in it.

### Option B — publish now, accepting the four gaps in writing

Defensible, and the residual risk is genuinely low: the code paths are small, were reviewed
in the previous session, and their failure modes are fail-safe by construction.

**That last sentence is an argument, not a measurement, and it is exactly the kind of
argument this product exists to refuse.** If Option B is chosen, the honest thing is to say
so in the release notes rather than imply full coverage.

**The specific exposure worth weighing:** uninstall. On a free public release the uninstaller
is the first thing an unhappy user reaches for, and it is the one changed shipped file with
no evidence behind it at all.

### Option C — do not publish yet for a different reason: `#261`

See section 3. This is a product-quality judgement, not a coverage gap.

---

## 3. The finding that should shape the plan: card `#261`

**Measured for the first time on this run, with controls firing in every measurement.**

With the software-sources switch reading **ON** and a freshly-resolved address set:

```
api.github.com      connected  5 of 12 attempts
github.com          connected  2 of 5  attempts
registry.npmjs.org  connected  5 of 5   (CONTROL: the route works)
example.net         blocked    3 of 3   (CONTROL: denial works)
```

After a real Windows reboot, with the panel reading `On. 28 network addresses reachable.`:

```
toolchain route     connected  2 of 6 attempts
user's own site     connected  4 of 6 attempts
```

**Cause.** The firewall matches by IP address. The resolver samples a rotating DNS pool three
times and installs what it saw. GitHub's pool is larger than the sample, so DNS routinely
hands the agent an address that is not in the set.

**Why it matters for planning, in plain terms.** A user switches the control ON, the panel
says it is on and names a number, and the thing works about half the time. The panel's
wording admits no "sometimes". This is not a lie the way `#274` was — the switch really is
on — but it is the same *category* of problem: the interface states a binary where the
reality is probabilistic.

**It is NOT a v1.4.1 regression.** It pre-dates this build, is already carded, and v1.4.1
narrows it (three-pass resolution on read-fetch, bounded per-host retention). v1.4.1 makes it
better, not worse.

**The unadjudicated options on `#261`**, carried from earlier sessions:

- **(a)** more resolution passes — narrows, never closes; already applied.
- **(b)** ship GitHub's published address ranges — closes it for GitHub specifically, at the
  cost of a much wider allowlist and a list that goes stale.
- **(c)** resolve at connect time rather than at refresh time — architecturally different,
  and an nftables set cannot express it.
- **(d)** accept and document — change the copy so the panel stops implying certainty.

**Recommendation for the planning conversation: (d) is the cheap honest move and could ship
with v1.4.1 as a copy change.** (b) is the real fix and is a v1.5 item.

---

## 4. Everything that is proven, if the plan needs to lean on it

- Artifact identity: three independent digest derivations agree (build machine, blob storage
  readback, on-box after transfer).
- Clean install: `INSTALLER_DONE=success`, all 34 security resources present, firewall chain
  shape asserted, the new boot unit enabled with its read-back passing.
- Reboot pass: clean, 8 of 8, controls fired. The egress deny survives a full Windows reboot.
- Guard 2 (approval-gated email): **proven end to end for the first time on any build** —
  queue, approval binding, staged-hash equality, deny, replay refusal, hash-mismatch void,
  expiry, post-approval swap resistance, receipt without body, credential unreadable by the
  agent and absent from logs, argv and environ. A real message was accepted by Gmail.
- Guard 3 web access: user can add and remove sites; removal takes effect; a revoked site
  does not return after a reboot; bad input refused with readable messages.
- Studio: all seven not-in-this-release panels render an honest empty state naming no
  scaffold and no dead endpoint; the shipped `app.asar` digest matches the build-time pin.
- Harness integrity: self-test 15/15, and zero malformed verdict rows across 22 phases.

---

## 5. Known residuals that are accepted, not open questions

- **`SP.8` fails by design.** The skill hub shares an IP address with the permanently-allowed
  `openclaw.ai`, so the software-sources switch cannot make it unreachable. Documented
  address-scoping residual. Card `#277` inverts the check to assert the residual rather than
  fail on it — deliberately scheduled *after* the shipping decision, never during.
- **Door 2** (`.mjs` bypass, agent and gateway share a uid) — accepted-and-documented for v1,
  closure is a v2 item.
- **`clawagent-setup`** is archived and carries a supersession notice retracting its false
  security claims, but is still public and its *release assets* still contain that copy. This
  was verified from GitHub this session; an earlier note claiming nothing had been done was
  wrong.
- **Inno Setup 6.7.1** binaries say "Non-commercial use only". A free release plausibly sits
  inside that tier. Unadjudicated, unchanged, operator's call.

---

## 6. Open cards after this run

| Card | State | One line |
| --- | --- | --- |
| `#274` `#275` `#276` | **done** | fixed and validated this run |
| `#273` | `in_progress` | fix is in the shipped bundle; two clicks would confirm it renders |
| `#198` | open | external delivery VOID — Gmail accepted, receiving provider silently filtered |
| `#261` | open, **now quantified** | see section 3 |
| `#277` | queued | invert `SP.8` — after the shipping decision |
| `#278` | queued, widened | one-shot reachability probes are coin flips against rotating pools |
| `#280` | new | `G2.13` scan detects its own `grep` and reports a leak that does not exist |
| `#281` | new | `/proc` mounted without `hidepid`; nothing exposed today, defence-in-depth absent |
| `#282` | new | `stagebox` seeds `www.iana.org`, a host that cannot detect the defect it seeds for |
| `#283` | new | `studiowhere` registers no positive control so it always reports VOID |
| `#259` | standing | unattended validation harness — biggest cost reduction available |

---

## 7. Traps for whoever plans or runs the next box

These cost time on this run and will cost it again.

1. **`www.iana.org` cannot detect the boot-path defect.** It returns one address set forever,
   so a stale replayed set and a fresh set are identical. It is still `stagebox.ps1`'s
   default. Seed a genuinely rotating host — `outlook.office.com` worked and is in neither
   the toolchain nor provider lists — and prove the rotation on the box before relying on it.
2. **`switchprovider` needs `-ExtraFiles validation\sp-prefix-fw.sh`** or its fault injection
   never lands and all 40 rows go VOID.
3. **A single reachability attempt is a coin flip.** `TC.1c` passed and `TC.5` failed on the
   same mechanism minutes apart. Take several attempts and report the count.
4. **Never run automated probes while a human is clicking through the by-hand checks.** It
   produced a false FAIL that had to be re-derived.
5. **`phase3b` sends TWO real emails**, in test 3 and test 6. Count a probe's side effects
   before running it against a limited authorisation.
6. **One `az vm run-command` at a time**, subscription-wide. A second one returns `Conflict`
   and kills the job.
7. **The Dispatch board has ONE write endpoint**: `POST /api/agent/update`. REST verbs on
   `/api/cards/:id` return 400.
8. **Azure spend.** The two baseline images and the storage account are the standing cost in
   `clawfactory-validation` and persist between runs; the VM is not the lever. Old
   `combined-*.exe` blobs (~440 MB each, `cfv-153` through `cfv-175`) are pure accumulation
   and safely deletable — the artifacts are reproducible from the repo.

---

## 8. The one-paragraph version

v1.4.1 fixes both defects that blocked v1.4.0, and both fixes are now measured on a running
machine rather than argued from source — including the reverse direction of the boot-path fix,
which is the dangerous one and which nobody had tested. Twelve of fourteen matrix rows passed,
no product regression appeared, and every failure traced either to a known documented residual
or to a defect in the test instruments. The verdict is nonetheless NO, because a clean
uninstall was never run on a release where the uninstaller changed, and three other small
checks went unmeasured when the run ended early on a spend limit. One box and about an hour
closes all four. Separately, and independently of that decision, card `#261` is now
quantified: with the software-sources switch reading ON, the route answers roughly half the
time, and the panel says nothing about that.
