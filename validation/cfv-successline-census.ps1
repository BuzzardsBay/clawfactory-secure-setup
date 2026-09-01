<#
  cfv-successline-census.ps1 -- enumerate every place the harness announces an
  outcome that its own code path cannot have established.

  THE DEFECT BEING COUNTED
  ------------------------
  docs/session_reports/2026-08-31_systemd_reboot_persistence_closeout.md 4.7 item 11:

      "A SAS expiry built from local time and labelled Z. Ten uploads returned
       AuthenticationFailed, and the script printed `uploaded <file>` for every
       one of them, because the success line sat unconditionally after the call.
       That is switch-provider.ps1:349's defect, reproduced by this session, in
       this session."

  The shape, not the instance: a statement that REPORTS an outcome, placed after a
  call whose failure does not prevent it from running. Under
  $ErrorActionPreference = 'Continue' -- which every driver in this tree sets at
  the top -- a failing Invoke-WebRequest writes an error and execution continues
  to the next line, so the success line prints over a failure.

  WHY THIS IS AN AST INSTRUMENT AND NOT A GREP
  --------------------------------------------
  The preamble: "Where the question is enumeration rather than detection, parse
  the AST instead of matching text." A grep for `Write-Output "uploaded` finds the
  instances whose success word someone already thought of.

  AND WHY THE AST ALONE IS NOT ENOUGH, WHICH IS THE PART THAT MATTERS
  -------------------------------------------------------------------
  The known live instances -- interim-v145-runner.ps1:171 and :195 -- are inside
  a HERE-STRING. To the parser of that file they are a string literal, not code,
  so an AST walk of the driver files is structurally blind to exactly the place
  the defect was found. A census built that way would report the tree clean and
  the report would be wrong in the same way the code was.

  So this walks two layers: the file's own AST, and then the CONTENT of every
  string literal that parses as PowerShell, re-parsed and walked with the same
  rule. Findings from the second layer carry both line numbers.

  CALIBRATION (an audit regex is itself a probe)
  ----------------------------------------------
  -Calibrate builds three fixtures and asserts the instrument's answer on each
  BEFORE any real file is scanned:

    CANARY-A  an unguarded success line at file level            MUST be found
    CANARY-B  the identical unguarded success line INSIDE a      MUST be found
              here-string, with backtick-escaped variables --
              shaped like the instance that actually shipped
    CONTROL   the same call and the same success word, with the  MUST NOT be found
              outcome checked between them

  CANARY-B is the load-bearing one. A canary only certifies the pattern against
  the shape of the canary, and the shape this instrument is afraid of missing is
  the nested one. CONTROL is the other direction: an instrument that flagged
  everything would pass a one-sided test.

  Exit 0 = calibrated and clean. Exit 1 = findings. Exit 4 = the instrument failed
  its own calibration, in which case its findings mean nothing and are not printed.
#>
[CmdletBinding()]
param(
    [string[]]$Path = @('validation', 'scripts'),
    [switch]$Calibrate,
    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent (Split-Path -Parent $PSCommandPath)

# Words that ASSERT an outcome. Deliberately not "done"/"ok" alone, which appear
# in progress chatter; each of these claims a thing happened.
$SuccessWords = @(
    'uploaded','downloaded','staged','written','wrote','copied','created','registered',
    'deleted','removed','installed','published','confirmed','succeeded','success',
    'complete','completed','saved','armed','applied','sent','retrieved'
)

# Calls whose failure does not, on its own, prevent the next statement running.
$RiskyCommands = @(
    'Invoke-WebRequest','Invoke-RestMethod','az','az.cmd','Copy-Item','Move-Item',
    'Remove-Item','New-Item','Set-Content','Add-Content','Out-File','Start-Process',
    'Register-ScheduledTask','Unregister-ScheduledTask','Expand-Archive','Compress-Archive',
    'Set-ItemProperty','New-ItemProperty','curl','curl.exe','robocopy','xcopy'
)

# Anything that CHECKS THE OUTCOME OF THE PRECEDING CALL. One of these between the
# call and the report means the report is earned.
#
# Test-Path and Get-Item are deliberately NOT here, and that omission is the whole
# lesson of this instrument's second calibration. `if (Test-Path $source) { upload;
# Write-Output "uploaded" }` checks that the SOURCE existed. It says nothing about
# whether the upload succeeded -- and it is the exact wrapper around the two live
# instances at interim-v145-runner.ps1:171 and :195. With Test-Path treated as a
# guard, this instrument reported those two files clean: a false negative on the
# precise defect it was built to find. A canary only certifies the pattern against
# the shape of the canary, and the first canary lacked the wrapper the real one had.
$GuardOutcome = '\$LASTEXITCODE|\$\?|StatusCode|contentLength|\bthrow\b|-ne\s+0|-eq\s+0|\.Ok\b|\bexit\s+\d|\bCompare-|-match|-eq\s+\$'

# A report that READS THE ARTEFACT BACK inside its own statement is earned, because
# the read-back is the check. `Write-Output "dropped $((Get-Item $p).Length)"` fails
# loudly if the drop failed.
$GuardInline = $GuardOutcome + '|\bTest-Path\b|\bGet-Item\b'

function Get-StringValue($ast) {
    if ($ast -is [System.Management.Automation.Language.StringConstantExpressionAst]) { return $ast.Value }
    if ($ast -is [System.Management.Automation.Language.ExpandableStringExpressionAst]) { return $ast.Value }
    return $null
}

function Test-IsSuccessReport($cmdAst) {
    $name = $cmdAst.GetCommandName()
    if ($name -notin @('Write-Output','Write-Host','Say','Write-Information')) { return $null }
    foreach ($el in $cmdAst.CommandElements) {
        $v = Get-StringValue $el
        if ($null -eq $v) { continue }
        foreach ($w in $SuccessWords) {
            # Word-boundary match so "incomplete" does not read as "complete" and
            # "unconfirmed" does not read as "confirmed".
            if ($v -match "(?i)(^|[^A-Za-z])$w([^A-Za-z]|$)") { return $v }
        }
    }
    return $null
}

function Get-RiskyName($stmtAst) {
    $cmds = $stmtAst.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true)
    foreach ($c in $cmds) {
        $n = $c.GetCommandName()
        if ($n -and ($RiskyCommands -contains $n)) {
            # -ErrorAction Stop makes the failure terminating, so a following
            # statement really cannot run after it. That is a guard.
            if ($c.Extent.Text -match '(?i)-ErrorAction\s+Stop') { return $null }
            return $n
        }
    }
    return $null
}

function Get-OwningBlock($node) {
    <# The statement block a command actually belongs to. Without this, walking a
       statement with FindAll descends into nested blocks and attributes an inner
       command to the OUTER block's predecessor -- which is precisely how the
       calibration's guarded CONTROL was flagged on this instrument's first run.
       The inner block gets its own iteration; it must not also be judged here. #>
    $p = $node.Parent
    while ($p) {
        if ($p -is [System.Management.Automation.Language.StatementBlockAst] -or
            $p -is [System.Management.Automation.Language.NamedBlockAst]) { return $p }
        $p = $p.Parent
    }
    return $null
}

function Test-GuardedByAncestor($node) {
    <# A report inside `if ($r.StatusCode -eq 201) { ... }` IS earned: the outcome
       was checked. Walk the ancestor chain for a conditional or a catch whose own
       text checks an outcome. #>
    $p = $node.Parent
    while ($p) {
        if ($p -is [System.Management.Automation.Language.IfStatementAst]) {
            foreach ($clause in $p.Clauses) { if ($clause.Item1.Extent.Text -match $GuardOutcome) { return $true } }
        }
        if ($p -is [System.Management.Automation.Language.CatchClauseAst]) { return $true }
        $p = $p.Parent
    }
    return $false
}

function Find-InAst {
    <# Walks every statement block, looking for [risky call] followed by
       [success report] with no outcome check between them. #>
    param($RootAst, [string]$File, [int]$LineOffset = 0, [string]$Context = '')
    $findings = @()

    # Collect each block ONCE. The root ScriptBlockAst's statements live in its
    # NamedBlockAst children, which FindAll already returns, so adding the root
    # again double-counted every top-level finding.
    $blocks = @($RootAst.FindAll({ param($n)
        $n -is [System.Management.Automation.Language.StatementBlockAst] -or
        $n -is [System.Management.Automation.Language.NamedBlockAst] }, $true))

    foreach ($b in $blocks) {
        $stmts = @($b.Statements)
        for ($i = 1; $i -lt $stmts.Count; $i++) {
            $cmds = @($stmts[$i].FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true))
            foreach ($c in $cmds) {
                # Only judge commands this block actually owns.
                if ((Get-OwningBlock $c) -ne $b) { continue }
                $msg = Test-IsSuccessReport $c
                if (-not $msg) { continue }
                if (Test-GuardedByAncestor $c) { continue }
                # Walk backwards over at most two statements. More than that and
                # the association is too weak to call a defect.
                $risky = $null; $guarded = $false
                for ($k = $i - 1; $k -ge 0 -and $k -ge $i - 2; $k--) {
                    $prev = $stmts[$k]
                    if ($prev.Extent.Text -match $GuardOutcome) { $guarded = $true; break }
                    $rn = Get-RiskyName $prev
                    if ($rn) { $risky = $rn; break }
                }
                # An inline check in the reporting statement itself also counts.
                if ($c.Extent.Text -match $GuardInline) { $guarded = $true }
                if ($risky -and -not $guarded) {
                    $findings += [pscustomobject]@{
                        File       = $File
                        Line       = $c.Extent.StartLineNumber + $LineOffset
                        Context    = $Context
                        RiskyCall  = $risky
                        Report     = ($msg -replace '\s+',' ')
                        Statement  = ($c.Extent.Text -replace '\s+',' ')
                    }
                }
            }
        }
    }
    return $findings
}

function Find-InFileText {
    <# Layer 1: the file's own AST. Layer 2: the content of every string literal
       that parses as PowerShell and contains a command. #>
    param([string]$File, [string]$Text)
    $tok = $null; $errs = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseInput($Text, [ref]$tok, [ref]$errs)
    $all = @(Find-InAst -RootAst $ast -File $File -Context 'file')

    $strings = @($ast.FindAll({ param($n)
        $n -is [System.Management.Automation.Language.StringConstantExpressionAst] -or
        $n -is [System.Management.Automation.Language.ExpandableStringExpressionAst] }, $true))
    foreach ($s in $strings) {
        $v = Get-StringValue $s
        if ($null -eq $v -or $v.Length -lt 40) { continue }
        if ($v -notmatch '(?i)Write-Output|Write-Host|Invoke-WebRequest|\baz\b') { continue }
        # A here-string that is a PAYLOAD is PowerShell for another machine. The
        # driver's own parser saw a string; this parses it as what it will become.
        # Backtick-escaped sigils are what the far side will see un-escaped, so
        # they are unescaped here before parsing, or the payload does not parse.
        $inner = $v -replace '`\$', '$' -replace '`"', '"'
        $t2 = $null; $e2 = $null
        $a2 = [System.Management.Automation.Language.Parser]::ParseInput($inner, [ref]$t2, [ref]$e2)
        if ($e2 -and $e2.Count -gt 4) { continue }   # not really PowerShell
        $offset = $s.Extent.StartLineNumber - 1
        $all += @(Find-InAst -RootAst $a2 -File $File -LineOffset $offset `
                    -Context "inside a string literal beginning at line $($s.Extent.StartLineNumber)")
    }
    return $all
}

# ---------------------------------------------------------------------------
# CALIBRATION. Runs first, always. If the instrument cannot find a defect it was
# handed, its report on the real tree is not permitted to be believed.
# ---------------------------------------------------------------------------
function Invoke-Calibration {
    $dir = Join-Path $env:TEMP "cfv-successcensus-$PID"
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $results = @()

    # CANARY-A: the plain shape, at file level.
    $a = @'
$ErrorActionPreference = 'Continue'
Invoke-WebRequest -Uri $u -Method Put -InFile $p -UseBasicParsing | Out-Null
Write-Output "uploaded $p"
'@
    # CANARY-B: THE SHAPE THAT ACTUALLY SHIPPED, copied structurally from
    # interim-v145-runner.ps1:167-172. Inside a here-string payload, with
    # backtick-escaped sigils, inside a foreach, AND inside an
    # `if (Test-Path $source)` precondition.
    #
    # The first version of this canary omitted the Test-Path wrapper. With it
    # omitted the instrument passed calibration and then reported both live
    # instances clean, because Test-Path was being read as an outcome check. The
    # canary must look like the thing you are afraid of missing, not like the
    # thing you already know is there -- so the wrapper is here now, and the two
    # real instances are what this fixture is a model of.
    $b = @'
$body = @"
foreach (`$pair in @(@('C:\a.txt','a.txt'))) {
    if (Test-Path `$pair[0]) {
        Invoke-WebRequest -Uri `$u -Method Put -InFile `$pair[0] -Headers @{ 'x-ms-blob-type'='BlockBlob' } -UseBasicParsing | Out-Null
        Write-Output "uploaded `$(`$pair[1])"
    }
}
"@
'@
    # CONTROL 1: the same call, the same success word, with the outcome checked.
    # MUST NOT be flagged, or the instrument is not discriminating.
    $c = @'
$ErrorActionPreference = 'Continue'
$r = Invoke-WebRequest -Uri $u -Method Put -InFile $p -UseBasicParsing
if ($r.StatusCode -eq 201) { Write-Output "uploaded $p" } else { Write-Output "upload FAILED $p" }
'@
    # CONTROL 2: the exit-code idiom this tree uses correctly in a dozen places.
    # MUST NOT be flagged. Without this the instrument could pass by flagging
    # every report that follows any call, which would be one-sided.
    $d = @'
$ErrorActionPreference = 'Continue'
az storage blob upload --account-name $sa --name $n --file $p --overwrite --output none
if ($LASTEXITCODE -ne 0) { throw "upload failed" }
Say "  uploaded $n"
'@
    foreach ($fx in @(@('canaryA', $a, $true), @('canaryB', $b, $true), @('control', $c, $false), @('control2', $d, $false))) {
        $f = Join-Path $dir "$($fx[0]).ps1"
        [IO.File]::WriteAllText($f, $fx[1], (New-Object Text.UTF8Encoding($false)))
        $hits = @(Find-InFileText -File $f -Text $fx[1])
        $found = ($hits.Count -gt 0)
        $results += [pscustomobject]@{
            Fixture  = $fx[0]
            Expected = $(if ($fx[2]) { 'FOUND' } else { 'NOT FOUND' })
            Actual   = $(if ($found) { 'FOUND' } else { 'NOT FOUND' })
            Pass     = ($found -eq $fx[2])
            Detail   = (($hits | ForEach-Object { "line $($_.Line) $($_.Context): $($_.Statement)" }) -join ' | ')
        }
    }
    return $results
}

$cal = Invoke-Calibration
if (-not $Quiet) {
    Write-Host ''
    Write-Host '=== CALIBRATION: the instrument against rigged inputs ===' -ForegroundColor Cyan
    foreach ($r in $cal) {
        $c = if ($r.Pass) { 'Green' } else { 'Red' }
        Write-Host ("  [{0}] {1,-8} expected {2,-9} got {3,-9} {4}" -f $(if ($r.Pass) { 'PASS' } else { 'FAIL' }), $r.Fixture, $r.Expected, $r.Actual, $r.Detail) -ForegroundColor $c
    }
}
if (@($cal | Where-Object { -not $_.Pass }).Count -gt 0) {
    Write-Host ''
    Write-Host 'INSTRUMENT FAILED ITS OWN CALIBRATION. Its findings are withheld, because a pattern that cannot find a planted defect cannot certify a tree clean.' -ForegroundColor Red
    exit 4
}
if (-not $Quiet) { Write-Host '  calibration passed: the instrument finds the plain shape, finds the nested shape, and leaves the guarded control alone.' -ForegroundColor Green }

if ($Calibrate) { exit 0 }

# ---------------------------------------------------------------------------
# THE CENSUS
# ---------------------------------------------------------------------------
$files = @()
foreach ($p in $Path) {
    $full = if ([IO.Path]::IsPathRooted($p)) { $p } else { Join-Path $RepoRoot $p }
    if (Test-Path $full -PathType Container) { $files += @(Get-ChildItem $full -Filter *.ps1 -Recurse -File) }
    elseif (Test-Path $full) { $files += @(Get-Item $full) }
}
$files = @($files | Where-Object { $_.Name -ne 'cfv-successline-census.ps1' } | Sort-Object FullName)

Write-Host ''
Write-Host "=== CENSUS over $($files.Count) files ===" -ForegroundColor Cyan
$all = @()
foreach ($f in $files) {
    $txt = Get-Content $f.FullName -Raw
    if (-not $txt) { continue }
    $all += @(Find-InFileText -File $f.FullName -Text $txt)
}

if ($all.Count -eq 0) {
    Write-Host "  no instances found in $($files.Count) files." -ForegroundColor Green
} else {
    foreach ($g in ($all | Group-Object File)) {
        Write-Host ''
        Write-Host ("  {0}" -f ($g.Name -replace [regex]::Escape($RepoRoot + '\'), '')) -ForegroundColor Yellow
        foreach ($h in ($g.Group | Sort-Object Line)) {
            Write-Host ("    line {0,-5} [{1}] after {2,-20} :: {3}" -f $h.Line, $h.Context, $h.RiskyCall, $h.Statement)
        }
    }
}
# ---------------------------------------------------------------------------
# ADJUDICATION. Recorded, never SUPPRESSED. The census still counts and prints
# every candidate; this table says what was decided about each and why, so a
# later cycle re-reads a judgement instead of re-making it. A suppression list
# would let a real finding be retired by editing a file, which is the opposite of
# what this instrument is for.
# ---------------------------------------------------------------------------
$Adjudications = @(
    @{ File = 'scripts\azure-validate.ps1';            Line = 231; Verdict = 'REAL, NOT FIXED';
       Why  = 'Real instance. This driver is FORBIDDEN by PROMPT 15: it arms auto-logon by resetting the admin account (az vm user update at :449 writes DefaultPassword). Repairing an instrument nobody may run would make it look blessed -- the same argument the v1.4.4 close-out made about its stale digest, which was deliberately left as a brake.' }
    @{ File = 'scripts\azure-validate.ps1';            Line = 238; Verdict = 'REAL, NOT FIXED';  Why = 'Same file, same reason as line 231.' }
    @{ File = 'validation\interim-v120-validate.ps1';  Line = 318; Verdict = 'REAL, NOT FIXED';
       Why  = 'Real instance. Forbidden driver: az vm user update at :436, DefaultPassword at :516.' }
    @{ File = 'validation\job3-validate.ps1';          Line = 250; Verdict = 'REAL, NOT FIXED';
       Why  = 'Real instance, and the worst-shaped of the four: "uploaded $($f.n)" with no read-back at all. Forbidden driver: az vm user update at :275, DefaultPassword at :313.' }
    @{ File = 'validation\interim-v146-runner.ps1';    Line = 193; Verdict = 'FALSE POSITIVE';
       Why  = 'The success word "deleted" appears inside a quoted aphorism in a section banner -- "it said deleted is not the same claim as it is gone" -- not in a claim about an outcome. The instrument matches words, and this is the price of that; recorded rather than tuned away, because narrowing the word list to exclude it would also narrow it against real reports.' }
)
Write-Host ''
Write-Host '=== ADJUDICATION of the surviving candidates ===' -ForegroundColor Cyan
foreach ($a in $Adjudications) {
    $matched = @($all | Where-Object { $_.File -like "*$($a.File)" -and $_.Line -eq $a.Line })
    $state = if ($matched.Count -gt 0) { 'still present' } else { 'NO LONGER PRESENT -- re-adjudicate' }
    Write-Host ("  {0}:{1}  {2}  [{3}]" -f $a.File, $a.Line, $a.Verdict, $state) -ForegroundColor $(if ($matched.Count -gt 0) { 'DarkGray' } else { 'Yellow' })
    Write-Host ("      {0}" -f $a.Why) -ForegroundColor DarkGray
}
$unadjudicated = @($all | Where-Object { $h = $_; -not ($Adjudications | Where-Object { $h.File -like "*$($_.File)" -and $h.Line -eq $_.Line }) })
Write-Host ''
Write-Host ("UNADJUDICATED candidates: {0}" -f $unadjudicated.Count) -ForegroundColor $(if ($unadjudicated.Count -gt 0) { 'Red' } else { 'Green' })
foreach ($u in $unadjudicated) { Write-Host ("  {0}:{1} :: {2}" -f $u.File, $u.Line, $u.Statement) -ForegroundColor Red }

Write-Host ''
Write-Host ("CENSUS RESULT: {0} candidate instance(s) across {1} files. Files scanned: {2}." -f $all.Count, @($all | Group-Object File).Count, $files.Count)
$all | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $env:TEMP "cfv-successline-census.json")
Write-Host "Machine-readable copy: $(Join-Path $env:TEMP 'cfv-successline-census.json')"
exit $(if ($all.Count -gt 0) { 1 } else { 0 })
