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
MAP_FILE=/etc/clawfactory/read-fetch-ips.map
MAX_IPS=512

# How many times to resolve each host before building the set.
#
# THIS USED TO BE ONE, AND ONE IS WRONG FOR THE SAME REASON IT IS WRONG IN
# clawfactory-toolchain.sh. A rotating pool answers with a different address on
# roughly every other lookup, so a set built from a single lookup misses the
# address the next connection actually uses and the host is intermittently
# unreachable while the panel still lists it. The toolchain resolver has carried
# a three-pass union since it was written; this one did not, and the difference
# was never deliberate. A site the USER allowed failing intermittently is worse
# than a software source doing it, because the user chose that site by hand.
#
# Kept identical to RESOLVE_PASSES in clawfactory-toolchain.sh on purpose. If
# one moves, move both.
RESOLVE_PASSES=3

# See the retention block in section 3, and the matching constant in
# clawfactory-toolchain.sh.
RETAIN_MAX_AGE=86400

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
#
# RETENTION, AND WHY IT IS PER-HOST. Until v1.4.1 a run that resolved nothing
# wrote an EMPTY file. At boot that is destructive rather than merely cautious:
# fw-apply.sh replays the persisted addresses BEFORE DNS is necessarily up, and
# a resolver run in that window emptied the set it had just replayed. A site the
# USER allowed then stopped working while the panel still listed it -- Guard 3's
# headline feature failing quietly on the user's own choice.
#
# THE REVOCATION GUARANTEE, WHICH MATTERS MORE HERE THAN IN THE TOOLCHAIN
# RESOLVER, BECAUSE THIS LIST IS THE USER'S. Retention is keyed by HOST and the
# map is rebuilt from $HOSTS, which is the list just parsed out of the policy
# file. A host the user REMOVED in Studio is not in $HOSTS, so it is never
# looked up, nothing is carried forward for it, and its old lines are dropped
# when the map is rewritten below. There is no path by which a removed site
# returns at boot. An unreadable or malformed policy leaves $HOSTS empty, so the
# same rewrite empties both files: a fault denies everything.
#
# $MAP_FILE input shapes are decided exactly as in clawfactory-toolchain.sh:
# absent or empty means no retention; a malformed line is DROPPED and counted
# rather than guessed at; the address is re-validated against a strict IPv4
# pattern before it can reach the firewall; a future timestamp is a fault and
# expires immediately. Every one of those failures narrows the set.
NOW="$(date +%s)"
NEWMAP="${MAP_FILE}.tmp"
: > "$NEWMAP"
chmod 644 "$NEWMAP" 2>/dev/null || true

MAP_BAD=0
if [ -f "$MAP_FILE" ]; then
    MAP_BAD="$(awk -F'\t' '
        NF != 3 { bad++; next }
        $3 !~ /^[0-9]+$/ { bad++; next }
        $2 !~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/ { bad++; next }
        END { print bad + 0 }
    ' "$MAP_FILE" 2>/dev/null || echo 0)"
fi
[ -n "$MAP_BAD" ] || MAP_BAD=0
if [ "$MAP_BAD" -gt 0 ]; then
    loud "$MAP_FILE holds $MAP_BAD malformed line(s); each is DROPPED rather than guessed at, so those addresses are not carried forward"
fi

retain_for() {
    [ -f "$MAP_FILE" ] || return 0
    awk -F'\t' -v h="$1" -v now="$NOW" -v maxage="$RETAIN_MAX_AGE" '
        NF != 3 { next }
        $1 != h { next }
        $3 !~ /^[0-9]+$/ { next }
        $2 !~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/ { next }
        (now - $3) < 0 { next }
        (now - $3) > maxage { next }
        { print $2 "\t" $3 }
    ' "$MAP_FILE"
}

RESOLVED=""
COUNT=0
TRUNCATED=0
HOSTS_TOTAL=0
HOSTS_OK=0
HOSTS_FAILED=0
RETAINED=0
for h in $HOSTS; do
    # Belt and braces: the node filter already refused anything but a hostname
    # or an IPv4 literal, and this refuses it again before the value reaches a
    # command. Two filters because only one of them is in the file a reader is
    # likely to check.
    case "$h" in
        *[!a-z0-9.-]*|-*|.*|"") loud "skipping unexpected destination: $h"; continue ;;
    esac
    HOSTS_TOTAL=$((HOSTS_TOTAL + 1))
    # Several passes, unioned. See RESOLVE_PASSES above.
    GOT=""
    p=0
    while [ "$p" -lt "$RESOLVE_PASSES" ]; do
        GOT="$GOT $(getent ahostsv4 "$h" 2>/dev/null | awk '{print $1}')"
        p=$((p + 1))
    done
    GOT="$(printf '%s\n' $GOT | sed '/^$/d' | sort -u)"
    if [ -n "$GOT" ]; then
        HOSTS_OK=$((HOSTS_OK + 1))
        for ip in $GOT; do printf '%s\t%s\t%s\n' "$h" "$ip" "$NOW" >> "$NEWMAP"; done
    else
        HOSTS_FAILED=$((HOSTS_FAILED + 1))
        KEPT="$(retain_for "$h")"
        if [ -n "$KEPT" ]; then
            NKEPT="$(printf '%s\n' "$KEPT" | sed '/^$/d' | wc -l | tr -d ' ')"
            RETAINED=$((RETAINED + NKEPT))
            loud "cannot resolve $h right now; KEEPING the $NKEPT address(es) last resolved for it rather than emptying the set. You allowed this site, so a lookup failure denies it rather than the site being dropped, and the addresses expire after $RETAIN_MAX_AGE seconds without a successful lookup."
            GOT="$(printf '%s\n' "$KEPT" | awk -F'\t' 'NF==2 {print $1}')"
            printf '%s\n' "$KEPT" | awk -F'\t' -v h="$h" 'NF==2 {printf "%s\t%s\t%s\n", h, $1, $2}' >> "$NEWMAP"
        else
            loud "cannot resolve $h and nothing recent is recorded for it; it stays denied"
            continue
        fi
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
# The map is rewritten from the CURRENT host list on every run, including the
# empty one. That is what makes a removal take effect: a host the user deleted
# contributes no lines here, so nothing about it survives into the next boot.
printf '%s\n' $RESOLVED | sed '/^$/d' | sort -u > "$IPS_FILE"
chown root:root "$IPS_FILE" 2>/dev/null || true
chmod 644 "$IPS_FILE" 2>/dev/null || true
mv -f "$NEWMAP" "$MAP_FILE" 2>/dev/null || { loud "could not update $MAP_FILE; retention will use the previous copy"; rm -f "$NEWMAP" 2>/dev/null || true; }
chown root:root "$MAP_FILE" 2>/dev/null || true
chmod 644 "$MAP_FILE" 2>/dev/null || true

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
# Machine-readable, for clawfactory-egress-refresh.sh to decide whether DNS was
# up. See the matching TOOLCHAIN_STATUS line in clawfactory-toolchain.sh.
note "READFETCH_STATUS hosts=$HOSTS_TOTAL resolved=$HOSTS_OK failed=$HOSTS_FAILED retained=$RETAINED addresses=$NIPS backend=$BACKEND"
note "backend=$BACKEND hosts=$NHOSTS addresses=$NIPS (0 hosts means every read-fetch destination is denied)"
exit 0
