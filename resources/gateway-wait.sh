#!/bin/bash
# ClawFactory shared gateway-health helpers -- the SINGLE source of the
# cold-start health-wait window, so install steps cannot drift apart and
# re-introduce the "window shorter than the ~67s cold-start" class of
# false-failure (v1.0.41 shipped that bug in three separate places; see L13).
#
# The OpenClaw gateway cold-start on a 2-vCPU VM is ~67s (binds :8787 at ~35s,
# fully ready ~67s after a model-warmup network stall). EVERY install-path
# health window that gates or reports success must budget >= that, with
# headroom. 120s is the standard: it matches the proven
# Step-PreinstallGatewayRuntime /status poll (13 x 10s) and switch-provider.ps1
# (40 x 3s). Do NOT hand-roll a shorter loop anywhere -- source this and call
# wait_for_gateway_healthy.
#
# Sourced by: resources/install-chat-proxy.sh (root) and setup.ps1's
# Step-EnableChatCompletions here-string (clawuser). Staged to
# /usr/local/lib/clawfactory/gateway-wait.sh by Step-StageGatewayHelper.
#
# Idempotent to source: defines functions and (only if unset) the two knobs;
# runs nothing.

# The one knob. Overridable via env for tests only; the install path uses 120.
: "${CLAWFACTORY_GATEWAY_HEALTH_TIMEOUT_S:=120}"
: "${CLAWFACTORY_GATEWAY_HEALTH_INTERVAL_S:=3}"

# wait_for_gateway_healthy <port> [timeout_s] [as_user]
#   Poll http://127.0.0.1:<port>/status until HTTP 200 or timeout. Breaks on the
#   first success, so it is instant when the gateway is already healthy and only
#   spends the full window during a genuine cold start. If <as_user> is given and
#   we are root, each probe runs via `su <as_user>` (mirrors install-chat-proxy's
#   clawuser-context probes). Returns 0 on 200, 1 on timeout.
wait_for_gateway_healthy() {
    local port="$1"
    local timeout_s="${2:-$CLAWFACTORY_GATEWAY_HEALTH_TIMEOUT_S}"
    local as_user="${3:-}"
    local interval="$CLAWFACTORY_GATEWAY_HEALTH_INTERVAL_S"
    # Wall-clock deadline (not accumulated sleep): a cold gateway can make each
    # probe cost up to --max-time before failing, so counting only the sleeps
    # would let the real wait run well past timeout_s. Bound the total instead.
    local start now
    start="$(date +%s)"
    while :; do
        if [ -n "$as_user" ] && [ "$(id -u)" = "0" ]; then
            if su "$as_user" -s /bin/bash -c "curl -fsS --max-time 5 http://127.0.0.1:${port}/status >/dev/null 2>&1"; then
                return 0
            fi
        else
            if curl -fsS --max-time 5 "http://127.0.0.1:${port}/status" >/dev/null 2>&1; then
                return 0
            fi
        fi
        now="$(date +%s)"
        [ "$((now - start))" -ge "$timeout_s" ] && return 1
        sleep "$interval"
    done
}

# assert_user_manager_ready <user>
#   Ensure <user>'s systemd --user manager is actually up so `systemctl --user`
#   works in the no-login install context. Without linger the per-user manager
#   exits with the last session and `systemctl --user` fails "Failed to connect
#   to bus: No such file or directory" (microsoft/WSL#8842, #10846) -- which makes
#   a port-move restart a silent no-op. Enables linger idempotently, then waits
#   for /run/user/<uid> AND a responsive manager (systemctl --user
#   show-environment connects to the user bus). Returns 0 if ready, 1 if not.
#   Must run as root (needs loginctl + su).
assert_user_manager_ready() {
    local user="$1"
    local uid
    uid="$(id -u "$user" 2>/dev/null)" || return 1
    [ -n "$uid" ] || return 1
    loginctl enable-linger "$user" >/dev/null 2>&1 || true
    local i
    for i in $(seq 1 30); do
        if [ -d "/run/user/$uid" ] \
           && su "$user" -s /bin/bash -c "XDG_RUNTIME_DIR=/run/user/$uid systemctl --user show-environment >/dev/null 2>&1"; then
            return 0
        fi
        sleep 2
    done
    return 1
}
