# Release body for v1.4.4, drafted and not published

*This file is the text to paste into the GitHub Release body. It is a draft. Nothing
in this repository publishes it. Creating the tag and cutting the release are the
operator's actions, and the commands are in
`docs/session_reports/2026-08-29_v144_release_prep_closeout.md`.*

*Everything between the two rules below is the body itself.*

---

**ClawFactory Secure Setup v1.4.4. Free and open source under Apache-2.0.** There is
nothing to buy, no key to enter, no account to create, and the installer makes no
network call to any ClawFactory-operated server at any point.

A Windows installer that sets up a hardened runtime for an AI coding agent: a WSL2
sandbox running as a non-privileged account, Windows drive automounting disabled, an
operating-system firewall scoped to that account, a loopback-only gateway with a
Windows inbound block, and a safety-rules file that is root-owned, read-only and
hash-pinned at install.

**Read the full notes before installing:
[`docs/RELEASE_NOTES_v1.4.4.md`](https://github.com/BuzzardsBay/clawfactory-secure-setup/blob/v1.4.4/docs/RELEASE_NOTES_v1.4.4.md).**
They state what is enforced by the operating system, what is only enforced on the
gateway path, and every residual we know about. The residuals themselves are in
[`SECURITY_FINDINGS.md`](https://github.com/BuzzardsBay/clawfactory-secure-setup/blob/v1.4.4/SECURITY_FINDINGS.md),
which is the authority; if the two ever disagree, it wins.

## Three things to know before you download 440 MB

**1. Seven of Studio's eleven panels are not in this release.** You talk to your agent
in ClawChat, which the desktop icon opens, and you manage it in ClawFactory Studio,
which is a different window. Four Studio panels are real: Workspace, Approvals, Web
access and Recently deleted. Seven say on their own page that they are not in this
release: Templates, Files, Activity, Chat, Agents, Skills and Settings. Studio's own
Chat panel is one of the seven, and Templates is the first item in its navigation.

**2. Your data does reach your model provider.** That is what a hosted AI agent is.
The sandbox runs on your machine; the model does not. What is gated by approval is
email, and only email.

**3. Root ends everything.** Every control is enforced by the operating system against
one unprivileged identity. Root inside the sandbox, or an Administrator on Windows,
can remove all of them. The threat model is a hostile agent running unprivileged.

## Three disclosures

These are stated here rather than left in the notes for you to find.

**One approval guarantee has never been measured, on any release.** After you approve
a message, if the source attachment is rewritten before the message is sent, do the
approved bytes go or the rewritten ones? That comparison has never been made, on any
release of this product, on any machine. The surrounding mechanism is proven: enqueue,
approval, single-use approval, payload hash binding at approval time, the receipt, the
staging purge, and the refusal of a replayed approval. The end-to-end comparison was
never made because nothing ever arrived, and the reason is a limitation in our test
rig rather than a product failure: against an unencrypted mail sink the broker
correctly refuses to submit a credential, and against an encrypted sink with a
throwaway certificate authority the bundled runtime will not trust the certificate. So
the product behaves correctly in both directions and the harness cannot reach the
assertion.

**With the software-source switch on, GitHub fetches can fail and succeed on retry.**
Measured across 96 attempts on 8 toolchain hosts, 12 each: four hosts answered on
every attempt, `codeload.github.com` answered 10 of 12, `api.clawhub.ai` 9 of 12,
`github.com` 7 of 12, and `api.github.com` 6 of 12. **The mechanism is inferred and
labelled as such** in the notes: we believe the firewall holds a snapshot of resolved
addresses while those services answer from a rotating pool, but nothing in any run
measures the pool. The split is measured; the cause is not. **This does not affect the
route to your model provider**, which is allowlisted separately and measured at 12 of
12 in the same run. Turning the switch off still reliably blocks.

**Five shipped scripts render em dashes as garbage in seven customer-visible places.**
They are saved as UTF-8 without a byte-order mark, and Windows PowerShell 5.1 decodes
a mark-less script as the ANSI codepage. Five of the seven are in the dialog explaining
why renaming your assistant is not supported yet; two are in the bootstrap script. It
is cosmetic. Nothing about the sandbox, the firewall, the guards, the gateway or
containment is implicated. It is shipping in this release and is scheduled for v1.5
with a build gate that closes the class rather than the instance.

## What changed

Three shipped behaviour changes, all in the direction of the product doing what it
says. No security boundary was moved.

- **The kill switch works.** On every release before this one, both of the commands it
  sent into the sandbox died on a quoting fault and it printed a success banner
  anyway. It now stops the gateway and any running turn, counts the agent's processes,
  and reports only what that count supports, exiting non-zero when it cannot confirm.
- **Switching model provider works at all.** The script died before changing anything,
  for every provider, on an unescaped variable inside four of its own explanatory
  comments.
- **The provider switch tells the truth about Ollama**, replacing an unconditional
  success line with a warning when the model is not actually installed.
- **A ninth build gate** parses every shipped script at build time and fails the build
  if any of them references a variable the file never defines. That is the class of
  defect that made the provider switch inert.

The releases numbered 1.4.2 and 1.4.3 were built and signed but never published. They
are superseded by this one.

## Validation

Validated on four clean cloud machines built from a stock Windows image, installed the
way a customer installs, using this exact signed binary. **No product defect was found
on any of them.** Every block assertion carries a positive control that must succeed in
the same run, and a control that did not fire voids the result rather than producing a
verdict.

The record of what went wrong during development, including the defects found in our
own test instruments during this cycle and how many of them would have produced false
findings, is in
[`docs/FAILURE_CATALOGUE.md`](https://github.com/BuzzardsBay/clawfactory-secure-setup/blob/v1.4.4/docs/FAILURE_CATALOGUE.md).

## The download, and how to verify it

**`ClawFactory-Secure-Setup.exe`**

| | |
|---|---|
| Size | **440,610,608 bytes** |
| SHA-256 | **`6e65560325cb6d7d3fea204ebb72876b3b113cbbfe9f2fa4f94113237e9eb4d1`** |
| Signature | Authenticode, Azure Trusted Signing, `CN=Bret Mckinney`, timestamped |
| Built from | commit `25945d5` |

Check the digest:

```powershell
Get-FileHash -Algorithm SHA256 .\ClawFactory-Secure-Setup.exe
```

Check the signature:

```powershell
Get-AuthenticodeSignature .\ClawFactory-Secure-Setup.exe | Format-List Status, StatusMessage, SignerCertificate
```

`Status` must read `Valid`. Trusted Signing issues short-lived certificates, so the
signing certificate's own expiry date will already be in the past; the timestamp is
what keeps the signature valid, and `Status` is the field that answers the question.

Windows SmartScreen may still show a warning until the signing identity accumulates
reputation. Verify the digest above before choosing to run it.

## Requirements

Windows 10 version 2004 or later, or Windows 11. Administrator privileges. 16 GB RAM
recommended and 8 GB minimum. 50 GB free disk. Hardware virtualization enabled in
firmware for WSL2, with an automatic fallback to WSL1 if it is unavailable. Allow 10 to
20 minutes; the installer reboots once if Windows features have to be enabled, and
resumes on its own.

## Reporting

For a security issue, email the address in
[`SECURITY.md`](https://github.com/BuzzardsBay/clawfactory-secure-setup/blob/v1.4.4/SECURITY.md)
rather than opening a public issue. For anything else, including a claim in these notes
that you think is wrong or reads as more flattering than the facts support, an issue is
welcome.

---

*End of release body.*
