# GENERATED, DO NOT EDIT. The firewall block of resources/switch-provider.ps1 as it
# stood at commit 9710c5a (v1.3.4), rendered with PROVIDER_HOST=api.anthropic.com.
#
# This is the DEFECTIVE pre-fix text, retained ONLY as the measurement reference for
# card #258 test 4. It re-seeds seven toolchain hostnames into @allowed_ipv4, the set
# nothing can revoke, which is the defect under demonstration. Never install this.
#
# Rendered from git rather than hand-copied so it is provably the shipped 1.3.4 text.
set -euo pipefail

# Full baseHosts list -- must stay in sync with setup.ps1 Step-EgressFirewall.
# 16 hosts: github (4) + openclaw/clawhub (4) + npm/node (3) + ubuntu apt (5).
# (Docker Hub hosts removed with Docker itself -- SECFIX_CLOSE_DOORS decision A.)
BASE_HOSTS="api.github.com github.com raw.githubusercontent.com codeload.github.com openclaw.ai docs.openclaw.ai clawhub.ai api.clawhub.ai registry.npmjs.org nodejs.org deb.nodesource.com archive.ubuntu.com security.ubuntu.com ports.ubuntu.com esm.ubuntu.com ppa.launchpad.net"
PROVIDER_HOST="api.anthropic.com"

# Resolve all allowlist hosts to IPv4s.
ALLOWED_IPS=""
for h in $BASE_HOSTS $PROVIDER_HOST; do
    [ -z "$h" ] && continue
    for ip in $(getent ahostsv4 "$h" 2>/dev/null | awk '{print $1}' | sort -u); do
        ALLOWED_IPS="$ALLOWED_IPS $ip"
    done
done

# Detect active backend (set by setup.ps1 Step-EgressFirewall at install).
BACKEND="$(cat /etc/clawfactory/fw-backend 2>/dev/null || echo nftables)"

# Defect 1: restrict port 53 to the WSL resolver(s). The allowlist helper is
# installed by setup.ps1 Step-EgressFirewall; fall back to the persisted list.
# Must stay in sync with setup.ps1 Step-EgressFirewall's DNS restriction.
if [ -x /usr/local/sbin/clawfactory-dns-resolvers.sh ]; then
    CF_RESOLVERS="$(/usr/local/sbin/clawfactory-dns-resolvers.sh)"
else
    CF_RESOLVERS="$(cat /etc/clawfactory/dns-resolvers.txt 2>/dev/null)"
fi
printf '%s\n' $CF_RESOLVERS | sed '/^$/d' > /etc/clawfactory/dns-resolvers.txt

if [ "$BACKEND" = "iptables-legacy" ]; then
    IPT="$(command -v iptables-legacy || true)"
    [ -n "$IPT" ] || { echo "[switch-provider] iptables-legacy missing" >&2; exit 1; }
    "$IPT" -F OUTPUT
    "$IPT" -A OUTPUT -m owner --uid-owner clawuser -o lo -j ACCEPT
    for ip in $CF_RESOLVERS; do
        "$IPT" -A OUTPUT -m owner --uid-owner clawuser -d "$ip" -p udp --dport 53 -j ACCEPT
        "$IPT" -A OUTPUT -m owner --uid-owner clawuser -d "$ip" -p tcp --dport 53 -j ACCEPT
    done
    "$IPT" -A OUTPUT -m owner --uid-owner clawuser -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
    for ip in $ALLOWED_IPS; do
        "$IPT" -A OUTPUT -m owner --uid-owner clawuser -d "$ip" -p tcp --dport 443 -j ACCEPT
    done
    "$IPT" -A OUTPUT -m owner --uid-owner clawuser -d 127.0.0.1 -p tcp --dport 11434 -j ACCEPT
    "$IPT" -A OUTPUT -m owner --uid-owner clawuser -j DROP
else
    /usr/sbin/nft flush set inet clawfactory allowed_ipv4 2>/dev/null || true
    for ip in $ALLOWED_IPS; do
        /usr/sbin/nft add element inet clawfactory allowed_ipv4 "{ $ip }" 2>/dev/null || true
    done
    # Defect 1: refresh the DNS resolver set too (in case resolv.conf changed).
    /usr/sbin/nft flush set inet clawfactory dns_resolvers 2>/dev/null || true
    for ip in $CF_RESOLVERS; do
        /usr/sbin/nft add element inet clawfactory dns_resolvers "{ $ip }" 2>/dev/null || true
    done
fi

# Persist for boot-time apply (clawfactory-fw.service reads this file).
mkdir -p /etc/clawfactory
printf '%s\n' $ALLOWED_IPS | sed '/^$/d' > /etc/clawfactory/allowed-ips.txt

HOST_COUNT=$(echo $BASE_HOSTS $PROVIDER_HOST | wc -w)
IP_COUNT=$(echo $ALLOWED_IPS | wc -w)
echo "[switch-provider] firewall updated; backend=$BACKEND; hosts=$HOST_COUNT; ips=$IP_COUNT"