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
su clawuser -s /bin/bash -c "$UCTL daemon-reload; $UCTL restart openclaw-gateway"

ok=0
for i in $(seq 1 15); do
    if su clawuser -s /bin/bash -c "curl -fsS --max-time 3 http://127.0.0.1:$REAL_PORT/status >/dev/null 2>&1"; then ok=1; break; fi
    sleep 2
done
if [ "$ok" != "1" ]; then
    echo "[chat-proxy] FATAL: gateway did not come up on $REAL_PORT -- rolling back to 8787" >&2
    rm -f "$DROPIN"
    su clawuser -s /bin/bash -c "$UCTL daemon-reload; $UCTL restart openclaw-gateway"
    exit 1
fi
echo "[chat-proxy] real gateway is on 127.0.0.1:$REAL_PORT"

# --- Start the proxy on the public port ------------------------------------
systemctl enable --now clawfactory-proxy >/dev/null 2>&1 || true
ok=0
for i in $(seq 1 10); do
    code=$(su clawuser -s /bin/bash -c "curl -s -o /dev/null -w '%{http_code}' --max-time 4 http://127.0.0.1:8787/status" || true)
    if [ "$code" = "200" ]; then ok=1; break; fi
    sleep 2
done
if [ "$ok" != "1" ]; then
    echo "[chat-proxy] FATAL: /status not 200 through the proxy -- rolling back" >&2
    systemctl disable --now clawfactory-proxy >/dev/null 2>&1 || true
    rm -f "$DROPIN"
    su clawuser -s /bin/bash -c "$UCTL daemon-reload; $UCTL restart openclaw-gateway"
    exit 1
fi
echo "[chat-proxy] gating proxy is live on 127.0.0.1:8787 -> 127.0.0.1:$REAL_PORT"
