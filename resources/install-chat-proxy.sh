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
UCTL='XDG_RUNTIME_DIR=/run/user/1000 systemctl --user'

# Shared cold-start health helpers -- the SINGLE source of the 120s health window
# (wait_for_gateway_healthy) and the user-manager readiness assert
# (assert_user_manager_ready). Staged to this path by setup.ps1
# Step-StageGatewayHelper, which runs before this step. Its absence is a real
# install fault, so fail loud rather than silently hand-roll a short loop.
if [ -r /usr/local/lib/clawfactory/gateway-wait.sh ]; then
    . /usr/local/lib/clawfactory/gateway-wait.sh
fi
if ! type wait_for_gateway_healthy >/dev/null 2>&1 || ! type assert_user_manager_ready >/dev/null 2>&1; then
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

# A2 (linger): the port-move restart below is `systemctl --user`, which is a
# silent no-op unless clawuser's user manager is actually up. Assert it (enables
# linger idempotently + waits for /run/user/1000 and a live bus) and FAIL LOUD if
# it never comes up -- otherwise the restart would appear to succeed while the
# gateway never actually moves to $REAL_PORT.
if ! assert_user_manager_ready clawuser; then
    echo "[chat-proxy] FATAL: clawuser systemd --user manager is not ready (linger/user-bus). The gateway port-move restart would be a silent no-op. Enable linger and ensure /run/user/1000 is up." >&2
    exit 1
fi
su clawuser -s /bin/bash -c "$UCTL daemon-reload; $UCTL restart openclaw-gateway"

# Health window = 120s (shared standard), matched to the ~67s cold-start. A
# restart triggers a fresh cold start; the previous ~30s loop undershot it and
# fail-closed a healthy install (v1.0.41, cfv-0716r).
ok=0
wait_for_gateway_healthy "$REAL_PORT" "" clawuser && ok=1
if [ "$ok" != "1" ]; then
    echo "[chat-proxy] FATAL: gateway did not come up on $REAL_PORT within ${CLAWFACTORY_GATEWAY_HEALTH_TIMEOUT_S}s -- rolling back to 8787" >&2
    rm -f "$DROPIN"
    su clawuser -s /bin/bash -c "$UCTL daemon-reload; $UCTL restart openclaw-gateway"
    exit 1
fi
echo "[chat-proxy] real gateway is on 127.0.0.1:$REAL_PORT"

# --- Start the proxy on the public port ------------------------------------
systemctl enable --now clawfactory-proxy >/dev/null 2>&1 || true
# Health window = 120s (shared standard). The proxy forwards to the gateway on
# $REAL_PORT, so this also absorbs any residual gateway warmup; the previous ~20s
# loop undershot the ~67s cold-start.
ok=0
wait_for_gateway_healthy 8787 "" clawuser && ok=1
if [ "$ok" != "1" ]; then
    echo "[chat-proxy] FATAL: /status not 200 through the proxy within ${CLAWFACTORY_GATEWAY_HEALTH_TIMEOUT_S}s -- rolling back" >&2
    systemctl disable --now clawfactory-proxy >/dev/null 2>&1 || true
    rm -f "$DROPIN"
    su clawuser -s /bin/bash -c "$UCTL daemon-reload; $UCTL restart openclaw-gateway"
    exit 1
fi
echo "[chat-proxy] gating proxy is live on 127.0.0.1:8787 -> 127.0.0.1:$REAL_PORT"
