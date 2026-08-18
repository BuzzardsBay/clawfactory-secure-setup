<#
  interim-v120-phaselib.ps1 -- the phase runner every validation phase dot-sources.

  WHY THIS FILE EXISTS
  --------------------
  L29: a control that cannot fail is not a control, and a pass from an absent
  subject is worse than a failure. One session produced four separate results
  that looked like verdicts and were not:

    * four FAILs and a PASS from a send queue that was empty, because the phase
      assumed an SMTP credential that a fresh box does not have
    * an all-clear on absent markers from a search over a COMPRESSED payload,
      where nothing at all was findable
    * a pin that reports INFO on every successful install, so it can only speak
      once something else has already broken
    * two resource counts disagreeing on adjacent lines, both passing, because
      each side only ever counted itself

  Every one of those was caught by a human reading the transcript afterwards.
  Relying on that is relying on the reader being awake. So the discipline is
  encoded here, in the runner, where a phase author cannot forget it:

    1. A phase that registers NO positive control cannot report PASS. It reports
       VOID. Silence is not evidence.
    2. A phase whose positive control did not FIRE IN THE SAME RUN reports VOID,
       and every PASS and FAIL it recorded is downgraded with it. A measurement
       taken through an instrument that was not shown to work is not a result.
    3. A phase whose declared precondition is absent reports VOID with a NAMED
       reason. A missing precondition is never a product verdict.
    4. A held copy of a list that is never compared against what the product
       reports is not independence, it is a second stale list, so the comparison
       is a first-class call rather than something a reader is left to spot.
    5. A search for absences must first prove its target is searchable at all.
    6. A row whose verdict the runner cannot READ is recorded as VOID and named.
       An empty, null or unrecognised verdict is a measurement that was not
       taken, and it must never be counted as nothing.

  These are properties of the runner, not habits of the test author. That is the
  whole point: the previous session had the habits and still shipped four wrong
  results.

  DISCIPLINE 6, ADDED 2026-08-17, AND THE RUN THAT FORCED IT
  ---------------------------------------------------------
  Card 254 question 6. A `$2` inside a double-quoted here-string was read by
  PowerShell as a variable reference, which on the VM is a terminating error, so
  the `$(if ($mntC) { 'PASS' } else { 'FAIL' })` verdict subexpression produced
  NOTHING and five of that phase's ten Record calls arrived with an empty
  verdict argument.

  An empty string is not PASS, not FAIL and not VOID. The tally below counts the
  four verdicts it knows by exact name, so those five rows were counted as
  nothing at all, no branch of the precedence rule was reached, and the phase
  printed

      PHASE VERDICT: PASS

  over a phase in which half the checks had said nothing. That is the exact
  shape of the four defects this file was built to stop, arriving through the
  one door left open: the tally trusted the verdict string.

  So Record now READS the verdict rather than storing it. PASS, FAIL, VOID and
  INFO are the entire vocabulary. Anything else -- empty, null, whitespace, or a
  word the runner does not know -- becomes VOID, is named with its raw value,
  and withholds the phase pass.

  ROW-LEVEL OR INSTRUMENT-LEVEL, and the distinction is not cosmetic. A
  malformed verdict on a row the runner can still ACCOUNT FOR is row-level: the
  row voids, the rest of the phase stands. But when the runner cannot establish
  how many rows were affected it goes instrument-level, because a runner that
  cannot count what it lost cannot certify what survived. Two detectable cases:

    * the row has no usable id, so the void cannot be attributed to a check and
      two such rows are indistinguishable from one
    * the call arrived SHORT, with no evidence argument bound, which means the
      argument list shifted. The runner does not know which argument it is
      holding, so it does not know what else in the phase was mis-bound

  There is a third case it cannot detect at all, and it is worth stating rather
  than pretending otherwise: a Record call that THREW never reaches this
  function, so its row does not exist and nothing here can miss it. That is the
  driver's job, via probe stderr, and it is why stderr is a first-class evidence
  channel. See the close-out for 2026-08-17.

  A NOTE ON VOCABULARY, because this fix has a blast radius. The phases in this
  directory record REVIEW, UNTESTED, BLOCKED, MEASURED-BYPASS, MEASURED-HELD,
  PARTIAL, NOTE, WARN and others. Every one of those was ALREADY counted as
  nothing by the tally, and every one of them already produced the same silent
  pass. They now void loudly instead. That is the fix working, not a regression,
  but each of those call sites needs a real verdict chosen for it before the
  next validation run.

  WHAT A "POSITIVE CONTROL" MEANS HERE
  ------------------------------------
  A check that MUST SUCCEED for the phase's other measurements to be meaningful.
  It is not the same as a negative control (something that must fail, proving the
  probe discriminates), and both are useful. Register the positive one with
  Register-Control; a negative control is an ordinary Record whose expected
  verdict is a refusal.

  Example. Phase 6 blocks four sites for uid 1000. That result means nothing
  unless the same probe, in the same run, could reach SOMETHING. So the provider
  route is the positive control: if it did not connect, the four blocks are
  unmeasured rather than proven.

  EXIT CODES
  ----------
    0  phase complete, no FAIL, no VOID
    1  phase complete, at least one FAIL
    2  channel or harness fault; nothing was measured
    4  phase VOID -- the measurements were not trustworthy. Deliberately NOT 0
       and NOT 1: a driver that treats VOID as a pass repeats exactly the failure
       this file exists to stop, and one that treats it as a product failure
       manufactures defects out of harness gaps.
#>

# --- state ------------------------------------------------------------------
$script:CF_Results      = New-Object System.Collections.ArrayList
$script:CF_Controls     = New-Object System.Collections.ArrayList
$script:CF_Preconditions= New-Object System.Collections.ArrayList
$script:CF_PhaseName    = 'unnamed phase'
$script:CF_Transcript   = 'C:\cfv\phase-out-probe.txt'
$script:CF_Sentinel     = 'PHASE_PROBE_COMPLETE'

# The ENTIRE verdict vocabulary. Complete-Phase tallies by exact match against
# this list, so a verdict outside it is counted by no branch and silently
# disappears. That is not a style rule, it is the card 254 defect: keep this list
# and the tally in Complete-Phase reading from the same source, and never add a
# verdict here without adding it to the tally.
$script:CF_Verdicts     = @('PASS', 'FAIL', 'VOID', 'INFO')

# Rows whose verdict the runner could not read. Each entry carries the raw value
# and whether the damage was countable, because that decides row-level versus
# instrument-level in Complete-Phase.
$script:CF_Malformed    = New-Object System.Collections.ArrayList

function Start-Phase {
    <# Called once, first, by every phase. #>
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Transcript,
        [Parameter(Mandatory)][string]$Sentinel
    )
    $script:CF_PhaseName  = $Name
    $script:CF_Transcript = $Transcript
    $script:CF_Sentinel   = $Sentinel
    Section "$Name  $(Get-Date -Format s)"
}

function W([string]$m) {
    $line = "[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $m
    Write-Host $line
    $line | Out-File $script:CF_Transcript -Encoding utf8 -Append
}

function Section($t) { W ''; W ("=" * 72); W $t; W ("=" * 72) }

function Marker($n) { New-Item -ItemType File -Path "C:\cfv\$n.marker" -Force | Out-Null }

function Record($id, $name, $verdict, $evidence) {
    <# Records one measurement, and READS the verdict rather than storing it
       unexamined. See discipline 6 in the header for the run that forced this.

       The check is here rather than in Complete-Phase on purpose. Here the
       runner still knows how the CALL was shaped -- whether an evidence
       argument was bound at all -- and that is the only signal available for
       telling a row-level void apart from an instrument-level one. By the time
       Complete-Phase sees the row that information is gone. #>

    # Bound BEFORE anything else touches $PSBoundParameters. A short call means
    # the argument list shifted, and a shifted list means the runner does not
    # know which argument it is holding.
    $evidenceBound = $PSBoundParameters.ContainsKey('evidence')

    $raw  = $verdict
    $norm = if ($null -eq $raw) { '' } else { "$raw".Trim().ToUpperInvariant() }

    if ($script:CF_Verdicts -contains $norm) {
        $final           = $norm
        $malformedReason = ''
        $emitEvidence    = $evidence
    } else {
        # Name the raw value in a form that survives the transcript. An empty
        # string and a null are different defects with different causes, and
        # printing both as nothing is how this went unnoticed the first time.
        $shown =
            if ($null -eq $raw)                   { '<null>' }
            elseif ("$raw" -eq '')                { '<empty string>' }
            elseif ([string]::IsNullOrWhiteSpace("$raw")) { "<whitespace only, $(("$raw").Length) chars>" }
            else                                  { "'$raw'" }

        $idBlank    = [string]::IsNullOrWhiteSpace("$id")
        $countable  = (-not $idBlank) -and $evidenceBound

        $why = "recorded the verdict $shown, which is not one of $($script:CF_Verdicts -join ', '). " +
               'A verdict the runner cannot read is a measurement it did not get, so this row is VOID.'
        if ($idBlank) {
            $why += ' It also arrived with NO ID, so this void cannot be attributed to a named check' +
                    ' and two such rows cannot be told apart.'
        }
        if (-not $evidenceBound) {
            $why += ' It also arrived SHORT, with no evidence argument bound, so the argument list' +
                    ' shifted and the runner does not know what else in this phase was mis-bound.'
        }
        if (-not $countable) {
            $why += ' The extent of the damage is therefore unknown, which makes this instrument-level:' +
                    ' a runner that cannot count what it lost cannot certify what survived.'
        }

        $final           = 'VOID'
        $malformedReason = "malformed verdict: $(if ($idBlank) { '<unnamed row>' } else { "$id" }) $name -- $why"
        $emitEvidence    = ("$evidence" + $(if ("$evidence") { ' | ' } else { '' }) + "RUNNER: $why")

        [void]$script:CF_Malformed.Add([pscustomobject]@{
            Id = "$id"; Name = "$name"; Raw = $shown; Countable = $countable; Reason = $malformedReason
        })
    }

    [void]$script:CF_Results.Add([pscustomobject]@{
        Id = $id; Name = $name; Verdict = $final; RawVerdict = $raw
        MalformedReason = $malformedReason; Evidence = $emitEvidence
    })
    W ("  [{0}] {1} :: {2}" -f $final, $id, $name)
    if ($emitEvidence) { W ("        {0}" -f ($emitEvidence -replace "`r?`n", ' | ')) }
}

function Register-Control {
    <# THE LOAD-BEARING CALL IN THIS FILE.

       Declares a check that MUST have succeeded in THIS run for the phase's
       other measurements to mean anything. If it did not fire, Complete-Phase
       voids the whole phase rather than reporting the measurements it enabled.

       -Fired is the boolean the phase computed from real output. Passing a
       constant $true would defeat this entirely, which is a thing a reviewer
       can check for by reading one line. #>
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][AllowNull()][object]$Fired,
        [string]$Evidence = ''
    )
    $ok = [bool]$Fired
    [void]$script:CF_Controls.Add([pscustomobject]@{ Id = $Id; Name = $Name; Fired = $ok; Evidence = $Evidence })
    Record $Id "POSITIVE CONTROL: $Name" $(if ($ok) { 'PASS' } else { 'FAIL' }) `
        ("$Evidence" + $(if ($ok) { '' } else { ' -- this control did not fire, so every measurement it underwrites is VOID' }))
    return $ok
}

function Require-Precondition {
    <# Declares something the phase needs before it can measure anything, and
       records VOID with a NAMED reason when it is absent.

       Phase 6 is the worked example this exists for: no SMTP credential means
       the send queue is empty, so "the broker refused" and "there was nothing to
       refuse" are indistinguishable. The right output there is VOID and the
       reason, not four FAILs and a PASS.

       Returns $true when the precondition holds, so the caller can skip the
       measurement entirely rather than take it and have it thrown away. #>
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][AllowNull()][object]$Met,
        [Parameter(Mandatory)][string]$Reason
    )
    $ok = [bool]$Met
    [void]$script:CF_Preconditions.Add([pscustomobject]@{ Id = $Id; Name = $Name; Met = $ok; Reason = $Reason })
    if ($ok) {
        Record $Id "PRECONDITION: $Name" 'PASS' $Reason
    } else {
        Record $Id "PRECONDITION: $Name" 'VOID' "NOT MET: $Reason. Nothing downstream of this is a product verdict."
    }
    return $ok
}

function Assert-Searchable {
    <# A search that reports "the bad marker is absent" has said nothing unless
       the same search could find something it was supposed to find.

       The case this is built from: twenty-six panel markers were searched for in
       a compiled NSIS installer. The payload is compressed, so the search found
       NOTHING, and the absent-marker section printed a clean all-clear. Only the
       positive control caught it.

       So this both registers a positive control AND records the searchability
       finding, because the two are the same fact. #>
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][AllowNull()][object]$PositiveMarkerFound,
        [Parameter(Mandatory)][string]$MarkerDescription
    )
    $ok = [bool]$PositiveMarkerFound
    $ev = if ($ok) {
        "the target is searchable: $MarkerDescription was found, so an absence in this search is real"
    } else {
        "the target is NOT searchable: $MarkerDescription was not found either, so every 'absent' result here is meaningless (a compressed or encoded payload finds nothing and reads as clean)"
    }
    return (Register-Control -Id $Id -Name "search target is searchable ($Name)" -Fired $ok -Evidence $ev)
}

function Compare-Independent {
    <# Reconcile a copy this harness holds against the value the PRODUCT reports.

       Holding an independent copy is only independence if the two are actually
       compared. On 2026-08-14 a phase printed "installer reports 33 resources"
       and "all 30 required resources present" on adjacent lines and passed both.
       Disagreement IS the finding, and it must name both numbers. #>
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][AllowNull()][object]$Mine,
        [Parameter(Mandatory)][AllowNull()][object]$Reported,
        [string]$MineLabel     = 'this harness',
        [string]$ReportedLabel = 'the product'
    )
    if ($null -eq $Reported -or "$Reported" -eq '') {
        Record $Id $Name 'VOID' `
            "$ReportedLabel reported nothing to compare against; $MineLabel holds $Mine. An uncompared copy is a second stale list, not independence."
        return $false
    }
    $agree = ("$Mine" -eq "$Reported")
    Record $Id $Name $(if ($agree) { 'PASS' } else { 'FAIL' }) `
        "$MineLabel has $Mine; $ReportedLabel reports $Reported.$(if (-not $agree) { ' They disagree, so one of the two is stale. The disagreement IS the finding.' })"
    return $agree
}

function Complete-Phase {
    <# The gate. Computes the phase verdict and writes both channels.

       Order matters. Preconditions are checked first, because an unmet
       precondition explains an unfired control and reporting both as separate
       problems sends the reader chasing two ghosts. #>
    param(
        [Parameter(Mandatory)][string]$ResultsJson,
        [string]$MarkerPrefix = 'PHASE'
    )

    Section "Result table: $($script:CF_PhaseName)"

    $unmet    = @($script:CF_Preconditions | Where-Object { -not $_.Met })
    $unfired  = @($script:CF_Controls      | Where-Object { -not $_.Fired })
    $noControl = ($script:CF_Controls.Count -eq 0)

    # TWO KINDS OF VOID, and collapsing them loses information a reader needs.
    #
    # INSTRUMENT-LEVEL. No positive control, a control that did not fire, or an
    # unmet precondition. The instrument itself was never shown to work, so every
    # measurement taken with it is unsafe, including the ones that look like
    # failures. These downgrade the whole phase.
    #
    # ROW-LEVEL. One specific measurement could not be taken -- an address
    # collision made a disjointness test unmeasurable, say -- while the rest of
    # the phase measured fine. Voiding the other nineteen results because of it
    # would discard good evidence and push an author towards not recording the
    # void at all. So those rows stand, and only the PHASE VERDICT is withheld.
    #
    # Either way the phase does not exit 0. A run carrying an unmeasured check is
    # not a clean pass, and the distinction is about which rows survive, never
    # about whether the phase can still be called green.
    $instrumentReasons = @()
    if ($noControl) {
        $instrumentReasons += 'this phase registered NO positive control, so nothing it measured can be reported as a pass'
    }
    foreach ($u in $unmet)   { $instrumentReasons += "precondition not met: $($u.Id) $($u.Name) -- $($u.Reason)" }
    foreach ($u in $unfired) { $instrumentReasons += "positive control did not fire: $($u.Id) $($u.Name)" }

    # An UNCOUNTABLE malformed verdict is instrument-level. Record already made
    # the call, because only Record could see the shape of the invocation.
    foreach ($m in @($script:CF_Malformed | Where-Object { -not $_.Countable })) {
        $instrumentReasons += $m.Reason
    }

    # THE BACKSTOP. Record normalises every verdict into $script:CF_Verdicts, so
    # this can only fire if something bypassed it -- a future edit, or a row
    # pushed into CF_Results directly. It exists because the tally below counts
    # by exact name, and a row it cannot count is a row that vanishes silently.
    # An assertion that never fires is the cheapest thing in this file and it is
    # the one that would have caught card 254 on its own.
    $unreadable = @($script:CF_Results | Where-Object { $script:CF_Verdicts -notcontains "$($_.Verdict)" })
    if ($unreadable.Count -gt 0) {
        $instrumentReasons += ("$($unreadable.Count) row(s) carry a verdict this runner cannot count: " +
            (@($unreadable | ForEach-Object { "$($_.Id)=[$($_.Verdict)]" }) -join ', ') +
            '. The tally would have dropped them, so the phase total is not a total.')
    }

    $rowVoids = @($script:CF_Results | Where-Object { $_.Verdict -eq 'VOID' })
    $rowReasons = @()
    foreach ($r in $rowVoids) {
        # A malformed row explains itself and names its raw value. A deliberate
        # VOID from Require-Precondition or Compare-Independent does not, so it
        # keeps the generic line.
        if ("$($r.MalformedReason)") {
            # Skip the uncountable ones: they are already listed above as
            # instrument reasons, and printing one defect twice makes a reader
            # chase two ghosts, which is the thing the ordering comment warns of.
            if ($instrumentReasons -notcontains $r.MalformedReason) { $rowReasons += $r.MalformedReason }
        }
        else { $rowReasons += "a check could not be measured: $($r.Id) $($r.Name)" }
    }

    $instrumentVoid = ($instrumentReasons.Count -gt 0)
    $phaseVoid      = $instrumentVoid -or ($rowVoids.Count -gt 0)
    $voidReasons    = @($instrumentReasons) + @($rowReasons)

    # Downgrade, but ONLY on an instrument-level void. A PASS taken through an
    # instrument that was not shown to work is not a PASS, and neither is the
    # FAIL beside it: both are unmeasured. The ORIGINAL verdict is kept alongside
    # so the transcript still shows what the probe saw, which is what a person
    # debugging the harness needs.
    $emitted = New-Object System.Collections.ArrayList
    foreach ($r in $script:CF_Results) {
        $v = $r.Verdict
        if ($instrumentVoid -and ($v -eq 'PASS' -or $v -eq 'FAIL')) { $v = 'VOID' }
        [void]$emitted.Add([pscustomobject]@{
            Id = $r.Id; Name = $r.Name; Verdict = $v; OriginalVerdict = $r.Verdict
            RawVerdict = $r.RawVerdict; MalformedReason = $r.MalformedReason; Evidence = $r.Evidence
        })
    }

    foreach ($row in $emitted) {
        $suffix = if ($row.Verdict -ne $row.OriginalVerdict) { "  (was $($row.OriginalVerdict), voided with the phase)" } else { '' }
        W ("{0,-24} {1,-6} {2}{3}" -f $row.Id, $row.Verdict, $row.Name, $suffix)
    }

    $nPass = @($emitted | Where-Object Verdict -eq 'PASS').Count
    $nFail = @($emitted | Where-Object Verdict -eq 'FAIL').Count
    $nVoid = @($emitted | Where-Object Verdict -eq 'VOID').Count
    $nInfo = @($emitted | Where-Object Verdict -eq 'INFO').Count
    W ''
    # The tally is printed WITH the row count it was taken over. Card 254 printed
    # a tally of five over a table of ten and nothing in the output said so.
    W "PASS=$nPass FAIL=$nFail VOID=$nVoid INFO=$nInfo  (counted $($nPass + $nFail + $nVoid + $nInfo) of $($emitted.Count) recorded rows)"
    if ($script:CF_Malformed.Count -gt 0) {
        W ("malformed verdicts={0} (countable={1}, uncountable={2}) -- every one of these was recorded as VOID" -f `
            $script:CF_Malformed.Count,
            @($script:CF_Malformed | Where-Object Countable).Count,
            @($script:CF_Malformed | Where-Object { -not $_.Countable }).Count)
        foreach ($m in $script:CF_Malformed) { W ("    raw verdict {0} on row {1}" -f $m.Raw, $(if ("$($m.Id)") { $m.Id } else { '<unnamed>' })) }
    }
    W "positive controls registered=$($script:CF_Controls.Count) fired=$(@($script:CF_Controls | Where-Object Fired).Count)"
    W "preconditions declared=$($script:CF_Preconditions.Count) met=$(@($script:CF_Preconditions | Where-Object Met).Count)"

    # Precedence. An instrument-level void outranks everything, because it says
    # the other numbers are not numbers. A real FAIL outranks a row-level void,
    # because a product defect is the more actionable finding and the unmeasured
    # rows are still listed above it. A row-level void alone still withholds the
    # pass.
    $phaseVerdict =
        if ($instrumentVoid)     { 'VOID' }
        elseif ($nFail -gt 0)    { 'FAIL' }
        elseif ($phaseVoid)      { 'VOID' }
        else                     { 'PASS' }

    $payload = [pscustomobject]@{
        Phase             = $script:CF_PhaseName
        PhaseVerdict      = $phaseVerdict
        VoidKind          = $(if ($instrumentVoid) { 'instrument' } elseif ($rowVoids.Count -gt 0) { 'row' } else { 'none' })
        VoidReasons       = $voidReasons
        InstrumentReasons = $instrumentReasons
        RowVoidReasons    = $rowReasons
        MalformedVerdicts = @($script:CF_Malformed)
        RowsRecorded      = $emitted.Count
        RowsCounted       = ($nPass + $nFail + $nVoid + $nInfo)
        Controls          = @($script:CF_Controls)
        Preconditions     = @($script:CF_Preconditions)
        Results           = @($emitted)
    }
    $payload | ConvertTo-Json -Depth 6 | Out-File $ResultsJson -Encoding utf8

    if ($instrumentVoid) {
        W ''
        W 'PHASE VERDICT: VOID (instrument). This phase reports no product result at all.'
        foreach ($r in $instrumentReasons) { W "   VOID because: $r" }
        W 'Every PASS and FAIL above was downgraded: the instrument was never shown to work in this run.'
        W 'A VOID phase is a MISSING MEASUREMENT, not a passing product and not a failing one.'
        Marker "$($MarkerPrefix)_VOID"
        W ''
        W "$($script:CF_Sentinel) rc=4"
        exit 4
    }

    if ($nFail -gt 0) {
        W ''
        W 'PHASE VERDICT: FAIL. Failing checks:'
        foreach ($f in @($emitted | Where-Object Verdict -eq 'FAIL')) { W "   FAIL $($f.Id) $($f.Name) :: $($f.Evidence)" }
        if ($rowVoids.Count -gt 0) {
            W "   plus $($rowVoids.Count) check(s) that could not be measured at all:"
            foreach ($r in $rowReasons) { W "     $r" }
        }
        Marker "$($MarkerPrefix)_FAIL"
        W ''
        W "$($script:CF_Sentinel) rc=1"
        exit 1
    }

    if ($phaseVoid) {
        W ''
        W 'PHASE VERDICT: VOID (incomplete). Nothing FAILED, but not every check was measured,'
        W 'so this phase is not a clean pass and must not be reported as one.'
        foreach ($r in $rowReasons) { W "   unmeasured: $r" }
        W 'The measured rows above stand: the instrument was sound, these specific checks were not takeable.'
        Marker "$($MarkerPrefix)_VOID"
        W ''
        W "$($script:CF_Sentinel) rc=4"
        exit 4
    }

    W ''
    W 'PHASE VERDICT: PASS. Every positive control fired and every precondition was met.'
    Marker "$($MarkerPrefix)_PASS"
    W ''
    W "$($script:CF_Sentinel) rc=0"
    exit 0
}
