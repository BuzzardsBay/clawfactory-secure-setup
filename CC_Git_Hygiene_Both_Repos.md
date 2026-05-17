# CC PROMPT -- ClawFactory Git Hygiene (Both Repos)

USE SUB-AGENTS for parallel reads where useful.

---

SPEC BLOCK
What this does: Audits and commits all appropriate uncommitted changes in
  clawfactory-secure-setup and clawagent-setup. Excludes binaries, temp
  files, and anything that should never be committed. Pushes both repos
  to main. Produces a summary of what was committed and what was excluded.
Mechanism: headless via az vm run-command invoke only. No mstsc, no
  computer-use, no local desktop interaction. Install flags:
  /SILENT /VERYSILENT /SUPPRESSMSGBOXES /NORESTART -- verify against .iss
  before use. If silent flags insufficient, STOP and report missing flag.
Files it touches: staging + commits in both repos. No source edits.
What should be true when done:
  - clawfactory-secure-setup: clean working tree, pushed to main
  - clawagent-setup: clean working tree, pushed to main
  - Output\ binaries never committed
  - .env never committed
  - Temp *_update.md files never committed
  - Every commit message follows: v[version] -- [one-line summary]
What should NOT change:
  - No source file contents modified -- staging and committing only
  - clawchat repo -- do not touch (separate private repo)
  - FrontierAI or avital-research repos -- do not touch

---

## TASK 1 -- Audit clawfactory-secure-setup

```powershell
Set-Location "C:\Users\bmcki\ClawFactory-Secure-Setup"
git status
git log --oneline -5

```

Read the full git status output. Every file is either STAGE or EXCLUDE. No ambiguous middle ground -- if it matches an exclusion rule, exclude it. Everything else gets staged.
Exclusion rules (never commit these):

* Output* -- compiled binaries and anything else under Output\
* .env -- API keys
* update.md -- temp doc update files (e.g. CLAUDE_ClawFactory_update.md)
* *.log -- log files
* node_modules\ -- dependencies
* Any file over 50 MB
Report the STAGE and EXCLUDE lists before staging anything.
TASK 2 -- Commit clawfactory-secure-setup
Stage all STAGE files explicitly -- do NOT use git add -A or git add .
After staging, verify:

```powershell
git diff --cached --stat

```

Commit message format: v[version] -- [one-line summary] If staged files span multiple concerns, use the most significant as the summary and list the rest in the body.

```powershell
git commit -m "v[version] -- [summary]" -m "- [change 1]\n- [change 2]"
git push origin main

```

Verify push succeeded. Report the final commit hash. If working tree is already clean: note that and skip.
TASK 3 -- Audit clawagent-setup

```powershell
Set-Location "C:\Users\bmcki\clawagent-setup"
git status
git log --oneline -5

```

Same binary categorization: STAGE or EXCLUDE. Same exclusion rules apply.
TASK 4 -- Commit clawagent-setup
Same process as Task 2. Commit message format: v[current version] -- [one-line summary] If working tree is already clean: note that and skip.
TASK 5 -- Final report

```
=== GIT HYGIENE COMPLETE ===

clawfactory-secure-setup
  Files staged:    [count] -- [list]
  Files excluded:  [count] -- [list with reason]
  Commit:          [hash] -- [message]  (or: working tree already clean)
  Push:            PASS / FAIL

clawagent-setup
  Files staged:    [count] -- [list]
  Files excluded:  [count] -- [list with reason]
  Commit:          [hash] -- [message]  (or: working tree already clean)
  Push:            PASS / FAIL

============================

```

DO NOT modify any source file contents. Staging and committing only.
