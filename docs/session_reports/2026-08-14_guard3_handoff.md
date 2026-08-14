# Guard 3 and Studio polish. Session handoff, 2026-08-14.

Written to be read cold by whoever holds the original work package. Self-contained: you
should not need the transcript.

**Dispatch card #244, moved to done.**
Input: Secure-Setup `acd0250`, Studio `8b4e238`, artifact `29acdf95...`.
Output: Secure-Setup `bd66c26`, Studio `34c9947`, artifact `6282a228...`.
Full technical close-out: `docs/session_reports/2026-08-14_guard3_and_studio_polish_closeout.md`.

---

## 1. Bottom line

Guard 3 is built, validated green on a clean box, validated again after a reboot, and
pushed. All five Studio polish items are fixed. Nothing in the work package was left
undone except one item deliberately deferred with its replacement text recorded, and one
item whose premise turned out to be already satisfied.

The honest headline is narrower than the feature name. **Guard 3 works exactly as
specified, but the baseline it sits on is wider than anyone had written down.** A fresh
install reaches 72 network addresses, not just the model provider. That was true before
this session and Guard 3 did not cause it, but Guard 3 is the first time the product makes
a public promise about web access, so it now matters.

---

## 2. Every item in the work package, and what happened to it

### 2.2 Ground truth, reported by execution before building

All four questions answered on a live install with controls. Summarised:

| Question | Answer |
| --- | --- |
| What does `read_fetch` contain, what enforces it? | `allow: []`, and nothing. Zero consumers in the tree. The smoke close-out was right |
| How does the agent reach the network, as which uid? | Gateway runs as **uid 1000**; brokers run as root. `net.fetch` was deliberately left to the firewall |
| Firewall, broker, or both? | **Firewall**, and it was already denying. Measured: uid 1000 to example.com:443 times out, to api.anthropic.com:443 returns 404, root to example.com returns 200 |
| Provider allowlist vs user read-fetch list? | Indistinguishable at the firewall for any co-hosted address. See section 4 |

**The finding that reshaped the job: deny-by-default already existed and was already
structural.** Guard 3 does not create the denial. It gives the user a way to open and
close a named hole in a denial that was already closed, and it makes the previously inert
policy section the thing that governs it. That is why it stayed config plus UI, exactly as
the work package predicted.

### 2.3 Build requirements

| Requirement | Status |
| --- | --- |
| Allowlist lives in the existing root-owned policy file, no second config | Done |
| Default deny; fresh install reaches the provider and nothing else | **Partly.** Default deny is done and proven. "Nothing else" is false because of the pre-existing baseline. See section 4 |
| Additions by the user through Studio, never the agent; proven | Done. Ten channels tested, all refused, with a positive control |
| Fail closed on unreadable or malformed policy, loudly | Done. The set is flushed before anything is added, so every failure path narrows rather than widens |
| Survives the five-hour refresh; tripwire covers it | Done, and re-proven after a full reboot |

### 2.4 Honesty constraint

**Verdict: Guard 3 is STRUCTURAL with respect to the agent, at the level of network
addresses.** It holds because the nft chain filters by uid rather than by process, so it
survives the agent's shell. It is not hostname-exact.

Five bypasses, all named in the close-out: address-scoping (anything co-hosted on an
allowed address is reachable, including addresses shared with sites the user allowed); the
always-open baseline route; ungated DNS; root; and a five-hour window before a moved
address is re-resolved.

**Claim sentence, written to survive a copy audit without softening:**

> Web access is denied by default. Your agent can reach the AI provider, the software
> sources ClawFactory needs, and the network addresses of the sites you have allowed.
> Nothing else.

"Network addresses of the sites you have allowed" is deliberate. It does not collapse into
"only the sites you list", which would be false.

### 3. Studio polish, five items

| # | Item | Status |
| --- | --- | --- |
| 3.1 | Expired approval requests invisible | Fixed. Own array, filtered to what lapsed since last view, with dismiss. `ESTATE` and `EEXPIRED` both re-proven |
| 3.2 | Footer says MIT | Fixed in Studio. **The repo `LICENSE` was already PolyForm** (`5899d25`), so the brief's premise was stale |
| 3.3 | Header reads `v0.1.0` | Fixed. Reads the running app's real version through the shell, so it cannot drift again |
| 3.4 | Studio installer filename | Fixed. Studio moved to 1.2.0, so filename, header and package metadata all read one field |
| 3.5 | Truncated attachment hash | Fixed. Reveal control, verified by hand character for character against the broker value |

On 3.1, two design choices worth carrying forward. Expired records come back in a
**separate array** from pending rather than as a flagged member of one list, because a
renderer that forgot the flag would draw an approve button on a dead request. And the
last-viewed mark advances when the user **leaves** the panel, not when they arrive, so
cards do not vanish under someone still reading them.

One necessary change beyond the five: the egress policy file now has two writers, so
`setSendDestination` takes the shared store lock. Without it a simultaneous SMTP save and
destination add could drop one write, and the one dropped would be the user's authorized
send destination.

### 4. Build and validation

**Artifacts.** ClawFactory `6282a228e620d7d580f7bedadb0a96c9b166f037f2dd83645911b5fcf90603f0`,
440,596,328 bytes. Studio `540bb30b6f163ae2fb3b381d4491e5b6a25b2973add7d69615fb078a8b156fb9`,
100,032,544 bytes. All seven gates passed. Both Authenticode Valid and timestamped.

**All nine required tests were run.**

| Pass | Result |
| --- | --- |
| Phase 1, clean install | 13 PASS / 0 FAIL / 0 VOID |
| Guard 3 suite (tests 1 to 8) | **0 FAIL / 0 VOID** |
| Post-reboot pass (tests 1, 2, 5) | **0 FAIL / 0 VOID** |
| By-hand panel checks (test 9) | 5 of 5 |

Every block assertion carried a control that failed in the same run. The sharpest: the
`EEXPIRED` refusal was proven against a live request that refused with the **different**
code `EHASH`, so the refusal is specific to expiry rather than blanket.

The single most important test is the add-then-revoke pair, because deny-by-default alone
would pass on a machine where Guard 3 was never installed. Both halves held, and the
control host was chosen by verified address-disjointness rather than assumed.

### 6. Git

`git status --short` first, explicit per-file staging, no `git add -A`, no worktrees.
Separate commits as required:

| Commit | Repo | Content |
| --- | --- | --- |
| `4530f01` | Secure-Setup | Guard 3 |
| `160fb05` | Secure-Setup | Approvals polish |
| `f0795cb` | Secure-Setup | Build and repin |
| `82748cc` | Secure-Setup | The fw-apply escaping fix |
| `1d55b14` | Secure-Setup | Validation suite and four harness defects |
| `bd66c26` | Secure-Setup | Close-out and L29 |
| `f113517` | Studio | Web access panel |
| `e4da2be` | Studio | Four polish defects |
| `34c9947` | Studio | Licence swap |

Both repos pushed and in sync. **No tag**, per the work package.

### 7. Out of scope, confirmed untouched

No Guard 4. No Studio restyle beyond the five items. No marketing copy beyond the footer
and licence. No tag, no publish, no Inno licence purchase. `SECURITY.md:114` left alone.
Step 7, full assembled-build validation, not run.

---

## 3. What went wrong, and what it cost

Two VMs were used instead of one.

**cfv-161: the installer refused to finish, and it was right to.** A comment I wrote
inside a double-quoted PowerShell here-string contained a backtick before an `n`, which
PowerShell expanded to a real newline, splitting the comment and emitting its tail into the
generated firewall script as a command. The boot-time firewall re-apply exited 127 and the
installer aborted rather than leave a machine claiming a control it did not have. **The
fail-closed design caught the bug on a test box instead of a customer one**, which is the
system working.

**cfv-162 lost about an hour to an unchecked `az` call.** `az vm user update` was invoked
with no exit-code check immediately before its password was written into Winlogon and the
box rebooted. The VMAccess extension hung, the reset never applied, auto-logon failed
against a password the account did not have, and the driver polled a dead machine for 48
minutes. Now checked, and the poll aborts at 12 minutes with a named diagnosis.

**Four harness defects produced wrong results**, and they are the durable lesson (L29,
appended to the lessons file):

1. Phase 6's first run gave four FAILs and one PASS from an empty queue, because a fresh
   box has no SMTP credential and Guard 2 correctly refuses to enqueue. The PASS was the
   more dangerous outcome.
2. A marker search over the compiled installer reported its absent-controls clean while
   finding nothing at all, because the payload is compressed. Only the positive control
   caught it.
3. `PIN.studio` had never been updated since the file was created, and can only produce a
   verdict when an install has already failed. It is vacuous on the happy path.
4. Phase 1 printed "installer reports 33 resources" and "all 30 required resources
   present" on adjacent lines and passed both, because each side only counted itself.

The shape they share: **the measurement succeeded while the thing measured was absent.**
All four are fixed.

**One correction to something reported mid-session.** I initially flagged the earlier
cfv-160 smoke close-out as inconsistent because `PIN.studio` should have failed there too.
That was my error; the earlier close-out was sound. The check only derives a digest when
the staged payload survives, which happens only when an install fails.

---

## 4. The thing to decide next

**`AUX_HOSTS` is not "the provider", and this is the top recommendation.**

The always-open baseline is ten hostnames: three model providers plus `clawhub.ai`,
`api.github.com`, `raw.githubusercontent.com`, `objects.githubusercontent.com` and
`registry.npmjs.org`. On the probe box those resolved to **72 live addresses**, including
GitHub's shared content CDN and roughly two dozen Cloudflare edge addresses. A customer
reading "web off by default" and later discovering the agent can reach arbitrary content
on those addresses would rightly feel misled.

I did not trim it: those hosts serve skill installation, deleting them breaks a real
feature, and it is well outside config plus UI.

**Recommendation: make the toolchain hosts an opt-in toggle in the Web access panel**,
default off, using the resolver, control tool, panel and tripwire that Guard 3 has just
built and validated. That makes the baseline provider-only, makes the claim sentence true
as literally written, and surfaces a capability users currently have without knowing it.
It is cheap because the machinery exists.

**Second: answer card #197 before starting Guard 4.** One question: does the bundled
provider plugin honour a `models.providers.*.baseUrl` override? If yes, a root-owned
outbound proxy can hold the key and enforce hostnames, closing both the address-scoping
residual and the exfiltration residual. If no, address-scoping is permanent for v1. It is
roughly an afternoon and it determines what Guard 4 should even be.

**Third: an hour on the harness rather than features.** Make every phase exit VOID if its
own positive control does not fire. Four wrong results in one session is a structural gap,
not bad luck.

**Fourth: bump the ClawFactory installer version off 1.2.0**, which now names three
distinct payloads.

---

## 5. Deferred deliberately, with the text recorded

The Web access panel footnote is honest but **incomplete**: it says a site sharing an
address with the provider may be reachable, and omits that the same is true of a site
sharing an address with one the user allowed. Correcting it means rebuilding Studio,
re-signing, repinning, rebuilding the installer, re-signing and reinstalling, which
discards the build this session validated for a text-only change and would leave the
reboot evidence describing a different build.

Replacement text, agreed and recorded so it cannot drift:

> A site you have not added is not reachable. Two things stay reachable whatever this list
> says: the AI provider your agent talks to, and the software sources ClawFactory needs to
> run, which are GitHub and npm. Matching is by network address rather than by name, so
> allowing a site also allows anything else served from the same address. Removing a site
> takes effect immediately.

First item on the next Studio pass, where it costs nothing extra alongside the opt-in
toggle.

Also carded: trim or gate `AUX_HOSTS`; bump the installer version; the stale "Studio
backend unreachable" banner on the home route, whose wording caused the D4 misdiagnosis
across three sessions and is still misleading; the `v1.2.0Templates` header spacing; and
`PIN.bundle`'s label saying 30 while checking 33.

---

## 6. Resource ledger

Both VMs created and deleted, with evidence. `cfv-161` deleted after its aborted install,
including the orphaned disk, NIC, public IP and NSG that the VM delete left behind.
`cfv-162` torn down through the standard script: licence slot released with `Machine
deactivated successfully`, and the unfiltered teardown proof shows the only remaining
resources are the storage account, the VNET and the two baseline images. **Nothing
matching `cfv-161` or `cfv-162` remains, and nothing is billing.**

`cfv-162` was deliberately deallocated for roughly 25 minutes mid-run, by a parking job
whose unconditional `finally` block stopped it across a human handoff with nobody watching.
That behaviour should be kept.

**Credential hygiene.** The SMTP app password was typed into the Studio panel by hand and
never entered a script, a transcript or the model's context. It remains the kept throwaway;
none was generated and none revoked, per the standing decision. Two VM admin passwords were
reset directly through `az` by the operator, chosen by them and never seen by the model.

---

## 7. Environment notes for whoever picks this up

- **`python` is blocked** by a Windows Application Control policy on the build machine.
  `dispatch_card.py` will not run. The Dispatch API works directly from PowerShell; the
  contract is in the memory notes and was used to close card #244.
- **`az vm run-command` runs as SYSTEM, and WSL refuses to run there.** Every WSL test
  needs the interactive session. Auto-logon is a one-shot, so after any reboot a human must
  log in over RDP and start the on-VM runner by hand. This is not scriptable around and
  must be planned into any run that includes a restart.
- **Never write a backtick inside a double-quoted PowerShell here-string**, not even in a
  comment. Only the escapes mapping to control characters matter, which is why some
  pre-existing instances are harmless and this one was fatal.
- A probe whose subject expires on a timer cannot be staged in advance and handed to a
  person. Stage it immediately before they act.
