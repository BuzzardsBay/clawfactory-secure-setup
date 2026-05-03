# Contributing to ClawFactory Secure Setup

ClawFactory Secure Setup is a commercial product developed by **Frontier Automation Systems LLC**. The repository is open under the MIT license, but the release process — code signing, build artifacts, and distribution — is internal.

## What we accept

- **Bug reports** via GitHub Issues. Include: Windows version, install log (`%ProgramData%\ClawFactory\install.log`), the smoke-test output if relevant, and the smallest repro you can produce. Logs may contain device-identity hashes; nothing more sensitive than that should appear in normal operation.
- **Pull requests for security fixes and documented bugs.** Match the existing code style (PowerShell 5.1 compatible, no PS7-only syntax). Every PR must compile cleanly with `ISCC.exe ClawFactory-Secure-Setup.iss` and pass the seven-check smoke test on a clean Windows 11 VM. Add a row to the smoke-test history in `CLAUDE_ClawFactory.md` for any change that affects install behavior.
- **Documentation improvements** — typos, broken links, missing context. No process for these beyond a clear PR description.

## What we don't accept

- **Feature additions without prior discussion.** Open an issue first; the v1.x line is scoped tight, and most feature ideas land in `v1.1_backlog.md` for later.
- **Refactors that don't fix a bug.** The PowerShell + Inno Setup combination is fragile by nature; reorganizing for taste alone introduces risk without payoff.
- **Changes to the SHA-256 pin in `setup.ps1`** without an accompanying audit of the new `install.sh` content. The pin is a load-bearing supply-chain control.

## Reporting security issues

**Do not open a public issue for security vulnerabilities.** See [SECURITY.md](SECURITY.md). Email **hello@avitalresearch.com** with details. We respond within 72 hours.

## Development workflow

The codebase has a documented diagnostic reference pack at [`CLAUDE_ClawFactory.md`](CLAUDE_ClawFactory.md). Read it before changing anything in `setup.ps1`, `bootstrap.ps1`, or `post-install.ps1` — it describes the install execution map, the user-context boundaries (root vs clawuser vs Windows), and a pattern hazard list of bug shapes that have bitten this codebase.

The expected loop on every non-trivial change:

1. Read the relevant section of `CLAUDE_ClawFactory.md`.
2. Make the change with exact find/replace blocks (descriptive instructions are a known failure mode in this code).
3. Build: `ISCC.exe ClawFactory-Secure-Setup.iss`.
4. Run the seven-check smoke test on a clean Windows 11 VM.
5. Update the smoke-test history table in `CLAUDE_ClawFactory.md` with the result + the commit hash.
6. PR description references the section of `CLAUDE_ClawFactory.md` that's relevant to the change, plus the smoke-test result.

## Build prerequisites

- [Inno Setup 6](https://jrsoftware.org/isdl.php)
- PowerShell 5.1+ (ships with Windows 10/11)
- A copy of the bundled Ubuntu rootfs at `resources\ubuntu-rootfs.tar.gz` (gitignored — sourced separately at build time; see internal docs for the source)

## License

By contributing, you agree that your contributions are licensed under the MIT License (the same as the project).
