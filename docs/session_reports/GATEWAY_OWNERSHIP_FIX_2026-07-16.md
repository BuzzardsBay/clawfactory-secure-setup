# Gateway-unit ownership fix + fail-loud guards — v1.0.39 — 2026-07-16

**FIXED, BUILT, SIGNED, STAGED.** Card #125 → done. Local session — no Azure, no VM;
the clean-machine validation that *proves* the fix is the next job.

The v1.0.38 clean-install failure (root-caused on `cfv-0715p`: `openclaw gateway
install` runs as clawuser and hit `EACCES` writing the systemd unit because root owned
the `.config/systemd/user` parent chain) is fixed three ways — the ownership itself, a
durable assertion, and honest failure signals — plus the two false-success bugs the
probe exposed.

Signed artifact: **`ClawFactory-Secure-Setup-v1.0.39.exe`**, sha256
`1b63dd0c…b0ae2c`, 340587832 B, blob `installers/…v1.0.39.exe` (byte-exact verified).

---

## 1. The fix, precisely — before / after

### Task 1 — own the parent chain (`setup.ps1`, sub-block b, ~1706)

The `mkdir -p` runs inside a **root**-context block (`Invoke-WslBash -User 'root'`), so it
created `.config`, `.config/systemd`, `.config/systemd/user` **root-owned**. Added an
explicit non-recursive chown of those three parents + the leaf immediately after:

```bash
 OVERRIDE_DIR=/home/clawuser/.config/systemd/user/openclaw-gateway.service.d
 mkdir -p "$OVERRIDE_DIR"
+chown clawuser:clawuser \
+    /home/clawuser/.config \
+    /home/clawuser/.config/systemd \
+    /home/clawuser/.config/systemd/user \
+    "$OVERRIDE_DIR"
 cat > "$OVERRIDE_DIR/clawfactory-tunables.conf" <<'EOF'
```

Non-recursive, so it touches only those four directories: **corrects** them if root owns
them (the bug), **harmless no-op** if clawuser already does (Docker-era boxes, re-runs).
The leaf-only `chown -R …service.d` in sub-block (h) is kept — it owns the `.conf` inside.

### Task 2 — assert it (top of `$gatewayInstall`, before the install)

The bug hid for 38 versions because **nothing asserted ownership**. Now, right before
`openclaw gateway install` (which runs as clawuser):

```bash
UNIT_DIR=/home/clawuser/.config/systemd/user
for d in /home/clawuser/.config /home/clawuser/.config/systemd "$UNIT_DIR"; do
    owner="$(stat -c '%U' "$d" 2>/dev/null || echo MISSING)"
    if [ "$owner" != "clawuser" ]; then
        echo "[gateway-install] FATAL: $d is owned by '$owner', not clawuser -- ... (EACCES) ..." >&2
        ls -ld /home/clawuser/.config /home/clawuser/.config/systemd "$UNIT_DIR" 2>/dev/null >&2 || true
        exit 90
    fi
done
```

Fail-loud, names the offending dir + actual owner, dumps the `ls -ld` chain the probe had
to gather by hand, exits 90.

### Task 3 — stop swallowing the install rc (same block + PowerShell side)

**Before:** a non-zero rc was a `WARN` that continued into `daemon-reload/enable/restart`
(each `|| true`) on a nonexistent unit; the block always `exit 0`; PowerShell only
`Write-Log WARN`. So a precise `EACCES` surfaced 120 s later as *"Gateway did not respond"*.

**After** — the unit file existing is the exact success criterion:

```bash
install_out="$(openclaw gateway install --force --port 8787 2>&1)"; rc=$?
printf '%s\n' "$install_out"
UNIT="$UNIT_DIR/openclaw-gateway.service"
if [ ! -f "$UNIT" ]; then
    echo "[gateway-install] FATAL: 'openclaw gateway install' exited $rc and did NOT create $UNIT." >&2
    printf '%s\n' "$install_out" >&2
    if [ "$rc" -ne 0 ]; then exit "$rc"; else exit 1; fi
fi
# unit exists + rc!=0 => documented transient (auto-start hiccup); defer to /status poll
```

`|| true` removed from the three systemctl calls (`set -o pipefail` added, so a genuine
failure aborts). PowerShell side now **throws** instead of warning:

```powershell
-  if ($rcGateway -ne 0) { Write-Log WARN "... no longer treated as fatal ..." }
+  if ($rcGateway -ne 0) { throw "openclaw gateway install failed (exit=$rcGateway): the systemd user unit ... was not created. See ... $LogFile ... (exit 90 = ownership guard tripped; any other = install did not write the unit)." }
```

**Task 3.2 preserved:** the downstream `/status` health poll (13×10 s) and its diagnostic
dump + throw are untouched — the documented 3–14 s active-but-refused cold-start window
still tolerated. `restart` returns as soon as node is exec'd for a Type=simple unit
(before the port binds), so failing it loud does not race that window.

**Logic verified locally** (bash `-n` + mocked control-flow, since Git Bash lacks Unix
ownership):

```
guard:      root->exit 90    clawuser->exit 0    MISSING->exit 90
fail-loud:  no-unit->ABORT   unit+rc0->PROCEED   unit+rc!=0->defer to /status poll
```

### Task 4 — honest success signal (`scripts/azure-validate.ps1`)

`setup.ps1` **already** exits 1 on failure (`exit ([int](-not $InstallSucceeded))`, 2821)
and writes `INSTALLER_DONE=success|failure` to `install-result.txt` (2807/2813). The lossy
layer is Inno: the `.iss` `[Run]` entry (`Flags: waituntilterminated`) does **not**
propagate setup.ps1's exit code, so `setup.exe` exits 0 regardless. Making Inno propagate
an arbitrary child code isn't cleanly supported by a `[Run]` entry (it needs a `[Code]`
`Exec`+forced-abort, which also triggers file rollback) — so the correct, low-risk fix is
**consumer-side**: assert on the honest marker.

- `wrapper.cmd` now appends `C:\ProgramData\ClawFactory\install-result.txt` into
  `INSTALLER_DONE.txt` after `setup.exe` returns.
- the install poll parses `INSTALLER_DONE=(success|failure)` and reports **that** as the
  verdict, explicitly labelling `setup.exe`'s `INSTALLER_EXIT` as *not authoritative*.

**What the next validation cycle asserts on:** `INSTALLER_DONE=success` (from the marker),
never `setup.exe`'s exit code.

### Task 5.1 — the real log path

`setup.ps1:66-67`: `$LogDir = Join-Path $env:ProgramData 'ClawFactory'`,
`$LogFile = "$LogDir\install.log"` → **`C:\ProgramData\ClawFactory\install.log`**. Both
earlier guesses (`…\ClawFactory Secure Setup\` and `…\ClawFactory\` under *Program Files*)
were wrong, which is why the `GW-*` dump was never read back. Corrected in
`probe-gateway-install.ps1`.

---

## 2. Ledger

| # | Item | Result |
|---|---|---|
| Gate 1 | Read `setup.ps1` ~1690-1935; confirm diagnosis vs source | **PASS** — matches at every point (§1 of the reopened card / stated back in chat) |
| Gate 2 | `cfv-0715p` close-out + line-1183 TRAP comment (adding the 4th dep) | **PASS** |
| Gate 3 | Fetch card comments | **PASS** — #125 done, 0 comments |
| **1** | Ownership fix | **PASS** — non-recursive chown of 3 parents + leaf |
| **2** | Fail-loud ownership assertion | **PASS** — exit 90, named; logic-tested |
| **3** | Stop swallowing the install rc | **PASS** — unit-existence gate + throw; `/status` poll preserved; logic-tested |
| **4** | Honest INSTALLER_EXIT | **PASS** — marker-based; documented assertion for the next cycle |
| 5.1 | Real log path | **PASS** — `C:\ProgramData\ClawFactory\install.log` |
| 5.2 | `enable-linger \|\| true` fail-loud | **SKIPPED → carded** (no validation this session; a benign linger failure aborting the install is an unvalidated behavior change — deferred, not risked) |
| 6.1 | Version + commit + tag | **PASS** — `MyAppVersion 1.0.39`; commit `78e2e2a`; tag `v1.0.39` → `78e2e2a` |
| 6.2 | Build (ISCC) | **PASS** — `Successful compile`; bundling guard intact (§3) |
| 6.3 | Sign | **PASS** — Valid, timestamped, `signtool verify /pa /v` = *Successfully verified* |
| 6.4 | Upload | **PASS** — byte-exact, 340587832 B |

---

## 3. Build / sign / stage evidence (verbatim)

```
ISCC: Successful compile (40.453 sec). Resulting Setup program filename is:
      ...\Output\ClawFactory-Secure-Setup.exe

bundling guard (v1.0.38) STILL PASSES -- all security resources compress in:
  Compressing: resources\safety-rules.md            resources\clawfactory-grants.ps1
  Compressing: resources\openclaw-shim.sh           resources\clawfactory-turn-gate.sh
  Compressing: resources\clawfactory-spend-check.js resources\install-turn-gate.sh
  Compressing: resources\freeze-injected-soul.sh    resources\clawfactory-proxy.js
  Compressing: resources\clawfactory-proxy.service  resources\install-chat-proxy.sh

stamped ProductVersion: 1.0.39
unsigned: 340572187 B  sha256 6bd747cf…6584dfa0

signing: Signing completed with status 'Succeeded' in 2.25s
Get-AuthenticodeSignature: Status=Valid  Signer=CN=Bret Mckinney  Timestamp=True
signtool verify /pa /v:
    Issued to: Bret Mckinney   (chained to Microsoft Identity Verification Root CA 2020)
    The signature is timestamped: Thu Jul 16 06:20:56 2026
    Successfully verified   |  warnings: 0

signed:  340587832 B  sha256 1b63dd0cf0ae9918cf0bdc0a7fad2aee7c45d5a90db58fc73013158b9eb0ae2c
blob:    installers/ClawFactory-Secure-Setup-v1.0.39.exe
         blob sha256 == local sha256, blob length 340587832  ->  BYTE-EXACT: True
```

---

## 4. SURPRISES

1. **`MyAppVersion` had silently drifted.** The `.iss` internal version was still `1.0.37`
   through the entire `v1.0.38` tag — the release version is applied only as the blob-name
   suffix at upload, so the internal version (Add/Remove Programs) had been lying for two
   releases. Bumped to `1.0.39` so it is honest again; pre-existing drift noted so it is
   not re-introduced.
2. **setup.ps1 was already honest; Inno is the liar.** Task 4 started as "make the
   installer exit honestly," but setup.ps1 already exits 1 and writes the marker — the
   false 0 is entirely Inno's `[Run]` swallowing the child code. So the fix is consumer-
   side (assert the marker), not a setup.ps1 change. Documented what the validation asserts.
3. **The transient-case carve-out matters.** A naive "throw on any non-zero install rc"
   would have broken the documented case where the install writes the unit but the service
   start hiccups. Gating on *unit-file existence* (not rc) is what lets Task 3 fail loud on
   the real bug while preserving the tolerance Task 3.2 requires.

---

## 5. END-OF-SESSION GATE

**Task accounting:** §2. Tasks 1-4 (load-bearing) **PASS**; 5.1 PASS; 5.2 carded; 6.1-6.4
PASS. No Azure, no VM, no suite (out of scope).

**Resource ledger:** no VM created — $0 compute. One blob added
(`installers/ClawFactory-Secure-Setup-v1.0.39.exe`, 340587832 B). RG otherwise unchanged
(storage + vnet + 2 images). A temp verify-download was created in `%TEMP%` and deleted.
No scratch files left in the repo (`bash -n`/mock tests live in the session scratchpad,
outside the tree).

**Delta security sweep.**
- **No permission widened beyond clawuser owning its OWN `.config` subtree.** The chown is
  non-recursive, targets exactly four directories under `/home/clawuser`, and sets them to
  the user who already owns that home. Nothing group/other-writable; no setuid; no world
  access. It replaces an *accidental* Docker side effect with an *explicit, asserted* step.
- **No Docker reintroduced** — verified: `setup.ps1` still has no `dockerd`/`docker-ce`/
  rootless references (only the removal-explaining comments).
- **No new egress** — the AUX_HOSTS allowlist, nft table, and firewall logic are untouched;
  the fix adds no hosts and opens no ports.
- **Fail-loud is stricter, not looser** — the ownership guard and the install-rc throw
  make the installer *refuse* to proceed on a broken gateway state it previously limped
  past. The honest-marker change makes a failed install *report* failure it previously hid.
- No key/token/password/SAS in this report or in any commit. Signing SP secrets live only
  in `.env` (gitignored) and were never printed.
- Bret's daily driver: **untouched** — this session only edited files, ran ISCC/signtool
  locally, and used `bash -n` in local Git Bash. No WSL distro state changed.

**Delta bug review — introduced / found:**
1. **No new bug introduced** — the three edits are additive guards + an ownership
   correction; the logic paths were exercised (bash `-n` + mocked control-flow) and the
   full ISCC build succeeded with the bundling guard intact.
2. **Carried forward (unchanged):** the two `enable-linger || true` calls (5.2, carded);
   the fact that a mid-install Windows reboot would leave the honest marker unwritten on
   the first `wrapper.cmd` pass (pre-existing harness edge; the gateway bug fails without a
   reboot so it does not bite here — noted for the validation cycle).
3. **Still owed:** the clean-machine validation of this fix, and the headline isolation
   claim, both remain **unproven** — that is the next job, by design.

**Card #125 → done.** Next: one Azure validation cycle on `v1.0.39` asserting
`INSTALLER_DONE=success`, the gateway unit present, and `/status`=200 — then the isolation
suite.

---

## 6. Commits

```
78e2e2a  fix(gateway): own the .config/systemd/user chain + assert it + fail loud (v1.0.39)
         (setup.ps1 Tasks 1-3, .iss version, azure-validate.ps1 Task 4, probe path, L9)
tag v1.0.39 -> 78e2e2a
<this>   chore(release): stage v1.0.39 signed artifact + close-out
         (azure-validate.ps1 default Blob/sha256 -> v1.0.39; this report)
```
