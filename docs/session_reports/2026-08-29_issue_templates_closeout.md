# Close-out: issue templates and triage labels for the public repository

**Date:** 2026-08-29
**Repository:** `C:\Users\bmcki\ClawFactory-Secure-Setup` (`BuzzardsBay/clawfactory-secure-setup`)
**Branch:** `main`
**Commits:** `4edf4bb` (templates, labels), plus this close-out
**Shipped bytes:** none. No build, no release, no tag, no version bump. The installer, the site and every other repository are untouched.
**Public issue opened:** none.

---

## 0. Preamble clauses deleted, and why

The PROMPT 15 block in `docs/VALIDATION_PREAMBLE.md` was applied with the following clauses deleted, because this job provisions nothing and installs nothing.

| Deleted | Why it provably does not apply |
|---|---|
| `ENVIRONMENT, NOT NEGOTIABLE` | No Azure VM. No `az` call was made in this session. No VM size, image, resource group, RDP rule, auto-logon session or `/var/tmp` path is in scope. |
| `RESOURCE LEDGER` | No compute was provisioned, so there is nothing to sweep, nothing to deallocate, and no licence slot to release. |
| `HUMAN HANDOFF CARDS` | The job needs no human step. There is no provisioning, no password to set, and no reboot. |
| `MEASUREMENT DISCIPLINE` (the phase-runner clause) | `validation/interim-v120-phaselib.ps1` reports on a VM run. There is no run to report. **The parts of that section that are general were kept and used**: calibrate before measuring, a control that must fail, and read stderr rather than the transcript. See section 5. |
| `VERSION AND BUILD` | Nothing is built and nothing is released, so `released-versions.tsv` is not touched and the version gate is not engaged. |

Kept and applied in full: close-out is a gate; the four pre-flight checks; "if this prompt is wrong, say so before executing it"; shell and exit codes; **an audit regex is itself a probe**; credential hygiene; git.

**The citation clause added in `fa4423f` applies directly and was applied.** Every fact in the templates about what a user sees was checked against the file that actually ships or the surface that is actually served, not against the nearest local copy with a plausible name. This caught two errors before they were written into a template, both recorded in section 6.

---

## 1. Challenge to the prompt

Four things in the brief were wrong or did not hold. None of them blocked the job.

**1. `ClawFactory_Install_Lessons_Learned.md` does not contain user-facing install failures.** The brief says to read it and "pre-empt the failures already recorded there so a reporter can self-serve." The file is 71 KB and 30 numbered lessons, and it is a build-and-validation engineering record: `az.cmd` argument re-parsing, a WSL probe channel that fabricates passes, a class of too-short gateway cold-start timeouts, a PowerShell array literal that silently splits a string. A stranger installing on their own laptop hits none of these. The file was read; the six pre-emptions in the install template are therefore sourced from where user-facing failures actually are, which is `README.md` under Known limitations and System requirements, and `docs/RELEASE_NOTES_v1.4.4.md` under Installing. Each of the six is cited in section 4.

**2. There were two templates, not two plus a config that needed keeping.** The brief implies `config.yml` may or may not exist. It did, and it carried the single most false line in the directory: a contact link offering to sell a licence.

**3. `support@clawfactory.app` is correct, and was verified on the live surface rather than assumed.** `https://clawfactory.app/` returns HTTP 200 and the address appears four times in the served bytes, twice as a `mailto:` link, once in the footer and once in the body text about requesting additional access. This is the check the citation clause demands: this repository's own `docs/index.html` is a stale unpublished copy that serves nothing, so it was not consulted.

**4. Nothing in the brief would have opened a public issue or changed a repository setting beyond labels and templates, and nothing here did.** Creating three labels is the only repository-state change. The three form pages were opened in a browser to read them; `Create` was never pressed on any of them.

---

## 2. TASK 0: what was there, and what in it was false

### 2.1 The two templates and the config, verbatim as they stood at `fa4423f`

<details>
<summary><code>.github/ISSUE_TEMPLATE/bug_report.md</code> (deleted)</summary>

```markdown
---
name: Bug report
about: Report an installer or runtime problem
title: "[Bug] "
labels: bug
---

**Do NOT report security vulnerabilities here.** Email support@clawfactory.app instead (see SECURITY.md).

## What happened

A clear description of the problem and what you expected instead.

## Steps to reproduce

1.
2.
3.

## Environment

- ClawFactory version (installer filename or `--version`):
- Windows version (`winver`):
- RAM / free disk:
- Provider selected (claude / openai / grok / gemini / ollama):
- Hardware virtualization enabled (VT-x / AMD-V)? Did the install fall back to WSL1?

## Install log

Attach the install log:

```
C:\ProgramData\ClawFactory\install.log
```

If the install failed, also attach:

```
C:\ProgramData\ClawFactory\install-result.txt
```

(Redact any API keys before attaching. The installer does not write keys to these logs, but double-check.)

## Smoke test output (if the install completed)

```
powershell -ExecutionPolicy Bypass -File "C:\Program Files\ClawFactory\smoke-test.ps1"
```

Paste the output.
```

</details>

<details>
<summary><code>.github/ISSUE_TEMPLATE/support_request.md</code> (deleted)</summary>

```markdown
---
name: Support request
about: Questions about installing, configuring, or using ClawFactory
title: "[Support] "
labels: support
---

**Do NOT post security vulnerabilities here.** Email support@clawfactory.app instead (see SECURITY.md).

## Your question

What are you trying to do, and where are you stuck?

## Environment

- ClawFactory version:
- Windows version (`winver`):
- Provider selected (claude / openai / grok / gemini / ollama):

## What you have tried

Commands run, wizard choices made, anything from the Known limitations section of the README you have already checked.

## Relevant logs (optional)

If useful, attach the install log (redact API keys first):

```
C:\ProgramData\ClawFactory\install.log
```
```

</details>

<details>
<summary><code>.github/ISSUE_TEMPLATE/config.yml</code> (replaced)</summary>

```yaml
blank_issues_enabled: false
contact_links:
  - name: Security vulnerability (private)
    url: https://github.com/BuzzardsBay/clawfactory-secure-setup/blob/main/SECURITY.md
    about: Do not file security issues publicly. Email support@clawfactory.app - see SECURITY.md.
  - name: Purchase / licensing
    url: https://clawfactory.app
    about: Buy a license or ask pre-sales questions at clawfactory.app.
```

</details>

### 2.2 Every sentence in them that is false now

| # | File | The sentence | Why it is false |
|---|---|---|---|
| 1 | `config.yml` | `name: Purchase / licensing` | There is nothing to purchase. The licence check was removed at v1.4.0 and both repositories are Apache-2.0. |
| 2 | `config.yml` | `about: Buy a license or ask pre-sales questions at clawfactory.app.` | The same, stated as an instruction to a stranger. "Pre-sales" describes a relationship that does not exist. |
| 3 | `support_request.md` | `name: Support request` | There is no support arrangement to make a request against. |
| 4 | `support_request.md` | `about: Questions about installing, configuring, or using ClawFactory` | Not false in itself, but it sits under the "Support request" name and inherits its implication. |
| 5 | `support_request.md` | `title: "[Support] "` | Every issue filed through it was stamped as a support ticket. |
| 6 | `support_request.md` | `labels: support` | **Worse than false: it never worked.** There has never been a `support` label on this repository, and GitHub silently drops a template label that does not exist. Every issue filed through this template for the life of the template arrived unlabelled, and the template looked correct. |
| 7 | `support_request.md` | "anything from the Known limitations section of the README you have already checked" | Points a reporter at a section but names none of the three shipped disclosures, which is the specific thing that wastes a reporter's evening. |
| 8 | `bug_report.md` | `powershell -ExecutionPolicy Bypass -File "C:\Program Files\ClawFactory\smoke-test.ps1"` | **The path is wrong.** `ClawFactory-Secure-Setup.iss:61` installs `smoke-test.ps1` to `{app}\resources`, and `DefaultDirName={autopf}\ClawFactory` at line 28, so the shipped path is `C:\Program Files\ClawFactory\resources\smoke-test.ps1`. There is no copy at the directory root. A reporter following this gets a file-not-found and no output. |
| 9 | `bug_report.md` | "ClawFactory version (installer filename or `--version`)" | Nothing named `--version` exists. There is no ClawFactory CLI with a version flag; the version is in Windows Settings under Installed apps and in the installer filename. |
| 10 | `bug_report.md` | "Attach the install log" | Not false, but it is the instruction this job exists to reverse. The log carries Windows paths, the reporter's Windows account name and their machine name. Asking a stranger to attach it to a public issue is asking them to publish those. |
| 11 | `bug_report.md` | "(Redact any API keys before attaching. ...)" | The warning was present but buried at the bottom of a parenthetical, after the instruction to attach. It is now the first thing on every template. |
| 12 | both `.md` files | Neither says the product is free, unsupported, or that a reply is not guaranteed. | An omission rather than a false sentence, but it is the one that sets a stranger's expectations wrongly. |

Note on item 8: **the same wrong path is in `README.md:79` and was not fixed here.** It is a shipped documentation defect outside this job's scope. It is recorded in section 6.

### 2.3 Labels before the change, read from the API

```
bug               #d73a4a  Something isn't working
documentation     #0075ca  Improvements or additions to documentation
duplicate         #cfd3d7  This issue or pull request already exists
enhancement       #a2eeef  New feature or request
good first issue  #7057ff  Good for newcomers
help wanted       #008672  Extra attention is needed
invalid           #e4e669  This doesn't seem right
question          #d876e3  Further information is requested
wontfix           #ffffff  This will not be worked on
```

Nine labels, all GitHub defaults. Not one was created for this project. `install`, `known-issue`, `needs-info` and `support` were all absent, which is how the `labels: support` line in the old template came to be inert.

### 2.4 The three shipped disclosures

Read from `docs/RELEASE_NOTES_v1.4.4.md` (section "Three disclosures", lines 162 to 259) and cross-checked against the **published** release body, which was fetched from the API rather than read locally. `docs/RELEASE_v1.4.4_GITHUB_BODY.md` says of itself that it is a draft and that nothing in the repository publishes it; a diff of the published body at tag `v1.4.4` against that file's body block differs only in leading and trailing whitespace, so the draft is in fact the published text.

`docs/FAILURE_CATALOGUE.md` was read. It contains no shipped disclosure. It is a twelve-class record of what went wrong during development, including defects found in our own test instruments, and it is correctly linked from the release as context rather than as a list of live product caveats. It is not linked from the templates for that reason.

1. **One approval guarantee has never been measured, on any release.** After an approval, if the source attachment is rewritten before the message is sent, nothing establishes whether the approved bytes or the rewritten bytes go. The surrounding mechanism is proven; the end-to-end comparison was never reached, because the test rig cannot get a message to arrive.
2. **With the software source switch on, GitHub fetches can fail and succeed on retry.** 96 attempts across 8 toolchain hosts. Four hosts answered every time; `github.com` answered 7 of 12 and `api.github.com` 6 of 12. The split is measured and the cause is inferred and labelled as such. The route to the model provider is unaffected and measured at 12 of 12.
3. **Five shipped scripts render em dashes as garbage in seven customer-visible places.** UTF-8 without a byte-order mark, decoded by Windows PowerShell 5.1 as the ANSI codepage. Five of the seven are in the dialog explaining why renaming your assistant is not supported yet. Cosmetic. Scheduled for v1.5 with a build gate that closes the class.

All three now open all three templates, with links, which is TASK 1.4.

---

## 3. Pre-flight

**1. Comprehension.** Four files change under `.github/ISSUE_TEMPLATE/`: two markdown templates are deleted, three YAML issue forms are added, `config.yml` is rewritten. Three labels are created on the repository. Nothing depends on these files at build time: they are not in `[Files]` in `ClawFactory-Secure-Setup.iss`, so nothing about them can reach a customer machine. Checked against the repository rather than the brief: `git ls-files` shows the directory held exactly the three files named, and a tree-wide grep for `ISSUE_TEMPLATE` finds no script, gate or workflow that reads it.

**2. Dependency census.** Two things are removed.

*The `support` label reference.* WHO uses it: one site, `support_request.md:6`, and the label does not exist on the repository, so nothing downstream can be reading it either. WHEN is it needed: never; it was inert for the life of the file. Removing it removes nothing that worked.

*The "Purchase / licensing" contact link.* WHO uses it: one site, `config.yml:8-10`. A tree-wide grep for `licenses@clawfactory.app` and for pre-sales language finds no other issue-path site. WHEN is it needed: never again; the product went free at v1.4.0.

*The `support@clawfactory.app` address is NOT removed.* It appears at eight sites across the repository (`README.md:174`, `SECURITY.md:165`, `SECURITY_FINDINGS.md:180`, `CLAUDE_ClawFactory.md` twice, and the three template files). Only the three template sites are in scope and all three keep it. Removing it from a template while the README and `SECURITY.md` still point at it would have produced exactly the split-brain the census exists to catch.

**3. Failure-mode walk: what breaks if this works exactly as specified.** Three things, all accepted.

- **Required fields turn some reporters away.** An issue form with `required: true` on six fields will lose the reporter who cannot answer one of them. That is deliberate for bug and install, where an unanswerable report costs more than no report. It is why the third template exists, is short, and requires one field.
- **`blank_issues_enabled: false` means a stranger with something that fits none of the three has no escape hatch.** Confirmed on the rendered chooser: the blank issue entry is labelled "Maintainers only". Accepted, because "Question or feedback" is deliberately open enough to absorb anything, and because a blank box on a public repository is where the low-quality reports come from.
- **The disclosure block ages.** It is pinned to tag `v1.4.4`. When v1.5 ships, three links point at the previous release's notes. That is the correct failure direction: a pinned link keeps telling the truth about the release it names, whereas a `main` link would silently start describing something the reporter did not install. It does mean the templates are on the v1.5 checklist.

**4. Input-shape sweep.** The reader here is GitHub's issue-form parser, and the input is the four YAML files. Present: renders the form. Absent: GitHub falls back to the chooser without that entry. Empty: treated as malformed. Malformed: **the form is silently dropped and the reporter gets a blank issue box that looks like it worked.** That is the failure this job was warned about, it happened, and it is section 5.1. Wrong type: a `dropdown` whose `options` is a string rather than a list, or an option that YAML parses as a boolean rather than a string, both fail the same silent way; the validator checks both. Hostile is not a meaningful shape here, as the files are ours and are read only by GitHub.

---

## 4. TASK 1: what the templates now do, and where each fact came from

Three YAML issue forms replace two markdown templates. Forms rather than markdown because markdown asks and a form requires, and the whole point of the install template is that the diagnostic set arrives complete.

`bug_report.yml` asks for version, Windows version, clean-or-upgrade, surface, what happened, what was expected, exact error text, and the **path** of the install log. The surface list uses the real shipped names, taken from `ClawFactory-Secure-Setup.iss` `[Icons]` at lines 155 to 187: ClawChat (the desktop icon and Start Menu entry both point at `ClawChat.exe`), the Start Menu tools Kill Switch, Dashboard, Rename Your Assistant and Switch AI Provider, plus ClawFactory Studio, which the `.iss` installs de-elevated at `ssPostInstall` as a separate per-user application rather than as a `{group}` shortcut.

`install_failure.yml` asks for whether WSL2 was already present, whether the machine is company-managed, which step it stopped on, the exit code, how long it ran, and whether it rebooted. It pre-empts six documented behaviours that look like a failed install:

| Pre-emption | Source |
|---|---|
| It rebooted partway through and resumes on its own | `README.md:52`; release notes, Installing, step 4; the RunOnce `/resume` path at `ClawFactory-Secure-Setup.iss:904` |
| Allow 10 to 20 minutes | `README.md:52`; release notes, Installing, step 4 |
| Administrator privileges are required | `ClawFactory-Secure-Setup.iss:26` `PrivilegesRequired=admin`; `README.md:42` |
| SmartScreen "Unknown publisher", and the digest to check | `README.md:118`; the SHA-256 and signature block in the published release body |
| Hardware virtualization off falls back to WSL1 rather than failing | `README.md:45` and `README.md:119` |
| 50 GB free disk, 8 GB RAM minimum | `README.md:43-44` |

The exit-code field names `%ProgramData%\ClawFactory\install-result.txt`, which is the installer's own verdict file, read at `ClawFactory-Secure-Setup.iss:915`. The log path field names `%ProgramData%\ClawFactory\install.log`, which is where `resources/bootstrap.ps1:5` and `resources/post-install.ps1:17` write and what `resources/bootstrap.ps1:335` prints to the user at the end of an install. The bug template also names `%TEMP%\ClawFactory-Uninstall.log` for the uninstaller, from `resources/uninstall.ps1:47`.

`question.yml` is one required field and one optional one.

**The secrets warning is the first thing on every template** (TASK 1.1). It says do not paste an API key, says the repository is public and an issue cannot be truly unpublished, and says the install log carries paths, the Windows account name and the machine name. Both bug and install carry a required checkbox asserting no key is in the submission.

**No response time, fix or support is promised anywhere** (TASK 1.5). Every template ends its opening block with the same sentence: it is a free personal project under Apache-2.0, there is nothing to buy, there is no support arrangement, issues are read, a reply is not guaranteed. Bug and install add that neither is a fix.

**No em dashes** (TASK 1.5). Verified stronger than asked: all four files are pure ASCII, confirmed with `file` and with a byte-range grep whose canary is in section 5.2.

**`config.yml`** (TASK 1.6) keeps one private path, to `SECURITY.md`, whose `about` text names `support@clawfactory.app` and says plainly that a vulnerability filed publicly is disclosed to everyone the moment it is submitted. The address was verified on the live site, not inferred: see section 1, item 3. The second contact link points at the v1.4.4 release notes. The purchase link is gone.

---

## 5. TASK 3: verification, and the two instruments that turned out to be blind

### 5.1 The malformed-template failure actually happened, and was caught before push

The first draft of `bug_report.yml` and `install_failure.yml` did not parse. `placeholder: "%ProgramData%\ClawFactory\install.log"` is a double-quoted YAML scalar, in which `\C` is an invalid escape sequence. Both files were rejected, at line 143 and line 177 respectively.

**Had that been pushed, GitHub would have dropped both forms and served a blank issue box, which looks exactly like it worked.** It was caught because the files were parsed locally before the commit, with `js-yaml`, against a schema check for GitHub's issue-form rules. The fix was to switch to single-quoted scalars, in which backslashes are literal.

### 5.2 The validator was itself calibrated before it was trusted

Per the preamble clause that an audit instrument is itself a probe, the validator was run against three deliberately broken copies of a passing file. It caught all three and exited non-zero:

```
FAIL c1_badtype.yml:   body[4] bad type "dropdwon"  /  body[5] bad type "dropdwon"
FAIL c2_dupid.yml:     duplicate id "version"
FAIL c3_nooptions.yml: body[4] dropdown needs options
```

The em-dash sweep was calibrated the same way: a canary file containing a real U+2014 was written and the byte-range pattern found it, proving the pattern is not blind before its clean result on the four real files was believed. The anchor probe in 5.4 was calibrated against a deliberately wrong anchor, which it correctly reported missing.

### 5.3 Two instruments that produce plausible output and measure nothing

**GraphQL `issueTemplates` is blind to YAML issue forms.** Queried after the push, it returned an empty list. Read naively that says the three forms failed to parse. It does not. Three control repositories that certainly use YAML forms were queried:

| Repository | Template files | GraphQL `issueTemplates` |
|---|---|---|
| `nodejs/node` | `1-bug-report.yml`, `2-feature-request.yml`, `3-api-ref-docs-problem.yml`, `4-report-a-flaky-test.yml`, `config.yml` | empty |
| `github/docs` | `improve-existing-docs.yaml`, `improve-the-site.yml`, `partner-contributed-documentation.yml`, `config.yml` | empty |
| `vercel/next.js` | `1.bug_report.yml`, `4.docs_report.yml`, `config.yml` | empty |
| `cli/cli` (markdown control) | `bug_report.md` and two more `.md` | **returns all three** |

The field covers markdown templates only. An empty result from it carries no information about a forms repository, and the pre-change baseline it produced for this repository (which did return both old markdown templates) is what made the empty result look like a regression. It was discarded as an instrument.

**A signed-out fetch of the chooser is not possible.** TASK 3.2 asks for the listing "the way a stranger would see it", anonymously. GitHub answers `/issues/new/choose` with a redirect to `https://github.com/login?return_to=...` for any request without a session, and an API token does not authenticate the web UI either: the same request with `Authorization: Bearer <token>` also lands on the login page. **A signed-out stranger cannot see the chooser at all, because GitHub requires an account to file an issue.** The reachable anonymous surface is the raw published bytes, and those were fetched with no `Authorization` and no `Cookie` header, compared byte-for-byte against the local files, and re-validated as the fetched copies rather than the local ones:

```
bug_report.yml         HTTP=200 bytes=5886   IDENTICAL   OK  labels=["bug"]       12 body elements
install_failure.yml    HTTP=200 bytes=7365   IDENTICAL   OK  labels=["install"]   13 body elements
question.yml           HTTP=200 bytes=1962   IDENTICAL   OK  labels=["question"]   3 body elements
config.yml             HTTP=200 bytes=717    IDENTICAL   OK
```

### 5.4 What GitHub itself renders

Because neither instrument above answers the question, the chooser and all three form pages were opened in a signed-in browser and read. **No issue was created; `Create` was never pressed** (TASK 3.3).

The chooser renders, in order: **Bug report**, **Install failure**, **Question or feedback**, each with its description; **Blank issue (Maintainers only)**, which is `blank_issues_enabled: false` working; GitHub's own **Report a security vulnerability** entry, which comes from `SECURITY.md` existing; and both contact links with their full `about` text.

Each form page renders every field, every description and every required marker, and the metadata sidebar shows the label already applied, which is TASK 2.2 proven at the surface rather than inferred from the file:

| Form | Sidebar label shown before submit |
|---|---|
| Bug report | `bug`, Something isn't working |
| Install failure | `install`, Installer did not complete, or completed and reported failure |
| Question or feedback | `question`, Further information is requested |

This matters because a template label that does not exist is silently dropped, which is exactly what happened to `labels: support` for the life of the old template. The label being visible in the sidebar is the only check that distinguishes the two cases.

The three disclosure anchors were checked against the rendered release-notes page fetched anonymously, by looking for GitHub's `user-content-` anchor ids. All three present; the deliberately wrong control anchor absent.

### 5.5 Final label list, read back from the API after the change

```
bug               #d73a4a  Something isn't working
documentation     #0075ca  Improvements or additions to documentation
duplicate         #cfd3d7  This issue or pull request already exists
enhancement       #a2eeef  New feature or request
good first issue  #7057ff  Good for newcomers
help wanted       #008672  Extra attention is needed
install           #1d76db  Installer did not complete, or completed and reported failure
invalid           #e4e669  This doesn't seem right
known-issue       #fbca04  Already published in the release notes or SECURITY_FINDINGS.md
needs-info        #d4c5f9  Cannot be acted on until the reporter supplies more detail
question          #d876e3  Further information is requested
wontfix           #ffffff  This will not be worked on
```

Twelve labels. The six the brief asked for are all present: `bug`, `install`, `question`, `known-issue`, `needs-info`, `wontfix`. Three were created; `bug`, `question` and `wontfix` already existed as GitHub defaults and were reused rather than duplicated (TASK 2.1). Nothing was deleted, including the six defaults the brief did not ask for, because deleting a label deletes it from any issue carrying it and none of them is doing harm.

---

## 6. Found and deliberately not fixed

Both are outside the scope of this job, which is templates and labels.

**1. `README.md:79` gives the wrong path for the smoke test.** It says `C:\Program Files\ClawFactory\smoke-test.ps1`. `ClawFactory-Secure-Setup.iss:61` installs that script to `{app}\resources`, and `DefaultDirName={autopf}\ClawFactory` at line 28, so the shipped path is `C:\Program Files\ClawFactory\resources\smoke-test.ps1`. There is one `[Files]` entry for that script and no second copy. `README.md` is bundled and reachable from the Start Menu (`ClawFactory-Secure-Setup.iss:186`), so this is a shipped documentation defect: a customer following it gets a file-not-found. The old `bug_report.md` carried the same wrong command, which is how it was noticed. **The new templates do not ask a reporter to run the smoke test at all**, so nothing here propagates the error.

**2. `ClawFactory_Install_Lessons_Learned.md` holds no user-facing install failure modes.** Detailed in section 1, item 1. If the intent is that a reporter can self-serve from it, it does not currently serve that purpose and the README plus the release notes do.

---

## 7. Dispatch

Card **313** created via `POST https://avital-dispatch.up.railway.app/api/agent/update` with the `x-frontier-secret` header, from PowerShell, action `create`, status `done`. The secret was read from `C:\Projects\FrontierAI\.env` and never printed; its length was reported and nothing more.

---

## 8. Git

```
git status --short   (before staging)
 D .github/ISSUE_TEMPLATE/bug_report.md
 M .github/ISSUE_TEMPLATE/config.yml
 D .github/ISSUE_TEMPLATE/support_request.md
?? .github/ISSUE_TEMPLATE/bug_report.yml
?? .github/ISSUE_TEMPLATE/install_failure.yml
?? .github/ISSUE_TEMPLATE/question.yml
```

Six explicit `git add` calls, one per file. No `git add -A`. One commit, `4edf4bb`, pushed to `main`. **No tag.** All four files are `i/lf w/lf` under the repository's `text=auto eol=lf` attribute, so the committed blobs carry LF and the working tree matches.

**Deviation from TASK 4.2, stated rather than hidden.** The brief says one commit. This close-out is a second commit, because sections 5.3, 5.4 and 5.5 report verification that can only be performed after the templates are live on the default branch. A single commit would have required either writing the verification before performing it or omitting it.

---

## 9. The three finished templates, verbatim

Printed here so the operator can read exactly what a stranger sees without opening GitHub.

### 9.1 `.github/ISSUE_TEMPLATE/bug_report.yml`

```yaml
name: Bug report
description: Something ClawFactory does is wrong, or it stopped working after it was installed
title: "[Bug] "
labels: ["bug"]
body:
  - type: markdown
    attributes:
      value: |
        ## Before you write anything: do not paste secrets

        **Do not paste an API key, a provider key, or any part of one, anywhere in this
        issue.** This repository is public and an issue cannot be truly unpublished once
        it is filed. **The install log is not a safe thing to attach either.** It contains
        Windows paths, your Windows account name and your machine name, and you may not
        want those public. Give the log's path, not the log. If a maintainer needs the
        contents, that request can be made and you can decide then.

        If you believe you have found a **security vulnerability**, do not file it here at
        all. Email `support@clawfactory.app` instead. See
        [SECURITY.md](https://github.com/BuzzardsBay/clawfactory-secure-setup/blob/main/SECURITY.md).

        ---

        ## Three things are already known and published

        If you have hit one of these, it is not a new report and there is no need to write
        it up.

        1. **[One approval guarantee has never been measured](https://github.com/BuzzardsBay/clawfactory-secure-setup/blob/v1.4.4/docs/RELEASE_NOTES_v1.4.4.md#1-one-approval-guarantee-has-never-been-measured-on-any-release).**
           If an approved message's source attachment is rewritten before the message is
           sent, nothing establishes which bytes go.
        2. **[With the software source switch on, GitHub fetches can fail and succeed on retry](https://github.com/BuzzardsBay/clawfactory-secure-setup/blob/v1.4.4/docs/RELEASE_NOTES_v1.4.4.md#2-with-the-software-source-switch-on-github-fetches-can-fail-and-succeed-on-retry).**
           Measured, intermittent, and it does not affect the route to your model provider.
        3. **[Five shipped scripts render em dashes as garbage in seven places](https://github.com/BuzzardsBay/clawfactory-secure-setup/blob/v1.4.4/docs/RELEASE_NOTES_v1.4.4.md#3-five-shipped-scripts-render-em-dashes-as-garbage-in-seven-places).**
           Cosmetic. Mostly in the dialog that explains why renaming your assistant is not
           supported yet. Fix is scheduled for v1.5.

        The longer lists are the
        [v1.4.4 release notes](https://github.com/BuzzardsBay/clawfactory-secure-setup/blob/v1.4.4/docs/RELEASE_NOTES_v1.4.4.md)
        and
        [SECURITY_FINDINGS.md](https://github.com/BuzzardsBay/clawfactory-secure-setup/blob/v1.4.4/SECURITY_FINDINGS.md).

        ---

        ClawFactory is a free personal project under Apache-2.0. There is nothing to buy
        and there is no support arrangement. Issues are read. A reply is not guaranteed,
        and neither is a fix.

  - type: checkboxes
    id: preflight
    attributes:
      label: Before filing
      options:
        - label: I have read the three disclosures above and this is not one of them.
          required: true
        - label: There is no API key, or any part of one, in what I am about to submit.
          required: true

  - type: input
    id: version
    attributes:
      label: ClawFactory version
      description: >-
        Windows Settings, Installed apps. The entry reads "ClawFactory Secure Setup
        version 1.4.4" or similar. The installer filename you downloaded is also fine.
      placeholder: "1.4.4"
    validations:
      required: true

  - type: input
    id: windows
    attributes:
      label: Windows version
      description: Press Windows+R, type `winver`, and copy the version and build line.
      placeholder: "Windows 11 Home 24H2, build 26100.1742"
    validations:
      required: true

  - type: dropdown
    id: install_kind
    attributes:
      label: Was this a clean install or an upgrade?
      options:
        - Clean install, ClawFactory had never been on this machine
        - Clean install, but ClawFactory had been installed and uninstalled before
        - Upgrade over an existing ClawFactory install
        - I do not know
    validations:
      required: true

  - type: dropdown
    id: surface
    attributes:
      label: Where did the problem appear?
      options:
        - ClawChat, the window the desktop icon opens
        - ClawFactory Studio, the separate workbench window
        - The installer
        - The uninstaller
        - A Start Menu tool (Kill Switch, Switch AI Provider, Rename Your Assistant, Dashboard)
        - Somewhere else, described below
    validations:
      required: true

  - type: input
    id: which_tool
    attributes:
      label: If it was a Start Menu tool, which one?
      placeholder: "Switch AI Provider"

  - type: textarea
    id: what_happened
    attributes:
      label: What happened
      description: What you did, and what the product did.
    validations:
      required: true

  - type: textarea
    id: what_expected
    attributes:
      label: What you expected instead
    validations:
      required: true

  - type: textarea
    id: error_text
    attributes:
      label: The exact text of any error
      description: >-
        Copy it rather than describing it, and check it for keys, paths and machine names
        before you submit. Leave this empty if there was no error message.
      render: text

  - type: input
    id: log_path
    attributes:
      label: Install log path
      description: >-
        The path only. Do not paste the log. It is normally
        `%ProgramData%\ClawFactory\install.log`. If yours is somewhere else, say where.
        The uninstaller writes to `%TEMP%\ClawFactory-Uninstall.log` instead.
      placeholder: '%ProgramData%\ClawFactory\install.log'

  - type: textarea
    id: anything_else
    attributes:
      label: Anything else
      description: Optional.
```

### 9.2 `.github/ISSUE_TEMPLATE/install_failure.yml`

```yaml
name: Install failure
description: The installer did not finish, or finished and reported failure
title: "[Install] "
labels: ["install"]
body:
  - type: markdown
    attributes:
      value: |
        ## Before you write anything: do not paste secrets

        **Do not paste an API key, a provider key, or any part of one, anywhere in this
        issue.** This repository is public and an issue cannot be truly unpublished once
        it is filed. **The install log is not a safe thing to attach either.** It contains
        Windows paths, your Windows account name and your machine name, and you may not
        want those public. Give the log's path, not the log.

        If you believe you have found a **security vulnerability**, do not file it here at
        all. Email `support@clawfactory.app` instead. See
        [SECURITY.md](https://github.com/BuzzardsBay/clawfactory-secure-setup/blob/main/SECURITY.md).

        ---

        ## Three things are already known and published

        1. **[One approval guarantee has never been measured](https://github.com/BuzzardsBay/clawfactory-secure-setup/blob/v1.4.4/docs/RELEASE_NOTES_v1.4.4.md#1-one-approval-guarantee-has-never-been-measured-on-any-release).**
        2. **[With the software source switch on, GitHub fetches can fail and succeed on retry](https://github.com/BuzzardsBay/clawfactory-secure-setup/blob/v1.4.4/docs/RELEASE_NOTES_v1.4.4.md#2-with-the-software-source-switch-on-github-fetches-can-fail-and-succeed-on-retry).**
        3. **[Five shipped scripts render em dashes as garbage in seven places](https://github.com/BuzzardsBay/clawfactory-secure-setup/blob/v1.4.4/docs/RELEASE_NOTES_v1.4.4.md#3-five-shipped-scripts-render-em-dashes-as-garbage-in-seven-places).**

        None of the three stops an install. The full lists are the
        [v1.4.4 release notes](https://github.com/BuzzardsBay/clawfactory-secure-setup/blob/v1.4.4/docs/RELEASE_NOTES_v1.4.4.md)
        and
        [SECURITY_FINDINGS.md](https://github.com/BuzzardsBay/clawfactory-secure-setup/blob/v1.4.4/SECURITY_FINDINGS.md).

        ---

        ## Six things that look like a failed install and are not

        Please check these first. Each is documented behaviour.

        - **It rebooted the machine partway through.** That is expected when Windows
          features have to be enabled. It resumes on its own after you log back in. Give
          it time before deciding it died.
        - **It has been running a long time.** Allow 10 to 20 minutes, and longer on a
          slow disk. A bundled 6 GB Linux image is being unpacked.
        - **It was not run as administrator.** Administrator privileges are required.
          Right-click the downloaded file and choose Run as administrator.
        - **SmartScreen said "Unknown publisher".** The released binary is Authenticode
          signed and timestamped. Verify the SHA-256 published on the
          [release page](https://github.com/BuzzardsBay/clawfactory-secure-setup/releases/tag/v1.4.4)
          before choosing to run it. A build you compiled yourself is unsigned and will
          always warn.
        - **Hardware virtualization is off in firmware.** The installer falls back to WSL1
          automatically rather than failing. Some behaviour differs, and that is noted in
          the README under Known limitations.
        - **Not enough disk.** 50 GB free is the stated requirement, and 8 GB RAM is the
          stated minimum.

        ---

        ClawFactory is a free personal project under Apache-2.0. There is nothing to buy
        and there is no support arrangement. Issues are read. A reply is not guaranteed,
        and neither is a fix.

  - type: checkboxes
    id: preflight
    attributes:
      label: Before filing
      options:
        - label: I have read the six items above and none of them explains what I saw.
          required: true
        - label: There is no API key, or any part of one, in what I am about to submit.
          required: true

  - type: input
    id: version
    attributes:
      label: ClawFactory version
      description: The installer filename you downloaded, or the version shown in the wizard.
      placeholder: "ClawFactory-Secure-Setup.exe, v1.4.4"
    validations:
      required: true

  - type: input
    id: windows
    attributes:
      label: Windows version
      description: Press Windows+R, type `winver`, and copy the version and build line.
      placeholder: "Windows 11 Home 24H2, build 26100.1742"
    validations:
      required: true

  - type: dropdown
    id: wsl_present
    attributes:
      label: Was WSL2 already installed on this machine before you ran the installer?
      description: >-
        Open PowerShell and run `wsl --status`. If the command is not recognised, WSL was
        not present.
      options:
        - "No, WSL was not present"
        - "Yes, WSL2 was already installed and I already had at least one distro"
        - "Yes, WSL was installed but I had no distros"
        - "I do not know"
    validations:
      required: true

  - type: dropdown
    id: managed
    attributes:
      label: Is this machine managed by a company or a school?
      description: >-
        Domain joined, Intune enrolled, or otherwise under an IT policy. Policy commonly
        blocks enabling Windows features, which this installer has to do.
      options:
        - "No, it is my own machine"
        - "Yes, it is managed"
        - "I do not know"
    validations:
      required: true

  - type: input
    id: step
    attributes:
      label: Which step did it stop on?
      description: >-
        The wizard shows a step name in its status line, and the last line of the install
        log names one too. Copy it if you can, and describe it if you cannot.
      placeholder: "Step 12, Egress firewall"
    validations:
      required: true

  - type: input
    id: exit_code
    attributes:
      label: Exit code, or the failure line
      description: >-
        `%ProgramData%\ClawFactory\install-result.txt` holds the installer's own verdict.
        Paste that one line, or the exit code if you have it.
      placeholder: "INSTALLER_DONE=failure"

  - type: input
    id: duration
    attributes:
      label: How long did it run before it failed?
      placeholder: "About 8 minutes"
    validations:
      required: true

  - type: dropdown
    id: rebooted
    attributes:
      label: Did it reboot before it failed?
      options:
        - "No reboot happened"
        - "It rebooted and then failed after I logged back in"
        - "It rebooted and never resumed"
        - "I do not know"
    validations:
      required: true

  - type: textarea
    id: error_text
    attributes:
      label: The exact text of any error
      description: >-
        Copy it rather than describing it, and check it for keys, paths and machine names
        before you submit.
      render: text

  - type: input
    id: log_path
    attributes:
      label: Install log path
      description: >-
        The path only. Do not paste the log. It is normally
        `%ProgramData%\ClawFactory\install.log`. If yours is somewhere else, say where.
      placeholder: '%ProgramData%\ClawFactory\install.log'

  - type: textarea
    id: anything_else
    attributes:
      label: Anything else
      description: Optional.
```

### 9.3 `.github/ISSUE_TEMPLATE/question.yml`

```yaml
name: Question or feedback
description: Ask something, or say something that is not a defect
title: "[Question] "
labels: ["question"]
body:
  - type: markdown
    attributes:
      value: |
        Not everything is a defect. Questions are welcome, so is an opinion about how the
        product behaves, and so is telling us that something in the documentation reads as
        more flattering than the facts support.

        **Do not paste an API key, or any part of one.** This repository is public.

        For a **security vulnerability**, email `support@clawfactory.app` rather than
        filing here. See
        [SECURITY.md](https://github.com/BuzzardsBay/clawfactory-secure-setup/blob/main/SECURITY.md).

        **Three things are already known and published:**
        [the unmeasured approval guarantee](https://github.com/BuzzardsBay/clawfactory-secure-setup/blob/v1.4.4/docs/RELEASE_NOTES_v1.4.4.md#1-one-approval-guarantee-has-never-been-measured-on-any-release),
        [intermittent GitHub fetches with the software source switch on](https://github.com/BuzzardsBay/clawfactory-secure-setup/blob/v1.4.4/docs/RELEASE_NOTES_v1.4.4.md#2-with-the-software-source-switch-on-github-fetches-can-fail-and-succeed-on-retry),
        and
        [garbled em dashes in five shipped scripts](https://github.com/BuzzardsBay/clawfactory-secure-setup/blob/v1.4.4/docs/RELEASE_NOTES_v1.4.4.md#3-five-shipped-scripts-render-em-dashes-as-garbage-in-seven-places).

        ClawFactory is a free personal project under Apache-2.0. There is nothing to buy
        and there is no support arrangement. Issues are read. A reply is not guaranteed.

  - type: textarea
    id: body
    attributes:
      label: What is on your mind?
    validations:
      required: true

  - type: input
    id: version
    attributes:
      label: ClawFactory version
      description: Optional, and only if the question is about a specific version.
      placeholder: "1.4.4"
```

### 9.4 `.github/ISSUE_TEMPLATE/config.yml`

```yaml
blank_issues_enabled: false
contact_links:
  - name: Security vulnerability (do not file publicly)
    url: https://github.com/BuzzardsBay/clawfactory-secure-setup/blob/main/SECURITY.md
    about: >-
      Email support@clawfactory.app instead of opening an issue. SECURITY.md says what to
      include. A vulnerability filed as a public issue is disclosed to everyone the moment
      you submit it.
  - name: Release notes, residuals and known limitations
    url: https://github.com/BuzzardsBay/clawfactory-secure-setup/blob/v1.4.4/docs/RELEASE_NOTES_v1.4.4.md
    about: >-
      What v1.4.4 enforces, what it does not, the three disclosures, and every residual
      that is known. Worth reading before filing.
```

---

## 10. End-of-session gate

| Gate | State |
|---|---|
| Close-out written, committed, printed in full unprompted | Yes |
| Shipped bytes changed | None. No build, no release, no tag, no version bump |
| Public issue opened on the repository | None |
| Repository settings changed beyond labels and templates | None |
| Templates parse, proven at GitHub's own render | Yes, section 5.4 |
| Labels wired to templates, proven at the surface | Yes, section 5.4 |
| Labels read back from the API rather than assumed | Yes, section 5.5 |
| Secrets printed anywhere | None. Dispatch secret length only |
| Azure resources provisioned | None. Nothing to deallocate |
| Every instrument calibrated before its result was believed | Yes, section 5.2; two instruments discarded as blind, section 5.3 |
| Em dashes in the template files | None. All four files are pure ASCII |
| Commits pushed | `4edf4bb` pushed; this close-out follows |
| Tag created | None, as instructed |

**Nothing is needed from the operator.** Jason can install and file through [the chooser](https://github.com/BuzzardsBay/clawfactory-secure-setup/issues/new/choose) as it now stands.

One thing worth knowing rather than doing: the disclosure links are pinned to tag `v1.4.4` on purpose, so they keep describing the release a reporter actually installed. When v1.5 ships, these three templates need the links repointed. That belongs on the v1.5 checklist alongside the mojibake fix and the README badge, not in this session.
