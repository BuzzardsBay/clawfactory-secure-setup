# Why `openclaw gateway install` fails — Azure probe — 2026-07-15

**CAUSE CAPTURED, VERBATIM.** Card #125 → **done** (probe complete; the fix is the next job).

> **`openclaw gateway install --force --port 8787` fails with `EACCES: permission denied`
> writing `/home/clawuser/.config/systemd/user/openclaw-gateway.service`, because
> `setup.ps1:1706` creates that directory chain **as root** via `mkdir -p` while
> `setup.ps1:1862` chowns back only the **leaf** `.service.d` — leaving the `user/`
> directory root-owned and unwritable by clawuser, who is deliberately the one who runs
> the install (1909).**

The egress-firewall suspect is **DEAD** — clawuser's network is fully working. Task 3
was skipped by the job's own decision rule, mechanically, and **no firewall rule was
ever touched**.

VM: `cfv-0715p`, provisioned 20:24:19, destroyed 21:04 PT. **~$0.13.**

---

## 1. THE ANSWER (Task 2.2) — verbatim

```
--- unit BEFORE (expect: absent) ---
ls: cannot access '/home/clawuser/.config/systemd/user/openclaw-gateway.service': No such file or directory

--- RUNNING: su clawuser -s /bin/bash -c 'openclaw gateway install --force --port 8787; echo rc=$?' ---
Gateway install failed: Error: EACCES: permission denied, open '/home/clawuser/.config/systemd/user/openclaw-gateway.service'
rc=1

--- unit AFTER (did the manual re-run create it?) ---
ls: cannot access '/home/clawuser/.config/systemd/user/openclaw-gateway.service': No such file or directory
```

It fails **the same way on a manual re-run** — so this is not a timing or ordering
artifact of the installer. It is deterministic.

**`EACCES`, not `ENOENT`, is the whole tell.** `open()` returns ENOENT when the parent
directory is missing and EACCES when the parent **exists but is not writable**. So
`/home/clawuser/.config/systemd/user/` exists and clawuser cannot write into it.

---

## 2. The mechanism — proven in `setup.ps1`

```
1705   OVERRIDE_DIR=/home/clawuser/.config/systemd/user/openclaw-gateway.service.d
1706   mkdir -p "$OVERRIDE_DIR"
         ^ run as ROOT (the whole $script block is Invoke-WslBash -User 'root', line 1874).
           `mkdir -p` creates EVERY missing parent — .config, .config/systemd,
           .config/systemd/user — and they are owned by the CREATING user: root.

1860   # --- h. Chown everything back to clawuser --------------------------------
1861   chown -R clawuser:clawuser /home/clawuser/.openclaw
1862   chown -R clawuser:clawuser /home/clawuser/.config/systemd/user/openclaw-gateway.service.d
         ^ the LEAF only. -R descends INTO .service.d; it never touches the three
           parent directories root just created.

1909   # Runs as clawuser (not root) so the unit lands under /home/clawuser/
1910   # .config/systemd/user/, not /root/.
1918   openclaw gateway install --force --port 8787
         ^ clawuser writes into a root-owned directory -> EACCES.

1921-1923  if [ "$rc" -ne 0 ]; then echo "[gateway-install] WARN: ... continuing" >&2
         ^ the failure is demoted to a warning; daemon-reload/enable/restart then run
           `|| true` against a unit that does not exist, and the install dies 120s
           later blaming the gateway.
```

The comment at 1909 is the irony: running as clawuser is **correct and deliberate** —
it is what keeps the unit out of `/root/`. The bug is that root got there first.

---

## 3. Why this was latent for 38 versions — the Docker step was propping it up

Both lines date to the **initial release**, not to v1.0.38:

```
=== when was OVERRIDE_DIR / the drop-in introduced? ===
d9b6d36 Initial release: ClawFactory Secure Setup v1.0
=== when was the chown-back line introduced? ===
d9b6d36 Initial release: ClawFactory Secure Setup v1.0
```

So why did **v1.0.37 / cfv-137 pass**? Because the **removed Docker step** ran
`su - clawuser -c 'dockerd-rootless-setuptool.sh install'`, and per Docker's own docs
that tool **creates `~/.config/systemd/user/docker.service`** — i.e. it created
`/home/clawuser/.config/systemd/user/` **as clawuser**, *before* the gateway step. Root's
later `mkdir -p` then had nothing to create, and ownership stayed correct.

**Removing Docker (Job 3, decision A) removed the thing that was accidentally making the
gateway install work.** This is the **fourth** hidden dependency on that step. `setup.ps1`
already documents three, at line 1183 — *"TRAP (why this is NOT a plain deletion)"* —
naming `nftables` (the firewall backend), `dbus-user-session`, and the linger call. The
`.config/systemd/user` ownership was missed, because nothing in the flow ever asserted it.

This also explains every observation the lineage collected:

| Box | Docker ever installed? | `.config/systemd/user` owner | Gateway |
|---|---|---|---|
| cfv-137 (v1.0.37) | yes | clawuser | **PASS** |
| cfv-0715h / p (v1.0.38) | no | root | **FAIL — EACCES** |
| Bret's daily driver | yes (historically) | clawuser | works |
| local scratch distro | n/a — died at `user@1000` first | — | never got here |

---

## 4. Ruled out, with evidence

**Egress firewall — DEAD.** clawuser's network is fully functional at the moment of
failure:

```
--- can clawuser reach the network AT ALL right now? ---
  curl https://registry.npmjs.org -> http=200 exit=0
  dns registry.npmjs.org rc=0
--- is the clawfactory table even present? ---
  table inet clawfactory: PRESENT          (allowed_ipv4 populated, ~70 live elements)
```

The firewall is up and correctly scoped, and clawuser gets HTTP 200 through it. Task 3's
A/B would have proven nothing:

```
########## TASK 3 DECISION -- is 2.2's error network-ish? ##########
  VERDICT: NOT network-ish -> SKIPPING Task 3 per the job's decision rule.
```

That decision was made **by a mechanical grep of 2.2's output inside the probe**, not by
me after the fact — the rule was written before the answer was known.

**The upstream `is-enabled` bug (openclaw#33512/#33633) — DEAD.** This was my *stated
prediction* going in, and the VM killed it. That bug returns **exit 4** with
*"systemctl is-enabled unavailable"* on **2026.3.2**. We see:

```
--- systemctl --user is-enabled (THE preflight openclaw runs; exit 4 = not-found) ---
Failed to get unit file state for openclaw-gateway.service: No such file or directory
is-enabled rc=1
--- openclaw --version ---
OpenClaw 2026.4.27 (cbc2ba0)
```

Different rc, different message, and a version well past the fix (PR #33634). Prediction
falsified by evidence — which is what the probe was for.

**Version/subcommand mismatch — DEAD.** `/usr/bin/openclaw`, `OpenClaw 2026.4.27`,
node `v24.18.0`, npm `11.16.0`, and `openclaw gateway --help` lists `--port`/`--force`.

**OpenClaw's own install — CLEAN.** `/tmp/openclaw-install.log` (Task 2.1, the log
`setup.ps1:1913` writes and nothing ever reads back) ends:

```
[2/3] Installing OpenClaw
  Installing OpenClaw v2026.4.27
  OpenClaw npm package installed
  OpenClaw installed
[3/3] Finalizing setup
  OpenClaw installed successfully (2026.4.27)!
  Skipping onboard (requested); run openclaw onboard later
```

Note it is `-rw-r--r-- 1 root root` — corroborating that this phase runs as root.

---

## 5. What is observed vs inferred — stated plainly

**Observed (verbatim):** the EACCES error and its exact path; that a manual re-run fails
identically; that the unit is absent before and after; that clawuser's network works;
that openclaw/node/npm are sane.

**Proven from source:** root creates the chain at 1706; the chown at 1862 covers only the
leaf; the install runs as clawuser at 1918; the rc is swallowed at 1921.

**Not directly observed:** the actual `ls -ld` ownership of
`/home/clawuser/.config{,/systemd,/systemd/user}` on the box. The probe captured the
error but not the ownership of the path it names. The chain above is a tight inference
(EACCES-not-ENOENT + POSIX `mkdir -p` semantics + the code), **not** a guess — but it is
an inference, and the honest thing is to say so.

**The single observation that closes it** (one line, and the fix session gets it for free
since the fix must touch exactly this path):

```bash
ls -ld /home/clawuser /home/clawuser/.config /home/clawuser/.config/systemd \
       /home/clawuser/.config/systemd/user /home/clawuser/.config/systemd/user/openclaw-gateway.service.d
# expect: .config, .config/systemd, .config/systemd/user  -> root:root   (the bug)
#         openclaw-gateway.service.d                      -> clawuser    (the partial chown at 1862)
```

If that comes back root-owned, the chain is closed end to end. If it comes back
clawuser-owned, this report is wrong and the EACCES has another source — in which case
capture `namei -l` on the full path and the process's effective uid.

---

## 6. Ledger

| # | Item | Result |
|---|---|---|
| Gate 1 | `CLAUDE_ClawFactory.md` firewall/egress lore + step ordering | **DONE** — found the load-bearing fact: `meta skuid != clawuser return`, so the firewall scopes **only** clawuser |
| Gate 1 | cfv-0715h close-out (root cause, §4 probe, §6 L5/L6/L7/L2) | **DONE** |
| Gate 2 | Fetch card comments | **DONE** — #124 done/0 comments; opened **#125** |
| Gate 3 | State back: probe-only, failure expected, no key, two exit paths | **DONE** |
| Web | `openclaw gateway install` internals; rootless-docker unit path | **DONE** — issues #33512/#33633 (prediction, later killed); Docker docs confirm the `.config/systemd/user` creation |
| 0.1 | `git status --short` | **DONE** — clean at `05b70c4` |
| 0.2 | Staged installer reused, not rebuilt | **DONE** — blob `ClawFactory-Secure-Setup-v1.0.38.exe`, **340587592 B**, sha256 re-verified on the VM |
| 0.3 | RG holds only reusable infra, nothing billing | **DONE** — §7 |
| **0.3** | **Sweep list survives a killed harness** | **DONE** — `ACTIVE_VMS.txt` + `azure-sweep.ps1`; **and a bug in it was found and fixed** (§8) |
| 1.1 | Provision `cfv-0715p` | **DONE** — D2s_v4, Standard, agent Ready |
| 1.2 | Auto-logon + RunOnce, proven flags | **DONE** — `PAYLOAD_BYTES=9477`, sha256 verified on box |
| 1.3 | Poll to failure at 8c, no intervention | **DONE** — checkpoint ends at `OpenClawConfigured`, exactly as predicted |
| **2.1** | `/tmp/openclaw-install.log` | **CAPTURED** — OpenClaw's own install is CLEAN |
| **2.2** | **The exact failing command, rc + both streams** | **CAPTURED — THE ANSWER** — `EACCES`, `rc=1` |
| 2.3 | setup.ps1's own log at the corrected path | **FAILED — the file does not exist** (§8) |
| 2.4 | Version/subcommand sanity | **CAPTURED** — all sane; mismatch ruled out |
| **3.x** | Firewall A/B | **CORRECTLY SKIPPED** — error is not network-ish; **no rule touched** |
| 4.1 | Teardown by explicit name + unfiltered proof | **DONE** — §7 |

**Out of scope, untouched:** no installer fix, no rebuild, no suite. The swallowed rc,
`INSTALLER_EXIT=0`, and the `|| true` linger gap all remain deferred.

---

## 7. Resource ledger + teardown proof (UNFILTERED — L3)

```
=== VMs in subscription (UNFILTERED) ===
                                              <- empty: nothing billing

=== ALL resources in clawfactory-validation (UNFILTERED) ===
clawfactoryvalc467             Microsoft.Storage/storageAccounts   (reusable)
bake-vmVNET                    Microsoft.Network/virtualNetworks   (reusable)
clawfactory-win11-baseline     Microsoft.Compute/images            (reusable)
clawfactory-win11-baseline-v2  Microsoft.Compute/images            (reusable)

=== sweep list ===
(empty -- cfv-0715p de-registered after the listing proved it gone)
```
Harness verdict: `CLEAN -- no resource matching 'cfv-0715p' remains.` **~$0.13** (one VM,
~40 min D2s_v4). No provider key was placed on the VM (none needed — confirmed last cycle
and re-confirmed by the checkpoint dying before `WireProviderKey`).

---

## 8. SURPRISES

1. **My prediction was wrong, and the probe is why we know.** I went in expecting the
   upstream `is-enabled`-exit-4 bug, with the expected error string written into the
   script before the run. The box returned a completely different error. Had I "confirmed"
   the prediction from the GitHub issues alone — they matched the symptom *perfectly*
   (fresh-install-only, unit never written, chicken-and-egg) — the fix would have been
   built against a bug this product does not have.
2. **The Docker removal had a FOURTH hidden dependency.** Job 3 caught three (nftables,
   dbus-user-session, linger) and wrote them into a "TRAP" comment. It missed that
   `dockerd-rootless-setuptool.sh` was also the only thing creating
   `/home/clawuser/.config/systemd/user/` **as clawuser**. A removal that documents three
   of four hidden side effects still ships a broken installer — the lesson is that
   *nothing asserted the ownership*, so nothing could catch it.
3. **The bug is 38 versions old and only just became reachable.** It has been latent since
   `d9b6d36`; Docker was silently masking it the whole time.
4. **Task 2.3 failed: `C:\Program Files\ClawFactory\install.log` does not exist.**
   ```
   --- path exists? False : C:\Program Files\ClawFactory\install.log ---
   NOT FOUND -- enumerating what IS under C:\Program Files\ClawFactory:
   (no .log files)
   ```
   Last cycle I blamed the wrong path (`...\ClawFactory Secure Setup\`) for this. The
   corrected path is *also* wrong — setup.ps1's log lives somewhere else entirely, so the
   `GW-JOURNAL/GW-STATUS/GW-PORT/GW-TMPLOG` dump has **still** never been read. It did not
   matter this time (2.2 answered the question directly), but the diagnostic dump the
   installer works to produce remains unreachable. **Carded, not fixed.**
5. **The sweep list I added this session had a bug — caught by using it.** After a
   provably clean teardown, `ACTIVE_VMS.txt` still listed `cfv-0715p`.
   `Where-Object | Set-Content` **no-ops when the filter empties the pipeline**, so the
   list only ever cleared when 2+ VMs were registered. A guard that cries wolf every run
   is how a real alarm gets ignored — same family as the ORPHAN false alarm last session.
   Fixed, and the fix was proven by reproducing both paths side by side (old: entry
   survives; new: file cleared). Recorded as **L8**.

---

## 9. END-OF-SESSION GATE

**Task accounting:** §6. Every numbered item CAPTURED/DONE except 2.3 (failed — logged as
a finding) and Task 3 (correctly skipped by the decision rule). **The deliverable — the
definitive cause, verbatim — is achieved.**

**Delta security sweep.**
- **The Task 3 firewall relaxation NEVER RAN.** The decision rule skipped it, so no
  `nft` rule was added, flushed, or modified; the `restore` trap was never armed because
  there was nothing to restore. The ruleset on the VM was left exactly as the installer
  built it — and the VM was destroyed regardless. **No control was weakened anywhere.**
- Product code: **unchanged** — this was a probe. The only commits are probe/sweep
  tooling and lessons.
- The probe **observes only** — it runs the failing command (which the installer itself
  had already run) and reads logs. It does not repair, restart, or reconfigure. The one
  destructive line (`rm -f` the unit) lives **inside** the Task 3 branch that never ran.
- Secrets: the VM admin password and SAS tokens live in temp files outside the repo,
  shredded in `finally`; `validation-runs/` is gitignored; no key/token/password/SAS
  appears in this report. No provider key was ever placed on any VM.
- Bret's daily driver: **untouched**.

**Delta bug review — found, not fixed:**
1. **THE FIX (next job):** root's `mkdir -p` at 1706 creates `.config/`,
   `.config/systemd/`, `.config/systemd/user/` root-owned; the chown at 1862 covers only
   the leaf. Fix by chowning the parents (or creating them as clawuser in the first
   place), then **assert** the ownership so it can never regress silently.
2. **The swallowed rc at 1921-1923** — still the reason a precise EACCES surfaces 120 s
   later as "Gateway did not respond". Fix alongside #1: fail loud at the point of failure.
3. **setup.ps1's install.log path is still unknown** (§8.4) — the GW-* dump has never once
   been read back. Find the real path; the dump would have answered this in cycle one.
4. **`INSTALLER_EXIT=0` on a failed install** — Inno's `[Run]` failure does not propagate
   under `/SILENT`; the harness's success signal is unreliable.
5. **Both `enable-linger` calls are `|| true`** — pre-existing, irrelevant to this bug,
   still open.
6. **Nothing asserts `.config/systemd/user` ownership** — the class of gap that let a
   38-version-old bug hide behind Docker.

**Card #125 → done** for the probe. **Next = the fix job**, which should: chown/create the
parent chain correctly, make the gateway-install rc fail loud, assert the ownership, and
capture the `ls -ld` in §5 to close the last inferred link. Only then re-run the suite —
**the headline isolation claim remains unproven** and is still the #1 owed item.

---

## 10. Commits

```
9db121d  feat(probe): capture why `openclaw gateway install` never writes the unit
         (+ Task 0.3 sweep list: ACTIVE_VMS.txt + azure-sweep.ps1)
<this>   probe(8c): CAUSE -- EACCES, root-owned .config/systemd/user (+ L8)
```
