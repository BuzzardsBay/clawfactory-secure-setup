set +e
# Stop and disable gateway
sudo -u clawuser bash -c 'systemctl --user stop openclaw-gateway 2>/dev/null; systemctl --user disable openclaw-gateway 2>/dev/null' 2>/dev/null
# Flush the clawfactory nft chain (the iptables-legacy backend is still reachable
# on a WSL2 kernel without nftables; see setup.ps1 Step-EgressFirewall)
/usr/sbin/nft delete table inet clawfactory 2>/dev/null
# Clear immutable flags so the frozen safety files can be removed (Defect 2/4:
# SOUL.md + workspace SOUL are root:root chattr +i; rm/deluser fail otherwise).
chattr -i /home/clawuser/.openclaw/SOUL.md /home/clawuser/.openclaw/SOUL.md.sha256 /home/clawuser/.openclaw/workspace/SOUL.md 2>/dev/null
# Stop + remove the chatCompletions gating proxy and put the gateway back on its
# public port (Blocker 1). Order matters: drop the proxy BEFORE the drop-in, so
# nothing is left owning 8787.
systemctl disable --now clawfactory-proxy 2>/dev/null
rm -f /etc/systemd/system/clawfactory-proxy.service /usr/local/sbin/clawfactory-proxy.js 2>/dev/null
rm -f /home/clawuser/.config/systemd/user/openclaw-gateway.service.d/clawfactory-real-port.conf 2>/dev/null
systemctl daemon-reload 2>/dev/null
sudo -u clawuser XDG_RUNTIME_DIR=/run/user/1000 systemctl --user daemon-reload 2>/dev/null
# Remove the ClawFactory turn-gate shim + helper scripts (Defect 3). Removing
# /usr/bin/openclaw below drops the shim; the real .mjs is removed too.
rm -f /usr/local/sbin/clawfactory-turn-gate.sh /usr/local/sbin/clawfactory-spend-check.js /usr/local/sbin/clawfactory-dns-resolvers.sh /usr/local/sbin/clawfactory-fw-apply.sh 2>/dev/null
# Guard 3: the read-fetch resolver and its root-only control tool. The allowlist
# itself lives in /etc/clawfactory, which is removed wholesale further down --
# and that includes the two *-ips.map retention files added in v1.4.1.
# clawfactory-toolchain.sh was missing from this list -- a pre-existing leftover,
# noticed while adding the boot unit below. Not a security gap (the file is inert
# without the firewall and the policy it reads), but a file the uninstaller
# claims to clean and did not.
rm -f /usr/local/sbin/clawfactory-read-fetch.sh /usr/local/sbin/clawfactory-toolchain.sh /usr/local/sbin/clawfactory-fetchctl.js /usr/local/sbin/clawfactory-fetchctl 2>/dev/null
# Guard 3, v1.4.1: the boot-time refresh unit. Disabled BEFORE its script is
# removed, so systemd is not left with an enabled unit pointing at nothing --
# which on the next boot would be a failed unit in the journal of a machine that
# no longer has ClawFactory on it.
systemctl disable --now clawfactory-egress-refresh.service 2>/dev/null
rm -f /etc/systemd/system/clawfactory-egress-refresh.service /usr/local/sbin/clawfactory-egress-refresh.sh 2>/dev/null
systemctl daemon-reload 2>/dev/null
# Guard 1: delete quarantine. Say how many held files go with it -- these are the
# user's own files, and removing them silently during an uninstall is exactly the
# surprise this guard exists to prevent.
if [ -f /var/lib/clawfactory/quarantine/index.json ]; then
    HELD=$(node -e 'try{console.log(JSON.parse(require("fs").readFileSync("/var/lib/clawfactory/quarantine/index.json")).length)}catch{console.log(0)}' 2>/dev/null || echo 0)
    echo "[uninstall] removing the delete quarantine and the $HELD file(s) still held in it"
fi
systemctl disable --now clawfactory-quarantine.service clawfactory-quarantine-gc.timer 2>/dev/null
rm -f /etc/systemd/system/clawfactory-quarantine.service /etc/systemd/system/clawfactory-quarantine-gc.service /etc/systemd/system/clawfactory-quarantine-gc.timer 2>/dev/null
rm -f /usr/local/sbin/clawfactory-quarantined.js /usr/local/sbin/clawfactory-quarantinectl.js 2>/dev/null
# Undo the /usr/bin/rm divert BEFORE removing anything the wrapper depends on.
#
# Guard 1 takes over the name `rm` via dpkg-divert. If an uninstall left that in
# place, the user would be left with a node wrapper as their system rm and no
# broker behind it. That is our bug to prevent, on their machine, after they
# asked us to leave. Restore the stock binary and PROVE it works before moving on.
if command -v dpkg-divert >/dev/null 2>&1 && dpkg-divert --list /usr/bin/rm | grep -q 'rm.real'; then
    # Delete OUR wrapper first: --rename refuses to move the real binary back
    # while something else occupies the name.
    if head -1 /usr/bin/rm 2>/dev/null | grep -q node; then
        /usr/bin/rm.real -f /usr/bin/rm 2>/dev/null || rm -f /usr/bin/rm 2>/dev/null
    fi
    dpkg-divert --rename --remove /usr/bin/rm 2>/dev/null
fi
# Fail loud rather than leave a box that cannot delete files.
if [ ! -x /usr/bin/rm ] || head -1 /usr/bin/rm 2>/dev/null | grep -q node; then
    [ -x /usr/bin/rm.real ] && cp -a /usr/bin/rm.real /usr/bin/rm 2>/dev/null
    echo "[uninstall] WARNING: /usr/bin/rm was not restored cleanly. The stock binary is at /usr/bin/rm.real; restore it with: cp -a /usr/bin/rm.real /usr/bin/rm" >&2
else
    echo "[uninstall] /usr/bin/rm divert removed; stock rm restored"
fi
rm -rf /usr/local/lib/clawfactory /var/lib/clawfactory 2>/dev/null
rm -rf /etc/clawfactory 2>/dev/null
# Remove the openclaw global install
rm -rf /usr/lib/node_modules/openclaw 2>/dev/null
rm -f /usr/bin/openclaw /usr/local/bin/openclaw /bin/openclaw 2>/dev/null
# Remove clawuser home + the user itself
deluser --remove-home clawuser 2>/dev/null
# Drop the WSL default-user line we added
sed -i '/^\[user\]/,/^$/d' /etc/wsl.conf 2>/dev/null
echo OK
