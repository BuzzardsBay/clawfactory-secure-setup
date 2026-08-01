# v1 Guard 1 — Quarantine-Delete — Close-out

**Date:** 2026-08-01 (prompt dated 2026-07-28)
**Dispatch card:** #189
**Commits:** `2c3b178` (ClawFactory-Secure-Setup, agent-side) · `6105c53` (ClawFactory-Studio, UI)
**Track:** v1 fast-security-harness. NOT the v2 split-authority architecture.

---

## 1. Task 0 recon table

Verified against the live dev-box install (WSL distro `Ubuntu`, OpenClaw
2026.4.27 `cbc2ba0`) and repo source before any build.

| # | Assumption | Actual | Changed the design? |
|---|---|---|---|
| 1 | The agent has a delete tool that can be removed from its toolset | **There is no delete tool.** `group:fs` = `read` / `write` / `edit` / `apply_patch` (`docs/tools/index.md`, `docs/gateway/config-tools.md`). Deletion is only reachable through the generic `exec` (shell) tool, which `setup.ps1:2160` deliberately retains: *"the agent needs shell to do any file/code work… denying it would break the product."* Tool policy lives at Step 9a (`tools.deny=["browser"]`). | **YES — routing stays advisory; see §3** |
| 2 | Quarantine can live somewhere the agent can write but not destroy | Grants mount Windows folders into the **gateway's** mount namespace at `/workspaces/<slug>` with `uid=1000`; the agent has full unlink there. And POSIX write permission on *any* directory grants unlink, so a clawuser-writable store is also clawuser-purgeable. A genuinely agent-proof store needs a **root-brokered move + chown root**. | **YES — forced the Tier A/Tier B choice; Bret chose Tier B** |
| 3 | Some scheduler exists for retention | Yes, with direct precedent: `clawfactory-allow-providers.timer` (root systemd oneshot, `OnBootSec=30s` + `OnUnitActiveSec`, enabled, observed running). WSL distro boot ≈ logon, so `OnBootSec` supplies the catch-up. OpenClaw's own `cron` is gateway-bound **and agent-reachable** (`group:automation`) — the wrong owner for a permanent-delete job. | No |
| 4 | Studio can read agent-side state and trigger a restore | Yes, cleanly. Studio is Electron (`backend/` is a retired, untracked Express leftover). Bridge = `preload.ts` (contextBridge, six hardcoded channels, no generic invoke) → `grants-ipc.ts` → `grants-engine.ts` → `powershell.exe -EncodedCommand` dot-sourcing `clawfactory-grants.ps1` → `wsl -u root`. clawuser has no route to it. | No |

Two mechanisms examined during recon and **rejected** as the fix for #1:

- **`exec-policy security=allowlist`** — better than expected (it parses *every
  pipeline segment*, not just `argv[0]`, and rejects chaining unless all
  segments match). But a coding agent needs `bash`/`node`/`python` allowlisted,
  and `rm` returns through the interpreter. Current effective policy is
  `security=full, ask=off`.
- **A sudoers `NOPASSWD` entry** for the broker — would have directly
  contradicted SOUL's standing claim that *"clawuser has no sudo and no
  sudo-group membership."* Rejected; a unix-socket broker gives the same
  capability without weakening a published claim.

---

## 2. What was built

**Agent side** (`ClawFactory-Secure-Setup`, commit `2c3b178`)

| File | Role |
|---|---|
| `resources/quarantine-lib.js` | Shared store/index helpers (config, lock, atomic index write, sizing, symlink-safe copy, recursive chown). Root-only. |
| `resources/clawfactory-quarantined.js` | The **broker**. Unix socket, root. Validates, moves, chowns root, records. The permission gate lives here. |
| `resources/clawfactory-quarantinectl.js` | Root `list` / `restore` / `gc`. Called by Studio and by the timer. |
| `resources/clawfactory-quarantine-rm.js` | The `rm` the **agent** sees, installed on the front of the exec PATH. |
| `resources/install-quarantine.sh` | Fail-loud installer. Refuses to proceed without `setpriv`. |
| `clawfactory-quarantine{,.gc}.service`, `-gc.timer` | systemd units. |
| `setup.ps1` | `Step-InstallQuarantine` (before `Step-InstallChatProxy`, whose gateway restart picks up `pathPrepend`), plus the eight new files added to `Step-Preflight`'s required list. |
| `ClawFactory-Secure-Setup.iss` | All eight bundled. (The preflight list and the `.iss` are the two halves of the bug that once shipped an installer with zero security controls.) |
| `clawfactory-grants.ps1` | `Get-QuarantineItems`, `Restore-QuarantineItem`. No purge function, by design. |
| `safety-rules.md`, `orchestrator-prompt.md` | Deletion copy made consistent with the wrapper. |
| `uninstall.ps1` | Units + code + store removed, with a count of still-held files echoed first. |

**Store layout** — `/var/lib/clawfactory/quarantine/` (root:root 0700),
`index.json` + one `<entry-id>/<basename>` payload directory per held item.
Record fields: `id`, `originalPath`, `name`, `type`, `sizeBytes`, `sha256`
(files only; `null` for directories and symlinks rather than a faked digest),
`deletedAt`, `taskId`, `requestedBy`.

**Config** — `/etc/clawfactory/quarantine.json`, root-owned mode 444
(world-readable because the agent-side wrapper reads it for scope; root-owned so
the agent cannot widen or narrow its own scope). Defaults: `retentionDays: 30`,
`maxEntryBytes: 2 GiB`, `quarantineRoots: ["/workspaces"]`, `skipSegments:
["node_modules", ".git"]`.

**Studio** (`ClawFactory-Studio`, commit `6105c53`) — `quarantine-engine.ts`,
`quarantine-ipc.ts` (two channels), `preload.ts` (+2 calls), and
`pages/deleted/RecentlyDeletedPage.tsx` on a `/deleted` route. Matches the
Workspace panel's patterns exactly; no restyle.

### Design decisions worth carrying forward

- **Scope is `/workspaces` only.** That is precisely "the user's files". Agent
  scratch, `/tmp`, build temp, `node_modules` and `.git` pass through to the real
  `rm`, so no existing workflow changes and one `rm -rf node_modules` cannot fill
  the store. Narrower scope, honest claim, smaller blast radius.
- **Broker-down fails loud, never falls back.** Falling through to the real `rm`
  on an outage would turn every hiccup into a silent permanent delete of exactly
  the files the guard exists to protect. A failed delete is recoverable; a silent
  one is not. Out-of-scope deletes still work normally while the broker is down.
- **No purge API anywhere in the stack.** The retention timer is the only thing
  that permanently removes a held file. That is what lets the panel say
  "kept for 30 days" with no asterisk.
- **A 2 GiB cap, refusing loudly.** Without it one `rm -rf` of a huge tree fills
  `/var/lib` and takes the box down.

---

## 3. Structural vs advisory, as implemented

**STRUCTURAL — the hold.** A quarantined file is chowned `root:root` inside a
`root:root 0700` store. clawuser cannot list it, restore it, or purge it.
Verified: `ls` → `Permission denied` (exit 2), `rm -rf` → `Permission denied`
(exit 1), store intact.

**ADVISORY — the routing.** There is no delete tool to deny, so the wrapper is
placed at the front of the exec PATH via `tools.exec.pathPrepend`. This is
stronger than a shell alias — OpenClaw *rejects* agent-supplied `env.PATH`
overrides for host execution, so the agent cannot displace the wrapper from
inside a turn — but it is not structural. **These still bypass it:** `/bin/rm`,
`unlink`, `find -delete`, `fs.rmSync`, `os.remove`, and truncation via `>`.

**The honest claim is therefore:** *deletes the agent makes the ordinary way are
recoverable for 30 days; a determined agent can still destroy a file.* It is
**not** "the agent cannot permanently delete your files." Any customer-facing
copy must stay on the first sentence.

**The root broker is not a privilege escalation.** It runs as root only because
only root can chown a payload away from clawuser. Before every move it
re-derives POSIX unlink permission *as clawuser* (`setpriv` drops to the agent
uid and tests the parent directory; the sticky-bit ownership rule is checked
separately), and refuses anything the caller could not have deleted itself. It
also refuses mount points and anything inside its own store, and resolves the
parent through symlinks so a link cannot be used to reach out of the grant.
`install-quarantine.sh` refuses to install at all if `setpriv` is absent, because
without the permission gate the broker would be a hole.

---

## 4. Validation evidence (dev box — see §7 for what this is not)

All runs on the live dev box, WSL `Ubuntu`, agent account `clawuser` (uid 1000),
invoking the wrapper the way the exec tool does (`PATH` front).

### 4.1 The required round trip

```
$ rm /workspaces/devtest/report.txt          # as clawuser, wrapper on PATH
rm: '/workspaces/devtest/report.txt' moved to ClawFactory quarantine (restorable from Studio > Recently deleted)
exit=0

$ ls -la /workspaces/devtest/                # source gone
total 8
drwxr-xr-x 2 clawuser clawuser 4096 Aug  1 05:55 .

$ ls -laR /var/lib/clawfactory/quarantine/   # held, root-owned
drwx------ 3 root root 4096 Aug  1 05:55 .
drwx------ 2 root root 4096 Aug  1 05:55 2026-08-01T11-55-32-000Z-hujl9n
-rw------- 1 root root  355 Aug  1 05:55 index.json
/var/lib/clawfactory/quarantine/2026-08-01T11-55-32-000Z-hujl9n:
-rw-r--r-- 1 root root   20 Aug  1 05:55 report.txt

$ cat index.json
[ { "id": "2026-08-01T11-55-32-000Z-hujl9n",
    "originalPath": "/workspaces/devtest/report.txt",
    "name": "report.txt", "type": "file", "sizeBytes": 20,
    "sha256": "2a0b82aa82c433fb2bd8b8826a58da0905d5dcf0e3fdc9fcbb0607e01e6d0513",
    "deletedAt": "2026-08-01T11:55:32.012Z", "taskId": null,
    "requestedBy": "clawuser" } ]
```

**Store is agent-proof:**

```
$ runuser -u clawuser -- ls -la /var/lib/clawfactory/quarantine/
ls: cannot open directory '/var/lib/clawfactory/quarantine/': Permission denied
ls exit=2
$ runuser -u clawuser -- rm -rf /var/lib/clawfactory/quarantine
rm: cannot remove '/var/lib/clawfactory/quarantine': Permission denied
rm exit=1
STORE STILL PRESENT
```

**Studio lists it** — driving the *same compiled main-process functions* the
`quarantine:list` / `quarantine:restore` IPC handlers call:

```
LIST -> {"retentionDays":30,"count":2}
  item: 2026-08-01T12-03-56-442Z-dpdaxj | /workspaces/devtest/olddir | directory | 7 B | present= true | expires 2026-08-31T12:03:56.442Z
  item: 2026-08-01T12-03-56-425Z-df5uj7 | /workspaces/devtest/quarterly.txt | file | 25 B | present= true | expires 2026-08-31T12:03:56.425Z
```

**Restore returns it to the original path:**

```
RESTORE RESULT -> {"restoredTo":"/workspaces/devtest/olddir","renamed":false,"originalPath":"/workspaces/devtest/olddir"}
LIST AFTER -> {"count":1}
$ ls -laR /workspaces/devtest/olddir
-rw-r--r-- 1 clawuser clawuser 7 Aug  1 06:03 note.txt      # tree + ownership intact
```

**Restore-as-copy when the path is occupied — original untouched:**

```
{"ok":true,...,"restoredTo":"/workspaces/devtest/b (restored).txt","renamed":true}
== /workspaces/devtest/b (restored).txt
ORIGINAL
== /workspaces/devtest/b.txt
REPLACEMENT
```

**Retention cleanup removes an artificially-aged item, and only that item:**

```
aged: a.txt   (deletedAt backdated 31 days)
$ systemctl start clawfactory-quarantine-gc.service
node[2269]: {"ok":true,"retentionDays":30,"reaped":1,"orphansReaped":0,
             "entries":[{"id":"...-e5kfmb","originalPath":"/workspaces/devtest/proj"}]}
systemd[1]: Finished ClawFactory quarantine retention cleanup.
entries before=1 after=0        # payload directory gone from disk too

$ systemctl list-timers clawfactory-quarantine-gc.timer
NEXT                        LEFT     UNIT                            ACTIVATES
Sun 2026-08-02 05:56:43 MDT 23h left clawfactory-quarantine-gc.timer clawfactory-quarantine-gc.service
```

### 4.2 The real customer shape — an actual grant mount

Proven separately because the store is on ext4 and a grant is a 9p/drvfs mount,
so the move is genuinely cross-device (`rename(2)` → `EXDEV`) and takes the
copy+remove path. Broker and grant mount confirmed in the **same** mount
namespace (`broker ns: mnt:[4026532219]` = `init ns: mnt:[4026532219]`).

```
9p     C:\Users\bmcki\Documents\guard1-quarantine-test
grant fs dev=82        store fs dev=2096          # cross-device confirmed

$ rm /workspaces/guard1-quarantine-test-dceb256a/thesis.txt
rm: '...thesis.txt' moved to ClawFactory quarantine (restorable from Studio > Recently deleted)
exit=0
-- gone from the Windows folder --
total 4
drwxrwxrwx 1 clawuser clawuser 4096 Aug  1 06:02 .

held: sha256 5c475ce288cc32de88b6081717e29f6489c1427e18c70888c3019b20414c8f06

$ restore
{"ok":true,...,"restoredTo":"/workspaces/guard1-quarantine-test-dceb256a/thesis.txt","renamed":false}
-rwxrwxrwx 1 clawuser clawuser 23 Aug  1 06:01 thesis.txt
REAL-GRANT-CANARY-9kd3m                          # content intact, back in the Windows folder
```

### 4.3 Security tests — the broker is not a new capability

```
T2.1  root-owned file in a granted folder clawuser cannot write to
      $ cat  -> ROOT-OWNED-DO-NOT-TOUCH        (readable, so scope/existence pass)
      $ rm   -> rm: cannot remove '...': permission denied
                exit=1, file survives, 0 occurrences in the index

T2.2  symlink escape: /workspaces/devtest/escape -> /etc
      $ rm /workspaces/devtest/escape/hostname
      /bin/rm: cannot remove '...': Permission denied      # resolved to /etc/hostname
      exit=1, /etc/hostname intact, 0 occurrences in the index

T2.3  raw socket call as clawuser, bypassing the wrapper entirely
      /etc/hostname                    -> {"ok":true,"quarantined":false,"reason":"out-of-scope"}
      /workspaces/rootzone/root-secret -> {"ok":false,"code":"EACCES","error":"permission denied: ..."}
      ROOT-OWNED-DO-NOT-TOUCH                              # survives

T2.4  out-of-scope passthrough deletes for real, store does not grow
      $ rm /tmp/scratch-file.txt   exit=0   ls: No such file or directory   entries: 1

T3.6  broker down -> FAIL LOUD, no silent delete
      $ systemctl stop clawfactory-quarantine.service
      $ rm /workspaces/devtest/precious.txt
      rm: cannot remove '...': quarantine service unreachable: connect ENOENT ...
      exit=1
      MUST-SURVIVE-broker-down                             # file still there
      $ rm /tmp/scratch2.txt   exit=0                      # out-of-scope still works

T3.4  directory refused without -r, held with -r
      no-r exit=1  "is a directory"   -> still there
      with-r exit=0                   -> held tree, root:root

PS engine id-injection guard
      Restore-QuarantineItem -Id "x'; touch /tmp/pwned; echo '"
      -> "invalid quarantine id";  ls /tmp/pwned -> No such file or directory
```

### 4.4 Two defects found and fixed during the diff review

1. **Broken symlinks bypassed routing.** The wrapper used `fs.existsSync`, which
   follows the link and reports a dangling link as missing — so it went to the
   real `rm` and was permanently deleted. Fixed to `lstat`.
2. **`fs.cpSync` cannot copy a dangling symlink** even with `dereference:false`
   — it stats the source and throws `ENOENT`. Exposed by fixing (1): the delete
   then failed loud (good) but the user could no longer delete a broken link at
   all. Fixed with `copyPreservingLinks` (readlink + symlink for link leaves),
   applied on both the hold and the restore path, plus `lstat`-based occupancy
   checks in `freeName`.

Full suite re-run against the corrected code — 7/7 pass, including:

```
held: dangling symlink sha256=null
lrwxrwxrwx 1 root root 24 ... /var/lib/clawfactory/quarantine/.../dangling -> /workspaces/devtest/nope
restore -> lrwxrwxrwx 1 clawuser clawuser 24 ... dangling -> /workspaces/devtest/nope
```

---

## 5. End-of-session gate

### 5.1 Task accounting

| Task | Status |
|---|---|
| 0 — Recon & confirm | **DONE.** Table in §1; posted to card #189 before any build. |
| 1 — Quarantine wrapper | **DONE, with the STOP condition reported and adjudicated.** Raw delete *cannot* be removed from the toolset because there is no delete tool — deletion is `exec`. Reported at the checkpoint; Bret chose Tier B (root-brokered) with the honest framing. |
| 2 — Retention cleanup | **DONE.** 30 days confirmed as the default and implemented as configurable. |
| 3 — Studio surface | **DONE.** `/deleted` panel, matches the wired Workspace panel, no restyle. |
| 4 — Consistency | **DONE.** SOUL + orchestrator copy updated; §5.3 sweep below. |
| 5 — Validation | **DONE (dev box).** §4. Clean-box rides the assembled-build run. |

No silent drops.

### 5.2 Resource ledger

- **Cloud:** none. No VM was created; nothing is billing.
- **Local, left in place deliberately:** the quarantine broker + timer are
  installed and running on the dev box (`clawfactory-quarantine.service` active,
  `clawfactory-quarantine-gc.timer` enabled). They are **inert** —
  `tools.exec.pathPrepend` was deliberately *not* set on the dev box, confirmed
  post-run (`Config path not found: tools.exec.pathPrepend`), so the dev-box
  agent still uses the real `rm`. Left installed for Guard 2 / clean-box
  comparison. Remove with the block now in `uninstall.ps1` if unwanted.
- **Cleaned up:** all test files, `/workspaces/devtest`, `/workspaces/rootzone`,
  the temporary grant (`guard1-quarantine-test-dceb256a`, revoked; 0 active
  grants remain), `C:\Users\bmcki\Documents\guard1-quarantine-test`, and every
  quarantine store entry (`items: []`). `/workspaces` is empty in both namespaces.
- **Scratch:** test scripts under the session scratchpad only; nothing in the repo.

### 5.3 Delta security sweep

- **No structural control weakened.** Sandbox, nftables egress, DNS restriction,
  SOUL immutability/pinning, spend gate, chat proxy: untouched. The SOUL SHA-256
  is computed from `safety-rules.md` at install time
  (`Step-ApplySafetyRules`), so editing that file re-pins correctly — no
  hardcoded digest to drift.
- **New root service reviewed as a privilege boundary.** See §3. It refuses
  anything the caller could not have deleted itself, refuses mount points,
  refuses its own store, resolves parents through symlinks, and is gated by a
  `root:clawuser 0660` socket. `sudo` was explicitly *not* used, so SOUL's "no
  sudo" claim stays true.
- **Raw delete IS still exposed to the agent — stated loudly.** `exec` is
  retained by design; `/bin/rm`, `unlink`, `find -delete`, `fs.rmSync` and `>`
  truncation all bypass the wrapper. This is the gap between the honest claim and
  an overclaim, and it is the single most important line in this document.
- **No credential values in either diff.** Scanned; clean. (One incidental note:
  reading `exec-approvals.json` during recon surfaced a local socket token in
  tool output. It was not reproduced anywhere and appears in no commit or report.)

### 5.4 Delta bug review

Diff re-read end to end. Two real defects found and fixed in-session (§4.4).
Carded, not patched, as out of scope:

- **Overclaim in `orchestrator-prompt.md:40`** — "`browser` … enforced by the
  gateway". Already a known open item (internal/low, reword pending) from the
  v1.0.48 tool-policy work. It sits two lines from copy I edited; deliberately
  left alone rather than folded into a security-copy commit.
- **`quarantine-lib.js` uses `Atomics.wait` for lock backoff.** Correct on
  Node's main thread and only reached under contention (never hit in testing),
  but it blocks the event loop. If a future guard makes concurrent deletes
  common, move the broker to an async queue.

---

## 6. Recommendations for Guard 2 (approval-gated send)

1. **`openclaw approvals` / `exec-policy` is a real primitive and it is already
   installed.** `exec-approvals.json` exists with a live socket + token;
   `openclaw approvals allowlist add/remove` edits a per-agent binary-path glob
   allowlist; `exec-policy set --ask off|on-miss|always` and
   `--security deny|allowlist|full` set the gate. Current effective policy is
   `security=full, ask=off` — i.e. wide open and unattended. Guard 2 should
   start by reading `docs/tools/exec-approvals.md` in the installed package.
2. **`ask=on-miss` is probably the shape you want**, not `security=allowlist`.
   Allowlist mode requires enumerating every binary a coding agent needs and
   still leaks through interpreters. `ask` gates the *request* rather than the
   binary, which is what "approval-gated" actually means.
3. **The approval UI has to be a Windows-side surface, not a chat message.** The
   exec tool returns `status: "approval-pending"` with an id, and the Gateway
   emits `Exec finished` / `Exec denied` events. Studio's IPC bridge is the right
   home — same pattern this guard used, and clawuser has no route to it.
4. **Reuse this guard's shape wholesale.** Root broker + unix socket + `0660
   root:clawuser` + a "would the caller have been allowed to do this itself"
   check + fail-loud-never-fall-back. It worked, it validated cleanly, and it
   kept the root service from becoming an escalation.
5. **Decide the send-scope question the same way scope was decided here.**
   Narrow, explicit, config-driven, root-owned. "Only these hosts / only these
   channels" beats "everything, gated" for both honesty and blast radius.
6. **Guard 1's own follow-ups:** (a) clean-box validation on the assembled build
   — the one link proven by architecture rather than execution here is that the
   *gateway's* namespace equals init's (it is a `systemd --user` service, and the
   broker was confirmed in init's namespace); the gateway was not running on this
   dev box. (b) Consider surfacing quarantine state in the ClawChat path too —
   this guard only touches the `openclaw`/exec route.

---

## 7. Scope statement

This is **dev-box validation, not clean-box**. Everything in §4 ran on the
existing dev install, which is older than the current installer and did not have
the gateway running. `Step-InstallQuarantine` itself, `Step-Preflight`'s new
required-file assertion, the `.iss` bundling, and the `tools.exec.pathPrepend`
config write have **not** been exercised by a real installer run — the components
they install were staged and installed by hand via `install-quarantine.sh`, which
is the same script the step invokes. Clean-box validation rides the assembled-build
run (Step 6 of the guard sequence).
