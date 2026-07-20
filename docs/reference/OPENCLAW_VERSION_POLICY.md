# OpenClaw version policy

**Pinned version: `2026.4.27`.**

## The pin

The OpenClaw runtime is installed at an **exact pinned version**, not `openclaw@latest`. The pin
is a single constant:

- `setup.ps1:65` — `$OpenClawNpmVersion = '2026.4.27'` (the one place the version literal lives).
- `setup.ps1:1595` — the install invocation passes it as `OPENCLAW_VERSION=$OpenClawNpmVersion`
  into the bundled `resources/openclaw-install.sh`.

The bundled install script honors the env var and skips every `latest` path when it is set to a
concrete version: `openclaw-install.sh:2343` only defaults to `latest` when `OPENCLAW_VERSION` is
*empty*, and `:2365`'s `@latest`/`@next` fallback only fires when it *equals* `latest`
(`OPENCLAW_BETA=0` by default, so the beta branch at `:2330-2340` is not taken). The bundled
script's `:-latest` default (`openclaw-install.sh:1004`) is therefore **never reached in our
install path** — it is dead unless `setup.ps1`'s env export is removed.

> Historical note: a capability-discovery pass on 2026-07-19 read only the bundled script's
> `:-latest` default and concluded "we ship `latest`." That was wrong — it missed the `setup.ps1`
> override. This document and the v1.0.48 validation (installed runtime version read off a clean
> box) correct the record.

## Why the pin exists

Every proof in our validation record — the isolation headline, the 28/0 adversarial suite, the
spend/SOUL gating, the egress persistence — was produced against a specific OpenClaw build. If we
shipped `latest`, each customer would receive whatever `openclaw@latest` resolved to at *their*
install moment: a potentially different artifact with different tool surface, `exec` semantics, or
approval behavior, installed *after* our validation and never tested by us — and our green results
would still read green because they were run against a different build. Pinning makes the artifact
customers receive the same one we validated. Bumps are deliberate and re-validated; they are never
ambient.

## The bump process (never ambient)

To move to a new OpenClaw version:

1. Install the candidate version on a clean cloud box (the standard `azure-validate.ps1` harness).
2. Run the **full adversarial suite** and compare against the prior baseline (currently
   **Tier 1: 28 PASS / 0 FAIL**). Any delta is a finding, not a footnote.
3. Confirm the tool surface and `exec`/approval behavior are unchanged (a version can silently
   change what tools exist or how a denial behaves — see `tools.deny` in Step 9a).
4. Re-run the headline isolation + egress-persistence checks.
5. Only if all pass: update the single constant `$OpenClawNpmVersion` in `setup.ps1`, rebuild,
   re-validate the pinned build end-to-end (read the installed version off the runtime, not the
   constant), and record the result in a session report.
6. The pin literal appears in exactly one place. Do not repeat it across files.
