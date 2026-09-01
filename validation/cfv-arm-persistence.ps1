<#
  cfv-arm-persistence.ps1 -- make the on-VM runner survive reboots, WITHOUT a
  credential anywhere.

  RUNS ON THE VM, dispatched through az vm run-command, so it executes as
  NT AUTHORITY\SYSTEM.

  THE PREMISE IN THE JOB CARD WAS HALF RIGHT, AND THE HALF THAT WAS WRONG MATTERS
  ------------------------------------------------------------------------------
  "Auto-logon is one-shot, so a box that reboots mid-run comes back with no
  interactive session." True of Windows, false of this fleet: the last three
  cycles armed NO auto-logon at all.

    docs/session_reports/2026-08-27_v143_validation_closeout.md:320
      "AutoAdminLogon= is empty and was ASSERTED rather than set. The driver arms
       no auto-logon."

  Every implementation in this tree -- interim-v120-validate.ps1:436,
  job3-validate.ps1:275, scripts/azure-validate.ps1:449,
  scripts/egress-persistence-probe.ps1:211 -- reaches the password by RESETTING
  the account with `az vm user update` and writing it in cleartext to HKLM
  Winlogon DefaultPassword. PROMPT 15 forbids both halves. So the problem was
  never "the one-shot expires"; it is that arming auto-logon at all requires a
  cleartext credential the session must not have.

  WHAT WAS TRIED FIRST, AND WHY IT IS NOT WHAT THIS FILE DOES
  -----------------------------------------------------------
  An S4U ("Service-For-User") scheduled-task principal produces a token for a
  local account with NO password, which would have given a non-SYSTEM boot
  context for free. MEASURED ON cfv-192, 2026-09-01, IT IS DENIED:

    Register-ScheduledTask -LogonType S4U -RunLevel Highest   Access is denied.
    Register-ScheduledTask -LogonType S4U -RunLevel Limited   Access is denied.
    schtasks /Create /XML with <LogonType>S4U</LogonType>     Access is denied. (exit 1)
    the same S4U call from Task Scheduler's OWN SYSTEM task   Access is denied.

  With two controls succeeding in the same run -- ServiceAccount/SYSTEM and
  Interactive/clawadmin both registered fine -- so the context can register tasks
  and the denial is specific to S4U. And with the obvious cause ruled out:
  SeBatchLogonRight = *S-1-5-32-544 (BUILTIN\Administrators), of which clawadmin
  (SID ...-500) is a member, so the target account holds the right it needs.

  Recorded as a measured negative, not an inference. If a future Windows build
  or a policy change makes S4U available, this file is where to re-test it.

  WHAT THIS DOES INSTEAD: TWO RUNNERS, AND AN HONEST SPLIT
  --------------------------------------------------------
  Two tasks, because the two things a runner does have different requirements and
  only one of them can be had for free:

    CFV-Runner-System   SYSTEM / ServiceAccount / AtStartup
                        Comes back at EVERY boot with no logon and no credential.
                        Services jobs/ -- every Windows-side measurement: registry,
                        filesystem, install.log, service and task state, censuses,
                        evidence collection. This is what removes the operator
                        login from the run.

    CFV-Runner-User     clawadmin / Interactive / AtLogOn
                        Services wsljobs/ -- anything touching wsl.exe, because
                        wsl.exe refuses NT AUTHORITY\SYSTEM by name (measured in
                        the same run: WSL_E_LOCAL_SYSTEM_NOT_SUPPORTED). An
                        Interactive principal only runs while a session exists, so
                        this one CANNOT come back on its own after a reboot.

  THE HONEST CONSEQUENCE, STATED HERE RATHER THAN DISCOVERED LATER
  ----------------------------------------------------------------
  Windows-side work is now unattended across reboots. WSL work is not, and cannot
  be made so without a credential. A WSL job dropped on a box with no session does
  not hang and does not fail: Wait-CfvJob reads the absent wsljobs heartbeat and
  reports RunnerAbsent, which is a NAMED PRECONDITION, and a missing precondition
  is never a product verdict.

  SECURITY IMPLICATION (TASK 1.2)
  -------------------------------
  No credential is created, stored, printed or requested. Nothing is written to
  HKLM Winlogon; the script asserts that at the end so a future edit that
  reintroduces the DefaultPassword route changes a line the close-out cannot miss.
  What remains is a SYSTEM autostart on a throwaway VM created --nsg-rule NONE,
  deleted with its disk at teardown. That is strictly less exposure than the
  cleartext administrator password the forbidden drivers leave behind, which
  survives into any snapshot taken afterwards.

  CONFINEMENT TO THE VALIDATION FLEET (TASK 1.2), VERIFIED BY EXECUTION
  ---------------------------------------------------------------------
    1. ClawFactory-Secure-Setup.iss [Files] names only LICENSE, NOTICE,
       README.md and resources\* -- zero validation\ sources.
    2. grep over setup.ps1, resources/ and the .iss for any filename here or for
       either task name returns 0 hits.
    3. resources/uninstall.ps1 removes tasks by an explicit three-name list, not
       a pattern, so it could not touch these even if they were present.
    4. The only delivery route is az vm run-command against clawfactory-validation.
#>
param(
    [Parameter(Mandatory)][string]$RunId,
    [Parameter(Mandatory)][string]$AdminUser,
    [string]$Root      = 'C:\cfv\runs',
    [string]$RunnerPs1 = 'C:\cfv\cfv-runner.ps1'
)

$ErrorActionPreference = 'Continue'
$SysTask  = 'CFV-Runner-System'
$UserTask = 'CFV-Runner-User'

function Out-Kv([string]$k, $v) { Write-Output ("{0}={1}" -f $k, $v) }
function Get-WhoAmI { $w = ''; try { $w = ((& whoami.exe) -join '').Trim() } catch { $w = 'unknown' }; return $w }

Out-Kv 'ARM_WHOAMI' (Get-WhoAmI)
Out-Kv 'ARM_RUNID'  $RunId

if (-not (Test-Path $RunnerPs1)) {
    Out-Kv 'ARM_RESULT' 'FAIL'
    Out-Kv 'ARM_REASON' "runner script absent at $RunnerPs1 -- refusing to register a task that would run nothing"
    exit 3
}

$runDir = Join-Path $Root $RunId
foreach ($d in @($runDir, (Join-Path $runDir 'jobs'), (Join-Path $runDir 'wsljobs'), (Join-Path $runDir 'evidence'))) {
    New-Item -ItemType Directory -Path $d -Force | Out-Null
}

# The account must exist and be resolvable BEFORE anything is registered, so a
# typo in -AdminUser is a named failure here rather than a task that never fires
# two hours from now.
$acct = $null
try { $acct = Get-LocalUser -Name $AdminUser -ErrorAction Stop } catch { }
if (-not $acct) {
    Out-Kv 'ARM_RESULT' 'FAIL'
    Out-Kv 'ARM_REASON' "local account '$AdminUser' not found"
    Out-Kv 'ARM_ACCOUNTS' ((Get-LocalUser | Select-Object -ExpandProperty Name) -join ',')
    exit 3
}
Out-Kv 'ARM_ACCOUNT_ENABLED' $acct.Enabled

$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
                -StartWhenAvailable -MultipleInstances IgnoreNew `
                -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) `
                -ExecutionTimeLimit ([TimeSpan]::Zero)

function Register-Runner {
    param([string]$Name, [string]$JobSubdir, $Trigger, $Principal)
    Unregister-ScheduledTask -TaskName $Name -Confirm:$false -ErrorAction SilentlyContinue
    $arg = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}" -RunId "{1}" -Root "{2}" -JobSubdir "{3}"' -f $RunnerPs1, $RunId, $Root, $JobSubdir
    $err = ''
    try {
        Register-ScheduledTask -TaskName $Name -Action (New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $arg) `
            -Trigger $Trigger -Principal $Principal -Settings $settings -Force -ErrorAction Stop | Out-Null
    } catch { $err = $_.Exception.Message }
    if ($err) { Out-Kv "ARM_${Name}_REGISTER_ERROR" ($err -replace '\s+', ' ') }
    return (Get-ScheduledTask -TaskName $Name -ErrorAction SilentlyContinue)
}

# --- The one that removes the operator login. -------------------------------
$sysT = Register-Runner -Name $SysTask -JobSubdir 'jobs' `
          -Trigger (New-ScheduledTaskTrigger -AtStartup) `
          -Principal (New-ScheduledTaskPrincipal -UserId 'NT AUTHORITY\SYSTEM' -LogonType ServiceAccount -RunLevel Highest)

# --- The one that can only ever run when a session exists. ------------------
$usrT = Register-Runner -Name $UserTask -JobSubdir 'wsljobs' `
          -Trigger (New-ScheduledTaskTrigger -AtLogOn -User $AdminUser) `
          -Principal (New-ScheduledTaskPrincipal -UserId $AdminUser -LogonType Interactive -RunLevel Highest)

# ---------------------------------------------------------------------------
# READ-BACK. Register-ScheduledTask returning an object is not the claim that
# matters; what the task store now holds is. Every field the mechanism depends on
# is re-read and asserted by name, so a registration that landed with the wrong
# principal fails HERE and not as a mystery after the next reboot.
# ---------------------------------------------------------------------------
function Report-Task {
    param([string]$Label, $T)
    if (-not $T) { Out-Kv "ARM_${Label}_PRESENT" 'False'; return @{ Ok = $false } }
    $trigs = @($T.Triggers | ForEach-Object { $_.CimClass.CimClassName })
    Out-Kv "ARM_${Label}_PRESENT"   'True'
    Out-Kv "ARM_${Label}_LOGONTYPE" "$($T.Principal.LogonType)"
    Out-Kv "ARM_${Label}_USERID"    "$($T.Principal.UserId)"
    Out-Kv "ARM_${Label}_RUNLEVEL"  "$($T.Principal.RunLevel)"
    Out-Kv "ARM_${Label}_STATE"     "$($T.State)"
    Out-Kv "ARM_${Label}_TRIGGERS"  ($trigs -join ',')
    Out-Kv "ARM_${Label}_ARGS"      "$($T.Actions[0].Arguments)"
    return @{ Ok = $true; Logon = "$($T.Principal.LogonType)"; Trigs = $trigs; Args = "$($T.Actions[0].Arguments)" }
}
$sysR = Report-Task -Label 'SYS'  -T $sysT
$usrR = Report-Task -Label 'USER' -T $usrT

# NEGATIVE CONTROLS, in the same run. The read-backs above mean nothing unless
# the same calls can return false.
$ctlName = "CFV-Runner-CONTROL-DOES-NOT-EXIST-$RunId"
$ctlAbsent = ($null -eq (Get-ScheduledTask -TaskName $ctlName -ErrorAction SilentlyContinue))
Out-Kv 'ARM_CTL_ABSENT_TASK_RETURNS_NULL' $ctlAbsent

# Second control half: the store must DISCRIMINATE logon types. The two tasks
# above were registered with deliberately different ones, so if the read-back
# reports them as different it cannot be echoing a constant.
$ctlDiscriminates = $false
if ($sysR.Ok -and $usrR.Ok) { $ctlDiscriminates = ($sysR.Logon -ne $usrR.Logon) }
Out-Kv 'ARM_CTL_READBACK_DISCRIMINATES' $ctlDiscriminates
Out-Kv 'ARM_CTL_LOGONTYPES_SEEN' "$($sysR.Logon)|$($usrR.Logon)"

# The security claim in machine-readable form.
$wl = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
$aal = ''; $dpp = $false
try { $aal = "$((Get-ItemProperty $wl -Name AutoAdminLogon -ErrorAction SilentlyContinue).AutoAdminLogon)" } catch { }
try { $dpp = ($null -ne (Get-ItemProperty $wl -Name DefaultPassword -ErrorAction SilentlyContinue).DefaultPassword) } catch { }
Out-Kv 'ARM_WINLOGON_AUTOADMINLOGON' $aal
Out-Kv 'ARM_WINLOGON_DEFAULTPASSWORD_PRESENT' $dpp

# The SYSTEM task is the load-bearing one; the run proceeds without the user task
# and simply cannot take WSL rows. So they are scored separately rather than
# collapsed into one verdict that would hide which half is missing.
$sysOk = $sysR.Ok -and ($sysR.Logon -eq 'ServiceAccount') -and
         ($sysR.Trigs -contains 'MSFT_TaskBootTrigger') -and ($sysR.Args -match [regex]::Escape($RunId)) -and
         $ctlAbsent -and (-not $dpp)
$usrOk = $usrR.Ok -and ($usrR.Logon -eq 'Interactive') -and ($usrR.Trigs -contains 'MSFT_TaskLogonTrigger')

Out-Kv 'ARM_SYSTEM_RESULT' $(if ($sysOk) { 'PASS' } else { 'FAIL' })
Out-Kv 'ARM_USER_RESULT'   $(if ($usrOk) { 'PASS' } else { 'FAIL' })
Out-Kv 'ARM_WSL_CAPABLE_UNATTENDED' 'False'
Out-Kv 'ARM_WSL_REASON' 'S4U is denied to SYSTEM on this build (measured, four paths); an Interactive principal cannot run without a session. WSL jobs need a logon and record RunnerAbsent otherwise.'

# Start the SYSTEM runner now so this boot has one without waiting for a restart.
$started = 'no'
try { Start-ScheduledTask -TaskName $SysTask -ErrorAction Stop; $started = 'yes' }
catch { $started = "no: $($_.Exception.Message)" }
Out-Kv 'ARM_SYSTEM_START_ISSUED' $started

Out-Kv 'ARM_RESULT' $(if ($sysOk) { 'PASS' } else { 'FAIL' })
if (-not $sysOk) { Out-Kv 'ARM_REASON' 'the SYSTEM read-back did not match the required shape; see the ARM_SYS_* lines' }
if ($sysOk) { exit 0 } else { exit 3 }
