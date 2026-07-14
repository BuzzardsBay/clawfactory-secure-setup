# clawfactory-grants.ps1 -- Grants substrate for ClawFactory v1.1 (Phase 1).
#
# Dot-source this library (`. clawfactory-grants.ps1`) from launcher.ps1, the
# Kill Switch, the smoke test, and (Phase 2) ClawFactory Studio. It provides:
#
#   Ledger  (Task 1.1): Add-Grant, Remove-Grant, Get-Grants, Get-ActiveGrants
#   Workspace (Task 1.2): Grant-Workspace, Revoke-Workspace, Test-Grants
#   Replay/Kill (Task 1.3): Invoke-GrantReplay, Invoke-GrantKillUnmount
#   Governor (Task 1.4): Get-SpendStatus, Test-TurnAllowed, Invoke-GatedAgentTurn
#
# One ledger (C:\ProgramData\ClawFactory\grants.json) covers all three grant
# types (workspace | skill | domain). Only `workspace` is USED in v1.1; the
# `skill`/`domain` types are DEFINED so Phase 3 does not migrate the file.
#
# Mount mechanism (Phase 0 VERIFIED, drvfs -- agents are clawuser processes on
# ext4, never containers):
#   wsl -d Ubuntu -u root -- mount -t drvfs '<WinPath>' /workspaces/<slug> \
#       -o metadata,uid=1000,gid=1000[,ro]
# clawuser is uid/gid 1000 (Phase 0 VERIFIED). Forward-slash Windows paths are
# used because backslashes are eaten crossing the PowerShell->wsl->bash boundary
# (Phase 0 lesson).
#
# Windows PowerShell 5.1 compatible (no ternary / ?? / ?. operators).

Set-StrictMode -Version 3.0

#--- Paths / constants -------------------------------------------------------
$script:CF_Dir            = Join-Path $env:ProgramData 'ClawFactory'
$script:CF_GrantsFile     = Join-Path $script:CF_Dir 'grants.json'
$script:CF_GrantsAuditLog = Join-Path $script:CF_Dir 'grants-audit.log'
$script:CF_GovernorFile   = Join-Path $script:CF_Dir 'governor.json'
$script:CF_WslDistro      = 'Ubuntu'
$script:CF_WslUser        = 'clawuser'
$script:CF_MountRoot      = '/workspaces'

# Install dir = parent of the resources dir this script lives in. Used by the
# deny list so a workspace grant can never expose the ClawFactory install tree.
if ($PSScriptRoot) {
    $script:CF_InstallDir = Split-Path -Parent $PSScriptRoot
} else {
    $script:CF_InstallDir = $null
}

#--- Low-level WSL invocation (self-contained; UTF-8 Linux stdout) -----------
function Invoke-ClawWslBash {
    # Runs a bash script inside WSL, base64-encoded so quoting survives the
    # PowerShell -> wsl.exe -> bash boundary (mirrors setup.ps1 Invoke-WslBash).
    # Returns @{ ExitCode; StdOut; StdErr }. Linux stdout is UTF-8.
    param(
        [Parameter(Mandatory)][string]$Script,
        [string]$User = $script:CF_WslUser
    )
    $norm = $Script.Replace("`r`n", "`n").Replace("`r", "`n")
    $enc  = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($norm))
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName               = 'wsl.exe'
    $psi.Arguments              = "-d $script:CF_WslDistro -u $User -- bash -lc `"echo '$enc' | base64 -d | bash -l`""
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true
    $psi.UseShellExecute        = $false
    $psi.CreateNoWindow         = $true
    $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $psi.StandardErrorEncoding  = [System.Text.Encoding]::UTF8
    $proc   = [System.Diagnostics.Process]::Start($psi)
    $stdout = $proc.StandardOutput.ReadToEnd()
    $stderr = $proc.StandardError.ReadToEnd()
    $proc.WaitForExit()
    return @{ ExitCode = $proc.ExitCode; StdOut = $stdout; StdErr = $stderr }
}

#--- Audit log (append-only; atomic tmp+rename, matches launcher.ps1) --------
function Write-GrantAudit {
    # One JSON object per line. There was NO pre-existing runtime audit log in
    # this repo (only install.log = install-time, launcher.log = launch-state);
    # this follows the established "one append-only log per subsystem in
    # ProgramData\ClawFactory" convention rather than inventing a new scheme.
    param(
        [Parameter(Mandatory)][string]$Event,
        [hashtable]$Data = @{}
    )
    try {
        if (-not (Test-Path -LiteralPath $script:CF_Dir)) {
            New-Item -ItemType Directory -Path $script:CF_Dir -Force | Out-Null
        }
        $rec = [ordered]@{
            ts    = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ssK')
            event = $Event
        }
        foreach ($k in $Data.Keys) { $rec[$k] = $Data[$k] }
        $line = ($rec | ConvertTo-Json -Depth 6 -Compress)
        $existing = ''
        if (Test-Path -LiteralPath $script:CF_GrantsAuditLog) {
            $existing = Get-Content -LiteralPath $script:CF_GrantsAuditLog -Raw -Encoding UTF8
        }
        $tmp = "$script:CF_GrantsAuditLog.tmp.$PID"
        # WriteAllText + UTF8Encoding($false): PS 5.1's Set-Content -Encoding UTF8
        # prepends a BOM, which breaks non-PowerShell JSON parsers reading the
        # first line (e.g. Studio's Node backend). No BOM here.
        [System.IO.File]::WriteAllText($tmp, ($existing + $line + "`r`n"), (New-Object System.Text.UTF8Encoding($false)))
        Move-Item -LiteralPath $tmp -Destination $script:CF_GrantsAuditLog -Force
    } catch {
        # Best-effort: an audit write failure must not abort a grant operation,
        # but we surface it so it is not silent.
        Write-Warning "grant audit-log write failed: $($_.Exception.Message)"
    }
}

#===========================================================================
# TASK 1.1 -- Grants ledger
#===========================================================================
# Schema (one object per grant in grants.json .grants[]):
#   id          stable slug (unique)
#   type        'workspace' | 'skill' | 'domain'
#   label       human-readable
#   created_at  ISO-8601 timestamp
#   mode        workspace only: 'rw' | 'ro' (null for skill/domain)
#   target      the concrete grant: Windows path | plugin id | hostname
#   depends_on  array of grant ids (e.g. a skill grant -> the domain grants it needs)
#   active      bool

function Get-GrantsRaw {
    # Internal: returns an array of grant PSCustomObjects (never $null).
    if (-not (Test-Path -LiteralPath $script:CF_GrantsFile)) { return @() }
    try {
        $json = Get-Content -LiteralPath $script:CF_GrantsFile -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        throw "grants.json is present but unparseable ($($_.Exception.Message)). Refusing to guess; fix or remove $script:CF_GrantsFile."
    }
    if ($null -eq $json -or -not ($json.PSObject.Properties.Name -contains 'grants')) { return @() }
    return @($json.grants)
}

function Save-GrantsRaw {
    param([Parameter(Mandatory)][AllowEmptyCollection()][array]$Grants)
    if (-not (Test-Path -LiteralPath $script:CF_Dir)) {
        New-Item -ItemType Directory -Path $script:CF_Dir -Force | Out-Null
    }
    $state = [ordered]@{ grants = @($Grants) }
    $tmp = "$script:CF_GrantsFile.tmp.$PID"
    # No BOM (PS 5.1 Set-Content -Encoding UTF8 would add one).
    [System.IO.File]::WriteAllText($tmp, ($state | ConvertTo-Json -Depth 8), (New-Object System.Text.UTF8Encoding($false)))
    Move-Item -LiteralPath $tmp -Destination $script:CF_GrantsFile -Force
}

function Get-Grants {
    # Public: every grant (active and inactive), all types.
    return Get-GrantsRaw
}

function Get-ActiveGrants {
    # Public: active grants, optionally filtered by type.
    param([ValidateSet('workspace', 'skill', 'domain')][string]$Type)
    $all = Get-GrantsRaw | Where-Object { $_.active }
    if ($Type) { $all = $all | Where-Object { $_.type -eq $Type } }
    return @($all)
}

function Add-Grant {
    # Public: append a new active grant and audit-log it. Returns the grant.
    param(
        [Parameter(Mandatory)][ValidateSet('workspace', 'skill', 'domain')][string]$Type,
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][string]$Label,
        [Parameter(Mandatory)][string]$Target,
        [ValidateSet('rw', 'ro')][string]$Mode,
        [string[]]$DependsOn = @()
    )
    $grants = @(Get-GrantsRaw)
    if ($grants | Where-Object { $_.id -eq $Id }) {
        throw "grant id '$Id' already exists; use a unique id."
    }
    $modeVal = $null
    if ($Type -eq 'workspace') { $modeVal = $Mode }
    $grant = [ordered]@{
        id         = $Id
        type       = $Type
        label      = $Label
        created_at = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ssK')
        mode       = $modeVal
        target     = $Target
        depends_on = @($DependsOn)
        active     = $true
    }
    $obj = [pscustomobject]$grant
    Save-GrantsRaw -Grants (@($grants) + $obj)
    Write-GrantAudit -Event 'grant.add' -Data @{ id = $Id; type = $Type; target = $Target; mode = $modeVal }
    return $obj
}

function Remove-Grant {
    # Public: mark a grant inactive (soft; preserves the audit trail) and
    # audit-log it. Returns $true if a grant changed, $false if none matched.
    # NOTE: this is deactivation, not physical deletion -- it is the ledger side
    # of a revoke. The Kill Switch does NOT call this (kill != revoke).
    param([Parameter(Mandatory)][string]$Id)
    $grants = @(Get-GrantsRaw)
    $match = $grants | Where-Object { $_.id -eq $Id }
    if (-not $match) { return $false }
    foreach ($g in $grants) { if ($g.id -eq $Id) { $g.active = $false } }
    Save-GrantsRaw -Grants $grants
    Write-GrantAudit -Event 'grant.remove' -Data @{ id = $Id }
    return $true
}

#===========================================================================
# TASK 1.2 -- Workspace grant / revoke engine (drvfs)
#===========================================================================

function ConvertTo-CanonicalPath {
    # Normalize + resolve reparse points (junctions/symlinks) so the deny list
    # validates the RESOLVED path, not the string the user typed. PS 5.1 exposes
    # .Target on FileSystemInfo (an ETS property) for links.
    param([Parameter(Mandatory)][string]$Path)
    $p = [System.IO.Path]::GetFullPath($Path)
    $seen = @{}
    for ($i = 0; $i -lt 40; $i++) {
        if (-not (Test-Path -LiteralPath $p)) { break }
        $item = Get-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue
        if ($null -eq $item) { break }
        $target = $null
        if ($item.PSObject.Properties.Name -contains 'Target') { $target = $item.Target }
        if ($target) {
            $t = @($target)[0]
            if (-not [System.IO.Path]::IsPathRooted($t)) {
                $t = Join-Path (Split-Path -Parent $p) $t
            }
            $t = [System.IO.Path]::GetFullPath($t)
            if ($seen.ContainsKey($t.ToLowerInvariant())) { break }  # loop guard
            $seen[$t.ToLowerInvariant()] = $true
            $p = $t
            continue
        }
        break
    }
    return $p.TrimEnd('\')
}

function Test-PathIsUnder {
    # Case-insensitive: is $Child equal to, or nested under, $Parent?
    param([string]$Child, [string]$Parent)
    if (-not $Child -or -not $Parent) { return $false }
    $c = $Child.TrimEnd('\').ToLowerInvariant()
    $p = $Parent.TrimEnd('\').ToLowerInvariant()
    if ($c -eq $p) { return $true }
    return $c.StartsWith($p + '\')
}

function Test-WorkspaceDenied {
    # Returns a rejection reason string if the RESOLVED path is denied, else $null.
    param([Parameter(Mandatory)][string]$ResolvedPath)

    # Exact-match denials (the roots themselves; sub-folders are fine).
    $exact = @()
    foreach ($d in [System.IO.DriveInfo]::GetDrives()) { $exact += $d.RootDirectory.FullName.TrimEnd('\') }
    if ($env:USERPROFILE) { $exact += $env:USERPROFILE.TrimEnd('\') }

    # Prefix denials (the whole tree is off-limits).
    $prefixes = @()
    foreach ($v in @($env:WINDIR, $env:ProgramData, $env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:APPDATA, $env:LOCALAPPDATA)) {
        if ($v) { $prefixes += $v.TrimEnd('\') }
    }
    if ($env:USERPROFILE) { $prefixes += (Join-Path $env:USERPROFILE 'AppData').TrimEnd('\') }
    if ($script:CF_InstallDir) { $prefixes += $script:CF_InstallDir.TrimEnd('\') }

    $rp = $ResolvedPath.TrimEnd('\')
    foreach ($e in $exact) {
        if ($rp.ToLowerInvariant() -eq $e.ToLowerInvariant()) {
            return "Refusing to grant '$rp': that is a drive root or your user-profile root. Grant a specific project folder instead (e.g. $($env:USERPROFILE)\Documents\my-project)."
        }
    }
    foreach ($pre in $prefixes) {
        if (Test-PathIsUnder -Child $rp -Parent $pre) {
            return "Refusing to grant '$rp': it is inside a protected system location ($pre). Grant a specific project folder outside Windows/Program Files/ProgramData/AppData and the ClawFactory install."
        }
    }
    return $null
}

function Get-WorkspaceWarnings {
    # Non-fatal advisories for OneDrive placeholder + UNC/mapped paths (Phase 0
    # BLOCKED items: OneDrive on-demand hydration and mapped drives untested).
    param([Parameter(Mandatory)][string]$ResolvedPath)
    $warn = @()
    if ($env:OneDrive -and (Test-PathIsUnder -Child $ResolvedPath -Parent $env:OneDrive.TrimEnd('\'))) {
        $warn += "Path is under OneDrive. On-demand (placeholder) files may fail or hang for the agent until hydrated; keep files 'Always keep on this device' if the agent needs them."
    }
    if ($ResolvedPath.StartsWith('\\')) {
        $warn += "UNC/network path: not validated in Phase 0 (no network drive was available to test). Reads may be slow or fail; prefer a local folder."
    } else {
        $drive = $null
        try { $drive = [System.IO.DriveInfo]::new($ResolvedPath.Substring(0,3)) } catch {}
        if ($drive -and $drive.DriveType -eq 'Network') {
            $warn += "Mapped network drive: untested in Phase 0. Reads may be slow or fail; prefer a local folder."
        }
    }
    return @($warn)
}

function New-WorkspaceSlug {
    # Deterministic slug: sanitized leaf name + short hash of the resolved path,
    # so the same folder always maps to the same /workspaces/<slug> (idempotency).
    param([Parameter(Mandatory)][string]$ResolvedPath)
    $leaf = Split-Path -Leaf $ResolvedPath
    if (-not $leaf) { $leaf = 'root' }
    $clean = ($leaf.ToLowerInvariant() -replace '[^a-z0-9]+', '-').Trim('-')
    if (-not $clean) { $clean = 'ws' }
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $bytes = $sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($ResolvedPath.ToLowerInvariant()))
    $sha.Dispose()
    $hash = -join ($bytes[0..3] | ForEach-Object { $_.ToString('x2') })
    return "$clean-$hash"
}

function Test-WslMountLive {
    # Is /workspaces/<slug> currently a live mountpoint?
    param([Parameter(Mandatory)][string]$Slug)
    $r = Invoke-ClawWslBash -User 'root' -Script "mountpoint -q '$script:CF_MountRoot/$Slug' && echo LIVE || echo DEAD"
    return ($r.StdOut.Trim() -eq 'LIVE')
}

function Grant-Workspace {
    # Mount exactly one Windows folder into WSL at /workspaces/<slug> and record
    # the grant. Idempotent: an already-active grant for the same resolved path
    # is a reported no-op, not a double mount. Returns the grant object.
    param(
        [Parameter(Mandatory)][string]$Path,
        [ValidateSet('rw', 'ro')][string]$Mode = 'rw'
    )
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Path does not exist: '$Path'."
    }
    $resolved = ConvertTo-CanonicalPath -Path $Path

    $deny = Test-WorkspaceDenied -ResolvedPath $resolved
    if ($deny) {
        Write-GrantAudit -Event 'workspace.denied' -Data @{ path = $resolved; reason = $deny }
        throw $deny
    }

    $warnings = Get-WorkspaceWarnings -ResolvedPath $resolved
    foreach ($w in $warnings) { Write-Warning $w }

    # Idempotency: already an active workspace grant for this resolved path?
    $existing = Get-ActiveGrants -Type workspace | Where-Object {
        (ConvertTo-CanonicalPath -Path $_.target) -ieq $resolved
    } | Select-Object -First 1
    if ($existing) {
        if (Test-WslMountLive -Slug $existing.id) {
            Write-Verbose "Already granted (mount live): $($existing.id)"
            return $existing
        }
        # Grant exists but mount is gone (stale) -> remount under the same slug.
        $slug = $existing.id
    } else {
        $slug = New-WorkspaceSlug -ResolvedPath $resolved
    }

    $winFwd = $resolved -replace '\\', '/'
    $roOpt = ''
    if ($Mode -eq 'ro') { $roOpt = ',ro' }
    $mountScript = @"
set -e
mkdir -p '$script:CF_MountRoot/$slug'
if mountpoint -q '$script:CF_MountRoot/$slug'; then echo ALREADY_MOUNTED; exit 0; fi
mount -t drvfs '$winFwd' '$script:CF_MountRoot/$slug' -o metadata,uid=1000,gid=1000$roOpt
mountpoint -q '$script:CF_MountRoot/$slug' && echo MOUNTED
"@
    $r = Invoke-ClawWslBash -User 'root' -Script $mountScript
    if ($r.ExitCode -ne 0) {
        Write-GrantAudit -Event 'workspace.mount_failed' -Data @{ path = $resolved; slug = $slug; stderr = $r.StdErr.Trim() }
        throw "Mount failed for '$resolved' (exit=$($r.ExitCode)): $($r.StdErr.Trim())"
    }

    if ($existing) {
        Write-GrantAudit -Event 'workspace.remounted' -Data @{ id = $slug; path = $resolved; mode = $Mode }
        return $existing
    }
    # Re-granting a previously-REVOKED path: the slug is deterministic, so a prior
    # (inactive) ledger record already owns this id. Reactivate it in place rather
    # than colliding with Add-Grant's unique-id guard.
    $prior = Get-GrantsRaw | Where-Object { $_.id -eq $slug } | Select-Object -First 1
    if ($prior) {
        $all = @(Get-GrantsRaw)
        foreach ($g in $all) { if ($g.id -eq $slug) { $g.active = $true; $g.mode = $Mode; $g.target = $resolved } }
        Save-GrantsRaw -Grants $all
        Write-GrantAudit -Event 'workspace.reactivated' -Data @{ id = $slug; path = $resolved; mode = $Mode }
        return ($all | Where-Object { $_.id -eq $slug } | Select-Object -First 1)
    }
    $label = Split-Path -Leaf $resolved
    $grant = Add-Grant -Type workspace -Id $slug -Label $label -Target $resolved -Mode $Mode
    Write-GrantAudit -Event 'workspace.mounted' -Data @{ id = $slug; path = $resolved; mode = $Mode; mountpoint = "$script:CF_MountRoot/$slug" }
    return $grant
}

function Revoke-Workspace {
    # Unmount + remove the mountpoint + mark the grant inactive. Succeeds even if
    # the mount is already gone (stale state) -- reports, never throws.
    param([Parameter(Mandatory)][string]$Id)
    $grant = Get-GrantsRaw | Where-Object { $_.id -eq $Id -and $_.type -eq 'workspace' } | Select-Object -First 1
    if (-not $grant) {
        Write-Warning "No workspace grant with id '$Id'."
        return $false
    }
    $unmountScript = @"
if mountpoint -q '$script:CF_MountRoot/$Id'; then
    umount '$script:CF_MountRoot/$Id' && echo UNMOUNTED || echo UMOUNT_FAILED
else
    echo NOT_MOUNTED
fi
rmdir '$script:CF_MountRoot/$Id' 2>/dev/null && echo RMDIR_OK || echo RMDIR_SKIP
"@
    $r = Invoke-ClawWslBash -User 'root' -Script $unmountScript
    Remove-Grant -Id $Id | Out-Null
    Write-GrantAudit -Event 'workspace.revoked' -Data @{ id = $Id; detail = $r.StdOut.Trim() }
    return $true
}

function Test-Grants {
    # For every ACTIVE workspace grant, report whether its Windows path still
    # exists and whether the mount is live. Phase 2 UI uses this to flag a grant
    # as 'broken' with repair/revoke choices.
    $out = @()
    foreach ($g in (Get-ActiveGrants -Type workspace)) {
        $pathExists = Test-Path -LiteralPath $g.target
        $mountLive  = Test-WslMountLive -Slug $g.id
        $state = 'ok'
        if (-not $pathExists) { $state = 'broken-path' }
        elseif (-not $mountLive) { $state = 'not-mounted' }
        $out += [pscustomobject]@{
            id         = $g.id
            label      = $g.label
            target     = $g.target
            mode       = $g.mode
            mountpoint = "$script:CF_MountRoot/$($g.id)"
            pathExists = $pathExists
            mountLive  = $mountLive
            state      = $state
        }
    }
    return @($out)
}

#===========================================================================
# TASK 1.3 -- Launcher replay + Kill Switch
#===========================================================================

function Invoke-GrantReplay {
    # Replay every ACTIVE workspace grant after a WSL restart: recreate the
    # mountpoint and remount. A grant whose Windows path has vanished is marked
    # broken (logged) and SKIPPED -- never silently dropped, never fatal.
    # Returns a summary object.
    $replayed = 0; $broken = 0; $skipped = 0
    foreach ($g in (Get-ActiveGrants -Type workspace)) {
        if (-not (Test-Path -LiteralPath $g.target)) {
            $broken++
            Write-GrantAudit -Event 'workspace.replay_broken' -Data @{ id = $g.id; path = $g.target }
            continue
        }
        if (Test-WslMountLive -Slug $g.id) { $skipped++; continue }
        $winFwd = ($g.target -replace '\\', '/')
        $roOpt = ''
        if ($g.mode -eq 'ro') { $roOpt = ',ro' }
        $script = @"
set -e
mkdir -p '$script:CF_MountRoot/$($g.id)'
mount -t drvfs '$winFwd' '$script:CF_MountRoot/$($g.id)' -o metadata,uid=1000,gid=1000$roOpt
mountpoint -q '$script:CF_MountRoot/$($g.id)' && echo OK
"@
        $r = Invoke-ClawWslBash -User 'root' -Script $script
        if ($r.ExitCode -eq 0) {
            $replayed++
            Write-GrantAudit -Event 'workspace.replayed' -Data @{ id = $g.id; path = $g.target }
        } else {
            $broken++
            Write-GrantAudit -Event 'workspace.replay_failed' -Data @{ id = $g.id; path = $g.target; stderr = $r.StdErr.Trim() }
        }
    }
    return [pscustomobject]@{ replayed = $replayed; broken = $broken; alreadyMounted = $skipped }
}

function Invoke-GrantKillUnmount {
    # Kill Switch helper: unmount EVERY active workspace mount so the agent can
    # no longer see any of the user's files. Grants STAY active in the ledger
    # (kill != revoke) so a later start replays them. Returns count unmounted.
    $count = 0
    foreach ($g in (Get-ActiveGrants -Type workspace)) {
        $r = Invoke-ClawWslBash -User 'root' -Script "if mountpoint -q '$script:CF_MountRoot/$($g.id)'; then umount '$script:CF_MountRoot/$($g.id)' && echo UNMOUNTED; fi"
        if ($r.StdOut.Trim() -eq 'UNMOUNTED') {
            $count++
            Write-GrantAudit -Event 'workspace.kill_unmounted' -Data @{ id = $g.id }
        }
    }
    return $count
}

#===========================================================================
# TASK 1.4 -- Spend governor: metering + turn-gate
#===========================================================================

function Get-GovernorConfig {
    # Caps config in ProgramData\ClawFactory\governor.json. Created with defaults
    # if absent. Editable: daily_cap_usd, monthly_cap_usd, warn_pct.
    $defaults = [ordered]@{ daily_cap_usd = 5.0; monthly_cap_usd = 50.0; warn_pct = 80 }
    if (-not (Test-Path -LiteralPath $script:CF_GovernorFile)) {
        if (-not (Test-Path -LiteralPath $script:CF_Dir)) { New-Item -ItemType Directory -Path $script:CF_Dir -Force | Out-Null }
        ($defaults | ConvertTo-Json) | Set-Content -LiteralPath $script:CF_GovernorFile -Encoding UTF8
        return [pscustomobject]$defaults
    }
    try {
        $cfg = Get-Content -LiteralPath $script:CF_GovernorFile -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        throw "governor.json unparseable ($($_.Exception.Message)); fix or remove $script:CF_GovernorFile."
    }
    return $cfg
}

function Get-Spend {
    # Meter sourced from OpenClaw's native `gateway usage-cost --json`. Returns
    # @{ today; month; ok }. On ANY failure (command missing, non-zero, schema
    # change, unparseable) returns ok=$false and NULL amounts -- $0.00 is never
    # faked from a broken data source (zero must be distinguishable from unknown).
    $r = Invoke-ClawWslBash -User $script:CF_WslUser -Script 'openclaw gateway usage-cost --json --days 400 2>/dev/null'
    if ($r.ExitCode -ne 0 -or -not $r.StdOut.Trim()) {
        return @{ today = $null; month = $null; ok = $false; error = "usage-cost failed (exit=$($r.ExitCode))" }
    }
    try {
        $data = $r.StdOut | ConvertFrom-Json
    } catch {
        return @{ today = $null; month = $null; ok = $false; error = 'usage-cost JSON unparseable' }
    }
    if (-not ($data.PSObject.Properties.Name -contains 'daily')) {
        return @{ today = $null; month = $null; ok = $false; error = 'usage-cost schema changed (no .daily)' }
    }
    $todayStr = (Get-Date).ToString('yyyy-MM-dd')
    $monthPfx = (Get-Date).ToString('yyyy-MM')
    $today = 0.0; $month = 0.0
    foreach ($d in @($data.daily)) {
        if (-not ($d.PSObject.Properties.Name -contains 'totalCost')) { continue }
        $cost = [double]$d.totalCost
        if ($d.date -eq $todayStr) { $today += $cost }
        if (("" + $d.date).StartsWith($monthPfx)) { $month += $cost }
    }
    return @{ today = $today; month = $month; ok = $true }
}

function Get-SpendStatus {
    # Public (Phase 2 cost meter). Returns:
    #   { today; month; caps; pct_of_cap; state }
    # state = 'ok' | 'warning' | 'blocked' | 'unknown'
    #   unknown = meter data source broke (NOT the same as $0.00)
    #   blocked = today >= daily cap OR month >= monthly cap
    #   warning = either >= warn_pct of its cap
    $cfg = Get-GovernorConfig
    $spend = Get-Spend
    $caps = [pscustomobject]@{
        daily_cap_usd   = [double]$cfg.daily_cap_usd
        monthly_cap_usd = [double]$cfg.monthly_cap_usd
        warn_pct        = [int]$cfg.warn_pct
    }
    if (-not $spend.ok) {
        return [pscustomobject]@{
            today = $null; month = $null; caps = $caps; pct_of_cap = $null
            state = 'unknown'; error = $spend.error
        }
    }
    $pctDaily = 0.0; $pctMonth = 0.0
    if ($caps.daily_cap_usd -gt 0)   { $pctDaily = 100.0 * $spend.today / $caps.daily_cap_usd }
    if ($caps.monthly_cap_usd -gt 0) { $pctMonth = 100.0 * $spend.month / $caps.monthly_cap_usd }
    $pct = [Math]::Round([Math]::Max($pctDaily, $pctMonth), 1)
    $state = 'ok'
    if ($spend.today -ge $caps.daily_cap_usd -or $spend.month -ge $caps.monthly_cap_usd) {
        $state = 'blocked'
    } elseif ($pct -ge $caps.warn_pct) {
        $state = 'warning'
    }
    return [pscustomobject]@{
        today      = [Math]::Round($spend.today, 4)
        month      = [Math]::Round($spend.month, 4)
        caps       = $caps
        pct_of_cap = $pct
        state      = $state
    }
}

function Test-TurnAllowed {
    # Turn-gate. Returns @{ allowed; state; message }. Enforcement is at TURN
    # granularity, not per-call: an in-flight turn can overshoot the cap. This is
    # stated plainly and must not be presented as a hard per-call guarantee.
    $s = Get-SpendStatus
    if ($s.state -eq 'blocked') {
        $msg = "Spend cap reached. Today $([string]::Format('{0:C2}',$s.today)) / cap $([string]::Format('{0:C2}',$s.caps.daily_cap_usd)); this month $([string]::Format('{0:C2}',$s.month)) / cap $([string]::Format('{0:C2}',$s.caps.monthly_cap_usd)). New turns are blocked until spend falls below the cap or you raise it in $script:CF_GovernorFile. (A turn already running can overshoot; the gate stops NEW turns, not in-flight calls.)"
        return @{ allowed = $false; state = 'blocked'; message = $msg }
    }
    if ($s.state -eq 'unknown') {
        # Fail-safe policy: if the meter is broken we cannot prove we are under
        # the cap. Default to BLOCK and say so, rather than silently allowing.
        return @{ allowed = $false; state = 'unknown'; message = "Spend meter unavailable ($($s.error)). Blocking new turns until the meter is readable (fail-safe). Check 'openclaw gateway usage-cost --json' in WSL." }
    }
    return @{ allowed = $true; state = $s.state; message = 'within budget' }
}

function Invoke-GatedAgentTurn {
    # The turn-gate wrap. Phase 2's Studio (chat.ts) should route its CLI turn
    # (currently `openclaw agent --json --message ...` in
    # runOpenClawAgentTurn) THROUGH this function instead of spawning openclaw
    # directly. If blocked, it refuses WITHOUT launching the turn.
    param(
        [Parameter(Mandatory)][string]$Agent,
        [Parameter(Mandatory)][string]$Message
    )
    $gate = Test-TurnAllowed
    if (-not $gate.allowed) {
        Write-GrantAudit -Event 'governor.turn_blocked' -Data @{ agent = $Agent; state = $gate.state }
        return [pscustomobject]@{ blocked = $true; state = $gate.state; message = $gate.message; output = $null }
    }
    $enc = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Message))
    $r = Invoke-ClawWslBash -User $script:CF_WslUser -Script "openclaw agent --agent '$Agent' --json --message `"`$(echo '$enc' | base64 -d)`""
    return [pscustomobject]@{ blocked = $false; state = $gate.state; message = 'ok'; output = $r.StdOut; exit = $r.ExitCode }
}
