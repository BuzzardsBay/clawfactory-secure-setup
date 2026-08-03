#!/bin/bash
# clawfactory-fw-assert.sh -- Guard 2's firewall assertion.
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

CHAIN="$(nft list chain inet clawfactory output 2>/dev/null)" || {
    bad "cannot read chain inet clawfactory output (is the firewall applied?)"
    exit 1
}

# 1. The chain must still scope itself to the agent uid at the top. Without this
#    line the whole chain applies to root too, which would break the broker.
if ! grep -qE 'meta skuid != (clawuser|1000) return' <<<"$CHAIN"; then
    bad "the chain no longer begins by returning for uid != 1000"
fi

# 2. THE LOAD-BEARING CHECK. Every allowlist accept must be port-scoped to 443.
#    If this ever widens, the "no route" half of Guard 2's claim is gone, because
#    a co-hosted address would then reach whatever port was opened.
while IFS= read -r line; do
    case "$line" in
        *@allowed_ipv4*accept*)
            if ! grep -qE 'tcp dport 443 accept' <<<"$line"; then
                bad "allowlist accept is no longer scoped to tcp dport 443: $line"
            fi
            ;;
    esac
done <<<"$CHAIN"

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
    note "chain shape OK (uid-scoped, allowlist accept is 443-only, SMTP dropped explicitly, terminal drop present)"
else
    echo "[fw-assert] The egress chain has drifted from the shape Guard 2's claim depends on." >&2
    echo "[fw-assert] Email containment may be weakened. Investigate before trusting the send path." >&2
fi
exit "$FAIL"
