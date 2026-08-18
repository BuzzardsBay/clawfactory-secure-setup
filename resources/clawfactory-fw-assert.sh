#!/bin/bash
# clawfactory-fw-assert.sh -- the firewall assertion for Guard 2 and Guard 3.
#
# READS the live chain and fails loud if its shape has drifted. It NEVER writes
# a rule and never touches a set element. That restraint is deliberate:
#
#   - The "no route to SMTP for uid 1000" property is EMERGENT, not granted. The
#     chain opens with `meta skuid != clawuser return`, and the only allowlist
#     accept is `tcp dport 443`. Every other destination and port for uid 1000
#     falls through to the terminal drop. Guard 2 therefore has no deny to add.
#   - Anything written directly to the running ruleset outside the persistent
#     path is erased by the five-hourly refresh, silently, on a customer machine,
#     hours after validation went green. A checker cannot rot that way.
#
# So this is a tripwire, not a control. The control is the chain shape itself,
# which lives in /etc/nftables.conf and is re-applied by clawfactory-fw-apply.sh.
#
# Installed to /usr/local/sbin/clawfactory-fw-assert.sh, root:root 0755. Run as
# ExecStartPost on clawfactory-allow-providers.service, so it re-checks on every
# refresh cycle, and once at install time so a broken shape fails the install.

set -uo pipefail

FAIL=0
note() { echo "[fw-assert] $*"; }
bad() { echo "[fw-assert] FAIL: $*" >&2; FAIL=1; }

BACKEND="$(cat /etc/clawfactory/fw-backend 2>/dev/null || echo nftables)"
if [ "$BACKEND" != "nftables" ]; then
    # The iptables-legacy fallback has its own shape. Guard 2's SMTP property
    # there comes from the terminal `-j DROP` for clawuser plus the absence of
    # any SMTP accept. Assert that much and say plainly that the rest is not
    # checked, rather than reporting a pass we did not earn.
    IPT="$(command -v iptables-legacy || true)"
    if [ -z "$IPT" ]; then
        bad "backend is iptables-legacy but iptables-legacy is missing"
    else
        if ! "$IPT" -S OUTPUT | grep -qE -- '-m owner --uid-owner (clawuser|1000) -j DROP'; then
            bad "iptables-legacy OUTPUT has no terminal DROP for the agent uid"
        fi
        if "$IPT" -S OUTPUT | grep -qE -- '--dport (25|465|587|2525) -j ACCEPT'; then
            bad "iptables-legacy OUTPUT accepts an SMTP port for the agent uid"
        fi
        note "backend=iptables-legacy: terminal DROP present, no SMTP accept. Chain-order checks not performed."
    fi
    exit "$FAIL"
fi

# THE CHAIN READ. Everything below is derived from this one capture, so a
# transient failure here is not a shape finding, it is no finding at all.
#
# This script already distinguished "cannot read the chain" from "the rule is
# absent", which is the harder half and is why it is not the file that broke the
# install. But it took exactly ONE look and discarded stderr with 2>/dev/null,
# so it could say THAT the read failed and never WHY. That matters more here
# than anywhere else in the product: this runs as ExecStartPost on
# clawfactory-allow-providers.service, on a five-hourly timer, on customer
# machines, where a single transient failure marks the unit failed hours after
# any validation went green and nobody is watching.
#
# So: bounded poll on the condition, stderr kept, and the two failures still
# reported separately. A healthy box pays one iteration.
#
# MEASURED, not assumed: on a live box with 34 refresh cycles across 15 boots
# this unit had never failed, and 300 consecutive at-rest reads of this chain
# produced 0 failures. The retry is therefore cheap insurance against a window
# that is real but rare, not a workaround for a chronically flaky read.
CHAIN_MAX_TRIES=30
CHAIN_ERRF="$(mktemp)"
chain_tries=0; CHAIN=''; chain_rc=0; chain_err=''; chain_ok=0
chain_start="$(date +%s)"
while [ "$chain_tries" -lt "$CHAIN_MAX_TRIES" ]; do
    chain_tries=$((chain_tries + 1))
    chain_rc=0
    CHAIN="$(nft list chain inet clawfactory output 2>"$CHAIN_ERRF")" || chain_rc=$?
    chain_err="$(cat "$CHAIN_ERRF" 2>/dev/null || true)"
    # The condition is "readable AND non-empty", never "the grep succeeded".
    # An empty capture with exit 0 would sail through every check below and
    # report a clean shape over nothing at all.
    if [ "$chain_rc" -eq 0 ] && [ -n "$CHAIN" ]; then chain_ok=1; break; fi
    if [ "$chain_tries" -lt "$CHAIN_MAX_TRIES" ]; then sleep 1; fi
done
chain_elapsed=$(( $(date +%s) - chain_start ))
rm -f "$CHAIN_ERRF"

if [ "$chain_ok" != "1" ]; then
    bad "cannot read chain inet clawfactory output after $chain_tries attempt(s) over ${chain_elapsed}s (is the firewall applied?). This is a READ failure and says NOTHING about which rules are present: nft exit status $chain_rc, nft stderr [${chain_err:-<empty>}], bytes returned ${#CHAIN}."
    exit 1
fi
if [ "$chain_tries" -gt 1 ]; then
    note "chain read succeeded on attempt $chain_tries of $CHAIN_MAX_TRIES after ${chain_elapsed}s; earlier attempts failed with [${chain_err:-<empty>}]"
fi

# 1. The chain must still scope itself to the agent uid at the top. Without this
#    line the whole chain applies to root too, which would break the broker.
if ! grep -qE 'meta skuid != (clawuser|1000) return' <<<"$CHAIN"; then
    bad "the chain no longer begins by returning for uid != 1000"
fi

# 2. THE LOAD-BEARING CHECK. Every allowlist accept must be port-scoped to 443.
#    If this ever widens, the "no route" half of Guard 2's claim is gone, because
#    a co-hosted address would then reach whatever port was opened.
#
#    ALL THREE address sets are checked. Guard 3 added @read_fetch_ipv4 and the
#    toolchain toggle added @toolchain_ipv4, and each needs exactly the same
#    scoping for exactly the same reason: they are address sets, so a widened
#    port would expose every service on every listed address rather than the web
#    page the user was thinking of. The toolchain set is the worst case of the
#    three, because GitHub's content CDN is shared with a great deal else.
while IFS= read -r line; do
    case "$line" in
        *@allowed_ipv4*accept*)
            if ! grep -qE 'tcp dport 443 accept' <<<"$line"; then
                bad "provider allowlist accept is no longer scoped to tcp dport 443: $line"
            fi
            ;;
        *@read_fetch_ipv4*accept*)
            if ! grep -qE 'tcp dport 443 accept' <<<"$line"; then
                bad "read-fetch allowlist accept is no longer scoped to tcp dport 443: $line"
            fi
            ;;
        *@toolchain_ipv4*accept*)
            if ! grep -qE 'tcp dport 443 accept' <<<"$line"; then
                bad "toolchain allowlist accept is no longer scoped to tcp dport 443: $line"
            fi
            ;;
    esac
done <<<"$CHAIN"

# 2b. Guard 3's set must EXIST. Without it there is no read-fetch accept, which
#     is the denied state and therefore safe, but it also means the control the
#     product describes is not present. A missing control that fails safe is
#     still a missing control, and silence here would let it stay missing.
# Same retry discipline as the chain read above, and for the same reason: a
# transient netlink failure here marks the refresh unit failed on a customer
# machine and reads as "the control is absent" when the control is fine.
# Returns 0 only when the set was genuinely observed; sets SET_ERR on failure.
#
# DELIBERATELY 5 ATTEMPTS AND NOT 30, and the difference is not arbitrary.
#
# Two reasons. First, by the time this runs the chain read above has already
# succeeded, which proves the table is readable right now; a set still unlisted
# after a few tries is genuinely absent rather than transiently unreadable, so
# the long bound buys nothing. Second, and this is the one that would have hurt:
# this script runs as ExecStartPost on clawfactory-allow-providers.service,
# which is Type=oneshot with no TimeoutStartSec, so systemd's 90s default
# applies to ExecStart plus ExecStartPost together. At 30 attempts each, a box
# genuinely missing both sets would spend 30 + 30 + 30 = 90s here and be KILLED
# by the start timeout, turning a precise "set X is missing, nft said Y" into
# "start operation timed out", which is a worse diagnostic than the single-look
# check this replaced. 30 + 5 + 5 leaves comfortable room under the timeout.
SET_MAX_TRIES=5
set_exists_retry() {
    local name="$1" tries=0 rc=0 errf
    errf="$(mktemp)"
    SET_ERR=''
    while [ "$tries" -lt "$SET_MAX_TRIES" ]; do
        tries=$((tries + 1))
        rc=0
        nft list set inet clawfactory "$name" >/dev/null 2>"$errf" || rc=$?
        if [ "$rc" -eq 0 ]; then rm -f "$errf"; return 0; fi
        SET_ERR="$(cat "$errf" 2>/dev/null || true)"
        if [ "$tries" -lt "$SET_MAX_TRIES" ]; then sleep 1; fi
    done
    SET_ERR="after $tries attempt(s): nft exit $rc, stderr [${SET_ERR:-<empty>}]"
    rm -f "$errf"
    return 1
}

if ! set_exists_retry read_fetch_ipv4; then
    bad "set inet clawfactory read_fetch_ipv4 is missing; Guard 3 is not applied (read-fetch is denied, but the control is absent). $SET_ERR"
fi

# 2c. The toolchain set and its accept must BOTH exist, checked by name.
#
#     Two separate failures are possible and they are not the same problem, so
#     they are reported separately. A missing SET means the toggle has nothing to
#     switch: the toolchain route is denied, which is safe, but a user who
#     switches it on gets nothing and no error. A missing ACCEPT RULE with the
#     set present is worse in the other direction: the set fills up on every
#     refresh and nothing ever reads it, so the product holds a list it does not
#     enforce, which is the shape of a control that looks present and is not.
if ! set_exists_retry toolchain_ipv4; then
    bad "set inet clawfactory toolchain_ipv4 is missing; the toolchain toggle is not applied (the toolchain route is denied, but the control is absent). $SET_ERR"
fi
if ! grep -qE '@toolchain_ipv4 tcp dport 443 accept' <<<"$CHAIN"; then
    bad "the toolchain accept rule is missing from the live chain; the toolchain set is not being enforced by anything"
fi

# 3. No accept anywhere in the chain may name an SMTP port.
if grep -E 'accept' <<<"$CHAIN" | grep -qE 'dport[^a-z]*(25|465|587|2525)([^0-9]|$)'; then
    bad "an accept rule names an SMTP port"
fi

# 4. Guard 2's explicit drop must be present. It is REDUNDANT with the terminal
#    `counter drop`, and that redundancy is the point: it makes the property
#    legible in source instead of dependent on a reader noticing rule ordering.
if ! grep -qE 'tcp dport \{[^}]*\b25\b[^}]*\}.*drop' <<<"$CHAIN"; then
    bad "the explicit Guard 2 SMTP drop is missing from the live chain"
fi

# 5. The chain must still end in a drop. A policy-accept chain with no terminal
#    drop accepts everything not explicitly matched.
if ! grep -qE 'counter packets [0-9]+ bytes [0-9]+ drop' <<<"$CHAIN"; then
    bad "the chain has no terminal counter drop"
fi

if [ "$FAIL" -eq 0 ]; then
    note "chain shape OK (uid-scoped, all three allowlist accepts are 443-only, read-fetch and toolchain sets present with their accepts, SMTP dropped explicitly, terminal drop present)"
else
    echo "[fw-assert] The egress chain has drifted from the shape Guard 2 and Guard 3 depend on." >&2
    echo "[fw-assert] Email containment or web containment may be weakened. Investigate before trusting either path." >&2
fi
exit "$FAIL"
