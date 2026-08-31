# ClawFactory v1.4.5

An install-path release. It fixes the way the installer fails on a machine that has never had
WSL, and it removes a fallback path that could not produce a working install.

If v1.4.4 installed correctly for you, v1.4.5 changes nothing you will notice. The whole of this
release is about what happens when the install does not work.

---

## Why this release exists

On 2026-08-30 the first person outside this project to run the v1.4.4 installer could not install
it. His machine was an ordinary Windows 11 PC that had never had WSL.

What v1.4.4 did on that machine:

1. It ran `wsl --update`. Windows enabled the Virtual Machine Platform feature and printed
   "Changes will not be effective until the system is rebooted." The installer wrote that
   sentence to its log and did not read it.
2. It ran `wsl --status`, which exited 0. The installer took that exit code as proof the Linux
   kernel was available. It was not.
3. It tried to import the bundled Ubuntu image. That failed with
   `HCS_E_SERVICE_NOT_AVAILABLE`.
4. It fell back to `wsl --install`, which **also exited 0** without creating anything.
5. Four steps later it tried to create a Linux user account inside a Linux environment that did
   not exist, and stopped with:

   ```
   Failed to pre-create clawuser stub (exit=-1)
   ```

He spent about 41 minutes reaching that message. It named a Linux user account on a machine
with no Linux, it did not say what had actually gone wrong, and it did not tell him what to do.
It also did not print the path to the install log.

## What v1.4.5 does instead

On a machine in the same state, the installer now stops in about two minutes with a message that
says what happened and what to do about it:

```
wsl --install reported success (exit 0), but no working 'Ubuntu' environment exists on this
computer afterwards. ClawFactory will not continue against an environment that was never
created. Two things cause this. Restart this computer and run the installer again - Windows
sometimes needs a restart before virtualization support becomes active. If that does not work,
check your BIOS/UEFI setup screen and turn on Intel VT-x (or AMD SVM Mode); Task Manager >
Performance > CPU > Virtualization will say Disabled if that is the cause. Full details are in
C:\ProgramData\ClawFactory\install.log.
```

This was measured, not designed and assumed. A stock Windows 11 24H2 machine was put into the
same state by the installer's own code path, and the run above is what it produced: 131 seconds
to that message, and no occurrence of the old `clawuser` error anywhere in the log.

**The advice in that message is the right advice.** In the reproduction, a restart was in fact
what the machine needed.

### Three changes deliver that, and they are independent of each other

- **A command that exits 0 is no longer treated as proof that a distro exists.** After
  `wsl --install` or `wsl --import` claims success, the installer now checks that an Ubuntu
  environment is actually present and responds to a command before anything downstream depends
  on it.
- **The virtualization diagnostic now reads the import stream as well.** The real error text on
  the failing machine appeared on the import path, which the previous code did not examine, so
  the diagnosis was drawn from the wrong half of the output.
- **The readiness check runs before the Linux user account is created**, not after. That is what
  turns "failed to pre-create clawuser stub" into a message about virtualization.

### Also fixed on the same path

- The install log path is now printed on every failure path. Its absence is part of why the
  first external install took as long as it did.
- If `wsl --list` fails, the installer now records nothing about whether an Ubuntu distro existed
  before the install, rather than recording "no". The uninstaller reads that value to decide
  whether a distro is ClawFactory's to remove, and "no" was the answer that permits removing a
  distro you already had.
- A failed install no longer reports that it undid steps that have no undo action.
- Log lines coming from `wsl.exe` no longer carry stray null bytes.

---

## The WSL1 fallback has been removed. This is a security fix

Earlier releases fell back to installing WSL **1** when WSL 2 reported that the hypervisor was
not available. That fallback is gone. If WSL 2 is unavailable, the installer now stops with a
named message rather than installing WSL 1.

The reason is not tidiness. **Eleven of ClawFactory's controls are systemd units**, including the
delete broker, the approval-gated send broker, the request-gating proxy and the egress allowlist
re-apply at boot. WSL 1 has no systemd. An install that completed on WSL 1 would have been an
install with those controls absent.

In practice it did not complete either. The WSL 1 path ran for roughly twenty minutes and then
failed on a gateway health check, telling the user nothing about the real cause. So the fallback
produced a long, confusing failure in the best case and, if it had ever succeeded, a quieter
install than the one the documentation describes.

**On hardware without nested virtualization, ClawFactory does not install.** That is now stated
plainly in the README rather than being discovered after twenty minutes.

---

## One fix in this release does not work, and it is shipped switched off

The release was scoped around five defects. One of them, the pending-reboot gate, **does not
function and is shipped inert.** It is documented as inert in the source, at all three places it
appears.

**What it was meant to do.** Detect that Windows had enabled the Virtual Machine Platform feature
but needed a restart before it took effect, and stop the install there.

**Why it does not.** It reads the typed state of the Windows feature and acts if that state is
`EnablePending`. On Windows 11 24H2 that value is never produced. The feature reads `Enabled`
both before and after the restart, so the signal it gates on is identical on both sides of the
thing it is supposed to detect. This was measured twice, on two separate machines, in the exact
state it was written for.

**How it came to be built that way.** It was proved by feeding the value `EnablePending` into the
function through the function's own test parameter. That proves the comparison works. It does not
prove Windows ever emits that value, and the test that would have asked was deferred and then not
taken before the code was described as working. That is our mistake, it is written up in full in
`docs/FAILURE_CATALOGUE.md`, and the practice that would have caught it has been added there.

**Why the release ships anyway.** The three changes that deliver the user-visible fix do not
depend on it. The measured improvement above (about two minutes to a clear message, against 41
minutes to an unusable one) was produced with this gate inert, because it never fired. Its cost
when it runs is about 1.25 seconds on an install.

**Rewriting it is v1.5 work.** Two signals that do carry the information were measured during the
same run and are recorded for that work.

---

## Security disclosures from v1.4.4 that still stand

Nothing in v1.4.5 changes any of these. They are repeated because they remain true.

- **The agent and the gateway share one user identity inside the Linux environment.** A control
  enforced anywhere that identity can influence is advisory, not structural. Separating them is
  v2 work.
- **The persona is a build-time constant.** It is pinned at build time and the running agent
  cannot author it. User-authorable personas are v1.5.
- **The build gates are advisory against anyone who can run the build scripts.** Invoking the
  Inno compiler directly and then the signer bypasses all nine of them. The build stamp makes
  that route fail, which defends against process drift rather than against an attacker with local
  execution. We describe it as exactly that and not more.

The removal of the WSL 1 fallback closes a gap that was previously implied rather than disclosed:
that an install could in principle complete with eleven systemd-based controls absent.

---

## Verification

- Signature: signed via Azure Trusted Signing, countersigned by the Microsoft Public RSA Time
  Stamping Authority. The signing certificate is short-lived by design and rotates; the
  countersigned timestamp is what keeps the signature valid afterwards.
- Unsigned SHA-256, as recorded in `released-versions.tsv`:
  `28e14e56e217b73d4e391c85700f5127afefa8866fc8a81c66897bc7e0158c08`, 440,604,218 bytes.
  The ledger records the unsigned digest because signing embeds a timestamp, so the signed digest
  differs on every signing run over identical input.
- Built by `scripts/build_release.ps1`, which is the only route that runs the nine pre-build
  gates, stamps the artifact and writes the ledger row.

**One limitation, stated rather than left to be discovered.** The build script recompiles when it
signs, and the compile embeds build-time metadata, so the signed artifact is not byte-identical
to the one the validation run was taken against. The two were built from the same commit with the
same gates passing, and differ in 2,526 bytes inside a single 2,592-byte region out of
440,604,218. The claim this release makes is "same source, same gates", not "same bytes".
Removing that gap is on the v1.5 list.

---

## Full record

- `docs/session_reports/2026-08-30_v145_install_path_fixes_closeout.md` - the fixes
- `docs/session_reports/2026-08-30_v145_validation_closeout.md` - the validation run
- `docs/session_reports/2026-08-31_d1_record_correction_closeout.md` - the pending-reboot gate
  correction, the rebuild and the re-take
- `docs/FAILURE_CATALOGUE.md` - including entry 15.1, the gate that shipped inert
- `docs/V1_5_BACKLOG.md` - items 8 and 9, the rewrite and the related fall-through
