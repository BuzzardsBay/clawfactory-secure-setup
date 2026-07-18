#!/bin/bash
# ClawFactory universal turn gate (Defect 3 -- gate coverage).
#
# Invoked by the openclaw shim BEFORE every `openclaw agent` launch, so no
# caller can start an ungated turn. Enforces, in WSL, on every turn:
#   1. SOUL integrity -- factory (~/.openclaw/SOUL.md) AND the injected
#      workspace SOUL (~/.openclaw/workspace/SOUL.md, once pinned) against
#      root-owned pins the agent's UID cannot write.
#   2. Spend cap -- caps from the root-owned mirror /etc/clawfactory/governor.json
#      (synced from the canonical Windows governor), spend from the meter.
#
# Exit 0 = allowed. Non-zero = blocked: a machine-readable envelope goes to
# STDOUT (Studio parses it into a human message) and a human line to STDERR.
# Fail-SAFE: any inability to verify (missing file/pin/meter/config) => block.
set -uo pipefail
REAL_OPENCLAW="$(cat /etc/clawfactory/openclaw-real 2>/dev/null || echo /usr/lib/node_modules/openclaw/openclaw.mjs)"
SPEND_CHECK="/usr/local/sbin/clawfactory-spend-check.js"

emit_block() {  # $1=state  $2=human message
    local esc
    esc=$(printf '%s' "$2" | sed 's/\\/\\\\/g; s/"/\\"/g')
    printf '{"clawfactory_gate":"blocked","state":"%s","message":"%s"}\n' "$1" "$esc"
    printf 'ClawFactory: %s\n' "$2" >&2
}

verify_pinned() {  # $1=file  $2=pin  $3=label ; returns 1 + emits on mismatch
    local f="$1" pin="$2" label="$3" have expect
    [ -r "$f" ]   || { emit_block soul_missing "the $label ($f) is missing or unreadable"; return 1; }
    have=$(sha256sum "$f" 2>/dev/null | awk '{print $1}')
    expect=$(tr -d '[:space:]' < "$pin" 2>/dev/null)
    [ -n "$have" ] && [ -n "$expect" ] || { emit_block soul_unverifiable "could not compute or read the pin for the $label"; return 1; }
    [ "$have" = "$expect" ] || { emit_block soul_mismatch "the $label no longer match the value pinned at install time -- they may have been tampered with. No turn will run until they are restored."; return 1; }
    return 0
}

soul_ok() {
    # Factory SOUL -- always enforced.
    [ -r /etc/clawfactory/soul.sha256 ] || { emit_block soul_pin_missing "the factory safety pin is missing -- cannot verify the rules. Re-run ClawFactory setup."; return 1; }
    verify_pinned /home/clawuser/.openclaw/SOUL.md /etc/clawfactory/soul.sha256 "factory safety rules" || return 1
    # Injected workspace SOUL -- enforced only once its pin exists (Defect 4).
    if [ -r /etc/clawfactory/workspace-soul.sha256 ]; then
        verify_pinned /home/clawuser/.openclaw/workspace/SOUL.md /etc/clawfactory/workspace-soul.sha256 "safety rules injected into the agent" || return 1
    fi
    return 0
}

spend_ok() {
    local gov dc mc usage out today month _i
    gov=/etc/clawfactory/governor.json
    [ -r "$gov" ] || { emit_block spend_config_missing "the spend governor is not configured on this machine ($gov). Re-run ClawFactory setup."; return 1; }
    dc=$(grep -oE '"daily_cap_usd"[^,}]*'   "$gov" | grep -oE '[0-9]+(\.[0-9]+)?' | head -1)
    mc=$(grep -oE '"monthly_cap_usd"[^,}]*' "$gov" | grep -oE '[0-9]+(\.[0-9]+)?' | head -1)
    [ -n "$dc" ] && [ -n "$mc" ] || { emit_block spend_config_bad "the spend governor config is unreadable ($gov)"; return 1; }
    # v1.0.45 (L18): the usage-cost WS can be transiently cold -- the first turn
    # after a gateway (re)start or after idle finds it not-yet-ready and it returns
    # empty, which fail-safe-blocked a fresh install's first turns (cfv-0717d/e).
    # Retry a few times to let it warm BEFORE declaring the meter unknown. The
    # fail-safe is preserved: if it never warms, we still block. A warm meter
    # returns on the FIRST call, so this adds no latency in the normal case.
    usage=""
    for _i in 1 2 3 4 5 6 7 8 9 10; do
        usage=$("$REAL_OPENCLAW" gateway usage-cost --json --days 400 2>/dev/null)
        [ -n "$usage" ] && break
        sleep 1
    done
    [ -n "$usage" ] || { emit_block spend_meter_unknown "the spend meter is unavailable, so we cannot confirm you are under budget. Turns are blocked until it is readable (fail-safe)."; return 1; }
    out=$(printf '%s' "$usage" | node "$SPEND_CHECK" 2>/dev/null) || { emit_block spend_meter_unknown "the spend meter returned unusable data; blocking (fail-safe)."; return 1; }
    today=${out%% *}; month=${out##* }
    [ -n "$today" ] && [ -n "$month" ] || { emit_block spend_meter_unknown "the spend meter returned unusable data; blocking (fail-safe)."; return 1; }
    if awk -v t="$today" -v d="$dc" -v m="$month" -v mm="$mc" 'BEGIN{ exit !(t+0 >= d+0 || m+0 >= mm+0) }'; then
        emit_block spend_blocked "spend cap reached (today \$$today / cap \$$dc; this month \$$month / cap \$$mc). New turns are blocked until spend falls below the cap or you raise it."
        return 1
    fi
    return 0
}

soul_ok  || exit 3
spend_ok || exit 4
exit 0
