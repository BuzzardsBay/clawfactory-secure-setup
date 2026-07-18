# Security Findings

*Last updated 2026-07-18. This document is published deliberately. ClawFactory's
pitch is security, so its residuals are published in the same voice as its
evidence — a vendor that states its boundaries plainly is easier to trust than
one that hides them.*

This document does two things:

1. It names, precisely, **what each control guarantees and against whom** — by
   splitting the controls into two classes that behave differently under a
   hostile agent.
2. It states the one **accepted residual** in v1 (Door-2), its actor model, and
   its committed v2 closure — so a security-literate reader cannot mistake the
   scope in either direction.

Nothing here weakens the product's provable claim. The headline — **file
isolation** — is structural, was proven from the agent's own output on seven
consecutive clean machines, and is unaffected by the residual below.

---

## Two classes of guarantee

Every control in ClawFactory falls into one of two classes. The distinction is
not marketing; it is a statement about **which attacker each control stops**.

- **Structural guarantee** — enforced by the OS/kernel on something the agent's
  own Linux identity (`clawuser`) cannot change from inside. It holds against
  **both** a network attacker **and** a hostile agent with shell access running
  as `clawuser`. Even an agent executing hostile instructions cannot route
  around it.
- **Gateway-path guarantee** — enforced on the network path **through** the
  local OpenClaw gateway (and the root-owned proxy in front of it). It holds
  against anything that goes through that path — this is **Door-1, closed and
  verified**. It is **advisory** against a hostile agent that starts the runtime
  by another route — this is **Door-2, open** (see below).

### Structural guarantees (hold against the network AND a hostile agent)

| Control | Implementation | Holds against |
|---|---|---|
| **File isolation** (headline) | WSL `automount=false`; Windows folders reach the agent only through explicit grants mounted under `/workspaces`. | Network + hostile agent. **Proven from the agent's own output** on 7 clean boxes: it refuses an ungranted canary via `/mnt/c`, directory listing, and symlink / `../../..` traversal; `/etc/shadow` denied. |
| **Egress allowlist** | nftables in the WSL kernel scoped to `meta skuid clawuser`; outbound HTTPS to an approved hostlist + your provider only, DNS to the WSL resolver only, everything else dropped. | Network + hostile agent. An ungated turn still cannot reach an arbitrary destination — the exfiltration surface is unchanged by Door-2. |
| **Inbound deny / loopback-only gateway** | Gateway binds `127.0.0.1` only; a Windows Firewall inbound-deny rule on TCP/8787 backs it up. | Network. Door-2 is a **local-only** concern; nothing here is reachable off-box. |
| **Credential storage at rest** | API key held in Windows Credential Manager (DPAPI, tied to your Windows user); inside WSL it is written only to `~/.openclaw/auth-profiles.json` at mode `600`. Never on a command line, never in `.env`, never in the WSL process environment. | Network + other local users. *Nuance:* the agent is **provisioned its own key by design** — it must have the key to call the provider — so this control protects the key at rest and in transit, not from the agent that legitimately holds it. The **egress allowlist** is what bounds where a held key could be sent. |
| **Safety-rules file integrity** | `SOUL.md` is written as root, owned `root:root`, mode `444`, and made immutable with `chattr +i`; a root-owned copy of its hash lives at `/etc/clawfactory/soul.sha256`, outside `clawuser`'s reach. | Network + hostile agent. `clawuser` cannot modify, `chmod`, or delete-and-recreate the file. *(This is file **integrity** — a structural guarantee. Whether that file is **enforced at turn time** is a gateway-path guarantee; see below.)* |
| **User kill switch** | Start Menu shortcut that stops the gateway and the agent processes, run by the Windows user out-of-band. | Hostile agent. The agent (`clawuser`) cannot stop the Windows user from pulling the plug. |

### Gateway-path guarantees (hold through the gateway; advisory against a hostile agent)

| Control | Implementation | Holds against | Advisory against |
|---|---|---|---|
| **Spend cap** | Turn gate reads the spend meter and blocks a turn once the cap is reached; fail-closed if the meter is unknown. | Any turn that crosses the gateway / proxy path (Door-1). Verified: a `cap=0` turn is blocked with a readable reason and **zero model tokens**. | A turn launched by full-path invocation that never crosses the gate (Door-2). |
| **chatCompletions gating** | A root-owned proxy owns `127.0.0.1:8787` and gates ClawChat's `/v1/chat/completions` path with the same turn gate; the real gateway is moved to private `127.0.0.1:8788`. Fail-closed: if the proxy is down, nothing answers on 8787. | ClawChat's HTTP path (Door-1, closed). | Full-path invocation (Door-2). |
| **Safety-rules enforcement at turn time** | The turn gate re-checks the live `SOUL.md` hash against the pinned value and refuses the turn on mismatch before the agent runs. | Any turn that crosses the gate (Door-1). Verified: a tampered SOUL blocks the turn with a readable reason and **zero model tokens**. | Full-path invocation (Door-2). |

---

## The accepted residual: Door-2

**In one sentence:** a process with local shell access under the agent's own
identity (`clawuser`) can invoke the OpenClaw runtime directly by full path,
producing a turn that never crosses the gateway and is therefore not subject to
the gateway-path controls (spend cap, chatCompletions gating, turn-time
safety-rules check) — while the **structural** boundaries (file isolation and
the egress allowlist) still apply to that process.

### Actor model — read this before judging the scope

- **Local only.** Exploitation requires code execution as `clawuser` on the
  machine. It is **not reachable from the network**: inbound is denied and the
  gateway is loopback-only. A remote attacker gains nothing here.
- **The realistic actor is the agent itself**, acting on hostile instructions
  (a prompt injection, a malicious skill). ClawFactory's standing principle is
  *assume the model is hostile*, which puts exactly this actor in scope — so we
  state the boundary rather than assume good behavior.
- **This is not a file-isolation break and not an egress break.** An ungated
  turn still cannot read your Windows files (`automount=false` holds) and still
  cannot reach a non-allowlisted destination (nftables holds). The residual is
  bounded to two things: (1) **spend** against the key you already provisioned
  to the agent — a cost exposure, capped by your provider, not a data exposure;
  and (2) **advisory** safety-rule enforcement — the model may do at turn time
  what the turn-gate would have refused. The harm ceiling is your own API bill
  plus a model that ignores a rule, **not** exfiltration of your data.

### Why v1 does not ship a partial mitigation

Every mechanism that could distinguish the agent from the gateway — nftables UID
scoping, file permissions, systemd sandboxing of the gateway unit — keys on
**identity**, and the agent and the gateway share one (`clawuser`). Any control
that keys on that shared identity can be routed around by that same identity,
while **falsely implying the boundary moved**. Restricting permissions on the
runtime entry point fails because `clawuser` owns it; removing the interpreter
from `PATH` fails because the agent runtime *is* the interpreter; wrappers and
aliases are rules the same identity can step around. Shipping any of them would
violate this document's own structural-vs-advisory line. The honest v1 action —
the one that actually adds security value — is to **state the boundary here**.

### The v2 closure

Door-2 is closed by **separate-identity isolation**: running the agent process
under a different identity from the gateway, so the runtime it can reach un-gated
holds nothing it can replay directly. The design seed already exists in this
release — the chatCompletions proxy runs **as root, a different identity, and
that boundary holds**. Whether the v2 form is a dedicated UID, a container, or a
user namespace is an open design question to be settled on v2's clock. See the
roadmap entry: [`v1.1_backlog.md` → "Door-2 closure: separate-identity agent
isolation"](v1.1_backlog.md).

---

## Evidence (validation record through 2026-07-17)

- **Installer GREEN on 7 consecutive clean Azure boxes** — `cfv-0717a` … `cfv-0717g`, all `INSTALLER_DONE=success`.
- **File isolation proven from the agent's own output** — the agent refuses an ungranted canary via `/mnt/c`, directory listing, and symlink / `../../..` traversal; `/etc/shadow` denied (`cfv-0717d`).
- **Positive control** — the agent reads *and quotes* a **granted** file from `/workspaces/<grant-id>` (`cfv-0717g`).
- **Both gateway-path block cases return a readable reason with zero model tokens** — spend `cap=0` (`spend_blocked`) and tampered SOUL (`soul_mismatch`) (`cfv-0717g`).
- **`SOUL.md` verified `root:root` mode `444`, immutable** (`lsattr` shows `+i`) post-install.
- **Gateway loopback-only** — real gateway on private `127.0.0.1:8788` behind the root proxy on `8787`; `clawuser` → gateway dropped by nftables (`000` on IPv4 and IPv6), proxy `200`.

**Confidence:** the items above are VERIFIED from the repo-confirmed validation
record. The harm-ceiling and regression-risk judgments in this document are
analytical reads of that record (INFERRED). Repo is truth: if any statement here
is later contradicted by the record, the record wins and this file is corrected.

---

## Reporting a vulnerability

See [`SECURITY.md`](SECURITY.md). Email **support@clawfactory.app**; please do
not open a public issue for security vulnerabilities.
