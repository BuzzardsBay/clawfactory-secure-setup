# Sending email: `clawfactory-send`

User-facing reference for the approval-gated email capability (v1 Guard 2).

---

## 1. What it is

Your ClawFactory agent has one way to send email, and it is not a way it can use on its
own. A command called `clawfactory-send` sits on the agent's PATH inside the sandbox. When
the agent runs it, the message is handed to a separate service that runs as root, outside
the agent's reach, and it stops there. It waits for you.

The guarantee:

> Your agent can write an email. It cannot send one. Every message waits for you, and
> approving it sends exactly that message, once.

And the boundary that goes with it, every time the mechanism is described:

> This covers email. It is not a claim that no data can leave your machine: your agent talks
> to a hosted AI model, and anything it can read it can send there.

Both sentences matter. The first is what the guard does. The second is what it does not do,
and no amount of email gating changes it.

## 2. Why your agent will not offer to email things

This is deliberate, and it is a security property rather than a missing feature.

The agent is not told that `clawfactory-send` exists. Ask it in plain language to email
someone and it will not go looking for the command, and it will not improvise some other way
to get a message out. That second half is the important one: a fresh install was tested on
exactly this and the agent reached for no alternative transport at all.

An agent that knows it can send email will offer to send email. Offers become a stream of
approval requests, and a stream of approval requests is how people learn to click Approve
without reading. A capability whose entire premise is that a human reads each message is
safest when it never fires unless a human asked for it first.

So the capability is real, it works, and you drive it.

## 3. How to use it

Tell your agent to use the command by name. That is the whole trick.

```text
Use clawfactory-send to email alice@example.com with the subject
"Q3 summary" and the body of the report you just wrote.
```

```text
Use clawfactory-send to email bob@example.com the file
/workspaces/<your-workspace>/report.pdf as an attachment.
```

The agent then runs something equivalent to:

```text
clawfactory-send --to alice@example.com --subject "Q3 summary" --body-file draft.txt
clawfactory-send --to bob@example.com --subject "Report" --body "Attached." \
                 --attach /workspaces/<your-workspace>/report.pdf
```

`--to`, `--cc`, `--bcc` and `--attach` can each be repeated. The body comes from either
`--body` (inline text) or `--body-file` (a file the agent can read).

What comes back is not a sent message. It is a receipt saying the message is queued:

```text
status=pending
requestId=...
payloadHash=...
expiresAt=...

Queued for approval in ClawFactory Studio. Nothing has been sent.
```

## 4. What happens next

1. **The message is staged.** Attachments are copied, at that moment, into a root-owned
   staging area. What gets sent later is that copy. If the agent edits the original file
   afterwards, the edit changes nothing about what leaves your machine.
2. **A fingerprint is taken.** Every recipient, the subject, the body and every attachment
   are hashed together into one payload hash.
3. **It appears in ClawFactory Studio, under Approvals.** You open Studio from the Start
   Menu.
4. **You read it and decide.** Nothing happens until you do.

### The approval card

The card shows you the message, not a summary of the message:

- Every recipient, including Bcc.
- The subject.
- The body itself, in full.
- Every attachment: its name, its size, and the hash of the staged copy that would actually
  be transmitted.
- Which destination server it would go through, and how long you have left to decide.

There is no "approve all", no "always allow this recipient", and no bulk action. Those are
absent from the interface because they are absent from the machinery underneath it.

### Approve

**Approve and send** transmits exactly the message on the card, once. Your approval carries
the payload hash with it, so it is bound to what you were shown. If anything about the
message changed between the card rendering and your click, the approval is refused rather
than applied to something different. A used approval cannot be replayed.

After sending, the staged copies are purged and a receipt is written. A receipt records the
outcome of a request rather than only a successful send: an expired request produces one too,
carrying `sent: false` and the reason. For a send it also carries the provider's reference. A
denied request does not produce a receipt; the denial is recorded on the request itself. All
of these are readable only by root, and none of them record the body.

### Deny

**Deny** sends nothing and discards the staged attachments.

### The ten minute window

An approval request expires ten minutes after it is queued. This is long enough to read a
real message and short enough that a request left sitting overnight is not a standing
permission to send. An expired request is refused, and nothing is sent. If you want it after
all, ask your agent to queue it again.

## 5. Setting up your email account

Nothing can be sent at all until you tell ClawFactory which email account to send from. You
do this once, in Studio, under **Approvals > Email settings**: your SMTP server and port,
your username, your password or app password, and the address messages come from.

Two things about that password:

- It never travels as a command-line argument at any step. Anything on a command line is
  visible to every account on the machine, including the account your agent runs as. Your
  password goes over a private input channel the whole way down and lands in a file only
  root can read.
- It is never shown back to you, not even masked. Studio can tell you an account is
  configured and which address it sends from. It cannot tell you the secret, because it
  cannot read it.

Configuring the account is also the act that authorizes a destination. Before you do it, no
mail server is reachable and the system fails closed.

## 6. Limits

| Limit | Value |
|---|---|
| Approval window | 10 minutes |
| Attachment size | 25 MB each |
| Attachments per message | 20 |
| Recipients per message | 50 |
| Body size | 5 MB |

Exceeding a limit is refused out loud when the message is queued. A partial set is never
staged.

## 7. If something goes wrong

**"The send broker is unreachable."** The service that holds messages is not running.
Nothing was sent, and there is no fallback path for it to be sent by, because
`clawfactory-send` holds no mail credential and no mail transport of its own. Your draft is
preserved on disk so the work is not lost, and the error tells you where.

**A message did not arrive, and you are not sure whether you approved it in time.** An
expired request does not stay in Approvals. Once the ten minutes are up it disappears from
the panel, so an expired request and a request that was never queued look identical there.
Expired always means it was never sent. If you need to know which happened, ask your agent to
queue it again rather than trying to tell from the panel.

**Your agent says it cannot email.** That is expected until you name the command. See
section 3.

## 8. What your agent cannot do

Stated plainly, because these are the properties the guarantee rests on:

- It holds no mail credential, and cannot read the one you configured.
- It has no route to any SMTP server. Outbound mail ports are blocked for its account at the
  firewall, including to a mail server running on the machine itself.
- It cannot approve. The approval channel is a separate root-only socket its account cannot
  open, and approval is issued from Windows, as you, not from inside the sandbox.
- It cannot change an approved message. The bytes were copied and fingerprinted when it
  asked, not when you clicked.

---

## Status of this document

The mechanism described above is validated end to end, including real delivery to an
external mailbox on a different provider.

The Studio side of the flow was driven by hand on a clean install on 2026-08-13, on VM
cfv-160. Both surfaces work. Sections 4 and 5 describe observed behaviour.

What was exercised, and what was checked underneath it rather than taken from the interface:

- **Email settings.** An SMTP account was configured through the form. The credential landed
  root-owned at mode `600`, the agent's account was refused when it tried to read it, and the
  reply the panel receives carries the address and server but no secret-shaped field of any
  kind. The password was typed by a person and appears in no script or transcript.
- **The approval card.** It shows every recipient, the destination server, who queued it, a
  live countdown, the body in full, and each attachment with name, size and hash, without
  expanding anything. The attachment hash is displayed truncated to its first 16 characters.
- **Approve.** The message was transmitted and the provider returned a queue id. A receipt
  was written.
- **Deny.** Nothing was sent and the staged attachment bytes were discarded, verified by
  searching the store for the exact bytes with a control proving the search was not blind.
- **Expiry.** An unattended request expired. Nothing was sent, and staging was purged.

Two corrections this run produced, both to the text above rather than to the product:

1. **Section 7 was wrong about expired requests and has been corrected.** It said an expired
   request stays visible and is marked as such. It does not: the broker omits expired requests
   from the list the panel reads, so the panel shows "Nothing waiting" and gives the user no
   sign the request ever existed. The security property is intact, the message was not sent,
   but a user watching only the panel cannot tell an expired request from one that never
   happened.
2. **Section 4 under-described receipts and has been corrected.** A receipt is written for
   expired requests too, recording `sent: false` with the outcome, so it is an outcome record
   rather than only a send record. A denied request produces no receipt; the denial is
   recorded on the request itself, root-owned at mode `600`, with the hash the decision was
   bound to and the time it was made.

*Last reviewed 2026-08-13, after the cfv-160 panel smoke test.*
