#!/usr/bin/env bash
# clawfactory-toolchain.sh -- the toolchain access toggle's enforcement step.
#
# Installed to /usr/local/sbin/clawfactory-toolchain.sh, root:root 0755.
#
# WHAT THIS IS. ClawFactory's baseline egress allowlist was never "the model
# provider". It was ten hostnames: three providers plus the software sources the
# agent needs to do its job. On a measured box those ten resolved to 72 live
# addresses, including GitHub's shared content CDN and roughly two dozen
# Cloudflare edges. So "a fresh install reaches the provider and nothing else"
# was false before Guard 3 existed, and the close-out said so.
#
# This script splits that baseline in half and puts the second half under the
# user's control. Provider hosts stay always-open, in @allowed_ipv4, untouched by
# this file: an agent that cannot reach its model is a bricked product. The
# TOOLCHAIN hosts below move into their own set, which this script flushes and
# rebuilds on every run, so the user's switch actually takes effect.
#
# WHY NOT DEFAULT OFF. Defaulting off ships a product where skill installation,
# npm and GitHub fail on a fresh box, which is a functional regression in the
# agent's core workflows. It also buys no honesty: the claim sentence the product
# makes already names the software sources explicitly, so nothing is being
# concealed by leaving them reachable. What the toggle buys is CONTROL. A user
# who wants a narrower box can have one, and accepts that skill install stops
# working. The toggle only ever NARROWS, so the claim sentence holds either way.
#
# WHY A THIRD SET RATHER THAN REUSING @allowed_ipv4. Exactly the reason Guard 3
# needed a second one, applied again. @allowed_ipv4 is refreshed ADDITIVELY by
# hostname every five hours and its elements carry a timeout; nothing is ever
# removed from it deliberately. An address placed there cannot be revoked, so a
# user who switched the toolchain off would find it back within five hours and
# the switch would silently not have taken. That is the single most likely way
# this feature could appear to work and not work, so it gets its own test.
#
# FAIL CLOSED, BY ORDERING. The set is flushed BEFORE anything is resolved or
# added, so every failure path leaves the set NARROWER than it was, never wider.
# An unreadable or malformed policy file ends with an empty set and a loud
# message, which denies the toolchain route while leaving the provider route
# untouched, because the provider route lives in a different set and this script
# never touches it.
#
# WHAT THIS DOES NOT CLAIM. Matching is by resolved ADDRESS, because that is the
# only thing an nftables set can hold. Switching the toolchain off removes these
# addresses from this set; it does not make a host unreachable if the same
# address is reachable for another reason, such as a provider that shares a CDN
# edge with it. This inherits Guard 3's address-scoping residual in full and must
# never be described as hostname-exact.

set -uo pipefail

POLICY=/etc/clawfactory/egress-policy.json
IPS_FILE=/etc/clawfactory/toolchain-ips.txt
MAX_IPS=512

# THE TOOLCHAIN HOST LIST, and it lives HERE on purpose.
#
# This file is root:root 0755, so the agent cannot edit the list, and the list is
# not a user-editable policy value: the user's control is the on/off switch, not
# the membership. Keeping the names in one root-owned place also stops the
# duplication that bit the provider list, which was copied into two blocks of
# setup.ps1 and had to be kept in step by hand.
#
# clawhub.ai and api.clawhub.ai are what skill installation talks to. The GitHub
# and npm entries are what the agent fetches code through. The panel copy names
# both consequences.
#
# THIS LIST MUST BE THE EXACT COMPLEMENT of what was removed from $baseHosts and
# AUX_HOSTS in setup.ps1. A host in both places is unrevocable (its address is
# re-seeded into @allowed_ipv4, where nothing removes it) and the switch silently
# fails to close it. A host in neither is unreachable even with the switch ON.
# Measured on cfv-164: github.com, codeload.github.com and api.clawhub.ai were
# missing here while still present in $baseHosts, so the switch could not close
# them and the validation caught it.
TOOLCHAIN_HOSTS="clawhub.ai api.clawhub.ai api.github.com github.com raw.githubusercontent.com objects.githubusercontent.com codeload.github.com registry.npmjs.org"

# How many times to resolve each host before building the set.
#
# A ROTATING POOL is why this is not 1. api.github.com answers with a different
# address on roughly every other lookup (measured on cfv-164: 140.82.116.6 and
# 20.29.134.17 across five lookups), so a set built from ONE lookup misses the
# address the next connection actually uses, and the host is intermittently
# unreachable while the switch reads ON.
#
# The provider set does not have this problem, but only by accident: it is
# refreshed ADDITIVELY with element timeouts, so it accumulates a pool over hours.
# This set is flushed and rebuilt every run, which is what makes revocation work
# at all, and the cost of that is losing the accumulation. Resolving several times
# and taking the union buys back most of the pool WITHOUT giving up revocation,
# because the union is still discarded and rebuilt on the next run.
#
# Three is a deliberate compromise. It is enough to catch an alternating pool,
# cheap enough to run on a five-hourly timer, and it is not a substitute for the
# residual being documented: no number of lookups makes address matching into
# hostname matching.
RESOLVE_PASSES=3

note() { echo "[toolchain] $*"; }
loud() { echo "[toolchain] $*" >&2; }

# --list-hosts prints the list and exits, so install-read-fetch.sh can reconcile
# it against the copy setup.ps1 seeded WITHOUT scraping this file's source text.
#
# The first version of that reconciliation did scrape, with a sed that only
# matched a single-line assignment, and this list was backslash-continued across
# three lines. It parsed to EMPTY and would have failed the install claiming
# total drift. Fail-closed, so not dangerous, but wrong about the reason, and a
# check that reports the wrong reason sends the next person to the wrong place.
# Having the program report its own value removes the parsing surface entirely.
if [ "${1:-}" = "--list-hosts" ]; then
    printf '%s\n' "$TOOLCHAIN_HOSTS"
    exit 0
fi

if [ "$(id -u)" != "0" ]; then
    loud "must run as root"
    exit 1
fi

BACKEND="$(cat /etc/clawfactory/fw-backend 2>/dev/null || echo nftables)"

# --- 1. Flush first. Every exit after this point is fail-closed. -------------
if [ "$BACKEND" = "nftables" ]; then
    if nft list set inet clawfactory toolchain_ipv4 >/dev/null 2>&1; then
        nft flush set inet clawfactory toolchain_ipv4 2>/dev/null || true
    else
        # Absent set means no toolchain accept path at all, which is the denied
        # state and therefore safe, but it also means the control the product
        # describes is not installed. Saying so is more useful than succeeding.
        loud "set inet clawfactory toolchain_ipv4 is absent; the toolchain toggle is not applied to the live firewall"
        loud "toolchain destinations are ALL DENIED until the firewall is re-applied"
    fi
fi

# --- 2. Read the toggle from the root-owned policy file ----------------------
# Parsed by node rather than by shell text-mangling, for the same reason the
# read-fetch resolver is: this input is a file the UI writes, and a hand-rolled
# JSON reader is how a stray quote becomes a command.
#
# THE DEFAULT IS ON, AND THE DEFAULT FOR AN UNREADABLE FILE IS OFF. Those are
# different questions and conflating them is how a parse error silently widens a
# firewall. An ABSENT key means a policy file written before this feature
# existed, and the documented default for that is enabled. A file that cannot be
# read or parsed at all is a fault, and a fault denies.
NODE="$(command -v node || echo /usr/bin/node)"
ENABLED=0
if [ ! -x "$NODE" ]; then
    loud "node is missing; cannot read $POLICY. The toolchain route stays denied."
elif STATE="$("$NODE" -e '
const fs = require("node:fs");
const raw = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
const t = raw ? raw.toolchain : undefined;
// THREE cases, and keeping them apart is the whole point. Collapsing "absent"
// into "malformed" would break upgrades; collapsing "malformed" into "absent"
// would let a garbage value open a firewall, which is the direction that costs
// something.
//
//   ABSENT     -> ON. A policy file written before this feature has no toolchain
//                 key, and the documented meaning of that is the pre-feature
//                 behaviour, which was reachable.
//   MALFORMED  -> OFF. Present but the wrong shape is a FAULT, not a preference,
//                 and a fault denies. This includes a non-object toolchain value
//                 and a non-boolean enabled: the string "true" is NOT true here,
//                 because something that writes a string into this field is not
//                 something whose intent should be guessed.
//   BOOLEAN    -> exactly what it says.
if (t === undefined || t === null) {
  process.stdout.write("TOOLCHAIN=on-default");
} else if (typeof t !== "object" || Array.isArray(t)) {
  process.stderr.write("[toolchain] the toolchain policy section is not an object; treating as OFF\n");
  process.stdout.write("TOOLCHAIN=off-malformed");
} else if (t.enabled === undefined || t.enabled === null) {
  process.stdout.write("TOOLCHAIN=on-default");
} else if (t.enabled === true) {
  process.stdout.write("TOOLCHAIN=on");
} else if (t.enabled === false) {
  process.stdout.write("TOOLCHAIN=off");
} else {
  process.stderr.write("[toolchain] toolchain.enabled is not a boolean; treating as OFF\n");
  process.stdout.write("TOOLCHAIN=off-malformed");
}
' "$POLICY" 2>/dev/null)"; then
    case "$STATE" in
        TOOLCHAIN=on|TOOLCHAIN=on-default) ENABLED=1 ;;
        *) ENABLED=0 ;;
    esac
    note "policy says $STATE"
else
    loud "cannot read or parse $POLICY. The toolchain route stays denied."
    ENABLED=0
fi

# --- 3. Resolve, only if enabled --------------------------------------------
RESOLVED=""
COUNT=0
TRUNCATED=0
if [ "$ENABLED" = "1" ]; then
    for h in $TOOLCHAIN_HOSTS; do
        # Belt and braces. The list is a root-owned constant in this file rather
        # than user input, so this cannot currently fire; it is here so that if a
        # future change ever makes the list configurable, the value is filtered
        # before it reaches a command rather than after somebody remembers.
        case "$h" in
            *[!a-z0-9.-]*|-*|.*|"") loud "skipping unexpected toolchain host: $h"; continue ;;
        esac
        # Several passes, unioned. See RESOLVE_PASSES above: a single lookup misses
        # half of a rotating pool, and the host is then intermittently unreachable
        # while the switch reads ON.
        GOT=""
        p=0
        while [ "$p" -lt "$RESOLVE_PASSES" ]; do
            GOT="$GOT $(getent ahostsv4 "$h" 2>/dev/null | awk '{print $1}')"
            p=$((p + 1))
        done
        GOT="$(printf '%s\n' $GOT | sed '/^$/d' | sort -u)"
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
        loud "the toolchain list resolved to more than $MAX_IPS addresses; the remainder were NOT added and stay denied"
    fi
fi

# --- 4. Persist, so the boot path rebuilds the same set ----------------------
# Written unconditionally. When the toggle is OFF this TRUNCATES the file to
# empty, which is the point: fw-apply.sh reads it at boot, and a stale file would
# re-open at the next restart a route the user closed.
printf '%s\n' $RESOLVED | sed '/^$/d' | sort -u > "$IPS_FILE"
chown root:root "$IPS_FILE" 2>/dev/null || true
chmod 644 "$IPS_FILE" 2>/dev/null || true

# --- 5. Apply to the live firewall ------------------------------------------
if [ "$BACKEND" = "nftables" ]; then
    if nft list set inet clawfactory toolchain_ipv4 >/dev/null 2>&1; then
        while IFS= read -r ip; do
            [ -n "$ip" ] || continue
            nft add element inet clawfactory toolchain_ipv4 "{ $ip }" 2>/dev/null || true
        done < "$IPS_FILE"
    fi
elif [ "$BACKEND" = "iptables-legacy" ]; then
    # The iptables fallback has no set to flush, so a revocation can only take
    # effect by rebuilding the whole chain. fw-apply.sh reads all three persisted
    # files and is the single place that knows the chain order.
    if [ -x /usr/local/sbin/clawfactory-fw-apply.sh ]; then
        /usr/local/sbin/clawfactory-fw-apply.sh || loud "fw-apply failed; the live chain may not match the policy"
    else
        loud "clawfactory-fw-apply.sh is missing; cannot apply the toolchain list on this backend"
    fi
fi

NIPS="$(wc -l < "$IPS_FILE" | tr -d ' ')"
if [ "$ENABLED" = "1" ]; then
    note "backend=$BACKEND toolchain=ON addresses=$NIPS (skill installation, GitHub and npm are reachable)"
else
    note "backend=$BACKEND toolchain=OFF addresses=$NIPS (skill installation, GitHub and npm are denied; the provider route is untouched)"
fi
exit 0
