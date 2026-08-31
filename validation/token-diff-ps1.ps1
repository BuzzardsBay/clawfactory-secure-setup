param([string]$Orig, [string]$New, [string]$WorkDir)
$ErrorActionPreference = 'Stop'

function Get-CodeTokens($path) {
    $text = [System.IO.File]::ReadAllText($path)
    $errs = $null
    $toks = [System.Management.Automation.PSParser]::Tokenize($text, [ref]$errs)
    if ($errs -and $errs.Count -gt 0) { throw "PARSE ERRORS in ${path}: $($errs.Count) -- first: $($errs[0].Message)" }
    return @($toks | Where-Object { $_.Type -ne 'Comment' -and $_.Type -ne 'NewLine' } |
             ForEach-Object { "$($_.Type)|$($_.Content)" })
}
function Compare-Files($a, $b) {
    $ta = Get-CodeTokens $a; $tb = Get-CodeTokens $b
    if ($ta.Count -ne $tb.Count) { return "DIFFERENT (count $($ta.Count) vs $($tb.Count))" }
    for ($i = 0; $i -lt $ta.Count; $i++) {
        if ($ta[$i] -ne $tb[$i]) { return "DIFFERENT (token $i : '$($ta[$i])' vs '$($tb[$i])')" }
    }
    return "IDENTICAL ($($ta.Count) code tokens)"
}

if (-not $WorkDir) { $WorkDir = Split-Path -Parent $Orig }
$dir = $WorkDir
$raw = [System.IO.File]::ReadAllText($Orig)

# CONTROL 2 -- a REAL code change planted. This MUST read DIFFERENT.
$c2 = Join-Path $dir 'cal-code.ps1'
[System.IO.File]::WriteAllText($c2, ($raw -replace "-eq 'EnablePending'", "-eq 'ZnablePending'"), (New-Object System.Text.UTF8Encoding($false)))
# CONTROL 3 -- a comment-only change planted. This MUST read IDENTICAL.
$c3 = Join-Path $dir 'cal-comment.ps1'
[System.IO.File]::WriteAllText($c3, ($raw + "`n# planted comment, calibration only`n"), (New-Object System.Text.UTF8Encoding($false)))

Write-Host "CONTROL 1  orig vs orig            : $(Compare-Files $Orig $Orig)"
Write-Host "CONTROL 2  orig vs planted CODE    : $(Compare-Files $Orig $c2)      <- must be DIFFERENT"
Write-Host "CONTROL 3  orig vs planted COMMENT : $(Compare-Files $Orig $c3)      <- must be IDENTICAL"
Write-Host "SUBJECT    orig vs edited setup.ps1: $(Compare-Files $Orig $New)"
