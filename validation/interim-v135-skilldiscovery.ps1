<#
  TASK 1, STEP 1 of 2: WHAT DOES "SKILL INSTALLATION" ACTUALLY RUN?

  This probe measures nothing about the toggle. It answers the question that has
  to be answered before the toggle can be measured at all: what command performs
  a skill installation on this product, and which host does it talk to.

  WHY THIS IS A SEPARATE PROBE, AND NOT SECTION 0 OF THE REAL ONE
  ---------------------------------------------------------------
  The finding on the table is that clawhub.ai and openclaw.ai share the address
  216.150.1.1, openclaw.ai is a permanent base host, and therefore clawhub.ai
  stays reachable with the toolchain toggle off while the Studio panel says the
  toggle stops skill installation. But api.clawhub.ai measured BLOCKED and only
  bare clawhub.ai measured CONNECTED. If installation talks to the API host, the
  panel copy is accurate as written and the finding downgrades to "a website
  stays reachable", which the footnote already discloses by saying matching is
  by address.

  So the whole adjudication turns on which host the installer uses. Writing a
  phase against a GUESSED command name would produce a confident answer about a
  code path the product does not have. The repo's own recon note
  (docs/session_reports/PHASE0_RECON_2026-07-13.md) records `openclaw plugins
  install <npm-spec>`, npm-registry specs only, which if still true would mean
  installation talks to registry.npmjs.org and NEITHER clawhub host. That would
  change the answer again. It is a year-old note about a pinned upstream and it
  is not evidence about the shipped build.

  Everything here is INFO. There is no subject and no verdict, because a
  discovery probe that renders PASS/FAIL invites its guesses being read as
  measurements. The one control present is the channel control, because a
  fabricated transcript would be worse here than anywhere: it would silently
  choose the command the real phase is then built around.

  The toggle is NOT touched. This probe must leave the box exactly as it found
  it, because the phase that follows sets its own preconditions and an inherited
  half-changed state is what the runner voids for.
#>
param(
    [string]$Transcript = 'C:\cfv\skilldiscovery-out-probe.txt'
)

$ErrorActionPreference = 'Continue'
. C:\cfv\interim-v120-wslchan.ps1
. C:\cfv\interim-v120-phaselib.ps1

Start-Phase -Name 'Task 1 step 1: discover the real skill-installation command and its hosts' `
    -Transcript $Transcript -Sentinel 'SKILLDISCOVERY_PROBE_COMPLETE'

$chan = Test-WslChannel
Register-Control -Id 'SD.CHAN' -Name 'the file-based WSL channel discriminates' `
    -Fired $chan.Ok -Evidence $chan.Detail | Out-Null
if (-not $chan.Ok) {
    W 'CHANNEL UNTRUSTWORTHY, stopping (L22).'
    Complete-Phase -ResultsJson 'C:\cfv\skilldiscovery-results.json' -MarkerPrefix 'SKILLDISCOVERY'
}

# =========================================================================
Section '0. Starting state, recorded so the next phase does not inherit a guess'
# The handoff for this job warns that the toolchain toggle was left ON by the
# #261 diagnostic while SP.9 reports it OFF. This probe does not fix that. It
# records what is actually true right now, so the phase that follows can set the
# precondition rather than assume one.
$state = Invoke-WslFile -Tag 'sd-state' -User 'root' -Body @'
echo "POLICY_ENABLED=$(node -e 'const p=require("/etc/clawfactory/egress-policy.json");process.stdout.write(String(!p.toolchain||p.toolchain.enabled!==false))' 2>/dev/null || echo unknown)"
echo "TOOLCHAIN_SET_COUNT=$(nft list set inet clawfactory toolchain_ipv4 2>/dev/null | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | sort -u | wc -l)"
echo "ALLOWED_SET_COUNT=$(nft list set inet clawfactory allowed_ipv4 2>/dev/null | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | sort -u | wc -l)"
echo "--- CONTROL: a set name that must not exist, so an empty read is not mistaken for a working read ---"
nft list set inet clawfactory not_a_real_set >/dev/null 2>&1 && echo "STATE_CONTROL=FAILED" || echo "STATE_CONTROL=OK"
'@
W $state.Out
$stateCtl = $state.Out -match 'STATE_CONTROL=OK'
Register-Control -Id 'SD.0.CTL' -Name 'the nft read discriminates a real set from a bogus one' `
    -Fired $stateCtl -Evidence 'a nonexistent set name did not resolve' | Out-Null
Record 'SD.0' 'The toolchain toggle state as actually found, before anything is touched' 'INFO' `
    ("policy enabled=$(if ($state.Out -match 'POLICY_ENABLED=(\w+)') { $Matches[1] } else { '?' }), " +
     "toolchain_ipv4 holds $(if ($state.Out -match 'TOOLCHAIN_SET_COUNT=(\d+)') { $Matches[1] } else { '?' }) address(es), " +
     "allowed_ipv4 holds $(if ($state.Out -match 'ALLOWED_SET_COUNT=(\d+)') { $Matches[1] } else { '?' }). " +
     'Recorded, not corrected. The handoff warns SP.9 reports the toggle OFF while a later diagnostic left it ON.')

# =========================================================================
Section '1. What subcommands does the shipped CLI actually have?'
# Run as clawuser, because that is the uid a skill installation would run under
# and a root PATH could resolve a binary the agent cannot reach.
$cli = Invoke-WslFile -Tag 'sd-cli' -User 'clawuser' -Body @'
echo "whoami=$(id -un) uid=$(id -u)"
echo "OPENCLAW_BIN=$(command -v openclaw || echo NONE)"
echo "OPENCLAW_VERSION=$(openclaw --version 2>&1 | head -3)"
echo "--- top-level help ---"
openclaw --help 2>&1 | head -80
echo "--- does a skills noun exist? ---"
if openclaw skills --help >/dev/null 2>&1; then echo "NOUN_SKILLS=yes"; else echo "NOUN_SKILLS=no"; fi
if openclaw plugins --help >/dev/null 2>&1; then echo "NOUN_PLUGINS=yes"; else echo "NOUN_PLUGINS=no"; fi
echo "--- CONTROL: a noun that cannot exist, so NOUN_*=yes is not simply what this shell always says ---"
if openclaw notarealnoun --help >/dev/null 2>&1; then echo "NOUN_CONTROL=FAILED"; else echo "NOUN_CONTROL=OK"; fi
'@
W $cli.Out
$nounCtl = $cli.Out -match 'NOUN_CONTROL=OK'
Register-Control -Id 'SD.1.CTL' -Name 'the subcommand probe can say no' `
    -Fired $nounCtl -Evidence 'a fabricated subcommand was rejected, so a yes for skills or plugins is a real yes' | Out-Null
$hasSkills  = $cli.Out -match 'NOUN_SKILLS=yes'
$hasPlugins = $cli.Out -match 'NOUN_PLUGINS=yes'
Record 'SD.1' 'Which installation nouns the shipped CLI exposes to uid 1000' 'INFO' `
    "skills=$hasSkills plugins=$hasPlugins. The full help text is in the transcript above."

# =========================================================================
Section '2. The help text for whichever noun exists, and its registry/source'
$sub = Invoke-WslFile -Tag 'sd-sub' -User 'clawuser' -Body @'
for n in skills plugins; do
  if openclaw "$n" --help >/dev/null 2>&1; then
    echo "=== openclaw $n --help ==="
    openclaw "$n" --help 2>&1 | head -60
    echo "=== openclaw $n install --help ==="
    openclaw "$n" install --help 2>&1 | head -60
  fi
done
echo "--- any configured registry or hub base URL, names only, values printed because they are hostnames and not secrets ---"
grep -rhoE 'https?://[A-Za-z0-9._-]*(clawhub|openclaw|npmjs)[A-Za-z0-9._/-]*' /home/clawuser/.openclaw/openclaw.json 2>/dev/null | sort -u | head -20
echo "--- installed skill or plugin directories, so the next phase knows what a successful install looks like on disk ---"
for d in /home/clawuser/.openclaw/skills /home/clawuser/.openclaw/plugins /home/clawuser/.claw/skills; do
  if [ -d "$d" ]; then echo "DIR_PRESENT $d"; ls -1 "$d" 2>/dev/null | head -20 | sed 's/^/  entry: /'; else echo "DIR_ABSENT $d"; fi
done
'@
W $sub.Out
Record 'SD.2' 'The install subcommand help, the configured hub base URL, and the on-disk install location' 'INFO' `
    'read from the shipped CLI and the live config; the next phase is built against this, not against a year-old recon note'

# =========================================================================
Section '3. What the search/registry call talks to, WITHOUT installing anything'
# A search or registry-list call is the cheapest thing that exercises the same
# network path as an install. It is run here only to name the host; the real
# phase runs a real installation end to end, because a search that reaches the
# hub proves nothing about whether an install can complete.
#
# strace is not assumed present. The host is read from the connections the
# process actually opens, via ss, sampled while the call runs.
$net = Invoke-WslFile -Tag 'sd-net' -User 'root' -Body @'
echo "--- addresses the toolchain hosts resolve to right now, so the next phase can attribute a drop to a host ---"
for h in clawhub.ai api.clawhub.ai openclaw.ai registry.npmjs.org api.github.com codeload.github.com; do
  echo "RESOLVE $h -> $(getent ahostsv4 "$h" 2>/dev/null | awk '{print $1}' | sort -u | tr '\n' ' ')"
done
echo "--- which of those addresses are currently in each set ---"
for s in allowed_ipv4 toolchain_ipv4; do
  echo "SET $s: $(nft list set inet clawfactory $s 2>/dev/null | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | sort -u | tr '\n' ' ')"
done
echo "--- CONTROL: an address that must be in NEITHER set, so a membership hit is not this grep saying yes to everything ---"
CAL=$(getent ahostsv4 example.org 2>/dev/null | awk '{print $1}' | head -1)
echo "CONTROL_ADDR=$CAL"
if nft list set inet clawfactory allowed_ipv4 2>/dev/null | grep -q "\b$CAL\b"; then echo "MEMBERSHIP_CONTROL=FAILED"; else echo "MEMBERSHIP_CONTROL=OK"; fi
'@
W $net.Out
$memCtl = $net.Out -match 'MEMBERSHIP_CONTROL=OK'
Register-Control -Id 'SD.3.CTL' -Name 'the set-membership read can say no' `
    -Fired $memCtl -Evidence 'an un-allowlisted address was not found in allowed_ipv4' | Out-Null
Record 'SD.3' 'Current resolution of every candidate install host and its set membership' 'INFO' `
    'this is the attribution table the real phase uses to turn a dropped address back into a hostname'

Complete-Phase -ResultsJson 'C:\cfv\skilldiscovery-results.json' -MarkerPrefix 'SKILLDISCOVERY'
