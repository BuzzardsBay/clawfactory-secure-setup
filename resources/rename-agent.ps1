[CmdletBinding()]
param()

# rename-agent.ps1 — Secure-Setup variant.
#
# The factory installer creates four agents whose names are roles, not
# user-facing identities (orchestrator, skill-scout, skill-builder,
# publisher). Renaming any of them semantically breaks the orchestrator's
# prompt (which talks about coordinating its three siblings by name). So
# this script does NOT rename anything in factory installs — it explains
# the situation. A single-agent installer variant (planned for a future
# release) will support full personal-assistant renaming.

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3.0

Add-Type -AssemblyName System.Windows.Forms

[System.Windows.Forms.MessageBox]::Show(
    @"
ClawFactory ships four role-based agents — Orchestrator, Scout, Builder, Publisher — that work together as a "skill factory."

Their names are roles, not identities. Renaming "Orchestrator" to "Max" would break the prompts that reference "Orchestrator" by name (and the Orchestrator's own coordination logic that addresses its three siblings).

A single-agent installer variant — which fully supports personal-assistant renaming ("Max", "Aria", "Claw", anything) — is planned for a future release.

For now, no changes have been made.
"@,
    'ClawFactory — Rename Your Assistant',
    [System.Windows.Forms.MessageBoxButtons]::OK,
    [System.Windows.Forms.MessageBoxIcon]::Information
) | Out-Null

exit 0
