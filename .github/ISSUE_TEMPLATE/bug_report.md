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
