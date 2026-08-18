# Close-out: the provider route missing from the egress allow-list

Session 2026-08-18. Dispatch card #257. Input artifact 1.3.4, signed
`ee6a5cd0232d7eb039182fe45e967cf2407e4ccd70f2e06540e06c93b89b5214`, 440,607,456
bytes, Authenticode Valid, verified byte for byte on disk before anything was
read or changed.

**STATUS: IN PROGRESS.** This file is written early and honestly rather than at
the end, so that an error-terminated session still leaves a truthful record
rather than nothing. It is updated in place as measurements land. If it still
says IN PROGRESS, the VM run had not returned and nothing below the line marked
PENDING has been measured.

---

## 1. Pre-flight

**Prompt library.** PROMPT 15 is present at
`C:\Users\bmcki\OneDrive\Desktop\Claude Prompts\FrontierAI_CC_Prompt_Library.md`
line 645 and runs to the end of the file, carrying the close-out gate, the four
pre-flight checks, the calibrate-before-measuring rule, the
instruction-challenge clause, the measurement and shell rules, the handoff
cards, the resource ledger and the credential rules. Not truncated, not stale.

**The correction the job asked to be recorded.** The previous job instructed the
deletion of a superseded prompt file that does not exist on this machine. Nothing
was deleted and nothing should have been. Recorded here in one line, as
instructed, and not investigated further.

**Comprehension.** What changes: nothing in the shipped product unless a root
cause is confirmed by measurement. What is written regardless: a source-read
artefact, a calibration-gated probe, a re-specification of TC.3, and this
close-out. Checked against the repo rather than the prompt, which is where two of
the job's four candidates died.

**Dependency census.** Run tree-wide and reported in full in
`docs/session_reports/2026-08-18_provider_route_source_read.md` section 1: five
sites seed or refresh a provider hostname, four of them resolve, and the fifth
replays a persisted file. The WHEN half is section 5 of the same artefact: every
seed site precedes the first moment a turn can be requested.

**Failure-mode walk.** The candidate fix, mirroring the toolchain path's three
unioned resolve passes into the provider path, does exactly what it says and
still does not close the gap, because an address set cannot follow a name that
moves. That is stated as a residual rather than discovered later. The second
candidate fix, an install-time reachability check, breaks nothing at steady
state but WOULD refuse installs on a box whose provider is unreachable for an
unrelated reason, such as a corporate proxy. That is the intended behaviour and
it is a product decision, so it is reported rather than built.

**Input-shape sweep.** No new value is read by any shipped code in this session.
The probe reads three: an nft set listing (present, empty, unreadable, all three
distinguished by an explicit control), a kernel log buffer (marked by line offset
so a wrapped buffer under-reports rather than misreports), and a resolver answer
(present, absent and NXDOMAIN separated by two controls).

**Instruction challenge.** One deviation from PROMPT 15, taken deliberately and
recorded rather than applied silently. The preamble says not to call
`az vm user update` after provisioning and to hand the operator a card so they
set the admin password themselves. Those clauses exist for runs where a human
must reach the box over RDP. This run has no human step: no RDP rule is opened at
all (`--nsg-rule NONE`), nothing reboots after the install, and every measurement
goes through `az vm run-command` and the on-VM job runner. The proven harness
`validation/interim-v120-validate.ps1` generates the password in memory, never
prints it and never writes it, and its `az vm user update` call is checked
because an unchecked one cost cfv-162 an hour. Substituting a hand-driven
password flow into a proven harness under ship-blocker pressure, to satisfy a
clause aimed at a case that does not arise here, is exactly the kind of
improvisation the job warns against.

## 2. Task 0: resource ledger, starting state

Unfiltered resource list for `clawfactory-validation` before anything was
provisioned:

```
clawfactoryvalc467             storageAccounts
bake-vmVNET                    virtualNetworks
clawfactory-win11-baseline     images
clawfactory-win11-baseline-v2  images
```

That is exactly the expected residual and nothing else. Zero VMs in the
subscription, so no prior FAIL VMs, disks, NICs, public IPs or NSGs to sweep.

`cfv-168` provisioned for this session, `Standard_D2s_v4`,
`clawfactory-win11-baseline-v2`, machine_id `bbc62062-20bb-492e-9be3-ecf31c9e38f7`.

## 3. Task 1: the source read

Delivered in full, with file and line for every claim, at
`docs/session_reports/2026-08-18_provider_route_source_read.md`, commit `55c3f81`.
It answers all six of the job's questions. The three results that change what the
VM run has to do:

- **Candidate B is refuted.** `api.anthropic.com` is in `AUX_HOSTS` at both the
  install-time copy (`setup.ps1:2144`) and the refresh copy (`setup.ps1:2230`),
  and in `$providerHosts` under `/PROVIDER=claude`. It appears in no toolchain
  list. Nothing was lost in the split.
- **Candidate D is refuted for the identification.** Eleven forward lookups
  across four independent resolvers returned exactly one address,
  `160.79.104.10`, which is the address the kernel refused. Forward and reverse
  agree.
- **Candidate A is weakened to the point of refutation.** The premise is true:
  the provider path resolves once and does not union, at all four resolving
  sites, while the toolchain path resolves three times. But a pool of one cannot
  be missed by a single lookup.

Two findings reported and not fixed, both real and neither the cause: on the
nftables backend the `AUX_HOSTS` addresses are never persisted to
`allowed-ips.txt`, and `switch-provider.ps1:170` still carries all seven
toolchain hosts, so the shipped Start Menu item would permanently defeat Guard 3.

**The install has no provider-reachability check of any kind**, and the two
things that look like one are not: the final gate is a loopback call that never
leaves the box, and the key wizard's models request runs on the Windows side of
the clawuser chain and is skipped entirely under `/SILENT`.

## 4. Task 3: TC.3 re-specified

Done, commit `eba2ba9`, and not run. The control turn now executes while the
toggle is still ON, is recorded as its own row (`TC.1d`) because a turn that
cannot complete with the toggle ON is a ship-blocker in its own right rather than
only somebody's VOID reason, and gates the subject through
`Require-Precondition`. If the control does not complete, `TC.3` records VOID
with a named reason and the toggle-OFF turn is NOT run at all. A comment in the
file says not to re-run it until the provider route works, because until then the
control cannot pass and the test cannot say anything.

---

## PENDING: task 2, the VM run

Everything below this line is unmeasured until `cfv-168` returns. If this
document still carries this heading, the run did not complete and no measurement
in the job's list of six was taken.

## 9. Git

Commits on `main` so far: `55c3f81` (source read), `eba2ba9` (probe and TC.3
re-specification). Explicit per-file staging throughout. No tag.
