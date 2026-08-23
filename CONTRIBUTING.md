# Contributing to ClawFactory Secure Setup

ClawFactory Secure Setup is free and open source, developed by **Frontier Automation Systems LLC** and licensed under the Apache License 2.0. The release process (code signing, build artifacts, and distribution) is internal.

## What we accept

- **Bug reports** via GitHub Issues. Include: Windows version, install log (`%ProgramData%\ClawFactory\install.log`), the smoke-test output if relevant, and the smallest repro you can produce. Logs may contain device-identity hashes; nothing more sensitive than that should appear in normal operation.
- **Pull requests for security fixes and documented bugs.** Match the existing code style (PowerShell 5.1 compatible, no PS7-only syntax). Every PR must compile cleanly (`ISCC.exe ClawFactory-Secure-Setup.iss` is enough for a local check) and pass the smoke test on a clean Windows 11 VM. Add a row to the smoke-test history in `CLAUDE_ClawFactory.md` for any change that affects install behavior.
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
3. Build. `ISCC.exe ClawFactory-Secure-Setup.iss` compiles a local dev build; `.\scripts\build_release.ps1` is the real build command and is the only one that runs the pre-build gates and produces something signable.
4. Run the smoke test on a clean Windows 11 VM.
5. Update the smoke-test history table in `CLAUDE_ClawFactory.md` with the result + the commit hash.
6. PR description references the section of `CLAUDE_ClawFactory.md` that's relevant to the change, plus the smoke-test result.

## Build prerequisites

- [Inno Setup 6](https://jrsoftware.org/isdl.php)
- PowerShell 5.1+ (ships with Windows 10/11)
- A copy of the bundled Ubuntu rootfs at `resources\ubuntu-rootfs.tar.gz`. Gitignored because it is 341 MB, over GitHub's per-file limit. It is a stock, unmodified Canonical image with nothing added:

  | | |
  |---|---|
  | Source | <https://cloud-images.ubuntu.com/wsl/jammy/20250318/ubuntu-jammy-wsl-amd64-ubuntu22.04lts.rootfs.tar.gz> |
  | Release | Ubuntu 22.04.5 LTS (jammy) amd64, image built 2025-03-18 |
  | sha256 | `1483cc5c1dce13064f774834cbffdff226559fd522a67a381a8ea77d63fb4109` |

  That digest is Canonical's own published value, from the `SHA256SUMS` in the same dated directory. Check any copy you fetch against it. Use the dated URL, not `.../wsl/jammy/current/`, which moves to the newest build. `setup.ps1` pins the same digest and refuses to import a rootfs that does not match, and `build_release.ps1` fails the build on drift.

## License

By contributing, you agree that your contributions are licensed under the same terms as the project (Apache License 2.0).
