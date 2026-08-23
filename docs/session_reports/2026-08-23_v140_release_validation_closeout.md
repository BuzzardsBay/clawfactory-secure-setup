# CLOSE-OUT: v1.4.0 housekeeping, build, and release validation, card #266

Session 2026-08-23. Phase 0 housekeeping, the v1.4.0 build, the packet-capture proof, and
the release matrix. No tag, no publish, no GitHub release: those are the next job.

**Status of this document: IN PROGRESS at the time of writing.** Sections marked PENDING are
work that had not finished when this draft was written. If the session ends before they are
filled in, the PENDING marker is the honest state and must not be read as a pass.

---

## 1. Phase 0, housekeeping

| Item | State |
| --- | --- |
| Secure-Setup push | `74563a7..03fa6d7`, remote head verified equal to local by `git ls-remote` |
| Studio push | `229ad26..1312035`, then `..66ca506` for the 1.3.1 rebuild |
| Site | committed `41365d3`, **pushed**, Pages build confirmed running at that exact commit |
| `clawagent-setup` | supersession notice committed FIRST (`3368e6b`, tense corrected in `b5b45ba`), then archived. `isArchived: true`, still PUBLIC, all four releases still resolve |

**Order mattered on the archive and was followed.** Archiving makes a repository read-only,
so the notice had to land first. It did.

**The site push corrected two claims that were live and false**, not merely stale marketing:

- *"Nothing leaves your machine without your permission."* The forbidden shape. Every turn
  goes to the hosted model, carrying whatever the agent read.
- *"It cannot read your files."* Untrue the moment a grant exists, and granting folders is
  described on the same page.

Also corrected there: the ClawAgent security-parity claim, the pricing framing in three
places, the PolyForm footer, and the product card, which presented ClawAgent as a current
choice while its repository was being archived.

**The Inno Setup position, reported not acted on.** Two facts, both established by
execution, and they are in tension. `license.txt` as installed grants commercial use with
no fee, under four attribution conditions a normal Inno-built installer satisfies. But
`ISCC.exe` and `Compil32.exe` both contain the UTF-16 string **"Non-commercial use only"**,
sitting beside "Update entitlement ended", so Inno 6.7.x has paid entitlement tiers and this
machine runs the free one. The scan was calibrated in both directions before being trusted:
a string the banner certainly prints matched, a planted sentinel did not, and an ASCII-only
scan found nothing at all. A free Apache-2.0 release plausibly sits inside the tier the
installed build is labelled for, so the free-release decision **narrows** this rather than
widening it. It gates nothing. It involves money, so it is the operator's call.

---

## 2. Phase 1, the build

All seven gates green, nothing auto-corrected.

```
SOUL pin OK          e70212603f2f91e6abf6db576c9535b1aaad60506e2fb075c199f18160db7941
Bundle check OK      all 34 preflight resources are in [Files]
Studio pin OK        e56139f80245e02d2ce1d00b794ed03b2f64b256d152bfbf45527a711a220a43
Version OK           1.4.0 (.iss and setup.ps1 agree)
Persona pin OK       0557d07004d4d067d8cd9e7cee7b2a3a783e0ac8ff4c492c0c152d7e35ff63a0
Workspace SOUL OK    441b6279f6613c313e87e9e9e034f97a220540cddbf1cf738bb9a86c37a5a257
Rootfs pin OK        1483cc5c1dce13064f774834cbffdff226559fd522a67a381a8ea77d63fb4109
```

| | |
| --- | --- |
| signed sha256 | `257f30ff6284a3645144b70822a9c55c342d4f90df179e00705dae3c52e6c390` |
| signed bytes | 440,613,512 |
| Authenticode | Valid, `CN=Bret Mckinney`, countersigned to 2026-10-22 |
| ledger row | `1.4.0  ClawFactory-Secure-Setup.exe  unsigned  67c3b21a7e9abc2be8475aa32a6abe58729772ff0c893c7480ea7db6397201ef  440597857  2026-08-23` |

The signing certificate's own `NotAfter` is 2026-08-24, one day out, which is normal for
Trusted Signing. Verified BEFORE the build by querying the certificate PROFILE via
`az rest` rather than inferring from an artifact: `clawfactory-cert` Active, provisioningState
Succeeded, three live certificates. The previous close-out's claim that nothing could be
signed was the same false alarm this project has raised and retracted once already.

### The Studio repin was four steps, not three

The brief and the prior close-out both described it as three edits. It could not be, because
**there was no artifact to repin to**: #265 corrected Studio's source and left the packaged
1.3.0 still carrying the old strings. So Studio was rebuilt and re-signed as **1.3.1** first.

The version bump is not cosmetic. `artifactName` carries `${version}`, so rebuilding at
1.3.0 would have produced a same-named, different-digest artifact, which is the exact drift
the pin exists to catch.

| | |
| --- | --- |
| Studio 1.3.1 sha256 | `e56139f80245e02d2ce1d00b794ed03b2f64b256d152bfbf45527a711a220a43` |
| bytes | 100,033,848 |
| Authenticode | Valid, `CN=Bret Mckinney` |
| installed app.asar | `5c4ffbf420814939579f00f0b8e69e949ba34af20d239ddcdc6cf4da383e2d85` |

Then the three edits, together: the digest and name in `build_release.ps1` and the `.iss`
define; the two retired strings moved out of phase 6's PRESENT list into its ABSENT list,
joined by `runs entirely on your machine`; and two new PRESENT markers.

**A bare `Apache-2.0` was rejected as the new PRESENT marker.** Dozens of `node_modules`
licence banners carry it, so the assertion could never fail, and a control that cannot fail
is decoration. Verified against the packaged `app.asar` before pinning: 20 of 20 PRESENT,
9 of 9 ABSENT, positive control OK.

---

## 3. Phase 2, the packet-capture proof

**PROVEN, on a fresh install, with a control that fired in the same run.**

The instrument is two windows. Window A brackets the real install and expects silence.
Window B, immediately after, deliberately fetches `https://api.clawfactory.app/` from
Windows and expects a signal. Window B is registered with `Register-Control`, so a blind
instrument voids the phase instead of reporting a clean pass. A capture that records nothing
is not a result until the same instrument, on the same machine, against the same host, has
produced a signal in the same run.

Measured on cfv-171, `/PROVIDER=later`:

```
WINDOW A (whole install)   dns subject=False  dns control=True   pkt subject=0  pkt control=0
WINDOW B (calibration)     dns subject=True                      pkt subject=48

P1.LC.CTL   PASS   the capture can see a Windows-side call to api.clawfactory.app
P1.LC       PASS   The installer makes NO outbound licence call to api.clawfactory.app
```

The DNS channel is primary and it is the one that carried the verdict: the removed call used
a hostname, never a literal address, so it could not have been made without resolving that
name. Its control host appeared during the install and the subject never did. pktmon saw
zero control packets, so it was correctly excluded as blind, because the install's traffic
leaves from inside WSL2 on a virtual adapter the capture does not cover.

**The string scan was refused as evidence** and the refusal is not theoretical: the shipped
1.3.5 binary returns zero hits for `api.clawfactory.app` while demonstrably containing it,
because Inno compresses the `[Code]` section.

### The corroborating measurement, from the opposite direction

cfv-173, matrix row 2, **7 of 7 rows PASS, every control fired**:

```
B1    PASS  the block is real and specific
            subject reachable=False, control openclaw.ai reachable=True
B2    PASS  the block WOULD have stopped the old licence-carrying build
            v1.1.1 under the identical block: log carries 'License activation failed'=True,
            and it installed nothing=True
B2.1  PASS  v1.1.1 left the box clean for the subject install
B3    PASS  v1.4.0 installs to completion with api.clawfactory.app unreachable
B3.1  PASS  the block was still in force when the install finished
```

Same box, same block, same run: the old build dies where the new one completes. That is the
behaviour change measured on one machine rather than argued from source.

---

## 4. The matrix, every row at its true state

| # | Test | State | Where |
| --- | --- | --- | --- |
| 1 | Clean install, all resources, all pins, five-page wizard | **PASS** | cfv-170 phase 1, 16 PASS / 5 INFO of 22 rows |
| 2 | Install completes with `api.clawfactory.app` unreachable | **PASS** | cfv-173, 7/7, with the v1.1.1 abort control |
| 3 | Provider gate healthy plus blocked CONTROL | **PASS** | cfv-170, 11 PASS / 1 INFO of 12 |
| 4 | Provider gate skipped with a stated reason under `-Provider later` | **PASS** | cfv-171, 5/5 |
| 5 | `SP.*` no toolchain address enters after a switch | **PASS** | cfv-170, SP.4a and SP.4b |
| 6 | `SP.*` toggle OFF, GitHub and npm unreachable after a switch | **PASS** | cfv-170, SP.5a |
| 7 | CONTROL for 6: toggle ON, reachable | **PASS** | cfv-170, SP.6a |
| 8 | `TC.3` real agent turn with the toggle OFF | **PASS** | cfv-170, both runs |
| 9 | `TC.1,2,4,5,6,7,8` regression | **PASS**, 30/30 on the re-run | cfv-170 |
| 10 | Reboot pass | **PENDING** | needs the operator |
| 11 | The MANUAL panel checks by hand | **PENDING** | needs the operator |
| 12 | Harness self-test 15/15, build machine and box | **PASS** on both | |
| 13 | Zero malformed verdict rows | **PASS** so far | every phase counted N of N |
| 14 | Step 7, full assembled-build validation | **IN PROGRESS** | see section 6 |

---

## 5. Findings

### Product findings

**One so far, and it is pre-existing and already documented.** `SP.8.PRE` FAIL: with the
toolchain toggle off, `clawhub.ai:443` still connects, because it shares an address with the
permanently-allowed `openclaw.ai`. This is the address-scoping residual in
`SECURITY_FINDINGS.md`. It is not a regression.

**Its premise is now stale, and that is the more useful finding.** The check asserts the hub
must be unreachable BECAUSE THE PANEL COPY SAID the toggle stops skill installation. This
release removed that claim. Phase 6 confirmed independently that the shipped 1.3.1 asar no
longer carries it. So the check now asserts against a claim the product does not make.

**I did not change it.** Adjusting a check to green after watching it fail, during a release
run, is the wrong instinct even when the reasoning is sound. Carded.

### Harness findings, carded rather than fixed under release pressure

- **`TC.1a/1b/1c` turn a missing precondition into three product FAILs.** The phase before
  them ends by deliberately switching the toolchain toggle OFF, so `TC.1` reads a box that
  is not in the fresh-install state it assumes. They should `Require-Precondition` and record
  VOID with a named reason. Proven by re-running from the state `TC.9` leaves behind: 30/30.
- **`setup.ps1` carries one non-ASCII character in a BOM-less file**, a pre-existing em-dash
  in a comment. PowerShell 5.1 reads a BOM-less file as ANSI, so it is mangled on read. I
  fixed it and reverted within the minute: `setup.ps1` is an input to the artifact already
  signed and under test, and editing it would make the repository disagree with the binary.

### Defects in my own instruments, found and fixed during the run

Four, and none of them was the product. All four were caught the same way: a number that did
not fit, checked against the raw evidence rather than explained.

1. **The packet counter counted mentions, not packets.** pktmon declares its filters in the
   dump header, so a capture with zero packets still contains the address once. Window A
   counted exactly 1 for the subject AND exactly 1 for the control, which is the signature of
   two filter echoes and no traffic. Confirmed verbatim on the box: `A.txt` line 34 is
   `Packet Filter 1, Name cf694646108 ... IP-1 69.46.46.108`. Fixed to match address-plus-port
   and calibrated against both real line shapes.
2. **A blind channel was allowed to produce a verdict.** Window B proves the instrument CAN
   see the call; it does not prove either channel was watching. Each channel is now gated on
   its own in-window control and excluded in EITHER direction when it did not fire.
3. **My python edits stripped the UTF-8 BOM.** PowerShell 5.1 then read the file as ANSI and
   a marker containing a middot could never match, so phase 6 reported `missing markers=1`
   against an asar that demonstrably contained every marker. Marker is now ASCII and the file
   carries a BOM.
4. **`ExtraStage` was uploaded but never downloaded.** cfv-172 ran its whole install with the
   v1.1.1 comparison control absent. The phase did the right thing and voided rather than
   reporting the two rows that had passed. Fixed, plus an assertion that each extra is present
   on the box at stage time.

Two more, smaller: `powershell -File` drops an empty-string argument, so `-Phase1Extra ''`
failed at parameter binding, now a sentinel; and a bad slice using `s.index()` on a
non-unique anchor DUPLICATED a block in the offline probe instead of removing one, caught by
grepping for the install argument and finding two matches where there should be one.

### A finding about the brief

The brief says the manual panel checks have "never passed in any run". The v1.3.5 close-out
records them passing on cfv-169, first time, all six by hand. They have never passed against
**this** build, which is the part that matters, and the checklist has been rewritten because
it was stale in exactly the places this release changed.

---

## 6. PENDING

- Matrix rows 10 and 11, which need the operator.
- The remaining step 7 guard phases.
- `G1.7`, under investigation at the time of writing.
- Guard 2 rows gated on the SMTP credential.
- Final fit-to-publish statement.

---

## 7. Resource ledger

| Resource | State |
| --- | --- |
| cfv-170 | **ALIVE, deliberately.** Holds the installed product for the panel checks and the reboot pass |
| cfv-171 | torn down: vm, nic, pip, nsg, disk, each by explicit name, every call exit 0 |
| cfv-172 | torn down the same way. Its install was spent and row 2 needed a clean box |
| cfv-173 | torn down the same way, after its evidence was retrieved |
| RDP | one rule, `67.164.251.99/32`, port 3389, read back and confirmed. No wider rule on the NSG |
| Studio 1.3.1 | new signed artifact, in `resources/` and in the Studio repo's release dir |

Teardown was proven by an UNFILTERED resource list, polled until ARM's eventual consistency
settled rather than trusting the first read, which still showed `cfv-173-osdisk`.

Residual after teardown: the storage account, the vnet, the two baseline images, and cfv-170
with its children. Nothing else.
