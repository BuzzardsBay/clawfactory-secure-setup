# ClawFactory Secure Setup v1.4.3

**Free and open source under Apache-2.0.** Not a beta, not a trial, not a limited
edition. There is nothing to buy, no key to enter, no account to create, and the
installer makes no network call to any ClawFactory-operated server at any point.

This page is written for someone deciding whether to install it. It says what the
product enforces, what it does not enforce, and where the difference is weaker than
the name suggests. If you would rather read the negative space first, start with
[`SECURITY_FINDINGS.md`](../SECURITY_FINDINGS.md), and the record of what went wrong
during development is in [`FAILURE_CATALOGUE.md`](FAILURE_CATALOGUE.md).

---

## What it is

A Windows installer that sets up a hardened runtime for an AI coding agent on a fresh
machine, with the defaults set to the restrictive side rather than the convenient one.

The agent runs inside a WSL2 sandbox as a non-privileged account, with Windows drive
automounting disabled, an operating-system firewall scoped to that account, the local
gateway bound to loopback only, an inbound block on the Windows side, the provider
credential held in the Windows credential store, and a safety-rules file that is
root-owned, read-only and hash-pinned at install.

It ships with a desktop application for managing grants, approvals and network access,
so the ordinary tasks do not require a terminal.

### System requirements

- Windows 10 version 2004 or later, or Windows 11
- Administrator privileges to install
- 16 GB RAM recommended, 8 GB minimum
- 50 GB free disk, which covers the bundled Linux filesystem, the agent runtime and
  the desktop application
- Hardware virtualization enabled in firmware for WSL2. The installer falls back to
  WSL1 automatically if it is unavailable

### Installing

1. Download the installer from the Releases page. It is about 440 MB, because the
   Linux filesystem image and the desktop application are bundled rather than fetched.
2. Right-click and choose Run as administrator.
3. Walk the wizard: choose a provider, supply an API key, acknowledge the security
   summary, install.
4. Allow 10 to 20 minutes. The installer reboots once if Windows features have to be
   enabled, and resumes on its own.

---

## What it enforces, in two classes

These are not one undifferentiated set of security claims, and presenting them that
way would be dishonest. They fall into two classes with genuinely different strength,
and the distinction is maintained everywhere in this project's documentation.

### Structural

Enforced by the operating system, the filesystem or the network stack. They hold
regardless of what the agent does or how its process was started. **A hostile agent
cannot route around these.**

| Guarantee | How it is enforced |
|---|---|
| The agent cannot read files you did not grant it | Sandbox with Windows automounting disabled, plus explicit per-folder grants |
| The agent cannot reach network addresses outside a fixed set | Firewall rules scoped to the agent's system identity |
| Nothing on your network can reach the agent | Loopback-only gateway plus a Windows inbound block |
| The agent cannot send email | The mail broker runs as a different, privileged identity; the agent holds no mail credential and its identity has no route out |
| An approval covers one message, once | The broker refuses a mutated payload and refuses a re-used approval |
| A deleted file is held where the agent cannot reach it | Root-owned quarantine. The **hold** is structural; the routing of deletes into it is not, and that limit is stated below |
| Your API key is not left in readable configuration or on a command line | Windows credential store on the Windows side; a permission-scoped file inside the sandbox |
| The agent cannot alter its own safety rules | Root-owned, read-only, immutable flag, hash-pinned at install |
| You can stop everything immediately | The kill switch terminates the real agent process |

Each of these was proven by asking the agent itself to cross the boundary on a freshly
installed machine and recording what it actually did, rather than by reading a
configuration file. A configuration that is wrong and a configuration that is right
look identical from the configuration side.

### Gateway-path

Enforced on the network path through the local gateway. They hold against anything
arriving over that path, including everything the chat interface sends. They are
**advisory** against an agent that already has shell access and starts the runtime
another way. See "Same-identity runtime invocation" below.

| Guarantee | How it is enforced |
|---|---|
| Spend cap | The turn gate reads the spend meter before each turn and fails closed if the meter cannot be read |
| Chat gating | A root-owned proxy fronts the private gateway port |
| Safety rules checked at turn time | Turns refuse to run when the rules file does not match its pinned value |
| Browser tool denial | Denied in the gateway configuration. This is **not** an operating-system control, and an earlier version of our own documentation wrongly called it structural |

---

## What it does not do

Stated plainly, because these are the parts a reader is most likely to assume in our
favour.

**Your data does reach your model provider.** That is what a hosted AI agent is. The
sandbox runs on your machine; the model does not. Nothing here prevents content from
leaving the machine to the provider you configured, and any claim that it does would
be false.

**It is not injection-proof, and nothing here claims to make a model behave.** The
design assumes the model may act on hostile content it processes. The answer is to
bound what the agent's identity can reach at the operating-system level, not to make
the agent trustworthy.

**A fresh install does not reach only your provider.** See the accepted conditions
below.

**Root ends everything.** Every control here is enforced by the operating system
against one unprivileged identity. Root inside the sandbox, or an Administrator on
Windows, can remove all of them. The threat model is a hostile agent running
unprivileged. It is not a hostile administrator and it is not physical access.

---

## Accepted conditions of shipping

Every one of these is known, measured, and shipped anyway. They are conditions, not
surprises, and each one is a decision rather than an oversight.

Conditions 2 through 8 below are seven of the eight residuals recorded in
[`SECURITY_FINDINGS.md`](../SECURITY_FINDINGS.md), restated here in plain language so
that a reader of the release notes alone is not missing any of them. The eighth, that
root ends every control, is stated under "What it does not do" above because it is a
property of the threat model rather than a condition of this release. That document is
the authority; if the two ever disagree, it wins.

### 1. Software sources succeed intermittently when the switch is on

**With the software-sources switch on, fetches from code and package repositories
succeed only intermittently, roughly half the time in measurement.**

The reason is that the firewall holds a snapshot of network addresses, while those
services answer from a larger, rotating pool. The switch is not lying about being on.
The address list behind it is incomplete.

Measured before this release and quoted as prior measurement: with the switch reading
on and a freshly resolved address set, the route answered 2 of 6 attempts after a
reboot and 5 of 12 before one. A site the user had allowed themselves answered 9 of
12. The panel reads that the switch is on and reports a number of reachable addresses,
and it admits no "sometimes".

**Turning the switch off still reliably blocks.** The failure is in the permissive
direction for reliability and not in the permissive direction for security.

If you rely on package installation inside the sandbox, expect to retry.

*Source: `docs/session_reports/2026-08-26_v141_validation_closure_closeout.md`, section 9,
where these counts are recorded and labelled as prior measurement.*

### 2. The allowlist matches addresses, not names

The egress firewall permits traffic to a set of addresses resolved from a list of host
names. It does not inspect the host name in the request. **Anything served from an
address already in the set is reachable, whether or not you allowed that site.** On
shared content-delivery infrastructure, where many unrelated sites answer on the same
address, this is not a corner case.

This applies to sites you allow as much as to ours. Allowing one site allows everything
co-hosted with it.

One measured consequence, so this is concrete: a panel switch that turns off software
sources does not stop a component installation, because the relevant service resolves
to an address it shares with a permanent base host that no switch can revoke. The panel
used to say the switch stopped it. That wording was wrong and has been corrected
everywhere it appeared.

Fixing this properly means terminating encrypted connections and inspecting the name
inside them, which is a different product with a different trust story. We would rather
be address-scoped and say so.

### 3. A fresh install is not provider-only

A default install can reach roughly twenty-two host names: a small set of base hosts
for the runtime and the operating system's own package sources, the hosts of the
provider you chose, five model-provider endpoints that are added regardless of which
provider you picked, and eight software-source hosts that are reachable until you
switch them off.

Several are content-delivery backed and therefore resolve to rotating pools of
addresses, which combines with the point above. The honest sentence is the one on the
panel: the AI provider, the software sources the product needs, and the addresses of
the sites you have allowed. Every entry is justified in the installer source at the
point it is added.

### 4. Same-identity runtime invocation

The agent process and the local gateway run under the same system identity inside the
sandbox. A process running as that identity, including the agent itself, can start the
model runtime directly, producing a turn that never crosses the gateway and is
therefore not subject to the spend cap, the chat gating, the turn-time safety-rules
check, or the browser-tool denial.

**Every structural guarantee still holds against such a turn.** It still cannot read
ungranted files, reach addresses outside the allowlist, send email, or alter the safety
rules, and the kill switch still stops it. **The exposure is cost and unmetered
operation, not data access.**

It is not patched because the controls that could distinguish the two processes all key
on identity, and the two processes share one. Any mitigation short of giving the agent
its own identity can be routed around by that same identity while creating the
impression that the boundary moved.

### 5. Name lookups are not filtered

Outbound name resolution is constrained to the configured resolver, so the agent cannot
choose its own. The queries themselves are not filtered, so a host name remains a
usable low-bandwidth outbound channel. Eliminating this needs an allowlist-only local
resolver, which is not in this version. The safety rules tell the agent that a lookup
is not a private channel, but that is a statement in a prompt, not a control.

### 6. The provider key is given to the agent by design

Your API key is deliberately provided to the agent's runtime, because that is how the
product works. Inside the sandbox it lives in a permission-scoped file owned by the
agent's identity, and once the runtime makes a call the key is in that process's
memory. Any code running as that identity can read it. What bounds the damage is the
egress allowlist: a held key can only be sent to an address already in the set. What
does not bound it is the gateway, which holds the same credential under the same
identity.

The key is permission-scoped rather than encrypted at rest inside the sandbox. On the
Windows side it is held in the platform credential store.

### 7. Recoverable delete covers deletion by name

The recoverable-delete guarantee works by placing a different delete command on the
agent's path, routing deletions under the workspace into a root-owned hold. **The hold
is structural.** The routing is not. A delete by full path, a search-and-delete, an
unlink call from a script, or truncating a file to zero bytes all destroy the file
without passing through it, and nothing outside the workspace is covered at all.

The wording in the product is deliberately limited to match: this covers deletion by
name, which is how deletion is ordinarily expressed, and it does not cover every
possible way a program can destroy a file.

### 8. The build stamp is forgeable

Release builds carry a stamp over the compiled bytes, and the signing script refuses a
binary without a matching one. The stamp is an ordinary file, and anyone who can run
the signer can write one. It is a real guard against the documented shortcut being
taken under time pressure. It is no guard at all against someone who already has
execution on the build machine, and the build script says so in its own comments.

---

## What changed in the 1.4 series

### 1.4.3

**Every file the installer bundles now contains the bytes the repository contains.**

Ten bundled files had a working-copy form that differed from their committed form, and
six of them already carried the rule that was meant to prevent it. Adding such a rule
does not re-normalise files that are already checked out, and the ordinary status and
difference commands are blind to the divergence by construction, so nothing reported
it. All divergent files were re-materialised, a repository-wide baseline was added so
the checked-out form no longer depends on how an individual machine is configured, and
a build gate now refuses to build when a bundled file is not its committed bytes.

Comparing this release with the previous one blob by blob, **exactly one bundled file's
committed bytes changed, and that was the version string**. The ten files were never
edited. Content did not change; only the line endings that the build machine's working
copy had been carrying.

One delivered file's size changes as a result: the agent's orchestrator prompt reaches
the sandbox 65 bytes smaller, with identical content.

*Source: `docs/session_reports/2026-08-26_v143_line_endings_closeout.md`, sections 3.3,
3.4, 6 and 7.5.*

### 1.4.2

Uninstaller fixes, all on the branch that keeps the Linux environment.

The teardown script's output and exit code are now captured, logged and checked against
a terminal marker, rather than discarded with a success marker written unconditionally.
The removal list is derived from the installer rather than maintained by hand, covering
11 units disabled before deletion, 17 helper scripts, a configuration drop-in directory
and one command-line tool. The gateway stop carries the environment variable it needs
and no longer discards its error output. The agent account's processes are verified
gone before the account is removed. A failed teardown now shows the user a dialog
naming what was left behind. The uninstall dialog's wording was rewritten.

No security control was added, removed, weakened or re-scoped.

*Source: `docs/session_reports/2026-08-26_v142_uninstaller_fixes_closeout.md`, section
10.5.*

### 1.4.1

Two defects from the previous release cleared, measured across a real reboot.

*Source: `docs/session_reports/2026-08-26_v141_validation_closure_closeout.md`.*

### 1.4.0

**The release became free.** Licence checking was removed entirely, and with it the
network call that had been sending a machine identifier to a project-operated server on
every install. The README had said "no telemetry" while that call existed. It is now
true, and the document says specifically that there is no telemetry, no licence server
and no account.

The same pass audited every claim in the shipped documents against the code that was
supposed to implement it. Ten source links that all landed in the wrong place were
removed rather than corrected. A control described as "structurally denied" was
corrected to gateway-path. A claim of four working agents was qualified, because three
of them are scaffolding. Apache-2.0 in both repositories.

*Source: `docs/session_reports/2026-08-23_free_release_prep_closeout.md`, section 4.2.*

---

## Validation status

*This section is completed when the v1.4.3 validation run closes. It is deliberately
left unwritten rather than filled with the previous release's results: this release has
not been installed on a clean machine at the time of writing, and saying otherwise
would be exactly the class of claim the rest of this page exists to avoid.*

How validation is done, so the eventual statement can be read properly: runs happen on
clean cloud machines built from a stock Windows image, installed the way a customer
installs. Every block assertion carries a positive control that must succeed in the
same run, and a control that does not fire voids the result rather than producing a
verdict.

---

## Reporting a problem

For a security issue, email the address in [`SECURITY.md`](../SECURITY.md) rather than
opening a public issue.

For anything else, including a claim on this page that you think is wrong or reads as
more flattering than the facts support, an issue is welcome. An inaccurate claim in a
security product is a defect in the same sense as any other.
