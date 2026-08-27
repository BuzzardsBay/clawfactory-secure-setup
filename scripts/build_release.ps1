<#
Produces a release-ready, signed ClawFactory installer:
  1. Runs nine pre-build gates (SOUL, bundle, interpolation, worktree, Studio,
     version, persona, workspace SOUL, rootfs). Each fails the build on drift;
     none auto-correct.
  2. Compiles ClawFactory-Secure-Setup.iss with Inno Setup (ISCC.exe)
  3. Enforces the second half of the VERSION gate, which cannot run any earlier:
     the compiled digest must not contradict a version already in
     released-versions.tsv. Refusal happens here, before the signature.
  4. Stamps the compiled bytes so sign_installer.ps1 will accept them
  5. Signs Output\ClawFactory-Secure-Setup.exe via scripts\sign_installer.ps1
  6. Appends the shipped artifact to released-versions.tsv, on success only

This is the build command, not merely the release one. ISCC.exe on its own still
compiles a perfectly good local dev build; that output simply cannot be signed,
because sign_installer.ps1 refuses anything this script did not stamp. That is
the whole point of the stamp: unsigned dev compiles stay easy, and the route
that reaches a customer is the one that passed the gates.
#>

[CmdletBinding()]
param(
    [string]$IsccPath = "C:\Program Files (x86)\Inno Setup 6\ISCC.exe",
    # No default here on purpose; see the resolution below.
    [string]$RepoRoot
)

$ErrorActionPreference = "Stop"

# $RepoRoot used to default to (Split-Path -Parent $PSScriptRoot) in the param
# block. That is fine when the script is invoked from an existing session with &
# or dot-sourcing, which is the only way it has ever been run here, but it is
# broken under `powershell.exe -File`: with [CmdletBinding()] present, parameter
# defaults are evaluated at a point where $PSScriptRoot is still EMPTY, so
# Split-Path threw "Cannot bind argument to parameter 'Path'" and the script died
# before the first gate. Isolated to that single variable on 2026-08-05: the same
# param block without [CmdletBinding()] resolves correctly under -File, and the
# same script with it fails under -File whether or not arguments are passed.
# $PSScriptRoot IS populated by the time the body runs, so resolve it here.
if (-not $RepoRoot) { $RepoRoot = Split-Path -Parent $PSScriptRoot }
if (-not $RepoRoot) { Write-Error "build_release.ps1: could not resolve the repo root; pass -RepoRoot explicitly."; exit 1 }

function Fail($msg) {
    Write-Error "build_release.ps1: $msg"
    exit 1
}

if (-not (Test-Path $IsccPath)) {
    Fail "ISCC.exe not found at $IsccPath"
}

$issPath = Join-Path $RepoRoot "ClawFactory-Secure-Setup.iss"
if (-not (Test-Path $issPath)) {
    Fail "$issPath not found"
}

# --- Pre-build gate: the SOUL pin must be a build-time constant that MATCHES ---
# setup.ps1 carries the expected SHA-256 of resources/safety-rules.md as a
# literal, and refuses to install if the file on disk disagrees. That is what
# makes the pin an integrity control rather than theatre: a pin computed from
# the artefact it certifies certifies nothing.
#
# The literal therefore has to be kept honest at BUILD time, here, and drift has
# to fail the build loudly rather than be auto-corrected -- silently rewriting it
# would just move the self-certification one step earlier.
$soulFile = Join-Path $RepoRoot "resources\safety-rules.md"
if (-not (Test-Path $soulFile)) { Fail "resources/safety-rules.md not found" }
$soulActual = (Get-FileHash -LiteralPath $soulFile -Algorithm SHA256).Hash.ToLower()
$setupText  = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "setup.ps1")
# NOTE the backtick. In a double-quoted PowerShell string "$expectedSoulHash" is
# an EMPTY VARIABLE, not a literal, so the pattern collapsed to one that can never
# match and this gate failed the build unconditionally from the day it was added.
# It failed closed, so nothing shipped past it -- but it also never once compared
# the pin to the file. Verified by execution 2026-08-04; use '\$' or `$, not \$.
$m = [regex]::Match($setupText, "\`$expectedSoulHash\s*=\s*'([a-f0-9]{64})'")
if (-not $m.Success) {
    Fail "setup.ps1 does not carry an `$expectedSoulHash literal. The SOUL pin must be baked in at build time."
}
$soulPinned = $m.Groups[1].Value
if ($soulPinned -ne $soulActual) {
    Fail ("SOUL pin drift: setup.ps1 pins $soulPinned but resources/safety-rules.md hashes to $soulActual. " +
          "If the safety rules changed on purpose, update the `$expectedSoulHash literal in setup.ps1 to $soulActual and rebuild.")
}
Write-Host "SOUL pin OK: $soulPinned"

# --- Pre-build gate: every preflight-required resource must be BUNDLED --------
# The two halves of the bug that once shipped an installer with zero security
# controls: Step-Preflight's required list and the .iss [Files] section drifted
# apart, so the step existed and the file did not. Check the pairing here, where
# it is cheap, instead of on a customer's machine.
$reqMatch = [regex]::Match($setupText, "(?s)\`$required\s*=\s*@\((.*?)\)")   # backtick: see above
if (-not $reqMatch.Success) { Fail "could not read Step-Preflight's `$required list from setup.ps1" }
$required = [regex]::Matches($reqMatch.Groups[1].Value, "'([^']+)'") | ForEach-Object { $_.Groups[1].Value }
$issText  = Get-Content -Raw -LiteralPath $issPath
$notBundled = @($required | Where-Object { $issText -notmatch [regex]::Escape("resources\$_") })
if ($notBundled.Count -gt 0) {
    Fail ("These resources are required by Step-Preflight but are NOT in the .iss [Files] section: " +
          ($notBundled -join ', ') + ". A build with this gap installs with missing security controls.")
}
Write-Host ("Bundle check OK: all {0} preflight resources are in [Files]." -f $required.Count)

# --- Pre-build gate: no shipped script interpolates an UNDEFINED variable -----
# v1.4.3 shipped a "Switch AI Provider" Start Menu item that could not work for
# any provider. resources/switch-provider.ps1 sets Set-StrictMode -Version 3.0
# and builds its firewall payload as an EXPANDABLE here-string; four occurrences
# of $baseHosts inside that here-string's COMMENTS were not escaped, PowerShell
# expanded them, the variable did not exist, and StrictMode turned that into a
# terminating error before the script applied anything. The commit that
# introduced them (3818bc0) was itself a security fix; its explanatory comments
# are what broke the script.
#
# The class is not "a typo in switch-provider.ps1". It is: text that reads like
# prose to a human is CODE to the parser once it is inside an expandable string.
# That is invisible to review and invisible to a grep, because a regex cannot
# tell an escaped `$name from a live one, nor a variable assigned elsewhere from
# one never assigned at all. So this gate parses.
#
# WHY IT RUNS BEFORE THE WORKTREE GATE. This is a lint on source text, and a
# lint that only ever sees committed bytes cannot be canaried without committing
# the defect it is meant to catch. Running it first means a planted instance in
# a dirty tree reaches it, which is how it was proved to fire at all.
#
# WHAT THIS GATE CANNOT CATCH, stated so its OK line is never read as more than
# it is:
#   * A variable assigned SOMEWHERE in the file but not yet assigned at the
#     point of use. "Defined anywhere" is the test, not "defined by now".
#   * A variable that a dot-sourced library defines. That direction is the
#     false-POSITIVE risk, not a miss: such a variable would be reported here
#     even though it resolves at runtime. There are none today.
#   * A shell variable that is correctly escaped as `$x but is WRONG -- this
#     gate checks that PowerShell will not eat it, not that bash wants it.
#   * Anything outside the .iss [Files] set. The validation harness and the
#     build scripts are not swept.
#   * The other half of the same family: a bash payload carrying its own double
#     quotes, which PowerShell 5.1 fails to escape when it builds a native
#     command line. That is what made the kill switch inert from v1.0 to v1.4.4.
#     It is a different shape and this gate does not look for it;
#     resources/clawfactory-stop.ps1 refuses such a payload at runtime instead.
#
# Scope note: the defect is only FATAL under StrictMode, but in a file without
# it the same shape silently interpolates an EMPTY string into a shell payload,
# which is how a probe once turned `grep -q "$ip"` into `grep -q ""` and matched
# everything. Both are defects, so all shipped scripts are swept and StrictMode
# is reported per finding rather than used to filter.
$AutoVars = @(
    '_','PSItem','null','true','false','args','input','this','Matches','Error','LASTEXITCODE',
    'PSScriptRoot','PSCommandPath','MyInvocation','PWD','HOME','PID','Host','ExecutionContext',
    'StackTrace','PSBoundParameters','PSCmdlet','PSDefaultParameterValues','ErrorActionPreference',
    'WarningPreference','VerbosePreference','DebugPreference','ProgressPreference',
    'InformationPreference','ConfirmPreference','WhatIfPreference','OFS','ShellId','PSVersionTable',
    'IsWindows','IsLinux','IsMacOS','PSEdition','PSCulture','PSUICulture','NestedPromptLevel',
    'ConsoleFileName','PSHOME','PSSenderInfo','Sender','EventArgs','EventSubscriber','Event'
)
function Test-AstType($n, $t) { $n.GetType().Name -eq $t }

$shippedPs1 = @()
foreach ($line in (Get-Content -LiteralPath $issPath)) {
    if ($line -match '^Source:\s*"([^"]+)"' -and $Matches[1] -match '\.ps1$') {
        $shippedPs1 += (Join-Path $RepoRoot ($Matches[1] -replace '\\', '/'))
    }
}
if ($shippedPs1.Count -eq 0) {
    Fail ("could not read any .ps1 Source entries from the .iss [Files] section. The interpolation gate would " +
          "pass vacuously, which is worse than no gate.")
}

$interpDefects = @()
foreach ($psFile in $shippedPs1) {
    $parseErrs = $null
    $fileAst = [System.Management.Automation.Language.Parser]::ParseFile($psFile, [ref]$null, [ref]$parseErrs)
    if ($parseErrs -and $parseErrs.Count -gt 0) {
        Fail ("$psFile does not parse: line {0}: {1}. A shipped script that cannot be parsed cannot be shipped." -f
              $parseErrs[0].Extent.StartLineNumber, $parseErrs[0].Message)
    }
    $isStrict = @($fileAst.FindAll({ param($n) (Test-AstType $n 'CommandAst') -and $n.GetCommandName() -eq 'Set-StrictMode' }, $true)).Count -gt 0

    $defined = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($a in $fileAst.FindAll({ param($n) Test-AstType $n 'AssignmentStatementAst' }, $true)) {
        foreach ($v in $a.Left.FindAll({ param($n) Test-AstType $n 'VariableExpressionAst' }, $true)) {
            $null = $defined.Add($v.VariablePath.UserPath)
        }
    }
    foreach ($a in $fileAst.FindAll({ param($n) Test-AstType $n 'ParameterAst' },       $true)) { $null = $defined.Add($a.Name.VariablePath.UserPath) }
    foreach ($a in $fileAst.FindAll({ param($n) Test-AstType $n 'ForEachStatementAst' }, $true)) { $null = $defined.Add($a.Variable.VariablePath.UserPath) }
    foreach ($c in $fileAst.FindAll({ param($n) Test-AstType $n 'CommandAst' }, $true)) {
        if (@('Set-Variable','New-Variable') -contains $c.GetCommandName()) {
            for ($i = 1; $i -lt $c.CommandElements.Count; $i++) {
                $e = $c.CommandElements[$i]
                if ((Test-AstType $e 'StringConstantExpressionAst') -and $e.Value -notmatch '^-') { $null = $defined.Add($e.Value); break }
            }
        }
    }

    foreach ($str in $fileAst.FindAll({ param($n) Test-AstType $n 'ExpandableStringExpressionAst' }, $true)) {
        foreach ($nested in $str.NestedExpressions) {
            foreach ($v in $nested.FindAll({ param($n) Test-AstType $n 'VariableExpressionAst' }, $true)) {
                if ($v.VariablePath.IsDriveQualified) { continue }
                $vname = $v.VariablePath.UserPath
                if ($AutoVars -contains $vname)  { continue }
                if ($defined.Contains($vname))   { continue }
                $interpDefects += ("{0}:{1} `${2} inside a {3}{4}" -f
                    ($psFile -replace [regex]::Escape($RepoRoot + '\'), '' -replace [regex]::Escape($RepoRoot + '/'), ''),
                    $v.Extent.StartLineNumber, $vname, $str.StringConstantType,
                    $(if ($isStrict) { ' (file sets StrictMode: this is FATAL at runtime)' } else { ' (no StrictMode: this silently interpolates an EMPTY string)' }))
            }
        }
    }
}
if ($interpDefects.Count -gt 0) {
    Fail ("UNDEFINED INTERPOLATION in shipped scripts. PowerShell expands these; they are not prose. " +
          "Escape each as ``$name, or reword so no dollar sign appears -- " + ($interpDefects -join ' | '))
}
Write-Host ("Interpolation gate OK: {0} shipped .ps1 files parse, and none interpolates a variable the file never defines." -f $shippedPs1.Count)

# --- Pre-build gate: the bundled bytes must BE the committed bytes ------------
# The audit claim this product makes is that a stranger can read the repo that
# produced the artifact. That claim is false the moment a bundled file's bytes on
# disk differ from the bytes git holds -- and until v1.4.3 TEN of them did,
# silently, for months. `git status` cannot see it: a `text` attribute makes git
# normalise on COMPARISON, so a stale CRLF working copy compares equal to an LF
# index for ever, and git never re-normalises an existing working copy when an
# attribute is added later. `git ls-files --eol` was the only reading that showed
# it, and nothing ran it. .gitattributes now pins the checked-out form; this gate
# is what makes that pin load-bearing instead of merely well-intentioned.
#
# It compares BYTES, not line endings, so it catches ANY divergence -- a hand
# edit, a half-applied revert, an editor save into the install dir -- rather than
# only this one class. `git hash-object --no-filters` is the whole trick:
# --no-filters hashes the file exactly as it sits on disk, skipping the clean
# filter that hides the difference everywhere else.
#
# WHAT THIS GATE CANNOT CATCH, stated here so its output is never read as more
# coverage than it has. It compares the working tree against HEAD -- routed
# through the index so the two failure modes (bytes in no git object at all vs
# bytes staged but uncommitted) can be told apart and reported separately. What
# it therefore CANNOT see is a file that was committed wrong in the first place:
# such a file is byte-identical to its committed blob and passes cleanly. This
# gate proves the ARTIFACT MATCHES THE REPO. It does not prove the repo is
# correct, it is not a review, and it says nothing about the two gitignored
# binaries it skips by name (the rootfs and the Studio installer) beyond what
# their own digest pins already assert.
$bundled = @()
foreach ($line in (Get-Content -LiteralPath $issPath)) {
    if ($line -match '^Source:\s*"([^"]+)"') {
        $p = $Matches[1]
        # Expand ISPP #define references (e.g. {#StudioInstaller}) to real paths.
        foreach ($d in [regex]::Matches($issText, '(?m)^#define\s+(\S+)\s+"(.*)"\s*$')) {
            $p = $p -replace [regex]::Escape('{#' + $d.Groups[1].Value + '}'), $d.Groups[2].Value
        }
        $bundled += ($p -replace '\\', '/')
    }
}
if ($bundled.Count -eq 0) {
    Fail "could not read any [Files] Source entries from the .iss. The worktree gate would pass vacuously, which is worse than no gate."
}

Push-Location $RepoRoot
try {
    $trackedList = @(& git ls-files)
    if ($LASTEXITCODE -ne 0) {
        Fail ("git ls-files failed in $RepoRoot (exit $LASTEXITCODE). This gate needs git to compare the bundled " +
              "bytes against the committed ones, and a gate that silently skips when its data source is missing " +
              "is not a gate. Build from a git checkout.")
    }
    $trackedSet = @{}
    foreach ($t in $trackedList) { $trackedSet[$t] = $true }
    $check   = @($bundled | Where-Object { $trackedSet.ContainsKey($_) })
    $skipped = @($bundled | Where-Object { -not $trackedSet.ContainsKey($_) })

    # Raw on-disk hash: no clean filter, so line endings are NOT normalised away.
    $rawHashes = @(& git hash-object --no-filters -- @check)
    if ($LASTEXITCODE -ne 0 -or $rawHashes.Count -ne $check.Count) {
        Fail ("git hash-object --no-filters returned $($rawHashes.Count) hashes for $($check.Count) bundled paths. " +
              "Refusing to compare a list against a differently sized list.")
    }
    $idx = @{}
    foreach ($l in (& git ls-files -s -- @check)) {
        if ($l -match '^\d+\s+([0-9a-f]{40})\s+\d+\s+(.+)$') { $idx[$Matches[2]] = $Matches[1] }
    }
    $head = @{}
    foreach ($l in (& git ls-tree -r HEAD -- @check)) {
        if ($l -match '^\d+\s+blob\s+([0-9a-f]{40})\s+(.+)$') { $head[$Matches[2]] = $Matches[1] }
    }

    # Three-way, so the diagnosis is precise rather than merely negative. The
    # claim being enforced is that the bundled bytes are the COMMITTED bytes, so
    # both failure modes below are real: bytes that are in no git object at all,
    # and bytes that are staged but not yet committed. They are reported
    # separately because the fix differs.
    $drifted   = @()   # worktree != index: these bytes exist nowhere in git
    $unstaged  = @()   # worktree == index != HEAD: staged, not committed
    for ($i = 0; $i -lt $check.Count; $i++) {
        $p = $check[$i]
        if (-not $idx.ContainsKey($p)) {
            Fail "bundled file $p is listed by git ls-files but has no index entry; refusing to guess what it should contain."
        }
        if ($idx[$p] -ne $rawHashes[$i]) { $drifted += $p }
        elseif ((-not $head.ContainsKey($p)) -or ($head[$p] -ne $idx[$p])) { $unstaged += $p }
    }
    if ($drifted.Count -gt 0) {
        Fail ("WORKTREE DRIFT: these bundled files would be compiled into the installer with bytes that are NOT the " +
              "bytes git holds, so the shipped artifact would not match the repo a reader can audit -- " +
              ($drifted -join ', ') + ". Diagnose with 'git ls-files --eol'; 'git diff' reports NOTHING when the " +
              "cause is line endings, because a text attribute makes git normalise on comparison. If the cause is " +
              "line endings, fix it by deleting each file and running 'git checkout -- <path>', which re-materialises " +
              "it from the index under the rules in .gitattributes. If the cause is a real edit, commit it.")
    }
    if ($unstaged.Count -gt 0) {
        Fail ("UNCOMMITTED BUNDLED FILES: these are staged but not committed, so the artifact would ship bytes that " +
              "no commit names -- " + ($unstaged -join ', ') + ". Commit them and rebuild. This is not pedantry: the " +
              "whole value of a signed artifact whose source is public is that a reader can fetch the commit it was " +
              "built from, and a staged-only change has no commit to fetch.")
    }
    foreach ($s in $skipped) {
        Write-Host "  Worktree pin: $s is not tracked by git (sourced at build time, gitignored). Not compared here; its own pin gate covers it."
    }
    Write-Host ("Worktree pin OK: all {0} tracked [Files] resources are byte-identical to their committed form." -f $check.Count)
}
finally { Pop-Location }
# --- Pre-build gate: the embedded Studio installer must be the VALIDATED one ---
# resources\ClawFactory-Studio-Setup-*.exe is gitignored and copied in from the
# Studio repo's release directory at build time, so git cannot tell you whether
# the right binary is sitting there. Both ClawFactory-Secure-Setup.iss and
# .gitignore said it was "verified by sha256 before compile"; that verification
# was real but MANUAL (performed in JOB 3B, recorded as MATCH in
# docs/session_reports/2026-07-21_job3b_combined_installer_closeout.md), and a
# check that lives only in a human's habit is not a check the build has.
#
# The digest below is NOT computed from the file in resources\. It is recorded
# here by hand from a build whose contents were checked, and drift fails the
# build; it is never auto-corrected, for the same reason the SOUL pin above is
# not.
#
# Repinned 2026-08-05 for v1.2.0. The previous pin, d5ff8370..., covered the
# artefact built from Studio @9d62ad0 and validated on cfv-152. That artefact had
# gone STALE rather than merely old: Studio @6105c53 and @14b6422 added the three
# panels the agent-side guards need a front end for, and none of them were in it.
# Shipping it would have paired a working send broker with a Studio that has no
# approval card, which is a broken product rather than an out-of-date asset.
#
# The value below is the artefact built from Studio @14b6422 (main), signed by
# the same Azure Trusted Signing cert. Before pinning it, its app.asar was
# extracted from the compiled NSIS payload and searched for twelve markers drawn
# from the three new panels (/approvals/smtp, Email settings, smtp.example.com,
# Currently sending as, send:approve, send:credential, send:deny, send:list,
# Recently deleted, quarantine:list, quarantine:restore, clawfactory-sendctl).
# All twelve are present in this artefact and absent from the d5ff8370 one, so
# the search discriminates rather than merely matching. See
# docs/session_reports/2026-08-05_first_gated_build_closeout.md.
#
# Repinned 2026-08-13 for the Studio panel smoke test, from Studio @14b6422 to
# the build carrying the SMTP-save parse fix. b701bfb7 could not save an SMTP
# credential at all: invokeEngineWithInput wrapped a two-statement expression in
# the PowerShell grouping operator ( ), which takes one pipeline, so the script
# died at PARSE time and surfaced as "the send service did not respond". The fix
# is the subexpression operator $( ).
#
# Verified before pinning, from the compiled signed installer rather than from
# source: all twelve panel markers above are still present (so the fix dropped
# nothing), and "-InputObject $(" is present in this artefact and ABSENT from
# b701bfb7, while "-InputObject (" is present in both because invokeEngine
# legitimately uses grouping and was not touched. So the search discriminates.
# Positive control 'Workspace' in both, negative sentinel in neither.
#
# RESOLVED 2026-08-14: the filename now carries the version again. It had been
# reused for three distinct payloads, because electron-builder interpolates
# ${version} from desktop/package.json and that had sat at 1.1.0 across two
# rebuilds. Bumping Studio to 1.2.0 fixes the name, the header the user sees and
# the package metadata in one move, since all three read the same field. The
# digest below remains the authority; the name is now merely honest as well.
#
# Repinned 2026-08-14 for Guard 3 and the five smoke-test polish items: the new
# Web access panel, expired approval requests, the full attachment hash, the real
# version in the header, and the PolyForm footer.
#
# Repinned 2026-08-15 for Studio 1.3.0: the toolchain access switch on the Web
# access panel, the ratified replacement footnote, the header spacing fix, and the
# removal of the "Studio backend unreachable" banner from the home route.
#
# Verified before pinning, from the packaged app.asar rather than from source,
# and the search DISCRIMINATES in both directions:
#   present  -- Software sources ClawFactory needs, stops skill installation,
#               unless you switch them off above, Matching is by network address
#               rather than by name, setToolchain, web:toolchain,
#               Running outside the ClawFactory Studio app
#   absent   -- Studio backend unreachable, Two things are always reachable
#               regardless, Running on http://127.0.0.1:8080, MIT licensed, v0.1.0
#   controls -- Workspace and Web access both present, so an "absent" above is a
#               real absence rather than an unreadable payload
# See docs/session_reports/2026-08-15_guard3_followups_closeout.md.
#
# Repinned 2026-08-23 for Studio 1.3.1, the free release. This was the THREE-part
# change the previous note described, and all three landed together:
#   1. $studioName and $studioPinned below, and the .iss #define,
#   2. 'stops skill installation' and 'PolyForm Perimeter 1.0.0' moved OUT of the
#      phase6 PRESENT list and INTO its stale/ABSENT list, joined by
#      'runs entirely on your machine',
#   3. 'does not stop skill installation' and the full footer string
#      'Frontier Automation Systems LLC (middot) Apache-2.0' added to PRESENT.
# Doing 1 without 2 and 3 would have turned a green phase6 into a test of copy no
# artifact produces.
#
# A bare 'Apache-2.0' was REJECTED as the PRESENT marker: dozens of node_modules
# licence banners carry it, so the assertion could never fail. The footer string
# is ours alone. And 'does not stop skill installation' does not contain the
# substring 'stops skill installation', so the PRESENT and ABSENT assertions
# genuinely oppose each other rather than both matching the same bytes.
#
# Verified before pinning, against the packaged app.asar rather than the source:
# 20 of 20 PRESENT, 9 of 9 ABSENT, POSCONTROL_OK.
# Version bumped 1.3.0 -> 1.3.1 deliberately. artifactName carries ${version}, so
# rebuilding at 1.3.0 would have produced a same-named, different-digest artifact,
# which is exactly the drift this pin exists to catch.
#
# Repinned 2026-08-24 for Studio 1.3.2, carrying cards #273, #274 and #275: the
# toggle notices corrected, nine dead routes given an honest empty state, and the
# header made a link home. Same three-part change, all three parts landed:
#   1. $studioName and $studioPinned below, and the .iss #define,
#   2. phase6's PRESENT list gained 'which this switch does not cover',
#      'Your agent can reach the skill hub, GitHub and npm again',
#      'is not part of this release' and 'ClawFactory Studio home'; its ABSENT
#      list gained the two retired notice strings,
#   3. $PIN.studioAsar in validation/interim-v120-phase1.ps1.
#
# Verified against the packaged app.asar before pinning, and the scan
# discriminates in BOTH directions in the same run: Workspace PRESENT (not
# blind) and ClawFactoryNegativeSentinelZZ9 absent (not matching everything).
#   present -- which this switch does not cover, Your agent can reach the skill
#              hub GitHub and npm again, is not part of this release, What you
#              can use today, ClawFactory Studio home
#   absent  -- Skill installation is now off, Your agent can install skills and
#              fetch code from GitHub and npm again, stops skill installation
#
# ONE STRING SURVIVES THAT LOOKS LIKE IT SHOULD NOT, and it is recorded here so
# the next reader does not chase it. 'not wired in the desktop shell scaffold'
# is still in the bundle: it is a constant in api/client.ts, which is still
# imported for app.version(). No route renders it any more -- the nine panels
# that used to are now the honest empty state -- so it is unreachable dead text
# rather than copy. It is deliberately NOT asserted absent, because asserting an
# absence that is not true is how a check starts lying.
$studioName   = 'ClawFactory-Studio-Setup-1.3.2.exe'
$studioPinned = 'ac5937516e7edbb5aac00433bfa6e5074449cbc28b132883099391639e1e7dca'
$studioFile   = Join-Path $RepoRoot "resources\$studioName"
if (-not (Test-Path $studioFile)) {
    Fail ("resources\$studioName not found. It is gitignored; copy it in from the Studio repo's " +
          "release directory before building.")
}
if ($issText -notmatch [regex]::Escape($studioName)) {
    Fail ("ClawFactory-Secure-Setup.iss no longer embeds $studioName. If Studio was rebuilt, update " +
          "BOTH the .iss #define and the `$studioPinned digest in this script.")
}
$studioActual = (Get-FileHash -LiteralPath $studioFile -Algorithm SHA256).Hash.ToLower()
if ($studioActual -ne $studioPinned) {
    Fail ("Studio installer drift: resources\$studioName hashes to $studioActual but this build pins " +
          "$studioPinned. Refusing to embed an unverified 100 MB payload. If Studio was rebuilt on " +
          "purpose, validate the new artefact, record its digest in a close-out, and update " +
          "`$studioPinned here to $studioActual.")
}
Write-Host "Studio pin OK: $studioPinned"

# --- Pre-build gate: the two version literals must agree ----------------------
# .iss MyAppVersion feeds AppVersion, so it is what the customer sees in Apps &
# Features and on the uninstall entry. That makes it the authority.
# setup.ps1's $InstallerVersion follows it. The two drifted for roughly fifteen
# releases (1.0.34 against 1.1.1) because nothing compared them. Same shape as
# the gates above: fail on drift, never auto-correct, because a silent rewrite
# would just hide which one someone forgot to bump.
$issVer = [regex]::Match($issText,   '#define\s+MyAppVersion\s+"([^"]+)"')
$psVer  = [regex]::Match($setupText, "\`$InstallerVersion\s*=\s*'([^']+)'")   # backtick, see above
if (-not $issVer.Success) { Fail "could not read MyAppVersion from ClawFactory-Secure-Setup.iss" }
if (-not $psVer.Success)  { Fail "could not read `$InstallerVersion from setup.ps1" }
if ($issVer.Groups[1].Value -ne $psVer.Groups[1].Value) {
    Fail ("Version drift: .iss MyAppVersion is $($issVer.Groups[1].Value) but setup.ps1 " +
          "`$InstallerVersion is $($psVer.Groups[1].Value). The .iss value is the one the customer " +
          "sees, so set `$InstallerVersion to $($issVer.Groups[1].Value) and rebuild.")
}
$buildVersion = $issVer.Groups[1].Value
Write-Host "Version OK: $buildVersion (.iss and setup.ps1 agree)"

# --- Same gate, second half: the version must not already name OTHER BYTES -----
# The check above only proves the two literals agree with each other. Both can
# agree and still be a number that has already shipped meaning something else,
# which is exactly what happened: 1.2.0 named three distinct payloads and the two
# literals agreed every time. Agreement between two copies of a stale value is
# not freshness.
#
# So this reads the repo-tracked ledger and, if this version has already shipped,
# remembers its digest. The comparison itself cannot happen yet -- the digest of
# the compiled bytes does not exist until ISCC has run -- so it is enforced below,
# after the compile and BEFORE the signature. That placement is deliberate and it
# is the same posture as the build stamp: an unsigned dev compile stays cheap, and
# the route that can reach a customer is the one that is gated.
$ledgerPath = Join-Path $RepoRoot 'released-versions.tsv'
$script:LedgerRows = @()
if (Test-Path $ledgerPath) {
    foreach ($line in (Get-Content -LiteralPath $ledgerPath)) {
        if ($line -match '^\s*#' -or -not $line.Trim()) { continue }
        $c = $line -split "`t"
        if ($c.Count -lt 6 -or $c[0] -eq 'version') { continue }
        $script:LedgerRows += [pscustomobject]@{
            Version = $c[0].Trim(); Artifact = $c[1].Trim(); Kind = $c[2].Trim()
            Sha256  = $c[3].Trim().ToLower(); Bytes = $c[4].Trim(); Date = $c[5].Trim()
            Note    = $(if ($c.Count -ge 7) { $c[6].Trim() } else { '' })
        }
    }
    Write-Host "Ledger OK: released-versions.tsv carries $($script:LedgerRows.Count) prior artifact row(s)."
} else {
    # Absent is allowed on a first run, and it is announced rather than silent. A
    # gate that quietly does nothing when its data file is missing is a gate that
    # can be disabled by deleting a file nobody notices.
    Write-Host "Ledger: released-versions.tsv is ABSENT. This build will create it. No prior version can be checked."
}
$script:PriorForThisVersion = @($script:LedgerRows | Where-Object { $_.Version -eq $buildVersion })
if ($script:PriorForThisVersion.Count -gt 0) {
    Write-Host "Ledger: version $buildVersion has shipped before. The compiled digest will be checked against it."
    foreach ($p in $script:PriorForThisVersion) { Write-Host "  prior: $($p.Version) $($p.Kind) $($p.Sha256) $($p.Bytes) B  $($p.Date)" }
}

# --- Pre-build gate: the persona and the COMPOSED workspace SOUL -------------
# v1 makes the agent's injected SOUL a build-time constant: factory safety rules
# plus a fixed persona, in a fixed order. Two literals in setup.ps1 cover it, and
# both are checked here for the same reason the SOUL pin is. The composed digest
# is the one that matters, because that is the file the agent actually reads and
# the launch gate actually enforces.
#
# The composition below MUST stay byte-identical to the one in
# resources/freeze-injected-soul.sh. It is deliberately trivial (two constant
# strings around two file bodies) to keep that surface small, and a drift between
# the two fails the INSTALL loudly as well, because the script compares its own
# composed output against the digest passed to it.
$personaFile = Join-Path $RepoRoot "resources\persona.md"
if (-not (Test-Path $personaFile)) { Fail "resources/persona.md not found" }
$personaActual = (Get-FileHash -LiteralPath $personaFile -Algorithm SHA256).Hash.ToLower()
$pm = [regex]::Match($setupText, "\`$expectedPersonaHash\s*=\s*'([a-f0-9]{64})'")
if (-not $pm.Success) { Fail "setup.ps1 does not carry an `$expectedPersonaHash literal." }
if ($pm.Groups[1].Value -ne $personaActual) {
    Fail ("Persona pin drift: setup.ps1 pins $($pm.Groups[1].Value) but resources/persona.md hashes to " +
          "$personaActual. If the persona changed on purpose, update BOTH `$expectedPersonaHash and " +
          "`$expectedWorkspaceSoulHash in setup.ps1 and rebuild.")
}

Write-Host "Persona pin OK: $personaActual"

$hdr = "<!--`n" +
       "  CLAWFACTORY -- HARD SAFETY BOUNDARIES (the block below, before the persona).`n" +
       "  This file is root-owned and IMMUTABLE (chattr +i): the agent cannot modify,`n" +
       "  chmod, or delete it. A turn is REFUSED in code at launch if this file is`n" +
       "  tampered with. The boundaries below override everything that follows.`n" +
       "-->`n`n"
$sep = "`n---`n<!-- CLAWFACTORY: the text below is fixed at build time in v1. -->`n`n"
$enc = New-Object System.Text.UTF8Encoding($false)
$composed = New-Object System.Collections.Generic.List[byte]
$composed.AddRange($enc.GetBytes($hdr))
$composed.AddRange([IO.File]::ReadAllBytes($soulFile))
$composed.AddRange($enc.GetBytes($sep))
$composed.AddRange([IO.File]::ReadAllBytes($personaFile))
$sha = [System.Security.Cryptography.SHA256]::Create()
$composedHash = ([BitConverter]::ToString($sha.ComputeHash($composed.ToArray())) -replace '-','').ToLower()
$sha.Dispose()
$wm = [regex]::Match($setupText, "\`$expectedWorkspaceSoulHash\s*=\s*'([a-f0-9]{64})'")
if (-not $wm.Success) { Fail "setup.ps1 does not carry an `$expectedWorkspaceSoulHash literal." }
if ($wm.Groups[1].Value -ne $composedHash) {
    Fail ("Workspace SOUL pin drift: setup.ps1 pins $($wm.Groups[1].Value) but the composed file " +
          "(header + safety-rules.md + separator + persona.md) hashes to $composedHash. " +
          "Update `$expectedWorkspaceSoulHash to $composedHash and rebuild. If you did not change " +
          "either resource, check their line endings: .gitattributes pins both to eol=lf.")
}
Write-Host "Workspace SOUL pin OK: $composedHash ($($composed.Count) bytes composed)"

# --- Pre-build gate: the bundled Ubuntu rootfs must be the IDENTIFIED one -----
# resources\ubuntu-rootfs.tar.gz is 341 MB and gitignored, so like the Studio
# payload above, git cannot tell you whether the right bytes are sitting there.
# It is the higher risk of the two: every structural control the product sells
# runs INSIDE this filesystem, so a substitution here is underneath the nftables
# chain, both root brokers, the credential modes and the turn gate at once.
#
# Until 2026-08-05 it had no recorded source and no digest anywhere in the repo.
# It has now been identified as a stock, unmodified Canonical image and the
# digest below is UPSTREAM'S published value, not one computed from the file in
# resources\. See the setup.ps1 comment at the pin literal for the full
# provenance block (source URL, date, and what was checked).
#
#   Ubuntu 22.04.5 LTS (jammy) amd64, image built 2025-03-18
#   https://cloud-images.ubuntu.com/wsl/jammy/20250318/ubuntu-jammy-wsl-amd64-ubuntu22.04lts.rootfs.tar.gz
#   published in that directory's SHA256SUMS, retrieved 2026-08-05
#
# Fails on drift, never auto-corrects, same as every gate above.
$rootfsName   = 'ubuntu-rootfs.tar.gz'
$rootfsFile   = Join-Path $RepoRoot "resources\$rootfsName"
if (-not (Test-Path $rootfsFile)) {
    Fail ("resources\$rootfsName not found. It is gitignored; fetch it from " +
          "https://cloud-images.ubuntu.com/wsl/jammy/20250318/ubuntu-jammy-wsl-amd64-ubuntu22.04lts.rootfs.tar.gz " +
          "before building.")
}
if ($issText -notmatch [regex]::Escape("resources\$rootfsName")) {
    Fail ("ClawFactory-Secure-Setup.iss no longer bundles $rootfsName. Without it the installer " +
          "silently falls back to a network WSL install, which is not the filesystem this build was " +
          "verified against.")
}
# The expected value is read out of setup.ps1 rather than written here, so the
# literal that the INSTALL enforces is the one this gate keeps honest. A second
# copy here would only ever drift from it.
$rm = [regex]::Match($setupText, "\`$expectedRootfsHash\s*=\s*'([a-f0-9]{64})'")   # backtick, see above
if (-not $rm.Success) {
    Fail "setup.ps1 does not carry an `$expectedRootfsHash literal. The rootfs pin must be baked in at build time."
}
$rootfsPinned = $rm.Groups[1].Value
$rootfsActual = (Get-FileHash -LiteralPath $rootfsFile -Algorithm SHA256).Hash.ToLower()
if ($rootfsActual -ne $rootfsPinned) {
    Fail ("Rootfs drift: resources\$rootfsName hashes to $rootfsActual but setup.ps1 pins $rootfsPinned. " +
          "Refusing to embed an unidentified 341 MB filesystem. If the rootfs was replaced on purpose, " +
          "check the new file against the publisher's own SHA256SUMS, record the source URL and date in " +
          "the `$expectedRootfsHash comment in setup.ps1, and update the literal to $rootfsActual.")
}
Write-Host "Rootfs pin OK: $rootfsPinned"

Write-Host "Compiling installer with Inno Setup..."
& $IsccPath $issPath
if ($LASTEXITCODE -ne 0) {
    Fail "ISCC.exe compile failed (exit $LASTEXITCODE)."
}

$installerPath = Join-Path $RepoRoot "Output\ClawFactory-Secure-Setup.exe"
if (-not (Test-Path $installerPath)) {
    Fail "Expected compiled installer not found at $installerPath"
}

# --- Build stamp: the thing sign_installer.ps1 refuses to sign without --------
# Every gate above was advisory until this existed. `ISCC.exe` invoked directly
# followed by the signer produced a release-grade signed binary that had passed
# none of them, and that two-line route was the one the README taught first.
#
# The stamp is bound to the DIGEST of the unsigned bytes, not merely present, so
# a fresh direct compile cannot inherit an older stamp. It is worth being precise
# about why that holds: an Inno compile over identical inputs is byte-for-byte
# deterministic (measured 2026-08-05), so a stale stamp matches a direct compile
# only when the inputs were identical to a build that already passed the gates,
# which is the case where the gates would have passed anyway. Any input that
# would have failed a gate changes the compiled bytes and orphans the stamp.
#
# What this is NOT: a defence against anyone who can run the signer. The stamp is
# a file, and whoever can invoke sign_installer.ps1 can write one. That is
# accepted. The threat being addressed is a tired founder taking a documented
# shortcut at 2am, not an adversary with local execution. This control is
# ADVISORY against an attacker and STRUCTURAL against process drift, and it
# should never be described as more than that.
$unsignedHash = (Get-FileHash -LiteralPath $installerPath -Algorithm SHA256).Hash.ToLower()
$unsignedBytes = (Get-Item -LiteralPath $installerPath).Length

# --- Version gate, enforcement half: this version must not name OTHER BYTES ----
# Runs here because the compiled digest does not exist any earlier, and before the
# signature because an unsigned binary cannot reach a customer.
foreach ($prior in $script:PriorForThisVersion) {
    if ($prior.Kind -ne 'unsigned') {
        # A backfilled row records a SIGNED digest, which is not comparable with
        # the unsigned bytes measured here. Saying so is the honest outcome; a
        # mismatch reported from two different measurements would be a false
        # alarm, and treating it as a match would be worse.
        Write-Host ("Ledger: prior row for $buildVersion carries a $($prior.Kind) digest, which is not comparable " +
                    "with the unsigned bytes this gate measures. Not compared. Reason: $($prior.Note)")
        continue
    }
    if ($prior.Sha256 -eq $unsignedHash) {
        Write-Host "Ledger OK: $buildVersion rebuilt byte-for-byte identically to its recorded artifact."
        continue
    }
    Fail ("VERSION REUSE: $buildVersion has already shipped as $($prior.Sha256) ($($prior.Bytes) B, $($prior.Date)) " +
          "and this build produced $unsignedHash ($unsignedBytes B). The same version number would name two " +
          "different payloads, which is the defect released-versions.tsv exists to prevent. " +
          "Bump MyAppVersion in ClawFactory-Secure-Setup.iss (and `$InstallerVersion in setup.ps1 to match) and " +
          "rebuild. The unsigned output is left at $installerPath for inspection; it has NOT been signed.")
}

$stampPath    = "$installerPath.buildstamp"
$stamp = [ordered]@{
    producer      = 'scripts/build_release.ps1'
    version       = $buildVersion
    unsignedSha256 = $unsignedHash
    unsignedBytes = (Get-Item -LiteralPath $installerPath).Length
    gatesPassed   = @('soul', 'bundle', 'worktree', 'studio', 'version', 'persona', 'workspace-soul', 'rootfs')
    stampedUtc    = (Get-Date).ToUniversalTime().ToString('o')
}
# BOM-less UTF-8 on purpose; see the same note in sign_installer.ps1. PS 5.1's
# Set-Content -Encoding utf8 writes a BOM and non-PowerShell readers choke on it.
[System.IO.File]::WriteAllText($stampPath, ($stamp | ConvertTo-Json -Depth 5), (New-Object System.Text.UTF8Encoding($false)))
Write-Host "Build stamp written: $stampPath"
Write-Host "  unsigned sha256: $unsignedHash"

Write-Host "Signing compiled installer..."
$signScript = Join-Path $RepoRoot "scripts\sign_installer.ps1"
& $signScript -InstallerPath $installerPath
if ($LASTEXITCODE -ne 0) {
    Fail "Signing failed. $installerPath is UNSIGNED -- do not upload it to a GitHub Release."
}

# --- Append to the ledger, on success only -----------------------------------
# After signing, because a build that failed to sign did not ship and recording
# it would poison the gate for the next real attempt at this version. Skipped
# when this exact version and digest are already recorded, so a re-run of an
# identical build does not grow the file without saying anything new.
$already = @($script:LedgerRows | Where-Object { $_.Version -eq $buildVersion -and $_.Sha256 -eq $unsignedHash -and $_.Kind -eq 'unsigned' })
if ($already.Count -gt 0) {
    Write-Host "Ledger: this exact version and digest are already recorded; nothing appended."
} else {
    if (-not (Test-Path $ledgerPath)) {
        Fail ("released-versions.tsv is missing at signing time. It is repo-tracked and the gate depends on it; " +
              "refusing to silently recreate it, because a gate whose history can be erased by deleting a file " +
              "is not a gate.")
    }
    $row = @($buildVersion, 'ClawFactory-Secure-Setup.exe', 'unsigned', $unsignedHash, $unsignedBytes,
             (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd'),
             'written by scripts/build_release.ps1 after all gates passed and the artifact was signed') -join "`t"
    # Append with an explicit LF and no BOM. PS 5.1's Add-Content defaults to the
    # system ANSI codepage and Set-Content -Encoding utf8 writes a BOM; either
    # would corrupt a file that .gitattributes pins and that other tools parse.
    $existing = [IO.File]::ReadAllText($ledgerPath)
    if ($existing.Length -gt 0 -and -not $existing.EndsWith("`n")) { $existing += "`n" }
    [IO.File]::WriteAllText($ledgerPath, ($existing + $row + "`n"), (New-Object System.Text.UTF8Encoding($false)))
    Write-Host "Ledger: appended $buildVersion $unsignedHash ($unsignedBytes B)."
    Write-Host "  COMMIT released-versions.tsv with this build. An unrecorded release defeats the gate."
}

Write-Host ""
Write-Host "Release-ready signed installer: $installerPath"
