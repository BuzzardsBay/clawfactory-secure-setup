# ClawFactory handoff after the Studio panel smoke test, 2026-08-13

Written for a design conversation starting cold, with no memory of this session. The companion
document is `docs/session_reports/2026-08-13_studio_smoke_closeout.md`, which is the evidence.
This is the state of play and the decisions actually open.

Supersedes the Studio sections of `2026-08-13_v1_2_0_handoff.md`, which still describes Studio
as a scaffold. It is not one.

---

## 1. What the product is, in one paragraph

ClawFactory packages a local AI agent (OpenClaw) inside WSL on Windows with security guards
around it, plus a desktop UI called Studio. v1 ships two guards. **Guard 1, recoverable
deletes:** a file the agent deletes inside a folder you granted it is held for 30 days instead
of destroyed. **Guard 2, approval-gated email:** the agent can compose a message but only a
human can send it. Guards 3 and 4 are unbuilt. Studio is a separate private repo
(`BuzzardsBay/ClawFactory-Studio`) whose installer is embedded as a payload inside the
ClawFactory installer.

---

## 2. Current verified state

| Thing | State |
| --- | --- |
| Install on a clean Windows 11 box | **works**, 12 PASS / 0 FAIL |
| Guard 1 recoverable deletes | **works**, proven by a real agent turn |
| Guard 2 approval-gated email | **works**, all 14 tests, real external delivery proven |
| **Studio, all three guard panels** | **works**, driven by hand on cfv-160 on 2026-08-13 |
| Structural properties, before and after reboot | **hold** |
| Release status | **NOT released.** No tag. Latest tag is still `v1.1.0` |

### The artifacts

```
ClawFactory installer   29acdf95c6c12d4ef6e6b248527ae74b77c0bd46aca10db9a8c66c661bea2ae1
                        440,583,848 bytes, signed and timestamped, all seven gates passed
Studio payload          62402ff65b5623414faae2e804d98c9c658aab5468090b9f226a3e1998f891d9
                        100,028,736 bytes, signed, Studio commit 8b4e238
```

Repos: Secure-Setup at `acd0250`, Studio at `8b4e238`. Both pushed, both clean.

---

## 3. The finding that changes planning

**D4 was wrong, and it had been the premise of three sessions.** The interim validation
concluded Studio ships as a scaffold with the guard panels unwired. The scope session refuted
that from source; this session refuted it by use. All three panels work.

**The scope estimate collapses from three-plus sessions to done.** What actually remained was
one defect fix and one validation pass, both now complete.

One line item in the old estimate would have been actively harmful: **building a Studio
backend.** Studio is Electron IPC, in-process, with no listener by design. The sixth-channel
test proves the agent cannot reach the approval path partly *because* nothing listens. Adding
a backend would create the network surface that is currently absent. Do not put one in a plan.

---

## 4. The next build. This is what you are designing.

Three changes, all in the Studio renderer, all cheap, none urgent individually. Doing them
together costs one Studio rebuild, one repin, one installer rebuild and one VM run instead of
three of each.

### 4.1 Expired approval requests are invisible

**The defect.** When an approval request expires, it vanishes from the Approvals panel. A user
who steps away and returns is shown "Nothing waiting", which is what they would also see if the
request had never been queued. The two are indistinguishable in the interface.

**Where it lives.** `resources/clawfactory-sendd.js`, `handleList()` filters
`r.state === 'pending'`. A separate GC flips expired records to `state: 'expired'`, so they
drop out of the list.

**Evidence the design intended otherwise.** `handleList()` already returns a per-record
`expired` boolean. Because the GC changes state, that flag can only be true in the narrow
window between real expiry and the GC noticing. The feature was designed and then closed off by
the reaper.

**Why it is not urgent, and this matters for how you scope it.** Hiding expired requests was
never the security control. `handleApprove()` refuses anything whose state is not `pending`
(`ESTATE`), then independently re-checks expiry under the store lock immediately before opening
a connection (`EEXPIRED`), and staging is purged on expiry so there would be nothing to
transmit. Showing expired cards cannot make them approvable. Treat this as UX on a
safety-critical surface, not as a hole.

**The open design question.** Records are retained for `pendingRetentionHours: 24`. Showing
every expired record for a day means the panel accumulates dead cards, and a panel people stop
reading is worse than the current confusion. Options worth weighing: a shorter display window
than the retention window; a dismiss action; collapsing them into a single "3 requests expired
while you were away" line; or showing only since-last-viewed. This is a product decision, not a
technical constraint.

**Scope note.** Touching `handleList()` means touching a shipped security component, so the
change needs the full build and validate cycle rather than a Studio-only rebuild.

### 4.2 The footer says "MIT licensed"

Studio's footer reads `Frontier Automation Systems LLC . MIT licensed`. The licence decision
was PolyForm. The Secure-Setup repo `LICENSE` is also still MIT. Customer-facing.

### 4.3 The header reads `v0.1.0`

`App.tsx:37` is a hardcoded literal, against an installed product reporting 1.2.0. Cosmetic,
but it is the string that made D4 look like a stale payload, so it has already cost real time
once.

### 4.4 Also worth folding in while the build is open

- **`ClawFactory-Studio-Setup-1.1.0.exe` now names a third distinct set of bytes.** The pin
  digest is the authority so this is a confusion hazard rather than a security one, but the
  filename should carry a version. Bumping touches `ClawFactory-Secure-Setup.iss:16`,
  `build_release.ps1:127` and `:128`, plus Studio's `package.json` files. Doing it in the same
  pass as 4.3 makes the header, the filename and `package.json` finally agree.
- **The approval card truncates the attachment hash** to 16 characters with no way to reveal
  the full value. Minor, but the staging guarantee rests on the user being able to see what
  will actually be transmitted.

---

## 5. What is proven, so it does not get re-litigated

- **All three Studio panels work**, driven by hand, with every outcome verified through the
  root channel rather than taken from the interface. Restore is byte-exact by sha256. The
  credential lands `root:root 600` and uid 1000 is refused. Approve transmits and the provider
  returns a queue id. Deny discards the staged bytes.
- **The agent cannot reach the approval path through the Studio IPC bridge.** 13 PASS, 1 NOTE,
  0 FAIL, measured against a running Studio, with a paired Windows-side control that succeeds
  so the refusals are statements about the caller rather than a dead path.
- **Studio owns none of the box's 29 listening sockets**, and no remote-debugging port is open.
- **Guard 2's gate holds at expiry and at denial.** Nothing sent, staging purged, decisions
  recorded in root-only audit records.
- **The SMTP save path works.** It could not before 2026-08-13: `invokeEngineWithInput` wrapped
  a two-statement expression in the PowerShell grouping operator `( )`, which takes one
  pipeline, so it died at parse time and surfaced as "the send service did not respond".

---

## 6. Known bypasses. Do not describe the product as if these are closed.

1. **The agent can exfiltrate to the model provider.** The gateway runs as the agent's uid and
   holds the provider credential; anything the agent reads can leave over allowlisted 443. No
   v1 guard touches this. Card #197.
2. **Door 2, full-path `.mjs` execution.** Agent and gateway share a uid. Accepted v1 residual.
3. **Deletes that are not `rm`.** `unlink`, `find -delete`, `fs.rmSync`, `os.remove` and
   truncation via `>` all bypass the quarantine wrapper. Measured, not assumed.
4. **Root is out of scope by design.**

### The claim sentences the evidence supports

> Your agent can write an email. It cannot send one. Every message waits for you, and approving
> it sends exactly that message, once.

> When your agent deletes a file in a folder you granted it, the file is held for 30 days and
> you can put it back. This covers deletion by name, which is how deletion is ordinarily
> expressed; it does not cover every possible way a program can destroy a file.

Both must carry this boundary wherever the mechanism is described:

> This covers email. It is not a claim that no data can leave your machine: your agent talks to
> a hosted AI model, and anything it can read it can send there.

**Never write that data cannot leave the machine without approval.** Guard 2 gates email; it
does not gate egress.

As of this session, both sentences may now be paired with claims about Studio.

---

## 7. Build and validate

**Build and sign** (seven pre-build gates, refuses on any drift):

```
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\build_release.ps1
```

**Rebuild Studio first if Studio changed**, from the Studio repo root, then copy
`desktop/release/ClawFactory-Studio-Setup-1.1.0.exe` into Secure-Setup `resources\` and update
`$studioPinned` in `build_release.ps1`:

```
$env:CLAWFACTORY_SIGN_SCRIPT = 'C:\Users\bmcki\ClawFactory-Secure-Setup\scripts\sign_installer.ps1'
npm run package
```

**Validate on a clean Azure box.** Repin `$Sha256` and `$ExpectBytes` in
`validation/interim-v120-validate.ps1` first:

```
powershell -NoProfile -ExecutionPolicy Bypass -File .\validation\interim-v120-validate.ps1 -VmName cfv-161
```

**Drive the panels.** `validation/interim-v120-panels.ps1` is committed and has steps
`prep-quarantine`, `verify-restore`, `verify-cred`, `prep-approval`, `verify-approve`,
`verify-deny`. Run them through the job runner with `-ScriptArgs "-Step <name>"`. A human at the
keyboard over RDP does the clicking between steps.

**The sixth channel.** `validation/interim-v120-phase5.ps1`, run while Studio is open.

**Teardown**, which also releases the license slot:

```
powershell -NoProfile -ExecutionPolicy Bypass -File .\validation\job3-teardown.ps1 -VmName cfv-161 -ResourceGroup clawfactory-validation -OutDir "C:\Users\bmcki\ClawFactory-Secure-Setup\validation-runs"
```

### Environment facts that otherwise cost an hour each

- DSv5 quota in westus2 is **0**. Use `Standard_D2s_v4`.
- Use image `clawfactory-win11-baseline-v2`.
- **`az vm run-command` runs one at a time.** Overlapping jobs fail with a Conflict.
- `az vm run-command` runs as SYSTEM and **cannot touch WSL**. Anything WSL-side needs the
  interactive auto-logon session, which is what `interim-v120-runner.ps1` is for.
- The installer sets `[automount] enabled=false`, so **Windows is not visible in the distro**.
  Note that `/mnt/c` exists as an empty stub, so `[ -d /mnt/c ]` is not a valid test of this.
- `/tmp` is tmpfs and is wiped by a restart. Use `/var/tmp`.
- Always pass `-OutDir` explicitly to the teardown script.
- **RDP is not open by default** (`--nsg-rule NONE`). Add a rule scoped to a single `/32`.
- A working throwaway Gmail app password **already exists and is deliberately kept**. Do not
  ask for a new one, and do not close out by asking for it to be revoked.

### Validation discipline that actually catches things

- **Every block assertion carries a control that must fail in the same run.** A test whose
  control does not fail is a void result, not a pass.
- **Prove liveness by the thing itself, not by a status report.**
- **A new probe inherits none of the preconditions of the phases beside it.** This session's
  first run recorded "Guard 1 failed on a clean box" because it issued a load-bearing agent turn
  without warming the agent first. Every precondition in the existing phases was added because
  something lied once.

---

## 8. Open decisions

1. **How expired requests should appear** (section 4.1). The only genuinely open design
   question, and it is a product call rather than a technical one.
2. **The licence.** PolyForm was decided; the Studio footer and the repo `LICENSE` still say
   MIT.
3. **Guards 3 and 4**, then step 7, full validation on the assembled build. That has never run.
4. **Tag and release.** Nothing is tagged past `v1.1.0` and the release gate has not been run.
5. **#199a**, the agent does not discover `clawfactory-send` on its own. Resolved as a product
   decision, documented for the user in `docs/reference/EMAIL_APPROVAL.md` rather than fixed in
   the persona. Reopen only deliberately.

---

## 9. Housekeeping

- Working tree clean in both repos, everything pushed.
- Dispatch card #243 closed.
- **Zero Azure VMs.** cfv-160 created and deleted the same day, roughly 3 hours, license slot
  released.
- `ClawFactory_Install_Lessons_Learned.md` gained **L28**: three weak signals that agree with
  each other feel like proof and are not. That is the lesson D4 taught, and it is worth reading
  before trusting any diagnosis assembled from circumstantial evidence.
- Not done, deliberately: no tag, no publish, no Inno licence purchased, no Guard 3 or 4 work,
  no product defects fixed beyond the parse defect, no restyle.
