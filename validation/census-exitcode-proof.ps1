#requires -Version 5.1
<#
  census-exitcode-proof.ps1 -- the exit-code-as-proof census.

  WHY THIS FILE IS COMMITTED. It is a measurement, so its numbers have to be
  re-derivable rather than believed. Written 2026-08-30 after the first external
  install failure, whose second defect (D2) was
  `Install-WslDistroWithFallback` accepting `$rInst.ExitCode -eq 0` as proof that
  a Linux distro existed. The question this answers is: where else.

  Usage:
      .\census-exitcode-proof.ps1 -Path C:\...\setup.ps1
      .\census-exitcode-proof.ps1 -Path (Get-ChildItem resources\*.ps1).FullName

  It ENUMERATES. It does not adjudicate. Every hit still has to be read and
  classified -- verified / unverified-but-harmless / unverified-and-load-bearing.
  On setup.ps1 at commit dd03fa1 it reported 65 hits, of which 16 were false
  positives of the taint model and 1 was in dead code. The adjudication of the
  remaining 48 is in
  docs/session_reports/2026-08-30_pre_v145_groundwork_closeout.md section 3.

  CALIBRATION, run 2026-08-30 against setup.ps1 itself, per the PROMPT 15 clause
  "AN AUDIT REGEX IS ITSELF A PROBE". Six canaries were planted in shapes the
  real file does not contain, plus one clean control that must NOT be reported.
  setup.ps1 was restored afterwards and proved byte-identical by sha256
  (26e1593d..., 214311 bytes), NOT by `git status`, which cannot see a
  line-ending rewrite under core.autocrlf=true.

      C1  if (0 -eq $p.ExitCode)                 reversed operands   FOUND
      C2  & cmd.exe /c "exit 0"; if ($?)         PowerShell $?       FOUND
      C3  switch ($p.ExitCode) { 0 { ... } }     switch condition    FOUND
      C4  $s = @{ rc = $p.ExitCode }; $s.rc -eq 0  property bag      FOUND
      C5  rc written to a file, read back, tested                    MISSED
      C6  rc passed across a parameter binding                       MISSED
      D1  if ($cName -eq "widget")               clean control   NOT REPORTED

  Totals moved 65 -> 69 with C1-C4 planted and stayed at 65 with C5-C6 planted,
  so the four finds and the two misses are both exact and the clean control did
  not inflate the count. C5 and C6 are the measured limit of the instrument: it
  follows variables and function returns, and it does not follow a value across
  the filesystem or across a parameter binding. It also cannot see intent -- a
  site it classifies as a hit may be perfectly sound (a `setpriv` permission
  probe's exit code IS the state), and only reading it settles that.

  Enumerates, by AST rather than by text match, every decision site in a PowerShell
  file whose condition is derived from an exit code, a process return value, or a
  function return that carries one.

  Taint model:
    seed   : $LASTEXITCODE, $?, any member access named ExitCode
    level2 : a variable assigned an expression containing a seed
    level3 : a variable assigned a call to a function whose own returns are tainted
             (fixed point, iterated to convergence)

  Reports every IfStatementAst clause, WhileStatementAst, DoWhile/DoUntil and ternary
  whose condition contains a tainted expression, with the enclosing function and the
  first statement of the taken branch.

  Also reports, separately, every function whose return value is a bare status token
  (string/bool literal) -- "a return value used as evidence".
#>
param(
    [Parameter(Mandatory)][string[]]$Path
)

$ErrorActionPreference = 'Stop'

function Get-Ast {
    param([string]$File)
    $tokens = $null; $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($File, [ref]$tokens, [ref]$errors)
    if ($errors -and $errors.Count -gt 0) {
        Write-Host "PARSE ERRORS in $File :" -ForegroundColor Red
        foreach ($e in $errors) { Write-Host ("  {0}: {1}" -f $e.Extent.StartLineNumber, $e.Message) }
    }
    [pscustomobject]@{ Ast = $ast; ErrorCount = @($errors).Count }
}

function Get-EnclosingFunction {
    param($Node)
    $p = $Node.Parent
    while ($p) {
        if ($p -is [System.Management.Automation.Language.FunctionDefinitionAst]) { return $p.Name }
        $p = $p.Parent
    }
    return '<top-level>'
}

function Test-Seed {
    param($Node)
    # $LASTEXITCODE
    $v = $Node.FindAll({ param($n)
        $n -is [System.Management.Automation.Language.VariableExpressionAst] -and
        ($n.VariablePath.UserPath -eq 'LASTEXITCODE' -or $n.VariablePath.UserPath -eq '?')
    }, $true)
    if ($v.Count -gt 0) { return $true }
    # .ExitCode member
    $m = $Node.FindAll({ param($n)
        $n -is [System.Management.Automation.Language.MemberExpressionAst] -and
        $n.Member -is [System.Management.Automation.Language.StringConstantExpressionAst] -and
        $n.Member.Value -eq 'ExitCode'
    }, $true)
    return ($m.Count -gt 0)
}

$allResults = @()
$fnStatusReturns = @()

foreach ($file in $Path) {
    $g = Get-Ast -File $file
    $ast = $g.Ast
    if (-not $ast) { continue }

    # ---- build the set of functions whose returns are exit-code tainted -------
    $funcs = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    $taintedFuncs = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $changed = $true
    $pass = 0
    while ($changed -and $pass -lt 10) {
        $changed = $false; $pass++
        foreach ($f in $funcs) {
            if ($taintedFuncs.Contains($f.Name)) { continue }
            $rets = $f.Body.FindAll({ param($n) $n -is [System.Management.Automation.Language.ReturnStatementAst] }, $true)
            $hit = $false
            foreach ($r in $rets) {
                if ($null -eq $r.Pipeline) { continue }
                if (Test-Seed -Node $r.Pipeline) { $hit = $true; break }
                # return of a call to an already-tainted function
                $cmds = $r.Pipeline.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true)
                foreach ($c in $cmds) {
                    $nm = $c.GetCommandName()
                    if ($nm -and $taintedFuncs.Contains($nm)) { $hit = $true; break }
                }
                if ($hit) { break }
            }
            if ($hit) { [void]$taintedFuncs.Add($f.Name); $changed = $true }
        }
    }

    # ---- taint variables ------------------------------------------------------
    $taintedVars = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $assigns = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] }, $true)
    $changed = $true; $pass = 0
    while ($changed -and $pass -lt 10) {
        $changed = $false; $pass++
        foreach ($a in $assigns) {
            if (-not ($a.Left -is [System.Management.Automation.Language.VariableExpressionAst])) { continue }
            $name = $a.Left.VariablePath.UserPath
            if ($taintedVars.Contains($name)) { continue }
            $hit = $false
            if (Test-Seed -Node $a.Right) { $hit = $true }
            if (-not $hit) {
                $cmds = $a.Right.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true)
                foreach ($c in $cmds) {
                    $nm = $c.GetCommandName()
                    if ($nm -and $taintedFuncs.Contains($nm)) { $hit = $true; break }
                }
            }
            if (-not $hit) {
                $vars = $a.Right.FindAll({ param($n) $n -is [System.Management.Automation.Language.VariableExpressionAst] }, $true)
                foreach ($v in $vars) { if ($taintedVars.Contains($v.VariablePath.UserPath)) { $hit = $true; break } }
            }
            if ($hit) { [void]$taintedVars.Add($name); $changed = $true }
        }
    }

    # ---- decision sites -------------------------------------------------------
    $conds = @()
    $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.IfStatementAst] }, $true) | ForEach-Object {
        foreach ($cl in $_.Clauses) { $conds += [pscustomobject]@{ Kind='if'; Cond=$cl.Item1; Body=$cl.Item2 } }
    }
    $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.WhileStatementAst] }, $true) | ForEach-Object {
        $conds += [pscustomobject]@{ Kind='while'; Cond=$_.Condition; Body=$_.Body }
    }
    $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.DoWhileStatementAst] }, $true) | ForEach-Object {
        $conds += [pscustomobject]@{ Kind='dowhile'; Cond=$_.Condition; Body=$_.Body }
    }
    $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.DoUntilStatementAst] }, $true) | ForEach-Object {
        $conds += [pscustomobject]@{ Kind='dountil'; Cond=$_.Condition; Body=$_.Body }
    }
    # TernaryExpressionAst does not exist in Windows PowerShell 5.1's parser. setup.ps1
    # must run under 5.1 (it is launched by Inno with powershell.exe), so a ternary in it
    # would be a parse error, not a missed census hit. Guarded rather than assumed.
    $ternaryType = 'System.Management.Automation.Language.TernaryExpressionAst' -as [type]
    if ($ternaryType) {
        $ast.FindAll({ param($n) $n -is $ternaryType }, $true) | ForEach-Object {
            $conds += [pscustomobject]@{ Kind='ternary'; Cond=$_.Condition; Body=$null }
        }
    }
    $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.SwitchStatementAst] }, $true) | ForEach-Object {
        $conds += [pscustomobject]@{ Kind='switch'; Cond=$_.Condition; Body=$null }
    }

    foreach ($c in $conds) {
        if ($null -eq $c.Cond) { continue }
        $why = @()
        if (Test-Seed -Node $c.Cond) { $why += 'seed' }
        $vars = $c.Cond.FindAll({ param($n) $n -is [System.Management.Automation.Language.VariableExpressionAst] }, $true)
        foreach ($v in $vars) {
            if ($taintedVars.Contains($v.VariablePath.UserPath)) { $why += ('var:$' + $v.VariablePath.UserPath) }
        }
        $cmds = $c.Cond.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true)
        foreach ($cm in $cmds) {
            $nm = $cm.GetCommandName()
            if ($nm -and $taintedFuncs.Contains($nm)) { $why += ('fn:' + $nm) }
        }
        if ($why.Count -eq 0) { continue }
        $bodyFirst = ''
        if ($c.Body -and $c.Body.Statements.Count -gt 0) {
            $bodyFirst = ($c.Body.Statements[0].Extent.Text -split "`r?`n")[0].Trim()
            if ($bodyFirst.Length -gt 110) { $bodyFirst = $bodyFirst.Substring(0,110) + ' ...' }
        }
        $ctext = ($c.Cond.Extent.Text -replace "`r?`n", ' ') -replace '\s+', ' '
        if ($ctext.Length -gt 130) { $ctext = $ctext.Substring(0,130) + ' ...' }
        $allResults += [pscustomobject]@{
            File   = (Split-Path $file -Leaf)
            Line   = $c.Cond.Extent.StartLineNumber
            Fn     = (Get-EnclosingFunction -Node $c.Cond)
            Kind   = $c.Kind
            Why    = ($why | Select-Object -Unique) -join ','
            Cond   = $ctext
            Then   = $bodyFirst
        }
    }

    # ---- functions returning a bare status token -----------------------------
    foreach ($f in $funcs) {
        $rets = $f.Body.FindAll({ param($n) $n -is [System.Management.Automation.Language.ReturnStatementAst] }, $true)
        foreach ($r in $rets) {
            if ($null -eq $r.Pipeline) { continue }
            $t = $r.Pipeline.Extent.Text.Trim()
            if ($t -match "^(\`$true|\`$false|'[^']*'|`"[^`"]*`"|\d+)$") {
                $fnStatusReturns += [pscustomobject]@{
                    File = (Split-Path $file -Leaf); Line = $r.Extent.StartLineNumber
                    Fn = $f.Name; Return = $t
                }
            }
        }
    }
}

Write-Host ''
Write-Host '================ DECISION SITES DERIVED FROM AN EXIT CODE / RETURN VALUE ================'
$allResults | Sort-Object File, Line | ForEach-Object {
    '{0,-28} {1,5}  {2,-34} {3,-8} [{4}]' -f $_.File, $_.Line, $_.Fn, $_.Kind, $_.Why
    '        cond: {0}' -f $_.Cond
    if ($_.Then) { '        then: {0}' -f $_.Then }
}
Write-Host ''
Write-Host ("TOTAL decision sites: {0}" -f $allResults.Count)
Write-Host ''
Write-Host '================ FUNCTIONS RETURNING A BARE STATUS TOKEN ================'
$fnStatusReturns | Sort-Object File, Line | ForEach-Object {
    '{0,-28} {1,5}  {2,-34} return {3}' -f $_.File, $_.Line, $_.Fn, $_.Return
}
Write-Host ("TOTAL bare-status returns: {0}" -f $fnStatusReturns.Count)
