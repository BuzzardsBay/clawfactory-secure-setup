<#
  Sections 14.8 and 14.9, on the installed box.

  14.8  Every file the .iss [Files] section bundles under {app} and
        {app}\resources has, ON THE INSTALLED MACHINE, a SHA-256 identical to its
        COMMITTED BLOB at the build commit, and CR=0 for every text file.
  14.9  resources\orchestrator-prompt.md reaches the DISTRO with CR=0, delivered
        byte-identical to its committed source, read as the right identity.

  WHY THE NEGATIVE HALVES ARE NOT OPTIONAL
  ----------------------------------------
  A CR counter that always returns zero passes all 54 files identically and
  produces exactly the same clean result as a correct one. So a CR is PLANTED and
  the counter must report it. Likewise a byte is appended to a copy and the digest
  must differ, and a path that cannot exist must read as absent rather than as a
  match. Without those three, "54 of 54 match" is unfalsifiable.

  RETRIEVAL, AND THE READING THAT MADE IT NECESSARY
  -------------------------------------------------
  This probe writes its rows to a FILE on the box and prints only counts. The
  v1.4.3 run printed rows directly and az vm run-command truncated the middle:
  the completion sentinel arrived and only 25 of 54 rows did. A reader gating on
  the sentinel would have called it complete and counted 25 files as 54.

  The manifest is generated on the build machine by parsing the .iss and hashing
  each committed blob, and is staged beside this probe. Its own generator carries
  seven assertions, because the v1.4.3 generator produced 55 rows all carrying
  e3b0c442... , the SHA-256 of the empty string, from a parse bug.

  L17: a new probe inherits NONE of the preconditions of the phases beside it.
#>
param(
    [string]$Transcript  = 'C:\cfv\bundlebytes-out-probe.txt',
    [string]$ManifestPath = 'C:\cfv\manifest.txt',
    [string]$RowsOut     = 'C:\cfv\bundlebytes-rows.txt'
)

$ErrorActionPreference = 'Continue'
. C:\cfv\interim-v120-wslchan.ps1
. C:\cfv\interim-v120-phaselib.ps1

Start-Phase -Name 'ClawFactory v1.4.4 sections 14.8 and 14.9: bundled bytes and the orchestrator prompt' `
    -Transcript $Transcript -Sentinel 'BUNDLEBYTES_COMPLETE'

# Files whose CR count is DATA, not line endings. Confirmed binary in git
# (-text on both sides) by the v1.4.3 run; the digest assertion still applies to
# them in full, only the CR=0 assertion is waived.
$binaryLeaves = @('logo.png', 'lobster.ico', 'ClawChat.exe')

# =========================================================================
Section '1. Section 14.8: the bundled bytes on the box ARE the committed bytes'

Require-Precondition -Id 'BB.PRE' -Name 'the staged manifest is present and non-trivial' `
    -Met ((Test-Path $ManifestPath) -and (@(Get-Content $ManifestPath).Count -ge 30)) `
    -Reason 'without the manifest there is nothing to compare against, and "0 mismatches" over 0 rows is the most dangerous clean result this check can produce' | Out-Null

$rows = @(Get-Content $ManifestPath | Where-Object { $_ -match '\|' })
W "MANIFEST_ROWS=$($rows.Count)"

$sb = New-Object Text.StringBuilder
$match = 0; $mismatch = 0; $absent = 0; $crBad = 0; $crWaived = 0
foreach ($line in $rows) {
    $p = $line -split '\|', 3
    $rel = $p[0]; $dest = $p[1]; $want = $p[2].Trim()
    $leaf = Split-Path $dest -Leaf
    if (-not (Test-Path $dest)) {
        $absent++
        [void]$sb.AppendLine("ABSENT|$rel|$dest|-|-")
        continue
    }
    $bytes = [IO.File]::ReadAllBytes($dest)
    $got = (Get-FileHash $dest -Algorithm SHA256).Hash.ToLower()
    $cr = 0; foreach ($b in $bytes) { if ($b -eq 13) { $cr++ } }
    $isBin = $binaryLeaves -contains $leaf
    if ($got -eq $want) { $match++ } else { $mismatch++ }
    if ($cr -ne 0) { if ($isBin) { $crWaived++ } else { $crBad++ } }
    [void]$sb.AppendLine("ROW|$rel|$got|$want|$($got -eq $want)|cr=$cr|bin=$isBin|bytes=$($bytes.Length)")
}

# ---- the three canaries, without which the counts above are unfalsifiable ----
$canDir = 'C:\cfv\canary148'
New-Item -ItemType Directory -Path $canDir -Force | Out-Null
$srcSoul = 'C:\Program Files\ClawFactory\resources\safety-rules.md'
$canAlt = Join-Path $canDir 'altered.md'
$canCr  = Join-Path $canDir 'withcr.md'
$canAbs = Join-Path $canDir 'this-cannot-exist-9f31a7.md'

$soulBytes = [IO.File]::ReadAllBytes($srcSoul)
[IO.File]::WriteAllBytes($canAlt, ($soulBytes + [byte]0x21))
$crBytes = New-Object 'System.Collections.Generic.List[byte]'
$crBytes.AddRange($soulBytes); $crBytes.Insert(10, [byte]13)
[IO.File]::WriteAllBytes($canCr, $crBytes.ToArray())

function Read-Canary([string]$p) {
    if (-not (Test-Path $p)) { return @{ Present = $false; Sha = '-'; Cr = -1 } }
    $b = [IO.File]::ReadAllBytes($p)
    $c = 0; foreach ($x in $b) { if ($x -eq 13) { $c++ } }
    return @{ Present = $true; Sha = (Get-FileHash $p -Algorithm SHA256).Hash.ToLower(); Cr = $c }
}
$rAlt = Read-Canary $canAlt
$rCr  = Read-Canary $canCr
$rAbs = Read-Canary $canAbs
$soulWant = ($rows | Where-Object { $_ -match 'safety-rules\.md' }) -split '\|' | Select-Object -Last 1

W "CANARY_ALTERED|present=$($rAlt.Present)|sha=$($rAlt.Sha)|cr=$($rAlt.Cr)"
W "CANARY_CR     |present=$($rCr.Present)|sha=$($rCr.Sha)|cr=$($rCr.Cr)"
W "CANARY_ABSENT |present=$($rAbs.Present)"
W "SOUL_COMMITTED=$($soulWant.Trim())"

# REGISTER-Control, not Record. Recording a control as an ordinary row leaves the
# phase with "positive controls registered=0", and the runner then correctly
# downgrades every PASS in the phase: an instrument never shown to work in the
# run cannot report a result. That is what voided this phase on its first outing.
Register-Control -Id 'BB.CTL.ALTERED' -Name 'a one-byte change makes the digest differ' `
    -Fired ($rAlt.Present -and $rAlt.Sha -ne $soulWant.Trim()) `
    -Evidence "altered copy sha=$($rAlt.Sha) vs committed $($soulWant.Trim()). If these matched, the digest comparison could not detect a changed file." | Out-Null

Register-Control -Id 'BB.CTL.CR' -Name 'the CR counter reports a planted CR' `
    -Fired ($rCr.Cr -ge 1) `
    -Evidence "planted-CR copy reports cr=$($rCr.Cr), must be >=1. A counter that always returns 0 would pass all $($rows.Count) files identically and produce this same clean result." | Out-Null

Register-Control -Id 'BB.CTL.ABSENT' -Name 'a path that cannot exist reads as absent' `
    -Fired (-not $rAbs.Present) `
    -Evidence 'a missing file must not be able to read as a match' | Out-Null

[IO.File]::WriteAllText($RowsOut, $sb.ToString(), (New-Object Text.UTF8Encoding($false)))
$rowsSha = (Get-FileHash $RowsOut -Algorithm SHA256).Hash.ToLower()
W "ROWS_FILE=$RowsOut ROWS_SHA=$rowsSha"
W "COMPARED=$($rows.Count) MATCH=$match MISMATCH=$mismatch ABSENT=$absent CR_BAD=$crBad CR_WAIVED_BINARY=$crWaived"

Record 'BB.1' 'Every bundled file on the box matches its committed blob at the build commit' `
    $(if ($rows.Count -eq 0) { 'VOID' } elseif ($mismatch -eq 0 -and $absent -eq 0) { 'PASS' } else { 'FAIL' }) `
    "compared=$($rows.Count) match=$match mismatch=$mismatch absent=$absent"

Record 'BB.2' 'CR=0 across every bundled TEXT file' `
    $(if ($rows.Count -eq 0) { 'VOID' } elseif ($crBad -eq 0) { 'PASS' } else { 'FAIL' }) `
    "text files with CR!=0: $crBad. Binary files carrying 0x0D as data (logo.png, lobster.ico, ClawChat.exe): $crWaived, waived for CR only -- their DIGEST assertion still applies and is counted above."

Remove-Item $canDir -Recurse -Force -ErrorAction SilentlyContinue

# =========================================================================
Section '2. Section 14.9: the orchestrator prompt reaches the DISTRO with CR=0'
$expectPrompt = 'f7f8163426790c05bbec090cc7efcfd83809a81531214fd26db68c6e4d12ec43'
# The first version searched only /home/clawuser and /etc/clawfactory and reported
# EXISTS=no. That is ambiguous between "the search was too narrow" and "the file is
# not delivered", which are completely different findings, so the search is now
# filesystem-wide and runs as ROOT: a clawuser-only search cannot traverse a
# directory clawuser may not enter, and would report a false absence.
# The whole match list is printed, not just the first hit, so a delivery to an
# unexpected location is visible rather than silently picked or silently missed.
$opFind = Invoke-WslFile -Tag 'bb149find' -User 'root' -Body @'
echo "--- the delivered agent.md files, which is the REAL subject ---"
for a in orchestrator skill-scout skill-builder publisher; do
  f="/home/clawuser/.openclaw/agents/$a/agent.md"
  if [ -e "$f" ]; then
    echo "FOUND=$f owner=$(stat -c %U:%G "$f") mode=$(stat -c %a "$f") bytes=$(stat -c %s "$f") sha=$(sha256sum "$f" | cut -d' ' -f1)"
  else
    echo "MISSING=$f"
  fi
done
echo "--- and confirm the SOURCE name is legitimately absent in the distro ---"
n=$(find /home/clawuser -name 'orchestrator-prompt.md' 2>/dev/null | wc -l)
echo "SOURCE_NAME_IN_DISTRO=$n"
echo "--- CONTROL: a filename that cannot exist must yield no hits ---"
m=$(find /home/clawuser -name 'agent-cannot-exist-5a91.md' 2>/dev/null | wc -l)
echo "CTL_FIND_ABSENT=$m"
'@
W $opFind.Out

Register-Control -Id 'BB.FIND.CTL' -Name 'the filesystem search discriminates present from absent' `
    -Fired ($opFind.Out -match 'CTL_FIND_ABSENT=0') `
    -Evidence 'a search that returns nothing for everything would make an EXISTS=no reading meaningless' | Out-Null

# NAME THE REAL SUBJECT. resources\orchestrator-prompt.md is delivered by
# bootstrap.ps1 into ~/.openclaw/agents/orchestrator/agent.md -- base64-streamed
# to a .tmp and atomically renamed. The source filename NEVER exists inside the
# distro, by design. An earlier revision of this probe searched the whole
# filesystem for 'orchestrator-prompt.md', found nothing, and would have reported
# "the orchestrator prompt never reaches the distro" -- a FALSE SHIP-BLOCKER
# against correct behaviour. The phase VOIDed instead of failing, which is the
# only reason that reading did not leave this file.
$op = Invoke-WslFile -Tag 'bb149' -User 'clawuser' -Body @'
F=/home/clawuser/.openclaw/agents/orchestrator/agent.md
echo "PATH_USED=$F"
if [ -e "$F" ]; then
  echo "EXISTS=yes"
  echo "BYTES=$(stat -c %s "$F")"
  echo "CR=$(tr -cd '\r' < "$F" | wc -c)"
  echo "SHA=$(sha256sum "$F" | cut -d' ' -f1)"
  echo "LINES=$(wc -l < "$F")"
  echo "OWNER=$(stat -c %U:%G "$F") MODE=$(stat -c %a "$F")"
  echo "PLACEHOLDER_HITS=$(grep -c '{{' "$F" 2>/dev/null || echo 0)"
else
  echo "EXISTS=no"
fi
printf 'a\rb\n' > /var/tmp/bb-crctl.txt
echo "CTL_CR_COUNTER=$(tr -cd '\r' < /var/tmp/bb-crctl.txt | wc -c)"
rm -f /var/tmp/bb-crctl.txt
if [ -e /home/clawuser/.openclaw/this-cannot-exist-7c2b.md ]; then echo "CTL_ABSENT=bad"; else echo "CTL_ABSENT=ok"; fi
echo "WHOAMI=$(whoami) UID=$(id -u)"
'@
W $op.Out

$opSha  = if ($op.Out -match 'SHA=([0-9a-f]{64})') { $Matches[1] } else { '' }
$opCr   = if ($op.Out -match 'CR=(\d+)')           { [int]$Matches[1] } else { -1 }
$opBytes= if ($op.Out -match 'BYTES=(\d+)')        { [int]$Matches[1] } else { -1 }

Register-Control -Id 'BB.3.CTL' -Name 'the in-distro CR counter counts, and an absent path reads absent' `
    -Fired (($op.Out -match 'CTL_CR_COUNTER=1') -and ($op.Out -match 'CTL_ABSENT=ok')) `
    -Evidence 'a CR counter that cannot count would report CR=0 on a file that holds one, which is this section''s exact failure mode' | Out-Null

Register-Control -Id 'BB.3.WHO' -Name 'the read happened as clawuser, uid 1000' `
    -Fired ($op.Out -match 'WHOAMI=clawuser UID=1000') `
    -Evidence 'read as the identity the item specifies, not as root and not as SYSTEM' | Out-Null

Record 'BB.3' 'orchestrator-prompt.md reaches the distro byte-identical to its committed source' `
    $(if (-not $opSha) { 'VOID' } elseif ($opSha -eq $expectPrompt) { 'PASS' } else { 'FAIL' }) `
    "inDistro=$opSha committed=$expectPrompt equal=$($opSha -eq $expectPrompt) bytes=$opBytes. This is strictly stronger than 'carries a digest somewhere': it subsumes non-empty and not-truncated."

Record 'BB.4' 'orchestrator-prompt.md is CR=0 in the distro' `
    $(if ($opCr -lt 0) { 'VOID' } elseif ($opCr -eq 0) { 'PASS' } else { 'FAIL' }) `
    "CR=$opCr. A CRLF rendering of this 65-line file would be exactly 65 bytes larger, so bytes=$opBytes is arithmetic corroboration of the CR count."

Complete-Phase -ResultsJson 'C:\cfv\bundlebytes-results.json' -MarkerPrefix 'BUNDLEBYTES'
