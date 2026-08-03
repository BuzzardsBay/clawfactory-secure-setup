#!/bin/bash
# install-send.sh -- stand up the ClawFactory approval-gated send broker
# (v1 Guard 2).
#
# setup.ps1 has already base64-dropped:
#   /usr/local/lib/clawfactory/send-lib.js
#   /usr/local/lib/clawfactory/send-smtp.js
#   /usr/local/sbin/clawfactory-sendd.js
#   /usr/local/sbin/clawfactory-sendctl.js
#   /usr/local/sbin/clawfactory-fw-assert.sh
#   /usr/local/bin/clawfactory-send            (the agent-facing client)
#   /tmp/clawfactory-send.service              (__NODE__ still to substitute)
#   /tmp/clawfactory-send-gc.service           (__NODE__ still to substitute)
#   /tmp/clawfactory-send-gc.timer
#   /tmp/egress-policy.json
#
# Runs as ROOT. Fails loud: a half-installed send guard is worse than none,
# because the product would then claim approval-gated email it cannot deliver.
set -e

AGENT_USER="${CLAWFACTORY_AGENT_USER:-clawuser}"
STORE=/var/lib/clawfactory/send

fatal() { echo "[send] FATAL: $*" >&2; exit 1; }

NODE=$(command -v node) || true
[ -n "$NODE" ] || fatal "node not found"

# The broker's escalation guard performs every attachment read at the agent uid
# via setpriv. Without setpriv there is no entitlement gate at all, and a root
# service that reads files on request is a hole. Refuse to install.
command -v setpriv >/dev/null 2>&1 || fatal "setpriv not found (util-linux) -- the broker's entitlement gate needs it"
id "$AGENT_USER" >/dev/null 2>&1 || fatal "agent account $AGENT_USER does not exist"
AGENT_UID=$(id -u "$AGENT_USER")
AGENT_GID=$(id -g "$AGENT_USER")
[ "$AGENT_UID" != "0" ] || fatal "agent account resolves to uid 0"

# --- a. code ---------------------------------------------------------------
# CR-strip before anything else: these files are authored on Windows and are
# executed through their shebang, where a trailing CR is fatal. L20/L21.
for f in /usr/local/lib/clawfactory/send-lib.js \
         /usr/local/lib/clawfactory/send-smtp.js \
         /usr/local/sbin/clawfactory-sendd.js \
         /usr/local/sbin/clawfactory-sendctl.js \
         /usr/local/bin/clawfactory-send; do
    [ -f "$f" ] || fatal "missing $f (setup.ps1 drop step did not run)"
    sed -i 's/\r$//' "$f"
    "$NODE" --check "$f" || fatal "$f failed syntax check"
    chown root:root "$f"
done
[ -f /usr/local/sbin/clawfactory-fw-assert.sh ] || fatal "missing /usr/local/sbin/clawfactory-fw-assert.sh"
sed -i 's/\r$//' /usr/local/sbin/clawfactory-fw-assert.sh
bash -n /usr/local/sbin/clawfactory-fw-assert.sh || fatal "clawfactory-fw-assert.sh failed syntax check"
chown root:root /usr/local/sbin/clawfactory-fw-assert.sh

chmod 644 /usr/local/lib/clawfactory/send-lib.js /usr/local/lib/clawfactory/send-smtp.js
chmod 755 /usr/local/sbin/clawfactory-sendd.js
# 0750: the approval tool is root-only. This is one of the two independent
# things that stop the agent approving its own request; the other is the 0600
# mode on the admin socket it speaks to.
chmod 750 /usr/local/sbin/clawfactory-sendctl.js
chmod 755 /usr/local/sbin/clawfactory-fw-assert.sh
# World-executable, root-owned, not writable by the agent: the agent runs the
# client but cannot edit it out of the way. It holds no capability regardless.
chmod 755 /usr/local/bin/clawfactory-send

# The name Studio invokes over its hardcoded `wsl -u root` channel. A wrapper
# rather than a symlink so the node path is pinned at install time, matching how
# the units resolve __NODE__. 0750 root:root: not executable by the agent, which
# is one of the two independent things preventing the agent from approving its
# own request.
cat > /usr/local/sbin/clawfactory-sendctl <<WRAP
#!/bin/bash
exec "$NODE" /usr/local/sbin/clawfactory-sendctl.js "\$@"
WRAP
chown root:root /usr/local/sbin/clawfactory-sendctl
chmod 750 /usr/local/sbin/clawfactory-sendctl

# --- b. store --------------------------------------------------------------
# 0700 root:root is the structural half of the guard. Staged attachment bytes
# live here, which is what makes "the bytes you approved are the bytes that go
# out" true rather than aspirational: the agent cannot rewrite them after
# approval because it cannot even list the directory.
mkdir -p "$STORE"/pending "$STORE"/staging "$STORE"/receipts
chown -R root:root "$STORE"
chown root:root /var/lib/clawfactory
chmod 700 "$STORE" "$STORE"/pending "$STORE"/staging "$STORE"/receipts
chmod 755 /var/lib/clawfactory

# --- c. config -------------------------------------------------------------
mkdir -p /etc/clawfactory
cat > /etc/clawfactory/send.json <<CFG
{
  "socketPath": "/run/clawfactory/send.sock",
  "adminSocketPath": "/run/clawfactory/send-admin.sock",
  "store": "$STORE",
  "credentialPath": "/etc/clawfactory/send-credential.json",
  "policyPath": "/etc/clawfactory/egress-policy.json",
  "killSwitchPath": "/etc/clawfactory/send-killswitch",
  "agentUser": "$AGENT_USER",
  "approvalTtlSeconds": 600,
  "maxAttachmentBytes": 26214400,
  "maxRequestBytes": 26214400,
  "maxStagingBytes": 536870912,
  "maxAttachments": 20,
  "maxRecipients": 50,
  "maxSubjectBytes": 998,
  "maxBodyBytes": 5242880,
  "pendingRetentionHours": 24
}
CFG
# 0444 root-owned: the agent may read its own limits but cannot widen them.
# NOTE the contrast with send-credential.json, which is 0600 and which the agent
# must never read. Nothing agent-side needs the credential.
chown root:root /etc/clawfactory/send.json
chmod 444 /etc/clawfactory/send.json

# The egress policy. Never clobber an existing one: it carries the user's
# authorized destination, and re-running the installer must not silently revoke
# or widen it.
if [ ! -f /etc/clawfactory/egress-policy.json ]; then
    [ -f /tmp/egress-policy.json ] || fatal "missing /tmp/egress-policy.json"
    cp /tmp/egress-policy.json /etc/clawfactory/egress-policy.json
fi
rm -f /tmp/egress-policy.json
chown root:root /etc/clawfactory/egress-policy.json
chmod 644 /etc/clawfactory/egress-policy.json

# --- d. firewall: make the existing property legible, assert it, add nothing --
# Guard 2 adds NO accept and NO exemption. The broker reaches SMTP because the
# chain returns early for every uid that is not the agent, not because anything
# was opened for it. What is added here is an explicit drop that states the
# property in source, and a checker that fails loud if the shape ever drifts.
if ! grep -q 'ClawFactory Guard 2' /etc/nftables.conf 2>/dev/null; then
    [ -f /etc/nftables.conf ] || fatal "/etc/nftables.conf is missing; run the firewall step first"
    cp /etc/nftables.conf /etc/nftables.conf.pre-guard2
    # Inserted BEFORE `oifname "lo" accept` on purpose, so it also covers a
    # local relay: handing mail to an MTA on loopback would be an egress path
    # that never touches the broker.
    awk '
      /oifname "lo" accept/ && !done {
        print "        # --- ClawFactory Guard 2: approval-gated send ---"
        print "        # Email leaves this machine only through the root-owned send broker."
        print "        # uid 1000 is the agent AND the gateway, one security principal, and it"
        print "        # has no SMTP path at all. This drop is REDUNDANT with the terminal"
        print "        # counter drop below; the redundancy is the point, because it states the"
        print "        # property in source instead of leaving it to be inferred from rule order."
        print "        # Guard 2 adds no accept and no exemption for the broker: root is already"
        print "        # unfiltered by the skuid return at the top of this chain."
        print "        tcp dport { 25, 465, 587, 2525 } counter drop"
        done = 1
      }
      { print }
    ' /etc/nftables.conf.pre-guard2 > /etc/nftables.conf
    grep -q 'ClawFactory Guard 2' /etc/nftables.conf || fatal "could not insert the Guard 2 drop into /etc/nftables.conf"
fi

# Re-apply, then repopulate through the SHIPPED refresh rather than by adding
# elements ourselves. `nft -f` flushes the ruleset, so skipping the refresh would
# leave the agent with a stale allowlist until the five-hourly timer fired.
if [ -x /usr/local/sbin/clawfactory-fw-apply.sh ]; then
    /usr/local/sbin/clawfactory-fw-apply.sh || fatal "firewall re-apply failed"
fi
if [ -x /usr/local/sbin/clawfactory-allow-providers.sh ]; then
    /usr/local/sbin/clawfactory-allow-providers.sh || true
fi

# Assert on every refresh cycle. A drop-in rather than an edit to the shipped
# unit, so this survives the unit being rewritten and adds no element logic to
# the refresh script itself.
mkdir -p /etc/systemd/system/clawfactory-allow-providers.service.d
cat > /etc/systemd/system/clawfactory-allow-providers.service.d/10-guard2-assert.conf <<'DROPIN'
[Service]
# Guard 2 tripwire. Reads the live chain and fails the unit if the allowlist
# accept ever widens beyond tcp dport 443, or if the explicit SMTP drop goes
# missing. Reads only; it never writes a rule or touches a set element.
ExecStartPost=/usr/local/sbin/clawfactory-fw-assert.sh
DROPIN

# --- e. units --------------------------------------------------------------
for u in clawfactory-send.service clawfactory-send-gc.service; do
    [ -f "/tmp/$u" ] || fatal "missing /tmp/$u"
    sed "s|__NODE__|$NODE|" "/tmp/$u" > "/etc/systemd/system/$u"
    rm -f "/tmp/$u"
done
[ -f /tmp/clawfactory-send-gc.timer ] || fatal "missing /tmp/clawfactory-send-gc.timer"
cp /tmp/clawfactory-send-gc.timer /etc/systemd/system/clawfactory-send-gc.timer
rm -f /tmp/clawfactory-send-gc.timer
systemctl daemon-reload
systemctl enable --now clawfactory-send.service >/dev/null 2>&1 || true
systemctl enable --now clawfactory-send-gc.timer >/dev/null 2>&1 || true

# --- f. assert the firewall shape, and refuse to finish if it is wrong ------
/usr/local/sbin/clawfactory-fw-assert.sh || fatal "egress chain shape check failed; refusing to complete the send install"

# --- g. prove the broker answers THE AGENT on the request socket ------------
ok=0
for _ in $(seq 1 30); do
    if [ -S /run/clawfactory/send.sock ]; then
        if setpriv --reuid="$AGENT_UID" --regid="$AGENT_GID" --clear-groups \
             "$NODE" -e '
               const net=require("node:net");
               const s=net.createConnection("/run/clawfactory/send.sock");
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

# --- h. PAIRED NEGATIVE CONTROL: the agent must NOT reach the approval socket -
# The positive probe above proves reachability. On its own it proves nothing
# about isolation, and a test whose control does not fail is a void result. So
# assert the other half here, at install time, on the same channel.
if setpriv --reuid="$AGENT_UID" --regid="$AGENT_GID" --clear-groups \
     "$NODE" -e '
       const net=require("node:net");
       const s=net.createConnection("/run/clawfactory/send-admin.sock");
       s.on("connect",()=>{s.write(JSON.stringify({op:"list"})+"\n");});
       s.on("data",()=>process.exit(0));
       s.on("error",()=>process.exit(3));
       setTimeout(()=>process.exit(3),5000);
     ' 2>/dev/null; then
    fatal "SECURITY: $AGENT_USER reached the approval socket. Refusing to complete the install."
fi

echo "[send] broker live on /run/clawfactory/send.sock (agent request channel, 0660 root:$AGENT_USER)"
echo "[send] approval channel on /run/clawfactory/send-admin.sock (0600 root:root, unreachable by $AGENT_USER)"
echo "[send] no destination is authorized until SMTP is configured in Studio (fail-closed)"
