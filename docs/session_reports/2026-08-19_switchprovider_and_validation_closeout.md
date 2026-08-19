# Close-out: the switch-provider Guard 3 defeat, the persistence gap, the install-time provider gate, and the validation owed since #245

**Card:** #258. **Date:** 2026-08-19. **Branch:** `main`.
**Input artifact:** 1.3.4, signed, `ee6a5cd0232d7eb039182fe45e967cf2407e4ccd70f2e06540e06c93b89b5214`.
**Output artifact:** 1.3.5, signed, unsigned sha256
`2c3e50f07afbdd67894d9fad76916e38666d00f6a30f5f3b3be9359112e38d55`, 440,599,315 B.

## THIS IS AN INTERIM CLOSE-OUT AND THE VALIDATION HAS NOT RUN

Read this first, because the rest of the document is easy to mistake for a finished
job. Three defects are fixed, the build is cut and signed, and the validation is
staged and calibrated. **No VM has been provisioned. Task 4 has not been executed.
Nothing in the matrix has passed.**

That was a deliberate choice, taken with the operator: the run needs a human at the
console twice (the admin password at provisioning, and again after the reboot,
because auto-logon is one-shot) and the five MANUAL panel checks are by hand. So the
build and the fixes landed now, and the VM run starts when the operator is free.
Nothing bills in the meantime; the resource group holds no VM.

**The debt owed since #245 is therefore still owed.** It is now staged rather than
merely named, which is progress, but it is not a pass, and this document does not
record it as one.

## What the session produced

| Commit | What |
| --- | --- |
| `2d081bc` | the census, and the correction to the comment that said three |
| `3818bc0` | the ship-blocker: switch-provider no longer re-seeds the toolchain hosts |
| `328e164` | the AUX_HOSTS persistence gap, both sites |
| `20a2d67` | the install-time provider-route gate |
| `2d9a6cc` | version bump to 1.3.5 |
| `d6cb41f` | the ledger row |
| `04237f3` | the staged validation phases, the 1.3.4 reference, and the runbook |

## 1. The hostname write census

Built before anything was changed, because two sessions have now shipped a defect
caused by a host list living somewhere nobody enumerated. It is committed as a
deliverable in its own right at `docs/reference/HOSTNAME_WRITE_CENSUS.md`.

**The instrument was calibrated before it was trusted.** A canary carrying seven
shapes chosen to look like what was feared missing rather than what was already
known: hyphenated labels, an uncommon TLD, a bare host on its own line, a host in a
JSON array, an Inno `#define`, a host in a bash for-list, and a host embedded in a
URL with a path. The pattern found all seven. Its one honest limit is a hostname
assembled at runtime, which the canary also proved (only the literal tail was
found); that class is covered instead by enumerating the write sinks and tracing
variables back to them.

| # | Site | Host list | Class | Writes into | Revocable |
| --- | --- | --- | --- | --- | --- |
| 1 | `setup.ps1:100-140` | `$ProviderConfig.*.AllowlistHosts` | provider | `allowed_ipv4`, `allowed-ips.txt` | No, by design |
| 2 | `setup.ps1:1394-1455` | `$baseHosts` (9) | other / infra | `allowed_ipv4`, `allowed-ips.txt` | No |
| 3 | `setup.ps1:1479-1487` | `$toolchainHosts` (8) | toolchain | `toolchain_ipv4`, `toolchain-ips.txt` | Yes |
| 4 | `setup.ps1:2144` | `AUX_HOSTS`, install-time | provider | `allowed_ipv4`; persisted on iptables only | No |
| 5 | `setup.ps1:2230` | `AUX_HOSTS`, 5-hourly refresh | provider | `allowed_ipv4`; persisted on iptables only | No |
| 6 | `setup.ps1:1738-1767` | none, reads the persisted IP files | derived | all three sets at boot | n/a |
| 7 | `switch-provider.ps1:163` | `PROVIDER_HOST` | provider | `allowed_ipv4`, `allowed-ips.txt` | No, by design |
| 8 | `switch-provider.ps1:170` | `BASE_HOSTS` (16 = 9 infra + **7 toolchain**) | **MIXED** | `allowed_ipv4`, `allowed-ips.txt` | No |
| 9 | `clawfactory-toolchain.sh:74` | `TOOLCHAIN_HOSTS` (8) | toolchain | `toolchain_ipv4`, `toolchain-ips.txt` | Yes |
| 10 | `clawfactory-read-fetch.sh:67-96` | from `egress-policy.json` | read-fetch | `read_fetch_ipv4`, `read-fetch-ips.txt` | Yes |
| 11 | `clawfactory-fetchctl.js:368` | one host per `add`, from Studio | read-fetch | `egress-policy.json` | Yes |
| 12 | `send-lib.js:283` via `sendctl:144` | the user's SMTP host | send | `egress-policy.json` `send_actions` | Yes, broker-enforced |
| 13 | `resources/egress-policy.json` | shipped default | read-fetch, send | ships EMPTY for both | n/a |

### There is no fifth site, and that is the finding

Exactly **four** sites write into `allowed_ipv4`, the pair nothing can revoke: rows
1, 2, 4/5 and 7/8. The card asked whether a fifth existed. It does not.

What the census found instead is worse than a fifth site. **The comment at
`setup.ps1:1414` said there were THREE and named them.** It was wrong, it was the
audit trail of a security product, and the site it omitted is precisely the one that
shipped the defect. A reader who trusted that comment would have stopped looking
exactly one site early, which is a fair description of what happened in card #245.
Corrected in `2d081bc`, and the enumeration moved out of a comment and into a file.

### Two corrections to the card's premises

- The card described switch-provider as adding to an additive set. It **flushes**
  `allowed_ipv4` and rebuilds it. That is what made the fix non-trivial: "seed
  provider hosts only" would also have dropped the nine infra hosts `setup.ps1`
  seeds at install, so a switched box would have diverged permanently from a fresh
  one. Raised before implementing; the operator chose the drift-proofed shape.
- The persistence gap has **two** sites, not one. The card named the install-time
  copy; the same branch in the 5-hourly refresh script had the identical gap and is
  fixed with it.

## 2. What the toolchain hosts were doing in switch-provider, answered from the code

**Nothing.** They are a stale mirror, not a dependency.

The script's own comment said `baseHosts list must stay in sync with setup.ps1
Step-EgressFirewall ($baseHosts)`. At the time it was written, `$baseHosts` contained
those seven hosts. Card #245 moved them out into `@toolchain_ipv4` so the user's
toggle could revoke them, and did not update the mirror. The mirror is what the
shipped Start Menu item runs.

Nothing in the switch path needs GitHub or npm:

- `openclaw config set` and `openclaw models set` write local JSON.
- The gateway restart is `systemctl --user`, local.
- The only remote fetch is the ollama branch (`curl https://ollama.com/install.sh`),
  which runs **as root**, exempt from the uid-1000 chain (`meta skuid != 1000
  return`), and runs **before** the firewall step in any case.

Adjacent observation, reported and not fixed because it is out of scope: the ollama
branch's `ollama pull` runs as **clawuser** and needs `registry.ollama.ai`, which is
not in switch-provider's host list at all and whose `Host` field is `$null`. That is
a pre-existing gap independent of this card.

## 3. The fixes

### 3.1 switch-provider (`3818bc0`): the ship-blocker

The mirror was not edited, it was **deleted**. `setup.ps1` now records its own
`$baseHosts`, provider deliberately excluded, to `/etc/clawfactory/base-hosts.seed`
(root:root 0644), and switch-provider reads that. One owner, every other reader
reads. Same discipline as the existing `toolchain-hosts.seed`.

Two things make the class impossible here rather than merely fixed once:

- **A structural guard.** Whatever the base list turns out to be, the script asks
  `clawfactory-toolchain.sh --list-hosts` for the *live* toolchain list and refuses
  the rebuild if any of those hosts would reach `allowed_ipv4`. It compares against
  the live owner, not another copy. If the resolver cannot be asked, that is a fault
  and it denies.
- **Stated input-shape handling.** ABSENT means an older install: warn loudly, fall
  back to a toolchain-free built-in list. EMPTY or MALFORMED is FATAL and the
  firewall is left untouched, because a fault is not a preference.

The fallback is still a copy, so it was compared rather than trusted. Read from
`setup.ps1`'s AST and diffed against the literal: **9 hosts, identical, zero
toolchain hosts on either side.**

Input-shape sweep, run locally against the extracted reader:

| Shape | Result |
| --- | --- |
| present, valid | rc=0, returns exactly the 3 hosts in the rigged file |
| absent | rc=0, falls back to the 9-host built-in list, warns |
| empty | rc=1, refuses, names the file |
| malformed (embedded space) | rc=1, refuses, names the line |
| wrong-type (no dot, `localhost`) | rc=1, refuses, names the value |
| hostile (`; rm -rf /tmp/pwned`) | rc=1, refuses; **nothing executed** |
| hostile (`$(id)`) | rc=1, refuses; **nothing executed** |
| malformed (`..evil.com`) | rc=1, refuses |
| malformed (`-lead.com`) | rc=1, refuses |

Nine of nine as specified. **The first run of that sweep passed every case
including its own positive control**, which was a harness defect: the extracted
block re-assigned the very path under test, so every case silently read the
fallback. Fixed; the control now discriminates (3 hosts vs 9). This is exactly the
failure the calibrate-before-measuring rule exists to catch, and it caught it.

### 3.2 The persistence gap (`328e164`)

The iptables branch has always persisted each auxiliary provider address to
`allowed-ips.txt`. The nftables branch added them to the live set and stopped, so
nothing survived a ruleset re-apply. It went unnoticed because on a normal install
`$providerHosts` covers the same provider and *is* persisted by
`Step-EgressFirewall`. It bites on `-Provider later`, where there is no provider
host at all. Fixed at both sites.

### 3.3 The install-time provider gate (`20a2d67`)

`Step-AssertProviderRoute`, running **last**, **as clawuser**, **inside WSL**,
**after every firewall write**. A TCP connect to the provider host on 443 via bash
`/dev/tcp`: no curl, no body, no credential, no tokens. DNS is checked separately
from the connect so the message names the right subject. Three attempts, so the gate
is not flaky, which is how a real gate gets disabled by the next person.

Fails the install loudly, per the pre-made decision. Skips, **with the reason printed
in the installer output**, when the provider is deferred (`-Provider later`) or is
ollama (local endpoint). A provider with no `AllowlistHosts` entry FAILS rather than
skips: that is a defect in the provider map, and skipping would silently reintroduce
the gap the step exists to close.

**Stale premise reported.** The card named `/DEFERKEY=1` as a deferral path. **No
such flag exists anywhere in the tree.** Deferral reaches `setup.ps1` only as
`-Provider later`, from wizard option 5 via `GetProviderLabel`, so that is what the
skip keys on.

**The two limits, in a comment at the site and repeated here.** It does not cover the
cfv-167 symptom: those turns failed while a TCP connect would have succeeded, so this
gate would have passed there. And it will correctly refuse an install on a machine
whose provider is unreachable for an unrelated reason, such as a corporate proxy or
an offline build box.

The probe was calibrated on rigged inputs with known answers before being trusted:
the OK arm connects to two real provider hosts, and the TCP arm and DNS arm each
fire with their own distinct message. **The first calibration attempt failed its own
positive control** because Git Bash has no `getent`, which is an environment defect in the
calibration, not the probe; re-run under a `getent` shim with the probe body
byte-identical.

## 4. Task 4, the validation: STAGED, NOT RUN

| # | Test | Status |
| --- | --- | --- |
| 1 | Clean install, all resources, all pins | **NOT RUN** |
| 2 | Provider gate passes healthy + CONTROL fails blocked | **NOT RUN** (phase staged; level-1 control calibrated locally) |
| 3 | Gate skipped with a stated reason under deferred provider | **NOT RUN** |
| 4 | `SP.*` no toolchain address enters after a switch | **NOT RUN** (A/B staged) |
| 5 | `SP.*` toggle OFF, GitHub and npm unreachable after switch and reboot | **NOT RUN** |
| 6 | CONTROL for 5: toggle ON, they are reachable | **NOT RUN** |
| 7 | `TC.3` re-run | **NOT RUN** |
| 8 | `TC.1,2,4,5,6,7,8` regression | **NOT RUN** |
| 9 | Five MANUAL panel checks | **NOT RUN, and never yet passed** |
| 10 | Reboot pass | **NOT RUN, and never yet passed** |
| 11 | Harness self-test 15/15 | **build machine: PASS 15/15.** On the box: NOT RUN |
| 12 | Zero malformed verdict rows | **NOT RUN** |

Tests 9 and 10 have never passed and are **not** recorded here as passing on the
strength of having been deferred again.

### What is staged

- `validation/interim-v135-switchprovider.ps1` is the A/B on one box, toggle held
  OFF throughout, only the script text differing. Two boxes would have introduced a
  second variable into the one comparison this card exists to make. It is also
  self-cleaning: the fixed script's own flush removes the pollution the pre-fix arm
  creates.
  - PRE arm = `validation/sp-prefix-fw.sh`, sha256
    `bee579419e262c7028b53b8fc09388562e8bc48427a7b3d26a2364215b404da0`, rendered
    from commit `9710c5a` so it is provably the shipped 1.3.4 text, not a hand-copy.
  - POST arm = rendered **on the VM from the INSTALLED** `switch-provider.ps1`, so
    the fixed arm tests the artifact that was installed rather than a repo copy.
- `validation/interim-v135-providergate.ps1` rigs the provider unreachable via
  `/etc/hosts` and TEST-NET-1 rather than a firewall edit, because
  `Step-EgressFirewall` rewrites the ruleset and would undo a rigged rule during the
  very re-run meant to observe it. Level 1 calibrates the shipped probe in both
  directions in seconds; level 2 observes the installer actually aborting and costs
  a full install. **When level 2 is not run it writes an explicit INFO row**, because
  a skipped control and a passed control must never look the same in a results file.
- `validation/RUNBOOK_v135.md` carries the phase order, exact commands, and the environment
  clauses.

### What was verified before any VM time

- Both phases parse clean.
- All seven literal bash bodies pass `bash -n`.
- The interpolated reachability body expands with zero leaked escapes and zero
  unexpanded PowerShell variables, and passes `bash -n`.
- `probe()` calibrated locally in both directions: CONNECTED for a live host,
  blocked for a closed port.
- Two defects found and fixed in the staging itself: `Compare-Independent` takes
  `-Reported`, not `-Theirs`; and the first draft moved the rendered script over
  `/mnt/c`, which is **absent by design** on a correct install, so that probe would
  only ever have worked on a broken one. It now travels the 9p file channel with a
  byte-count check. The Windows-side render was also moved off `powershell -Command`
  onto a file invocation, since a multi-line script on argv is the L22 shape.

## 5. The questions the card asked, answered

- **The defect demonstrated before the fix and absent after, both verbatim.**
  NOT YET. It requires the VM. The A/B is staged and its reference artifact is
  pinned by digest.
- **Does `-Provider later` now survive a ruleset re-apply?** NOT YET MEASURED. The
  code change is in and its mechanism is the same append the iptables branch has
  always used, but that is an argument, not a measurement, and this document does
  not promote arguments to results.
- **The provider gate proven in both directions plus the deferred skip.** The
  *probe* is proven in both directions on rigged inputs on the build machine. The
  *gate* in situ, and the deferred skip, are NOT YET RUN.
- **The MANUAL checks and the reboot pass resolved rather than carried.** Not
  resolved. Carried, for the fourth time, and said plainly.

## 6. Did anything widen?

**The toolchain fix narrows and nothing else.** Seven hostnames stop entering
`allowed_ipv4` through the switch path. Nothing was added to any set, no accept was
broadened, no port was opened, and the provider route is untouched. The fallback was
diffed against `$baseHosts` and is identical and toolchain-free.

**The persistence fix does widen one thing, and it is the point of the fix.**
Appending the auxiliary provider addresses to `allowed-ips.txt` means that file now
accumulates every address the provider has ever resolved to and never drops one, so
a retired provider address is re-added at each boot. It is bounded rather than
permanent: set elements carry a 6h timeout, so an address that no longer resolves
expires within 6h of the boot that re-added it. This is identical to what the
iptables branch has always done, it applies only to the provider route which is
deliberately always-open, and rewriting the file each tick was rejected because it
would drop the base hosts `Step-EgressFirewall` wrote into the same file. Stated in
a comment at the site. The class is already carded ("Allowlist addresses persist up
to 6h after a host is removed from source").

**The provider gate only refuses; it can never open a route.**

## 7. Watch item, do not chase

The cfv-167 turn failures remain unexplained. The misplaced-instrument hypothesis
explains the phantom drop lines but not why three turns failed at 301s and 165s with
an `api_error` when cfv-168 completed four turns in 20 to 48 seconds. That box is
gone and its probe was never committed, so nothing is re-measurable. Logged. A second
occurrence is what would make it chaseable. The new provider gate does **not** cover
this: a TCP connect would have succeeded on that box.

## 8. Other findings, reported not fixed

- **The signing certificate expires 2026-08-20, which is tomorrow.** This artifact
  stays valid because the signature carries a countersigned timestamp good to
  2026-10-22, but **the next build after tomorrow needs a renewed certificate.**
- `CHANGELOG.md` stops at 1.1.1 and has no entries for 1.2.0 through 1.3.5. It is
  stale rather than wrong. Not fixed: adding a lone 1.3.5 entry to a changelog
  missing five releases would make it look maintained when it is not.
- `switch-provider.ps1`'s ollama branch pulls a model as clawuser against
  `registry.ollama.ai`, which is in no allowlist it writes.

## 9. Next action

The operator starts the VM run. `validation/RUNBOOK_v135.md` carries the phase
order and the exact commands. The provisioning handoff card was printed at the end
of this session.
