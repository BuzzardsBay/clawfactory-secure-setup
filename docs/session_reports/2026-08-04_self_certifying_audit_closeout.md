# Self-Certifying Integrity Audit -- close-out

**Date:** 2026-08-04
**Track:** v1 fast-security-harness. Diagnostic and fix job.
**Depends on:** Guard 2 build (close-out `2026-08-02_v1_guard2_build_closeout.md`). Met.
**Runs independently of:** Guard 3, Guard 4.
**Repos touched:** ClawFactory-Secure-Setup only. Studio not touched.

---

## 0. Headline

The audit found **three** instances of the self-certification pattern, not one.

1. `freeze-injected-soul.sh` pinned the injected workspace SOUL by hashing the file it had just
   written into a directory the agent owns. **Fixed and proven by execution.**
2. The embedded 100 MB Studio installer was covered by a sha256 check that two comments described
   and no code performed. **Fixed and proven by execution.**
3. The build gate added in `ab180d4` to stop exactly this class **has never worked**. A PowerShell
   quoting defect made its regex unmatchable, so `build_release.ps1` failed unconditionally and
   never once compared the SOUL pin to the file. Found by running the negative control rather than
   reading the code. **Fixed and proven by execution.**

The pinned SOUL literal turned out to be correct on inspection, so no drift shipped. That is luck
plus a careful hand, not a control.

**Scope note on disclosure.** The SOUL pin defect shipped in every released build including v1.0.45,
which was validated and tagged. What that means for the honesty map, and for any prior claim of
structural SOUL enforcement, is founder work. Facts are recorded here. No customer-facing language
was written or changed.

---

## 1. Comprehension gate

**1. Why does an install-time self-hash produce the observable behaviour of a working integrity gate
while providing no integrity?**

Because every part of the mechanism except the provenance of the expected value is real. The hash
function is real, the pin file is real and root-owned and outside the agent's reach, and the launch
gate really does recompute and really does refuse on mismatch. What the gate actually proves is
"this file has not changed since we looked at it", and we looked at it after the attacker did. It is
not a broken control. It is a working control answering the wrong question. Every observable a
validator would check comes back green: pin present, gate fires, tamper test refuses. That is why it
survived validation and tagging.

**2. Why is auto-correcting a build-time constant on drift the wrong fix rather than a convenience?**

Because it reinstates the defect one step earlier in the pipeline. A build script that rewrites its
literal to match the file is doing what `Step-ApplySafetyRules` used to do, deriving the expected
value from the artefact, just at build time instead of install time. Drift is the signal. Either the
artefact changed on purpose, in which case a human should update the literal and know they did, or
it changed without anyone deciding to, which is the case the pin exists to catch. Auto-correction
cannot distinguish those and silently answers "fine" to both.

**3. What is the difference between verifying that a required resource is present and verifying that
it is the resource that was signed, and which does `Step-Preflight` do today?**

Presence answers "will this install crash". Provenance answers "is this the artefact that was
reviewed and signed". `Step-Preflight` ([setup.ps1:673](../../setup.ps1)) is `Test-Path` over 29
filenames: presence only, no size, no content. It would pass with all 29 files replaced by empty
stubs.

**4. Name the trust anchor each integrity value ultimately chains to.**

Everything security-relevant chains to the **Authenticode signature on
`ClawFactory-Secure-Setup.exe`**, reached through literals baked into signed source. Before the fixes
in this session, two values chained only to themselves: the injected workspace SOUL pin (row 3
below) and the embedded Studio installer (row 5). Both are findings, and both are now anchored. One
value chains to nothing by design and says so in its own comment: `installShHash` (row 4), which is
an audit log, not a gate.

---

## 2. The audit

Every integrity value, hash, checksum, pin, signature check, size check and version assertion in the
shipped install and launch path. Clean results are included: a table containing only findings is
indistinguishable from an audit that did not look.

| # | Value | Defined | Computed | Checked | Covers | Verdict |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | `$expectedSoulHash` | `setup.ps1:2380` literal | `build_release.ps1`; `setup.ps1:2381` | install refuses on mismatch | `resources/safety-rules.md` | **BUILD-TIME CONSTANT** |
| 2 | `/etc/clawfactory/soul.sha256` | written from #1 | `clawfactory-turn-gate.sh:29`, `Test-SoulIntegrity` | every turn | `~/.openclaw/SOUL.md` | **BUILD-TIME CONSTANT** (chains to #1) |
| 3 | `/etc/clawfactory/workspace-soul.sha256` | nowhere | **`freeze-injected-soul.sh:78`, from the file it just wrote** | every turn | injected workspace SOUL | **INSTALL-TIME SELF-HASH -- FIXED** |
| 4 | `installShHash` | no expected value exists | `setup.ps1:1574` | never compared | `resources/openclaw-install.sh` | NOT AN INTEGRITY CHECK (audit log; correctly documented as such) |
| 5 | Studio installer sha256 | **claimed** at `.iss:112` and in `.gitignore`; **existed nowhere** | nowhere | `FileExists` only (`.iss:1082`) | 100 MB gitignored payload | **PRESENCE ONLY, with a comment asserting a check that did not exist -- FIXED** |
| 6 | `ubuntu-rootfs.tar.gz` | none | none | none | 341 MB gitignored payload | PRESENCE ONLY (not even in `$required`) |
| 7 | `ClawChat.exe` | none | none | none | shipped desktop app (tracked in git) | PRESENCE ONLY |
| 8 | `Step-Preflight` `$required` | `setup.ps1:658` | n/a | `Test-Path` x29 | shipped security resources | **PRESENCE ONLY** (reported, not upgraded) |
| 9 | build bundle pairing | `build_release.ps1` | n/a | `$required` subset of `.iss [Files]` | preflight/iss drift | NOT AN INTEGRITY CHECK (build coherence gate). Clean, and correct as written |
| 10 | Ollama "basic integrity check" | none | n/a | `head -c 2 \| grep '#!'` | network-fetched script run as root | **PRESENCE ONLY** (shape assertion) |
| 11 | `$OpenClawNpmVersion` | `setup.ps1:66` literal | n/a | passed as `OPENCLAW_VERSION`, not re-asserted after install | openclaw npm package | VERSION ASSERTION, unverified post-install |
| 12 | `{{SOUL_SHA256}}` substitution | `bootstrap.ps1:235` | reads the root-owned pin | nothing consumes it | orchestrator `agent.md` prompt text | NOT AN INTEGRITY CHECK. **Dead code since `8eaeb60`** |
| 13 | Smoke `Check "Orchestrator SOUL hash substituted"` | `setup.ps1:2933` | greps for a placeholder | n/a | nothing | **VACUOUS: passes unconditionally since `8eaeb60`** |
| 14 | Quarantine record `sha256` | at capture | `clawfactory-quarantinectl.js:129` | restore refuses on mismatch | held payload while quarantined | Correct. Anchor is capture time, which is the right anchor for this question. Clean |
| 15 | Send `payloadHash` / `bodySha256` / attachment sha256 | `send-lib.js:212` canonical form | at enqueue, again at send (`clawfactory-sendd.js:364`) | send refuses if staged bytes changed | the approved email payload | Correct. Anchor is the approved request. Clean |
| 16 | `egress-policy.json` | ships fail-closed empty | n/a | broker exact host and port match | send destinations | NOT AN INTEGRITY CHECK (root-owned policy). Clean |
| 17 | `send.json`, `quarantine.json`, `governor.json`, `fw-backend`, `allowed-ips.txt`, `dns-resolvers.txt`, `openclaw-real` | generated at install | n/a | none | runtime config | NOT AN INTEGRITY CHECK. Protected by root ownership only. See note (b) |
| 18 | `clawfactory-fw-assert.sh` | shape literals in signed source | reads the live nft chain | every refresh cycle and at install | egress chain shape | NOT AN INTEGRITY CHECK (tripwire). Correctly anchored to literals, does not self-certify. Clean |
| 19 | Inno Setup extraction checksum | Inno internal | at extraction | aborts on corruption | all embedded files | NOT AN INTEGRITY CHECK (corruption, not provenance) |
| 20 | Authenticode signature | Azure Trusted Signing cert | Windows / SmartScreen at launch | before any of our code runs | the entire installer payload | **THE TRUST ANCHOR** |
| 21 | `%ProgramData%\ClawFactory` state (`checkpoint.json`, `install-result.txt`, `grants.json`, `governor.json`) | n/a | n/a | none | resume step-skip, Studio go/no-go, grants | NOT AN INTEGRITY CHECK. NTFS ACL verified on the live box: `BUILTIN\Users` has ReadAndExecute on the files, so they cannot be overwritten by a standard user. See note (c) |
| 22 | `$InstallerVersion` (`1.0.34`) vs `.iss MyAppVersion` (`1.1.1`) | two literals | n/a | never compared | version reporting only | NOT AN INTEGRITY CHECK. Drifted |

### Guard 2 artefacts, on the specific question of what stops each from being replaced

| Artefact | What stops replacement |
| --- | --- |
| `/etc/clawfactory/egress-policy.json` | root:root 0644 in a root-owned directory. Nothing else. No hash, no signature. The agent (uid 1000) cannot write it; root can |
| `/etc/clawfactory/send-credential.json` | root:root 0600. Same answer. The agent cannot even read it |
| `/etc/clawfactory/quarantine.json` | root:root 0444. Same answer |
| exec-approvals token | **Does not exist.** Searched `setup.ps1` and all of `resources/`; there is no exec-approvals token in this product. The approval channel is a 0600 root:root unix socket plus a 0750 root-only `clawfactory-sendctl`, which are capability boundaries, not tokens |

That is the honest answer for all four: **discretionary access control and nothing else.** It is
adequate against the stated actor (the agent shares uid 1000 with the gateway and is not root), and
it is the accepted v1 actor model per `SECURITY_FINDINGS.md`. It is not integrity in the
cryptographic sense and should never be described as such.

### Notes

**(a) `/etc/clawfactory/openclaw-real` is the one config file with no explicit mode.** Both
`openclaw-shim.sh` and `clawfactory-turn-gate.sh` `exec` whatever path it contains. It is created by
root in a root-owned 755 directory so it lands root:root 0644 by umask, which is correct, but every
sibling in `install-turn-gate.sh` gets an explicit `chown`/`chmod` and this one does not. Verified
correct on the live box. Recommend an explicit `chown root:root` and `chmod 644` for parity.
Cost: two lines, no behaviour change.

**(b)** Row 17's files are the runtime control surface (spend caps, quarantine scope, send limits,
egress destinations). None is hashed or signed. That is a deliberate and reasonable v1 position
given the actor model, but it means "structural" for these files means "root owns it", which is a
weaker claim than the word usually carries.

**(c)** The directory `C:\ProgramData\ClawFactory` grants `BUILTIN\Users` Write, which is the stock
ProgramData inheritance. The **files** inside grant Users ReadAndExecute only, so a standard user
cannot modify `checkpoint.json` (which drives step-skipping on resume) or `grants.json`. Verified by
reading the live ACLs, not assumed. One residual: a standard user can *create* a new file in that
directory, so `install-result.txt` could be pre-created with the text `success` before a first
install, which would make `InstallStudioComponent` proceed even if the core install failed. Local
access before install, cosmetic outcome. Recorded, not fixed.

---

## 3. Fixes, each with its negative control proven by execution

### Fix 1: the injected workspace SOUL pin (row 3)

`freeze-injected-soul.sh` built the file directly at
`/home/clawuser/.openclaw/workspace/SOUL.md` and then ran `sha256sum "$WS" > "$PIN"`. This was worse
than the factory-SOUL instance, because the workspace **directory** is clawuser-owned by necessity
(the agent must create `AGENTS.md` in it, per L16). The agent could therefore unlink the file and
put its own in its place during the window between the write and the `chattr +i`, and the
`chown`/`chmod`/`chattr`/`sha256sum` that followed would have frozen and pinned the agent's file as
the authoritative safety rules.

The fix uses the shape proven on the SOUL pin, adapted for an artefact that legitimately varies (it
carries user persona, so no build-time literal can cover the whole file):

- Build the intended bytes at `/etc/clawfactory/.workspace-soul.staged`, a directory only root can
  write.
- `rm` then `install -m 444 -o root -g root` into place, then `chattr +i`. An immutable inode cannot
  be replaced or renamed even by the owner of the directory, so any check made after that point is a
  check on the bytes that will actually be read.
- **Then** verify: not a symlink; `cmp` against the staged copy; and the safety block inside the
  frozen file byte-identical to `~/.openclaw/SOUL.md`, which `Step-ApplySafetyRules` has already
  proven equal to the SHA-256 baked into `setup.ps1` at build time. That is the step that anchors
  this pin to the signed build instead of to itself.
- Pin from the staged copy, refusing outright on any mismatch.

**Byte-neutrality established first.** Both the old and the new script were run against the same
restored input on the live box. Both produced `03f29043ca6e...` at 4537 bytes, identical. The fix
changes no output. (The input file on the box was 4536 bytes, dated 2026-07-14; the one-byte
difference is a blank line added by the pre-existing persona re-wrap, present in the old script too.
See section 6.)

**Negative control, by execution.** One line was injected into each script at the equivalent point,
simulating an attacker replacing the file in the window the fix closes:

| | old script | fixed script |
| --- | --- | --- |
| script exit code | **0** | 1 |
| script reported | `frozen + pinned`, `ownership OK` | `FATAL ... Refusing to pin` |
| pin ended up holding | `71876b2a...` (the attacker's) | `03f29043...` (the legitimate one) |
| launch gate then returned | **exit 0, turn ALLOWED** | exit 3, `soul_mismatch`, all turns blocked |

The old path pinned a 23-byte file whose entire contents were `MALICIOUS SAFETY RULES` as the
agent's authoritative safety rules, and reported success at every step. That is the pattern in its
finished form.

**Restored.** Workspace SOUL back to `6d211ded10ac...`, pin back to `6d211ded10ac...`, factory SOUL
`cd0199d52b9e...` matching its pin, `root:root 444`, `lsattr` shows `i`. Launch gate re-run: exit 0.

### Fix 2: the embedded Studio installer (row 5)

`ClawFactory-Secure-Setup.iss:112` and `.gitignore` both stated the payload was "verified by sha256
before compile". No such verification existed in any build script. The check was real but **manual**:
it was performed in JOB 3B and recorded as `MATCH` in
`2026-07-21_job3b_combined_installer_closeout.md`. A check that lives only in a human's habit is not
a check the build has, and the payload is gitignored, so git cannot tell you whether the right
binary is present either.

`build_release.ps1` now pins `d5ff8370943194c2...`, the digest recorded in that close-out for the
artefact built from Studio `@9d62ad0` and validated on cfv-152. **The value was taken from the
committed close-out, not computed from the file in `resources\`.** The file on disk was then
confirmed to match it, which is a verification rather than a derivation. The build fails on drift and
never auto-corrects. Both stale comments were corrected to describe what the code now does.

**Negative control, by execution.** One byte appended to the 100 MB payload:

```
Fail : build_release.ps1: Studio installer drift: resources\ClawFactory-Studio-Setup-1.1.0.exe
hashes to 91cba8a7589346da... but this build pins d5ff8370943194c2... Refusing to embed an
unverified 100 MB payload.
```

Restored by truncation; digest re-verified as `d5ff8370943194c2...`.

### Fix 3: the build gate that never ran (found by the negative control)

Running the tampered-payload control produced the wrong error. `build_release.ps1` was failing at
line 48 with "setup.ps1 does not carry an `$expectedSoulHash` literal" against a `setup.ps1` that
plainly carries it.

Root cause: `"\$expectedSoulHash\s*=..."` is a **double-quoted** PowerShell string, so
`$expectedSoulHash` interpolates as an empty variable and the pattern collapses to one requiring a
literal backslash. It can never match. `$required` on line 62 had the identical defect. So the gate
added in `ab180d4` specifically to prevent this class of defect **failed the build unconditionally
from the day it was written and never once compared the pin to the file.**

It failed *closed*, so nothing shipped past it. The cost is that no release has been cut through
`build_release.ps1` since `ab180d4`, and the SOUL literal's correctness was never machine-checked.

Fixed by backtick-escaping both. **Verified in both directions:**

- Clean run: `SOUL pin OK: 8f5531a3...`, `Bundle check OK: all 29 preflight resources are in
  [Files].`, `Studio pin OK: d5ff8370...`. (Run with a stand-in for `ISCC.exe` so it halts before
  compiling and signing.)
- Tampered `safety-rules.md`: `SOUL pin drift: setup.ps1 pins 8f5531a3... but
  resources/safety-rules.md hashes to 7c7b8b03...`. Restored via `git checkout`; digest re-verified
  as `8f5531a3...`.

The SOUL literal was found to be **correct**: `resources/safety-rules.md` hashes to
`8f5531a36e46af81...`, matching the pinned constant. No drift shipped.

---

## 4. PRESENCE ONLY results: recommendation and cost, founder decides

Per the job, these were not silently upgraded. Some presence checks are correct as presence checks.

| # | Finding | Recommendation | Cost |
| --- | --- | --- | --- |
| 8 | `Step-Preflight` is `Test-Path` over 29 files. It would pass against 29 empty stubs | **Leave as presence.** Its actual job is catching the `.iss`/`$required` drift that once shipped an installer with zero security controls, and `build_release.ps1` already catches that at build time where it is cheap. Content verification here would need 29 more literals to maintain, all covered by the Authenticode signature anyway | Would be roughly 30 lines plus permanent maintenance, for redundancy with the signature |
| 10 | Ollama's `head -c 2 \| grep '#!'` is a shape assertion on a script fetched over the network at install time and run as root. The word "integrity" in its comment is the tell | Ollama does not publish a stable digest, so a pin is not available. **Recommend rewording the comment** to say "shape check, not integrity" so it stops reading as a control, and noting in `SECURITY_FINDINGS.md` that the ollama provider path executes unpinned network-fetched code as root | Comment only, unless a vendored ollama installer is wanted, which is its own job |
| 13 | `Check "Orchestrator SOUL hash substituted"` has passed unconditionally since `8eaeb60` removed the `{{SOUL_SHA256}}` placeholder. It greps for a string that no longer exists in the source | **Delete the check**, or repoint it at the real control (`/etc/clawfactory/soul.sha256` present and matching). A green check that verifies nothing is worse than no check | A few lines |
| 12 | `bootstrap.ps1`'s `Get-SoulSha256` and its substitution are dead code for the same reason | Delete, or leave with a comment saying it is inert | A few lines |
| 6, 7 | `ubuntu-rootfs.tar.gz` (341 MB, gitignored) and `ClawChat.exe` are embedded with no build-time pin, exactly as Studio was | **Pin both in `build_release.ps1`** using the shape now proven there. The rootfs is the higher risk: it is gitignored, so git cannot see substitution either | Two literals plus two hash comparisons. About 20 lines. Needs a recorded provenance value for each, which does not exist yet for the rootfs |
| a | `/etc/clawfactory/openclaw-real` has no explicit mode, and both the shim and the gate `exec` its contents | Add `chown root:root` and `chmod 644` for parity with its siblings | Two lines |
| 22 | `$InstallerVersion` says `1.0.34`, `.iss` says `1.1.1` | Reconcile, and assert equality in `build_release.ps1` so they cannot drift again | A few lines |

### One finding that is not a presence check and needs a decision

**`Step-FreezeInjectedSoul` fails open.** In `setup.ps1`, a non-zero return from the freeze step
produces `Write-Log WARN` and the install continues and reports success. The sibling
`Step-ApplySafetyRules` throws. Because `clawfactory-turn-gate.sh` enforces the injected SOUL **only
if its pin exists**, a failed freeze yields an install that reports success, shows a green checklist,
and silently has no injected-SOUL enforcement at all.

This is the same family as the rest of this job: the observable signature of a working control
without the control. **Recommend changing the `WARN` to a `throw`**, matching
`Step-ApplySafetyRules`. It was not changed here because it converts a tolerated warning into an
install abort, which needs a clean-box run to validate, and this session did no clean-box install.
Cost: one line plus a validation run.

Note that Fix 1 makes this *more* likely to fire, by design: the freeze now refuses in cases where it
previously proceeded. That is correct behaviour and an argument for making the caller fail loudly
rather than continue.

---

## 5. The test send credential on the validation box

The validation box is the local WSL `Ubuntu` distro, still running. State found and changed:

| Item | Before | After |
| --- | --- | --- |
| `/etc/clawfactory/send-credential.json` | present, root:root 0600, `host: 127.0.0.1`, `port: 2525`, `username: cfsend` | **moved out of the broker's path** to `/root/cf-audit-backup/REMOVED-2026-08-04-test-sink-credential-NOT-LIVE.json.bak`, mode 0600 |
| `egress-policy.json` `send_actions` | `[{"protocol":"smtp","host":"127.0.0.1","port":2525,...}]` | `[]`, the shipped fail-closed default. Prior file kept at `/root/cf-audit-backup/egress-policy.json.pre-audit.bak` |

Both halves were dealt with deliberately. A credential pointing at a sink *and* a policy entry
authorising that sink are together what makes a demo look like delivery; removing only the credential
would have left the authorisation in place.

**Fail-closed proven by execution**, with a control that had to fail:

```
=== agent attempts a send with no authorized destination ===
clawfactory-send: no SMTP credential is configured
rc=1

=== CONTROL that must fail: nonexistent broker socket ===
control_error=ENOENT
```

Broker still `active` after restart.

**External delivery remains untested.** Everything demonstrated on this machine to date, including
Guard 2's Test 3 and Turn C, was demonstrated against a local sink on `127.0.0.1:2525`. It shows the
broker, the approval gate and the SMTP client work; it does not show mail reaches anyone. Tracked as
card **#198**.

---

## 6. End-of-session gate

### 6.1 Task accounting

| Item | Status |
| --- | --- |
| Dispatch card created and moved to done | DONE. Card **#208**. Recorded late in the session: the first search looked under `C:\Users\bmcki\FrontierAI` and found nothing, but the helper lives at `C:\Projects\FrontierAI\scripts\dispatch_card.py`. Two different FrontierAI checkouts exist |
| Comprehension gate answered before any change | DONE (section 1) |
| Enumerate every integrity value in the install and launch path | DONE (section 2, 22 rows plus the Guard 2 sub-table, clean results included) |
| `setup.ps1` in full, every `Step-*`, refresh heredocs | DONE |
| `Step-Preflight` required-resource list: presence, size, or content | DONE. Presence only |
| `.iss` bundle and what Inno verifies on extraction | DONE. Extraction checksum is corruption detection, not provenance (row 19) |
| `build_release.ps1` and other build scripts | DONE. Found the never-ran gate (Fix 3) and the missing Studio pin (Fix 2) |
| `resources/*.ps1`, `*.sh`, `*.js` including `switch-provider.ps1`, `clawfactory-fw-apply.sh`, `clawfactory-allow-providers.sh`, Guard 1 and Guard 2 installers | DONE. `clawfactory-fw-apply.sh` and `clawfactory-allow-providers.sh` are heredocs generated in `setup.ps1:1441` and `setup.ps1:1884`; they carry no integrity values and read root-owned config (row 17). `switch-provider.ps1` carries none |
| Launch gate and `clawfactory-turn-gate.sh` | DONE (rows 2, 3) |
| Anything that reads `.json`/`.yaml`/`.md` and decides whether to trust it | DONE (rows 16, 17, 21 and notes b, c) |
| Vendored OpenClaw install path, plugin and extension loading | DONE (rows 4, 11) |
| Guard 2 policy file, send credential, quarantine config, exec-approvals token | DONE. Sub-table in section 2. The exec-approvals token does not exist |
| Fix every INSTALL-TIME SELF-HASH | DONE. One found (row 3), fixed, negative control proven |
| PRESENCE ONLY results reported with recommendation and cost, not silently upgraded | DONE (section 4) |
| Each fix proven by a demonstrated refusal, then restored | DONE. Three negative controls executed, three restorations verified by digest |
| Test send credential removed or renamed, recorded in the ledger | DONE (section 5) |
| Note that external delivery remains untested per card #198 | DONE (section 5) |
| Add the pattern to `ClawFactory_Install_Lessons_Learned.md` as a numbered lesson | DONE. **L24**, written to the shape rather than the SOUL instance |
| Task accounting, resource ledger, delta security sweep, delta bug review, next-session recommendations | DONE (this section) |
| Guard 3 work | OUT OF SCOPE. Not touched |
| Guard 4 work | OUT OF SCOPE. Not touched |
| Studio restyle | OUT OF SCOPE. Not touched |
| Customer-facing copy, honesty map | OUT OF SCOPE. Not touched. See DEFERRED below |
| The four cards from the Guard 2 close-out | OUT OF SCOPE. Not touched |
| `Step-FreezeInjectedSoul` fail-open | **DEFERRED** to founder decision (section 4). Needs a clean-box run |
| `post-install.ps1:241` customer checklist claim | **DEFERRED.** Customer-facing copy, explicitly founder work. See 6.3 |
| Clean-box install validation of Fix 1 | **DEFERRED.** No Azure VM was created this session. See 6.5 |

### 6.2 Resource ledger

**Created on the live WSL box:**
- `/root/cf-audit-backup/` containing `SOUL.md.bak`, `pin.bak`,
  `REMOVED-2026-08-04-test-sink-credential-NOT-LIVE.json.bak`, `egress-policy.json.pre-audit.bak`.
  **Left in place deliberately** as the recovery copy for section 5. Remove with
  `rm -rf /root/cf-audit-backup` when no longer wanted.
- `/etc/clawfactory/.workspace-soul.staged` was created by the audit runs and **removed**. On a real
  install the fixed script recreates it as the known-good copy; `uninstall.ps1:402`
  (`rm -rf /etc/clawfactory`) already cleans it up, so it adds no uninstall litter.

**Removed from the live WSL box:**
- `/etc/clawfactory/send-credential.json` (moved to the backup directory, see section 5).
- The `127.0.0.1:2525` entry in `send_actions` (reset to `[]`).

**Tampered and restored, each verified by digest:**
- `resources/ClawFactory-Studio-Setup-1.1.0.exe`: appended a byte twice, truncated back both times.
  Final `d5ff8370943194c2643674ddba98e917ca61865ce127ec424a1cb37c746d45a7`, 100,022,000 bytes.
- `resources/safety-rules.md`: appended text, restored via `git checkout`. Final
  `8f5531a36e46af8143ffe59ae4112a83a28b3513c473562578ee81c408c07eb6`.
- Workspace SOUL and its pin on the live box: restored to `6d211ded10ac...`, launch gate exit 0.

**Scratchpad only, not in the repo:** `probe1.sh`, `g2-backup.sh`, `g2-restore.sh`, `g2-diff.sh`,
`g2-credential.sh`, `g2-failclosed.sh`, `freeze-old.sh`, `freeze-new.sh`, `freeze-fault.sh`,
`freeze-old-fault.sh`. The two `*-fault.sh` scripts contain the injected fault and were never written
to `resources/`.

**Azure:** none used. No VMs created, none live.

**Cost:** no builds compiled, nothing signed, nothing uploaded, no release cut.

### 6.3 Delta security sweep

**Every integrity value found, with its verdict**, is the 22-row table in section 2 plus the Guard 2
sub-table. Summarised by verdict:

- **BUILD-TIME CONSTANT:** rows 1, 2. Plus rows 3 and 5 as of this session.
- **INSTALL-TIME SELF-HASH:** row 3. One found. Fixed.
- **PRESENCE ONLY:** rows 5, 6, 7, 8, 10. Row 5 fixed; 6, 7, 8, 10 reported with recommendation and
  cost.
- **NOT AN INTEGRITY CHECK:** rows 4, 9, 12, 13, 14, 15, 16, 17, 18, 19, 21, 22. Rows 14, 15, 18 are
  clean and correct for what they do. Rows 12 and 13 are dead or vacuous.
- **THE TRUST ANCHOR:** row 20.

**Claims this job made untrue:** none. Nothing customer-facing was written.

**Pre-existing claims found to be false:**

1. `.iss:112` and `.gitignore` said the Studio payload was "verified by sha256 before compile". The
   verification was manual and never encoded. **Both comments corrected, and the check now exists.**
2. `setup.ps1:38` header lists `[R6] SOUL.md hash pinned into orchestrator prompt`, and
   `post-install.ps1:241` prints `[x] SOUL.md installed and hash-pinned in orchestrator prompt` to
   the customer. **The hash has not been in the orchestrator prompt since `8eaeb60` (2026-07-14)**,
   which removed the `{{SOUL_SHA256}}` placeholder. That removal was the right call: it replaced a
   prompt-level "compute the hash yourself" rule, which a hostile model ignores, with the real code
   gate. But the claim was left behind in two places. `post-install.ps1` is customer-facing and is
   therefore **founder work, not touched here.** The `setup.ps1` header comment is internal and was
   also left, so the two stay consistent until the founder decides the wording.
3. The `freeze-injected-soul.sh` header says "Re-running with unchanged rules is a no-op." It is not
   quite: re-running against a file produced by an earlier build adds one blank line after the
   marker (4536 to 4537 bytes on the live box). Proven pre-existing by running the old and new
   scripts against the same input and getting identical output. Harmless in content, but the pin
   changes, so it is not a no-op. Recorded, not fixed.

**New security surface added:** none. The two fixes both remove trust, and Fix 1 additionally closes
a symlink-follow on `$WS` (the old code redirected into the path with no `rm` first).

**Residual on Fix 1:** `rm -f "$WS"` then `install` still leaves a narrow window in which a symlink
could be planted at that name, in which case `install` writes through it before the `-L` check
refuses. The window is much smaller than before (the old code had no `rm` at all and never checked),
the refusal is correct, and closing it entirely needs `openat2(RESOLVE_NO_SYMLINKS)` or an
`O_CREAT|O_EXCL` write, which is more than a shell script does well. Recorded.

### 6.4 Delta bug review, from an end-to-end diff read

Read the complete working diff across all five files.

- `freeze-injected-soul.sh`: `set -e` is active, so `[ -L "$WS" ] && { ...; }` would have aborted the
  script on the **normal** path (test returns 1 when the file is not a symlink). Caught before
  execution and written as an `if` block. This is the same class as L21's shell traps and is worth
  remembering: a bare `[ ... ] &&` as a statement is a landmine under `set -e`.
- `dd bs=1 count=2330` is 2330 one-byte reads. Negligible for a 2 KB region, and correct; `bs=2330
  count=1` would be wrong because `dd` may short-read.
- `chattr +i "$WS"` is unguarded under `set -e`, matching the previous behaviour exactly. On a
  filesystem that cannot hold the flag the script aborts and `setup.ps1` logs a warning. Parity
  preserved deliberately; see the fail-open item in section 4.
- `$STAGED` is written before its `chmod 400`, so it is briefly 0644 in `/etc/clawfactory`, which is
  root-owned 755. Not reachable by the agent.
- `build_release.ps1`: `$issText` is assigned in the bundle-check block that precedes the new Studio
  block. Confirmed by execution, not by reading.
- `[regex]::Escape($studioName)` used with `-notmatch`: correct, since `-notmatch` treats its right
  side as a regex. Confirmed by execution.
- The new `Fail` strings use backtick-escaped `` `$studioPinned ``, which is the correct literal form
  and precisely the mistake Fix 3 was about. Checked deliberately.
- Git reports `CRLF will be replaced by LF` for `build_release.ps1`. It is a Windows-only script that
  never enters WSL, so this is harmless. `freeze-injected-soul.sh` does enter WSL, but
  `Step-FreezeInjectedSoul` normalises CRLF to LF at the transport boundary, so L20/L21 do not bite.
- No secret, key, token or password appears in any changed file or in this close-out. The removed
  credential is referenced by path and by its non-secret fields only.

### 6.5 Next-session recommendations

1. **Cut a build.** `build_release.ps1` has never completed a run **in its gated form**, because of
   Fix 3. Nothing validates that the compile and sign path still works end to end after these
   changes. This is the highest-value next step and it is small. Note that the three gates now pass,
   so the next attempt should be the first to reach `ISCC.exe` **through the gates**.

   > **Correction, 2026-08-04, post-audit follow-up session.** An earlier draft of this line said
   > "`build_release.ps1` has never completed a run" without qualification, and the headline said the
   > compile-and-sign path had never completed one. That was wrong. `v1.0.45` was tagged 2026-07-17
   > and `ab180d4` landed 2026-08-03, so the gate defect **postdates every shipped release**. Those
   > releases were built by `build_release.ps1` as of `e966409`, which carried no gates at all.
   > The accurate claim is the narrow one now stated above. See
   > `2026-08-04_post_audit_followups_closeout.md` Task 1, which also records a bypass-route finding
   > that this audit missed.
2. **Clean-box validation of Fix 1.** The injected-SOUL change was proven on a box that already had
   an install. The path that has never been exercised is the fresh-install ordering, where
   `$WS` does not exist and `PERSONA` falls back to `DEFAULT_PERSONA`. Reuse the cfv harness.
3. **Decide the `Step-FreezeInjectedSoul` fail-open** (section 4). One line, but it changes install
   behaviour, so it belongs with the clean-box run in item 2.
4. **Decide the two stale `[R6]` claims** (section 6.3 item 2). Customer-facing, so founder work. It
   is a small wording change in `post-install.ps1` plus the `setup.ps1` header comment.
5. **Pin `ubuntu-rootfs.tar.gz` and `ClawChat.exe`** in `build_release.ps1` (section 4). The shape is
   now proven twice in that file. The rootfs needs a provenance value recorded first, since none
   exists in any close-out.
6. **Delete or repoint the vacuous smoke check** (row 13) and the dead `Get-SoulSha256` (row 12).
7. **Reconcile the version drift** (row 22) and assert it in the build script.
8. **External SMTP delivery (card #198)** is still the only part of Guard 2 that has never been
   demonstrated. Section 5 removed the thing on this machine that made it look otherwise.

---

## 7. Git

`git status --short` was run first. Explicit per-file staging, no `git add -A`, no
`git worktree add`, committed to `main` in the single working tree.

Files changed:

| File | Why |
| --- | --- |
| `resources/freeze-injected-soul.sh` | Fix 1: the install-time self-hash |
| `scripts/build_release.ps1` | Fix 2 (Studio pin) and Fix 3 (the never-ran regexes) |
| `ClawFactory-Secure-Setup.iss` | Corrected the comment claiming a check that did not exist |
| `.gitignore` | Same correction |
| `ClawFactory_Install_Lessons_Learned.md` | L24 |
| `docs/session_reports/2026-08-04_self_certifying_audit_closeout.md` | This close-out |

Studio repo: not changed, nothing to push.
