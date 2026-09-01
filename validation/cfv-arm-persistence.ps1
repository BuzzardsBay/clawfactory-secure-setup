<#
  cfv-arm-persistence.ps1 -- make the on-VM runner survive reboots, WITHOUT a
  credential anywhere.

  RUNS ON THE VM. Dispatched by the driver through az vm run-command, so it
  executes as NT AUTHORITY\SYSTEM. That is deliberate: SYSTEM can register a
  scheduled task for another principal under an S4U logon type without supplying
  or knowing that principal's password.

  THE PREMISE IN THE JOB CARD WAS HALF RIGHT, AND THE HALF THAT WAS WRONG MATTERS
  ------------------------------------------------------------------------------
  "Auto-logon is one-shot, so a box that reboots mid-run comes back with no
  interactive session." The first clause is true of Windows and false of this
  fleet: the last three cycles armed NO auto-logon at all.

    docs/session_reports/2026-08-27_v143_validation_closeout.md:320
      "AutoAdminLogon= is empty and was ASSERTED rather than set. The driver arms
       no auto-logon, which is what makes the two operator logins the correct
       price of the PROMPT 15 credential rule rather than a defect to engineer
       around."

  Every implementation of auto-logon in this tree -- interim-v120-validate.ps1:436,
  job3-validate.ps1:275, scripts/azure-validate.ps1:449,
  scripts/egress-persistence-probe.ps1:211 -- reaches the password the same way:
  it RESETS the admin account with `az vm user update` to a password the script
  generated, then writes that password in cleartext to HKLM Winlogon
  DefaultPassword. PROMPT 15 forbids both halves ("Do not generate an admin
  password, do not print one, do not ask for one, and do not call az vm user
  update after provisioning"), which is why those drivers are forbidden and why
  every recent cycle paid an RDP login per boot instead.

  So the problem was never "the one-shot expires". It is that arming auto-logon at
  all requires a cleartext credential the session must not have.

  WHAT THIS DOES INSTEAD
  ----------------------
  It does not arm auto-logon. It registers a scheduled task whose principal is the
  admin account with LogonType S4U -- Service-For-User. S4U produces a token for a
  local account WITHOUT a password: Windows issues it directly, which is why the
  task can be created by SYSTEM and re-run at every boot forever with nothing
  secret stored anywhere. No DefaultPassword, no az vm user update, no generated
  password, nothing for this session to read.

  Triggers are AtStartup AND AtLogOn, so the runner comes back whether the box
  reboots into no session at all or the operator later logs in for a hand check.
  MultipleInstances=IgnoreNew makes the second trigger harmless.

  SECURITY IMPLICATION, STATED PLAINLY (TASK 1.2)
  -----------------------------------------------
  The task runs as the local admin account at highest privilege, at every boot,
  with no interactive user present. On a validation VM that is the intended
  posture and it is STRICTLY SAFER than the alternative it replaces: the forbidden
  drivers leave a cleartext administrator password in HKLM\...\Winlogon
  DefaultPassword, readable by any local administrator and captured in any disk
  image or snapshot taken afterwards. S4U leaves no credential to read.

  What remains is a privileged autostart. On these boxes it is bounded by:
    - the VM exists for hours and is deleted at teardown, disk included;
    - the NSG is created --nsg-rule NONE with one RDP rule scoped to a single /32;
    - the task action is a fixed path under C:\cfv, on a machine with no user data.

  CONFINEMENT TO THE VALIDATION FLEET (TASK 1.2)
  ----------------------------------------------
  This file cannot reach a customer machine, for three independent reasons, each
  checkable rather than asserted:
    1. It lives in validation/, and ClawFactory-Secure-Setup.iss bundles no file
       from validation/. Verify with: the [Files] section names resources\ and
       Output\, never validation\.
    2. Nothing in setup.ps1 or resources/ references cfv-arm-persistence.ps1 or
       the CFV-Runner task name. Verify with a tree-wide grep.
    3. Its only delivery route is az vm run-command against a VM in the
       clawfactory-validation resource group, dispatched by hand from the driver.
  The close-out records the executed form of all three.

  WHAT THIS DOES NOT CLAIM
  ------------------------
  It does not claim WSL works under the resulting token. It cannot: wsl.exe refuses
  NT AUTHORITY\SYSTEM by name, and "not SYSTEM" is a different claim from "WSL
  works here". cfv-runner.ps1 measures that once at startup, with a control, and
  records the answer in _wslcontext.json. A job that needs WSL on a box where the
  answer is false records a NAMED precondition failure. A missing precondition is
  never a product verdict.
#>
param(
    [Parameter(Mandatory)][string]$RunId,
    [Parameter(Mandatory)][string]$AdminUser,
    [string]$Root      = 'C:\cfv\runs',
    [string]$RunnerPs1 = 'C:\cfv\cfv-runner.ps1',
    [string]$TaskName  = 'CFV-Runner'
)

$ErrorActionPreference = 'Continue'
$nonce = 'CFV_ARM_' + $RunId

function Out-Kv([string]$k, $v) { Write-Output ("{0}={1}" -f $k, $v) }

Out-Kv 'ARM_WHOAMI'   (try { (& whoami.exe 2>&1 | Out-String).Trim() } catch { '?' })
Out-Kv 'ARM_RUNID'    $RunId
Out-Kv 'ARM_TASKNAME' $TaskName

if (-not (Test-Path $RunnerPs1)) {
    Out-Kv 'ARM_RESULT' 'FAIL'
    Out-Kv 'ARM_REASON' "runner script absent at $RunnerPs1 -- refusing to register a task that would run nothing"
    Write-Output "CFV_EOF:$nonce"
    exit 3
}

New-Item -ItemType Directory -Path (Join-Path $Root $RunId) -Force | Out-Null

# The account must exist and must be resolvable, or S4U registration succeeds
# against nothing useful. Checked BEFORE registering, so a typo in -AdminUser is
# a named failure here rather than a task that never fires two hours later.
$acct = $null
try { $acct = Get-LocalUser -Name $AdminUser -ErrorAction Stop } catch { }
if (-not $acct) {
    Out-Kv 'ARM_RESULT' 'FAIL'
    Out-Kv 'ARM_REASON' "local account '$AdminUser' not found"
    Out-Kv 'ARM_ACCOUNTS' ((Get-LocalUser | Select-Object -ExpandProperty Name) -join ',')
    Write-Output "CFV_EOF:$nonce"
    exit 3
}
Out-Kv 'ARM_ACCOUNT_ENABLED' $acct.Enabled

Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue

$action = New-ScheduledTaskAction -Execute 'powershell.exe' `
            -Argument ('-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}" -RunId "{1}" -Root "{2}"' -f $RunnerPs1, $RunId, $Root)

# AtStartup is the one that removes the operator login. AtLogOn is kept so that a
# hand check which does involve an interactive session still finds a live runner,
# and so the mechanism degrades to the OLD behaviour rather than to nothing if
# AtStartup ever fails to fire.
$triggers = @(
    (New-ScheduledTaskTrigger -AtStartup),
    (New-ScheduledTaskTrigger -AtLogOn -User $AdminUser)
)

# S4U: run whether the user is logged on or not, WITHOUT storing a password.
$principal = New-ScheduledTaskPrincipal -UserId $AdminUser -LogonType S4U -RunLevel Highest

$settings = New-ScheduledTaskSettingsSet `
                -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
                -StartWhenAvailable `
                -MultipleInstances IgnoreNew `
                -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) `
                -ExecutionTimeLimit ([TimeSpan]::Zero)

$reg = $null
try {
    $reg = Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $triggers `
             -Principal $principal -Settings $settings -Force -ErrorAction Stop
} catch {
    Out-Kv 'ARM_REGISTER_ERROR' $_.Exception.Message
}

# ---------------------------------------------------------------------------
# READ-BACK. Register-ScheduledTask returning an object is not the claim that
# matters; the claim that matters is what the task store now holds. Every field
# the mechanism depends on is re-read from the store and asserted by name, so a
# registration that silently landed with the wrong principal is a FAIL here and
# not a mystery after the next reboot.
# ---------------------------------------------------------------------------
$t = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if (-not $t) {
    Out-Kv 'ARM_RESULT' 'FAIL'
    Out-Kv 'ARM_REASON' 'task absent from the store after registration'
    Write-Output "CFV_EOF:$nonce"
    exit 3
}

$rbLogon    = "$($t.Principal.LogonType)"
$rbUser     = "$($t.Principal.UserId)"
$rbRunLevel = "$($t.Principal.RunLevel)"
$rbState    = "$($t.State)"
$rbTrigs    = @($t.Triggers | ForEach-Object { $_.CimClass.CimClassName })
$rbArgs     = "$($t.Actions[0].Arguments)"

Out-Kv 'ARM_RB_LOGONTYPE' $rbLogon
Out-Kv 'ARM_RB_USERID'    $rbUser
Out-Kv 'ARM_RB_RUNLEVEL'  $rbRunLevel
Out-Kv 'ARM_RB_STATE'     $rbState
Out-Kv 'ARM_RB_TRIGGERS'  ($rbTrigs -join ',')
Out-Kv 'ARM_RB_ARGS'      $rbArgs

# NEGATIVE CONTROL, in the same run. The read-back above only means something if
# these same predicates can return false. A name that cannot exist is queried
# through the identical call, and its absence is asserted. Without this, a
# Get-ScheduledTask that returned a stub for everything would read as a pass.
$ctlName = "CFV-Runner-CONTROL-DOES-NOT-EXIST-$RunId"
$ctl = Get-ScheduledTask -TaskName $ctlName -ErrorAction SilentlyContinue
Out-Kv 'ARM_CTL_ABSENT_TASK_RETURNS_NULL' ($null -eq $ctl)

# Second control half: the store must distinguish logon types. Register a throwaway
# task with an explicitly DIFFERENT logon type and confirm the read-back says so,
# then remove it. If this reads S4U too, the read-back above is not discriminating.
$ctl2Name = "CFV-Runner-CONTROL-LOGONTYPE-$RunId"
$ctl2Read = 'not-taken'
try {
    Register-ScheduledTask -TaskName $ctl2Name `
        -Action (New-ScheduledTaskAction -Execute 'cmd.exe' -Argument '/c exit 0') `
        -Trigger (New-ScheduledTaskTrigger -AtStartup) `
        -Principal (New-ScheduledTaskPrincipal -UserId 'NT AUTHORITY\SYSTEM' -LogonType ServiceAccount -RunLevel Highest) `
        -Force -ErrorAction Stop | Out-Null
    $ctl2Read = "$((Get-ScheduledTask -TaskName $ctl2Name -ErrorAction SilentlyContinue).Principal.LogonType)"
} catch {
    $ctl2Read = "control-registration-threw: $($_.Exception.Message)"
} finally {
    Unregister-ScheduledTask -TaskName $ctl2Name -Confirm:$false -ErrorAction SilentlyContinue
}
Out-Kv 'ARM_CTL_OTHER_LOGONTYPE_READBACK' $ctl2Read
$ctlDiscriminates = ($ctl2Read -ne $rbLogon)
Out-Kv 'ARM_CTL_READBACK_DISCRIMINATES' $ctlDiscriminates

# Assert that no cleartext credential was created as a side effect. This is the
# security claim in machine-readable form: if a future edit reintroduces the
# DefaultPassword route, this line changes and the close-out cannot miss it.
$wl = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
Out-Kv 'ARM_WINLOGON_AUTOADMINLOGON'  ("$((Get-ItemProperty $wl -Name AutoAdminLogon  -ErrorAction SilentlyContinue).AutoAdminLogon)")
Out-Kv 'ARM_WINLOGON_DEFAULTPASSWORD_PRESENT' ($null -ne (Get-ItemProperty $wl -Name DefaultPassword -ErrorAction SilentlyContinue).DefaultPassword)

$ok = ($rbLogon -eq 'S4U') -and
      ($rbUser -match [regex]::Escape($AdminUser)) -and
      ($rbRunLevel -eq 'Highest') -and
      ($rbTrigs -contains 'MSFT_TaskBootTrigger') -and
      ($rbTrigs -contains 'MSFT_TaskLogonTrigger') -and
      ($rbArgs -match [regex]::Escape($RunId)) -and
      ($null -eq $ctl) -and $ctlDiscriminates

Out-Kv 'ARM_RESULT' $(if ($ok) { 'PASS' } else { 'FAIL' })
if (-not $ok) {
    Out-Kv 'ARM_REASON' 'read-back did not match the required shape; see the ARM_RB_* lines above'
}

# Start it now so the current boot has a runner without waiting for a restart.
try {
    Start-ScheduledTask -TaskName $TaskName -ErrorAction Stop
    Out-Kv 'ARM_START_ISSUED' 'yes'
} catch {
    Out-Kv 'ARM_START_ISSUED' "no: $($_.Exception.Message)"
}

Write-Output "CFV_EOF:$nonce"
if ($ok) { exit 0 } else { exit 3 }
