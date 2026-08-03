# v1 Guard 2 BUILD: approval-gated send (Tier A), close-out

**Date:** 2026-08-02
**Dispatch card:** #193
**Track:** v1 fast-security-harness. Not the v2 split-authority architecture.
**Spec:** `CC_v1_Guard2_Build_Approval_Gated_Send_v3.md` plus Addendum A, Addendum B,
and the 2026-08-02 RESUME instruction.
**Status:** IN PROGRESS. This file is written incrementally so that an interruption
leaves reviewable work rather than an empty tree.

---

## 1. Resumed-session state verification (R.0, R.1, R.2)

A prior session on this box completed Task 0, answered the comprehension gate, and
created card #193. It stopped before the section 4 simulation and before any build
code. That report was treated as a claim and re-established by execution.

### 1.1 Repository state (R.0.1, R.0.2)

Verbatim:

```
=== SECURE-SETUP ===
dc3450a fix(egress): take Google's API hosts off the agent allowlist, and make setup.ps1 diffable
2b59e85 fix(guard1): store ceiling, restore integrity check, non-blocking index lock
3fd1d69 docs(guard1): quarantine-delete close-out -- recon table, evidence, honest claim
2c3b178 feat(guard1): agent deletes go to a root-owned quarantine, recoverable for 30 days
--- status ---
(end)

=== STUDIO ===
6105c53 feat(quarantine): Recently deleted panel -- list and restore what the agent deleted
--- status ---
(end)
```

Both trees clean. No uncommitted files, no untracked files, nothing deleted.
Matches expectation: Secure-Setup at `dc3450a`, Studio at `6105c53`.

### 1.2 Interrupted-state hazard sweep (R.1). Result: CLEAN, nothing to tear down.

The specific hazard is a half-built broker: a listening send socket with no working
approval path, a credential file with the wrong mode, or a staging directory with no
garbage collector. None of those exist.

```
-- send-credential.json?
ls: cannot access '/etc/clawfactory/send-credential.json': No such file or directory
-- any file matching *send* under /etc/clawfactory /usr/local/sbin /usr/local/lib?
   (no lines above = none)
-- any staging dir?
ls: cannot access '/var/lib/clawfactory/send-staging': No such file or directory
-- any smtp/send unit file on disk?
   (no lines above = none)
```

Every clawfactory unit present, and the only listening socket:

```
clawfactory-allow-providers.service   loaded inactive dead    refresh LLM provider IPs in nft allowlist
clawfactory-fw.service                loaded inactive dead    egress firewall (nftables or iptables-legacy fallback)
clawfactory-proxy.service             loaded active   running chatCompletions gating proxy on 127.0.0.1:8787
clawfactory-quarantine-gc.service     loaded inactive dead    quarantine retention cleanup
clawfactory-quarantine.service        loaded active   running delete quarantine broker
clawfactory-allow-providers.timer     loaded active   waiting refresh LLM provider IPs every 5h
clawfactory-quarantine-gc.timer       loaded active   waiting quarantine retention cleanup (daily)

u_str LISTEN 0 511 /run/clawfactory/quarantine.sock 17422 * 0
```

Resource ledger entry: **nothing was found and nothing was removed.** The box entered
this session in the same state it entered the prior one.

### 1.3 Incidental restart evidence

The distro restarted between the two sessions: `quarantine.sock` is stamped
`Aug 2 07:12` against `Aug 1 07:02` previously, `dns-resolvers.txt` is stamped
`Aug 2 07:12`, and the nft drop counter had reset to 786 packets. The firewall table,
both timers, the gating proxy and the quarantine broker all returned without
intervention. This is unforced partial evidence for section 5 test 14 and is recorded
as observed rather than as a substitute for running that test deliberately.

### 1.4 Five cheap re-confirmations (R.2)

| Check | Result |
| --- | --- |
| `clawuser` is uid 1000, `inet clawfactory` active | `1000`; `table inet clawfactory` present |
| `chain output` accept line still 443 only | `ip daddr @allowed_ipv4 tcp dport 443 accept` |
| quarantine socket mode and service | `srw-rw---- 1 root clawuser`, `active` |
| interop closed | `[interop] enabled=false`, `appendWindowsPath=false` |
| dispatch client resolves | yes; card #193 read read-only, `in_progress`, 0 comments |

Full `chain output` as measured this session:

```
type filter hook output priority filter; policy accept;
meta skuid != 1000 return
ip daddr 127.0.0.1 tcp dport 8788 drop
ip6 daddr ::1 tcp dport 8788 drop
oifname "lo" accept
ip daddr @dns_resolvers udp dport 53 accept
ip daddr @dns_resolvers tcp dport 53 accept
ct state established,related accept
ip daddr @allowed_ipv4 tcp dport 443 accept
ip daddr 127.0.0.1 tcp dport 11434 accept
counter packets 786 bytes 47044 drop
```

---

## 2. Comprehension gate (v3 section 2, re-answered per R.3)

**1. Why uid 1000 makes an in-gateway email channel permanently forbidden.**
The agent and the gateway are a single security principal at uid 1000, which is the
same structural fact behind the Door-2 full-path `.mjs` bypass. An in-gateway email
channel would hand the send capability to the agent itself, degrading approval from a
boundary into a code path the agent can route around. It is forbidden rather than
deferred because no gate built at that location can ever be structural.

**2. The attachment time-of-check to time-of-use hole.**
Approval binds a hash computed at request time, but an attachment carried by path is
re-read at execution time, and the agent owns that file in the interval. Hashing at
request time describes the bytes that were shown, not the bytes that will be read, so
it cannot close a window the attacker controls. Copying every attachment into
root-owned staging at request time and sending the staged copies is what makes the
approved bytes and the transmitted bytes the same bytes rather than the same name.

**3. Why a root broker holding an SMTP credential is not an escalation.**
Holding a credential in a root process is an escalation only if a lower-privileged
caller can use it to do something it could not otherwise do. The concrete risk is file
read: the broker becoming a root-read primitive that mails out a root-only file on the
agent's behalf. Guard 1's mechanism prevents it, namely re-deriving entitlement by
dropping to the caller's uid with `setpriv` and confirming the caller could itself have
read each attachment, refusing otherwise. The credential itself is mode 600 root:root
and is never returned to any caller or renderer.

**4. The two independent conditions, and which one this job endangers.**
(a) No route: uid 1000 has no network path to any SMTP port, enforced by the nft chain.
(b) No capability: the agent holds no credential and no send code path, the only sender
being root-owned and approval-gated. This job creates (b) from nothing, so (b) is the
condition at risk. If the broker socket executes rather than merely enqueues, or if the
approval path is reachable from clawuser, (b) collapses and only (a) remains, which
protects nothing once a root process is willing to send on the agent's behalf.

**5. Why a validated firewall rule can be gone four hours later.**
The refresh timer re-resolves allowlisted hostnames and rewrites the nft set roughly
every five hours, so any rule written directly to the running ruleset outside that path
is erased at the next refresh, silently, on a customer machine, long after validation
went green. Guard 2's egress work therefore has to live in the persistent path rather
than beside it.

**6. "Email cannot leave without approval" versus "data cannot leave without approval."**
The first is true of this product once Guard 2 lands, because SMTP is the only email
path, it is root-owned, and approval is the only way to reach it. The second is false
and cannot be made true in v1: the gateway runs as uid 1000, holds the provider
credential, and makes its own outbound 443 call, so any file the agent can read can
leave the machine to the model provider authenticated with the user's own key. Guard 2
gates email. It does not gate egress. No sentence in this document or in customer copy
may claim otherwise.

---

## 3. Section 4 simulation, written before any build code

This is the predicted behaviour. Section 5 records what actually happened, and section
5.1 compares the two. Any divergence is reported, not quietly reconciled.

### 3.0 Components the simulation assumes

| Component | Path | Owner and mode |
| --- | --- | --- |
| Send broker daemon | `/usr/local/lib/clawfactory/clawfactory-sendd.js` | root:root 0755 |
| Broker socket | `/run/clawfactory/send.sock` | `srw-rw---- root:clawuser` |
| Agent-facing client | `/usr/local/bin/clawfactory-send` | root:root 0755 |
| Root-only control tool | `/usr/local/sbin/clawfactory-sendctl` | root:root 0750 |
| Credential | `/etc/clawfactory/send-credential.json` | root:root 0600 |
| Egress policy | `/etc/clawfactory/egress-policy.json` | root:root 0644 |
| Staging root | `/var/lib/clawfactory/send-staging/` | root:root 0700 |
| Receipts | `/var/lib/clawfactory/send-receipts/` | root:root 0700 |
| Pending queue | `/var/lib/clawfactory/send-pending/` | root:root 0700 |
| GC timer | `clawfactory-send-gc.timer` | root |

Two channels, deliberately disjoint:

- **Request channel.** clawuser to root over `/run/clawfactory/send.sock`. Can enqueue
  and can query status. Cannot approve. This is the only channel the agent can reach.
- **Approval channel.** Studio to root over `wsl -u root` running
  `clawfactory-sendctl`. Never traverses the socket, never runs as uid 1000. clawuser
  has no path to it: `/usr/local/sbin` is 0755 but the binary is 0750 root:root, and
  the control tool additionally refuses to run when `getuid() != 0`.

### 3.1 Canonical payload hash, defined explicitly so it is reproducible

Ordering and encoding are fixed. The hash is SHA-256 over the UTF-8 encoding of the
following sections joined by a single `0x1E` record separator:

1. Literal version tag `cfsend-v1`.
2. Destination, lowercased, as `host:port`.
3. Recipients: each trimmed and lowercased, de-duplicated, sorted bytewise ascending,
   joined with `0x1F`. To, Cc and Bcc are all covered and are tagged with their field
   name so that moving an address between fields changes the hash.
4. Subject, Unicode NFC normalized, leading and trailing whitespace trimmed.
5. Body: the lowercase hex SHA-256 of the raw body bytes, not the body itself.
6. Attachments: for each, `basename`, decimal byte `size`, and lowercase hex SHA-256 of
   the **staged copy**, joined with `0x1F`; entries sorted bytewise ascending by the
   resulting triple string, then joined with `0x1F`.

Rationale for hashing the body rather than including it: the hash record is written to
receipts, and receipts are content-minimized. Rationale for sorting: a reordering of
recipients or attachments must not void an approval, but any change of membership,
name, size or content must.

### 3.2 Happy path, step by step, with the expected observable

| # | Step | Expected observable |
| --- | --- | --- |
| 1 | Agent runs `clawfactory-send --to a@example.com --subject S --body-file B --attach F` | Client connects to `/run/clawfactory/send.sock`. Exit code 0, stdout carries `status=pending` and a `requestId`. |
| 2 | Broker reads `SO_PEERCRED` on the connection | Peer uid recorded as 1000. Request rejected outright if peer uid is 0, so a root caller cannot launder a request through the agent channel. |
| 3 | Broker resolves destination against `egress-policy.json` | Destination present in the `send_actions` section. A destination outside it is refused here, before staging, and logged locally. |
| 4 | Broker re-derives entitlement per attachment | For each path, `setpriv --reuid=1000 --regid=1000 --clear-groups test -r <path>` must succeed. `/etc/shadow` fails and the whole request is refused before any staging occurs. |
| 5 | Broker stages attachments | `/var/lib/clawfactory/send-staging/<requestId>/` created 0700 root:root, each attachment copied in, staged copy hashed. Cumulative staging size checked against the cap; over-cap refuses loudly and stages nothing partial. |
| 6 | Broker computes the canonical hash and writes the pending record | `send-pending/<requestId>.json` written with hash, recipients, subject, attachment table, destination, `createdAt`, `expiresAt` = created + 10 minutes. |
| 7 | Broker replies | `{status: "pending", requestId, payloadHash}`. **Nothing has left the machine.** No SMTP connection has been opened. |
| 8 | Studio lists pending | Studio calls `clawfactory-sendctl list` through the root channel and renders the approval card: every recipient, the subject, the full body or an exact expandable preview, every attachment with name, size and staged hash, and the destination host. Never the model's summary. |
| 9 | User clicks approve | Studio calls `clawfactory-sendctl approve <requestId> <payloadHash>`. |
| 10 | Broker validates the approval | Record exists, not expired, not already used, and the supplied hash equals the stored hash recomputed from the staged copies. |
| 11 | Broker executes the send | Opens SMTP to the policy destination as root, authenticates with the credential, sends the staged bytes. Root is unfiltered by `meta skuid != 1000 return`, so this succeeds while the same connection from uid 1000 would be dropped. |
| 12 | Broker writes the receipt, then finishes | `send-receipts/<requestId>.json`: request id, timestamp, payload hash, recipients, approval state and the hash it was bound to, result, provider reference (SMTP server response id). No body, no credential. If the receipt cannot be written, the send does not execute. |
| 13 | Staging purged | `send-staging/<requestId>/` removed. Pending record marked consumed. |
| 14 | Agent polls status | `clawfactory-send status <requestId>` returns `sent` plus the provider reference. The agent never sees the credential. |

Ordering note for step 12: the receipt is written before the SMTP `DATA` is committed
where the protocol allows, and otherwise a pre-send intent record is written first and
amended with the result. The rule "a send that cannot write its receipt does not
execute" is enforced by writing and `fsync`ing the intent record before opening the
SMTP connection, not by writing the receipt afterwards and hoping.

### 3.3 Failure path 1: broker down

| Step | Expected observable |
| --- | --- |
| Agent runs `clawfactory-send ...` with `clawfactory-send.service` stopped | `connect()` to the socket fails with `ENOENT` or `ECONNREFUSED`. |
| Client behaviour | Exit code non-zero, stderr states the broker is unreachable in plain language. |
| Draft preservation | The client writes the composed draft to `~/.clawfactory/drafts/<timestamp>.json` under clawuser so nothing the user dictated is lost. |
| Fall-through | None. The client contains no SMTP code, no credential, and no network path. There is nothing to fall through to. |
| Net effect | Deny, loud, draft preserved. |

### 3.4 Failure path 2: approval denied

| Step | Expected observable |
| --- | --- |
| Request reaches pending as in 3.2 steps 1 to 7 | `status=pending`. |
| User clicks deny in Studio | `clawfactory-sendctl deny <requestId>`. |
| Broker | Marks the record denied. Opens no SMTP connection. |
| Receipt | Written with `result: "denied"` and the payload hash it was bound to. |
| Staging | `send-staging/<requestId>/` purged immediately, not left for the GC timer. |
| Agent status poll | `denied`. No reason string is fabricated. |

### 3.5 Failure path 3: payload mutated after approval

This is the case where the *request record* is tampered with rather than the file.

| Step | Expected observable |
| --- | --- |
| Request pending with hash H | `payloadHash=H`. |
| Agent attempts to alter the pending record, for example by re-issuing with the same id and a new body | The pending directory is 0700 root:root, so clawuser cannot write it at all. The re-issue arrives as a **new** request with a new id and a new hash, and it is pending, not approved. |
| Approval replay: agent supplies H for the mutated request | Rejected. The stored hash for the new id is not H, and approval does not traverse the agent channel in any case. |
| If a hash mismatch is detected at execution | Approval invalidated, send refused, a new preview required. |
| Net effect | Approval binds to exactly one payload and one request id, single use. |

### 3.6 Failure path 4: attachment rewritten after approval. The staging test.

This is the most important failure path in the job.

| Step | Expected observable |
| --- | --- |
| Agent requests a send with attachment `F` containing bytes A | Staged copy holds A. Attachment hash in the approval card is `sha256(A)`. |
| User approves | Approval bound to a hash computed over the staged copy of A. |
| Agent rewrites `F` on disk to bytes B before execution | The on-disk file now differs from the staged copy. No error is raised at this point, because the broker never re-reads `F`. |
| Broker executes | Reads `/var/lib/clawfactory/send-staging/<requestId>/F`, which still contains A. clawuser cannot modify it: the staging tree is 0700 root:root. |
| What arrives at the destination | Bytes A, the bytes the user approved. |
| Receipt | Records `sha256(A)`. |
| Verification method | The received message is extracted and hashed, and that hash is compared against both `sha256(A)` and `sha256(B)`. The test passes only if it equals `sha256(A)` and differs from `sha256(B)`. Both comparisons are reported. |

If instead the attachment were carried by path, the expected observable would be bytes
B arriving, which is precisely the defect staging exists to remove.

### 3.7 Failure path 5: expiry

| Step | Expected observable |
| --- | --- |
| Request pending, `expiresAt` = created + 10 minutes, config-driven | Card shows a countdown. |
| Wait past the window | The GC timer marks the record expired and purges its staging. |
| Attempt approval after expiry | `clawfactory-sendctl approve` refuses with `expired`. No SMTP connection opened. |
| Race: approval arriving in the same second as expiry | The broker re-checks `now < expiresAt` under the record lock immediately before opening the connection, so the ambiguous case denies. |
| Receipt | Written with `result: "expired"`. |

### 3.8 What the simulation asserts that validation must actually prove

1. Nothing leaves the machine at request time (3.2 step 7).
2. The approval card content comes from the broker record, not from the agent (3.2 step 8).
3. clawuser has no channel to approve (section 3.0, proven by test 8).
4. Staged bytes, not on-disk bytes, are what get sent (3.6).
5. The uid-1000 SMTP block survives a refresh run (tests 9 and 9a).
6. The credential never appears in any log, receipt, error or process listing (test 13).

---

## 4. Build

TO BE COMPLETED. No build code has been written at the time of this revision.

Blocked item recorded honestly: **Addendum B was not available to this session.** It is
not present on disk and was not supplied in full. Only three fragments are known, quoted
in the RESUME instruction: B.1 (file-based verifier channel, paired failing controls,
lessons-learned entry), B.2 (the refuted A.4 concern), and B.4 (do not add
element-manipulation logic to `clawfactory-allow-providers.sh`). B.4 reverses Addendum A
section A.2's instruction without supplying its replacement, and at least one further
section, B.3, is entirely unknown. Section 3.4 of the build, the egress policy file and
firewall assertion, is therefore held rather than guessed at.

---

## 5. Validation

TO BE COMPLETED.

---

## 6. End-of-session gate

TO BE COMPLETED.
