# ClawFactory Secure Setup v1.4.4

**Free and open source under Apache-2.0.** Not a beta, not a trial, not a limited
edition. There is nothing to buy, no key to enter, no account to create, and the
installer makes no network call to any ClawFactory-operated server at any point.

This page is written for someone deciding whether to install it. It says what the
product enforces, what it does not enforce, and where the difference is weaker than
the name suggests. If you would rather read the negative space first, start with
[`SECURITY_FINDINGS.md`](../SECURITY_FINDINGS.md), which is the authority; if the two
ever disagree, it wins. The record of what went wrong during development is in
[`FAILURE_CATALOGUE.md`](FAILURE_CATALOGUE.md).

**Artifact:** `ClawFactory-Secure-Setup.exe`, 440,610,608 bytes, signed SHA-256
`6e65560325cb6d7d3fea204ebb72876b3b113cbbfe9f2fa4f94113237e9eb4d1`. See
"Verifying what you downloaded" at the end.

---

## Read this before you download 6 GB

**You talk to your agent in ClawChat, and you manage it in Studio. They are two
different windows.** The desktop icon and the ClawChat entry in the Start Menu both
open ClawChat, which is the chat interface.

**ClawFactory Studio is the control panel, and seven of its eleven panels are not in
this release.** Four are real and are where grants, approvals, web access and
recovered files live: **Workspace**, **Approvals**, **Web access** and **Recently
deleted**. The seven that are not in this release say so on their own page:
**Templates**, **Files**, **Activity**, **Chat**, **Agents**, **Skills** and
**Settings**. Each renders a heading, the sentence `<Panel> is not part of this
release.`, a line reading `Nothing here failed and nothing is misconfigured`, and a
card listing the four panels you can use today.

**Studio's own Chat panel is one of the seven.** Chat lives in ClawChat, not in
Studio. And Templates is the first item in Studio's navigation, so it is likely the
first thing you click, and it is one of the seven.

This is stated here rather than left to be discovered after a 6 GB download and a
20 minute install.

*Source for the panels: box A close-out, section 14, matrix row 11 checks 9a to 9e,
verified by hand over RDP with screenshots retained. Source for the shortcuts: the
`[Icons]` section of `ClawFactory-Secure-Setup.iss` at the build commit.*

---

## What it is

A Windows installer that sets up a hardened runtime for an AI coding agent on a fresh
machine, with the defaults set to the restrictive side rather than the convenient one.

The agent runs inside a WSL2 sandbox as a non-privileged account, with Windows drive
automounting disabled, an operating-system firewall scoped to that account, the local
gateway bound to loopback only, an inbound block on the Windows side, and a
safety-rules file that is root-owned, read-only and hash-pinned at install.

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

A clean install was completed on four separate machines for this release, across
three provider variants. Each reported success from the installer's own completion
marker, and the same 15 of 19 smoke checks passed, with 4 skipped and none failed.

*Source: box A, boxes B and C, and box D close-outs, phase 1 in each.*

---

## What it enforces structurally

These are the guarantees enforced by the operating system, the filesystem or the
network stack. They hold regardless of what the agent does or how its process was
started. **A hostile agent cannot route around these.**

This is the structural column only. ClawFactory also has a set of guarantees enforced
on the network path through the local gateway, which are weaker. Those are listed
under "The gateway-path guarantees are advisory" below rather than mixed in here.

| Guarantee | How it is enforced |
|---|---|
| The agent cannot read files you did not grant it | Sandbox with Windows automounting disabled, plus explicit per-folder grants |
| The agent cannot reach network addresses outside a fixed set | Firewall rules scoped to the agent's system identity |
| Nothing on your network can reach the agent | Loopback-only gateway plus a Windows inbound block |
| The agent cannot send email | The mail broker runs as a different, privileged identity; the agent holds no mail credential and its identity has no route out |
| An approval covers one message, once | The broker refuses a mutated payload and refuses a re-used approval |
| A deleted file is held where the agent cannot reach it | Root-owned quarantine. The hold is structural; the routing of deletes into it is not, and that limit is stated below |
| Your API key is not left in readable configuration or on a command line | Windows credential store on the Windows side; a permission-scoped file inside the sandbox |
| The agent cannot alter its own safety rules | Root-owned, read-only, immutable flag, hash-pinned at install |

Most of these were proven by asking the agent itself to cross the boundary on a
freshly installed machine and recording what it actually did. A configuration that is
wrong and a configuration that is right look identical from the configuration side.

### Two of those rows rest on weaker evidence than the rest, and say so

Every row of this table was enumerated in v1.4.4, one at a time, and asked what
evidence stood behind it. Two rows cannot be proven by asking the agent to cross the
boundary, and both carry their own method in their Status column in
[`SECURITY_FINDINGS.md`](../SECURITY_FINDINGS.md) rather than borrowing the sentence
above.

**Inbound deny** is a claim about a machine other than this one. It is measured as
the absence of a listening surface plus the presence of the firewall rule. No run has
ever driven a connection attempt from a second host on the network.

**Credential protection** is a claim about where a secret rests. It is measured as
file ownership and file mode, not by a recorded refusal, and it cannot be anything
else: the agent is provisioned its own key by design, so asking it to fetch the key
would not produce a refusal in any case.

Both are real evidence and both are a weaker class than a recorded refusal. Calling
them the same thing would be the kind of flattening this document exists to avoid.

That enumeration also removed a row. The kill switch had been listed as a proven
structural guarantee since the first release and had never once been executed on an
installed machine. See "The kill switch is an action, not a boundary" below.

*Source: v1.4.4 wrapper-fixes close-out, section 5.2, which enumerates all nine rows.*

---

## What it does not do

Stated plainly, because these are the parts a reader is most likely to assume in our
favour.

**Your data does reach your model provider.** That is what a hosted AI agent is. The
sandbox runs on your machine; the model does not. Nothing here prevents content from
leaving the machine to the provider you configured, and any claim that it does would
be false. What is gated by approval is email, and only email.

**Nothing here claims to make a model behave.** The design assumes the model may act
on hostile content it processes. The answer is to bound what the agent's identity can
reach at the operating-system level, not to make the agent trustworthy.

**A fresh install does not reach only your provider.** See the residuals below.

**Root ends everything.** Every control here is enforced by the operating system
against one unprivileged identity. Root inside the sandbox, or an Administrator on
Windows, can remove all of them. The threat model is a hostile agent running
unprivileged. It is not a hostile administrator and it is not physical access.

---

## Three disclosures

None of these is buried further down. Each is stated here, in full, before the
residuals list.

### 1. One approval guarantee has never been measured, on any release

**The specific assertion:** after you approve a message, if the source attachment is
rewritten before the message is sent, do the approved bytes go or the rewritten ones?

**That comparison has never been made, on any release of this product, on any
machine, in this project's history.** Not in v1.4.4, not in v1.4.3, not earlier.

**The surrounding mechanism is proven.** Enqueue, approval, single-use approval,
payload hash binding at approval time (a wrong payload hash voids the approval), the
receipt, the staging purge, and the refusal of a replayed approval are all measured.
What was never made is the end-to-end comparison of approved bytes against arrived
bytes.

**The reason is a limitation in our test rig, not a product failure**, and the
distinction is measured rather than argued. Against a plain loopback mail sink the
broker correctly refuses to submit, because the sink does not offer STARTTLS and the
broker will not send a credential in cleartext. That refusal is itself recorded as a
positive security property. Against an encrypted sink using a locally trusted
throwaway authority, the bundled Node build will not read the system trust store and
rejects the certificate. So the product behaves correctly in both directions and the
harness cannot reach the assertion. Nothing ever arrived, so nothing could be
compared.

It is tracked as card #305.

*Source: box D completion close-out, section 14.1.*

### 2. With the software-source switch on, GitHub fetches can fail and succeed on retry

With the software-sources switch on, a fetch from a GitHub-family host may
intermittently fail and succeed when you try again.

Measured on one machine: 96 attempts across 8 toolchain hosts, 12 attempts each, as
the agent's identity, with the switch confirmed on and both controls firing in the
same run.

| Host | Connected |
|---|---|
| `clawhub.ai`, `objects.githubusercontent.com`, `raw.githubusercontent.com`, `registry.npmjs.org` | 12 of 12 |
| `codeload.github.com` | 10 of 12 |
| `api.clawhub.ai` | 9 of 12 |
| `github.com` | 7 of 12 |
| `api.github.com` | 6 of 12 |

Four of the eight answered on every attempt. Every one of the eight answered at least
once, so a working route was built to each.

**The mechanism is INFERRED, and is labelled as such.** The explanation we believe is
that the firewall holds a snapshot of resolved addresses while those services answer
from a rotating pool, so an address that was allowed at refresh time may not be the
address DNS returns moments later. That is consistent with the split, but nothing in
any run measures the pool itself. The split is measured; the cause is not.

**This does not affect the route to your model provider**, which is allowlisted
separately and measured at 12 of 12 in the same run, alongside a control host that
was blocked 0 of 12.

**Turning the switch off still reliably blocks.** If you rely on package installation
inside the sandbox, expect to retry.

It is tracked as card #261.

*Source: boxes B and C close-out, and box D completion close-out section 14.3, where
these counts are recorded.*

### 3. Five shipped scripts render em dashes as garbage in seven places

Five of the shipped PowerShell scripts are saved as UTF-8 without a byte-order mark.
Windows PowerShell 5.1 decodes a mark-less script as the ANSI codepage, so each em
dash is read as three garbage characters.

**Seven of those occurrences are customer-visible.** Five are in the dialog that
`rename-agent.ps1` shows, which exists solely to explain why renaming your assistant
is not supported yet. Two are in `bootstrap.ps1`: one lands inside a prompt file
written for the stub agents, and one is a warning line that reaches the console and
the install log. The rest are in comments, invisible to you and one edit away from
becoming visible.

**It is cosmetic.** Nothing about the sandbox, the firewall, the guards, the gateway
or containment is implicated. The meaning survives; it looks broken. It is not in
either uninstall dialog, measured both ways across two independent invocations.

It is shipping in this release and is scheduled for v1.5 along with a tenth build
gate that closes the class rather than the instance: no shipped script may contain a
non-ASCII byte unless it carries a byte-order mark. It is tracked as card #296.

*Source: box A close-out, section 15, where the file's count of 7 em dash sequences
matched the 7 mojibake occurrences byte for byte; and box D completion close-out
section 14.2.*

---

## Residuals

These are the things that are weaker than they sound, and they are the whole of the
list in [`SECURITY_FINDINGS.md`](../SECURITY_FINDINGS.md), restated in plain language
so a reader of this page alone is not missing any of them. Each was found by
measurement.

### The allowlist matches addresses, not names

The egress firewall permits traffic to a set of addresses resolved from a list of
host names. It does not inspect the host name in the request. **Anything served from
an address already in the set is reachable, whether or not you allowed that site.**
On shared content-delivery infrastructure, where many unrelated sites answer on the
same address, this is not a corner case.

This applies to sites you allow as much as to ours. Allowing one site allows
everything co-hosted with it.

One measured consequence, so this is concrete: the panel switch that turns off
software sources does not stop a component installation, because the relevant service
resolves to an address it shares with a permanent base host that no switch can
revoke. The panel used to say the switch stopped it. That wording was wrong and has
been corrected everywhere it appeared.

Fixing this properly means terminating encrypted connections and inspecting the name
inside them, which is a different product with a different trust story. We would
rather be address-scoped and say so. Permanent for v1.

### A fresh install is not provider-only

A default install can reach roughly twenty-two host names: a small set of base hosts
for the runtime and the operating system's own package sources, the hosts of the
provider you chose, five model-provider endpoints that are added regardless of which
provider you picked, and eight software-source hosts that are reachable until you
switch them off.

Several are content-delivery backed and therefore resolve to rotating pools of
addresses, which combines with the point above. The honest sentence is the one on the
panel: the AI provider, the software sources the product needs, and the addresses of
the sites you have allowed. Every entry is justified in the installer source at the
point it is added. Permanent for v1.

### Same-identity runtime invocation

The agent process and the local gateway run under the same system identity inside the
sandbox. A process running as that identity, including the agent itself, can start
the model runtime directly, producing a turn that never crosses the gateway and is
therefore not subject to the spend cap, the chat gating, the turn-time safety-rules
check, or the browser-tool denial.

**Every structural guarantee still holds against such a turn.** It still cannot read
ungranted files, reach addresses outside the allowlist, send email, or alter the
safety rules. **The exposure is cost and unmetered operation, not data access.**

It is not patched because the controls that could distinguish the two processes all
key on identity, and the two processes share one. Any mitigation short of giving the
agent its own identity can be routed around by that same identity while creating the
impression that the boundary moved. Accepted for v1; closure is the v2 roadmap item.

### The gateway-path guarantees are advisory

Four guarantees are enforced on the network path through the local gateway rather
than by the operating system: the spend cap, the chat gating, the turn-time
safety-rules check, and the denial of the browser tool. They hold against everything
arriving over that path, including everything the chat interface sends, and each was
measured on that path. They are advisory against an agent that already has shell
access and starts the runtime another way, which is the point immediately above.

An earlier version of our own documentation called the browser-tool denial
structural. It is not, and the wording was corrected everywhere it appeared.

### Name lookups are not filtered

Outbound name resolution is constrained to the configured resolver, so the agent
cannot choose its own. The queries themselves are not filtered, so a host name
remains a usable low-bandwidth outbound channel. Eliminating this needs an
allowlist-only local resolver, which is not in this version. The safety rules tell
the agent that a lookup is not a private channel, but that is a statement in a
prompt, not a control. Known, not mitigated in v1.

### The provider key is given to the agent by design

Your API key is deliberately provided to the agent's runtime, because that is how the
product works. Inside the sandbox it lives in a permission-scoped file owned by the
agent's identity, and once the runtime makes a call the key is in that process's
memory. Any code running as that identity can read it. What bounds the damage is the
egress allowlist: a held key can only be sent to an address already in the set. What
does not bound it is the gateway, which holds the same credential under the same
identity.

The key is permission-scoped rather than encrypted at rest inside the sandbox. On the
Windows side it is held in the platform credential store. This is inherent to the
single-identity design of v1; closing it is the same work as the point above.

On a validation machine with a real credential present, the credential file was
measured unreadable by the agent's identity, and the secret was searched for on eight
separate surfaces and appeared on none of them.

*Source: box D close-out, checks `G2.10`, `S.4`, `S.4leak` and its control.*

### Recoverable delete covers deletion by name

The recoverable-delete guarantee works by placing a different delete command on the
agent's path, routing deletions under the workspace into a root-owned hold. **The
hold is structural.** The routing is not. A delete by full path, a search-and-delete,
an unlink call from a script, or truncating a file to zero bytes all destroy the file
without passing through it, and nothing outside the workspace is covered at all.

The wording in the product is deliberately limited to match: this covers deletion by
name, which is how deletion is ordinarily expressed, and it does not cover every
possible way a program can destroy a file. Accepted for v1.

### The kill switch is an action, not a boundary

Until this release the Start Menu kill switch stopped nothing. Both of the commands
it sent into the sandbox died on a quoting fault, the script ignored their exit
codes, and it printed that the gateway was stopped and any running turn killed over a
gateway that was still answering and a process that was still alive. Its third
action, unmounting your granted folders, did work. This was true of every release
from the first, and it was listed as a proven structural guarantee the entire time.

**What changed in v1.4.4.** The quoting is fixed, and, more importantly, the script
now measures. After it issues the stop it counts the agent's processes inside the
sandbox and prints only what that count supports, per claim, exiting non-zero when it
cannot confirm.

**It is not in the structural table, and it will not be.** A kill switch is an action
you take, not a boundary that holds: a stopped process running as the agent's own
identity can be started again by that identity. What it guarantees is that when you
run it, it tells you the truth about what it managed to stop.

Both halves were measured from a clean install for this release: it stops a running
gateway and turn, with a positive control confirming by two independent readers that
the gateway was up beforehand; and with every sandbox call deliberately made to fail,
it refuses to claim success.

*Source: box A close-out, sections 8I.1 and 8I.2.*

### The build stamp is forgeable

Release builds carry a stamp over the compiled bytes, and the signing script refuses
a binary without a matching one. The stamp is an ordinary file, and anyone who can
run the signer can write one. It is a real guard against the documented shortcut
being taken under time pressure. It is no guard at all against someone who already
has execution on the build machine, and the build script says so in its own comments.

---

## What changed in v1.4.4

Three shipped behaviour changes, all in the direction of the product doing what it
says. **No security boundary was moved:** the firewall, the sandbox, the guards and
the gateway path are untouched by this release.

**The kill switch works, and reports honestly when it cannot.** Described above.

**Switching model provider works at all.** The script that does it died before
changing anything, for every provider, on an unescaped variable inside four of its
own explanatory comments. It now completes, applies its firewall change, and leaves
the software-source set untouched. Measured on a clean install: it switched a machine
to a local model, exited zero, and the software-source address count was identical
either side of the switch.

**The provider switch tells the truth about Ollama.** Where the previous release
printed a success line unconditionally, it now prints a warning when Ollama is not
actually installed, and says the firewall change still applies. This proved itself on
a real failure rather than a rigged one: Ollama genuinely could not install on the
validation machine, and the script said so.

**A ninth build gate.** Every shipped script is now parsed at build time, and the
build fails if any of them interpolates a variable the file never defines. That is
the class of defect that made the provider switch inert. It does not ship in the
artifact; it constrains future builds.

*Source: v1.4.4 wrapper-fixes close-out, section 11.5; box A close-out, sections 8I
and 16.*

### The 1.4 series before this release

**1.4.3** made every file the installer bundles carry the bytes the repository
contains. Ten bundled files had a working-copy form that differed from their
committed form, and six of them already carried the rule that was meant to prevent
it. A build gate now refuses to build when a bundled file is not its committed bytes.

**1.4.2** fixed the uninstaller on the branch that keeps the Linux environment. The
teardown script's output and exit code are now captured and checked against a
terminal marker, rather than discarded with a success marker written unconditionally.

**1.4.1** cleared two defects from the previous release, measured across a real
reboot.

**1.4.0** made the release free. Licence checking was removed entirely, and with it
the network call that had been sending a machine identifier to a project-operated
server on every install. The README had said "no telemetry" while that call existed.
It is now true. Apache-2.0 in both repositories.

The releases numbered 1.4.2 and 1.4.3 were built and signed but never published. They
are superseded by this one.

---

## Uninstalling

Uninstall from Windows Settings, under Installed apps, where the entry reads
**ClawFactory Secure Setup version 1.4.4**.

You will see two questions.

**The first is Windows asking whether you are sure.** Answer Yes to proceed.

**The second is ours, and it is a real choice:**

> Also remove the Ubuntu Linux distro that ClawFactory created?
>
> ClawFactory is removed from this machine either way: the agent, its configuration
> and plugins, clawuser's home directory, the OpenClaw runtime, and every ClawFactory
> service and firewall rule.
>
> YES also unregisters the Ubuntu distro and deletes its disk image (about 6 GB).
> Choose this unless something else on this machine uses that distro.
>
> NO leaves the now-empty Ubuntu distro registered, so anything else that shares it
> keeps working. You can install ClawFactory again later and it will reuse the
> distro.
>
> Your ClawChat conversation history is stored on Windows, under %APPDATA%\ClawChat,
> and neither choice deletes it.

**On the No branch, the distro stays registered and its disk image stays on disk.**
That is deliberate: the registration points at that file, and deleting it would
destroy the distro you just chose to keep. Everything ClawFactory placed in the
Windows application directory is removed; on the validation machine that was 56 files
going to zero, with the distro's backing image correctly surviving.

**On the No branch, what was removed inside the distro was measured rather than
assumed**, by reading the machine back against a snapshot taken before the uninstall
started: 11 services to 0, 8 startup enablements to 0, 17 helper scripts to 0, the
agent's account and its home directory gone, the firewall table gone, the
configuration directory and both address maps gone, and the registry entries, program
data directory and scheduled task gone. Nothing ClawFactory installed runs at the
next boot of the kept distro. A reinstall onto the emptied distro completes.

**If the Linux cleanup cannot finish, it tells you.** With a fault deliberately
injected so that the cleanup could not complete, the product did not report success.
It logged the failure as a failure, showed a dialog headed "Linux cleanup incomplete"
naming exactly what was left behind, and told the user the command to run to finish
by hand. On that run the in-distro cleanup exited zero while leaving files behind, so
an uninstaller that had merely checked the exit code would have reported success. It
does not, because it requires the terminal marker as well.

*Source: box D close-out, sections 12 and 13; box D completion close-out, sections 7
to 10.*

---

## How this release was validated, so the statements above can be read properly

Runs happen on clean cloud machines built from a stock Windows image, installed the
way a customer installs, using the same signed binary published here.

Two rules the harness enforces mechanically, both learned by getting a result wrong:

**Every block assertion carries a positive control that must succeed in the same
run.** A refusal is only evidence if the thing is otherwise working.

**A control that did not fire voids the result.** A missing precondition is recorded
as void with a named reason, never as a product verdict.

This release was validated across four machines. **No product defect was found on any
of them.** The only product-shaped findings in the whole cycle are cosmetic and
carded: the mojibake disclosed above, and two observations about the uninstall
dialog.

What is honest to add is that in each of the five sessions of this cycle, the defects
found in our own instruments outnumbered the defects found in the product, and
several of those would have produced false findings had they not been caught. They
are recorded, counted and root-caused in
[`FAILURE_CATALOGUE.md`](FAILURE_CATALOGUE.md).

The things this cycle did **not** measure are listed rather than omitted: the
approval payload-binding assertion disclosed above; external mail delivery, which is
a receiving-provider outcome rather than a ClawFactory behaviour, and no outbound
mail left this cycle at all; a reinstall after the branch that removes the distro;
and a cross-account install.

*Source: box D completion close-out, sections 13 and 14.5.*

---

## Verifying what you downloaded

A release whose argument is that you can check it should tell you how to check it.

**The digest.** In PowerShell:

```powershell
Get-FileHash -Algorithm SHA256 .\ClawFactory-Secure-Setup.exe
```

It must print
`6E65560325CB6D7D3FEA204EBB72876B3B113CBBFE9F2FA4F94113237E9EB4D1`, and the file must
be 440,610,608 bytes.

**The signature.** In PowerShell:

```powershell
Get-AuthenticodeSignature .\ClawFactory-Secure-Setup.exe | Format-List Status, StatusMessage, SignerCertificate
```

Status must be `Valid`. The signer is `CN=Bret Mckinney`, signed through Azure
Trusted Signing and timestamped. Trusted Signing issues short-lived certificates, so
the signing certificate's own expiry date will already be in the past; the timestamp
is what keeps the signature valid, and `Status` is the field that answers the
question.

**The source.** Everything the installer bundles is in this repository. The build
refuses to run if any bundled file is not its committed bytes.

---

## Reporting a problem

For a security issue, email the address in [`SECURITY.md`](../SECURITY.md) rather
than opening a public issue.

For anything else, including a claim on this page that you think is wrong or reads as
more flattering than the facts support, an issue is welcome. An inaccurate claim in a
security product is a defect in the same sense as any other.
