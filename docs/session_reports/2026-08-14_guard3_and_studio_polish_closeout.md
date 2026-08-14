# Guard 3, web off by default, plus Studio polish. Close-out, 2026-08-14.

Dispatch card #244. Track: v1 fast-security-harness.

Input: Secure-Setup at `acd0250`, Studio at `8b4e238`, artifact `29acdf95...`.
Output: Secure-Setup `1d55b14`, Studio `34c9947`, artifact `6282a228...`.

---

## 1. Guard 3 ground truth, established by execution before anything was built

The job asked for this first, and it changed the shape of the work.

**What the read-fetch section contained, and what enforced it.** `read_fetch: { allow: [] }`,
root:root 0644, and nothing enforced it. Confirmed two ways: the whole tree had zero consumers
of the key, and `send-lib.js` read only `send_actions`. The smoke close-out was right.

**How the agent reaches the network.** The gateway runs as **uid 1000**. The three brokers run
as root. `net.fetch` was deliberately left to the firewall rather than the tool denylist
(`setup.ps1`, Step 9a). So every agent fetch leaves as uid 1000, whether from the fetch tool or
from a shell.

**Where enforcement belongs: the firewall, and it was already denying.** Measured on a live
install with both controls in the same run:

| Probe | Result |
| --- | --- |
| uid 1000 to `example.com:443` | timed out, `http=000`, exit 28 |
| CONTROL, uid 1000 to `api.anthropic.com:443` | `http=404`, exit 0, so TLS and HTTP completed |
| CONTROL, root to `example.com:443` | `http=200`, exit 0 |

So deny-by-default already existed and was structural. **Guard 3 is not a new denial. It is the
user's ability to open and close a named hole in one that was already closed**, and it makes the
previously inert policy section the thing that governs it. That is why it stayed config plus UI.

**The provider-allowlist interaction, which is the part most likely to bite Guard 4 or v2.**
Two findings, and the second is the load-bearing one.

1. The baseline set is **not** "the model provider". `AUX_HOSTS` is ten hostnames: three model
   providers plus `clawhub.ai`, `api.github.com`, `raw.githubusercontent.com`,
   `objects.githubusercontent.com` and `registry.npmjs.org`. On the probe box those resolved to
   **72 live addresses**, including GitHub's shared content CDN (`185.199.108-111.133`) and two
   dozen Cloudflare edge addresses (`104.16.x.x`). "A fresh install reaches the model provider
   and nothing else" was **false before Guard 3 existed** and is still false.
2. Because the set is address-scoped, read-fetch and provider traffic are indistinguishable for
   any host that resolves to an already-allowed address. `example.com` itself resolves to a
   Cloudflare address and was blocked only because that particular edge address is not in the
   set. DNS is no help: uid 1000 resolves arbitrary names freely, so only the connection is
   gated.

This did not move Guard 3 out of the firewall. The firewall is the only layer that survives the
agent's `exec`, so it stays the enforcement point. It does mean Guard 3's claim is about
**destination addresses, not hostnames**.

**AUX_HOSTS was deliberately not trimmed.** Removing GitHub and npm would break the agent's real
code workflows, is well outside config plus UI, and would have shipped a breaking change with no
test for what it breaks. The copy states what is actually reachable instead. Carded.

---

## 2. What Guard 3 is

| Piece | Where |
| --- | --- |
| `read_fetch_ipv4` | a second nft set, 443-scoped accept, empty on a fresh install |
| `clawfactory-read-fetch.sh` | root-owned resolver: flush first, then repopulate |
| `clawfactory-fetchctl.js` | the only write path, 0750 root:root |
| `install-read-fetch.sh` | installs the above, proves the set is live, runs the tripwire |
| Web access panel | Studio, three IPC channels, one destination at a time |

**Why a second set rather than reusing `allowed_ipv4`.** The provider set is refreshed
additively by hostname every five hours and its elements carry a timeout, so nothing in it is
ever deliberately removed. A user destination placed there **could not be revoked**: the next
refresh would put the address back and the user's removal would silently not take.
`read_fetch_ipv4` is flushed and rebuilt from the policy on every run, so removing a site in
Studio actually removes its route. Test `G3.3c` proves that, twice, including after a reboot.

**Fail-closed by ordering, not by a check.** The set is flushed *before* anything is resolved or
added, so every failure path leaves it narrower rather than wider. An unreadable or malformed
policy ends with an empty set and a loud message, and the provider route is untouched because it
lives in a different set.

**Validated inputs at three layers.** The IPC channel, the PowerShell engine and the root control
tool each refuse a malformed destination without trusting the layer above. The resolver keeps its
own copy specifically because it reads a file on disk and must not assume the control tool wrote
it. Tested against wildcards, schemes, ports, paths, command injection and shell metacharacters;
all refused, with the legitimate forms accepted.

---

## 3. Structural or advisory, and every bypass named

**Guard 3 is STRUCTURAL with respect to the agent, at the level of network addresses.**

It holds because the nft chain filters by **uid**, not by process. The agent cannot escape it by
choosing a different tool, shelling out, or writing its own client. Proven across ten channels in
`G3.4`: writing the policy file, the persisted address list, the host list and `/etc/nftables.conf`;
running the control tool directly and through node; running the resolver; adding a set element by
two paths; and restarting the refresh unit. All refused, against a positive control showing uid
1000 can write `/tmp`.

**What it does NOT claim, and these are the bypasses.**

1. **Address-level, not hostname-level.** An nftables set holds addresses. Any host sharing an
   address with something already reachable is reachable, whether that is the provider, the
   toolchain, or another site the user allowed. On shared CDN infrastructure this is a large set.
   This is the residual, it is permanent for v1, and no wording should imply otherwise.
2. **The baseline route is always open.** Ten hostnames and 72 addresses on the probe box,
   including GitHub's shared content CDN. A fresh install is not "provider only".
3. **DNS is not gated.** uid 1000 resolves any name it likes. Only the connection is stopped, so
   name lookup remains a low-bandwidth signalling channel. Pre-existing, unchanged by Guard 3.
4. **Root compromise ends it**, as it ends everything else. Not specific to Guard 3.
5. **The five-hour window.** A destination removed from the policy loses its route immediately
   because the control tool re-derives the set on every write. But an address that *moves* is only
   re-resolved on the refresh cycle, so a stale address can remain briefly reachable.

The claim is narrower than "web off by default" sounds. It is still worth having: the default is
deny, the user controls the exceptions, and the agent cannot grant itself one.

### 3.1 The claim sentence

Written to survive a copy audit without softening:

> **Web access is denied by default. Your agent can reach the AI provider, the software sources
> ClawFactory needs, and the network addresses of the sites you have allowed. Nothing else.**

"Network addresses of the sites you have allowed" is doing deliberate work. It does not collapse
into "only the sites you list", which would be false.

The panel currently ships a longer footnote saying the same thing. It is honest but **incomplete**:
it notes that a site sharing an address with the provider may be reachable, and omits that the
same is true of a site sharing an address with one the user allowed. Replacement text, agreed with
Bret and deferred rather than rebuilt (see section 9):

> A site you have not added is not reachable. Two things stay reachable whatever this list says:
> the AI provider your agent talks to, and the software sources ClawFactory needs to run, which
> are GitHub and npm. Matching is by network address rather than by name, so allowing a site also
> allows anything else served from the same address. Removing a site takes effect immediately.

---

## 4. Studio polish, five items

| # | Item | Outcome |
| --- | --- | --- |
| 3.1 | Expired approval requests invisible | **Fixed.** Returned in their own array, filtered to what lapsed since the panel was last viewed, with dismiss |
| 3.2 | Footer says MIT | **Fixed.** PolyForm Perimeter 1.0.0. See below on the repo LICENSE |
| 3.3 | Header reads `v0.1.0` | **Fixed.** Reads the running app's real version through the shell |
| 3.4 | Studio installer filename | **Fixed.** Studio moved to 1.2.0, so filename, header and package metadata all read one field |
| 3.5 | Truncated attachment hash | **Fixed.** Reveal control, verified by hand against the broker-derived value |

**On 3.2, the brief was out of date.** Secure-Setup's `LICENSE` was already PolyForm Perimeter
1.0.0, swapped in `5899d25` during the Ship-B batch. Only Studio still shipped MIT. It now carries
the same text byte for byte so the two cannot drift. A standing memory note also said the repo
licence was still MIT; that note was wrong and has been corrected.

**On 3.1, the design is anchored to the user's absence, not to a clock.** Expired records come
back in a **separate array** from pending rather than as a flagged member of one list, because a
renderer that forgot to check a flag would draw an approve button on a dead request. The
last-viewed mark advances when the user *leaves* the panel, not when they arrive, so cards do not
vanish under someone still reading them. Dismiss clears a card and keeps the audit record, and
the broker refuses to dismiss anything still pending, so it cannot hide a live decision.

Both pre-existing refusals were re-proven rather than assumed: `handleApprove` still refuses
non-pending state with `ESTATE` and still re-checks expiry under the store lock with `EEXPIRED`.

**One change beyond the five, and it was necessary rather than absorbed.** The egress policy file
now has two writers, so `setSendDestination` takes the shared store lock. Without it, a
simultaneous SMTP save and destination add could drop one write, and the one that gets dropped is
the user's authorized send destination. Guard 3 must never be the reason a user loses that.

---

## 5. Artifacts

| | Value |
| --- | --- |
| Studio installer | `540bb30b6f163ae2fb3b381d4491e5b6a25b2973add7d69615fb078a8b156fb9` |
| Studio bytes | 100,032,544 |
| Studio commit | `34c9947` |
| ClawFactory installer | `6282a228e620d7d580f7bedadb0a96c9b166f037f2dd83645911b5fcf90603f0` |
| ClawFactory bytes | 440,596,328 |
| Gates | all seven: soul, bundle, studio, version, persona, workspace-soul, rootfs |
| Authenticode | `Valid`, `CN=Bret Mckinney`, timestamped, both artifacts |

The bundle gate reported **33** resources, up from 30, confirming the three new Guard 3 files are
bundled. It derives its list from Step-Preflight rather than from a copy, so it needed no edit.

**Panel markers.** All 26 present in the packaged `app.asar`, including the 12 carried forward so
the change dropped nothing. Controls: `v0.1.0` and `MIT licensed` both **absent**, which is direct
evidence for two of the five polish items, and the positive control `Workspace` present.

**A marker check that would have read as a pass.** The same search over the compiled NSIS
installer finds *nothing*, because the payload is compressed. Its absent-controls section still
printed clean; only the positive control caught it. Recorded so nobody later reads that as
evidence. The check that means something is the one against the installed `app.asar`, which
`G3.8` performs on the box.

**NOT fixed, and it is the same hazard one level up.** The ClawFactory installer version is still
1.2.0, so this artifact is the **third** distinct payload carrying that version. The digest is the
authority. Bumping it is a release decision and would have rippled through the validation harness
immediately before a run.

---

## 6. Validation

Two VMs. `Standard_D2s_v4`, image `clawfactory-win11-baseline-v2`, both deviations carried
forward from prior runs and re-confirmed live.

### 6.1 cfv-161: the installer refused to finish, and it was right to

Phase 1 FAILED. `install-result.txt: INSTALLER_DONE=failure`, aborting at Step-InstallSend with
"firewall re-apply failed".

Root cause, mine. `setup.ps1` writes `clawfactory-fw-apply.sh` from a **double-quoted** PowerShell
here-string, where the backtick is the escape character. A comment referred to `nft -f` inside
backtick code quotes. PowerShell read backtick-n as a newline, split the comment, and emitted its
tail into the generated script as a command:

```
/usr/local/sbin/clawfactory-fw-apply.sh: line 44: ft: command not found
fw_apply_rc=127
```

`fw-apply` runs under `set -euo pipefail`, so it died, and `install-send.sh` refused to continue.

**The installer aborting is the correct outcome and is the headline of this failure.** It declined
to finish rather than leave a machine claiming a control it did not have. The fail-closed design
surfaced my bug on a test box instead of a customer one.

I then made the identical mistake inside the comment written to *explain* the mistake, and caught
it on re-read. Every block added to `setup.ps1` was audited afterwards; both shell here-docs are
clean. The two pre-existing hits at lines 1495-1496 are harmless, because backtick-o and
backtick-m are not PowerShell escapes and the backtick is simply dropped.

### 6.2 cfv-162: green

Phase 1: **13 PASS, 0 FAIL, 0 VOID, 5 INFO**. Install succeeded, 33/33 resources by independent
enumeration, all pins re-derived, version 1.2.0.

Phase 6 first run: four FAILs and one PASS, **all five meaningless**. A fresh box has no SMTP
credential, so Guard 2 correctly refused to queue anything, the ids came back empty, and `sendctl`
printed usage text instead of refusing anything. The PASS was the more dangerous of the two
outcomes. Scored VOID and re-run after Bret configured SMTP.

Phase 6 second run: **0 FAIL, 0 VOID**. Post-reboot pass: **0 FAIL, 0 VOID**.

---

## 7. Carried-forward test table

| Id | Test | Verdict | Note |
| --- | --- | --- | --- |
| P1.* | Clean install, 33 resources, seven pins | **13 PASS / 0 FAIL** | |
| P1.3b | Installer count and probe count reconciled | PASS | **new**, see 8.2 |
| PIN.studio | Embedded Studio payload | INFO | vacuous on a successful install, see 8.3 |
| G3.0a | Guard 3 installed: resolver, tool, set, 443 accept | PASS | checked before anything is measured through it |
| G3.0b | Write path is 0750 root:root | PASS | |
| G3.0c | Chain-shape tripwire covers Guard 3 | PASS | |
| G3.0d | Fresh install has an empty allowlist | PASS | |
| G3.1 | Non-allowlisted sites unreachable for uid 1000 | PASS | four subjects |
| G3.1b | CONTROL: provider route still works | PASS | its failure would void every block above |
| G3.2 | A real agent turn completes | PASS | warmed first, L17 |
| G3.3a | A user-added destination becomes reachable | PASS | the half deny-by-default cannot prove |
| G3.3b | CONTROL: only that destination | PASS | control host chosen by verified address-disjointness |
| G3.3c | Revoking actually removes the route | PASS | why the second set exists |
| G3.3d | Send destination survived a read-fetch write | PASS | shared policy file, shared lock |
| G3.4 | Agent cannot modify the list, ten channels | PASS | with a positive control |
| G3.5 | Survives the shipped five-hourly refresh | PASS | real unit, tripwire on ExecStartPost |
| G3.6a | EEXPIRED still refuses | PASS | control refused with the DIFFERENT code EHASH |
| G3.6b | ESTATE still refuses | PASS | showing a card did not make it approvable |
| G3.6c | Expired requests returned in a separate array | PASS | `EXPIRED_COUNT=2` |
| G3.7a | Dismiss removes the card | PASS | |
| G3.7b | Dismiss does NOT delete the audit record | PASS | state, recipients, hash all still on disk |
| G3.7c | CONTROL: dismiss refuses a pending request | PASS | cannot hide a live decision |
| G3.8 | Panels present in the INSTALLED app.asar | PASS | 0 missing, stale markers absent, control not blind |
| G3.*.POSTREBOOT | All of the above after a full restart | **PASS** | 0 FAIL / 0 VOID |
| MANUAL.1 | Full attachment hash revealed | PASS | matched the broker value character for character |
| MANUAL.2 | Expired card visually distinct | PASS | badge, amber, "nothing was sent" |
| MANUAL.3 | Expired card has no approve control | PASS | Dismiss only, against a live card showing Approve and Deny |
| MANUAL.4 | Dismiss clears the card from the panel | PASS | |
| MANUAL.5 | Web access panel: add, refuse bad input, remove | PASS | driven by hand |

---

## 8. Harness defects found, and they produced wrong results today

### 8.1 An unchecked `az` call cost a whole run

`az vm user update` was called with **no exit-code check**, immediately before its password was
written into Winlogon `DefaultPassword` and the box rebooted. On cfv-162 the VMAccess extension
hung in state `Updating`, so the reset never applied: the account kept its provisioning password,
auto-logon failed against the new one, no interactive session existed, the runner never started,
and the driver polled a dead box for 48 minutes. This is L6, in the one place in the chain still
missing the check. Now checked, and the poll aborts at roughly 12 minutes on a persistent
`no-runner` with the registry keys and event log to inspect.

The stop/start performed by the parking job is what eventually un-stuck the extension.

### 8.2 An "independent copy" that was never compared

Phase 1 holds its own copy of the resource list *specifically* so a disagreement with the
installer is itself the finding. The run printed `installer reports 33 resources` and `all 30
required resources present` on adjacent lines and passed both, because each side only ever counted
itself. An independent copy that is never reconciled is not independence, it is a second stale
list. `P1.3b` now compares the counts directly.

### 8.3 A pin that can only fire when something else has already failed

`PIN.studio` had never been changed since the file was created and was two Studio builds stale. It
failed a correct build on cfv-161.

I initially reported this as an unexplained inconsistency with the cfv-160 smoke close-out, which
reports 0 FAIL. **That was my error and the earlier close-out was sound.** The check only derives a
digest when the staged Studio payload survives, which happens only when the install fails before
`ssPostInstall`. cfv-161 failed early and kept it; cfv-160 succeeded and correctly got INFO.

The real finding is that the pin is **vacuous on the happy path**. It cannot detect the drift it
exists to detect on any successful install. Repinning it was still right, but it must not be
counted as drift protection. `G3.0a` tests the installed mechanism instead.

### 8.4 My own probe defects, three of them

- **Missing precondition.** Phase 6 assumed a configured SMTP credential. On a fresh box Guard 2
  fail-closes and nothing can be queued, so four FAILs and one PASS were produced from an absent
  subject. Now guarded twice: once on the credential summary and once on the returned ids, both
  recording VOID with a named reason. A missing precondition is not a product verdict.
- **A control that expired with its subject.** The live control was queued alongside the two meant
  to expire, before a wait longer than the TTL, so `approve C with a wrong hash` would have
  returned `EEXPIRED` rather than `EHASH`. A control that fails for the same reason as the subject
  is not a control. Now queued after the wait.
- **A hand-check with a ten-minute fuse.** The card staged for the by-hand hash check expired
  before Bret reached it, twice. A check whose subject destroys itself on a timer cannot be handed
  to a human without staging it immediately beforehand.

### 8.5 The parking job

`finish-and-park.ps1` waited only for the driver's *success* line, so on the error path it sat out
its full timeout and then deallocated underneath a live `run-command`, stacking an
`OperationPreempted` error on top of a diagnosable failure. It now treats `DRIVER ERROR` as
terminal. Its unconditional `finally` deallocation worked exactly as intended and stopped the VM
through a human handoff with nobody watching.

---

## 9. Deferred deliberately

**The Web access footnote.** The replacement text in 3.1 is agreed but not shipped. Applying it
means rebuilding Studio, re-signing, repinning, rebuilding the installer, re-signing and
reinstalling, which discards the build this session validated for a text-only change, and would
leave the reboot evidence describing a different build. The current text is incomplete rather than
false. First item on the next Studio pass, text recorded verbatim above so it cannot drift.

**Also carded:** trimming `AUX_HOSTS`; bumping the ClawFactory installer version; the stale
"Studio backend unreachable" banner on the home route, whose wording caused the D4 misdiagnosis
and is still misleading; the `v1.2.0Templates` header spacing; and `PIN.bundle`'s label still
saying 30 while checking 33.

---

## 10. Resource ledger

| Resource | Created | Disposed | Evidence |
| --- | --- | --- | --- |
| VM `cfv-161` | 2026-08-14 10:53 local | **deleted** 11:52 | install aborted; deleted before cfv-162 |
| `cfv-161-osdisk` | with the VM | **deleted** 13:5x | orphaned by the VM delete, swept explicitly |
| `cfv-161VMNic`, `-pip`, `-nsg` | with the VM | **deleted** | swept explicitly after the same orphan check |
| VM `cfv-162` | 2026-08-14 11:49 local | **deleted** 16:27 | teardown proof below |
| `cfv-162-osdisk`, `VMNic`, `-pip`, `-nsg` | with the VM | deleted | named explicitly in teardown |
| NSG rule `allow-rdp-from-operator` | during the run | deleted with the NSG | scoped to a single `/32`, never `0.0.0.0/0` |
| License slot | on install | **released** | `Machine deactivated successfully` |
| Blobs in `validation` container | staged | retained | evidence, not billable compute |

Teardown proof, unfiltered: the only resources remaining in `clawfactory-validation` are the
storage account, the VNET and the two baseline images. **No resource matching `cfv-161` or
`cfv-162` remains.**

`cfv-162` was **deallocated** for roughly 25 minutes mid-run, by the parking job, across a human
handoff. That was deliberate and it is the behaviour to keep.

**Credential hygiene.** The SMTP app password was typed by Bret into the Studio panel and never
entered a script, a transcript, or the model's context. It remains the kept throwaway; no new one
was generated and none was revoked, per the standing decision. Two VM admin passwords were reset
by Bret directly through `az`, chosen by him and never seen here.

---

## 11. Lessons learned

`ClawFactory_Install_Lessons_Learned.md` gains **L29: a control that cannot fail is not a control,
and a pass from an absent subject is worse than a failure.**

This session produced four separate results that looked like verdicts and were not:

- Phase 6's first run: four FAILs and a PASS from a queue that was empty.
- The marker search over the compiled installer: an all-clear on absent controls from a search
  that found nothing at all, caught only because the positive control failed.
- `PIN.studio`: a pin that reports INFO on every successful install, so it can only speak when
  something else has already broken.
- Phase 1's resource count: two numbers disagreeing on adjacent lines, both passing.

The shape they share is that **the measurement succeeded while the thing being measured was
absent**. This is the same family as L28, one level down: L28 was about weak signals agreeing,
this is about a signal with nothing behind it. The discipline that catches it is already the
project's own, applied more strictly: every assertion needs a control that must fail *in the same
run*, and when the control does not discriminate, the result is VOID rather than PASS.

### 11.1 The provider allowlist and user destinations, recorded for Guard 4 and v2

The job asked for this specifically.

The two lists cannot be separated at the firewall, because nftables sets hold addresses and
hostnames are co-hosted. Practical consequences:

1. **Never put user destinations in the provider set.** The provider set is refreshed additively
   by hostname with a timeout, so an element placed there cannot be revoked. Two sets is not
   tidiness, it is the only way removal works.
2. **The baseline is much wider than it reads.** Ten hostnames became 72 addresses, including a
   shared content CDN and two dozen Cloudflare edges. Any claim about what a fresh install can
   reach must be derived from the resolved set, not from the hostname list.
3. **Address-scoping is the permanent v1 residual.** Hostname-exact enforcement needs something
   that sees the SNI or the Host header, which means a fetch broker, and a broker in the agent's
   own uid is advisory rather than structural. Making it structural means the outbound injector
   question from card #197: if the bundled provider plugin honours a `baseUrl` override, a
   root-owned outbound proxy could hold the key and enforce hostnames at once. Do not build before
   that question is answered.
4. **Port scoping is what keeps this bounded.** Both accepts are `tcp dport 443` only. If either
   ever widens, every co-hosted address becomes reachable on whatever port was opened. That is why
   the tripwire checks both accepts by name and fails the unit if either drifts.

### 11.2 Two smaller ones

- **Backticks in a double-quoted PowerShell here-string alter the emitted shell text.** Only the
  escapes that map to control characters matter: backtick-n, backtick-r, backtick-t and friends.
  Backtick before anything else is silently dropped, which is why the pre-existing instances were
  harmless and mine was fatal. Never write a code-quoted reference inside one, not even in a
  comment.
- **`az vm run-command` runs as SYSTEM, and WSL refuses to run there.** Every WSL test needs the
  interactive session. Auto-logon is a one-shot: after any reboot, a human must log in over RDP
  and start the runner by hand before any WSL work can proceed. This is not scriptable around and
  should be planned into any run that includes a restart.

---

## 12. Out of scope, confirmed untouched

No Guard 4. No Studio restyle beyond the five named items. No marketing copy beyond the footer and
the licence file. No tag, no publish, no Inno licence purchase. `SECURITY.md:114` left alone. Step
7, full assembled-build validation, not run: it comes after Guard 4.
