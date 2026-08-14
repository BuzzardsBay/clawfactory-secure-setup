#!/usr/bin/env bash
# clawfactory-read-fetch.sh -- Guard 3's enforcement step.
#
# Installed to /usr/local/sbin/clawfactory-read-fetch.sh, root:root 0755.
#
# WHAT THIS IS. Outbound web fetching by the agent is denied by default. That
# denial is NOT created here: it already exists, because the egress chain scopes
# itself to uid 1000 and ends in a terminal drop, so any destination that is not
# in an allowlisted set is unreachable. What this script does is give the USER a
# way to open a named hole in that denial, and to close it again.
#
# WHY A SECOND SET RATHER THAN REUSING @allowed_ipv4. The provider set is
# refreshed ADDITIVELY by hostname every five hours and its elements carry a
# timeout. Nothing ever removes an element deliberately. A user destination
# placed in it could not be revoked: the next refresh would leave the address
# behind and the user's removal would silently not take. @read_fetch_ipv4 is
# flushed and rebuilt from the policy file on every run, so removing a site in
# Studio actually removes its route.
#
# FAIL CLOSED, AND THE ORDER OF OPERATIONS IS THE MECHANISM. The set is flushed
# BEFORE anything is resolved or added. Every failure path therefore leaves the
# set narrower than it was, never wider. An unreadable or malformed policy file
# ends with an empty set and a loud message, which denies every read-fetch
# destination while leaving the provider route untouched, because the provider
# route lives in a different set and this script never touches it.
#
# WHAT THIS DOES NOT CLAIM. Matching is by IP ADDRESS, because that is the only
# thing an nftables set can hold. A hostname that resolves to an address already
# reachable for another reason is reachable regardless of whether the user
# listed it. See SECURITY_FINDINGS.md; the close-out states this plainly.

set -uo pipefail

POLICY=/etc/clawfactory/egress-policy.json
IPS_FILE=/etc/clawfactory/read-fetch-ips.txt
HOSTS_FILE=/etc/clawfactory/read-fetch-hosts.txt
MAX_IPS=512

note() { echo "[read-fetch] $*"; }
loud() { echo "[read-fetch] $*" >&2; }

if [ "$(id -u)" != "0" ]; then
    loud "must run as root"
    exit 1
fi

BACKEND="$(cat /etc/clawfactory/fw-backend 2>/dev/null || echo nftables)"

# --- 1. Flush first. Every exit after this point is fail-closed. -------------
if [ "$BACKEND" = "nftables" ]; then
    if nft list set inet clawfactory read_fetch_ipv4 >/dev/null 2>&1; then
        nft flush set inet clawfactory read_fetch_ipv4 2>/dev/null || true
    else
        # The set is absent, so there is no read-fetch accept path at all. That
        # is the denied state, which is safe, but it means Guard 3 is not
        # actually installed and saying so is more useful than succeeding.
        loud "set inet clawfactory read_fetch_ipv4 is absent; Guard 3 is not applied to the live firewall"
        loud "read-fetch destinations are ALL DENIED until the firewall is re-applied"
    fi
fi

# --- 2. Extract the host list from the root-owned policy file ----------------
# Parsed by node rather than by shell text-mangling: this input is a file the
# UI writes, and a hand-rolled JSON reader is how a stray quote becomes a
# command. Node is already a hard dependency of all three brokers.
NODE="$(command -v node || echo /usr/bin/node)"
HOSTS=""
POLICY_OK=0
if [ ! -x "$NODE" ]; then
    loud "node is missing; cannot read $POLICY. All read-fetch destinations stay denied."
elif HOSTS="$("$NODE" -e '
const fs = require("node:fs");
// Deliberately strict. A destination is a bare hostname or an IPv4 literal:
// no scheme, no port, no path, no wildcard, no uppercase. Anything else is
// refused rather than normalised, because guessing what a user meant is how a
// wildcard gets into an allowlist.
const RE = /^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)+$/;
const raw = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
const rf = raw && raw.read_fetch;
const list = rf && Array.isArray(rf.allow) ? rf.allow : [];
const out = [];
for (const e of list) {
  const h = typeof e === "string" ? e : e && e.host;
  const s = String(h == null ? "" : h).trim().toLowerCase();
  if (!s || s.length > 253 || !RE.test(s)) {
    process.stderr.write(`[read-fetch] refusing malformed destination: ${JSON.stringify(h)}\n`);
    continue;
  }
  if (!out.includes(s)) out.push(s);
}
process.stdout.write(out.join("\n"));
' "$POLICY" 2>/dev/null)"; then
    POLICY_OK=1
else
    loud "cannot read or parse $POLICY. All read-fetch destinations stay denied."
    HOSTS=""
fi

if [ "$POLICY_OK" = "1" ]; then
    printf '%s\n' "$HOSTS" | sed '/^$/d' > "$HOSTS_FILE"
    chown root:root "$HOSTS_FILE" 2>/dev/null || true
    chmod 644 "$HOSTS_FILE" 2>/dev/null || true
fi

# --- 3. Resolve, with a cap that is announced rather than silent -------------
RESOLVED=""
COUNT=0
TRUNCATED=0
for h in $HOSTS; do
    # Belt and braces: the node filter already refused anything but a hostname
    # or an IPv4 literal, and this refuses it again before the value reaches a
    # command. Two filters because only one of them is in the file a reader is
    # likely to check.
    case "$h" in
        *[!a-z0-9.-]*|-*|.*|"") loud "skipping unexpected destination: $h"; continue ;;
    esac
    GOT="$(getent ahostsv4 "$h" 2>/dev/null | awk '{print $1}' | sort -u)"
    if [ -z "$GOT" ]; then
        loud "cannot resolve $h; it stays denied"
        continue
    fi
    for ip in $GOT; do
        if [ "$COUNT" -ge "$MAX_IPS" ]; then TRUNCATED=1; break; fi
        RESOLVED="$RESOLVED $ip"
        COUNT=$((COUNT + 1))
    done
done
if [ "$TRUNCATED" = "1" ]; then
    loud "the read-fetch list resolved to more than $MAX_IPS addresses; the remainder were NOT added and stay denied"
fi

# --- 4. Persist, so the boot path rebuilds the same set ----------------------
printf '%s\n' $RESOLVED | sed '/^$/d' | sort -u > "$IPS_FILE"
chown root:root "$IPS_FILE" 2>/dev/null || true
chmod 644 "$IPS_FILE" 2>/dev/null || true

# --- 5. Apply to the live firewall ------------------------------------------
if [ "$BACKEND" = "nftables" ]; then
    if nft list set inet clawfactory read_fetch_ipv4 >/dev/null 2>&1; then
        while IFS= read -r ip; do
            [ -n "$ip" ] || continue
            nft add element inet clawfactory read_fetch_ipv4 "{ $ip }" 2>/dev/null || true
        done < "$IPS_FILE"
    fi
elif [ "$BACKEND" = "iptables-legacy" ]; then
    # The iptables fallback has no set to flush, so a removal can only take
    # effect by rebuilding the whole chain. fw-apply.sh reads both persisted
    # files and is the single place that knows the chain order.
    if [ -x /usr/local/sbin/clawfactory-fw-apply.sh ]; then
        /usr/local/sbin/clawfactory-fw-apply.sh || loud "fw-apply failed; the live chain may not match the policy"
    else
        loud "clawfactory-fw-apply.sh is missing; cannot apply the read-fetch list on this backend"
    fi
fi

NHOSTS="$(printf '%s\n' $HOSTS | sed '/^$/d' | wc -l | tr -d ' ')"
NIPS="$(wc -l < "$IPS_FILE" | tr -d ' ')"
note "backend=$BACKEND hosts=$NHOSTS addresses=$NIPS (0 hosts means every read-fetch destination is denied)"
exit 0
