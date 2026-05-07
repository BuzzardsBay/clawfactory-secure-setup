# ClawFactory v1.0.9 Azure Validation Report

- **Timestamp (UTC):** 2026-05-07 18:12 - 19:05 UTC
- **Commit:** bc14fd5 -- v1.0.9: fix Step-EnsureWsl exit code routing to reboot-and-resume path
- **VM:** cfv-122326, Standard_D2s_v5, from clawfactory-win11-baseline (westus2)
- **Run duration (wall clock):** ~53 min total (~30 min quota/cleanup overhead; active install attempt ~23 min: 18:40 reboot -> 18:43 crash)

---

## Verdict: FAIL

setup.ps1 failed at **parse time**. PowerShell 5.1 misread UTF-8 em-dash characters
as Windows-1252, decoding byte `0x94` as `"` (RIGHT DOUBLE QUOTATION MARK, U+201D),
which PS treats as a string terminator. Line 597's double-quoted string broke, cascaded
to an unclosed `if {}` on line 596, and left `function Step-EnsureWsl` (line 506)
without its closing `}`. The parser threw before a single line of setup.ps1 executed --
no log file was created, no WSL install was attempted, no reboot occurred.

---

## Install

- **Duration:** ~2 seconds (18:43:41 launch -> 18:43:43 exit; InnoSetup extraction was ~60s prior)
- **Exit code:** 1 (setup.ps1 ParseError propagated through InnoSetup Run entry)
- **Did VM reboot mid-install (Step-EnsureWsl)?** No -- parse failure prevented any code from running
- **Did installer resume after reboot?** N/A

### First (and only) failure point

```
At C:\Program Files\ClawFactory\setup.ps1:506 char:25
+ function Step-EnsureWsl {
+                         ~
Missing closing '}' in statement block or type definition.
    + FullyQualifiedErrorId : MissingEndCurlyBrace
```

No `C:\ProgramData\ClawFactory\install.log` was created (log dir never initialized).

### InnoSetup stdout (`C:\install-stdout.log`)

InnoSetup completed successfully -- all files extracted to `C:\Program Files\ClawFactory\`,
shortcuts created, uninstall key written. The Run entry launched setup.ps1 as current user
(clawadmin), which exited 1 after ~2 seconds.

```
2026-05-07 18:43:41.912   Installation process succeeded.
2026-05-07 18:43:41.917   -- Run entry --
2026-05-07 18:43:41.917   Run as: Current user
2026-05-07 18:43:41.917   Filename: powershell.exe
2026-05-07 18:43:41.917   Parameters: -NoProfile -ExecutionPolicy Bypass
                           -File "C:\Program Files\ClawFactory\setup.ps1"
                           -AcknowledgedOpenClawUrl -Provider grok
                           -SourceExe "C:\install\ClawFactory.exe"
                           -BundledRootfsDir "C:\Users\CLAWAD~1\AppData\Local\Temp\is-9AHQ3KV8QT.tmp"
2026-05-07 18:43:43.335   Process exit code: 1
2026-05-07 18:43:43.341   Need to restart Windows? No
2026-05-07 18:43:43.466   Log closed.
```

### Root cause analysis

`setup.ps1` contains em-dash characters (U+2014) encoded as UTF-8 (`0xE2 0x80 0x94`)
but the file ships **with no UTF-8 BOM**. PowerShell 5.1, when invoked with `-File`,
reads scripts with no BOM using the system default ANSI code page (Windows-1252 on
en-US VMs). In Windows-1252, byte `0x94` maps to **U+201D (RIGHT DOUBLE QUOTATION
MARK)**, which PowerShell's parser accepts as a string terminator.

Affected line (example -- at least 5 similar lines in the function):

```
# setup.ps1 line 597 (inside Step-EnsureWsl)
Write-Log INFO "wsl --install returned $wslRc (elevation required or reboot pending)
               [em-dash] proceeding to reboot-and-resume path."
```

When read as Windows-1252 the em-dash bytes `0xE2 0x80 0x94` become `a[euro]"`.
The `0x94` byte (`"`) terminates the double-quoted string at `...pending) a[euro]`,
leaving ` proceeding to reboot-and-resume path."` as unparsed tokens. The trailing
`"` opens a new unclosed string. This causes:

1. The `if ($wslRc -notin @(0, 3010)) {` block (line 596) to lose its closing `}`
2. `function Step-EnsureWsl` (line 506) to lose its closing `}`
3. PS reports parse error at line 506 char 25

**Verification:** `[System.Management.Automation.Language.Parser]::ParseInput()` with
explicit UTF-8 decoding returns **0 errors**. `powershell.exe -File setup.ps1` (ANSI
default) returns **3 errors** including MissingEndCurlyBrace at line 506.

**Fix required:** Add UTF-8 BOM to setup.ps1 so PS 5.1 reads it as UTF-8, OR replace
all em-dash characters with ASCII alternatives (` - ` or ` -- `). The em-dash appears
in double-quoted Write-Log strings in Step-EnsureWsl and likely elsewhere.

---

## Smoke Test

Skipped -- installer did not complete.

---

## Idle Test

Skipped -- installer did not complete.

---

## Notes

**Quota blocker (pre-run):** Two VMs from prior FAIL runs (test-vm-185144 from v1.0.7;
test-vm-20260507095304 from v1.0.8) were deallocated but still held the 4-core regional
vCPU quota. Both VMs and disks were deleted with explicit user authorization before this
run could proceed.

**VM name constraint:** Prior names (e.g. `test-vm-20260507122150`, 22 chars) exceeded
Windows' 15-character hostname limit, causing DeploymentFailed/InvalidParameter. New
naming scheme uses `cfv-HHMMSS` (10 chars).

**Preserved disk for forensics:**
- OS Disk: `cfv-122326_disk1_319a774c2aa84bb885bed93e3abfc506`
- Resource group: `clawfactory-validation`
- VM: `cfv-122326` -- deallocated (not deleted) per FAIL cleanup policy

**Logs saved:**
- `validation-runs/v1.0.9-20260507-122326/install.log` -- stdout log + error analysis
- `validation-runs/v1.0.9-20260507-122326/run-meta.txt` -- run metadata
