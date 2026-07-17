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

# _gw_run_clawuser <cmd> -- run <cmd> as clawuser with XDG_RUNTIME_DIR and a login
#   PATH (so ~/.local/bin/openclaw resolves), whether the caller is root or already
#   clawuser. Internal helper for restart_gateway_reliably.
_gw_run_clawuser() {
    local uid
    uid="$(id -u clawuser 2>/dev/null || echo 1000)"
    if [ "$(id -u)" = "0" ]; then
        su clawuser -s /bin/bash -lc "XDG_RUNTIME_DIR=/run/user/$uid $1"
    else
        bash -lc "XDG_RUNTIME_DIR=/run/user/$uid $1"
    fi
}

# restart_gateway_reliably <port> -- (re)start the openclaw gateway and confirm it
#   answers on <port>, using the mechanism the gateway INSTALL proves works rather
#   than a bare `systemctl --user restart` (which demonstrably fails to rebind in
#   the no-login WSL install context -- cfv-0716s: EnableChatCompletions timed out
#   at 120s after its restart). Steps: (root) assert the user manager is up ->
#   daemon-reload -> `openclaw gateway restart` (openclaw's OWN sanctioned,
#   token-preserving restart) -> wait 60s -> if still not healthy, fall back to
#   `openclaw gateway install --force` (the proven install-start; the OpenClaw
#   runbook's supported re-resolve after a port change; --force is idempotent and
#   an ExecStart drop-in still wins on daemon-reload, so the gateway comes up on
#   the drop-in port) -> wait 120s.
#
#   The HEALTH PROBE runs as the CALLER's uid, not clawuser: the nft firewall drops
#   clawuser->127.0.0.1:8788 (the private port is reachable only by root/the proxy),
#   so a clawuser probe of 8788 can never succeed even when the gateway is healthy.
#   Callers on 8788 MUST run as root; callers on 8787 may be clawuser (that path is
#   allowed). Returns 0 if healthy within the window, 1 otherwise.
restart_gateway_reliably() {
    local port="$1"
    local timeout_s="${2:-$CLAWFACTORY_GATEWAY_HEALTH_TIMEOUT_S}"
    if [ "$(id -u)" = "0" ]; then
        assert_user_manager_ready clawuser || return 1
    fi
    # Attempt 1 -- openclaw's OWN restart (token-preserving; the runbook's
    # sanctioned restart). Give it the full cold-start window so a working restart
    # is not abandoned early (the ~67s cold start would overrun a shorter wait).
    _gw_run_clawuser "systemctl --user daemon-reload" >/dev/null 2>&1 || true
    _gw_run_clawuser "openclaw gateway restart" >/dev/null 2>&1 || true
    if wait_for_gateway_healthy "$port" "$timeout_s"; then return 0; fi
    # Attempt 2 (fallback) -- the install's proven start. Heavier (may re-resolve
    # the service / regenerate the token), so it is the last resort; ordering keeps
    # it safe (the proxy and clients read the token after the gateway is up).
    _gw_run_clawuser "openclaw gateway install --force --port 8787" >/dev/null 2>&1 || true
    _gw_run_clawuser "systemctl --user daemon-reload" >/dev/null 2>&1 || true
    wait_for_gateway_healthy "$port" "$timeout_s"
}
