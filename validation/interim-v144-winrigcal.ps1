<#
  CALIBRATION, not a verdict-bearing phase. One question, about a minute.

  CAN A WINDOWS-SIDE FAULT REACH THE PROVIDER-ROUTE GATE AT ALL?

  PG.3f needs a fault that is still in place when the gate runs at Step 15h. Three
  mechanisms inside the distro erase one, and all three are the install's own
  normal behaviour rather than anything exotic:

    1. setup.ps1 Step-ConfigureWslConf (Step 3) OVERWRITES /etc/wsl.conf wholesale
       from a here-string that contains no generateHosts, so a generateHosts=false
       rig is erased before the restart that it exists to survive.
    2. Step-RestartWsl (Step 4) then runs `wsl --shutdown`, and WSL regenerates
       /etc/hosts on the next start, erasing an /etc/hosts rig.
    3. Step-EgressFirewall rewrites the nftables ruleset, erasing a rigged rule --
       which is why interim-v135-providergate.ps1's header rejected a firewall rig
       in the first place.

  So every in-distro rig tried so far is erased by the install it is meant to
  interrupt. The remaining candidate is a fault OUTSIDE the distro, which
  setup.ps1 never touches: a Windows outbound firewall block on the provider's
  addresses. Matrix row 2 proves that technique survives a full 14-minute install
  (B3.1 re-measured the block as still in force at the end).

  WHAT IS GENUINELY UNKNOWN, and is the whole reason this file exists: the gate
  runs INSIDE WSL as clawuser, and WSL2 egress leaves through a virtual adapter.
  A Windows outbound rule may or may not apply to it. Box A's v1.4.0 notes record
  that pktmon saw zero packets from an install for exactly this reason. Guessing
  either way and writing it into a card would hand the next session a recipe that
  has never been run.

  This measures it directly, against the gate's OWN probe body -- the one
  interim-v135-providergate.ps1 extracted from the INSTALLED setup.ps1 earlier in
  this run and left at /var/tmp/pg-probe.sh -- so the answer is about the shipped
  measurement rather than about a re-implementation of it.
#>
param(
    [string]$Transcript   = 'C:\cfv\winrigcal-out-probe.txt',
    [string]$ResultsJson  = 'C:\cfv\winrigcal-results.json',
    [string]$ProviderHost = 'api.anthropic.com',
    [string]$GateProbe    = '/var/tmp/pg-probe.sh',
    [string]$LibDir       = 'C:\cfv'
)
$ErrorActionPreference = 'Continue'
. (Join-Path $LibDir 'interim-v120-wslchan.ps1')
. (Join-Path $LibDir 'interim-v120-phaselib.ps1')

Start-Phase -Name 'Calibration: can a Windows-side block reach the in-WSL provider-route gate?' `
    -Transcript $Transcript -Sentinel 'WINRIGCAL_PROBE_COMPLETE'

$chan = Test-WslChannel
Register-Control -Id 'WC.CHAN' -Name 'the file-based WSL channel discriminates' -Fired $chan.Ok -Evidence $chan.Detail | Out-Null
if (-not $chan.Ok) { W 'CHANNEL UNTRUSTWORTHY, stopping (L22).'; Complete-Phase -ResultsJson $ResultsJson -MarkerPrefix 'WINRIGCAL' }

# ------------------------------------------------------------ 0. the subject
Section '0. The gate''s own probe body must be present, or this measures a substitute'
$have = Invoke-WslFile -Tag 'wc-have' -User 'root' -Body "if [ -s $GateProbe ]; then echo `"GATE_PROBE_PRESENT bytes=`$(wc -c < $GateProbe | tr -d ' ')`"; else echo GATE_PROBE_ABSENT; fi"
W $have.Out
$haveProbe = $have.Out -match 'GATE_PROBE_PRESENT'
$ok = Require-Precondition -Id 'WC.PRE' -Name "the gate's extracted probe body is on the box at $GateProbe" `
    -Met $haveProbe `
    -Reason "interim-v135-providergate.ps1 extracts this from the INSTALLED setup.ps1 during its level-1 control and leaves it here. Without it this phase would have to re-implement the gate, and a calibration of a re-implementation says nothing about the shipped measurement"
if (-not $ok) { Complete-Phase -ResultsJson $ResultsJson -MarkerPrefix 'WINRIGCAL' }

# --------------------------------------------------- 1. unrigged: must succeed
Section '1. UNRIGGED: the gate probe succeeds as clawuser right now'
$un1 = Invoke-WslFile -Tag 'wc-unrig1' -User 'clawuser' -Body "bash $GateProbe; echo `"PROBE_RC=`$?`""
W $un1.Out
$unrigOk = $un1.Out -match 'PROBE_RC=0'
Register-Control -Id 'WC.CTL0' -Name 'the gate probe SUCCEEDS before the rig, in this same run' `
    -Fired $unrigOk -Evidence 'without this, a failure after the rig could just mean the probe never works here' | Out-Null

# ------------------------------------------------------- 2. rig, Windows-side
Section '2. Block the provider''s addresses with a Windows outbound rule'
$ips = @()
try { $ips = @((Resolve-DnsName $ProviderHost -Type A -ErrorAction Stop | Where-Object { $_.IPAddress }).IPAddress) } catch { }
W "$ProviderHost resolves Windows-side to: $(if ($ips) { $ips -join ' ' } else { '(did not resolve)' })"
Remove-NetFirewallRule -DisplayName 'cfv-winrig-provider' -ErrorAction SilentlyContinue
foreach ($ip in $ips) {
    New-NetFirewallRule -DisplayName 'cfv-winrig-provider' -Direction Outbound -Action Block `
        -RemoteAddress $ip -Protocol Any -Profile Any -ErrorAction SilentlyContinue | Out-Null
}
$rules = @(Get-NetFirewallRule -DisplayName 'cfv-winrig-provider' -ErrorAction SilentlyContinue)
W "rules created: $($rules.Count) for $($ips.Count) address(es)"
# The fault must be proven to have landed WINDOWS-SIDE before asking whether it
# reaches the distro. Those are two different claims.
$winBlocked = -not (Test-NetConnection -ComputerName $ProviderHost -Port 443 -InformationLevel Quiet -WarningAction SilentlyContinue)
W "Windows-side reachability after the block: $(if ($winBlocked) { 'BLOCKED' } else { 'STILL REACHABLE' })"
Register-Control -Id 'WC.CTL1' -Name 'THE FAULT LANDED on the Windows side' -Fired ($rules.Count -gt 0 -and $winBlocked) `
    -Evidence "rules=$($rules.Count), Windows-side connect blocked=$winBlocked. If the block does not even work Windows-side then the distro-side reading below is meaningless" | Out-Null

# ------------------------------------- 3. THE QUESTION: does it reach the gate?
Section '3. THE QUESTION: does that Windows-side block stop the IN-WSL gate probe?'
$rig1 = Invoke-WslFile -Tag 'wc-rigged' -User 'clawuser' -Body "bash $GateProbe; echo `"PROBE_RC=`$?`""
W $rig1.Out
$reaches = $rig1.Out -match 'PROBE_RC=1'
# CLASSIFY. Three named states, and the state is printed.
$state = if (-not $unrigOk) { 'UNCALIBRATED' } elseif ($reaches) { 'REACHES_WSL' } else { 'DOES_NOT_REACH_WSL' }
W "WINRIG_STATE=$state"
Record 'WC.1' 'a Windows-side outbound block stops the in-WSL provider-route gate probe' `
    $(if ($state -eq 'UNCALIBRATED') { 'VOID' } elseif ($state -eq 'REACHES_WSL') { 'PASS' } else { 'FAIL' }) `
    "state=$state. REACHES_WSL means a Windows-side rig is a viable basis for PG.3f's level-2 control, because setup.ps1 never touches Windows firewall rules and matrix row 2 proved such a block survives a full install. DOES_NOT_REACH_WSL means it is not viable and PG.3f needs a different approach entirely. Either answer is worth having; this row asserts only which one holds"

# ----------------------------------------------------------------- 4. restore
Section '4. Remove the fault and prove it is gone, from BOTH sides'
Remove-NetFirewallRule -DisplayName 'cfv-winrig-provider' -ErrorAction SilentlyContinue
$left = @(Get-NetFirewallRule -DisplayName 'cfv-winrig-provider' -ErrorAction SilentlyContinue).Count
$winBack = Test-NetConnection -ComputerName $ProviderHost -Port 443 -InformationLevel Quiet -WarningAction SilentlyContinue
$un2 = Invoke-WslFile -Tag 'wc-unrig2' -User 'clawuser' -Body "bash $GateProbe; echo `"PROBE_RC=`$?`""
W $un2.Out
$wslBack = $un2.Out -match 'PROBE_RC=0'
Record 'WC.2' 'the fault was removed and the provider route works again from both Windows and the distro' `
    $(if (($left -eq 0) -and $winBack -and $wslBack) { 'PASS' } else { 'FAIL' }) `
    "rules left=$left (must be 0); Windows-side reachable again=$winBack; in-WSL gate probe rc=0 again=$wslBack. A probe that leaves its fault behind would brick the agent on this box"

Complete-Phase -ResultsJson $ResultsJson -MarkerPrefix 'WINRIGCAL'
