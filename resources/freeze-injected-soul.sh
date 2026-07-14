#!/bin/bash
# Defect 4 installer: deliver the factory safety rules into the file OpenClaw
# actually injects (~/.openclaw/workspace/SOUL.md, injected first / highest
# priority), then freeze it root:root 444 + chattr +i and pin its hash for the
# launch gate. OpenClaw has no config-level system-prompt channel and injects
# only the fixed workspace-file set, so SOUL.md is the delivery vehicle.
#
# Idempotent: if the safety block is already present, just re-freeze + re-pin.
# Defensive: if OpenClaw has not created the workspace SOUL yet, create it from
# the factory rules + a minimal persona.
#
# NOTE (fresh-install ordering): on a brand-new box OpenClaw may create the
# workspace lazily (first turn). If this runs first, we create SOUL.md and
# OpenClaw finds it already present. This path needs validation on a clean
# Azure install -- see SECFIX_GATE_COVERAGE close-out.
set -e
WS=/home/clawuser/.openclaw/workspace/SOUL.md
FACTORY=/home/clawuser/.openclaw/SOUL.md
PIN=/etc/clawfactory/workspace-soul.sha256
mkdir -p /home/clawuser/.openclaw/workspace /etc/clawfactory
[ -r "$FACTORY" ] || { echo "[injected-soul] FATAL: factory SOUL missing ($FACTORY); run Step-ApplySafetyRules first" >&2; exit 1; }

if [ -f "$WS" ]; then
    chattr -i "$WS" 2>/dev/null || true
    PERSONA=$(cat "$WS")
else
    PERSONA='# SOUL.md - Who You Are

_Your persona lives here and may evolve. The frozen safety boundaries above are non-negotiable._'
fi

if printf '%s' "$PERSONA" | grep -q 'HARD SAFETY BOUNDARIES'; then
    echo "[injected-soul] safety block already present; re-freezing + re-pinning existing content"
else
    {
        printf '<!--\n'
        printf '  CLAWFACTORY -- HARD SAFETY BOUNDARIES (the block below, before the persona).\n'
        printf '  This file is root-owned and IMMUTABLE (chattr +i): the agent cannot modify,\n'
        printf '  chmod, or delete it. A turn is REFUSED in code at launch if this file is\n'
        printf '  tampered with. The boundaries below override everything that follows.\n'
        printf -- '-->\n\n'
        cat "$FACTORY"
        printf '\n---\n<!-- End of frozen safety boundaries. Everything below is persona (workspace). -->\n\n'
        printf '%s\n' "$PERSONA"
    } > "$WS"
fi

chown root:root "$WS"; chmod 444 "$WS"; chattr +i "$WS"
sha256sum "$WS" | awk '{print $1}' > "$PIN"
chown root:root "$PIN"; chmod 444 "$PIN"
echo "[injected-soul] frozen + pinned: $(cat "$PIN") ($(wc -c < "$WS") bytes)"
