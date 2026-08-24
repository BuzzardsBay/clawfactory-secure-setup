#!/usr/bin/env bash
# calibrate-retention.sh -- run the SHIPPED retention reader against rigged
# inputs whose answers are already known, and assert each one.
#
# WHY. v1.4.1 gives clawfactory-read-fetch.sh and clawfactory-toolchain.sh the
# ability to carry a previously-resolved address forward when a host will not
# resolve. That is the only code in either file that can make the firewall set
# WIDER than what this run resolved, so it is the only code in either file that
# has to be measured rather than reasoned about. In particular the "different
# host" case IS the revocation guarantee: if a map entry for a host that is no
# longer on the list could be returned, a site the user removed would come back.
#
# The function under test is EXTRACTED from the shipped file rather than
# retyped, so this cannot pass against a copy that has drifted from what ships.
#
# Usage: bash scripts/calibrate-retention.sh
# Exit 0 only if every case matches its expected answer.

set -uo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

PASS=0
FAIL=0

extract() {   # $1 = source file -> prints the retain_for() definition
    sed -n '/^retain_for() {/,/^}/p' "$1"
}

check() {     # $1 = name, $2 = expected (space-separated ips), $3 = actual
    if [ "$2" = "$3" ]; then
        printf 'PASS  %-46s expected=[%s] got=[%s]\n' "$1" "$2" "$3"
        PASS=$((PASS + 1))
    else
        printf 'FAIL  %-46s expected=[%s] got=[%s]\n' "$1" "$2" "$3"
        FAIL=$((FAIL + 1))
    fi
}

run_case() {  # $1 = name, $2 = host, $3 = expected ips, $4 = map body (may be the literal ABSENT)
    MAP_FILE="$WORK/map"
    rm -f "$MAP_FILE"
    if [ "$4" != "ABSENT" ]; then printf '%s' "$4" > "$MAP_FILE"; fi
    got="$(retain_for "$2" | awk -F'\t' '{print $1}' | tr '\n' ' ' | sed 's/ *$//')"
    check "$1" "$3" "$got"
}

for SRC in resources/clawfactory-read-fetch.sh resources/clawfactory-toolchain.sh; do
    echo "=== $SRC ==="
    DEF="$(extract "$HERE/$SRC")"
    if [ -z "$DEF" ]; then
        echo "FAIL  could not extract retain_for() from $SRC -- the calibration did not run"
        FAIL=$((FAIL + 1))
        continue
    fi
    # shellcheck disable=SC2086
    eval "$DEF"
    NOW=1000000
    RETAIN_MAX_AGE=86400
    T="$(printf '\t')"

    run_case 'absent map'                    example.com ''        ABSENT
    run_case 'empty map'                     example.com ''        ''
    run_case 'well-formed, fresh'            example.com 9.9.9.9   "example.com${T}9.9.9.9${T}999999
"
    run_case 'DIFFERENT host (revocation)'   example.com ''        "other.com${T}9.9.9.9${T}999999
"
    run_case 'expired beyond RETAIN_MAX_AGE' example.com ''        "example.com${T}9.9.9.9${T}900000
"
    run_case 'epoch in the FUTURE'           example.com ''        "example.com${T}9.9.9.9${T}1000500
"
    run_case 'malformed: two fields'         example.com ''        "example.com${T}9.9.9.9
"
    run_case 'malformed: four fields'        example.com ''        "example.com${T}9.9.9.9${T}999999${T}junk
"
    run_case 'wrong type: epoch not numeric' example.com ''        "example.com${T}9.9.9.9${T}yesterday
"
    run_case 'hostile: nft injection in ip'  example.com ''        "example.com${T}9.9.9.9 }; nft flush ruleset; #${T}999999
"
    run_case 'hostile: not an address'       example.com ''        "example.com${T}\$(id)${T}999999
"
    run_case 'mixed valid + malformed'       example.com 9.9.9.9   "example.com${T}bogus${T}999999
example.com${T}9.9.9.9${T}999999
"
    run_case 'two valid entries, both kept'  example.com '1.2.3.4 9.9.9.9' "example.com${T}1.2.3.4${T}999999
example.com${T}9.9.9.9${T}999990
"
    # THE CONTROL THAT MUST FAIL IF THE READER IS A NO-OP. If retain_for simply
    # returned nothing for everything, every case above that expects '' would
    # still pass. This one cannot: it expects a value, from the same reader, on
    # the same rigged file shape.
    run_case 'CONTROL: reader is not a no-op' example.com 7.7.7.7  "example.com${T}7.7.7.7${T}1000000
"
    unset -f retain_for
done

echo
echo "=== the boot refresh's wait condition ==="
# failed_from() is what decides whether clawfactory-egress-refresh.sh waits and
# tries again. If it reads zero from a run that actually failed, the boot refresh
# exits immediately and this whole release does nothing. Extracted from the
# HEREDOC INSIDE install-read-fetch.sh, so it is the text that will be written to
# the box rather than a copy of it.
BOOTSRC="$WORK/boot.sh"
sed -n "/^cat > \/usr\/local\/sbin\/clawfactory-egress-refresh.sh <<'BOOT'$/,/^BOOT$/p" \
    "$HERE/resources/install-read-fetch.sh" | sed '1d;$d' > "$BOOTSRC"
if [ ! -s "$BOOTSRC" ]; then
    echo "FAIL  could not extract the boot script from install-read-fetch.sh -- the calibration did not run"
    FAIL=$((FAIL + 1))
else
    DEF="$(sed -n '/^failed_from() {/,/^}/p' "$BOOTSRC")"
    if [ -z "$DEF" ]; then
        echo "FAIL  could not extract failed_from() from the generated boot script"
        FAIL=$((FAIL + 1))
    else
        eval "$DEF"
        say() { :; }   # silence the warning path; the RETURN VALUE is what is asserted
        pcase() {  # $1 = name, $2 = expected, $3 = key, $4 = resolver output
            got="$(failed_from "$4" "$3" 2>/dev/null | tail -1)"
            check "$1" "$2" "$got"
        }
        pcase 'status line, failed=0'         0 TOOLCHAIN_STATUS '[toolchain] TOOLCHAIN_STATUS enabled=1 hosts=8 resolved=8 failed=0 retained=0 addresses=28 backend=nftables'
        pcase 'status line, failed=3'         3 TOOLCHAIN_STATUS '[toolchain] TOOLCHAIN_STATUS enabled=1 hosts=8 resolved=5 failed=3 retained=9 addresses=19 backend=nftables'
        pcase 'no status line at all'         0 TOOLCHAIN_STATUS '[toolchain] policy says TOOLCHAIN=on'
        pcase 'empty output'                  0 TOOLCHAIN_STATUS ''
        pcase 'wrong key present, ours absent' 0 TOOLCHAIN_STATUS '[read-fetch] READFETCH_STATUS hosts=1 resolved=0 failed=1 retained=0 addresses=0 backend=nftables'
        pcase 'read-fetch key, failed=1'      1 READFETCH_STATUS '[read-fetch] READFETCH_STATUS hosts=1 resolved=0 failed=1 retained=4 addresses=4 backend=nftables'
        pcase 'failed= is not numeric'        0 TOOLCHAIN_STATUS '[toolchain] TOOLCHAIN_STATUS enabled=1 hosts=8 resolved=5 failed=many retained=0 addresses=19'
        pcase 'two status lines: last wins'   2 TOOLCHAIN_STATUS '[toolchain] TOOLCHAIN_STATUS failed=7 addresses=1
[toolchain] TOOLCHAIN_STATUS failed=2 addresses=3'
        # THE CONTROL. Every "expected 0" case above would also pass against a
        # failed_from() that always returned 0. These two cannot, and they are
        # the ones that decide whether the boot refresh ever waits.
        pcase 'CONTROL: a nonzero really reads back' 5 TOOLCHAIN_STATUS '[toolchain] TOOLCHAIN_STATUS enabled=1 hosts=8 resolved=3 failed=5 retained=0 addresses=11'
    fi
fi

echo
echo "=== the five-hourly refresh must REACH its resolver calls ==="
# The original defect: clawfactory-allow-providers.sh began with
# `nft list table ... || exit 0`, ninety lines above the two Guard 3 resolver
# calls, so a boot tick that fired before the firewall unit skipped them and
# reported success. The assertion is structural over the script setup.ps1
# EMITS: no unconditional `exit` may stand between the top of the file and the
# first resolver call.
#
# AND THE ASSERTION IS ITSELF A PROBE, so it is run twice: once against the
# emitted script, and once against a copy with the old `|| exit 0` deliberately
# put back. If the second run does not FAIL, the check is worthless.
REFRESH="$WORK/refresh.sh"
sed -n "/^cat > \/usr\/local\/sbin\/clawfactory-allow-providers.sh <<'REFRESH'$/,/^REFRESH$/p" \
    "$HERE/setup.ps1" | sed '1d;$d' > "$REFRESH"

reaches_resolvers() {   # $1 = script path -> prints yes|no
    local first_resolver first_exit
    first_resolver="$(grep -n '/usr/local/sbin/clawfactory-read-fetch.sh' "$1" | head -1 | cut -d: -f1)"
    if [ -z "$first_resolver" ]; then echo 'no-resolver-call'; return; fi
    first_exit="$(grep -nE '^[[:space:]]*(exit [0-9]+|.*\|\|[[:space:]]*exit [0-9]+)[[:space:]]*$' "$1" | head -1 | cut -d: -f1)"
    if [ -n "$first_exit" ] && [ "$first_exit" -lt "$first_resolver" ]; then echo no; else echo yes; fi
}

if [ ! -s "$REFRESH" ]; then
    echo "FAIL  could not extract clawfactory-allow-providers.sh from setup.ps1"
    FAIL=$((FAIL + 1))
else
    check 'emitted refresh reaches the resolvers' yes "$(reaches_resolvers "$REFRESH")"
    # THE CANARY: put the defect back, in the exact shape it shipped in.
    BROKEN="$WORK/refresh-broken.sh"
    awk 'NR==1{print; print "nft list table inet clawfactory >/dev/null 2>&1 || exit 0"; next} {print}' \
        "$REFRESH" > "$BROKEN"
    check 'CANARY: the shipped defect is DETECTED' no "$(reaches_resolvers "$BROKEN")"
fi

echo
echo "EGRESS_BOOT_CALIBRATION pass=$PASS fail=$FAIL"
[ "$FAIL" -eq 0 ]
