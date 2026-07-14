#!/bin/bash
# ClawFactory gated openclaw shim (Defect 3 -- gate coverage).
#
# Installed at /usr/bin/openclaw IN PLACE OF the stock symlink to
# /usr/lib/node_modules/openclaw/openclaw.mjs. It gates `openclaw agent` turn
# launches through the universal turn gate and passes every OTHER subcommand
# straight through. Because every launcher -- Studio (both its paths), the CLI,
# the ClawFactory PowerShell engine, and the agent itself -- runs `openclaw
# agent`, none of them can start an UNGATED turn without coming through here.
#
# Residual bypass (documented, not closed): calling the real .mjs by full path
# (`node /usr/lib/node_modules/openclaw/openclaw.mjs agent ...`), or driving a
# turn through the gateway's chatCompletions HTTP endpoint. Neither is used by
# the product's turn paths.
REAL_OPENCLAW="$(cat /etc/clawfactory/openclaw-real 2>/dev/null || echo /usr/lib/node_modules/openclaw/openclaw.mjs)"

if [ "${1:-}" = "agent" ]; then
    /usr/local/sbin/clawfactory-turn-gate.sh
    rc=$?
    if [ "$rc" -ne 0 ]; then
        exit "$rc"
    fi
fi
exec "$REAL_OPENCLAW" "$@"
