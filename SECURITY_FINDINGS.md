# ClawFactory Security Findings

*Last updated: 2026-07-18. Applies to ClawFactory Secure Setup v1.0.45.*

ClawFactory exists because AI agents need real access to be useful, and real access is what makes them risky. Our answer is to enforce boundaries at the operating-system level rather than by asking the agent to behave. This document states what that buys you, what it does not, and how we know.

We publish our residual findings because a security product that only lists its strengths is asking for trust it hasn't earned. Everything below was validated on clean machines, and where a boundary is weaker than it looks, we say so.

---

## How we test

Every claim in the "structural" table below was proven **consumer-side**: by asking the agent itself to cross the boundary and recording its actual output, on a freshly installed machine. We do not accept a configuration file or a mount table as evidence that a control works, because a misconfigured control and a working control look identical from the config side.

Validation runs on clean cloud VMs built from a stock Windows image, installed exactly as a customer would install. The current release passed the install gate on seven consecutive clean machines.

A note on method: refusals only count as evidence if the agent is otherwise working. In the same validation run that produced the refusals below, the agent successfully read and quoted a file the user *had* granted, made live network requests, and executed normal work. The boundaries are discriminating, not the symptom of a broken agent.

---

## Two classes of guarantee

Not every control in ClawFactory is equally strong, and treating them as one undifferentiated "security" claim would be dishonest. They fall into two classes, and the difference matters.

### Structural guarantees

Enforced by the operating system, the filesystem, or the network stack. They hold regardless of what the agent does, what model is behind it, or how the agent process was started. **A hostile agent cannot route around these.**

| Guarantee | Mechanism | Status |
|---|---|---|
| **File isolation** — the agent cannot read files you did not grant it | WSL2 sandbox with Windows automount disabled; explicit per-folder grants mapped into the sandbox | **Proven.** The agent refused to read an ungranted file by direct path, by directory listing, through a symlink, through `../../..` traversal, and via filesystem-wide search. It could not read `/etc/shadow`. The target file's contents never appeared in any output. |
| **Egress allowlist** — the agent cannot reach arbitrary internet destinations | nftables rules scoped to the agent's system identity | **Proven.** Non-allowlisted hosts, raw IP addresses, non-standard ports, and arbitrary DNS resolvers are all blocked. |
| **Inbound deny** — nothing on your network can reach the agent | Loopback-only gateway | **Proven.** No listening surface is exposed off the machine. |
| **Credential protection** — your API key is never left in readable config or on a command line | Windows Credential Manager (DPAPI) on the Windows side; inside the sandbox the key exists only in a mode-600 file — never on a command line, in an environment variable, or in `.env` | **Proven** for the storage path (Credential Manager + mode-600 file; nothing on a command line or in `.env`). *Nuance:* the sandbox copy is permission-scoped, not encrypted at rest, and the agent is provisioned its own key by design — the egress allowlist above is what bounds where a held key could be sent. |
| **Safety-rules integrity** — the agent's rules file cannot be altered by the agent | Root-owned, read-only, immutable flag, hash-pinned at install | **Proven.** The agent cannot write, change permissions on, or delete-and-recreate the file. |
| **Kill switch** — you can stop everything immediately | Terminates the real agent process | **Proven.** |

### Gateway-path guarantees

Enforced on the network path through the local gateway. They hold against anything arriving over that path, including everything the ClawChat interface sends. They are **advisory** against an agent that already has shell access on the machine and chooses to start the runtime by another route. See the residual below.

| Guarantee | Mechanism | Status |
|---|---|---|
| **Spend cap** | Turn-gate reads the spend meter before each turn; fails closed if the meter is unreadable | **Proven on the gateway path.** A turn at cap zero is blocked with a readable message and consumes zero model tokens. |
| **Chat gating** | Root-owned proxy fronts the private gateway port | **Proven on the gateway path.** The agent's own identity cannot reach the real gateway directly; it must traverse the proxy. |
| **Safety-rules enforcement** | Turns refuse to run when the rules file does not match its pinned value | **Proven on the gateway path.** A tampered rules file blocks turns with a readable message and zero model tokens. |

---

## Known residual: same-identity runtime invocation

**The finding.** The agent process and the local gateway run under the same system identity inside the sandbox. A process running as that identity — including the agent itself — can start the model runtime directly by its full path, producing a turn that never crosses the gateway and is therefore not subject to the spend cap, chat gating, or safety-rules check.

**Actor model.** This requires the ability to execute a shell command as the agent's identity inside the sandbox. It is not reachable from the network, and it is not a defect in file isolation. The realistic actor is the agent itself, acting on instructions from content it processes. Because our design principle is to assume the model may be hostile, we treat that actor as in scope rather than hypothetical.

**What it does and does not affect.** Every structural guarantee in the first table continues to hold against a turn started this way. Such a turn still cannot read ungranted files, still cannot reach non-allowlisted destinations, still cannot alter the safety-rules file, and is still stopped by the kill switch. What it can do is run without spend accounting and without the gateway-side safety check, using the API key you already provisioned. **The exposure is cost and unmetered operation, not data access.**

**Why we have not patched it.** The controls that could distinguish these processes — file permissions, network rules, sandboxing policy — all key on identity, and the two processes share one. Any mitigation short of giving the agent its own identity can be routed around by that same identity, while creating the false impression that the boundary moved. We would rather state the boundary accurately than ship a control that looks like a fix and is not.

**How it will be closed.** Separate-identity isolation — running the agent under a dedicated identity or container, so it cannot invoke the gateway's runtime or hold what the gateway holds — is committed to the next major version, and tracked as item #25 in our forward-looking backlog ([`v1.1_backlog.md`](v1.1_backlog.md)). The pattern is already proven in this release: the chat gating proxy runs under a different identity than the agent, and that boundary holds.

---

## Other known limitations

**DNS is restricted, not eliminated.** Outbound DNS is constrained to the configured resolver rather than blocked outright. Queries to that resolver are expected behavior, not a leak, but the metadata channel is narrowed rather than closed.

---

## Summary

If your concern is that an AI agent will read files you didn't give it, reach places it shouldn't, expose a door to your network, or quietly rewrite its own safety rules, those boundaries are structural and proven on clean machines.

If your concern is guaranteeing that a compromised agent cannot spend your API budget or run unmetered, that boundary is real against the network path and advisory against a hostile agent with shell access, and it will be structural in the next major version.

We would rather you know exactly which is which.
