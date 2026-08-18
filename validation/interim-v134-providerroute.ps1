<#
  Provider-route diagnosis. Card #257. Ship-blocker.

  WHAT IS BROKEN. On a freshly installed clean box running 1.3.4 the agent could
  not reach its own model. Three real turns, ten minutes, every one blocked by the
  machine's own firewall, and the kernel named the destination it refused. The
  turn failed identically with the toolchain toggle ON and OFF, so the toggle is
  exonerated and TC.3 as previously reported was an attribution error.

  WHAT THIS PROBE IS FOR. It discriminates between four candidates rather than
  confirming one. Section 7 of the source-read artefact
  (docs/session_reports/2026-08-18_provider_route_source_read.md) already refutes
  B and D from source, and weakens A with eleven forward lookups that returned one
  address every time. So the first measurement here is a single discriminating
  question, and everything after it branches on the answer:

      Is the address the gateway dials in @allowed_ipv4 immediately after a clean
      install, before any additional refresh cycle?

  If YES, every candidate in the work package is wrong, the set was right, and the
  packet was refused for another reason: a port other than 443, an address family
  the accept does not cover, or an instrument that attributed the drop wrongly.
  That is why this probe logs the PORT and the PROTOCOL and not only the address.
  If NO, the install evidence names which seed site did not take.

  THE INSTRUMENT, AND WHY THE TWO OBVIOUS ONES ARE WRONG. A packet capture cannot
  see this: nft's output filter hook drops before the device layer, so tcpdump
  reports a clean nothing for exactly the case under investigation, which reads as
  "not a network problem". conntrack is no better, because a dropped SYN never
  becomes a tracked connection. What sees it is the ruleset, so a rate-limited log
  rule goes in immediately before the terminal drop and the kernel names the
  destination.

  CALIBRATE BEFORE MEASURING, and the calibration GATES the subject. The rule is
  pointed at a destination that MUST be dropped and must be NAMED, and at an
  address that is in the allowlist and must NOT be named, so the instrument is
  shown to discriminate rather than merely to emit. If either half fails, the real
  measurement does not run: a null result from an uncalibrated instrument reads as
  "no network dependency" and is uninterpretable.

  WHAT THIS WRITES TO THE BOX. Exactly one thing, and it is removed in section 8:
  a `log` rule. A log action changes no reachability. Section 6 runs the SHIPPED
  refresh unit, which is the product's own five-hourly path executed early; it
  grants nothing the product would not grant itself within five hours. Nothing
  here makes the agent able to reach anything it could not reach before.
#>
param(
    [string]$Transcript = 'C:\cfv\provroute-out-probe.txt'
)

$ErrorActionPreference = 'Continue'
. C:\cfv\interim-v120-wslchan.ps1
. C:\cfv\interim-v120-phaselib.ps1

Start-Phase -Name 'Provider route: is the address the gateway dials in the allowlist' `
    -Transcript $Transcript -Sentinel 'PROVROUTE_PROBE_COMPLETE'

$chan = Test-WslChannel
Register-Control -Id 'PR.CHAN' -Name 'the file-based WSL channel discriminates' `
    -Fired $chan.Ok -Evidence $chan.Detail | Out-Null
if (-not $chan.Ok) { Complete-Phase -ResultsJson 'C:\cfv\provroute-results.json' -MarkerPrefix 'PROVROUTE' }

# =========================================================================
Section '1. MEASUREMENT 1: @allowed_ipv4 immediately after install, before any additional refresh'
# READ ONLY, and deliberately the first thing this probe does. Anything that
# triggers a refresh before this point destroys the measurement, because the
# whole accumulation account under test says a refresh repairs the defect.
$m1 = Invoke-WslFile -Tag 'pr-set' -User 'root' -Body @'
echo "=== the provider set, verbatim ==="
nft list set inet clawfactory allowed_ipv4 2>&1
echo "SET_READ_RC=$?"
echo
echo "=== element count ==="
echo "ALLOWED_COUNT=$(nft list set inet clawfactory allowed_ipv4 2>/dev/null | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | sort -u | wc -l)"
echo "TOOLCHAIN_COUNT=$(nft list set inet clawfactory toolchain_ipv4 2>/dev/null | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | sort -u | wc -l)"
echo "READFETCH_COUNT=$(nft list set inet clawfactory read_fetch_ipv4 2>/dev/null | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | sort -u | wc -l)"
echo
echo "=== CONTROL: the same read against a set that does not exist ==="
# Without this, ALLOWED_COUNT=0 cannot be told apart from a failed listing, and
# telling those two apart is the entire subject of the previous session.
nft list set inet clawfactory no_such_set_zzz >/dev/null 2>&1
echo "BOGUS_SET_RC=$?"
echo "BOGUS_SET_COUNT=$(nft list set inet clawfactory no_such_set_zzz 2>/dev/null | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | sort -u | wc -l)"
echo
echo "=== the persisted list the boot path replays ==="
echo "PERSISTED_COUNT=$(grep -c . /etc/clawfactory/allowed-ips.txt 2>/dev/null || echo 0)"
cat /etc/clawfactory/allowed-ips.txt 2>&1 | tr '\n' ' '; echo
echo
echo "=== the refresh timer and unit, as installed ==="
echo "TIMER_ENABLED=$(systemctl is-enabled clawfactory-allow-providers.timer 2>&1)"
echo "TIMER_ACTIVE=$(systemctl is-active clawfactory-allow-providers.timer 2>&1)"
systemctl show clawfactory-allow-providers.timer -p LastTriggerUSec -p NextElapseUSecRealtime 2>&1
systemctl show clawfactory-allow-providers.service -p Result -p NRestarts -p ExecMainStartTimestamp 2>&1
echo
echo "=== the terminal chain, so the accepts can be read rather than assumed ==="
nft -a list chain inet clawfactory output 2>&1
'@
W $m1.Out

$allowedCount = if ($m1.Out -match 'ALLOWED_COUNT=(\d+)')  { [int]$Matches[1] } else { -1 }
$persisted    = if ($m1.Out -match 'PERSISTED_COUNT=(\d+)'){ [int]$Matches[1] } else { -1 }
$bogusRc      = if ($m1.Out -match 'BOGUS_SET_RC=(\d+)')   { [int]$Matches[1] } else { -1 }

# The control that makes ALLOWED_COUNT mean anything. A bogus set name must fail
# to read. If it did not, the counter is counting something other than set
# membership and every number in this section is worthless.
Register-Control -Id 'PR.1.CTL' -Name 'the set reader can tell a real set from one that does not exist' `
    -Fired ($bogusRc -ne 0 -and $allowedCount -ge 0) `
    -Evidence "a nonexistent set name returned rc=$bogusRc (must be nonzero) while allowed_ipv4 read $allowedCount address(es); without this, zero and unreadable are the same output" | Out-Null

Record 'PR.1a' 'The provider set is populated at all on a fresh install' `
    $(if ($allowedCount -gt 0) { 'PASS' } elseif ($allowedCount -eq 0) { 'FAIL' } else { 'VOID' }) `
    "@allowed_ipv4 holds $allowedCount distinct address(es); /etc/clawfactory/allowed-ips.txt holds $persisted line(s). Candidate C predicts zero here."

# =========================================================================
Section '2. MEASUREMENT 2: forward resolution of every seeded provider hostname, several passes'
# Candidate A lives or dies here, and it is measured from INSIDE the distro on a
# clean box rather than from the build machine's network.
$m2 = Invoke-WslFile -Tag 'pr-resolve' -User 'root' -Body @'
echo "=== CONTROL A: a name that MUST resolve ==="
echo "CTL_RESOLVES=$(getent ahostsv4 openclaw.ai 2>/dev/null | awk '{print $1}' | sort -u | wc -l)"
echo "=== CONTROL B: a name that MUST NOT resolve ==="
echo "CTL_NXDOMAIN=$(getent ahostsv4 cf-no-such-host-zzz.invalid 2>/dev/null | awk '{print $1}' | sort -u | wc -l)"
echo
for h in api.anthropic.com console.anthropic.com api.openai.com auth.openai.com api.x.ai; do
  echo "--- $h ---"
  for i in 1 2 3 4 5; do
    echo "  pass$i: $(getent ahostsv4 "$h" 2>/dev/null | awk '{print $1}' | sort -u | tr '\n' ' ')"
    sleep 1
  done
  U=$(for i in 1 2 3 4 5; do getent ahostsv4 "$h" 2>/dev/null | awk '{print $1}'; done | sort -u)
  echo "  UNION=$(echo $U | tr ' ' ',')"
  echo "  UNION_COUNT_$h=$(echo "$U" | sed '/^$/d' | wc -l)"
done
echo
echo "=== is each currently-resolved provider address in the set? ==="
for h in api.anthropic.com console.anthropic.com api.openai.com auth.openai.com api.x.ai; do
  for ip in $(getent ahostsv4 "$h" 2>/dev/null | awk '{print $1}' | sort -u); do
    IN=$(nft list set inet clawfactory allowed_ipv4 2>/dev/null | grep -c "\b$ip\b")
    echo "  MEMBER $h $ip in_allowed=$IN"
  done
done
'@
W $m2.Out

$ctlResolves = if ($m2.Out -match 'CTL_RESOLVES=(\d+)')  { [int]$Matches[1] } else { -1 }
$ctlNx       = if ($m2.Out -match 'CTL_NXDOMAIN=(\d+)')  { [int]$Matches[1] } else { -1 }
Register-Control -Id 'PR.2.CTL' -Name 'the in-distro resolver discriminates a real name from a bogus one' `
    -Fired ($ctlResolves -gt 0 -and $ctlNx -eq 0) `
    -Evidence "openclaw.ai resolved to $ctlResolves address(es) and an .invalid name to $ctlNx; without both, an empty provider result cannot be told from a dead resolver" | Out-Null

$provUnion = if ($m2.Out -match 'UNION_COUNT_api\.anthropic\.com=(\d+)') { [int]$Matches[1] } else { -1 }
Record 'PR.2' 'CANDIDATE A: the provider address pool rotates between lookups' `
    $(if ($provUnion -gt 1) { 'PASS' } elseif ($provUnion -eq 1) { 'FAIL' } else { 'VOID' }) `
    "api.anthropic.com resolved to $provUnion distinct address(es) across five in-distro lookups. More than one supports candidate A, because the provider path resolves ONCE and does not union (setup.ps1:1598-1603) while the toolchain path resolves three times (clawfactory-toolchain.sh:206-214). Exactly one refutes it."

$memberMiss = @([regex]::Matches($m2.Out, 'MEMBER (\S+) (\d+\.\d+\.\d+\.\d+) in_allowed=(\d+)') |
    Where-Object { [int]$_.Groups[3].Value -eq 0 } | ForEach-Object { "$($_.Groups[1].Value)/$($_.Groups[2].Value)" })
$memberRows = [regex]::Matches($m2.Out, 'MEMBER \S+ \d+\.\d+\.\d+\.\d+ in_allowed=\d+').Count
Record 'PR.2b' 'Every currently-resolved provider address is in @allowed_ipv4' `
    $(if ($memberRows -eq 0) { 'VOID' } elseif ($memberMiss.Count -eq 0) { 'PASS' } else { 'FAIL' }) `
    ("$memberRows host/address rows read; missing from the set: " +
     $(if ($memberMiss.Count) { ($memberMiss | Select-Object -Unique) -join ', ' } else { 'NONE' }))

# =========================================================================
Section '3. MEASUREMENT 5: which install step populated the set, distinguishing candidate C'
$m5 = Invoke-WslFile -Tag 'pr-install-evidence' -User 'root' -Body @'
echo "=== the shipped refresh script exists and is root-owned ==="
ls -l /usr/local/sbin/clawfactory-allow-providers.sh 2>&1
echo "=== the host list it actually carries ==="
grep -m1 '^AUX_HOSTS=' /usr/local/sbin/clawfactory-allow-providers.sh 2>&1
echo "=== CONTROL: the same grep for a pattern that must NOT be there ==="
# The canary is shaped like the thing being looked for, not like something
# already known to be absent: a plausible-looking assignment of a toolchain host.
grep -c '^AUX_HOSTS=.*api\.github\.com' /usr/local/sbin/clawfactory-allow-providers.sh 2>/dev/null || echo 0
echo
echo "=== journal for the refresh unit since boot ==="
journalctl -u clawfactory-allow-providers.service --no-pager 2>&1 | tail -40
echo
echo "=== CONTROL: the same journal query against a unit that does not exist ==="
echo "BOGUS_UNIT_LINES=$(journalctl -u cf-no-such-unit-zzz.service --no-pager 2>/dev/null | grep -c .)"
'@
W $m5.Out

# =========================================================================
Section '4. CALIBRATE THE INSTRUMENT, and refuse to measure if it does not discriminate'
# The rate-limited log rule goes in immediately before the terminal drop. It is a
# log action: it accepts nothing, drops nothing, and changes no reachability.
#
# THE FAILURE STRINGS, stated here per the measurement rules. Calibration fails
# on CALIBRATION_NAMED=0 or on DISCRIMINATES=0. Neither string is echoed anywhere
# else in this probe's own output, so neither control can pass by finding itself.
$cal = Invoke-WslFile -Tag 'pr-calibrate' -User 'root' -Body @'
set -u
# The terminal drop is the only rule in this chain that is a bare counter+drop
# with no match expression. Guard 2's SMTP drop starts with `tcp dport`, and the
# two 8788 drops start with `ip daddr`, so anchoring on the line start excludes
# all three.
H=$(nft -a list chain inet clawfactory output 2>/dev/null \
    | grep -E '^[[:space:]]*counter packets [0-9]+ bytes [0-9]+ drop # handle [0-9]+$' \
    | tail -1 | awk '{print $NF}')
echo "TERMINAL_DROP_HANDLE=${H:-NONE}"
if [ -z "${H:-}" ]; then echo "CALIBRATION_NAMED=0"; echo "DISCRIMINATES=0"; echo "INSTRUMENT_INSTALLED=0"; exit 0; fi

nft insert rule inet clawfactory output handle "$H" limit rate 200/second log prefix '"CFDROP:"' 2>&1
echo "INSERT_RC=$?"
if nft list chain inet clawfactory output 2>/dev/null | grep -q 'CFDROP'; then
  echo "INSTRUMENT_INSTALLED=1"
else
  echo "INSTRUMENT_INSTALLED=0"; echo "CALIBRATION_NAMED=0"; echo "DISCRIMINATES=0"; exit 0
fi
echo "--- the last three rules, so the ORDER can be read rather than assumed ---"
nft list chain inet clawfactory output 2>/dev/null | tail -4

# --- calibration target: MUST be dropped and MUST be named -----------------
CALIP=$(getent ahostsv4 example.org 2>/dev/null | awk '{print $1}' | head -1)
echo "CALIBRATION_TARGET=${CALIP:-NONE}"
if [ -z "${CALIP:-}" ]; then echo "CALIBRATION_NAMED=0"; echo "DISCRIMINATES=0"; exit 0; fi
MARK=$(dmesg 2>/dev/null | wc -l)
su -s /bin/bash -c "timeout 6 bash -c 'exec 3<>/dev/tcp/$CALIP/443'" clawuser >/dev/null 2>&1 || true
sleep 3
HITS=$(dmesg 2>/dev/null | tail -n +$((MARK+1)) | grep -c "CFDROP:.*DST=$CALIP")
echo "CALIBRATION_HITS=$HITS"
if [ "$HITS" -gt 0 ]; then echo "CALIBRATION_NAMED=1"; else echo "CALIBRATION_NAMED=0"; fi
echo "--- the calibration lines the kernel actually wrote ---"
dmesg 2>/dev/null | tail -n +$((MARK+1)) | grep "CFDROP:" | tail -3

# --- discrimination target: an address that IS in the set MUST NOT be named -
# Taken from the live set rather than hardcoded, so this control is meaningful
# whatever the set turns out to contain. If the set is empty there is no such
# address and the control is reported as unavailable rather than as a pass.
OKIP=$(nft list set inet clawfactory allowed_ipv4 2>/dev/null | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | sort -u | head -1)
echo "DISCRIM_TARGET=${OKIP:-NONE}"
if [ -z "${OKIP:-}" ]; then echo "DISCRIMINATES=0"; echo "DISCRIM_UNAVAILABLE=1"; exit 0; fi
MARK2=$(dmesg 2>/dev/null | wc -l)
su -s /bin/bash -c "timeout 8 bash -c 'exec 3<>/dev/tcp/$OKIP/443'" clawuser >/dev/null 2>&1 || true
sleep 3
NOISE=$(dmesg 2>/dev/null | tail -n +$((MARK2+1)) | grep -c "CFDROP:.*DST=$OKIP")
echo "DISCRIM_HITS=$NOISE"
if [ "$NOISE" -eq 0 ]; then echo "DISCRIMINATES=1"; else echo "DISCRIMINATES=0"; fi
'@
W $cal.Out

$calNamed  = $cal.Out -match 'CALIBRATION_NAMED=1'
$calDiscr  = $cal.Out -match 'DISCRIMINATES=1'
$discrNA   = $cal.Out -match 'DISCRIM_UNAVAILABLE=1'

Register-Control -Id 'PR.4.CTL1' -Name 'the drop log NAMES a destination that must be dropped' `
    -Fired $calNamed `
    -Evidence "target $(if ($cal.Out -match 'CALIBRATION_TARGET=(\S+)') { $Matches[1] } else { '?' }), hits $(if ($cal.Out -match 'CALIBRATION_HITS=(\d+)') { $Matches[1] } else { '?' }). A null result from an uncalibrated instrument reads as 'no network dependency' and is uninterpretable, so this gates the subject." | Out-Null

Register-Control -Id 'PR.4.CTL2' -Name 'the drop log stays SILENT for an address that is in the allowlist' `
    -Fired $calDiscr `
    -Evidence $(if ($discrNA) { 'UNAVAILABLE: the allowlist is empty, so no in-set address exists to test silence against. That emptiness is itself measurement 1 answering the question.' } else { "target $(if ($cal.Out -match 'DISCRIM_TARGET=(\S+)') { $Matches[1] } else { '?' }), spurious hits $(if ($cal.Out -match 'DISCRIM_HITS=(\d+)') { $Matches[1] } else { '?' }) (must be 0). Without this the instrument could be logging everything and naming the provider by accident." }) | Out-Null

$instrumentOk = $calNamed -and $calDiscr

# =========================================================================
Section '5. MEASUREMENT 3 and 4: the address the gateway actually dials, during a real turn'
if (-not $instrumentOk) {
    Record 'PR.3' 'The address the gateway dials, read from the drop log during a real turn' 'VOID' `
        'the instrument did not calibrate, so the subject was NOT run. A null result here would have read as "no network dependency" and would have been uninterpretable.'
    Record 'PR.4' 'Set difference between the seeded allowlist and the address actually dialled' 'VOID' `
        'no measured dial address, because section 4 refused to run the subject'
} else {
    # L17: warm the agent. A cold first turn failing would be recorded as a
    # provider-route finding it has nothing to do with.
    W '--- warming the agent (L17) before any load-bearing turn ---'
    $warm = Invoke-WslFile -Tag 'pr-warm' -User 'clawuser' -Body @'
TOKEN=$(node -e 'const j=require("/home/clawuser/.openclaw/openclaw.json");process.stdout.write((j.gateway&&j.gateway.auth&&j.gateway.auth.token)||"")')
printf '%s' '{"model":"openclaw/main","stream":false,"messages":[{"role":"user","content":"Reply with exactly: WARMUP"}]}' > /var/tmp/pr-warm.json
curl -s --max-time 120 -X POST http://127.0.0.1:8787/v1/chat/completions -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" -H "x-openclaw-agent-id: main" --data @/var/tmp/pr-warm.json | head -c 600
rm -f /var/tmp/pr-warm.json
echo
'@
    W $warm.Out

    $subj = Invoke-WslFile -Tag 'pr-turn' -User 'root' -Body @'
MARK=$(dmesg 2>/dev/null | wc -l)
echo "DMESG_MARK=$MARK"
cat > /var/tmp/pr-turn.sh <<'EOS'
TOKEN=$(node -e 'const j=require("/home/clawuser/.openclaw/openclaw.json");process.stdout.write((j.gateway&&j.gateway.auth&&j.gateway.auth.token)||"")')
printf '%s' '{"model":"openclaw/main","stream":false,"messages":[{"role":"user","content":"Reply with exactly: PROVROUTEOK"}]}' > /var/tmp/pr-body.json
curl -s --max-time 200 -X POST http://127.0.0.1:8787/v1/chat/completions -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" -H "x-openclaw-agent-id: main" --data @/var/tmp/pr-body.json | head -c 900
rm -f /var/tmp/pr-body.json
echo
EOS
chmod 644 /var/tmp/pr-turn.sh
START=$(date +%s)
echo "--- TURN RESPONSE ---"
su -s /bin/bash -c 'bash /var/tmp/pr-turn.sh' clawuser 2>&1
echo "TURN_SECONDS=$(( $(date +%s) - START ))"
rm -f /var/tmp/pr-turn.sh
sleep 3
echo
echo "--- DROPPED, aggregated by destination and port ---"
dmesg 2>/dev/null | tail -n +$((MARK+1)) | grep "CFDROP:" \
  | sed -nE 's/.*DST=([0-9.]+).*PROTO=([A-Z]+).*DPT=([0-9]+).*/DROPPED \1 \2 \3/p' \
  | sort | uniq -c | awk '{print "DROPCOUNT="$1" "$3" "$4" dport="$5}'
echo "TOTAL_DROP_LINES=$(dmesg 2>/dev/null | tail -n +$((MARK+1)) | grep -c 'CFDROP:')"
echo
echo "--- raw sample, at most five lines ---"
dmesg 2>/dev/null | tail -n +$((MARK+1)) | grep "CFDROP:" | tail -5
echo
echo "--- and for each dropped destination, is it in the set right now ---"
for ip in $(dmesg 2>/dev/null | tail -n +$((MARK+1)) | grep "CFDROP:" | sed -nE 's/.*DST=([0-9.]+).*/\1/p' | sort -u); do
  IN=$(nft list set inet clawfactory allowed_ipv4 2>/dev/null | grep -c "\b$ip\b")
  RDNS=$(getent hosts "$ip" 2>/dev/null | awk '{print $2}' | head -1)
  echo "DIFF $ip in_allowed=$IN rdns=${RDNS:-none}"
done
'@
    W $subj.Out

    $turnOk    = $subj.Out -match 'PROVROUTEOK'
    $dropLines = if ($subj.Out -match 'TOTAL_DROP_LINES=(\d+)') { [int]$Matches[1] } else { -1 }
    $dropRows  = @([regex]::Matches($subj.Out, 'DROPCOUNT=(\d+) (\d+\.\d+\.\d+\.\d+) (\S+) dport=(\d+)') |
                   ForEach-Object { "$($_.Groups[1].Value)x $($_.Groups[2].Value):$($_.Groups[4].Value)/$($_.Groups[3].Value)" })
    $diffMiss  = @([regex]::Matches($subj.Out, 'DIFF (\d+\.\d+\.\d+\.\d+) in_allowed=(\d+) rdns=(\S+)') |
                   Where-Object { [int]$_.Groups[2].Value -eq 0 } |
                   ForEach-Object { "$($_.Groups[1].Value) ($($_.Groups[3].Value))" })

    Record 'PR.3a' 'A real agent turn completes end to end on a clean 1.3.4 install' `
        $(if ($turnOk) { 'PASS' } else { 'FAIL' }) `
        "the model reply is the evidence; turn took $(if ($subj.Out -match 'TURN_SECONDS=(\d+)') { $Matches[1] } else { '?' })s"

    Record 'PR.3b' 'The turn produced firewall drops, and the kernel named the destination' `
        $(if ($dropLines -gt 0) { 'PASS' } elseif ($dropLines -eq 0) { 'FAIL' } else { 'VOID' }) `
        ("$dropLines logged drops during the turn: " + $(if ($dropRows.Count) { $dropRows -join '; ' } else { 'none' }) +
         ". A calibrated instrument reporting zero here means the turn made no blocked outbound attempt.")

    Record 'PR.4' 'MEASUREMENT 4: every address the gateway dialled is in the seeded allowlist' `
        $(if ($dropLines -lt 0) { 'VOID' } elseif ($diffMiss.Count -eq 0) { 'PASS' } else { 'FAIL' }) `
        ("addresses dialled and refused because they are NOT in @allowed_ipv4: " +
         $(if ($diffMiss.Count) { ($diffMiss | Select-Object -Unique) -join ', ' } else { 'NONE' }) +
         '. That difference is the finding.')
}

# =========================================================================
Section '6. MEASUREMENT 6: does a turn succeed after one refresh cycle has run'
# This tests the accumulation-masks-the-defect account directly. The SHIPPED unit
# is started, not a simulation: it is the same code that runs unattended five
# hours after install. Running it early grants nothing the product would not
# grant itself.
$ref = Invoke-WslFile -Tag 'pr-refresh' -User 'root' -Body @'
echo "BEFORE_COUNT=$(nft list set inet clawfactory allowed_ipv4 2>/dev/null | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | sort -u | wc -l)"
systemctl start clawfactory-allow-providers.service
sleep 4
echo "UNIT_RESULT=$(systemctl show clawfactory-allow-providers.service -p Result --value 2>&1)"
echo "AFTER_COUNT=$(nft list set inet clawfactory allowed_ipv4 2>/dev/null | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | sort -u | wc -l)"
journalctl -u clawfactory-allow-providers.service -n 20 --no-pager 2>&1 | tail -20
echo "--- is the provider address in the set NOW ---"
for ip in $(getent ahostsv4 api.anthropic.com 2>/dev/null | awk '{print $1}' | sort -u); do
  echo "POSTREFRESH $ip in_allowed=$(nft list set inet clawfactory allowed_ipv4 2>/dev/null | grep -c "\b$ip\b")"
done
'@
W $ref.Out
$before = if ($ref.Out -match 'BEFORE_COUNT=(\d+)') { [int]$Matches[1] } else { -1 }
$after  = if ($ref.Out -match 'AFTER_COUNT=(\d+)')  { [int]$Matches[1] } else { -1 }

Register-Control -Id 'PR.6.CTL' -Name 'the refresh unit actually ran in this run' `
    -Fired ($ref.Out -match 'UNIT_RESULT=success') `
    -Evidence "unit Result=$(if ($ref.Out -match 'UNIT_RESULT=(\S+)') { $Matches[1] } else { '?' }); set went $before -> $after addresses. Without this, 'the turn still fails' would be indistinguishable from 'the refresh never ran'." | Out-Null

$post = Invoke-WslFile -Tag 'pr-turn2' -User 'clawuser' -Body @'
TOKEN=$(node -e 'const j=require("/home/clawuser/.openclaw/openclaw.json");process.stdout.write((j.gateway&&j.gateway.auth&&j.gateway.auth.token)||"")')
printf '%s' '{"model":"openclaw/main","stream":false,"messages":[{"role":"user","content":"Reply with exactly: POSTREFRESHOK"}]}' > /var/tmp/pr-body2.json
curl -s --max-time 200 -X POST http://127.0.0.1:8787/v1/chat/completions -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" -H "x-openclaw-agent-id: main" --data @/var/tmp/pr-body2.json | head -c 900
rm -f /var/tmp/pr-body2.json
echo
'@
W $post.Out
Record 'PR.6' 'A real turn succeeds after ONE refresh cycle has run' `
    $(if ($post.Out -match 'POSTREFRESHOK') { 'PASS' } else { 'FAIL' }) `
    "tests the accumulation account directly: if the turn fails before the refresh and succeeds after it, the defect is that the seeded set was missing the address and the timer repairs it within five hours"

# =========================================================================
Section '7. The install transcript, for the seed steps named in the source read'
# Read from the WINDOWS side, not through the distro. automount is disabled on a
# ClawFactory box, so /mnt/c is an empty stub and a grep through it would return
# nothing and read as "the installer never logged that".
$logPath = 'C:\ProgramData\ClawFactory\install.log'
if (-not (Test-Path $logPath)) {
    Record 'PR.7' 'The install transcript names the firewall step and the auxiliary seed' 'VOID' `
        "install.log absent at $logPath, so nothing here was searched"
} else {
    $log = Get-Content $logPath -Raw
    # A SEARCH FOR ABSENCES MUST FIRST PROVE ITS TARGET IS SEARCHABLE. The canary
    # is shaped like the thing being looked for, a Write-Log INFO line from the
    # firewall step, not like something already known to be present.
    $searchable = $log -match 'Step 7 \[R3\]'
    Assert-Searchable -Id 'PR.7.CTL' -Name 'the installer transcript' `
        -PositiveMarkerFound $searchable `
        -MarkerDescription 'the Step 7 [R3] firewall banner, which every install writes' | Out-Null
    foreach ($pat in @('Allowlist hosts:.*', 'active backend:.*', 'Step 7 \[R3\].*', 'Step 8b.*', 'allowlisted .*')) {
        foreach ($m in [regex]::Matches($log, $pat)) { W ("  LOG| " + $m.Value.Trim()) }
    }
    $hostsLine = if ($log -match 'Allowlist hosts: (.*)') { $Matches[1].Trim() } else { '(absent)' }
    Record 'PR.7' 'The install transcript names the exact host list the firewall step resolved' `
        $(if ($searchable -and $hostsLine -ne '(absent)') { 'PASS' } elseif ($searchable) { 'FAIL' } else { 'VOID' }) `
        "Allowlist hosts: $hostsLine"
}

# =========================================================================
Section '8. Remove the instrument, and prove the chain is back to its shipped shape'
$rm = Invoke-WslFile -Tag 'pr-cleanup' -User 'root' -Body @'
H=$(nft -a list chain inet clawfactory output 2>/dev/null | grep 'CFDROP' | tail -1 | awk '{print $NF}')
if [ -n "${H:-}" ]; then nft delete rule inet clawfactory output handle "$H" 2>&1; fi
if nft list chain inet clawfactory output 2>/dev/null | grep -q 'CFDROP'; then
  echo "INSTRUMENT_REMOVED=0"
else
  echo "INSTRUMENT_REMOVED=1"
fi
echo "--- the shipped tripwire must still pass, which is the independent check that nothing drifted ---"
/usr/local/sbin/clawfactory-fw-assert.sh >/dev/null 2>&1
echo "FW_ASSERT_RC=$?"
'@
W $rm.Out
Record 'PR.8' 'The probe left the shipped chain exactly as it found it' `
    $(if (($rm.Out -match 'INSTRUMENT_REMOVED=1') -and ($rm.Out -match 'FW_ASSERT_RC=0')) { 'PASS' } else { 'FAIL' }) `
    'the only write this probe made was a log rule, which accepts nothing and drops nothing; the shipped chain-shape tripwire is the independent confirmation'

Complete-Phase -ResultsJson 'C:\cfv\provroute-results.json' -MarkerPrefix 'PROVROUTE'
