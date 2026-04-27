# PERSONAS.md — Marketing briefs for ClawFactory Secure Setup

Twelve persona-specific briefs grounded in the actual `setup.ps1` steps. The installer ships a *hardened OpenClaw runtime* — WSL2 + rootless Docker + nftables egress firewall + loopback-only gateway + DPAPI-backed key + Kill Switch — and **nothing else**. Empty agent directories, no skills installed, no chat UI. Personas where that's a real gap are flagged.

---

## 1. Retail investor / trader

**PERSONA:** Self-directed retail trader running a Schwab/IBKR/Fidelity account from a Windows desktop.
**THE NEED:** They want to throw 10-Ks, earnings transcripts, and Reddit DD into an LLM, but the same Windows account holds their brokerage cookies, 2FA backups, and tax records — and a leak would ruin them.
**WHAT THIS INSTALLER SOLVES FOR THEM:** WSL `automount=false` means the agent has zero visibility into the Windows filesystem (no `C:\Users\me\Downloads\1099.pdf`); the nftables egress rule scoped to `clawuser`'s UID drops every outbound TCP except the one provider host they picked at install; the API key sits in DPAPI, not in a `.env` file the agent could grep.
**THE HOOK:** Got tired of pasting 10-Ks into ChatGPT and worrying about my brokerage cookies — set up a sandboxed agent box where the LLM literally can't see anything outside its own folder.
**DISTRIBUTION TARGET:** r/algotrading.
**GAP:** Real. The installer ships zero trading-specific agents — they'd be running raw `openclaw` CLI to talk to their LLM and writing their own scripts. This audience often can't.

---

## 2. Academic scientist (wet lab or computational)

**PERSONA:** Postdoc or PI running computational analysis on a lab Windows workstation, often with embargoed data, IRB-restricted datasets, or unpublished collaborator drafts.
**THE NEED:** They want AI help with literature review, code, and data wrangling, but department IT has banned cloud LLMs because nobody can prove the prompts aren't being trained on.
**WHAT THIS INSTALLER SOLVES FOR THEM:** Ollama option = fully local inference, zero outbound calls (egress firewall + loopback-only gateway prove it); WSL `automount=false` means embargoed `.csv`s on the Windows side never enter the agent's view; SHA-256-pinned fetch of `openclaw.ai/install.sh` gives IT a verifiable provenance story.
**THE HOOK:** Department blocked every cloud LLM, so I built my own — Ollama in a sandboxed WSL box, no internet egress, IT signed off in twenty minutes.
**DISTRIBUTION TARGET:** r/labrats and r/AskAcademia.

---

## 3. Startup founder, pre-funding

**PERSONA:** Solo or two-person founder, no SOC2, no compliance officer, building B2B SaaS on a personal laptop.
**THE NEED:** They want AI agents for sales/ops/code, but can't afford a security audit and can't risk customer PII or Stripe keys leaking into a third-party AI vendor.
**WHAT THIS INSTALLER SOLVES FOR THEM:** API key in Windows Credential Manager (DPAPI, tied to the Windows user — never on disk inside WSL); nftables egress whitelist = only the provider host they chose, every other outbound TCP is dropped; rootless Docker + non-sudo `clawuser` means a misbehaving agent can't escalate; Kill Switch shortcut on the Start Menu.
**THE HOOK:** Pre-funding, SOC2 wasn't on the menu — got a hardened local agent runtime running in an afternoon, customer data and Stripe keys never leave the box.
**DISTRIBUTION TARGET:** r/startups and r/indiehackers.

---

## 4. VC analyst

**PERSONA:** Junior associate at a Sand Hill firm reading 200 decks a week from a corporate laptop.
**THE NEED:** Compliance won't let them upload founder decks to ChatGPT (NDA-laden, often containing third-party customer data), but their job depends on speed.
**WHAT THIS INSTALLER SOLVES FOR THEM:** Loopback-only gateway on `127.0.0.1:8787` plus a Windows Firewall inbound-deny rule means the runtime is unreachable from the LAN; the egress firewall caps outbound to a single provider host, so a deck never lands on an unvetted endpoint; their *own* API key in DPAPI keeps the firm's vendor list clean.
**THE HOOK:** Compliance flagged my ChatGPT usage on deck reads — stood up a local agent box with a literal kill switch, audit went from a week to a meeting.
**DISTRIBUTION TARGET:** r/venturecapital.
**GAP:** Real. No deck-parsing agent ships. The analyst would still be doing the reading; this just buys them a defensible substrate to build on. If they aren't technical, they can't.

---

## 5. Independent consultant

**PERSONA:** Solo strategy/data/code consultant juggling 3–5 clients, each with a "no public LLM" clause buried in their MSA.
**THE NEED:** Their MSAs technically forbid pasting client data into hosted AI; honoring that costs them billable hours every week.
**WHAT THIS INSTALLER SOLVES FOR THEM:** Ollama option keeps every token on the client's laptop; egress firewall provides a screenshot-able artifact for the inevitable "prove it" conversation with the client's CISO; per-provider switch means one runtime serves clients with different vendor policies (just rotate via the Switch AI Provider shortcut).
**THE HOOK:** Three clients had "no cloud LLM" clauses, my hours were getting eaten — got Ollama running in a sandboxed WSL box and pointed the firewall config at it when the CISO asked.
**DISTRIBUTION TARGET:** r/consulting.
**GAP:** Real. The consultant has to write or BYO every agent. The installer is the substrate, not the work product.

---

## 6. Logistics / supply chain manager

**PERSONA:** Mid-career ops manager at a mid-market 3PL or shipper, running Windows on a corporate laptop, stuck between EDI feeds, vendor portals, and Excel.
**THE NEED:** Vendor contracts forbid uploading shipment data to third-party services; their team's reconciliation work is screaming for automation but every cloud AI tool fails the contract review.
**WHAT THIS INSTALLER SOLVES FOR THEM:** Local-first runtime (especially Ollama) means EDI payloads never leave the machine; egress allowlist gives Procurement a one-page artifact for the vendor risk file; SHA-256 pin on the upstream installer and MIT license remove the "is this software trustworthy" objection.
**THE HOOK:** Vendor contracts blocked every cloud AI tool I tried — built a local agent runtime in a weekend, started by killing thirty hours a week of EDI reconciliation.
**DISTRIBUTION TARGET:** r/supplychain.
**GAP:** Severe. This audience is mostly non-technical, and the installer drops you at a `wsl` prompt with no UI and no agents. Realistically, this persona is reachable only via a managed-service partner.

---

## 7. Solo SaaS developer

**PERSONA:** Building and operating a small SaaS solo, runs prod migrations from their laptop, has been burned by a runaway AI tool before.
**THE NEED:** They want Claude-Code-style agents wired into their dev loop without giving an autonomous loop access to their prod database credentials, ssh keys, or `~/.aws/credentials`.
**WHAT THIS INSTALLER SOLVES FOR THEM:** WSL `automount=false` + non-sudo `clawuser` + rootless Docker = the agent literally cannot read `C:\Users\me\.aws\` or `~/.ssh\id_rsa`; loopback-only gateway means a prompt injection in a third-party doc can't pivot the agent to call out; Kill Switch is one click away.
**THE HOOK:** Got paranoid an agent would touch my prod migrations — set up a runtime where the LLM literally cannot see `~/.aws` or my Stripe keys, and there's a kill switch on the start menu.
**DISTRIBUTION TARGET:** r/SaaS and r/indiehackers.

---

## 8. Security researcher

**PERSONA:** Pentester, red-teamer, or AI-safety researcher studying agent behavior, prompt injection, and lateral movement.
**THE NEED:** They need a deliberately air-gapped, instrumented agent runtime to probe — and most "local AI" stacks are ad-hoc enough that any finding is dismissed as a config bug.
**WHAT THIS INSTALLER SOLVES FOR THEM:** Pretty much purpose-built — UID-scoped nftables egress rule, loopback-only gateway, hash-pinned upstream installer, hash-pinned `SOUL.md` (mode 444), no-sudo non-root user, rootless Docker, MIT license, idempotent + rollback, every step logged to `%ProgramData%\ClawFactory\install.log`. They can fork the `.ps1` and audit every line.
**THE HOOK:** Built a deliberately constrained OpenClaw box for prompt-injection research — UID-scoped egress to one IP, loopback gateway, SOUL hash-pinned, full setup.ps1 on the GitHub.
**DISTRIBUTION TARGET:** r/netsec and r/AskNetsec.

---

## 9. Medical professional (clinical or research)

**PERSONA:** Physician, resident, or clinical researcher who has been told "don't use ChatGPT for anything patient-facing, ever."
**THE NEED:** They want AI for literature review, drug-interaction lookup, study design — uses where their hospital's BAA-less agreements with OpenAI/Anthropic legally bar them.
**WHAT THIS INSTALLER SOLVES FOR THEM:** Ollama option = inference happens entirely on the doctor's personal device, never touching a cloud provider; egress firewall + loopback gateway are auditable controls they can show their compliance officer; the runtime is on a personal laptop, fully outside the hospital network.
**THE HOOK:** Hospital banned ChatGPT after the third leak rumor — for literature review on my home machine, set up a fully local agent runtime that has no internet egress at all.
**DISTRIBUTION TARGET:** r/medicine and r/medicalschool.
**GAP:** Severe. This installer is **not HIPAA-suitable**, **not for PHI**, **not for clinical workflows**. Suitable only for personal/literature use on a personal device. Pitching it for clinical use would be reckless and the audience will (correctly) tear that pitch apart. Lead with the limitation.

---

## 10. Journalist / investigative reporter

**PERSONA:** Investigative reporter handling leaked documents, source-protection workflows, FOIA dumps.
**THE NEED:** They cannot put source documents into any cloud LLM — doing so risks subpoena, source identification, or the document being indexed somewhere the source can be tied to it.
**WHAT THIS INSTALLER SOLVES FOR THEM:** Ollama option means inference is fully local — no API calls, no logs at any third party, no provider-side retention; nftables egress + Windows Firewall inbound-deny + loopback-only gateway give a defensible "the document never left this machine" claim; WSL `automount=false` keeps the document corpus inside the WSL volume only.
**THE HOOK:** Couldn't paste source docs into anything cloud — got Ollama running inside a sandboxed WSL box where the model literally has no internet, kill switch on the start menu.
**DISTRIBUTION TARGET:** r/journalism, GIJN's Slack, OCCRP's contributor channels.

---

## 11. Enterprise IT manager evaluating agent infrastructure

**PERSONA:** Director-of-IT or principal engineer whose CISO just asked "can we deploy AI agents safely?"
**THE NEED:** They need a working, opinionated reference implementation to point internal AppSec at — something concrete enough to argue *with* instead of arguing *about*.
**WHAT THIS INSTALLER SOLVES FOR THEM:** Every default in `setup.ps1` is the kind of control a security review wants and a vendor pitch deck never delivers — UID-scoped nftables egress, loopback-bound gateway, Windows Firewall inbound-deny on `8787`, no-sudo user, rootless Docker, hash-pinned upstream script, hash-pinned safety policy, Kill Switch shortcut, MIT license (no procurement). It's a reference architecture in 932 lines of PowerShell.
**THE HOOK:** CISO wanted a baseline for AI agent rollout — pointed them at a 900-line setup.ps1 with literal nftables rules and a kill switch, two-week argument turned into a thirty-minute meeting.
**DISTRIBUTION TARGET:** r/sysadmin and r/cybersecurity; secondarily a CISO-channel Slack like Cyber-IT-ISAC.
**GAP:** Real but expected. This is a single-machine reference, not enterprise-deployable as-is. The pitch is "use this to anchor your internal standard," not "ship this to 5,000 endpoints."

---

## 12. Ambitious student (grad or undergrad)

**PERSONA:** CS or quantitative-major student who wants to learn agent development without paying $200/mo for Claude Pro and without their student visa or financial-aid status getting tangled up in a foreign-API audit.
**THE NEED:** They need real hands-on agent-development practice on a $400 laptop with no recurring cost.
**WHAT THIS INSTALLER SOLVES FOR THEM:** Ollama option = `$0` and runs `llama3.1:8b` on consumer hardware; the hardened defaults — non-sudo `clawuser`, rootless Docker, egress firewall, loopback gateway — teach what production-grade isolation actually looks like; MIT license means they can fork the `.ps1` for their thesis.
**THE HOOK:** Couldn't justify $20/mo for ChatGPT Plus — got llama3.1 running in a sandboxed WSL setup where the agent can't reach the internet, learning more about systems hardening than my OS class taught.
**DISTRIBUTION TARGET:** r/learnprogramming, r/cscareerquestions, r/MachineLearning.

---
