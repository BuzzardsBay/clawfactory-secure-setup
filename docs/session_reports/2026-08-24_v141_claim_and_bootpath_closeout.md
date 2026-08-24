# CLOSE-OUT: v1.4.1, claim correction and boot-path fixes, build and sign

Session 2026-08-24 (second of the day). Cards `#273`, `#274`, `#275`, `#276`.
No VM, no validation run, no tag, no GitHub release, no publish.

**STATUS: COMPLETE. Every task in the brief was executed. A signed v1.4.1 installer
exists, all seven build gates green, and it has NOT been validated.**

No fitness verdict is offered here, and that is deliberate: this session measured code,
not a running product. Section 11 says what the next job has to measure.

---

## 0. Task accounting

| Task | State |
| --- | --- |
| 0.1 Pre-flight, four checks | DONE, reported before any code was written |
| 0.2 Push the ten unpushed commits | DONE, `8174d3f..653667a` |
| 0.3 Delete the superseded prompt file | NOT IN TREE, reported |
| 0.4 Four cards to `in_progress` | DONE via the Dispatch API from PowerShell |
| 1 Verdict provenance sweep, rows 1 to 14 | DONE, **14 SOUND, 0 SUSPECT** |
| 2 #274 Studio toggle notices | DONE, both corrected, enumerated + canaried |
| 3 #274 Secure-Setup claim sites | DONE, **four sites, not the two the card named** |
| 4 #276 toolchain boot path | DONE, and the brief's premise corrected |
| 5 #276 read-fetch boot path | DONE, plus the multi-pass loop it never had |
| 6 #275 route enumeration and empty states | DONE, **nine routes, not the two the card named** |
| 7 #273 way back to the home route | DONE, measured from the accessibility tree |
| 8 Checklist update and full audit | DONE, seven checks to ten, three defects fixed |
| 9 Version, build, sign, ledger | DONE, seven gates green, ledger row appended |
| 10 Cards, commits, close-out | DONE |

---

## 1. TASK 1: the verdict provenance table

Instrument defect 7 (the dispatcher retrieving `<probe>-results.json` when the run wrote
`<probe>-results-postreboot.json`) and instrument defect 4 (phase 3 parsing `key=value`
output as JSON) were both fixed in-session last time and neither had its blast radius
measured. Measured now, **from the retained results files under `validation-runs/`, not
from reasoning**.

Results-file naming enumerated from source first, because the answer depends on it:

```
interim-v120-phase4.ps1            phase4-results-postreboot.json  phase4-results.json
interim-v120-phase6.ps1            phase6-results-postreboot.json  phase6-results.json
interim-v130-toolchain.ps1         Complete-Phase -ResultsJson "C:\cfv\toolchain-results-$tag.json"
interim-v135-switchprovider.ps1    Complete-Phase -ResultsJson "C:\cfv\switchprovider-results-$tag.json"
interim-v120-phase1.ps1            phase1-results.json
interim-v135-providergate.ps1      providergate-results.json
interim-v140-swapstruct.ps1        swapstruct-results.json
```

| # | Test | Session | Verdict read from | `-PostReboot`? | phase-3 id/hash? | Verdict |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | Clean install, all pins, wizard | cfv-174 | `cfv-174-phase1/phase1-results.json` | no — probe has no such switch | no | **SOUND** |
| 2 | Install with the licence host unreachable | cfv-173 | `cfv-173-20260823-114742/phase1-results.json` | no | no | **SOUND** |
| 3 | Provider gate healthy + blocked control | cfv-170 | `cfv-170-providergate-20260823-094737/providergate-results.json` | no | no | **SOUND** |
| 4 | Provider gate under `-Provider later` | cfv-171 | `cfv-171-providergate-deferred-20260823-105932/providergate-deferred-results.json` | no | no | **SOUND** |
| 5 | `SP.4a/4b` no toolchain address after a switch | cfv-170 | `cfv-170-switchprovider-20260823-095155/switchprovider.out.txt` | no | no | **SOUND** |
| 6 | `SP.5a` toggle OFF, unreachable after a switch | cfv-170 | same transcript | no | no | **SOUND** |
| 7 | `SP.6a` CONTROL, toggle ON, reachable | cfv-170 | same transcript | no | no | **SOUND** |
| 8 | `TC.3` real agent turn, toggle OFF | cfv-174 | `cfv-174-toolchainpost-20260824-133318/toolchainpost-results.json` | **yes, and the file self-identifies** | no | **SOUND** |
| 9 | `TC.1,2,4–8` regression | cfv-174 | same file | yes, self-identified | no | **SOUND** |
| 10 | Reboot pass | cfv-174 | `cfv-174-phase4real-20260824-132457/phase4real-results.json` + the toolchain file above | yes, self-identified | no | **SOUND** |
| 11 | Seven by-hand panel checks | cfv-174 | operator screenshots, quoted verbatim in the prior close-out | n/a | no | **SOUND** |
| 12 | Harness self-test | cfv-170 | `cfv-170-selftest-20260823-101601/selftest.out.txt` | no | no | **SOUND** |
| 13 | Zero malformed verdict rows | all | re-derived this session across all eight retained results files | n/a | no | **SOUND** |
| 14 | Step 7, assembled build | cfv-174 | `cfv-174-phase3b-20260824-110823/phase3b-results.json` + `cfv-174-swapstruct-20260824-121108/swapstruct-results.json` | no | **yes — but read POST-fix** | **SOUND** |

**Direct evidence, defect 7.** The stale artefact is preserved and it is not what any row
was read from:

```
cfv-174-phase4post-20260824-124506/phase4post-results.json
  "Phase":  "ClawFactory INTERIM validation, Phase 4 (structural), pass=PRE"
  "PhaseVerdict":  "VOID"          "RowsRecorded":  12

cfv-174-phase4real-20260824-132457/phase4real-results.json
  "Phase":  "ClawFactory INTERIM validation, Phase 4 (structural), pass=POSTREBOOT"
  "PhaseVerdict":  "PASS"          "RowsRecorded":  8
```

The prior close-out's row 10 quotes `PASS, 8 of 8` with `.POSTREBOOT` row ids. That is
`phase4real`. No accepted row traces to a suffix-mismatched retrieval.

**Direct evidence, defect 4.** Pre-fix against post-fix, same box:

```
phase3-results.json   (PRE-fix)   G2.3=VOID  G2.4=FAIL  G2.5=FAIL  G2.6=FAIL
phase3b-results.json  (POST-fix)  G2.3=FAIL  G2.3b=PASS G2.4=PASS  G2.5=PASS
                                  G2.5b=PASS G2.7=PASS
```

Row 14 rests on `phase3b` and on `swapstruct`, both post-fix.

**Rows 5, 6 and 7 could not have been affected by defect 7 for a structural reason worth
recording:** no results JSON was ever retrieved for them. The verdicts were read from the
run's own live transcript, which self-identifies its pass and tags every row:

```
[15:56:10] ClawFactory v1.3.5 switch-provider / Guard 3 defeat, pass=PRE  2026-08-23T15:56:10
[15:57:26]   [PASS] SP.4a.PRE  :: TEST 4: after the FIXED switch, NO toolchain address is in allowed_ipv4
[15:58:19]   [PASS] SP.5a.PRE  :: TEST 5: with the toggle OFF, GitHub and npm remain UNREACHABLE after a provider switch
[15:58:40]   [PASS] SP.6a.PRE  :: TEST 6: with the toggle ON, GitHub and npm ARE reachable, so the probe discriminates
```

**No SUSPECT rows. The stop condition in the brief did not fire, and the fixes proceeded.**

---

## 2. The brief's premise on TASK 4 was wrong, and it was reported before executing

The brief says: *"Only `clawfactory-toolchain.sh` re-resolves, on the five-hourly refresh
or on a toggle."* **The repo says a boot-time resolver trigger already exists**, and it is
the same timer:

```
setup.ps1:2251  OnBootSec=30s
setup.ps1:2252  OnUnitActiveSec=5h
setup.ps1:2253  Unit=clawfactory-allow-providers.service
```

and that service's script ends by calling **both** resolvers. Building "a boot trigger"
would have been building something that nominally existed.

Reading it found the reason it does nothing — the script short-circuits **ninety lines
above** the resolvers:

```
setup.ps1 (inside clawfactory-allow-providers.sh, as it shipped)
    if [ "$BACKEND" = "nftables" ]; then
        nft list table inet clawfactory >/dev/null 2>&1 || exit 0
    ...
    # ~90 lines later, at the very bottom of the file:
    if [ -x /usr/local/sbin/clawfactory-read-fetch.sh ]; then ...
    if [ -x /usr/local/sbin/clawfactory-toolchain.sh ];  then ...
```

The timer has **no ordering** against `clawfactory-fw.service`, which waits on
`network-online.target`. At 30 seconds after a WSL distro boot the nft table can
legitimately not exist yet, and `exit 0` then skips both resolvers while systemd records
a successful run. That reproduces the measured state exactly — a replayed 28-address set,
untouched, with GitHub and npm dead.

**This diagnosis is INFERRED from source. No box was available to confirm it**, and the
fix does not depend on it being the only cause: the second defect below is independently
sufficient and independently fixed.

---

## 3. #276: what was actually built

### 3.1 Two defects, both fixed, neither alone sufficient

**Defect A, the script never reached its resolvers.** Fixed by skipping the provider
block instead of abandoning the run. **And there was a second instance of the same shape
in the `iptables-legacy` branch** — `[ -n "$IPT" ] || exit 0` — which was **not found by
reading**. It was found by the structural check written to prove the first fix:

```
=== the five-hourly refresh must REACH its resolver calls ===
FAIL  emitted refresh reaches the resolvers          expected=[yes] got=[no]
PASS  CANARY: the shipped defect is DETECTED         expected=[no] got=[no]
```

That FAIL is the check earning its keep on its first run. After fixing the second
instance:

```
PASS  emitted refresh reaches the resolvers          expected=[yes] got=[yes]
PASS  CANARY: the shipped defect is DETECTED         expected=[no] got=[no]
```

**Defect B, a run before DNS was up destroyed the set it was meant to refresh.** Section 4
of both resolvers wrote the empty result unconditionally, so an early tick truncated the
addresses `fw-apply.sh` had just correctly replayed. This is why the existing 30-second
trigger firing at the wrong moment was *worse* than it not firing.

Both resolvers now keep `host<TAB>address<TAB>epoch` in a root-owned `*-ips.map` and carry
an address forward for a host that will not resolve now, bounded at `RETAIN_MAX_AGE=86400`.

### 3.2 The new boot unit, and what happens if it is absent

`install-read-fetch.sh` now writes and enables:

```
/usr/local/sbin/clawfactory-egress-refresh.sh          root:root 0755
/etc/systemd/system/clawfactory-egress-refresh.service root:root 0644

[Unit]
After=clawfactory-fw.service network-online.target
Wants=network-online.target
[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/sbin/clawfactory-egress-refresh.sh
[Install]
WantedBy=multi-user.target
```

It runs the **existing** resolvers and retries while either reports unresolved hosts, up
to `20 x 6s`. **It waits on state, not on a sleep, and needs no probe hostname of its
own** — the state it waits for is the resolution it was going to do anyway. With an empty
allowlist and the toggle off there is nothing to resolve, nothing fails, and it exits on
the first attempt having waited for nothing.

The enable is **verified by read-back and is fatal**:

```sh
EGRESS_ENABLED="$(systemctl is-enabled clawfactory-egress-refresh.service 2>&1 || true)"
if [ "$EGRESS_ENABLED" != "enabled" ]; then
    fatal "clawfactory-egress-refresh.service did not enable (systemctl is-enabled said '${EGRESS_ENABLED:-<empty>}') ..."
fi
```

**If the registration is absent** — an older install, or systemd unavailable — the product
falls back to exactly its previous behaviour: `fw-apply.sh` still replays at boot so the
deny holds and the set is never wider, and the five-hourly timer eventually corrects it.
Fail-safe, not fail-open.

**`fw-apply.sh` is deliberately untouched.** The boot replay stays exactly as it was, so
the deny is in force from the first moment of boot and is never wider during the window.
This only replaces a narrow stale set with a narrow fresh one, afterwards.

### 3.3 Answer to close-out question 2: how a user-closed route is prevented from reopening

**L30, quoted.** Retention lives entirely inside the `ENABLED` gate, and `ENABLED` is read
from the root-owned policy in section 2 **before** anything is resolved:

```sh
# --- 3. Resolve, only if enabled --------------------------------------------
...
RETAINED=0
if [ "$ENABLED" = "1" ]; then
    for h in $TOOLCHAIN_HOSTS; do
        ...
        KEPT="$(retain_for "$h")"
```

and section 4 truncates **both** files when it is off:

```sh
# --- 4. Persist, so the boot path rebuilds the same set ----------------------
# Written unconditionally. When the toggle is OFF this TRUNCATES both files to
# empty ... The map is truncated with it so a closed route leaves no retention
# fuel behind either.
printf '%s\n' $RESOLVED | sed '/^$/d' | sort -u > "$IPS_FILE"
...
mv -f "$NEWMAP" "$MAP_FILE" ...
```

So with the switch off: nothing is resolved, nothing is retained, the address file is
emptied, and the map is emptied. There is no state from which a boot run could reopen it.

For **read-fetch** the guarantee is sharper because the list is the user's own. Retention
is keyed by host and the map is rebuilt from `$HOSTS`, which is the list just parsed out of
the policy file:

```sh
# A host the user REMOVED in Studio is not in $HOSTS, so it is never looked up,
# nothing is carried forward for it, and its old lines are dropped when the map
# is rewritten below. There is no path by which a removed site returns at boot.
```

An unreadable or malformed policy leaves `$HOSTS` empty, so the same rewrite empties both
files: a fault denies everything.

**This guarantee is argued from source, not measured. It needs a test in the validation
job:** switch the toolchain off, reboot, and assert it is still off and the set is still
empty; and remove a site in Studio, reboot, and assert it did not come back.

### 3.4 Input-shape sweep for the new `*-ips.map` reader

Every shape decided in the code, and the comment and the code agree:

| Shape | Meaning | Direction |
| --- | --- | --- |
| absent | no retention. Fresh install, or a box upgraded from a build that predates the file | denies |
| empty | same as absent | denies |
| well-formed, epoch within `RETAIN_MAX_AGE` | used | the only widening path, and it is bounded |
| well-formed, expired | dropped | denies |
| wrong field count | line dropped **and counted**, reported loudly | denies |
| epoch not numeric | line dropped | denies |
| epoch in the future | a fault; line dropped | denies |
| address not IPv4-shaped | line dropped before it can reach `nft add` | denies |
| hostile (`9.9.9.9 }; nft flush ruleset; #`) | fails the IPv4 pattern; dropped | denies |

The original epoch is preserved when an address is carried forward, so **retention cannot
renew itself**: an address carried forward keeps ageing and expires on schedule.

### 3.5 Calibration — 39 rigged cases, controls in every group

`scripts/calibrate-egress-boot.sh` **extracts the shipped functions** with `sed` rather
than retyping them, so it cannot pass against a copy that has drifted:

```
=== resources/clawfactory-read-fetch.sh ===
PASS  absent map                                     expected=[] got=[]
PASS  empty map                                      expected=[] got=[]
PASS  well-formed, fresh                             expected=[9.9.9.9] got=[9.9.9.9]
PASS  DIFFERENT host (revocation)                    expected=[] got=[]
PASS  expired beyond RETAIN_MAX_AGE                  expected=[] got=[]
PASS  epoch in the FUTURE                            expected=[] got=[]
PASS  malformed: two fields                          expected=[] got=[]
PASS  malformed: four fields                         expected=[] got=[]
PASS  wrong type: epoch not numeric                  expected=[] got=[]
PASS  hostile: nft injection in ip                   expected=[] got=[]
PASS  hostile: not an address                        expected=[] got=[]
PASS  mixed valid + malformed                        expected=[9.9.9.9] got=[9.9.9.9]
PASS  two valid entries, both kept                   expected=[1.2.3.4 9.9.9.9] got=[1.2.3.4 9.9.9.9]
PASS  CONTROL: reader is not a no-op                 expected=[7.7.7.7] got=[7.7.7.7]
=== resources/clawfactory-toolchain.sh ===
   (identical 14, both files)
=== the boot refresh's wait condition ===
PASS  status line, failed=0                          expected=[0] got=[0]
PASS  status line, failed=3                          expected=[3] got=[3]
PASS  no status line at all                          expected=[0] got=[0]
PASS  empty output                                   expected=[0] got=[0]
PASS  wrong key present, ours absent                 expected=[0] got=[0]
PASS  read-fetch key, failed=1                       expected=[1] got=[1]
PASS  failed= is not numeric                         expected=[0] got=[0]
PASS  two status lines: last wins                    expected=[2] got=[2]
PASS  CONTROL: a nonzero really reads back           expected=[5] got=[5]
=== the five-hourly refresh must REACH its resolver calls ===
PASS  emitted refresh reaches the resolvers          expected=[yes] got=[yes]
PASS  CANARY: the shipped defect is DETECTED         expected=[no] got=[no]

EGRESS_BOOT_CALIBRATION pass=39 fail=0
```

**`DIFFERENT host (revocation)` is the load-bearing case.** If a map entry for a host no
longer on the list could be returned, a site the user removed would come back. Every
`expected=[]` case would also pass against a reader that always returned nothing, which is
why each group carries a `CONTROL` that must produce a value.

---

## 4. #276, read-fetch half, and answer to close-out question 3

`clawfactory-read-fetch.sh` had the identical replay comment and the identical
unconditional truncation, **and it resolved each host exactly once**. The toolchain
resolver has carried `RESOLVE_PASSES=3` since it was written, with a comment explaining
that a single lookup misses half of a rotating pool and leaves the host intermittently
unreachable while the panel reads on. This file simply never got the loop. That was not a
decision. It now has the same constant with the same name and a note that if one moves,
both move.

**This half is INFERRED, not measured.** cfv-174 seeded `www.iana.org` and never probed it
for reachability after the reboot; `TC.7a` only proves an add DURING a run works.

### The host the validation job must seed, and why `www.iana.org` cannot detect this

**`www.iana.org` has a stable address.** The defect is that the boot path replays a
*stale* set: for a host whose address does not move, the stale set and the fresh set are
the same set, so the route works whether or not the bug is present. It is a negative
control that can never fail.

**Seed `api.github.com` into the read-fetch allowlist before the reboot.** It is the
measured example: card #261 records six consecutive lookups on cfv-169 returning
`140.82.116.6, 140.82.116.6, 140.82.116.5, 140.82.116.5, 20.29.134.17, 140.82.116.5` —
three distinct addresses across six lookups, and one (`20.29.134.17`) that the live set
never captured at all. A replayed set for that host is very likely to miss the address the
next connection uses.

Two cautions for whoever writes that probe:

- **`api.github.com` is also a toolchain host.** With the toolchain toggle ON its addresses
  are in `@toolchain_ipv4` as well, so a reachability probe cannot attribute success to the
  read-fetch set. **Switch the toolchain OFF for this measurement**, or pick a different
  rotating-pool host that is not in `TOOLCHAIN_HOSTS`.
- **The probe needs both halves.** It must show the host reachable before the reboot and
  assert on it after, with a control host that must remain unreachable in the same run.

---

## 5. #274: the claim, in the four places it survived

### 5.1 What the notices said, verbatim, before anything was changed

```js
// frontend/src/pages/web/WebAccessPage.tsx, onToggleToolchain
setNote(
  next
    ? 'Your agent can install skills and fetch code from GitHub and npm again.'
    : 'Skill installation is now off, and your agent can no longer fetch code from GitHub or npm. Its AI provider is unaffected.',
);
```

**The ON notice also asserts something about skill installation, and the card did not name
it.** "can install skills ... again" implies the switch had stopped skill installation. It
is wrong in the opposite direction from the OFF notice and by the same mechanism.

### 5.2 The proposed replacements were verified and shipped unchanged

Checked clause by clause against the governing paragraph and against what the switch does:

| Governing paragraph | Proposed OFF notice | Verdict |
| --- | --- | --- |
| "Switching this off stops your agent fetching code from GitHub and npm." | "Your agent can no longer fetch code from GitHub or npm." | agrees |
| "It does not stop skill installation: the skill hub shares a network address with ClawFactory's own site, which stays reachable and which this switch does not cover." | "This does not stop skill installation: the skill hub shares a network address with ClawFactory's own site, which this switch does not cover." | agrees; shorter, drops "stays reachable", adds nothing |
| "It does not affect the AI provider your agent talks to." | "Its AI provider is unaffected." | agrees |

The ON replacement — "Your agent can reach the skill hub, GitHub and npm again." — is the
paragraph's own opening sentence plus "again", and it is accurate: `api.clawhub.ai` was
measured BLOCKED with the toggle off in the same cfv-170 run in which `clawhub.ai`
connected, so switching on genuinely restores something.

**Neither over- nor underclaims. Shipped as proposed.**

### 5.3 Studio enumeration: 42 claim candidates, 8 user-visible, all in one file

`ClawFactory-Studio/scripts/enumerate-toolchain-claims.mjs` parses every `.ts`/`.tsx` with
the TypeScript compiler API (5.9.3) and collects string literals, **template chunks** and
JSX text with line numbers, then filters by the subject of the claim. Template chunks
matter: an interpolated claim is three AST nodes and no single-line regex sees it whole.

The 8 that make a statement about what the switch does, all in `WebAccessPage.tsx`:

```
:101  Your agent can reach the skill hub, GitHub and npm again. Its AI provider is unaffected.   [FIXED]
:102  Your agent can no longer fetch code from GitHub or npm. This does not stop skill ...        [FIXED]
:234  Software sources ClawFactory needs
:236  Your agent can reach the skill hub, GitHub and npm. Switching this off stops ...            (the paragraph)
:245  Off. GitHub and npm are not reachable.
:261  This is switched on, but no addresses are currently reachable. ...
:268  ClawFactory could not read its own settings file, so these sources are switched off ...
:317  A site you have not added is not reachable. ... which are GitHub and npm, unless you ...     (the footnote)
```

Lines 234, 245, 261 and 268 were checked and make no claim about skill installation.
**Line 317, the ratified footnote, was found to disagree with the card above it** — see
section 9.

**The canary was shaped like what I feared missing, not like what I had found.** A claim
worded like neither known instance, built from a template literal with an interpolation,
in a page that carries no toggle copy:

```
inserted:  const __canary = `Turning ${1} the software sources also means your agent stops picking up add-ons.`;
found at:  frontend/src/pages/Status.tsx:41 [ast] the software sources also means your agent stops picking up add-ons.
removed:   CLAIM_HITS 43 -> 42
```

The count dropping by exactly one on removal is the measurement, not an assumption.

### 5.4 Secure-Setup enumeration, and the audit probe that had the defect it was hunting

`scripts/enumerate-toolchain-claims.mjs` (Secure-Setup) matches over **logical** lines,
joining shell backslash continuations and PowerShell concatenations first, because the
shape to fear here is a claim broken across lines. Hits are labelled SHIPPED when the file
appears in the `.iss` `[Files]` section.

**The card named two sites. Four were live.** All four fixed:

| Site | What it said |
| --- | --- |
| `resources/install-read-fetch.sh:243` | "Switching it off in Studio stops skill installation, GitHub and npm" |
| `resources/install-read-fetch.sh:228` | "Skill installation, GitHub and npm will be unreachable until the next refresh" |
| `resources/egress-policy.json` `_note` **and** `_comment` | "false closes that route and STOPS SKILL INSTALLATION" / "Off would ship a product where skill installation, npm and GitHub fail" |
| `resources/clawfactory-toolchain.sh:19-25` | "Defaulting off ships a product where skill installation, npm and GitHub fail" / "accepts that skill install stops working" |
| `resources/clawfactory-grants.ps1:1139` | "Off would break skill installation and the agent's code fetching" |

**THE ENUMERATOR MISSED ONE OF THEM.** Its first effect vocabulary lacked `break` and
`off`, so `grants.ps1:1139` — a live instance — was silently absent from its output. It was
caught by a second, cruder pass, and the pattern was widened:

```
=== does the widened pattern now find the missed site? ===
SHIPPED resources/clawfactory-grants.ps1:1139  # It DEFAULTS ON. Off would break skill installation and the agent's code
```

`grants.ps1:1139` is now the known-defective input the pattern has to find. **An audit
regex is itself a probe and can be wrong in the same way the code was**, and this one was.

**The continuation canary**, in a shipped file that carries no toggle copy:

```
--- physical lines 6-7, neither holds the claim whole ---
# Once the software sources are closed the agent can no longer \
# pick up new add-ons from the hub.
--- naive line-based grep for the whole claim (must find NOTHING) ---
NOT FOUND by a line-based search -- the canary has the shape I fear
--- enumerator ---
SHIPPED resources/clawfactory-fw-assert.sh:6  # Once the software sources are closed the agent can no longer \ # pick up new add-ons from the hub.
```

Canary removed; `git diff` on that file is empty.

### 5.5 TASK 3.4: verified against sources and the extracted bundle, not a binary scan

No binary string scan of the built installer was run. Inno compresses the code section and
such a scan is blind — the prior close-out records its positive control failing over the
compiled NSIS installer. Verified instead against the `app.asar` this build ships:

```
PRESENT    which this switch does not cover
PRESENT    Your agent can reach the skill hub, GitHub and npm again
absent     Skill installation is now off
absent     Your agent can install skills and fetch code from GitHub and npm again
absent     stops skill installation
PRESENT    Workspace                       <- positive control: the scan is not blind
absent     ClawFactoryNegativeSentinelZZ9  <- negative control: it is not matching everything
```

---

## 6. #275: nine dead ends, not two

The card named Templates and Settings. **Enumerating every route instead of fixing the two
known ones found nine.**

Studio's HTTP backend was retired when it became a packaged desktop app. `get()` and
`jsonRequest()` in `api/client.ts` now throw unconditionally; only the preload-bridge
namespaces work. Every route, classified by which namespaces its page uses:

| Route | Data source | Category |
| --- | --- | --- |
| `/` Status | `api.appVersion` (bridge, non-throwing) | real content |
| `/get-started` | none — static markdown | real content |
| `/workspace` | `api.grants` (bridge) | real content |
| `/deleted` | `api.quarantine` (bridge) | real content |
| `/approvals` | `api.send` (bridge) | real content |
| `/approvals/smtp` | `api.send` (bridge) | real content |
| `/web` | `api.web` (bridge) | real content |
| `/templates` | `api.templates` (**throws**) | **error naming a retired backend** |
| `/files` | `api.files` (**throws**) | **error naming a retired backend** |
| `/activity` | `api.activity` (**throws**) | **error naming a retired backend** |
| `/agents`, `/agents/new`, `/agents/:name` | `api.agents`, `api.providers` (**throws**) | **error naming a retired backend** |
| `/skills` | `api.skills` (**throws**) | **error naming a retired backend** |
| `/chat` | `api.chat`, `api.agents` (**throws**) | **error naming a retired backend** |
| `/settings` | `api.settings`, `api.providers` (**throws**) | **error naming a retired backend** |
| `/wizard` | static first step, `api.wizard` on the key step | renders, then dead-ends on action |
| `*` | none | "Page not found." |

`/wizard` is included in the fix although it does not error on load. A wizard that cannot
finish is a worse dead end than a panel that says so, the installer runs the real one, and
its only inbound link was from the Agents list, which is itself in the list.

The three banner components (`NamingBanner`, `Questionnaire`, `FirstRunBanner`) all call
stubbed namespaces and all swallow the rejection, so they render nothing. Honest by
absence; left alone.

**Measured from the rendered DOM, not the source:**

```
/#/settings ->  Settings
                Settings is not part of this release.
                Your agent's safety rules, its AI provider key, and the folders and sites
                it is allowed to touch. The last of those is on the Web access panel today.
                Nothing here failed and nothing is misconfigured -- this panel has no working
                version yet, so there is nothing for it to show. It is listed so you can see
                what is planned.
                What you can use today
                Workspace / Recently deleted / Approvals / Web access
```

Nav entries kept, per the card. The page components are not deleted — only which element
the route renders changed, which is a one-line revert per panel.

**One string survives in the bundle and is recorded so nobody chases it.** `not wired in
the desktop shell scaffold` is a constant in `api/client.ts`, still imported for
`app.version()`. **No route renders it.** It is deliberately NOT asserted absent in phase6,
because asserting an absence that is not true is how a check starts lying.

---

## 7. #273: the way home, measured from the accessibility tree

**Recommendation taken: make the title block a link, not a Home nav entry.** The nav
already wraps at narrow widths — there is a comment in `App.tsx` about the version and
`Templates` colliding — and a twelfth item makes that worse. A product's title going home
is the convention users arrive with, which is precisely why the operator clicked it twice.

**TASK 7.2, measured rather than asserted.** From the rendered accessibility tree:

```
banner [ref_1]
 link "ClawFactory Studio home" [ref_2] href="#/"
  heading "ClawFactory Studio" [ref_3]
```

and clicking it from `#/settings`:

```json
{"hash":"#/","h2":["ClawFactory Studio"],
 "firstPara":"This is where you decide what your agent is allowed to do. Each panel below cont"}
```

The lobster is `aria-hidden`, so the link's accessible name is the product name rather than
an emoji, and the whole block is one target so either instinctive click works.

---

## 8. The checklist: seven checks to ten, three defects fixed

**8.1 The address count is no longer a constant.** It was `On. 28 network addresses
reachable`; his panel read `On. 25 network addresses reachable.` The count is re-resolved
from DNS against hosts behind rotating pools, so two readings minutes apart legitimately
differ. Check 1c now asserts a **nonzero** count and the exact unit string, names the three
things that DO fail (zero, `Off.`, wrong unit wording), and asks for the number as evidence
rather than as a judgement. A check that fails on a healthy box teaches the next person to
explain away the day it fails on a sick one.

**8.2 Version strings, verified against the built bundle.** Checks 6b and 6f now quote
`ClawFactory Studio v1.3.2` and `1.3.2`, with 1.3.1 and 1.3.0 named as the wrong versions,
and 6g's collision example updated to `v1.3.2Templates`. Confirmed against the shipped
`app.asar`, not against intention.

**8.3 Check 8 is new** — the corrected OFF notice as a presence check with its text quoted
word for word, plus the ON notice, plus the state assertions on both sides. Absence of the
old claim is named as one of three failure modes rather than the only assertion. It is also
the only check in the file that moves the toggle, so the ordering against the automated
suite is stated and the file no longer says "never move it".

**8.4 Checks 9 and 10 are new** — all seven not-in-this-release nav panels with `9e` as a
navigation control so the assertions cannot pass on a dead shell, and both halves of the
click home.

**8.5 Every assertion re-audited, one at a time.** Full table in the file. Three defects
found and fixed: check 1c asserted a constant that was never constant; **check 6 still told
the operator not to click the lobster** — the exact instruction he had already reported,
which had been recorded in a close-out, never carded, and left in place by the session that
recorded it; and checks 6b/6f quoted a version this build does not ship.

---

## 9. Findings raised rather than fixed

**The ratified footnote enumerates the software sources differently from the card above
it.** `WebAccessPage.tsx:317` says *"It can also reach the software sources ClawFactory
needs, which are GitHub and npm"*. The card three inches up says *"the skill hub, GitHub
and npm"*, and the switch really does cover `clawhub.ai` and `api.clawhub.ai`. So the
footnote **understates** what is reachable, immediately after the sentence "A site you have
not added is not reachable", which makes it read as though the skill hub is not reachable.
It is.

**Not changed here, deliberately.** It is ratified text, asserted verbatim by check 2, and
the file comment says plainly not to reword it. Understating reachability is also the
cautious direction, so this is not a blocker. **Carded as #279** with a suggested four-word
edit and the three places that must move together if it is applied.

---

## 10. Answer to close-out question 4: exactly what changed between v1.4.0 and v1.4.1

The v1.4.0 build is commit `f529e90`. **The previous session changed no file that ships:**

```
git diff --stat f529e90..653667a -- setup.ps1 ClawFactory-Secure-Setup.iss resources/
(empty)
```

So the entire payload delta is this session's. Files that reach a customer's machine:

| File | Change | Card |
| --- | --- | --- |
| `ClawFactory-Secure-Setup.iss` | `MyAppVersion` 1.4.0 → 1.4.1; `StudioInstaller` → `-1.3.2.exe` | version |
| `setup.ps1` | `$InstallerVersion` → 1.4.1; **two** `|| exit 0` short-circuits removed from `clawfactory-allow-providers.sh` | version, #276 |
| `resources/ClawFactory-Studio-Setup-1.3.2.exe` | new Studio payload | #273/#274/#275 |
| `resources/clawfactory-toolchain.sh` | per-host retention + map + `TOOLCHAIN_STATUS`; "WHY NOT DEFAULT OFF" claim corrected | #276, #274 |
| `resources/clawfactory-read-fetch.sh` | `RESOLVE_PASSES=3`; per-host retention + map + `READFETCH_STATUS` | #276 |
| `resources/install-read-fetch.sh` | new `clawfactory-egress-refresh` script + unit + fatal read-back; two log strings corrected | #276, #274 |
| `resources/egress-policy.json` | `toolchain._note` and the `_comment` "WHY ON" paragraph corrected | #274 |
| `resources/clawfactory-grants.ps1` | toggle header comment corrected | #274 |
| `resources/uninstall.ps1` | removes the new unit and script; **also** `clawfactory-toolchain.sh`, a pre-existing leftover | #276 + hygiene |

**Nothing else changed in the shipped payload.** No security control was added, removed,
weakened or re-scoped. No firewall rule, chain, set, uid scoping, credential path, file
mode, broker, gate or pin changed. `fw-apply.sh` is byte-identical.

Repo-only, not in the installer: `scripts/build_release.ps1` (the pin), `released-versions.tsv`,
`scripts/enumerate-toolchain-claims.mjs`, `scripts/calibrate-egress-boot.sh`,
`validation/MANUAL_CHECKS_studio.md`, `validation/interim-v120-phase1.ps1`,
`validation/interim-v120-phase6.ps1`, this file.

Studio: `App.tsx`, `WebAccessPage.tsx`, new `NotInThisRelease.tsx`, three `package.json`
versions, and a new `scripts/` enumerator. `frontend/package.json` was at 1.3.0 while the
other two were at 1.3.1 — a latent trap, now all three at 1.3.2.

### The build

```
SOUL pin OK: e70212603f2f91e6abf6db576c9535b1aaad60506e2fb075c199f18160db7941
Bundle check OK: all 34 preflight resources are in [Files].
Studio pin OK: ac5937516e7edbb5aac00433bfa6e5074449cbc28b132883099391639e1e7dca
Version OK: 1.4.1 (.iss and setup.ps1 agree)
Ledger OK: released-versions.tsv carries 8 prior artifact row(s).
Persona pin OK: 0557d07004d4d067d8cd9e7cee7b2a3a783e0ac8ff4c492c0c152d7e35ff63a0
Workspace SOUL pin OK: 441b6279f6613c313e87e9e9e034f97a220540cddbf1cf738bb9a86c37a5a257 (6677 bytes composed)
Rootfs pin OK: 1483cc5c1dce13064f774834cbffdff226559fd522a67a381a8ea77d63fb4109
  unsigned sha256: a26e9a586dc4d3db0c0d13f591ed4ce957f5c85838c14d652738c9443f151f6f
Signed successfully: Output\ClawFactory-Secure-Setup.exe
Ledger: appended 1.4.1 a26e9a586dc4d3db0c0d13f591ed4ce957f5c85838c14d652738c9443f151f6f (440586571 B).
```

| | |
| --- | --- |
| gates | soul, bundle, studio, version, persona, workspace-soul, rootfs — **7 of 7 green** |
| ledger (unsigned) | `a26e9a586dc4d3db0c0d13f591ed4ce957f5c85838c14d652738c9443f151f6f`, 440,586,571 B |
| signed sha256 | `90c673ddaf0959418eef8b19b959894581003f0c5dbf0d78cfb2f52beb3ef398` |
| signed bytes | 440,602,224 |
| Authenticode | **Valid**, `CN=Bret Mckinney, O=Bret Mckinney, L=West Valley City, S=ut, C=US` |
| Studio `app.asar` | `a64a118f7ae748059b482589d2c124d082cc42dbf9d3239ba615079982d2a49e`, 487,784 B |
| Studio installer | `ac5937516e7edbb5aac00433bfa6e5074449cbc28b132883099391639e1e7dca`, 100,016,360 B, Authenticode Valid |

The v1.4.0 ledger row is untouched. The gate did not refuse anything. **No build gate was
tested by editing a comment** — Inno strips comments, so the compiled bytes would be
identical and the gate would correctly report a byte-for-byte rebuild.

The signing certificate's `NotAfter` is 2026-08-25, one day out. **That is normal and not
an alarm:** Azure Trusted Signing mints three-day certificates daily.

### The three-part Studio repin

All three parts landed in one commit, because doing one without the others is the failure
the pin exists to prevent:

1. `$studioName` / `$studioPinned` in `build_release.ps1`, and the `.iss` `#define`.
2. `interim-v120-phase6.ps1`'s shipped-copy assertions.
3. `$PIN.studioAsar` in `interim-v120-phase1.ps1`.

Part 2 was **run** against the shipped bundle using the lists verbatim:

```
MISSING_COUNT=0
STILLTHERE_COUNT=0
POSCONTROL_OK
```

25 of 25 PRESENT, 11 of 11 ABSENT. New markers are ASCII-only on purpose — the OFF notice
contains a curly apostrophe, and a marker carrying U+2019 is the middot bug that once
reported MISSING against an asar that demonstrably contained the string.

---

## 11. Answer to close-out question 5: what the next job has to measure

**No fitness verdict is offered.** This build has not been validated and any fitness
statement from this session would be an unmeasured premise.

What has to be measured before this artifact could be considered for publication:

1. **The full v1.4.0 matrix, re-run.** Every shipped file that changed is inside the
   firewall's own machinery. Rows 1 to 14 were sound on the previous build; none of them
   transfers to this one.
2. **#276, toolchain half, across a real reboot.** `TC.1c` must flip from FAIL to PASS. Its
   companions `TC.1a` and `TC.1b` passed on a dead route last time and are carded (#278) as
   not asserting what their names claim — read their evidence, do not take their verdicts.
3. **#276, read-fetch half, with a ROTATING-POOL HOST seeded before the reboot.**
   `www.iana.org` cannot detect this defect. See section 4, including the caution that
   `api.github.com` is also a toolchain host.
4. **L30, both directions, across a reboot.** Toolchain switched OFF stays off and its set
   stays empty. A site REMOVED in Studio does not come back. Both are argued from source in
   section 3.3 and neither is measured.
5. **The new unit is actually enabled and actually ran.** `systemctl is-enabled` and
   `is-active` for `clawfactory-egress-refresh.service`, plus its journal, which prints
   `attempt N/20: unresolved hosts read-fetch=X toolchain=Y`.
6. **The install-time fatal read-back fires.** Deliberately break the enable and confirm the
   install ABORTS with the named message. An unproven fatal is a fatal that might be a
   no-op.
7. **Checks 8, 9 and 10 of the by-hand checklist**, on the packaged app rather than the dev
   server. Check 8 is the only thing in the estate that can see the transient toggle
   messages, which is the whole of card #274 on the GUI side.
8. **The retention path exercised on a real box**, not only against rigged input: a resolver
   run with DNS unavailable must leave the persisted set intact rather than empty, with a
   control proving the run really did fail to resolve.
9. **A clean install and a clean uninstall**, since `install-read-fetch.sh` and
   `uninstall.ps1` both changed.

---

## 12. Deviations, and things deliberately not done

**The brief's TASK 4 premise was corrected before executing**, not quietly worked around.
Section 2.

**Two logical changes shared one file twice, and the commits were split anyway.** `App.tsx`
carries both #273 and #275; the working copy was parked, the file reverted, #273 re-applied
and committed alone, then the full version restored and committed as #275. Two revertible
commits rather than one lumped one. `clawfactory-toolchain.sh` and `install-read-fetch.sh`
carry both #274 strings and #276 code on overlapping lines and **could not** be split; both
cards are named in that commit message.

**One out-of-scope line was changed**, in a line already being edited: `uninstall.ps1` did
not remove `/usr/local/sbin/clawfactory-toolchain.sh`. A pre-existing leftover, not a
security gap, one filename added and stated here.

**The ratified footnote was not reworded.** Section 9. Carded as #279 instead.

**`api/client.ts` was not cleaned out.** The `SHELL_UNAVAILABLE` constant survives as
unreachable dead text. Removing it would mean deleting the api namespaces the unrendered
page components still import, which is a bigger change than this job asked for.

**Not done, and out of scope by instruction:** no VM, no validation run, no tag, no GitHub
release, no publish, no Guard 4, no `SP.8` retirement, no fix to the v1.2.0 driver
credential dependency, no fix to `TC.1a/b/c`, `G1.7` or `G1.7c`, no FrontierAI work.

---

## 13. Cards

| Card | State | Why |
| --- | --- | --- |
| #273 | `in_progress` | fix built and measured from the DOM; **not validated on the packaged app** |
| #274 | `in_progress` | fix built in Studio and in four Secure-Setup files; **not validated** |
| #275 | `in_progress` | fix built and measured from the DOM; **not validated** |
| #276 | `in_progress` | fix built and calibrated against rigged input; **the reboot behaviour is unmeasured** |
| #266 | `done` | untouched |
| #261 | `todo` | commented: v1.4.1 applied option (a) to read-fetch and adds bounded retention; the sampling problem itself is unchanged |
| #277 | NEW, `queued` | invert `SP.8` to assert the hub REMAINS reachable, documenting the residual rather than retiring the check |
| #278 | NEW, `queued` | harness defects `TC.1a/b/c`, `G1.7`, `G1.7c` |
| #279 | NEW, `queued` | the ratified footnote omits the skill hub from the sources it names |

**None of the four moved to `done`, and the reason is the same for all four: a fix that is
built but unvalidated is not done.** Every one of them changes what a user SEES or what the
firewall HOLDS after a reboot, and neither has been observed on a running box. The Dispatch
status enum offers no "in review", so `in_progress` is the state whose evidence exists, and
each card carries a comment stating exactly what is built and what is owed.

Already carded elsewhere, verified rather than duplicated: the v1.2.0 driver credential
dependency is **#259** (scope item 2), the `scout_agent` heartbeat is **#227**, and the
U+2022 characters in `publishing_agent.py` are **#241**.

---

## 14. Commits and remotes

**ClawFactory-Studio** — `origin/main` = `9282c42cc814cc379195e1df26657bf097c4a72c`
(from `git ls-remote`, not UI state)

```
9282c42 version: Studio 1.3.1 -> 1.3.2, and frontend's copy back in step
0788416 routes: nine dead ends replaced with an honest empty state
a567e2d shell: give the header a way back to the home route
eba52a3 web access: the toggle notices said the opposite of the paragraph above them
```

**ClawFactory-Secure-Setup** — `origin/main` = `3f9159932ed3abe1c89076fdc494dd3008878b1b`

```
3f91599 v1.4.1: version bump, three-part Studio repin, ledger row
79bf939 checklist: seven checks to ten, and the count that was never constant
bd19f54 read-fetch: a site the user allowed could be dead after a reboot, and resolved once
a63824d egress: the toolchain route was dead after a reboot while the panel said it was on
e592159 claims: the switch does not stop skill installation, in the two files that said it did
653667a  <- the ten commits pushed at session start, 8174d3f..653667a
```

Explicit per-file staging throughout. No `git add -A`, no worktree, **no tag created** —
confirmed with `git ls-remote --tags`, whose newest tag is still `v1.1.0`.

---

## 15. End-of-session gate

### Resource ledger

| Resource | State |
| --- | --- |
| Azure VMs | **none**, across the entire subscription. `VM_COUNT=0`, measured |
| VMs provisioned this session | none. This job provisions no VM |
| Spend incurred | the two Azure Trusted Signing operations `build_release.ps1` and the Studio packager perform on every build. Nothing else |
| Local dev server | Vite on :5173, started for the #273 and #275 DOM measurements, **stopped**; port confirmed free |
| Background tasks | none left running |

**Nothing is billing.**

### Delta security sweep

Reviewed the shipped diff, 481 insertions and 45 deletions across 8 files.

- **No security control was added, removed, weakened or re-scoped.** No change to any
  firewall rule, chain, nft set, uid scoping, credential path, file mode, broker, turn gate
  or pin. `fw-apply.sh` is byte-identical.
- **The one new capability that can WIDEN a set is per-host retention**, and it is bounded
  four ways: only for a host still on the current list; only within 24h of a successful
  lookup; only inside the `ENABLED` gate for the toolchain; and only after the address
  passes a strict IPv4 pattern before it can reach `nft add`. Every malformed, wrong-type
  or hostile input denies. Calibrated over 28 rigged cases with controls.
- **New file, new attack surface, assessed.** `clawfactory-egress-refresh.sh` is root:root
  0755 and reads nothing an attacker controls: it invokes two root-owned scripts and parses
  their own stdout for `failed=<digits>`. A non-numeric or absent value reads as zero, so
  the worst outcome of a corrupted status line is that the boot refresh stops retrying
  early — it cannot widen anything.
- **New file the agent might reach.** The `*-ips.map` files are root:root 0644 under
  `/etc/clawfactory`, the same directory and ownership as the address lists that already
  live there. The agent (uid 1000) can read them and cannot write them. Reading them
  discloses addresses it can already read from `*-ips.txt`.
- **The three `exit 0` removals narrow nothing.** They cause code that was being skipped to
  run; the code they now reach flushes before it adds.
- **No credential value entered any transcript, commit, or file.** Signing keys were
  checked for presence and length only. `DISPATCH_SECRET` was read single-key and reported
  as a length. `grep` over the diff for secret-shaped strings: nothing.

### Delta bug review

- **`bash -n`** clean on `clawfactory-toolchain.sh`, `clawfactory-read-fetch.sh`,
  `install-read-fetch.sh`, and on **both scripts the installer emits** (extracted from
  their heredocs and parsed separately).
- **PowerShell AST parse** clean on `setup.ps1`, `uninstall.ps1`, `clawfactory-grants.ps1`.
- **`JSON.parse`** clean on `egress-policy.json`.
- **`--list-hosts` smoke-tested**, because the install-time drift gate calls it and an
  empty return fails the install claiming DRIFT and blames the wrong file. Returns all
  eight hosts.
- **`npm run typecheck`** clean across the Studio frontend and desktop workspaces, at each
  of the three commits.
- **No `TODO`, `FIXME`, `XXX` or `HACK` introduced.**
- **The `set -e` interaction was checked** on the emitted `clawfactory-allow-providers.sh`:
  `if ! nft list ...; then` and `if [ -z "$IPT" ]; then` are both safe under `set -e`,
  unlike the `||` forms they replace.
- **Known residual, stated rather than left to be discovered:** a host that never resolves
  will make the boot refresh burn its full 120-second ceiling at every boot. It is bounded,
  it is logged with the host count, and the message says it is worth chasing.
