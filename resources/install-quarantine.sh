#!/bin/bash
# install-quarantine.sh — stand up the ClawFactory delete quarantine (v1 Guard 1).
#
# setup.ps1 has already base64-dropped:
#   /usr/local/lib/clawfactory/quarantine-lib.js
#   /usr/local/sbin/clawfactory-quarantined.js
#   /usr/local/sbin/clawfactory-quarantinectl.js
#   /usr/local/lib/clawfactory/execbin/rm      (the agent-facing wrapper)
#   /tmp/clawfactory-quarantine.service        (__NODE__ still to substitute)
#   /tmp/clawfactory-quarantine-gc.service     (__NODE__ still to substitute)
#   /tmp/clawfactory-quarantine-gc.timer
#
# Runs as ROOT. Fails loud: a half-installed quarantine is worse than none,
# because the product would then claim recoverable deletes it cannot deliver.
set -e

AGENT_USER="${CLAWFACTORY_AGENT_USER:-clawuser}"
STORE=/var/lib/clawfactory/quarantine
EXECBIN=/usr/local/lib/clawfactory/execbin

fatal() { echo "[quarantine] FATAL: $*" >&2; exit 1; }

NODE=$(command -v node) || true
[ -n "$NODE" ] || fatal "node not found"

# The broker's privilege-escalation guard drops to the agent uid with setpriv to
# re-derive unlink permission. Without setpriv there is no permission gate, and
# a root service that deletes on request is a hole. Refuse to install.
command -v setpriv >/dev/null 2>&1 || fatal "setpriv not found (util-linux) -- the broker's permission gate needs it"
id "$AGENT_USER" >/dev/null 2>&1 || fatal "agent account $AGENT_USER does not exist"

# --- a. code ---------------------------------------------------------------
# CR-strip before anything else: these files are authored on Windows and the
# wrapper is executed through its shebang, where a trailing CR is fatal
# ("bad interpreter"). .gitattributes pins them to LF; this is the runtime
# belt-and-suspenders that L20/L21 taught us to keep.
for f in /usr/local/lib/clawfactory/quarantine-lib.js \
         /usr/local/sbin/clawfactory-quarantined.js \
         /usr/local/sbin/clawfactory-quarantinectl.js \
         "$EXECBIN/rm"; do
    [ -f "$f" ] || fatal "missing $f (setup.ps1 drop step did not run)"
    sed -i 's/\r$//' "$f"
    "$NODE" --check "$f" || fatal "$f failed syntax check"
    chown root:root "$f"
done
chmod 644 /usr/local/lib/clawfactory/quarantine-lib.js
chmod 755 /usr/local/sbin/clawfactory-quarantined.js
chmod 755 /usr/local/sbin/clawfactory-quarantinectl.js
# World-executable, root-owned, not writable by the agent: the agent runs the
# wrapper but cannot edit it out of the way.
chmod 755 "$EXECBIN/rm"
chown root:root "$EXECBIN" /usr/local/lib/clawfactory
chmod 755 "$EXECBIN"

# --- b. store + config -----------------------------------------------------
# 0700 root:root is the structural half of the guard: held payloads are chowned
# to root inside a directory the agent cannot even list.
mkdir -p "$STORE"
chown root:root "$STORE" /var/lib/clawfactory
chmod 700 "$STORE"
chmod 755 /var/lib/clawfactory

mkdir -p /etc/clawfactory
cat > /etc/clawfactory/quarantine.json <<CFG
{
  "retentionDays": 30,
  "maxEntryBytes": 2147483648,
  "quarantineRoots": ["/workspaces"],
  "skipSegments": ["node_modules", ".git"],
  "socketPath": "/run/clawfactory/quarantine.sock",
  "store": "$STORE",
  "agentUser": "$AGENT_USER"
}
CFG
# World-readable on purpose: the agent-side wrapper reads it to decide which
# paths to route. Root-owned and mode 444 so the agent cannot widen or narrow
# its own scope.
chown root:root /etc/clawfactory/quarantine.json
chmod 444 /etc/clawfactory/quarantine.json

# --- c. units --------------------------------------------------------------
for u in clawfactory-quarantine.service clawfactory-quarantine-gc.service; do
    [ -f "/tmp/$u" ] || fatal "missing /tmp/$u"
    sed "s|__NODE__|$NODE|" "/tmp/$u" > "/etc/systemd/system/$u"
    rm -f "/tmp/$u"
done
[ -f /tmp/clawfactory-quarantine-gc.timer ] || fatal "missing /tmp/clawfactory-quarantine-gc.timer"
cp /tmp/clawfactory-quarantine-gc.timer /etc/systemd/system/clawfactory-quarantine-gc.timer
rm -f /tmp/clawfactory-quarantine-gc.timer
systemctl daemon-reload
systemctl enable --now clawfactory-quarantine.service >/dev/null 2>&1 || true
systemctl enable --now clawfactory-quarantine-gc.timer >/dev/null 2>&1 || true

# --- d. prove the broker answers THE AGENT ---------------------------------
# Probe as the agent account, not as root: the reachability that matters is the
# one clawuser gets through the socket's 0660 root:clawuser mode. Probing as
# root would pass even with the permissions wrong.
ok=0
for _ in $(seq 1 30); do
    if [ -S /run/clawfactory/quarantine.sock ]; then
        if setpriv --reuid="$(id -u "$AGENT_USER")" --regid="$(id -g "$AGENT_USER")" --clear-groups \
             "$NODE" -e '
               const net=require("node:net");
               const s=net.createConnection("/run/clawfactory/quarantine.sock");
               s.on("connect",()=>s.write(JSON.stringify({op:"ping"})+"\n"));
               s.on("data",d=>{try{process.exit(JSON.parse(String(d).split("\n")[0]).pong?0:1)}catch{process.exit(1)}});
               s.on("error",()=>process.exit(1));
               setTimeout(()=>process.exit(1),5000);
             ' 2>/dev/null; then
            ok=1
            break
        fi
    fi
    sleep 1
done
[ "$ok" = "1" ] || fatal "broker did not answer a ping from $AGENT_USER within 30s"

echo "[quarantine] broker live on /run/clawfactory/quarantine.sock (store=$STORE, retention=30d)"
echo "[quarantine] agent-facing wrapper at $EXECBIN/rm"
