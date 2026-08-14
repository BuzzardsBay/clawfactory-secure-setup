#!/usr/bin/env bash
# install-read-fetch.sh -- v1 Guard 3. Web off by default, allowlist only.
#
# Runs as root inside WSL, after install-send.sh, because the control tool loads
# the shared egress-policy helpers from send-lib.js and writes the same
# root-owned policy file.
#
# Installs:
#   /usr/local/sbin/clawfactory-read-fetch.sh   0755  the resolver, root-owned
#   /usr/local/sbin/clawfactory-fetchctl.js     0750  the only write path
#   /usr/local/sbin/clawfactory-fetchctl        0750  node wrapper for Studio
#
# WHAT GUARD 3 ADDS, STATED PRECISELY, because the wrong description is easy to
# write and hard to unwrite. It does NOT create the denial. The egress chain
# already scopes itself to uid 1000 and ends in a terminal drop, so a
# destination that is in no allowlisted set was already unreachable. Guard 3
# adds the USER-CONTROLLED way to open and close a named hole in that denial,
# and makes the previously inert read_fetch policy section the thing that
# governs it.
#
# It is structural with respect to the agent: the agent cannot write the policy
# file, cannot write the persisted address list, cannot run nft, and cannot
# escape the chain, which filters by uid rather than by process. It is NOT
# hostname-exact. nftables sets hold addresses, so any host sharing an address
# with something already reachable is reachable. That residual is stated in the
# close-out and must not be softened in customer copy.

set -euo pipefail

fatal() { echo "[install-read-fetch] FATAL: $*" >&2; exit 1; }
note()  { echo "[install-read-fetch] $*"; }

[ "$(id -u)" = "0" ] || fatal "must run as root"

NODE="$(command -v node || echo /usr/bin/node)"
[ -x "$NODE" ] || fatal "node is required and was not found"

# --- a. the resolver and the control tool ----------------------------------
for f in /usr/local/sbin/clawfactory-read-fetch.sh /usr/local/sbin/clawfactory-fetchctl.js; do
    [ -f "$f" ] || fatal "missing $f (the installer did not drop it)"
    chown root:root "$f"
done
chmod 755 /usr/local/sbin/clawfactory-read-fetch.sh
# 0750, matching clawfactory-sendctl.js. The agent must not even be able to read
# the write path, let alone run it.
chmod 750 /usr/local/sbin/clawfactory-fetchctl.js

[ -f /usr/local/lib/clawfactory/send-lib.js ] \
    || fatal "send-lib.js is absent; install-send.sh must run before this step"

cat > /usr/local/sbin/clawfactory-fetchctl <<WRAP
#!/bin/sh
exec "$NODE" /usr/local/sbin/clawfactory-fetchctl.js "\$@"
WRAP
chown root:root /usr/local/sbin/clawfactory-fetchctl
chmod 750 /usr/local/sbin/clawfactory-fetchctl

# --- b. the policy file must already carry the section ---------------------
# install-send.sh writes it and never clobbers an existing one, so the user's
# list survives a reinstall. Guard 3 only asserts that the section is there.
[ -f /etc/clawfactory/egress-policy.json ] \
    || fatal "/etc/clawfactory/egress-policy.json is absent; install-send.sh must run before this step"

"$NODE" -e '
const fs = require("node:fs");
const p = "/etc/clawfactory/egress-policy.json";
const raw = JSON.parse(fs.readFileSync(p, "utf8"));
if (!raw.read_fetch || !Array.isArray(raw.read_fetch.allow)) {
  raw.read_fetch = { allow: [] };
  fs.writeFileSync(p + ".tmp", JSON.stringify(raw, null, 2) + "\n", { mode: 0o644 });
  fs.renameSync(p + ".tmp", p);
  process.stdout.write("read_fetch section repaired to an empty allowlist\n");
} else {
  process.stdout.write("read_fetch section present with " + raw.read_fetch.allow.length + " destination(s)\n");
}
' || fatal "the egress policy file is not readable as JSON; refusing to continue"

chown root:root /etc/clawfactory/egress-policy.json
chmod 644 /etc/clawfactory/egress-policy.json

# --- c. apply once, so the set is populated from the policy rather than left
#        to the first timer tick ------------------------------------------
/usr/local/sbin/clawfactory-read-fetch.sh || fatal "the read-fetch resolver failed on its first run"

# --- d. prove the control is actually in the live chain --------------------
# A fresh install has an EMPTY read-fetch list, so "no read-fetch destination is
# reachable" is true whether or not Guard 3 installed correctly. Checking the
# empty outcome would therefore pass on a machine where nothing was installed.
# Check the mechanism instead: the set and its 443-scoped accept.
BACKEND="$(cat /etc/clawfactory/fw-backend 2>/dev/null || echo nftables)"
if [ "$BACKEND" = "nftables" ]; then
    nft list set inet clawfactory read_fetch_ipv4 >/dev/null 2>&1 \
        || fatal "set inet clawfactory read_fetch_ipv4 is missing from the live ruleset; Guard 3 would claim a control it does not have"
    nft list chain inet clawfactory output 2>/dev/null \
        | grep -qE '@read_fetch_ipv4 tcp dport 443 accept' \
        || fatal "the read-fetch accept is missing or is not scoped to tcp dport 443"
    note "live chain carries @read_fetch_ipv4 with a 443-scoped accept"
else
    note "backend=$BACKEND: the read-fetch list is applied as individual ACCEPT rules by fw-apply.sh"
fi

# --- e. the tripwire must now cover Guard 3 too -----------------------------
if [ -x /usr/local/sbin/clawfactory-fw-assert.sh ]; then
    /usr/local/sbin/clawfactory-fw-assert.sh \
        || fatal "the chain-shape tripwire failed after installing Guard 3"
fi

note "Guard 3 installed. Read-fetch destinations: $(wc -l < /etc/clawfactory/read-fetch-ips.txt | tr -d ' ') address(es) from the policy allowlist."
note "A fresh install has an empty allowlist, which means the agent can fetch nothing beyond the provider and toolchain route."
