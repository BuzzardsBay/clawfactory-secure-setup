# ClawFactory Security Findings

*Last updated: 2026-08-23. Applies to ClawFactory Secure Setup v1.4.0, the free release.*

This document is for someone deciding whether to trust ClawFactory, not for someone who already has. It says what the product actually enforces, what it does not, and how we know the difference. Where a boundary is weaker than its name suggests, that is stated here rather than left for you to discover.

ClawFactory exists because AI agents need real access to be useful, and real access is what makes them risky. Our answer is to enforce boundaries at the operating-system level rather than by asking the agent to behave. Not every boundary manages that, and the ones that do not are listed below with the same prominence as the ones that do.

ClawFactory is free and open source under Apache-2.0. There is no licence check, no account, and the installer makes no network call to any ClawFactory-operated server at any point. Everything below can be verified against the source in this repository.

---

## How we test

Every claim in the structural table below was proven **consumer-side**: by asking the agent itself to cross the boundary and recording its actual output, on a freshly installed machine. We do not accept a configuration file or a mount table as evidence that a control works, because a misconfigured control and a working control look identical from the config side.

Validation runs on clean cloud VMs built from a stock Windows image, installed exactly as a customer would install.

Two rules the harness enforces mechanically, because both were learned by getting a result wrong:

- **Every block assertion carries a positive control that must succeed in the same run.** A refusal only counts as evidence if the agent is otherwise working. In the same runs that produced the refusals below, the agent read and quoted a file the user *had* granted, made live network requests, and executed normal work.
- **A control that did not fire voids the phase.** A missing precondition is recorded as VOID with a named reason, never as a product verdict.

---

## Two classes of guarantee

Not every control here is equally strong, and presenting them as one undifferentiated "security" claim would be dishonest. They fall into two classes.

### Structural guarantees

Enforced by the operating system, the filesystem, or the network stack. They hold regardless of what the agent does, what model is behind it, or how the agent process was started. **A hostile agent cannot route around these.**

| Guarantee | Mechanism | Status |
|---|---|---|
| **File isolation**, meaning the agent cannot read files you did not grant it | WSL2 sandbox with Windows automount disabled; explicit per-folder grants mapped into the sandbox | **Proven.** The agent refused to read an ungranted file by direct path, by directory listing, through a symlink, through `../../..` traversal, and via filesystem-wide search. It could not read `/etc/shadow`. The target file's contents never appeared in any output. |
| **Egress allowlist**, meaning the agent cannot reach network addresses outside a fixed set | nftables rules scoped to the agent's system identity | **Proven, with the scoping residual below.** Non-allowlisted hosts, raw IP addresses, non-standard ports, and arbitrary DNS resolvers are all blocked. Read "Address scoping" and "The baseline route" before relying on this. |
| **Inbound deny**, meaning nothing on your network can reach the agent | Loopback-only gateway plus a Windows Firewall inbound block | **Proven.** No listening surface is exposed off the machine. |
| **No send path at the agent's identity**, so the agent cannot send email | The mail broker runs as root; SMTP ports are blocked for the agent's UID, including to loopback | **Proven.** The agent holds no mail credential and has no route out. |
| **Approval binding**, so an approval covers one message, once | The broker refuses a mutated payload and refuses a re-used approval | **Proven.** |
| **Quarantine hold**, meaning a deleted file the user can restore | Root-owned quarantine the agent's UID cannot reach | **Proven for the hold.** The *routing* of deletes into it is advisory; see "Guard 1 covers deletion by name". |
| **Credential protection**, so your API key is never left in readable config or on a command line | Windows Credential Manager (DPAPI) on the Windows side; inside the sandbox the key exists only in a mode-600 file | **Proven** for the storage path. *Nuance:* the sandbox copy is permission-scoped, not encrypted at rest, and the agent is provisioned its own key by design. See "Provider-key exposure". |
| **Safety-rules integrity**, so the rules file cannot be altered by the agent | Root-owned, read-only, immutable flag, hash-pinned at install | **Proven.** The agent cannot write, change permissions on, or delete-and-recreate the file. |
| **Kill switch**, so you can stop everything immediately | Terminates the real agent process | **Proven.** |

### Gateway-path guarantees

Enforced on the network path through the local gateway. They hold against anything arriving over that path, including everything the chat interface sends. They are **advisory** against an agent that already has shell access and chooses to start the runtime by another route. See "Same-identity runtime invocation".

| Guarantee | Mechanism | Status |
|---|---|---|
| **Spend cap** | Turn gate reads the spend meter before each turn; fails closed if the meter is unreadable | **Proven on the gateway path.** A turn at cap zero is blocked with a readable message and consumes zero model tokens. |
| **Chat gating** | Root-owned proxy fronts the private gateway port | **Proven on the gateway path.** The agent's own identity cannot reach the real gateway directly; it must traverse the proxy. |
| **Safety-rules enforcement at turn time** | Turns refuse to run when the rules file does not match its pinned value | **Proven on the gateway path.** A tampered rules file blocks turns with a readable message and zero model tokens. |
| **Browser tool denial** | `tools.deny` in the gateway configuration | **Proven on the gateway path.** The tool is absent rather than erroring softly. It is not an OS control, and an earlier version of our own documentation wrongly called it structural. What bounds the agent's network reach whatever tool it holds is the egress allowlist. |

---

## Residuals

These are the things we know are weaker than they sound. None of them is hypothetical; each was found by measurement, and each is stated here because a residuals list is the only part of a security document that is expensive to write and therefore worth reading.

### Same-identity runtime invocation (Door 2)

**The finding.** The agent process and the local gateway run under the same system identity inside the sandbox. A process running as that identity, including the agent itself, can start the model runtime directly by its full path, producing a turn that never crosses the gateway and is therefore not subject to the spend cap, the chat gating, the turn-time safety-rules check, or the browser-tool denial.

**Actor model.** This requires the ability to execute a shell command as the agent's identity inside the sandbox. It is not reachable from the network, and it is not a defect in file isolation. The realistic actor is the agent itself, acting on instructions from content it processes. Because our design principle is to assume the model may be hostile, we treat that actor as in scope rather than hypothetical.

**What it does and does not affect.** Every structural guarantee continues to hold against a turn started this way. Such a turn still cannot read ungranted files, still cannot reach addresses outside the allowlist, still cannot send email, still cannot alter the safety-rules file, and is still stopped by the kill switch. What it can do is run without spend accounting and without the gateway-side checks, using the API key you already provisioned. **The exposure is cost and unmetered operation, not data access.**

**Why we have not patched it.** The controls that could distinguish these processes (file permissions, network rules, sandboxing policy) all key on identity, and the two processes share one. Any mitigation short of giving the agent its own identity can be routed around by that same identity, while creating the false impression that the boundary moved. We would rather state the boundary accurately than ship a control that looks like a fix and is not.

**Status: accepted for v1.** Closure is on the roadmap below.

### Address scoping: the allowlist matches addresses, not names

**The finding.** The egress firewall permits traffic to a set of IPv4 addresses, resolved from a list of hostnames. It does not inspect the hostname in the request. **Anything served from an address that is already in the set is reachable, whether or not you allowed that site.** On shared CDN infrastructure, where thousands of unrelated sites answer on the same address, this is not a corner case.

This applies to sites *you* allow as much as to ours: allowing one site allows everything co-hosted with it.

**One measured consequence, so this is concrete rather than theoretical.** The Web access panel offers a switch that turns off the software sources. With that switch off, a real skill installation still completes: the skill hub resolves to an address it shares with `openclaw.ai`, which is a permanent base host no switch can revoke. Until 2026-08-23 the panel said the switch "stops skill installation". It does not, and the copy has been corrected on all three surfaces that said so.

**Status: permanent for v1.** Hostname-level enforcement means terminating TLS and inspecting SNI, which is a different product with a different trust story. We would rather be address-scoped and say so.

### The baseline route: a fresh install is not provider-only

**The finding.** A fresh install does not reach only your model provider. The unrevocable base host set, unchanged in v1.4.0 and measured in the v1.3.5 matrix run, is:

`openclaw.ai`, `docs.openclaw.ai`, `nodejs.org`, `deb.nodesource.com`, `archive.ubuntu.com`, `security.ubuntu.com`, `ports.ubuntu.com`, `esm.ubuntu.com`, `ppa.launchpad.net`

plus the hosts of the provider you chose, plus five model-provider endpoints that are added **unconditionally regardless of which provider you picked**: `api.anthropic.com`, `console.anthropic.com`, `api.openai.com`, `auth.openai.com`, `api.x.ai`.

On top of that, and reachable by default until you switch them off, are eight software-source hosts: `clawhub.ai`, `api.clawhub.ai`, `api.github.com`, `github.com`, `raw.githubusercontent.com`, `objects.githubusercontent.com`, `codeload.github.com`, `registry.npmjs.org`.

That is twenty-two hostnames on a default install, several of them CDN-backed and therefore resolving to rotating pools of addresses. Combined with address scoping above, the reachable surface is materially wider than "your provider and the sites you allowed", and the honest sentence is the one on the panel and in the README: *the AI provider, the software sources ClawFactory needs, and the network addresses of the sites you have allowed.*

**Status: permanent for v1**, though the list is deliberately short and every entry is justified in `setup.ps1` at the point it is added.

### DNS is not gated

**The finding.** Outbound DNS is constrained to the configured resolver, so the agent cannot pick `1.1.1.1`, but the queries themselves are not filtered. A lookup for an attacker-chosen hostname still leaves the machine through the permitted resolver, so a hostname is a usable low-bandwidth outbound channel.

Eliminating this needs a local allowlist-only resolver, which is not in v1. The safety rules tell the agent plainly that a lookup is not a private channel, but that is a prompt-level statement, not a control.

**Status: known, not mitigated in v1.**

### Provider-key exposure

**The finding.** Your provider API key is deliberately given to the agent's runtime, because that is how the product works. Inside the sandbox it lives in a mode-600 file owned by the agent's identity, and once the runtime makes a call the key is in that process's memory. Any code running as that identity can read it.

What bounds the damage is the egress allowlist: a held key can only be sent to an address already in the set. What does *not* bound it is the gateway, because the gateway holds the same credential and runs as the same identity (see Door 2).

**Status: inherent to v1's single-identity design.** Closing it is the same work as closing Door 2.

### Guard 1 covers deletion by name, not destruction

**The finding.** The recoverable-delete guarantee works by putting a different `rm` on the agent's PATH, which routes deletes under `/workspaces` into a root-owned hold. The hold is structural: the agent cannot reach into the quarantine. **The routing is not.** `/bin/rm` by full path, `find -delete`, an `unlink()` call from a script, or truncating a file to zero bytes all destroy the file without passing through it, and nothing outside `/workspaces` is covered at all.

The user-facing wording is deliberately limited to match: *this covers deletion by name, which is how deletion is ordinarily expressed; it does not cover every possible way a program can destroy a file.*

**Status: accepted for v1.** Closing it properly needs a filesystem-level interception layer, which was scoped and cut rather than deferred.

### The build stamp is forgeable

**The finding.** Release builds carry a stamp over the compiled bytes, and the signing script refuses any binary without a matching one. The stamp is an ordinary file. Anyone who can run the signer can write one.

It is a real guard against the documented shortcut being taken under time pressure, which is process drift, and no guard at all against an attacker who already has local execution on the build machine. We say so here rather than letting the phrase "build gate" do work it cannot do.

**Status: advisory by construction, and labelled as such in the build script itself.**

### Root ends everything

**The finding.** Every control here is enforced by the operating system against a specific unprivileged identity. Root inside the WSL distro, or Administrator on the Windows side, can remove all of them: flush the firewall, clear the immutable flag on the safety rules, read the credential store, empty the quarantine.

This is not a defect, it is the shape of the model. It is stated because "the agent is sandboxed" invites the reading that the sandbox holds against anything, and it does not. The threat model is a hostile *agent*, running unprivileged. It is not a hostile administrator, and it is not physical access.

**Status: by design.**

---

## Roadmap

**v2: separate-identity agent isolation.** Run the agent under a dedicated system identity or container, so it cannot invoke the gateway's runtime, cannot hold what the gateway holds, and cannot read the credential the gateway uses. This converts the spend cap, the chat gating, the turn-time safety-rules check and the browser-tool denial from gateway-path guarantees into structural ones, and it closes provider-key exposure at the same time. It is the single change that closes the most residuals on this page, and it is tracked as item #25 in [`v1.1_backlog.md`](v1.1_backlog.md).

The pattern is already proven in this release: the chat gating proxy and the mail broker both run under a different identity than the agent, and those boundaries hold.

---

## Summary

If your concern is that an AI agent will read files you did not give it, send mail you did not approve, expose a door to your network, or quietly rewrite its own safety rules, those boundaries are structural and proven on clean machines.

If your concern is that the agent can only talk to a short list of places, read the address-scoping and baseline-route findings first: the guarantee is real but it is about addresses, not names, and the default list is longer than "your provider".

If your concern is guaranteeing that a compromised agent cannot spend your API budget or run unmetered, that boundary is real against the network path and advisory against a hostile agent with shell access. It becomes structural with separate-identity isolation.

We would rather you know exactly which is which.

## Reporting

Email **support@clawfactory.app**. Please do not open a public issue for a security vulnerability. See [SECURITY.md](SECURITY.md) for the full policy.
