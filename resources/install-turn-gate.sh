#!/bin/bash
# Defect 3 installer: place the gated openclaw shim + universal turn gate.
# setup.ps1 has already base64-dropped:
#   /tmp/oc-shim                                  (openclaw-shim.sh)
#   /usr/local/sbin/clawfactory-turn-gate.sh      (the gate)
#   /usr/local/sbin/clawfactory-spend-check.js    (spend parser)
# This script wires the real-binary pointer, the default governor mirror, and
# swaps the openclaw symlink for the shim. Idempotent + reversible (uninstall
# restores the symlink from /etc/clawfactory/openclaw-real).
set -e
mkdir -p /etc/clawfactory
chmod 755 /usr/local/sbin/clawfactory-turn-gate.sh /usr/local/sbin/clawfactory-spend-check.js
chown root:root /usr/local/sbin/clawfactory-turn-gate.sh /usr/local/sbin/clawfactory-spend-check.js

# Resolve the REAL openclaw target BEFORE replacing the symlink (so a re-run
# never records the shim itself as the real binary).
if [ ! -s /etc/clawfactory/openclaw-real ]; then
    readlink -f "$(command -v openclaw)" > /etc/clawfactory/openclaw-real
fi
REAL=$(cat /etc/clawfactory/openclaw-real)
[ -n "$REAL" ] && [ -e "$REAL" ] || { echo "[turn-gate] FATAL: cannot resolve real openclaw binary ($REAL)" >&2; exit 1; }

# Default governor mirror (runtime Sync-GovernorMirror keeps it current).
[ -f /etc/clawfactory/governor.json ] || printf '{"daily_cap_usd":5,"monthly_cap_usd":50,"warn_pct":80}' > /etc/clawfactory/governor.json
chown root:root /etc/clawfactory/governor.json
chmod 644 /etc/clawfactory/governor.json

# Swap the openclaw symlink for the shim (idempotent: skip if already the shim).
OC=$(command -v openclaw)
if head -3 "$OC" 2>/dev/null | grep -q 'ClawFactory gated openclaw shim'; then
    echo "[turn-gate] shim already installed at $OC"
else
    install -m 755 -o root -g root /tmp/oc-shim "$OC"
    echo "[turn-gate] shim installed at $OC (was -> $REAL)"
fi
rm -f /tmp/oc-shim

# Cover /bin/openclaw if it is a DISTINCT symlink (non-usrmerge systems).
if [ "$(readlink -f /bin/openclaw 2>/dev/null)" != "$OC" ]; then
    ln -sf "$OC" /bin/openclaw 2>/dev/null || true
fi

# Verify passthrough (a non-agent subcommand must still work).
if openclaw --version >/dev/null 2>&1; then
    echo "[turn-gate] passthrough OK; installed"
else
    echo "[turn-gate] WARN: 'openclaw --version' failed through the shim -- check $OC and /etc/clawfactory/openclaw-real" >&2
fi
