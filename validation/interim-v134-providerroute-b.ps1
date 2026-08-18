<#
  Provider-route diagnosis, part B. Card #257.

  WHY THERE IS A PART B. Part A measured a clean 1.3.4 box and the reported
  defect DID NOT REPRODUCE: @allowed_ipv4 held the provider address, the
  443-scoped accept was present, a real turn completed in 48 seconds, and a
  fully calibrated drop instrument logged ZERO drops during that turn. All four
  candidates in the work package are refuted by that one measurement.

  So the question changes. It is no longer "why is the provider route missing".
  It is "what did cfv-167 do that cfv-168 did not". There is exactly one
  procedural difference between the two runs, and this probe replays it.

  THE DIFFERENCE. cfv-167 measured TC.3 through the toolchain probe, which flips
  the switch with `clawfactory-fetchctl toolchain off` and back on. Part A never
  touched the switch. On the nftables backend the toolchain resolver only flushes
  and rebuilds @toolchain_ipv4 and never touches @allowed_ipv4, so from source
  that flip cannot affect the provider route; this probe is here because "cannot
  from source" is what the last three sessions each believed before measuring.

  This replays cfv-167's exact sequence: SUBJECT is a turn with the toggle OFF,
  CONTROL is a turn with the toggle ON, both with the drop instrument live.

  A NEW PROBE INHERITS NONE OF THE PRECONDITIONS OF THE ONE BESIDE IT. The
  instrument is therefore re-installed and re-calibrated in BOTH directions here,
  from scratch, even though part A calibrated it twenty minutes ago.

  THE DISCRIMINATION HALF OF THE CALIBRATION IS THE POINT OF THIS FILE. An
  instrument that logs before the allowlist accept rather than after it will
  faithfully name every packet the agent sends to the provider, including the
  ones that are then ACCEPTED, and a reader would record those as drops. Pointing
  it at a destination that must be dropped cannot tell those two placements
  apart. Pointing it at an address that IS in the allowlist can, and must find
  nothing. That control is registered here for the same reason it is in part A.
#>
param(
    [string]$Transcript = 'C:\cfv\providerroute-b-out-probe.txt'
)

$ErrorActionPreference = 'Continue'
. C:\cfv\interim-v120-wslchan.ps1
. C:\cfv\interim-v120-phaselib.ps1

Start-Phase -Name 'Provider route B: replay the cfv-167 toggle sequence with a discriminating instrument' `
    -Transcript $Transcript -Sentinel 'PROVROUTEB_PROBE_COMPLETE'

$chan = Test-WslChannel
Register-Control -Id 'PB.CHAN' -Name 'the file-based WSL channel discriminates' `
    -Fired $chan.Ok -Evidence $chan.Detail | Out-Null
if (-not $chan.Ok) { Complete-Phase -ResultsJson 'C:\cfv\providerroute-b-results.json' -MarkerPrefix 'PROVROUTEB' }

# =========================================================================
Section '1. Re-install and re-calibrate the instrument from scratch'
$cal = Invoke-WslFile -Tag 'pb-calibrate' -User 'root' -Body @'
set -u
H=$(nft -a list chain inet clawfactory output 2>/dev/null \
    | grep -E '^[[:space:]]*counter packets [0-9]+ bytes [0-9]+ drop # handle [0-9]+$' \
    | tail -1 | awk '{print $NF}')
echo "TERMINAL_DROP_HANDLE=${H:-NONE}"
if [ -z "${H:-}" ]; then echo "CALIBRATION_NAMED=0"; echo "DISCRIMINATES=0"; exit 0; fi
nft insert rule inet clawfactory output handle "$H" limit rate 200/second log prefix '"CFDROP:"' 2>&1
if nft list chain inet clawfactory output 2>/dev/null | grep -q 'CFDROP'; then
  echo "INSTRUMENT_INSTALLED=1"
else
  echo "INSTRUMENT_INSTALLED=0"; echo "CALIBRATION_NAMED=0"; echo "DISCRIMINATES=0"; exit 0
fi
echo "--- placement, read rather than assumed: the log rule and everything after it ---"
nft list chain inet clawfactory output 2>/dev/null | sed -n '/CFDROP/,$p'
echo "--- and everything BEFORE it, so a reader can see the accepts are above the log ---"
nft list chain inet clawfactory output 2>/dev/null | sed -n '1,/CFDROP/p'

CALIP=$(getent ahostsv4 example.org 2>/dev/null | awk '{print $1}' | head -1)
echo "CALIBRATION_TARGET=${CALIP:-NONE}"
if [ -z "${CALIP:-}" ]; then echo "CALIBRATION_NAMED=0"; echo "DISCRIMINATES=0"; exit 0; fi
MARK=$(dmesg 2>/dev/null | wc -l)
su -s /bin/bash -c "timeout 6 bash -c 'exec 3<>/dev/tcp/$CALIP/443'" clawuser >/dev/null 2>&1 || true
sleep 3
HITS=$(dmesg 2>/dev/null | tail -n +$((MARK+1)) | grep -c "CFDROP:.*DST=$CALIP")
echo "CALIBRATION_HITS=$HITS"
if [ "$HITS" -gt 0 ]; then echo "CALIBRATION_NAMED=1"; else echo "CALIBRATION_NAMED=0"; fi

# The discrimination half, and it is deliberately pointed at the PROVIDER
# address rather than at any in-set address. If the instrument were placed above
# the allowlist accept, THIS is the measurement that would light up, and it is
# exactly the reading that would be misrecorded as "the provider route is
# blocked".
PROVIP=$(getent ahostsv4 api.anthropic.com 2>/dev/null | awk '{print $1}' | head -1)
echo "DISCRIM_TARGET=${PROVIP:-NONE}"
echo "PROV_IN_SET=$(nft list set inet clawfactory allowed_ipv4 2>/dev/null | grep -c "\b$PROVIP\b")"
MARK2=$(dmesg 2>/dev/null | wc -l)
su -s /bin/bash -c "timeout 8 bash -c 'exec 3<>/dev/tcp/$PROVIP/443'" clawuser >/dev/null 2>&1 && echo "PROV_TCP=CONNECTED" || echo "PROV_TCP=blocked"
sleep 3
NOISE=$(dmesg 2>/dev/null | tail -n +$((MARK2+1)) | grep -c "CFDROP:.*DST=$PROVIP")
echo "DISCRIM_HITS=$NOISE"
if [ "$NOISE" -eq 0 ]; then echo "DISCRIMINATES=1"; else echo "DISCRIMINATES=0"; fi
'@
W $cal.Out
$calNamed = $cal.Out -match 'CALIBRATION_NAMED=1'
$calDiscr = $cal.Out -match 'DISCRIMINATES=1'
Register-Control -Id 'PB.1.CTL1' -Name 'the drop log NAMES an address that must be dropped' `
    -Fired $calNamed -Evidence "target $(if ($cal.Out -match 'CALIBRATION_TARGET=(\S+)') { $Matches[1] } else { '?' }), hits $(if ($cal.Out -match 'CALIBRATION_HITS=(\d+)') { $Matches[1] } else { '?' })" | Out-Null
Register-Control -Id 'PB.1.CTL2' -Name 'the drop log stays SILENT for the PROVIDER address, which is in the allowlist' `
    -Fired $calDiscr -Evidence ("target $(if ($cal.Out -match 'DISCRIM_TARGET=(\S+)') { $Matches[1] } else { '?' }), in_set=$(if ($cal.Out -match 'PROV_IN_SET=(\d+)') { $Matches[1] } else { '?' }), tcp=$(if ($cal.Out -match 'PROV_TCP=(\S+)') { $Matches[1] } else { '?' }), spurious hits $(if ($cal.Out -match 'DISCRIM_HITS=(\d+)') { $Matches[1] } else { '?' }) (must be 0). " +
    'An instrument placed above the allowlist accept would report drops here for traffic that is in fact accepted, which is the single most likely way to misread a working provider route as a blocked one.') | Out-Null
$instrumentOk = $calNamed -and $calDiscr

# =========================================================================
Section '2. SUBJECT: the cfv-167 sequence, toggle OFF, real turn, drop log'
if (-not $instrumentOk) {
    Record 'PB.2' 'A real turn with the toolchain toggle OFF' 'VOID' 'the instrument did not calibrate in both directions, so the subject was not run'
    Record 'PB.3' 'A real turn with the toolchain toggle ON' 'VOID' 'the instrument did not calibrate in both directions, so the subject was not run'
} else {
    $off = Invoke-WslFile -Tag 'pb-off' -User 'root' -Body @'
/usr/local/sbin/clawfactory-fetchctl toolchain off 2>&1 | tail -2
echo "TOOLCHAIN_COUNT_AFTER_OFF=$(nft list set inet clawfactory toolchain_ipv4 2>/dev/null | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | sort -u | wc -l)"
echo "ALLOWED_COUNT_AFTER_OFF=$(nft list set inet clawfactory allowed_ipv4 2>/dev/null | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | sort -u | wc -l)"
echo "PROV_STILL_IN_SET=$(nft list set inet clawfactory allowed_ipv4 2>/dev/null | grep -c '160\.79\.104\.10')"
'@
    W $off.Out

    $turnOff = Invoke-WslFile -Tag 'pb-turn-off' -User 'root' -Body @'
MARK=$(dmesg 2>/dev/null | wc -l)
cat > /var/tmp/pb-turn.sh <<'EOS'
TOKEN=$(node -e 'const j=require("/home/clawuser/.openclaw/openclaw.json");process.stdout.write((j.gateway&&j.gateway.auth&&j.gateway.auth.token)||"")')
printf '%s' '{"model":"openclaw/main","stream":false,"messages":[{"role":"user","content":"Reply with exactly: TOGGLEOFFOK"}]}' > /var/tmp/pb-body.json
curl -s --max-time 200 -X POST http://127.0.0.1:8787/v1/chat/completions -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" -H "x-openclaw-agent-id: main" --data @/var/tmp/pb-body.json | head -c 900
rm -f /var/tmp/pb-body.json
echo
EOS
START=$(date +%s)
echo "--- TURN RESPONSE, toggle OFF ---"
su -s /bin/bash -c 'bash /var/tmp/pb-turn.sh' clawuser 2>&1
echo "TURN_OFF_SECONDS=$(( $(date +%s) - START ))"
rm -f /var/tmp/pb-turn.sh
sleep 3
echo "OFF_DROP_LINES=$(dmesg 2>/dev/null | tail -n +$((MARK+1)) | grep -c 'CFDROP:')"
echo "OFF_PROVIDER_DROPS=$(dmesg 2>/dev/null | tail -n +$((MARK+1)) | grep -c 'CFDROP:.*DST=160.79.104.10')"
dmesg 2>/dev/null | tail -n +$((MARK+1)) | grep "CFDROP:" \
  | sed -nE 's/.*DST=([0-9.]+).*PROTO=([A-Z]+).*DPT=([0-9]+).*/OFFDROP \1 \2 \3/p' | sort | uniq -c
'@
    W $turnOff.Out
    $offOk    = $turnOff.Out -match 'TOGGLEOFFOK'
    $offProv  = if ($turnOff.Out -match 'OFF_PROVIDER_DROPS=(\d+)') { [int]$Matches[1] } else { -1 }
    Record 'PB.2' 'A real turn completes with the toolchain toggle OFF, the cfv-167 SUBJECT' `
        $(if ($offOk) { 'PASS' } else { 'FAIL' }) `
        "turn ok=$offOk, provider-address drops logged during it=$offProv, total drops=$(if ($turnOff.Out -match 'OFF_DROP_LINES=(\d+)') { $Matches[1] } else { '?' }). cfv-167 recorded 91 provider drops here."

    # ---- CONTROL: toggle back ON, the cfv-167 CONTROL --------------------
    $on = Invoke-WslFile -Tag 'pb-on' -User 'root' -Body @'
/usr/local/sbin/clawfactory-fetchctl toolchain on 2>&1 | tail -2
sleep 2
echo "TOOLCHAIN_COUNT_AFTER_ON=$(nft list set inet clawfactory toolchain_ipv4 2>/dev/null | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | sort -u | wc -l)"
echo "ALLOWED_COUNT_AFTER_ON=$(nft list set inet clawfactory allowed_ipv4 2>/dev/null | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | sort -u | wc -l)"
'@
    W $on.Out

    $turnOn = Invoke-WslFile -Tag 'pb-turn-on' -User 'root' -Body @'
MARK=$(dmesg 2>/dev/null | wc -l)
cat > /var/tmp/pb-turn2.sh <<'EOS'
TOKEN=$(node -e 'const j=require("/home/clawuser/.openclaw/openclaw.json");process.stdout.write((j.gateway&&j.gateway.auth&&j.gateway.auth.token)||"")')
printf '%s' '{"model":"openclaw/main","stream":false,"messages":[{"role":"user","content":"Reply with exactly: TOGGLEONOK"}]}' > /var/tmp/pb-body2.json
curl -s --max-time 200 -X POST http://127.0.0.1:8787/v1/chat/completions -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" -H "x-openclaw-agent-id: main" --data @/var/tmp/pb-body2.json | head -c 900
rm -f /var/tmp/pb-body2.json
echo
EOS
START=$(date +%s)
echo "--- TURN RESPONSE, toggle ON ---"
su -s /bin/bash -c 'bash /var/tmp/pb-turn2.sh' clawuser 2>&1
echo "TURN_ON_SECONDS=$(( $(date +%s) - START ))"
rm -f /var/tmp/pb-turn2.sh
sleep 3
echo "ON_DROP_LINES=$(dmesg 2>/dev/null | tail -n +$((MARK+1)) | grep -c 'CFDROP:')"
echo "ON_PROVIDER_DROPS=$(dmesg 2>/dev/null | tail -n +$((MARK+1)) | grep -c 'CFDROP:.*DST=160.79.104.10')"
dmesg 2>/dev/null | tail -n +$((MARK+1)) | grep "CFDROP:" \
  | sed -nE 's/.*DST=([0-9.]+).*PROTO=([A-Z]+).*DPT=([0-9]+).*/ONDROP \1 \2 \3/p' | sort | uniq -c
'@
    W $turnOn.Out
    $onOk   = $turnOn.Out -match 'TOGGLEONOK'
    $onProv = if ($turnOn.Out -match 'ON_PROVIDER_DROPS=(\d+)') { [int]$Matches[1] } else { -1 }
    Record 'PB.3' 'A real turn completes with the toolchain toggle ON, the cfv-167 CONTROL' `
        $(if ($onOk) { 'PASS' } else { 'FAIL' }) `
        "turn ok=$onOk, provider-address drops logged during it=$onProv. cfv-167 recorded 78 provider drops here, and that control failing is what exonerated the toggle."

    Record 'PB.4' 'The cfv-167 observation reproduces on a clean 1.3.4 box' `
        $(if ((-not $offOk) -and (-not $onOk) -and $offProv -gt 0 -and $onProv -gt 0) { 'PASS' } else { 'FAIL' }) `
        "reproduction requires BOTH turns to fail AND the provider address to be named by a calibrated instrument. Measured: off-turn ok=$offOk provider-drops=$offProv, on-turn ok=$onOk provider-drops=$onProv. A FAIL here means the reported defect did not reproduce."
}

# =========================================================================
Section '3. Remove the instrument and prove the shipped chain is unchanged'
$rm = Invoke-WslFile -Tag 'pb-cleanup' -User 'root' -Body @'
H=$(nft -a list chain inet clawfactory output 2>/dev/null | grep 'CFDROP' | tail -1 | awk '{print $NF}')
if [ -n "${H:-}" ]; then nft delete rule inet clawfactory output handle "$H" 2>&1; fi
if nft list chain inet clawfactory output 2>/dev/null | grep -q 'CFDROP'; then echo "INSTRUMENT_REMOVED=0"; else echo "INSTRUMENT_REMOVED=1"; fi
/usr/local/sbin/clawfactory-fw-assert.sh >/dev/null 2>&1
echo "FW_ASSERT_RC=$?"
echo "FINAL_TOOLCHAIN_STATE=$(/usr/local/sbin/clawfactory-fetchctl list 2>/dev/null | tr -d '\n' | head -c 300)"
'@
W $rm.Out
Record 'PB.5' 'The probe left the shipped chain exactly as it found it' `
    $(if (($rm.Out -match 'INSTRUMENT_REMOVED=1') -and ($rm.Out -match 'FW_ASSERT_RC=0')) { 'PASS' } else { 'FAIL' }) `
    'the toggle is left ON, which is the shipped default, and the only rule this probe added was a log rule that accepts nothing and drops nothing'

Complete-Phase -ResultsJson 'C:\cfv\providerroute-b-results.json' -MarkerPrefix 'PROVROUTEB'
