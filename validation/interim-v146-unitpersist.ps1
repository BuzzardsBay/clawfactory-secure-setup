<#
  interim-v146-unitpersist.ps1 -- DO THE GUARDS SURVIVE A REBOOT?

  THE CLAIM UNDER TEST, AND WHY IT HAS NEVER BEEN MEASURED
  --------------------------------------------------------
  ClawFactory's whole position is that its controls are STRUCTURAL rather than
  advisory: enforced by the operating system, not by asking the agent to behave.
  Guard 1's broker, Guard 2's broker, both GC timers, the gating proxy, the
  egress firewall and the provider-refresh timer are all systemd units, and
  seven of the eight are enabled with `>/dev/null 2>&1 || true`.

  `enable --now` makes TWO claims. Every install-time check in the product --
  the two socket pings, the proxy health probe, the provider-route gate -- tests
  only the RUNNING-NOW half. Nothing has ever tested the other half, on any
  release. A unit that does not come back after a restart is a structural
  control that is silently absent, on an install that looks correct.

  WHY EVERY WSL STEP RUNS IN THE INTERACTIVE SESSION
  --------------------------------------------------
  `az vm run-command` executes as NT AUTHORITY\SYSTEM and `wsl.exe` refuses
  LocalSystem by name (Wsl/WSL_E_LOCAL_SYSTEM_NOT_SUPPORTED). An installer
  dispatched that way takes the WRONG BRANCH -- setup.ps1 reads `wsl --status`
  exit -1, decides the kernel is absent, and every assertion about the
  succeeding path scores a false FAIL. So run-command is used ONLY to drop job
  files and read status, and this script executes inside the clawadmin session
  through validation/interim-v120-runner.ps1. Every stage asserts its own
  context FIRST, as a Require-Precondition, so a wrong context records VOID
  instead of a confident product verdict.

  STAGES, AND WHY THEY ARE IN THIS ORDER
  --------------------------------------
    Install    run the SHIPPED v1.4.5 installer, /VERYSILENT, digest-gated
    Pre        census of all eight units + the guard end-to-end checks, taken
               BEFORE anything is restarted. This is the baseline the
               post-reboot reading is compared against; without it, "the guard
               does not hold after a reboot" and "the guard never held" are the
               same reading.
    WslCycle   `wsl --shutdown`, let the distro come back, re-census. The
               systemd half of the question alone, Windows held constant.
    Post       after `az vm restart`. The measurement the job exists for.
    Inject     TASK 2. Four-way calibrated proof that the new read-backs catch a
               unit that did not enable and that the OLD code did not. Runs LAST
               so it cannot pollute the subject of Pre/WslCycle/Post.

  A PROBE IS CALIBRATED AGAINST A RIGGED INPUT; A RUN IS NOT. Every census
  registers, in the same run, a positive control that creates a throwaway unit
  and reads it back as `enabled`, and a negative control that reads a unit which
  does not exist. Without the first, "not enabled" and "the reader is broken"
  are the same reading; without the second, a reader that answered `enabled` to
  everything would pass. The controls run AFTER the census reads and clean up
  after themselves, so they cannot influence what they underwrite.
#>
param(
    [Parameter(Mandatory)]
    [ValidateSet('Install','Pre','WslCycle','Post','Inject')]
    [string]$Stage,
    [string]$Exe         = 'C:\cfv\v145-shipped.exe',
    [string]$ExpectedSha = '2fe7dad18c9eab8c005e8ee4bf9a25a6ca08bb761c11d9baf111e3eac0145e87',
    [string]$FixedQuarantineSrc = 'C:\cfv\install-quarantine.sh',
    [ValidateSet('grok','openai','claude','gemini','ollama','later')][string]$Provider = 'claude',
    [string]$Transcript  = '',
    [string]$ResultsJson = ''
)

$ErrorActionPreference = 'Continue'
. C:\cfv\interim-v120-wslchan.ps1
. C:\cfv\interim-v120-phaselib.ps1

if (-not $Transcript)  { $Transcript  = "C:\cfv\v146-$Stage-out.txt" }
if (-not $ResultsJson) { $ResultsJson = "C:\cfv\v146-$Stage-results.json" }

Start-Phase -Name "ClawFactory v1.4.5 systemd reboot persistence, stage=$Stage" `
    -Transcript $Transcript -Sentinel 'UNITPERSIST_COMPLETE'

function Finish($code) { W ''; W "UNITPERSIST_COMPLETE rc=$code"; exit $code }

function Val([string]$text, [string]$key) {
    if ($text -match "(?m)^$([regex]::Escape($key))=(.*)$") { return $Matches[1].Trim() }
    return '(not reported)'
}

function Rows([string]$text, [string]$prefix) {
    return @($text -split "`r?`n" | Where-Object { $_.Trim() -like "$prefix|*" } | ForEach-Object { $_.Trim() })
}

function ToInt($v) { $n = 0; if ([int]::TryParse("$v", [ref]$n)) { return $n } else { return -1 } }

# Write an arbitrary file into the distro over the same 9p channel the probe
# payloads use. Needed by the Inject stage, which must run the SHIPPED text of
# the fixed installer rather than a copy retyped into this probe.
function Copy-IntoDistro([string]$LocalPath, [string]$LinuxPath) {
    $lf = ([IO.File]::ReadAllText($LocalPath) -replace "`r`n", "`n") -replace "`r", "`n"
    $leaf = Split-Path $LinuxPath -Leaf
    $unc = "\\wsl$\Ubuntu\var\tmp\$leaf"
    [IO.File]::WriteAllText($unc, $lf, (New-Object Text.UTF8Encoding($false)))
    return "/var/tmp/$leaf"
}

# The eight units, held here as the probe's OWN list. Compared against what the
# box reports rather than derived from it -- an uncompared copy is a second
# stale list, not independence.
$UNITS = @(
    'clawfactory-allow-providers.timer',
    'clawfactory-egress-refresh.service',
    'clawfactory-fw.service',
    'clawfactory-proxy.service',
    'clawfactory-quarantine-gc.timer',
    'clawfactory-quarantine.service',
    'clawfactory-send-gc.timer',
    'clawfactory-send.service'
)

# THE EXPECTED STATE PER UNIT, RE-DERIVED FROM THE TREE RATHER THAN ASSUMED.
#
# The first version of this probe asserted that all eight should read `active`,
# on the stated grounds that "the two oneshots carry RemainAfterExit=yes". That
# sentence is FALSE about the tree and the Pre census caught it: two rows failed
# and neither was a product defect. The measurement being right does not make
# the expectation right.
#
#   unit                                enabled with   RemainAfterExit
#   ----------------------------------  -------------  ---------------
#   clawfactory-allow-providers.timer   --now          n/a   setup.ps1:2798
#   clawfactory-egress-refresh.service  plain enable   YES   install-read-fetch.sh:379 / :356
#   clawfactory-fw.service              plain enable   NO    setup.ps1:2212 / :2199
#   clawfactory-proxy.service           --now          n/a   install-chat-proxy.sh:87
#   clawfactory-quarantine-gc.timer     --now          n/a   install-quarantine.sh:141
#   clawfactory-quarantine.service      --now          n/a   install-quarantine.sh:140
#   clawfactory-send-gc.timer           --now          n/a   install-send.sh:191
#   clawfactory-send.service            --now          n/a   install-send.sh:190
#
# So BEFORE any restart the two plain-enabled units have never been started at
# all -- the firewall was applied by setup.ps1 running clawfactory-fw-apply.sh
# directly, not through the unit -- and both correctly read inactive with
# ActiveEnterTimestampMonotonic = 0.
#
# AFTER a restart they must differ, and this is the sharpest evidence the job
# has: a unit that read 0 before and reads non-zero after was started by systemd
# at boot and by nothing else.
#   egress-refresh  RemainAfterExit=yes -> stays ACTIVE
#   fw.service      no RemainAfterExit  -> runs, exits, returns to INACTIVE.
#                   Asserting `active` on it would manufacture a false FAIL, so
#                   it is asserted on Result=success AND ActiveEnter > 0 AND the
#                   nft table being present (row G3), which is the effect the
#                   unit exists to produce.
$EXPECT_ACTIVE_PRE = @{
    'clawfactory-allow-providers.timer'  = 'active'
    'clawfactory-egress-refresh.service' = 'inactive'
    'clawfactory-fw.service'             = 'inactive'
    'clawfactory-proxy.service'          = 'active'
    'clawfactory-quarantine-gc.timer'    = 'active'
    'clawfactory-quarantine.service'     = 'active'
    'clawfactory-send-gc.timer'          = 'active'
    'clawfactory-send.service'           = 'active'
}
$EXPECT_ACTIVE_POST = @{
    'clawfactory-allow-providers.timer'  = 'active'
    'clawfactory-egress-refresh.service' = 'active'
    'clawfactory-fw.service'             = 'inactive'
    'clawfactory-proxy.service'          = 'active'
    'clawfactory-quarantine-gc.timer'    = 'active'
    'clawfactory-quarantine.service'     = 'active'
    'clawfactory-send-gc.timer'          = 'active'
    'clawfactory-send.service'           = 'active'
}
# The units that must show they RAN at boot rather than merely being loaded.
$ONESHOTS = @('clawfactory-egress-refresh.service', 'clawfactory-fw.service')

# ---------------------------------------------------------------------------
# CONTEXT. Asserted before anything else, in every stage.
# ---------------------------------------------------------------------------
function Assert-Context {
    <# -NeedChannel is NOT a convenience switch. The Install stage runs on a box
       with NO DISTRO -- neither baseline image carries one, and the installer is
       what imports it -- so \\wsl$\Ubuntu does not exist and the channel
       self-test cannot pass there. Measured, not assumed: the first attempt at
       this run asserted the channel in the Install stage and VOIDed with
       "The specified network name is no longer available" before the installer
       was launched. A precondition that cannot hold on the box it runs on is a
       broken instrument, and the runner correctly refused to report anything
       through it rather than installing and calling the result a product
       verdict. The channel is required by every stage that USES it, and by no
       other. #>
    param([switch]$NeedChannel)
    $id   = [Security.Principal.WindowsIdentity]::GetCurrent()
    $prin = New-Object Security.Principal.WindowsPrincipal($id)
    $elev = $prin.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    $isSystem = ($id.Name -eq 'NT AUTHORITY\SYSTEM')
    W "context: user=$($id.Name) elevated=$elev interactive=$([Environment]::UserInteractive)"
    $ok = Require-Precondition -Id "UP.CTX.$Stage" -Name 'running in the interactive elevated session, not as SYSTEM' `
        -Met ($elev -and (-not $isSystem) -and [Environment]::UserInteractive) `
        -Reason "wsl.exe refuses NT AUTHORITY\SYSTEM by name, so a WSL measurement taken from run-command reads -1 from every wsl call and scores a false product FAIL. user=$($id.Name), elevated=$elev, interactive=$([Environment]::UserInteractive)"
    if (-not $ok) { return $false }
    if (-not $NeedChannel) { return $true }
    # The channel itself, subject and control in one run, before any measurement.
    # NOTE .Ok. Test-WslChannel returns a HASHTABLE, and a non-null hashtable is
    # truthy, so `-Met $chan` would be a control that can never fail -- which is
    # the exact defect the whole phaselib exists to prevent.
    $chan = Test-WslChannel
    W "channel self-test: $(($chan.Detail -split "`r?`n" | Where-Object { $_ -match '=' }) -join '  ')"
    return (Require-Precondition -Id "UP.CHAN.$Stage" -Name 'the WSL file channel discriminates pass from fail' `
        -Met $chan.Ok `
        -Reason 'an inline nested wsl -- bash -c channel has fabricated passes on this project before: dropped echo lines, a zero exit code for a command that had just failed, and an empty variable that turned grep -q into a match-everything. The channel self-test runs a subject that must succeed and a control that must fail.')
}

# ---------------------------------------------------------------------------
# The census body. Reads only; the controls are a SEPARATE dispatch that runs
# afterwards, so nothing a control creates can appear in the census it
# underwrites.
# ---------------------------------------------------------------------------
$CENSUS = @'
set +e
echo "SYSTEMD_PID1=$(ps -p 1 -o comm= 2>/dev/null)"
echo "UPTIME_S=$(awk '{print int($1)}' /proc/uptime 2>/dev/null)"
echo "SYSTEMD_STATE=$(systemctl is-system-running 2>&1 | head -1)"
for u in clawfactory-allow-providers.timer clawfactory-egress-refresh.service clawfactory-fw.service clawfactory-proxy.service clawfactory-quarantine-gc.timer clawfactory-quarantine.service clawfactory-send-gc.timer clawfactory-send.service; do
  en="$(systemctl is-enabled "$u" 2>&1 | head -1)"
  ac="$(systemctl is-active "$u" 2>&1 | head -1)"
  # Monotonic microseconds since boot. A unit systemd started at boot has a
  # SMALL value; one started by hand minutes later does not. This is what turns
  # "it is running" into "it came back on its own".
  ts="$(systemctl show -p ActiveEnterTimestampMonotonic --value "$u" 2>/dev/null)"
  # Result and ExecMainStatus are what turn "inactive" into a readable answer
  # for a Type=oneshot with no RemainAfterExit: such a unit is inactive BOTH
  # when it ran and succeeded and when it never ran at all, and is-active cannot
  # tell those apart. ActiveEnterTimestampMonotonic separates them (0 = never
  # entered active this boot) and Result says how it ended.
  rs="$(systemctl show -p Result --value "$u" 2>/dev/null)"
  ex="$(systemctl show -p ExecMainStatus --value "$u" 2>/dev/null)"
  # InactiveExitTimestampMonotonic -- THE FIELD THAT ACTUALLY ANSWERS "did it
  # run". ActiveEnterTimestampMonotonic is structurally ALWAYS 0 for a
  # Type=oneshot with no RemainAfterExit, because such a unit goes
  # inactive -> activating -> inactive and never enters `active` at all. Reading
  # ActiveEnter on clawfactory-fw.service therefore reports "never ran" for a
  # unit whose own journal says it started and finished five seconds after boot.
  # Measured on cfv-191: it produced a FAIL that was one step from being written
  # up as a ship-blocking finding about the egress firewall.
  ie="$(systemctl show -p InactiveExitTimestampMonotonic --value "$u" 2>/dev/null)"
  echo "UNIT|$u|$en|$ac|$ts|$rs|$ex|$ie"
done
# BOOT IDENTITY. Every stage takes its census and its guard checks in separate
# dispatches, and WSL idle-terminates the distro between dispatches -- observed
# three times on cfv-191 inside twenty minutes. A census from one boot presented
# beside guard results from the next is two measurements reported as one, so
# both halves stamp this and the stage asserts they match.
echo "BOOT_ID=$(cat /proc/sys/kernel/random/boot_id 2>/dev/null)"
echo "WANTS_MULTIUSER=$(ls -1 /etc/systemd/system/multi-user.target.wants/clawfactory-* 2>/dev/null | wc -l | tr -d ' ')"
echo "WANTS_TIMERS=$(ls -1 /etc/systemd/system/timers.target.wants/clawfactory-* 2>/dev/null | wc -l | tr -d ' ')"
echo "UNITFILES_PRESENT=$(ls -1 /etc/systemd/system/clawfactory-*.service /etc/systemd/system/clawfactory-*.timer 2>/dev/null | wc -l | tr -d ' ')"
echo "SOCK_QUARANTINE=$( [ -S /run/clawfactory/quarantine.sock ] && echo present || echo absent )"
echo "SOCK_SEND=$( [ -S /run/clawfactory/send.sock ] && echo present || echo absent )"
echo "SOCK_SENDADMIN=$(stat -c '%U:%G %a' /run/clawfactory/send-admin.sock 2>/dev/null || echo absent)"
echo "NFT_TABLE=$(nft list table inet clawfactory >/dev/null 2>&1 && echo present || echo absent)"
echo "NFT_ADDRESSES=$(nft list table inet clawfactory 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | sort -u | wc -l | tr -d ' ')"
echo "ALLOWED_IPS_FILE=$(cat /etc/clawfactory/allowed-ips.txt 2>/dev/null | grep -cE '[0-9]' | tr -d ' ')"
echo "READER_CTL=$( [ -d /etc/systemd/system ] && echo present || echo absent )"
'@

# THE CONTROLS. Both halves, one dispatch, after the census.
#   POSITIVE: a throwaway unit is created, enabled, and must read back
#             'enabled'. Without this, "not enabled" and "the reader is broken"
#             are indistinguishable.
#   NEGATIVE: a unit that does not exist must NOT read back 'enabled'. Without
#             this, a reader that answered 'enabled' to everything would pass.
# The scratch unit is removed in the same dispatch and the removal is asserted,
# so the box under test is left as it was found.
$CONTROLS = @'
set +e
cat > /etc/systemd/system/cfv146-ctl.service <<UNIT
[Unit]
Description=cfv146 read-back calibration unit
[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/true
[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload 2>/dev/null
systemctl enable cfv146-ctl.service >/dev/null 2>&1
echo "CTL_POS_ISENABLED=$(systemctl is-enabled cfv146-ctl.service 2>&1 | head -1)"
echo "CTL_NEG_ISENABLED=$(systemctl is-enabled cfv146-absent-on-purpose.service 2>&1 | head -1)"
systemctl disable cfv146-ctl.service >/dev/null 2>&1
rm -f /etc/systemd/system/cfv146-ctl.service /etc/systemd/system/multi-user.target.wants/cfv146-ctl.service
systemctl daemon-reload 2>/dev/null
echo "CTL_CLEANUP_LEFT=$(ls -1d /etc/systemd/system/cfv146-ctl.service /etc/systemd/system/multi-user.target.wants/cfv146-ctl.service 2>/dev/null | wc -l | tr -d ' ')"
'@

# ---------------------------------------------------------------------------
# The guard end-to-end checks. Cheapest per guard; each names what it proves and
# what it does not. Expects TAG to be set by the caller's prologue.
# ---------------------------------------------------------------------------
$GUARDS = @'
set +e
echo "BOOT_ID=$(cat /proc/sys/kernel/random/boot_id 2>/dev/null)"
# WAIT FOR THE GATEWAY, ON STATE, NEVER ON A SLEEP.
#
# The OpenClaw gateway takes roughly fifty seconds from launch to
# "[gateway] ready" -- measured on cfv-191: started 18:33:24, ready 18:33:53.
# Until it binds, the proxy is up on 8787 and answers 502, and nothing answers
# on 8788. Every reading taken inside that window looks exactly like a gateway
# that failed to come back, and on the first attempt at this run it produced a
# FAIL on the proxy row that was purely a cold-start transient. So poll, record
# how long it took, and let the row read the settled state.
GW_WAIT=0
while [ $GW_WAIT -lt 180 ]; do
  code="$(runuser -u clawuser -- curl -s -o /dev/null -w '%{http_code}' --max-time 5 http://127.0.0.1:8787/status 2>/dev/null)"
  [ "$code" = "200" ] && break
  GW_WAIT=$((GW_WAIT+5)); sleep 5
done
echo "GW_READY_AFTER_S=$GW_WAIT"

# ---- GUARD 1: recoverable delete ------------------------------------------
# THE PATH MATTERS. quarantine.json's quarantineRoots is ["/workspaces"], and a
# probe pointed at /var/tmp or at the agent's home would be OUT of scope, where
# the broker correctly declares quarantined:false and the wrapper performs a
# real delete. A pass taken there would be a pass for the wrong reason -- the
# Guard 4 probe that answered YES on ext4 and NO on the real mount is the
# recorded precedent.
echo "G1_ROOTS=$(tr -d ' \"' < /etc/clawfactory/quarantine.json | sed -n 's/.*quarantineRoots:\[\([^]]*\)\].*/\1/p')"
STORE="$(tr -d ' \"' < /etc/clawfactory/quarantine.json | sed -n 's/.*store:\([^,}]*\).*/\1/p')"
echo "G1_STORE=$STORE"
echo "G1_STORE_MODE=$(stat -c '%U:%G %a' "$STORE" 2>/dev/null || echo absent)"
mkdir -p /workspaces/cfv146
chown clawuser:clawuser /workspaces/cfv146
F="/workspaces/cfv146/g1-$TAG.txt"
rm -rf "$F"
runuser -u clawuser -- /usr/bin/tee "$F" > /dev/null <<CANARY
cfv146-canary-$TAG
CANARY
echo "G1_CREATED=$( [ -f "$F" ] && echo yes || echo no )"
echo "G1_OWNER=$(stat -c '%U' "$F" 2>/dev/null || echo absent)"
# The wrapper is /usr/bin/rm after the dpkg-divert, so any rm reaches it. Run it
# through a login shell as clawuser, which is the path the agent's exec tool has.
OUT="$(runuser -u clawuser -- bash -lc "rm '$F'" 2>&1)"; RC=$?
echo "G1_RM_RC=$RC"
echo "G1_RM_OUT=$(printf '%s' "$OUT" | tr '\n' ' ' | cut -c1-200)"
echo "G1_GONE_FROM_WORKSPACE=$( [ -e "$F" ] && echo no || echo yes )"
echo "G1_IN_STORE=$(find "$STORE" -type f -name "g1-$TAG.txt" 2>/dev/null | wc -l | tr -d ' ')"
if runuser -u clawuser -- ls "$STORE" >/dev/null 2>&1; then echo "G1_AGENT_CAN_LIST=yes"; else echo "G1_AGENT_CAN_LIST=no"; fi
if head -1 /usr/bin/rm 2>/dev/null | grep -qi node; then echo "G1_WRAPPER_IS_NODE=yes"; else echo "G1_WRAPPER_IS_NODE=no"; fi
# CONTROL for G1: root must still get a WORKING rm. If the wrapper had broken
# every delete, "the file was held" and "delete is broken" would look alike.
T="$(mktemp /var/tmp/cfv146-rootrm.XXXXXX)"
/usr/bin/rm -f "$T" 2>/dev/null
echo "G1_CTL_ROOT_RM_WORKS=$( [ -e "$T" ] && echo no || echo yes )"

# ---- GUARD 2: no send path at uid 1000 ------------------------------------
# Cheapest sufficient check, and it needs NO SMTP credential. The request
# channel must answer ping, and must REFUSE an admin op BY NAME -- that refusal
# is the boundary itself, and a broker that came back with an unloaded config
# could not produce it. An actual approval round-trip needs the SMTP credential
# and would record VOID without it, which is why it is not the check used here.
cat > /var/tmp/cfv146-g2.js <<'JS'
const net = require("node:net");
const [sock, payload] = [process.argv[2], process.argv[3]];
const s = net.createConnection(sock);
let b = "";
s.setEncoding("utf8");
s.on("connect", () => { if (payload) { s.write(payload + "\n"); } else { process.stdout.write("CONNECTED"); process.exit(0); } });
s.on("data", d => { b += d; if (b.includes("\n")) { process.stdout.write(b.split("\n")[0]); process.exit(0); } });
s.on("error", e => { process.stdout.write("DENIED:" + e.code); process.exit(0); });
setTimeout(() => { process.stdout.write("TIMEOUT"); process.exit(0); }, 8000);
JS
chmod 644 /var/tmp/cfv146-g2.js
NODEBIN="$(command -v node)"
echo "G2_PING=$(runuser -u clawuser -- "$NODEBIN" /var/tmp/cfv146-g2.js /run/clawfactory/send.sock '{"op":"ping"}' 2>&1 | tr '\n' ' ' | cut -c1-200)"
echo "G2_ADMINOP_ON_REQUEST_CHANNEL=$(runuser -u clawuser -- "$NODEBIN" /var/tmp/cfv146-g2.js /run/clawfactory/send.sock '{"op":"approve","requestId":"cfv146"}' 2>&1 | tr '\n' ' ' | cut -c1-240)"
echo "G2_AGENT_ON_ADMIN_SOCKET=$(runuser -u clawuser -- "$NODEBIN" /var/tmp/cfv146-g2.js /run/clawfactory/send-admin.sock 2>&1 | tr '\n' ' ' | cut -c1-120)"
echo "G2_ADMIN_SOCK_MODE=$(stat -c '%U:%G %a' /run/clawfactory/send-admin.sock 2>/dev/null || echo absent)"
echo "G2_SENDD_USER=$(ps -o user= -p "$(systemctl show -p MainPID --value clawfactory-send.service 2>/dev/null)" 2>/dev/null | tr -d ' ')"
# CONTROL for G2: the same client, same code path, against a socket that is NOT
# there. It must report DENIED rather than a reply, or "the agent was refused"
# and "the client is broken" are the same reading.
echo "G2_CTL_ABSENT_SOCKET=$(runuser -u clawuser -- "$NODEBIN" /var/tmp/cfv146-g2.js /run/clawfactory/cfv146-not-a-socket 2>&1 | tr '\n' ' ' | cut -c1-120)"

# ---- GUARD 3 / the firewall: the one that fails SILENTLY -------------------
# Six attempts as uid 1000 to an address in no allowlisted set, and a root
# control to the SAME address in the same run. Without the root half, "the agent
# is denied" and "this box has no network" are the same reading.
b=0; for i in 1 2 3 4 5 6; do
  if runuser -u clawuser -- timeout 6 bash -c 'exec 3<>/dev/tcp/1.1.1.1/443' 2>/dev/null; then :; else b=$((b+1)); fi
done
echo "G3_AGENT_BLOCKED=$b of 6"
r=0; for i in 1 2 3; do
  if timeout 6 bash -c 'exec 3<>/dev/tcp/1.1.1.1/443' 2>/dev/null; then r=$((r+1)); fi
done
echo "G3_ROOT_REACHED=$r of 3"
echo "G3_NFT_TABLE=$(nft list table inet clawfactory >/dev/null 2>&1 && echo present || echo absent)"
echo "G3_NFT_TERMINAL_DROP=$(nft list table inet clawfactory 2>/dev/null | grep -cE 'drop$|policy drop')"

# ---- The gating proxy ------------------------------------------------------
# As CLAWUSER, because that is the reachability ClawChat actually gets. The
# paired half is the private port, which the same account must NOT reach.
echo "PROXY_8787_AS_AGENT=$(runuser -u clawuser -- curl -s -o /dev/null -w '%{http_code}' --max-time 10 http://127.0.0.1:8787/status 2>/dev/null)"
if runuser -u clawuser -- timeout 5 bash -c 'exec 3<>/dev/tcp/127.0.0.1/8788' 2>/dev/null; then
  echo "PROXY_8788_AS_AGENT=REACHED"
else
  echo "PROXY_8788_AS_AGENT=denied"
fi
echo "PROXY_8788_AS_ROOT=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 http://127.0.0.1:8788/status 2>/dev/null)"
echo "READER_CTL=$( [ -d /run/clawfactory ] && echo present || echo absent )"
'@

function Invoke-Census([string]$tag) {
    $c = Invoke-WslFile -Tag "v146cen$tag" -User 'root' -Body $CENSUS
    foreach ($ln in @($c.Out -split "`r?`n" | Where-Object { $_ -match '=|\|' })) { W "   CEN> $($ln.Trim())" }
    return $c.Out
}

function Invoke-Controls([string]$tag) {
    $c = Invoke-WslFile -Tag "v146ctl$tag" -User 'root' -Body $CONTROLS
    foreach ($ln in @($c.Out -split "`r?`n" | Where-Object { $_ -match '=' })) { W "   CTL> $($ln.Trim())" }
    return $c.Out
}

function Invoke-Guards([string]$tag) {
    # THE TAG MUST BE UNIQUE PER RUN, not per phase. G1 asserts that exactly ONE
    # copy of its canary reached the quarantine store, and the store is
    # cumulative -- a second run of the same phase would find two and score a
    # FAIL that says nothing about the product. "A second run over a box that
    # has already been run is not the same measurement as the first."
    $tag = "$tag-$PID"
    $body = "TAG=$tag`n" + $GUARDS
    $c = Invoke-WslFile -Tag "v146grd$tag" -User 'root' -Body $body
    foreach ($ln in @($c.Out -split "`r?`n" | Where-Object { $_ -match '=' })) { W "   GRD> $($ln.Trim())" }
    return $c.Out
}

function Record-Census([string]$text, [string]$ctl, [string]$phase) {
    # Controls first. Everything below is underwritten by them.
    Register-Control -Id "UP.$phase.CTL.POS" -Name 'the is-enabled reader can produce a known-correct ENABLED answer on this box, right now' `
        -Fired ((Val $ctl 'CTL_POS_ISENABLED') -eq 'enabled') `
        -Evidence "a throwaway unit was created and enabled in the same dispatch and read back '$(Val $ctl 'CTL_POS_ISENABLED')' (must be 'enabled'). Without this, a census reading 'not enabled' for the product's units and a census taken through a broken reader are the same transcript." | Out-Null
    Register-Control -Id "UP.$phase.CTL.NEG" -Name 'the is-enabled reader can also say NO' `
        -Fired ((Val $ctl 'CTL_NEG_ISENABLED') -ne 'enabled') `
        -Evidence "a unit that does not exist read back '$(Val $ctl 'CTL_NEG_ISENABLED')' (must NOT be 'enabled'). A reader that answered 'enabled' to everything would pass the positive control alone." | Out-Null
    Record "UP.$phase.CTL.CLEAN" 'the calibration left no trace of itself' `
        $(if ((Val $ctl 'CTL_CLEANUP_LEFT') -eq '0') { 'PASS' } else { 'FAIL' }) `
        "scratch unit files and wants entries left = $(Val $ctl 'CTL_CLEANUP_LEFT'). Must be 0, or the box under test is no longer the box that was measured."

    $rows = Rows $text 'UNIT'
    $reported = @($rows | ForEach-Object { ($_ -split '\|')[1] })
    # SET comparison, not an ordered-join comparison. The first version joined
    # both lists after Sort-Object and failed on the Pre census because
    # `clawfactory-quarantine-gc.timer` and `clawfactory-quarantine.service`
    # collate differently under a culture-aware sort than the hand-written list
    # assumed. The two lists held the SAME EIGHT NAMES. A row that fails on
    # ordering while the sets agree is a probe defect reported as a product
    # finding, which is worse than no row at all.
    $missing = @($UNITS | Where-Object { $reported -notcontains $_ })
    $extra   = @($reported | Where-Object { $UNITS -notcontains $_ })
    # Compare-Independent tests STRING EQUALITY. Handing it two differently
    # worded summaries of the same fact makes a row that can never pass, which
    # is what the first two Pre runs did: it reported "8 units, 0 unaccounted
    # for" against "8 units, 0 missing, 0 unexpected" and called that a
    # disagreement. Both sides must therefore be rendered by the SAME rule.
    #
    # ORDINAL sort, not Sort-Object. Sort-Object is culture-aware and orders
    # `clawfactory-quarantine-gc.timer` and `clawfactory-quarantine.service`
    # differently from a byte comparison, which is what produced the very first
    # false disagreement on this row.
    $mineSorted = [string[]]$UNITS;     [Array]::Sort($mineSorted, [StringComparer]::Ordinal)
    $repSorted  = [string[]]$reported;  [Array]::Sort($repSorted,  [StringComparer]::Ordinal)
    Compare-Independent -Id "UP.$phase.LIST" -Name 'the eight units this probe holds, against the set the box reported' `
        -Mine ($mineSorted -join ',') -Reported ($repSorted -join ',') `
        -MineLabel 'the probe' -ReportedLabel 'the box' | Out-Null
    Record "UP.$phase.LIST2" 'set difference between the two lists, named rather than counted' `
        $(if ($missing.Count -eq 0 -and $extra.Count -eq 0) { 'PASS' } else { 'FAIL' }) `
        "in the probe but not reported by the box: $(if ($missing.Count) { $missing -join '; ' } else { 'none' }). Reported by the box but not in the probe: $(if ($extra.Count) { $extra -join '; ' } else { 'none' }). A unit the product installs that this probe does not know about is the more dangerous half, because the probe would report full coverage while never having looked at it."

    $expect = if ($phase -eq 'PRE') { $EXPECT_ACTIVE_PRE } else { $EXPECT_ACTIVE_POST }

    W ''
    W "  unit                                    is-enabled   is-active  expected   ActiveEnter(us)  Result"
    foreach ($r in $rows) {
        $p = $r -split '\|'
        W ("  {0,-38}  {1,-11}  {2,-9}  {3,-9}  {4,-15}  {5}" -f $p[1], $p[2], $p[3], $expect[$p[1]], $p[4], $p[5])
    }
    W ''

    $notEnabled = @($rows | Where-Object { ($_ -split '\|')[2] -ne 'enabled' })
    $wrongState = @($rows | Where-Object { ($_ -split '\|')[3] -ne $expect[($_ -split '\|')[1]] })

    Record "UP.$phase.1" 'all eight ClawFactory units read back ENABLED' `
        $(if ($rows.Count -eq 8 -and $notEnabled.Count -eq 0) { 'PASS' } else { 'FAIL' }) `
        ("rows reported = $($rows.Count) of 8; not enabled = $($notEnabled.Count)" + $(if ($notEnabled.Count) { " [$(($notEnabled | ForEach-Object { ($_ -split '\|')[1] + '=' + ($_ -split '\|')[2] }) -join '; ')]" } else { '' }))

    Record "UP.$phase.2" 'every unit is in the state its own unit file says it should be in' `
        $(if ($rows.Count -eq 8 -and $wrongState.Count -eq 0) { 'PASS' } else { 'FAIL' }) `
        ("units not in their expected state = $($wrongState.Count)" + $(if ($wrongState.Count) { " [$(($wrongState | ForEach-Object { ($_ -split '\|')[1] + ' is ' + ($_ -split '\|')[3] + ', expected ' + $expect[($_ -split '\|')[1]] }) -join '; ')]" } else { '' }) + ". The expectation is per-unit and derived from the tree: six are enabled with --now and must be active; clawfactory-egress-refresh.service and clawfactory-fw.service are enabled WITHOUT --now, so before any restart neither has ever been started and inactive is correct. After a restart egress-refresh must be active (RemainAfterExit=yes) while fw.service correctly returns to inactive (it has none), which is why fw.service is judged on rows $phase.6 and G3 instead.")

    # The oneshots: did they RUN this boot, and did they succeed? is-active
    # cannot answer that for a unit with no RemainAfterExit -- inactive means
    # both "ran and finished" and "never ran".
    $oneshotRows = @($rows | Where-Object { $ONESHOTS -contains ($_ -split '\|')[1] })
    # InactiveExit, NOT ActiveEnter. See the census comment: ActiveEnter is
    # structurally always 0 for a oneshot with no RemainAfterExit, so reading it
    # reports "never ran" for a unit whose journal says otherwise.
    $ranOk = @($oneshotRows | Where-Object {
        $p = $_ -split '\|'
        ((ToInt $p[7]) -gt 0) -and ($p[5] -eq 'success')
    })
    Record "UP.$phase.6" 'the two boot-time oneshots: did they RUN this boot, and did they succeed?' `
        $(if ($phase -eq 'PRE') { 'INFO' } elseif ($ranOk.Count -eq 2) { 'PASS' } else { 'FAIL' }) `
        ("$($ranOk.Count) of $($oneshotRows.Count) left inactive (i.e. were started) with Result=success: " + (($oneshotRows | ForEach-Object { $p = $_ -split '\|'; "$($p[1]) InactiveExit=$($p[7]) ActiveEnter=$($p[4]) Result='$($p[5])' ExecMainStatus='$($p[6])'" }) -join '; ') + ". Judged on InactiveExitTimestampMonotonic because ActiveEnter is always 0 for a Type=oneshot with no RemainAfterExit -- clawfactory-fw.service is exactly that, and reading ActiveEnter on it reports 'never ran' for a unit whose own journal records it starting and finishing five seconds after boot. On the PRE reading this is INFO and both are expected to be 0, because neither is enabled with --now and neither has ever been started, which is what makes the post-restart reading unambiguous.")

    Record "UP.$phase.3" 'the wants symlinks on disk, which is what enablement IS' 'INFO' `
        "multi-user.target.wants/clawfactory-* = $(Val $text 'WANTS_MULTIUSER'), timers.target.wants/clawfactory-* = $(Val $text 'WANTS_TIMERS'), unit files present = $(Val $text 'UNITFILES_PRESENT'). is-enabled reads these; recorded separately so a disagreement between the two is visible rather than averaged away."

    Record "UP.$phase.4" 'distro state at the moment of measurement' 'INFO' `
        "pid1=$(Val $text 'SYSTEMD_PID1'), is-system-running='$(Val $text 'SYSTEMD_STATE')', uptime=$(Val $text 'UPTIME_S')s. Sockets: quarantine=$(Val $text 'SOCK_QUARANTINE'), send=$(Val $text 'SOCK_SEND'), send-admin=$(Val $text 'SOCK_SENDADMIN'). nft table=$(Val $text 'NFT_TABLE') carrying $(Val $text 'NFT_ADDRESSES') distinct addresses; allowed-ips.txt holds $(Val $text 'ALLOWED_IPS_FILE') address lines."
}

function Record-Guards([string]$g, [string]$phase) {
    Register-Control -Id "UP.$phase.G.CTL.NET" -Name 'the reachability instrument can reach the network at all' `
        -Fired ((Val $g 'G3_ROOT_REACHED') -match '^[1-3] of 3') `
        -Evidence "root reached 1.1.1.1:443 on $(Val $g 'G3_ROOT_REACHED') attempts. Without this, 'the agent is denied' and 'the box has no network' are the same reading." | Out-Null
    Register-Control -Id "UP.$phase.G.CTL.RM" -Name 'delete still works for root, so a held file is not just a broken rm' `
        -Fired ((Val $g 'G1_CTL_ROOT_RM_WORKS') -eq 'yes') `
        -Evidence "root removed its own temp file: $(Val $g 'G1_CTL_ROOT_RM_WORKS'). If the wrapper had broken every delete, 'the file was held' and 'delete is broken' would look identical." | Out-Null
    Register-Control -Id "UP.$phase.G.CTL.SOCK" -Name 'the socket client can report a refusal it did not receive a reply to' `
        -Fired ((Val $g 'G2_CTL_ABSENT_SOCKET') -match '^DENIED') `
        -Evidence "the same client against a socket that does not exist said '$(Val $g 'G2_CTL_ABSENT_SOCKET')'. Without this, 'the agent was refused on the admin socket' and 'the client never worked' are the same reading." | Out-Null

    Record "UP.$phase.G1" 'GUARD 1 HOLDS: an agent delete inside a quarantine root is HELD, not destroyed' `
        $(if ((Val $g 'G1_CREATED') -eq 'yes' -and (Val $g 'G1_GONE_FROM_WORKSPACE') -eq 'yes' -and (Val $g 'G1_IN_STORE') -eq '1' -and (Val $g 'G1_AGENT_CAN_LIST') -eq 'no') { 'PASS' } else { 'FAIL' }) `
        "roots=$(Val $g 'G1_ROOTS'); canary created=$(Val $g 'G1_CREATED') owned by $(Val $g 'G1_OWNER'); rm rc=$(Val $g 'G1_RM_RC') out='$(Val $g 'G1_RM_OUT')'; gone from the workspace=$(Val $g 'G1_GONE_FROM_WORKSPACE'); copies in the root-owned store=$(Val $g 'G1_IN_STORE'); store=$(Val $g 'G1_STORE') mode $(Val $g 'G1_STORE_MODE'); agent can list the store=$(Val $g 'G1_AGENT_CAN_LIST'); /usr/bin/rm is the node wrapper=$(Val $g 'G1_WRAPPER_IS_NODE'). PROVES: the dpkg-divert survived, the wrapper is still what the agent's shell resolves rm to, the broker answered, and the payload sits where uid 1000 cannot read it. DOES NOT PROVE the advisory half -- /bin/rm, unlink, find -delete and fs.rmSync were never covered and are not covered here."

    Record "UP.$phase.G2" 'GUARD 2 HOLDS: the request channel answers, and refuses an admin op BY NAME' `
        $(if ((Val $g 'G2_PING') -match 'pong' -and (Val $g 'G2_ADMINOP_ON_REQUEST_CHANNEL') -match 'EPERM' -and (Val $g 'G2_AGENT_ON_ADMIN_SOCKET') -match '^DENIED') { 'PASS' } else { 'FAIL' }) `
        "ping='$(Val $g 'G2_PING')'; approve-on-the-request-channel='$(Val $g 'G2_ADMINOP_ON_REQUEST_CHANNEL')' (must carry EPERM); agent on send-admin.sock='$(Val $g 'G2_AGENT_ON_ADMIN_SOCKET')' (must be DENIED); admin socket=$(Val $g 'G2_ADMIN_SOCK_MODE'); the broker runs as $(Val $g 'G2_SENDD_USER'). PROVES: the broker reloaded with its config and the request/admin split is still enforced at the socket, by a check that needs no SMTP credential. DOES NOT PROVE a full approval round-trip, which needs the credential and would record VOID without it rather than a verdict."

    Record "UP.$phase.G3" 'THE FIREWALL HOLDS: uid 1000 has no route to a non-allowlisted address' `
        $(if ((Val $g 'G3_AGENT_BLOCKED') -eq '6 of 6' -and (Val $g 'G3_NFT_TABLE') -eq 'present') { 'PASS' } else { 'FAIL' }) `
        "the agent was blocked on $(Val $g 'G3_AGENT_BLOCKED') attempts while root reached the same address on $(Val $g 'G3_ROOT_REACHED'); nft table=$(Val $g 'G3_NFT_TABLE') with $(Val $g 'G3_NFT_TERMINAL_DROP') terminal-drop line(s). THIS IS THE ROW THE WHOLE JOB TURNS ON: nft rules are kernel state, so after a restart this can only be true if clawfactory-fw.service came back and replayed the persisted list."

    Record "UP.$phase.G4" 'THE GATING PROXY HOLDS: 8787 answers the agent, 8788 does not' `
        $(if ((Val $g 'PROXY_8787_AS_AGENT') -eq '200' -and (Val $g 'PROXY_8788_AS_AGENT') -eq 'denied') { 'PASS' } else { 'FAIL' }) `
        "as clawuser: 127.0.0.1:8787/status -> $(Val $g 'PROXY_8787_AS_AGENT') (must be 200), 127.0.0.1:8788 -> $(Val $g 'PROXY_8788_AS_AGENT') (must be denied). As root, 8788/status -> $(Val $g 'PROXY_8788_AS_ROOT'), which shows the private gateway is alive and that the agent's denial is the firewall rather than a dead service. The gateway took $(Val $g 'GW_READY_AFTER_S')s to answer 200 after this distro came up; measured on cfv-191 it needs about fifty seconds from launch to '[gateway] ready', and every reading taken inside that window shows 502 on 8787 and nothing on 8788 -- which is indistinguishable from a gateway that never came back, and produced exactly that false FAIL on the first attempt at this run."
}

# ===========================================================================
if ($Stage -eq 'Install') {
    if (-not (Assert-Context)) { Complete-Phase -ResultsJson $ResultsJson -MarkerPrefix 'UP'; Finish 4 }

    Section '1. The artefact, identified by digest and not by filename'
    if (-not (Test-Path $Exe)) {
        Record 'UP.I0' 'the artefact is on the box' 'FAIL' "missing at $Exe"
        Complete-Phase -ResultsJson $ResultsJson -MarkerPrefix 'UP'; Finish 2
    }
    $h = (Get-FileHash -Algorithm SHA256 -LiteralPath $Exe).Hash.ToLower()
    W "on-box artefact sha256   = $h"
    W "expected published v1.4.5 = $ExpectedSha"
    $armed = Require-Precondition -Id 'UP.I.PRE' -Name 'the bytes on the box are the published v1.4.5' `
        -Met ($h -eq $ExpectedSha) `
        -Reason "measuring reboot persistence against the wrong build would answer the question fluently and wrongly. on-box=$h expected=$ExpectedSha"
    if (-not $armed) { Complete-Phase -ResultsJson $ResultsJson -MarkerPrefix 'UP'; Finish 4 }

    Section '2. Install'
    Remove-Item -LiteralPath 'C:\ProgramData\ClawFactory\install-result.txt' -Force -ErrorAction SilentlyContinue
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $p = Start-Process -FilePath $Exe -ArgumentList '/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART','/LOG=C:\cfv\v146-inno.log',"/PROVIDER=$Provider" -PassThru -Wait
    $sw.Stop()
    W "installer exit code = $($p.ExitCode), elapsed $([int]$sw.Elapsed.TotalMinutes) min ($([int]$sw.Elapsed.TotalSeconds)s)"

    $resultFile = 'C:\ProgramData\ClawFactory\install-result.txt'
    $verdict = if (Test-Path $resultFile) { (Get-Content $resultFile -Raw).Trim() } else { '(install-result.txt ABSENT)' }
    W "install-result.txt: $verdict"
    $logPath = 'C:\ProgramData\ClawFactory\install.log'
    $log = if (Test-Path $logPath) { Get-Content $logPath -Raw } else { '' }
    W "install.log length: $($log.Length) chars"
    Assert-Searchable -Id 'UP.I.CTL.LOG' -Name 'the install log' `
        -PositiveMarkerFound ($log -match 'Step 15') `
        -MarkerDescription 'a Step 15 guard-install banner, proving the install reached the steps that create the units and that this log is readable at all' | Out-Null

    Record 'UP.I1' 'the install completed and says so itself' `
        $(if ($verdict -match 'success') { 'PASS' } else { 'FAIL' }) `
        "install-result.txt='$verdict', Inno exit=$($p.ExitCode). setup.ps1's own verdict is the authority here; the Inno exit code is not, because the .iss raises no exception on setup.ps1's exit."
    foreach ($ln in @($log -split "`r?`n" | Select-Object -Last 40)) { W "   LOG> $ln" }

    Complete-Phase -ResultsJson $ResultsJson -MarkerPrefix 'UP'
    Finish 0
}

# ===========================================================================
if ($Stage -eq 'Pre' -or $Stage -eq 'WslCycle' -or $Stage -eq 'Post') {
    if (-not (Assert-Context -NeedChannel)) { Complete-Phase -ResultsJson $ResultsJson -MarkerPrefix 'UP'; Finish 4 }

    if ($Stage -eq 'WslCycle') {
        Section '0. Shut the distro down, then let it come back on its own'
        & wsl.exe --shutdown 2>&1 | ForEach-Object { W "   WSL> $_" }
        W 'distro is down. The next command that touches it starts it, which is how a user reaches it too.'
        # Wait on STATE, never on a sleep. `activating` is neither up nor failed,
        # and a fixed sleep that lands on it produces a false negative about the
        # thing under test.
        $deadline = (Get-Date).AddMinutes(5)
        do {
            $s = (Invoke-WslFile -Tag 'v146wait' -User 'root' -Body 'systemctl is-system-running 2>&1 | head -1').Out
            W "   is-system-running: $($s.Trim())"
            if ($s -match 'running|degraded') { break }
        } while ((Get-Date) -lt $deadline)
    }

    $phase = switch ($Stage) { 'Pre' { 'PRE' } 'WslCycle' { 'WSL' } 'Post' { 'POST' } }

    Section "1. Census of the eight units ($Stage)"
    $cen = Invoke-Census $phase
    Section '2. Calibrate the reader, in this same run, after the census'
    $ctl = Invoke-Controls $phase
    Record-Census $cen $ctl $phase

    Section "3. Do the guards themselves still hold? ($Stage)"
    $g = Invoke-Guards $phase
    Record-Guards $g $phase

    # BOOT IDENTITY. WSL idle-terminates the distro between dispatches -- three
    # times inside twenty minutes on cfv-191 -- and the census and the guard
    # checks are separate dispatches. If the distro restarted between them, this
    # stage is two measurements from two different boots reported as one, which
    # is not a weaker result but a different one. Asserted, not hoped for.
    $bootCen = Val $cen 'BOOT_ID'
    $bootGrd = Val $g   'BOOT_ID'
    Record "UP.$phase.BOOT" 'the census and the guard checks were taken in the SAME distro boot' `
        $(if ($bootCen -ne '(not reported)' -and $bootCen -eq $bootGrd) { 'PASS' } else { 'FAIL' }) `
        "census boot_id=$bootCen; guards boot_id=$bootGrd. The gateway needed $(Val $g 'GW_READY_AFTER_S')s to answer 200 on 8787 in this run, and the distro idle-terminates between dispatches, so a mismatch here means the two halves of this stage describe different machines."

    if ($Stage -eq 'WslCycle' -or $Stage -eq 'Post') {
        Section '4. Did they come back on their own, or did something start them?'
        # A unit systemd pulled in at boot has a SMALL
        # ActiveEnterTimestampMonotonic. Nothing in this run issues
        # `systemctl start`, and these numbers are the evidence for that rather
        # than the assertion.
        $rows = Rows $cen 'UNIT'
        $up   = ToInt (Val $cen 'UPTIME_S')
        # BOTH ends of the window. A unit that never entered active at all reads
        # ActiveEnter=0, and a filter that only looked for "later than 120s"
        # would score that 0 as early and pass it. Zero is the failure this row
        # exists to catch.
        # InactiveExit for EVERY unit, not ActiveEnter. Every unit that started
        # left the inactive state, whatever it did next, so this one field is
        # uniform across the long-running services, the timers and the two
        # oneshots. ActiveEnter would report 0 for the oneshots and fail them.
        $late = @($rows | Where-Object {
            $t = ($_ -split '\|')[7]
            $s = if ($t -as [double]) { [double]$t / 1000000.0 } else { -1 }
            ($s -le 0) -or ($s -gt 120)
        })
        Record "UP.$phase.5" 'every unit STARTED, and did so within the first two minutes of the distro coming up' `
            $(if ($rows.Count -eq 8 -and $late.Count -eq 0) { 'PASS' } else { 'FAIL' }) `
            ("distro uptime at measurement = ${up}s; units that never started, or started later than 120s after boot = $($late.Count)" + $(if ($late.Count) { " [$(($late | ForEach-Object { ($_ -split '\|')[1] + '@' + [math]::Round(([double](($_ -split '\|')[7]))/1000000.0,1) + 's' }) -join '; ')]" } else { '' }) + ". Read from InactiveExitTimestampMonotonic, which is uniform across services, timers and oneshots. This is what separates 'the units came back on their own' from 'the units are running because the probe started them'. Nothing in this run issues systemctl start.")
    }

    Complete-Phase -ResultsJson $ResultsJson -MarkerPrefix 'UP'
    Finish 0
}

# ===========================================================================
if ($Stage -eq 'Inject') {
    if (-not (Assert-Context -NeedChannel)) { Complete-Phase -ResultsJson $ResultsJson -MarkerPrefix 'UP'; Finish 4 }

    Section '1. TASK 2 -- the new read-back, against a unit that did not enable'

    # THE SUBJECT IS THE SHIPPED TEXT. The fixed resources/install-quarantine.sh
    # is copied into the distro and the block is EXTRACTED FROM IT by marker,
    # then those bytes are executed. It is not retyped into this probe: the
    # v1.4.3 suite ran payloads extracted from wrappers rather than the wrappers
    # themselves, and both of that release's blockers lived in exactly that gap.
    if (-not (Test-Path $FixedQuarantineSrc)) {
        Record 'UP.J0' 'the fixed installer source is on the box' 'FAIL' "missing at $FixedQuarantineSrc"
        Complete-Phase -ResultsJson $ResultsJson -MarkerPrefix 'UP'; Finish 2
    }
    $srcLin = Copy-IntoDistro $FixedQuarantineSrc '/var/tmp/cfv146-src-install-quarantine.sh'
    W "shipped source staged into the distro at $srcLin"
    W "windows-side sha256 = $((Get-FileHash -Algorithm SHA256 -LiteralPath $FixedQuarantineSrc).Hash.ToLower())"

    $body = @"
set +e
SRC=$srcLin
echo "SRC_PRESENT=`$( [ -f "`$SRC" ] && echo yes || echo no )"
echo "SRC_SHA=`$(sha256sum "`$SRC" 2>/dev/null | cut -d' ' -f1)"
# Extract from the READ BACK comment through the closing done -- the shipped
# bytes, by marker, with the line count reported so a silent mis-extraction
# cannot look like a pass.
awk '/^# READ BACK, BOTH OF THEM\./,/^done`$/' "`$SRC" > /var/tmp/cfv146-subject.sh
echo "SUBJECT_LINES=`$(wc -l < /var/tmp/cfv146-subject.sh | tr -d ' ')"
echo "SUBJECT_HAS_ISENABLED=`$(grep -c 'systemctl is-enabled' /var/tmp/cfv146-subject.sh)"
echo "SUBJECT_HAS_FATAL=`$(grep -c 'fatal ' /var/tmp/cfv146-subject.sh)"
# The shipped block calls fatal(), defined at the top of the real script. Take
# THAT definition from the same file rather than inventing one here.
grep -m1 '^fatal()' "`$SRC" > /var/tmp/cfv146-fatal.sh
echo "FATAL_DEF=`$(cat /var/tmp/cfv146-fatal.sh)"
cat /var/tmp/cfv146-fatal.sh /var/tmp/cfv146-subject.sh > /var/tmp/cfv146-run.sh

U=clawfactory-quarantine.service
W=/etc/systemd/system/multi-user.target.wants/`$U
COLL=clawfactory-send.service

# ---- A. POSITIVE CONTROL: nothing blocked, the shipped block must exit 0 ----
echo "A_PRE_ISENABLED=`$(systemctl is-enabled `$U 2>&1 | head -1)"
A_OUT="`$(bash /var/tmp/cfv146-run.sh 2>&1)"; A_RC=`$?
echo "A_RC=`$A_RC"
echo "A_OUT=`$(printf '%s' "`$A_OUT" | tr '\n' ' ' | cut -c1-300)"

# ---- inject: replace the wants symlink with a DIRECTORY ---------------------
rm -f "`$W"
mkdir -p "`$W"
echo "INJ_IS_DIR=`$( [ -d "`$W" ] && echo yes || echo no )"
echo "INJ_IS_LINK=`$( [ -L "`$W" ] && echo yes || echo no )"
echo "INJ_ISENABLED=`$(systemctl is-enabled `$U 2>&1 | head -1)"

# ---- C. OLD-CODE CONTROL: the pre-change line alone, same fault --------------
# This is the claim "the old code did not catch it", measured rather than said.
C_OUT="`$(systemctl enable --now `$U >/dev/null 2>&1 || true)"; C_RC=`$?
echo "C_RC=`$C_RC"
echo "C_OUT_LEN=`$(printf '%s' "`$C_OUT" | wc -c | tr -d ' ')"
echo "C_ISENABLED_AFTER=`$(systemctl is-enabled `$U 2>&1 | head -1)"

# ---- B. SUBJECT: the shipped block, same fault -------------------------------
B_OUT="`$(bash /var/tmp/cfv146-run.sh 2>&1)"; B_RC=`$?
echo "B_RC=`$B_RC"
echo "B_OUT=`$(printf '%s' "`$B_OUT" | tr '\n' ' ' | cut -c1-400)"

# ---- D. COLLATERAL CONTROL: a different unit still enables in that same dir ---
systemctl disable `$COLL >/dev/null 2>&1
D_ENABLE_OUT="`$(systemctl enable `$COLL 2>&1)"; D_RC=`$?
echo "D_RC=`$D_RC"
echo "D_ISENABLED=`$(systemctl is-enabled `$COLL 2>&1 | head -1)"

# ---- repair, and PROVE the repair, or the box lies to every later reader ------
rm -rf "`$W"
systemctl enable --now `$U >/dev/null 2>&1
systemctl enable --now `$COLL >/dev/null 2>&1
echo "REPAIR_U=`$(systemctl is-enabled `$U 2>&1 | head -1)"
echo "REPAIR_COLL=`$(systemctl is-enabled `$COLL 2>&1 | head -1)"
echo "REPAIR_U_ACTIVE=`$(systemctl is-active `$U 2>&1 | head -1)"
echo "REPAIR_COLL_ACTIVE=`$(systemctl is-active `$COLL 2>&1 | head -1)"
echo "READER_CTL=`$( [ -d /etc/systemd/system/multi-user.target.wants ] && echo present || echo absent )"
"@
    $r = Invoke-WslFile -Tag 'v146inject' -User 'root' -Body $body
    foreach ($ln in @($r.Out -split "`r?`n" | Where-Object { $_ -match '=' })) { W "   INJ> $($ln.Trim())" }
    $t = $r.Out

    $armed = Require-Precondition -Id 'UP.J.PRE' -Name 'the shipped installer text reached the box and the extraction found the block' `
        -Met (((Val $t 'SRC_PRESENT') -eq 'yes') -and ((ToInt (Val $t 'SUBJECT_HAS_ISENABLED')) -ge 1) -and ((ToInt (Val $t 'SUBJECT_HAS_FATAL')) -ge 1)) `
        -Reason "the subject must be the SHIPPED bytes, extracted by marker, not a copy retyped into the probe. src present=$(Val $t 'SRC_PRESENT') sha=$(Val $t 'SRC_SHA') extracted lines=$(Val $t 'SUBJECT_LINES') is-enabled hits=$(Val $t 'SUBJECT_HAS_ISENABLED') fatal hits=$(Val $t 'SUBJECT_HAS_FATAL')"
    if (-not $armed) { Complete-Phase -ResultsJson $ResultsJson -MarkerPrefix 'UP'; Finish 4 }

    Register-Control -Id 'UP.J.CTL.A' -Name 'A: the shipped read-back PASSES a correctly enabled unit' `
        -Fired ((Val $t 'A_RC') -eq '0') `
        -Evidence "with nothing blocked, is-enabled='$(Val $t 'A_PRE_ISENABLED')' and the shipped block exited $(Val $t 'A_RC') (must be 0). A check that always failed would pass a one-sided test and would also break every install; this is the half that rules that out." | Out-Null

    Register-Control -Id 'UP.J.CTL.D' -Name 'D: the injection is targeted at ONE unit' `
        -Fired (((Val $t 'D_RC') -eq '0') -and ((Val $t 'D_ISENABLED') -eq 'enabled')) `
        -Evidence "with the block in place on clawfactory-quarantine.service, clawfactory-send.service still enabled in the same directory: rc=$(Val $t 'D_RC'), is-enabled='$(Val $t 'D_ISENABLED')'. An injection that broke every enable would abort the install elsewhere and prove nothing about this check." | Out-Null

    Record 'UP.J1' 'THE FAULT LANDED: a directory occupies the enable target path' `
        $(if (((Val $t 'INJ_IS_DIR') -eq 'yes') -and ((Val $t 'INJ_IS_LINK') -eq 'no')) { 'PASS' } else { 'FAIL' }) `
        "the wants path is a directory=$(Val $t 'INJ_IS_DIR'), symlink=$(Val $t 'INJ_IS_LINK'), and is-enabled now reads '$(Val $t 'INJ_ISENABLED')'. A fault injection that does not inject scores a false pass and looks exactly like a working control."

    Record 'UP.J2' 'C: THE OLD CODE DID NOT CATCH IT -- the pre-change line exits 0, silently' `
        $(if (((Val $t 'C_RC') -eq '0') -and ((Val $t 'C_ISENABLED_AFTER') -ne 'enabled')) { 'PASS' } else { 'FAIL' }) `
        "the shipped v1.4.5 line -- systemctl enable --now the unit, redirected, or-true -- returned rc=$(Val $t 'C_RC') with $(Val $t 'C_OUT_LEN') bytes of output, and is-enabled afterwards read '$(Val $t 'C_ISENABLED_AFTER')'. That is the field failure exactly: the enable fails, the or-true swallows it, the unit is NOT enabled, and the install carries on reporting success."

    Record 'UP.J3' 'B: THE NEW CODE CATCHES IT -- the shipped read-back aborts, with its own message' `
        $(if (((Val $t 'B_RC') -ne '0') -and ((Val $t 'B_OUT') -match 'did not enable') -and ((Val $t 'B_OUT') -match 'does not come back after you restart your PC')) { 'PASS' } else { 'FAIL' }) `
        "the extracted shipped block exited $(Val $t 'B_RC') (must be non-zero) and said: '$(Val $t 'B_OUT')'. Both the unit name and the release-notes sentence are required, so a block that aborted for some other reason cannot score this row."

    Record 'UP.J4' 'the box was repaired and the repair was PROVED, not assumed' `
        $(if (((Val $t 'REPAIR_U') -eq 'enabled') -and ((Val $t 'REPAIR_COLL') -eq 'enabled') -and ((Val $t 'REPAIR_U_ACTIVE') -eq 'active') -and ((Val $t 'REPAIR_COLL_ACTIVE') -eq 'active')) { 'PASS' } else { 'FAIL' }) `
        "after removing the injected directory: quarantine is-enabled='$(Val $t 'REPAIR_U')' is-active='$(Val $t 'REPAIR_U_ACTIVE')'; send is-enabled='$(Val $t 'REPAIR_COLL')' is-active='$(Val $t 'REPAIR_COLL_ACTIVE')'. All four must read enabled/active or a later reader of this box is reading damage this probe caused."

    Complete-Phase -ResultsJson $ResultsJson -MarkerPrefix 'UP'
    Finish 0
}
