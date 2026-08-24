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
        note "WARNING: the toolchain switch is on but resolved 0 addresses. GitHub and npm will be unreachable until the next refresh. Skill installation is not affected: the skill hub shares a network address with ClawFactory's own site, which this switch does not cover."
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

# --- f. the boot-time refresh, which is what makes the panel true after a
#        restart ---------------------------------------------------------------
#
# THE DEFECT THIS CLOSES, measured on cfv-174 after a full Windows reboot:
# TC.1a PASS enabled=true, TC.1b PASS 28 live and 28 persisted, and TC.1c FAIL
# github and npm reachable=False. The panel read "On. 28 network addresses
# reachable" while the route was dead, for up to five hours.
#
# WHY THE EXISTING BOOT TRIGGER DID NOT DO THIS. clawfactory-allow-providers.timer
# already carries OnBootSec=30s and its script ends by calling both resolvers, so
# on paper this was covered. Two things stopped it:
#
#   1. That script begins `nft list table inet clawfactory >/dev/null 2>&1 ||
#      exit 0`. The timer has NO ordering against clawfactory-fw.service, which
#      waits on network-online.target, so at 30 seconds the table may not exist
#      yet -- and `exit 0` then skips the two resolver calls ninety lines below
#      while the unit reports success. Fixed in setup.ps1 in the same release.
#   2. Thirty seconds after a WSL distro boot is early for DNS. Before v1.4.1 a
#      resolver run with no DNS wrote an EMPTY set, so the trigger firing at the
#      wrong moment was worse than it not firing: it destroyed the set
#      fw-apply.sh had just correctly replayed.
#
# WHAT THIS ADDS. A unit ORDERED after the firewall, that runs the existing
# resolvers and RETRIES until they stop reporting resolution failures. It waits
# on that state rather than on a fixed sleep, and it needs no probe hostname of
# its own: the thing it is waiting for is the resolution it was going to do
# anyway. With an empty allowlist and the toggle off there is nothing to resolve,
# nothing fails, and it exits on the first attempt having waited for nothing.
#
# WHAT IT DELIBERATELY DOES NOT DO. It does not touch fw-apply.sh. The boot
# replay stays exactly as it is, so the deny is in force from the first moment of
# boot and is never wider during the window; this only replaces a narrow stale
# set with a narrow fresh one, afterwards. And it does not re-resolve anything
# the resolvers themselves would not: clawfactory-toolchain.sh reads the toggle
# from the root-owned policy BEFORE it resolves, so a user who switched the
# software sources off does not get them switched back on at every reboot.
#
# IF THIS REGISTRATION IS ABSENT -- an older install, or systemd unavailable --
# the product falls back to exactly its previous behaviour: fw-apply.sh still
# replays at boot so the deny holds and the set is never wider, and the
# five-hourly timer eventually corrects it. Fail-safe, not fail-open. That is
# why the enable below is checked by READ-BACK and is fatal: silently not
# installing a control the panel's honesty now depends on is the failure mode
# this whole file is written against.
cat > /usr/local/sbin/clawfactory-egress-refresh.sh <<'BOOT'
#!/usr/bin/env bash
# clawfactory-egress-refresh.sh -- re-derive both Guard 3 firewall sets once the
# network is actually up. Run by clawfactory-egress-refresh.service at boot.
#
# Both resolvers are safe to run repeatedly: each flushes its own set and
# rebuilds it from the root-owned policy, and each carries forward the addresses
# it last resolved for a host that will not resolve now, so an attempt made too
# early costs nothing and destroys nothing.
set -uo pipefail

MAX_ATTEMPTS=20
INTERVAL=6          # ceiling: 20 * 6 = 120s, and a healthy boot pays one attempt

say() { echo "[egress-refresh] $*"; }

# The number of hosts a resolver could not resolve AT ALL, from its own
# machine-readable status line. An ABSENT status line means a resolver from a
# build older than v1.4.1: there is no signal, so this treats it as "nothing
# failed" and says so, rather than retrying blind for two minutes at every boot.
failed_from() {   # $1 = resolver output, $2 = status key
    local n
    n="$(printf '%s\n' "$1" | sed -n "s/.*$2 .*failed=\([0-9][0-9]*\).*/\1/p" | tail -1)"
    if [ -z "$n" ]; then
        say "WARNING: no $2 line in the resolver output, so this run has no signal to wait on. Treating it as zero failures. The set is still whatever the resolver just built."
        echo 0
    else
        echo "$n"
    fi
}

attempt=0
while [ "$attempt" -lt "$MAX_ATTEMPTS" ]; do
    attempt=$((attempt + 1))

    rf_out=""; tc_out=""
    if [ -x /usr/local/sbin/clawfactory-read-fetch.sh ]; then
        rf_out="$(/usr/local/sbin/clawfactory-read-fetch.sh 2>&1 || true)"
    else
        say "clawfactory-read-fetch.sh is missing; the user's allowlist was NOT refreshed"
    fi
    if [ -x /usr/local/sbin/clawfactory-toolchain.sh ]; then
        tc_out="$(/usr/local/sbin/clawfactory-toolchain.sh 2>&1 || true)"
    else
        say "clawfactory-toolchain.sh is missing; the software-source route was NOT refreshed"
    fi

    rf_failed="$(failed_from "$rf_out" READFETCH_STATUS)"
    tc_failed="$(failed_from "$tc_out" TOOLCHAIN_STATUS)"
    total=$((rf_failed + tc_failed))

    say "attempt $attempt/$MAX_ATTEMPTS: unresolved hosts read-fetch=$rf_failed toolchain=$tc_failed"
    if [ "$total" -eq 0 ]; then
        say "every host that had to be resolved was resolved; both sets are current"
        printf '%s\n' "$rf_out" "$tc_out"
        exit 0
    fi
    [ "$attempt" -lt "$MAX_ATTEMPTS" ] && sleep "$INTERVAL"
done

# Out of attempts. This is NOT a firewall failure: every set is whatever the last
# run built, which is the previously-resolved addresses for any host that would
# not resolve, or nothing at all for one with no recent record. Narrow either
# way. The five-hourly refresh keeps trying after this.
say "gave up after $MAX_ATTEMPTS attempts with $total host(s) still unresolved. This denies rather than exposes: nothing was widened. A host that never resolves will do this at every boot, which is worth chasing."
printf '%s\n' "$rf_out" "$tc_out"
exit 0
BOOT
chown root:root /usr/local/sbin/clawfactory-egress-refresh.sh
chmod 755 /usr/local/sbin/clawfactory-egress-refresh.sh

cat > /etc/systemd/system/clawfactory-egress-refresh.service <<'UNIT'
[Unit]
Description=ClawFactory: re-resolve the Guard 3 egress sets once the network is up
# ORDERING IS THE POINT. clawfactory-fw.service replays the persisted addresses
# and must go first, so the deny is in force before anything here runs and the
# set is never wider during the window. network-online is Wants rather than
# Requires: if it never arrives, this still runs, finds nothing resolvable,
# keeps what was replayed and says so.
After=clawfactory-fw.service network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/sbin/clawfactory-egress-refresh.sh

[Install]
WantedBy=multi-user.target
UNIT
chown root:root /etc/systemd/system/clawfactory-egress-refresh.service
chmod 644 /etc/systemd/system/clawfactory-egress-refresh.service

systemctl daemon-reload 2>/dev/null || true
systemctl enable clawfactory-egress-refresh.service >/dev/null 2>&1 || true
# READ BACK. `systemctl enable` is routinely written here with `|| true`, which
# means a unit that failed to install looks identical to one that did. The panel
# now tells the user their sites are reachable after a restart, so the thing
# that makes that true has to be verified rather than attempted.
EGRESS_ENABLED="$(systemctl is-enabled clawfactory-egress-refresh.service 2>&1 || true)"
if [ "$EGRESS_ENABLED" != "enabled" ]; then
    fatal "clawfactory-egress-refresh.service did not enable (systemctl is-enabled said '${EGRESS_ENABLED:-<empty>}'). Without it, the Web access panel would report a live address count after a reboot while the addresses it names are stale. The firewall itself is unaffected and still denies, so this is an honesty failure rather than an exposure, but it is not shippable."
fi
note "boot refresh installed and enabled: clawfactory-egress-refresh.service, ordered after clawfactory-fw.service"

note "Guard 3 installed. Read-fetch destinations: $(wc -l < /etc/clawfactory/read-fetch-ips.txt | tr -d ' ') address(es) from the policy allowlist."
note "A fresh install has an empty allowlist, which means the agent can fetch nothing beyond the provider route and the software sources."
# THE SENTENCE BELOW IS A CUSTOMER-VISIBLE CLAIM, because this note lands in the
# install log the user can read. It used to say "Switching it off in Studio stops
# skill installation, GitHub and npm", which is false and was measured false on
# cfv-169: a real `openclaw skills install` completed with the switch off,
# because clawhub.ai shares an address with the permanently-allowed openclaw.ai.
# It must agree with the Studio panel paragraph and with the OFF message at the
# end of clawfactory-toolchain.sh. If one of the three changes, change all three.
note "Toolchain switch: $(node -e 'const p=require("/etc/clawfactory/egress-policy.json");process.stdout.write(String(!p.toolchain||p.toolchain.enabled!==false))' 2>/dev/null || echo unknown) with $(wc -l < /etc/clawfactory/toolchain-ips.txt 2>/dev/null | tr -d ' ') address(es). Switching it off in Studio stops your agent fetching code from GitHub and npm. It does not stop skill installation: the skill hub shares a network address with ClawFactory's own site, which this switch does not cover. It never affects the AI provider."
