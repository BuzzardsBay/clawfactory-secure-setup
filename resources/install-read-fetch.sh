#!/usr/bin/env bash
# install-read-fetch.sh -- v1 Guard 3. Web off by default, allowlist only.
#
# Runs as root inside WSL, after install-send.sh, because the control tool loads
# the shared egress-policy helpers from send-lib.js and writes the same
# root-owned policy file.
#
# Installs:
#   /usr/local/sbin/clawfactory-read-fetch.sh   0755  the resolver, root-owned
#   /usr/local/sbin/clawfactory-toolchain.sh    0755  the toolchain resolver
#   /usr/local/sbin/clawfactory-fetchctl.js     0750  the only write path
#   /usr/local/sbin/clawfactory-fetchctl        0750  node wrapper for Studio
#
# The toolchain access toggle installs here rather than in its own step because
# it is the same guard: same policy file, same control tool, same nft table, same
# tripwire. A separate installer would only add a second thing to forget.
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

# --- a. the resolvers and the control tool ----------------------------------
for f in /usr/local/sbin/clawfactory-read-fetch.sh /usr/local/sbin/clawfactory-toolchain.sh /usr/local/sbin/clawfactory-fetchctl.js; do
    [ -f "$f" ] || fatal "missing $f (the installer did not drop it)"
    chown root:root "$f"
done
chmod 755 /usr/local/sbin/clawfactory-read-fetch.sh
chmod 755 /usr/local/sbin/clawfactory-toolchain.sh
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
let dirty = false;
if (!raw.read_fetch || !Array.isArray(raw.read_fetch.allow)) {
  raw.read_fetch = { allow: [] };
  dirty = true;
  process.stdout.write("read_fetch section repaired to an empty allowlist\n");
} else {
  process.stdout.write("read_fetch section present with " + raw.read_fetch.allow.length + " destination(s)\n");
}
// The toolchain switch. An UPGRADE over a policy file that predates this feature
// has no toolchain key, and the documented reading of an absent key is ON, so
// seeding it true here changes nothing about behaviour and only makes the state
// explicit on disk. A REINSTALL over a file where the user switched it OFF must
// leave that alone: re-enabling it would silently re-open a route the user
// closed, which is the one thing this feature must never do.
if (!raw.toolchain || typeof raw.toolchain !== "object" || typeof raw.toolchain.enabled !== "boolean") {
  raw.toolchain = { enabled: true };
  dirty = true;
  process.stdout.write("toolchain section seeded to the default (enabled)\n");
} else {
  process.stdout.write("toolchain section present and PRESERVED: enabled=" + raw.toolchain.enabled + "\n");
}
if (dirty) {
  fs.writeFileSync(p + ".tmp", JSON.stringify(raw, null, 2) + "\n", { mode: 0o644 });
  fs.renameSync(p + ".tmp", p);
}
' || fatal "the egress policy file is not readable as JSON; refusing to continue"

chown root:root /etc/clawfactory/egress-policy.json
chmod 644 /etc/clawfactory/egress-policy.json

# --- c. apply once, so the set is populated from the policy rather than left
#        to the first timer tick ------------------------------------------
# --- c0. the two copies of the toolchain host list must AGREE -----------------
# setup.ps1 seeds @toolchain_ipv4 at firewall time from its own copy of this list,
# because the route has to exist before step 8c runs as clawuser. This resolver
# owns the list for every refresh afterwards. Two copies is a real risk: a host in
# setup.ps1's copy but not this one would be seeded and then silently dropped at
# the first refresh, and a host here but not there would be unreachable during the
# install. Duplication is only acceptable when something compares the copies, so
# this compares them and fails the install loudly on drift.
SEEDED=/etc/clawfactory/toolchain-hosts.seed
if [ -f "$SEEDED" ]; then
    # Ask the resolver for its list rather than scraping its source. See the
    # --list-hosts note in that file for what scraping cost.
    #
    # The resolver is run SEPARATELY from the pipeline that reshapes its output,
    # and its stderr is kept. The old form was one pipeline under `pipefail` with
    # `--list-hosts 2>/dev/null`, which is the same defect shape as the chain
    # asserts below: if the resolver failed to run at all, MINE came back empty,
    # the comparison failed, and the install aborted claiming host-list DRIFT.
    # That is a misdiagnosis pointing at the wrong file, and the message it
    # printed named two lists when the real fault was that one was never read.
    TC_LIST_ERRF="$(mktemp)"
    tc_list_rc=0
    TC_LIST_RAW="$(/usr/local/sbin/clawfactory-toolchain.sh --list-hosts 2>"$TC_LIST_ERRF")" || tc_list_rc=$?
    TC_LIST_ERR="$(cat "$TC_LIST_ERRF" 2>/dev/null || true)"
    rm -f "$TC_LIST_ERRF"
    if [ "$tc_list_rc" -ne 0 ]; then
        fatal "could not ASK clawfactory-toolchain.sh for its host list: exit status $tc_list_rc, stderr [${TC_LIST_ERR:-<empty>}]. This is a RESOLVER failure and NOT a drift finding, so the two host lists were never compared."
    fi
    MINE="$(printf '%s' "$TC_LIST_RAW" | tr ' ' '\n' | sed '/^$/d' | sort -u | tr '\n' ' ')"
    THEIRS="$(tr ' ' '\n' < "$SEEDED" | sed '/^$/d' | sort -u | tr '\n' ' ')"
    if [ -z "$MINE" ]; then
        fatal "clawfactory-toolchain.sh --list-hosts exited 0 but returned NO hosts (stderr [${TC_LIST_ERR:-<empty>}]). An empty list would compare unequal to the seed and read as DRIFT, which would blame the wrong thing, so this is reported as the empty read it is."
    fi
    if [ "$MINE" != "$THEIRS" ]; then
        fatal "toolchain host list DRIFT. setup.ps1 seeded [$THEIRS] but clawfactory-toolchain.sh owns [$MINE]. Both lists were read successfully, so this is a real disagreement. A host in one and not the other is either unreachable during install or silently dropped at the first refresh. Fix both and rebuild."
    fi
    note "toolchain host lists agree between setup.ps1 and the resolver ($(printf '%s' "$MINE" | wc -w | tr -d ' ') hosts)"
else
    note "WARNING: no toolchain host seed file to reconcile against; the two copies were NOT compared"
fi

/usr/local/sbin/clawfactory-read-fetch.sh || fatal "the read-fetch resolver failed on its first run"
/usr/local/sbin/clawfactory-toolchain.sh || fatal "the toolchain resolver failed on its first run"

# --- d. prove the control is actually in the live chain --------------------
# A fresh install has an EMPTY read-fetch list, so "no read-fetch destination is
# reachable" is true whether or not Guard 3 installed correctly. Checking the
# empty outcome would therefore pass on a machine where nothing was installed.
# Check the mechanism instead: the set and its 443-scoped accept.
BACKEND="$(cat /etc/clawfactory/fw-backend 2>/dev/null || echo nftables)"
if [ "$BACKEND" = "nftables" ]; then
    # ONE read of the chain, retried, from which every assertion here is made.
    #
    # This replaces four single-look checks. Two of them took SEPARATE listings
    # twelve lines apart to check two rules that CANNOT differ: both accepts are
    # static lines in the same /etc/nftables.conf, which opens with
    # `flush ruleset`, so no code path can affect one without affecting all. On
    # cfv-165 the first listing passed and the second failed twelve lines later,
    # which is only possible if the READ differed rather than the rules.
    #
    # The old form was `nft list chain ... 2>/dev/null | grep -qE ... || fatal`.
    # Under `set -o pipefail` that fatal fires when EITHER the listing failed or
    # the rule was absent, and the message asserted the second. It could not tell
    # the two apart, and 2>/dev/null discarded the one thing that would have
    # said which. So the message the installer printed was a claim the code was
    # not in a position to make.
    #
    # Two rules, both load-bearing:
    #   - poll the CONDITION, never "the grep succeeded". A retry loop around a
    #     check that can pass for the wrong reason is worse than no retry.
    #   - an unreadable chain and an absent rule are DIFFERENT failures with
    #     different owners, and are reported as such.
    # Bounded poll at 30 x 1s, matching install-send.sh and install-quarantine.sh.
    # A healthy box pays exactly one iteration because the loop exits on success.
    CHAIN_MAX_TRIES=30
    CHAIN_ERRF="$(mktemp)"
    chain_tries=0; chain_txt=''; chain_rc=0; chain_err=''; chain_readable=0
    have_rf_set=0; have_tc_set=0; have_rf_accept=0; have_tc_accept=0
    chain_start="$(date +%s)"

    while [ "$chain_tries" -lt "$CHAIN_MAX_TRIES" ]; do
        chain_tries=$((chain_tries + 1))
        chain_rc=0
        chain_txt="$(nft list chain inet clawfactory output 2>"$CHAIN_ERRF")" || chain_rc=$?
        chain_err="$(cat "$CHAIN_ERRF" 2>/dev/null || true)"
        if [ "$chain_rc" -eq 0 ]; then chain_readable=1; else chain_readable=0; fi

        if [ "$chain_readable" = "1" ]; then
            if printf '%s\n' "$chain_txt" | grep -qE '@read_fetch_ipv4 tcp dport 443 accept'; then have_rf_accept=1; else have_rf_accept=0; fi
            if printf '%s\n' "$chain_txt" | grep -qE '@toolchain_ipv4 tcp dport 443 accept';  then have_tc_accept=1; else have_tc_accept=0; fi
            if nft list set inet clawfactory read_fetch_ipv4 >/dev/null 2>&1; then have_rf_set=1; else have_rf_set=0; fi
            if nft list set inet clawfactory toolchain_ipv4  >/dev/null 2>&1; then have_tc_set=1; else have_tc_set=0; fi
            if [ "$have_rf_set$have_rf_accept$have_tc_set$have_tc_accept" = "1111" ]; then break; fi
        fi
        if [ "$chain_tries" -lt "$CHAIN_MAX_TRIES" ]; then sleep 1; fi
    done
    chain_elapsed=$(( $(date +%s) - chain_start ))
    rm -f "$CHAIN_ERRF"

    # Failure 1: the chain could not be READ. Says so, and does not pretend to
    # know anything about which rules are present.
    if [ "$chain_readable" != "1" ]; then
        fatal "could not READ chain inet clawfactory output after $chain_tries attempt(s) over ${chain_elapsed}s. This is a READ failure and NOT a statement about any rule: nft exit status $chain_rc, nft stderr [${chain_err:-<empty>}]. The firewall may not be applied, or the netlink socket was busy for the whole window."
    fi

    # Failure 2: the chain WAS readable and something is genuinely absent. Prints
    # the full chain text so the next reader does not have to reproduce it.
    if [ "$have_rf_set$have_rf_accept$have_tc_set$have_tc_accept" != "1111" ]; then
        echo "[install-read-fetch] --- full chain text from the final attempt ---" >&2
        printf '%s\n' "$chain_txt" >&2
        echo "[install-read-fetch] --- end chain text ---" >&2
        fatal "the chain WAS readable (nft exit 0) after $chain_tries attempt(s) over ${chain_elapsed}s, so these rules are genuinely ABSENT rather than unread: read_fetch set=$have_rf_set accept443=$have_rf_accept, toolchain set=$have_tc_set accept443=$have_tc_accept. A missing set means the control is not applied; a missing or non-443 accept means the set is a list nothing enforces."
    fi

    note "live chain carries @read_fetch_ipv4 and @toolchain_ipv4, both with 443-scoped accepts, and both sets exist (read in $chain_tries attempt(s) over ${chain_elapsed}s)"
    TC_N="$(wc -l < /etc/clawfactory/toolchain-ips.txt 2>/dev/null | tr -d ' ')"
    [ -n "$TC_N" ] || TC_N=0
    if [ "$TC_N" -eq 0 ]; then
        # Not fatal. A build box with no DNS at this point in the install would
        # resolve nothing, and refusing to install over that would be worse than
        # saying so: the next five-hourly refresh repairs it, and the failure
        # direction is denial rather than exposure.
        note "WARNING: the toolchain switch is on but resolved 0 addresses. Skill installation, GitHub and npm will be unreachable until the next refresh."
    fi
    note "toolchain set holds $TC_N address(es)"
else
    note "backend=$BACKEND: the read-fetch list is applied as individual ACCEPT rules by fw-apply.sh"
fi

# --- e. the tripwire must now cover Guard 3 too -----------------------------
if [ -x /usr/local/sbin/clawfactory-fw-assert.sh ]; then
    /usr/local/sbin/clawfactory-fw-assert.sh \
        || fatal "the chain-shape tripwire failed after installing Guard 3"
fi

note "Guard 3 installed. Read-fetch destinations: $(wc -l < /etc/clawfactory/read-fetch-ips.txt | tr -d ' ') address(es) from the policy allowlist."
note "A fresh install has an empty allowlist, which means the agent can fetch nothing beyond the provider route and the software sources."
note "Toolchain switch: $(node -e 'const p=require("/etc/clawfactory/egress-policy.json");process.stdout.write(String(!p.toolchain||p.toolchain.enabled!==false))' 2>/dev/null || echo unknown) with $(wc -l < /etc/clawfactory/toolchain-ips.txt 2>/dev/null | tr -d ' ') address(es). Switching it off in Studio stops skill installation, GitHub and npm, and never affects the AI provider."
