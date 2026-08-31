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

# --- a2. divert /usr/bin/rm to the wrapper ---------------------------------
#
# PATH interception alone does not work, and a clean-box validation caught it.
# OpenClaw prepends the running node binary's directory AFTER applying
# tools.exec.pathPrepend, and node is /usr/bin/node, so /usr/bin always precedes
# execbin and `rm` resolved to the real binary. A real agent turn destroyed a
# file in a granted workspace and then reported it safely quarantined. No config
# value can win, because the winning directory is derived from node's location.
#
# Diverting the NAME removes PATH from the question. /bin is a usrmerge symlink
# to /usr/bin, so this covers `/bin/rm` as well.
#
# Root passes straight through inside the wrapper, so apt, systemd and the
# installer keep stock behaviour and a broker outage cannot brick the box.
DIVERTED=/usr/bin/rm.real
if command -v dpkg-divert >/dev/null 2>&1; then
    if ! dpkg-divert --list /usr/bin/rm | grep -q "$DIVERTED"; then
        # --rename moves the existing /usr/bin/rm to $DIVERTED atomically.
        dpkg-divert --divert "$DIVERTED" --rename /usr/bin/rm \
            || fatal "dpkg-divert of /usr/bin/rm failed; refusing to install a guard that cannot intercept"
    fi
else
    fatal "dpkg-divert not found; cannot install the delete guard structurally"
fi

# The diverted binary MUST exist and be executable before the wrapper takes the
# name, or every delete on the system breaks. Verify, and roll the divert back
# if it does not, rather than leaving a box with no working rm.
if [ ! -x "$DIVERTED" ]; then
    dpkg-divert --rename --remove /usr/bin/rm 2>/dev/null || true
    fatal "expected the real rm at $DIVERTED after the divert; rolled back"
fi

install -m 755 -o root -g root "$EXECBIN/rm" /usr/bin/rm \
    || fatal "could not install the quarantine wrapper as /usr/bin/rm"

# Paired proof, both directions, before we call this installed:
#   root must still get the REAL rm (pass-through), and the wrapper must be what
#   the name resolves to. A guard that silently did neither would look identical
#   to a working one from the outside.
_t=$(mktemp /tmp/cfrm-divert-check.XXXXXX)
rm -f "$_t" || fatal "root rm pass-through is broken after the divert; the system delete path must keep working"
[ -e "$_t" ] && fatal "root rm did not remove its own temp file after the divert"
head -1 /usr/bin/rm | grep -q 'node' \
    || fatal "/usr/bin/rm is not the wrapper after install; the divert did not take"
echo "[quarantine] /usr/bin/rm diverted to $DIVERTED; wrapper installed at /usr/bin/rm"

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
  "maxStoreBytes": 10737418240,
  "minFreeBytes": 2147483648,
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

# READ BACK, BOTH OF THEM. `systemctl enable` is written above with `|| true`,
# which means a unit that failed to install looks identical to one that did.
# `enable --now` makes two claims and the socket ping below only proves the
# second: a broker that started now but was never linked into multi-user.target
# is gone at the next restart, and nothing on the box says so. Guard 1 is only
# structural if it is still there after the machine comes back.
for u in clawfactory-quarantine.service clawfactory-quarantine-gc.timer; do
    st="$(systemctl is-enabled "$u" 2>&1 || true)"
    [ "$st" = "enabled" ] || fatal "$u did not enable (systemctl is-enabled said '${st:-<empty>}'). Deletes are only recoverable while the quarantine broker is running, and a unit that is not enabled does not come back after you restart your PC. The install would finish, the guard would work today, and the first restart would silently remove it. Refusing to complete."
done

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
