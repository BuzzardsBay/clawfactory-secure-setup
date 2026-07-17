#!/bin/bash
# Blocker-1 installer: put the ClawFactory gating proxy on 127.0.0.1:8787 and
# move the REAL OpenClaw gateway to the private loopback port 8788.
#
# setup.ps1 has already base64-dropped:
#   /usr/local/sbin/clawfactory-proxy.js
#   /tmp/clawfactory-proxy.service      (with __NODE__ still to substitute)
#
# WHY AN ExecStart OVERRIDE, NOT AN ENV VAR: the gateway's own unit hardcodes
#   ExecStart=... gateway --port 8787
# and OpenClaw's port precedence is --port > OPENCLAW_GATEWAY_PORT > gateway.port.
# So a drop-in that only sets the env var is silently ignored (VERIFIED: the
# gateway stayed on 8787). The drop-in must CLEAR and REPLACE ExecStart. We derive
# the command from the live unit rather than hardcoding it, so an OpenClaw upgrade
# that changes the path still works.
#
# gateway.port in openclaw.json stays 8787 ON PURPOSE: that is what CLIENTS
# resolve (the CLI dials ws://127.0.0.1:8787), so they reach the proxy and are
# passed through. Only the SERVER moves.
set -e
UNITFILE=/home/clawuser/.config/systemd/user/openclaw-gateway.service
DROPDIR=/home/clawuser/.config/systemd/user/openclaw-gateway.service.d
DROPIN=$DROPDIR/clawfactory-real-port.conf
REAL_PORT=8788

# Shared cold-start health helpers -- the SINGLE source of the 120s health window
# (wait_for_gateway_healthy) and the user-manager readiness assert
# (assert_user_manager_ready). Staged to this path by setup.ps1
# Step-StageGatewayHelper, which runs before this step. Its absence is a real
# install fault, so fail loud rather than silently hand-roll a short loop.
if [ -r /usr/local/lib/clawfactory/gateway-wait.sh ]; then
    . /usr/local/lib/clawfactory/gateway-wait.sh
fi
if ! type wait_for_gateway_healthy >/dev/null 2>&1 || ! type assert_user_manager_ready >/dev/null 2>&1 || ! type restart_gateway_reliably >/dev/null 2>&1; then
    echo "[chat-proxy] FATAL: gateway-wait.sh helper not available (Step-StageGatewayHelper must run first)" >&2
    exit 1
fi

NODE=$(command -v node)
[ -n "$NODE" ] || { echo "[chat-proxy] FATAL: node not found" >&2; exit 1; }
chmod 755 /usr/local/sbin/clawfactory-proxy.js
chown root:root /usr/local/sbin/clawfactory-proxy.js
node --check /usr/local/sbin/clawfactory-proxy.js || { echo "[chat-proxy] FATAL: proxy failed syntax check" >&2; exit 1; }
sed "s|__NODE__|$NODE|" /tmp/clawfactory-proxy.service > /etc/systemd/system/clawfactory-proxy.service
rm -f /tmp/clawfactory-proxy.service
systemctl daemon-reload

# --- Move the real gateway to the private port -----------------------------
[ -f "$UNITFILE" ] || { echo "[chat-proxy] FATAL: gateway unit not found at $UNITFILE" >&2; exit 1; }
CUR=$(grep '^ExecStart=' "$UNITFILE" | head -1 | sed 's/^ExecStart=//')
NEW=$(printf '%s' "$CUR" | sed "s/--port[= ]*[0-9]\+/--port $REAL_PORT/")
case "$NEW" in
    *"--port $REAL_PORT"*) ;;
    *) echo "[chat-proxy] FATAL: could not retarget ExecStart (got: $NEW)" >&2; exit 1 ;;
esac
mkdir -p "$DROPDIR"
{
    printf '[Service]\n'
    printf 'ExecStart=\n'
    printf 'ExecStart=%s\n' "$NEW"
    printf 'Environment=OPENCLAW_GATEWAY_PORT=%s\n' "$REAL_PORT"
} > "$DROPIN"
chown -R clawuser:clawuser "$DROPDIR"

# v1.0.43 (restart class + firewall-context fix): move the gateway to $REAL_PORT
# using the RELIABLE restart -- openclaw's own `openclaw gateway restart`, falling
# back to `openclaw gateway install --force` (the mechanism the gateway install
# proves works in the no-login WSL context) -- NOT a bare `systemctl --user
# restart`, which cfv-0716s showed fails to rebind. restart_gateway_reliably
# asserts the user manager first (linger/bus) and fails loud if it never comes up.
#
# CRITICAL: restart_gateway_reliably runs the HEALTH PROBE as the caller's uid,
# and we are ROOT here -- ON PURPOSE. The nft firewall drops
# clawuser->127.0.0.1:$REAL_PORT (the private port is reachable only by root and
# the proxy). Probing $REAL_PORT as clawuser (the pre-v1.0.43 code) is DROPPED
# (000) even when the gateway is perfectly healthy -- a latent bug that fail-closed
# a healthy install once the firewall + this step both ran on a clean box.
if ! restart_gateway_reliably "$REAL_PORT"; then
    echo "[chat-proxy] FATAL: gateway did not come up on $REAL_PORT (root-probed) within the health window -- rolling back to 8787" >&2
    rm -f "$DROPIN"
    restart_gateway_reliably 8787 || true
    exit 1
fi
echo "[chat-proxy] real gateway is on 127.0.0.1:$REAL_PORT"

# --- Start the proxy on the public port ------------------------------------
systemctl enable --now clawfactory-proxy >/dev/null 2>&1 || true
# The proxy on 8787 is the CLIENT path -- verify it AS CLAWUSER, because that is
# exactly the reachability the CLI/ClawChat get (clawuser->8787 is allowed; only
# ->8788 is dropped). The proxy forwards /status to the gateway on $REAL_PORT, so
# a 200 here also confirms the gateway. 120s shared window.
ok=0
wait_for_gateway_healthy 8787 "" clawuser && ok=1
if [ "$ok" != "1" ]; then
    echo "[chat-proxy] FATAL: /status not 200 through the proxy within ${CLAWFACTORY_GATEWAY_HEALTH_TIMEOUT_S}s -- rolling back" >&2
    systemctl disable --now clawfactory-proxy >/dev/null 2>&1 || true
    rm -f "$DROPIN"
    restart_gateway_reliably 8787 || true
    exit 1
fi
echo "[chat-proxy] gating proxy is live on 127.0.0.1:8787 -> 127.0.0.1:$REAL_PORT"
