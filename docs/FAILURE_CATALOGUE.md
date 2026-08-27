# ClawFactory: what was wrong, and how it was found

*Companion to [`SECURITY_FINDINGS.md`](../SECURITY_FINDINGS.md). Covers development
through v1.4.3.*

Most projects publish what works. This document publishes what did not, because in a
security product the more useful question is not "what does it claim" but "what did
the claims turn out to be worth, and what caught the difference".

Everything below was found during development of a product that had not shipped, by
the people building it. None of it is a report from a user. That is the point: the
value of a control is not that it exists, it is that it fires on your own work before
anyone else is exposed to it.

## How to read this

Every entry has the same four parts.

- **Claimed.** What the product, the document, or the test said.
- **True.** What was actually the case.
- **Found by.** What surfaced the gap. This is the interesting part, and it is usually
  a control firing rather than a person being clever.
- **Changed.** What was done about it.

The entries are grouped by **class**, not by date, because the same shape recurred
across unrelated subsystems and the shape is the transferable part.

A note on tone. Nothing here is written to look brave. Several of these were caught
late, one of them shipped in a release, and a few were found only because an earlier
instance of the same class had already been paid for.

---

## Class 1: controls that passed their own tests while measuring nothing

The most expensive class in this catalogue, because a control in this state is worse
than no control. It occupies the slot where a real check would go and it reports
success.

### 1.1 A guard that intercepted nothing while reporting that it had

**Claimed.** The recoverable-delete guard routed deletions under the agent's
workspace into a root-owned hold, and its tests passed.

**True.** In the shipped configuration the interception was not on the path the agent
actually used. The hold itself was real and structural. The routing into it was not
happening at all, and the test suite could not tell, because it exercised the hold
directly rather than going through the agent.

**Found by.** An interim validation pass that insisted every block assertion carry a
positive control which must succeed in the same run. The control could not be made to
fire, which is what exposed that the subject was never being reached.

**Changed.** The interception was fixed and the test rewritten to go through the
agent's own path. The user-facing wording was also narrowed: the guarantee now says it
covers deletion by name, which is how deletion is ordinarily expressed, and says
plainly that it does not cover every way a program can destroy a file.

### 1.2 A pin that was assigned and never compared

**Claimed.** A validation harness carried a pinned digest for the sandbox filesystem
image, sitting in a list of pins that were compared on every run.

**True.** Nothing ever read it. The identifier appeared exactly twice after its
assignment: once in a line that recorded a weaker informational value, and once in a
list of results to void. A reader scanning the file would have counted it as coverage.

**Found by.** Enumerating every pin in the harness by parsing the source rather than
by reading it, during the preparation for the v1.4.3 validation run, and then checking
each one for a comparison site.

**Changed.** Recorded rather than deleted. It is not stale, because nothing reads it,
and it cannot become stale for the same reason. Deleting it during a run that was
about to trust the surrounding instrument would have been the wrong order.

### 1.3 Absence-only assertions in a human checklist

**Claimed.** A by-hand checklist verified that a panel did not contain certain
misleading wording.

**True.** Several checks asserted only that something was absent. A blank page, a
panel that failed to load, or a screen the operator never reached would all satisfy
them. The same defect in a probe would have been obvious. In prose addressed to a
person it read as diligence.

**Found by.** A review pass that asked of every check "what would make this fail",
which is the same question the harness asks of every automated control.

**Changed.** Every absence-only check gained a positive assertion ahead of it, so the
page has to be present and correct before the absence means anything.

---

## Class 2: success markers that could not fail

A marker that has never failed is indistinguishable from one that cannot.

### 2.1 An uninstaller that ran half of itself and logged success unconditionally

**Claimed.** The uninstaller wrote a completion marker to its log, and the log said
the teardown had succeeded.

**True.** The teardown script's output was discarded and its exit status was treated
as advisory, so the marker was written whether or not the work had happened. On one
branch the teardown stopped part way through and the log still said success. That
branch left the product running: units still enabled, the agent's account still
present, and one service left enabled with its script deleted, so it failed at every
subsequent boot.

**Found by.** A validation run that took the branch by hand, through the real dialog,
and then read the machine back against a snapshot captured before the uninstall
started, rather than reading the log. The log and the machine disagreed.

**Changed.** The teardown's output is now captured and checked, the marker is
conditional, and the log carries a read-back line stating what is left. The
validation for the following release requires the negative half as well: a
deliberately injected fault must produce a failure in the log and a message to the
user, or the marker is not evidence.

**This one reached a release.** It is the reason the release that contained it was
refused, and the reason this catalogue exists in the shape it does.

---

## Class 3: instruments that produced plausible output while measuring the wrong thing

The failures in this class are dangerous precisely because nothing looks wrong. There
is no error, no empty result, no obvious gap. There is a full, well-formed, confident
answer to a question nobody asked.

### 3.1 A job runner that reported success for work it had split in half

**Claimed.** A validation box reported that its jobs had run and passed.

**True.** The wrapper that launched them was built by joining several lines of script,
and the join produced separate statements where one had been intended. A redirect was
orphaned. The job reported success without having run the work.

**Found by.** A transcript that was shorter than the work it claimed to have done.

**Changed.** The wrapper builder now emits one physical line per command and asserts
its own line count before writing, refusing to produce a wrapper of the wrong shape.
The producer now writes a transcript and a completion sentinel, and evidence is
gathered before any machine is torn down.

### 3.2 A dispatcher that restated stale results as current

**Claimed.** A results table for a run performed after a reboot.

**True.** Two of the phases wrote their post-reboot results under a different filename
than the one the dispatcher asked for. It retrieved the file from the run before the
reboot and presented it as the new one. No error was raised anywhere.

**Found by.** Row identifiers in the table that carried the marker of the earlier
pass, on a job whose own transcript said it was the later one. Also by tests appearing
as "run" which the later pass is designed to skip.

**Changed.** The retrieval now derives the filename the same way the phase does. A
third naming pattern was then found by reading the remaining phases rather than by
waiting for another retrieval to come back wrong.

**Stale evidence presented as current is worse than missing evidence**, because
missing evidence announces itself.

### 3.3 A snapshot that captured an object graph instead of a file

**Claimed.** A before-state snapshot of a machine, for comparison after an uninstall.

**True.** It was about a hundred megabytes, taken from a machine whose largest
captured file is a hundred and eight bytes. Reading the files returned rich objects
carrying provider metadata, and the serialiser followed it.

**Found by.** The byte count not fitting, and being checked against the machine rather
than explained.

**Changed.** The capture casts to plain text, and a ceiling assertion now fails the
run loudly if a snapshot is ever that size again. The guard was calibrated in both
directions before it was trusted: it must fail on the old shape and pass on the new
one, and both were confirmed.

### 3.4 A probe that asked through a path that does not exist by design

**Claimed.** A check reported that the desktop application was not installed.

**True.** It was installed. The check asked for it through a mount that this product
deliberately disables, and which exists only as an empty stub. An empty answer from a
disabled mount looks exactly like an absent application.

**Found by.** A second diagnostic that asked from the other side of the boundary and
found the application immediately, at its expected digest.

**Changed.** The check asks from the side that can see the answer. The general rule it
produced is now in the standing preamble: **name the real subject**, and require the
measurement to happen where the thing actually is.

### 3.5 A waiter that matched text printed before it started

**Claimed.** A background wait for a long-running provisioning step.

**True.** It exited immediately. Its pattern included a word that already appeared in
an unrelated warning printed minutes earlier.

**Found by.** The wait returning far too fast.

**Changed.** Waiters are now armed on strings verified absent first. No measurement
was affected by this one; it is here because the class matters more than the cost.

---

## Class 4: ship-blockers manufactured by miscalibrated instruments

The mirror image of class 1, and nearly as expensive. An instrument that reports
failure it invented will stop a release just as effectively as a real defect, and it
consumes the effort of proving a healthy thing healthy.

### 4.1 A firewall log rule placed above the rule it was watching

**Claimed.** A validation box reported that the route to the model provider was being
blocked, which would have been a serious defect.

**True.** The route worked. The diagnostic rule that logged dropped packets had been
inserted above the rule that accepts allowed traffic, so it logged packets that were
about to be accepted. Every allowed packet looked like a drop.

**Found by.** Calibrating the log against a case whose answer was already known, and
finding that it named a target it should have stayed silent about.

**Changed.** The standing rule is now that a drop-log needs **both** calibration
halves before it may report anything: it must name a target that must be dropped, and
it must stay silent for an address that is in the allow set. One half alone certifies
nothing. This one cost a machine and a false ship-blocker.

### 4.2 A diagnosis that was confidently wrong before it was measured

**Claimed.** A failure to launch the desktop application was attributed to a specific
installer error code.

**True.** The application was failing earlier than that, before it reached the point
where the code could have been produced.

**Found by.** Testing the hypothesis rather than acting on it. It was refuted.

**Changed.** The real cause was found and fixed, and the retracted diagnosis was left
in the record rather than quietly replaced. A retracted diagnosis is data about how
much a diagnosis is worth before it is tested.

---

## Class 5: probes that detected themselves

### 5.1 A credential-leak scan that found its own search

**Claimed.** A scan of the running process table for the provider credential reported
a hit, which would have meant the credential was visible in a process listing.

**True.** The scan passed the secret to the search program as an argument, so the
search program's own process carried the secret, and the process listing running
alongside it saw exactly that one occurrence.

**Found by.** Re-deriving the same question three ways with the secret never on a
command line: snapshot the process table first and match against a pattern read from a
file, sweep every live process's arguments directly, and check a sibling probe written
correctly. All three agreed there was no leak, and the sibling probe passed. The
self-reference was then reproduced deliberately, to confirm that was the whole
explanation.

**Changed.** There was no credential leak. The probe was carded and the shape recorded:
**a measurement that must not appear anywhere must not be typed anywhere**, including
into the instrument that looks for it.

---

## Class 6: documentation that contradicted the artifact

Claims are part of a security product, not decoration around it. A false claim in a
README is a defect in the same sense as a false return value.

### 6.1 A README promising no telemetry over an installer that posted a machine
identifier on every run

**Claimed.** No telemetry.

**True.** While the licence check existed, the installer sent the machine's identifier
to a project-operated server on every install. The claim and the behaviour had been in
the same repository, both true of different eras, for some time.

**Found by.** A line-by-line audit of every claim in the shipped documents against the
code that was supposed to implement it, done as part of moving the product to a free
release.

**Changed.** The licence check and the network call were removed entirely. The claim
is now true, and states specifically that there is no telemetry, no licence server and
no account. The installer now makes no network call to any project-operated server at
any point.

### 6.2 Ten source links that all landed in the wrong place

**Claimed.** A security document cited ten specific line numbers in the installer as
evidence for its claims.

**True.** The claims were correct. **Every one of the ten anchors was wrong**, some by
thousands of lines, and one cited a function name that does not exist.

**Found by.** Following them.

**Changed.** All ten were removed rather than corrected. Function names were kept.
A link that lands in the wrong place is a claim that cannot be traced, and a
traceability aid that cannot be traced is worse than none.

### 6.3 A control described as structural that was not

**Claimed.** The browser tool was "structurally denied".

**True.** It is denied in the gateway's configuration. That is real, and it was
verified to be absent rather than failing softly, but it is enforced on the network
path rather than by the operating system, and it does not hold against an agent that
already has shell access and starts the runtime another way.

**Found by.** A claim audit that sorted every guarantee into structural or advisory
and required each one to name its enforcement mechanism.

**Changed.** The wording was corrected everywhere it appeared. The security document
now carries the structural and gateway-path guarantees in **two separate tables**, and
says which is which. The distinction is treated as non-negotiable: marketing claims
match the structural column only.

### 6.4 A switch whose description overstated what it stopped

**Claimed.** A panel switch "stops skill installation".

**True.** It does not. With the switch off, an installation still completes, because
the relevant service answers from an address shared with a host that no switch can
revoke. The switch does what it says about the addresses it controls. The claim about
the consequence was wrong.

**Found by.** Measuring the consequence rather than the setting: performing a real
installation with the switch off.

**Changed.** The copy was corrected on all three surfaces that carried it, and the
underlying limitation is now a named residual in the security document, because it is
a property of address-scoped filtering in general and not of that one switch.

### 6.5 Four agents, three of which were scaffolding

**Claimed.** Four pre-staged agents, each with its own role-specific prompt.

**True.** Literally true and materially misleading. Only one carried a working prompt.
The other three were scaffolding.

**Found by.** The same claim audit.

**Changed.** Kept, with the qualification stated in the sentence itself rather than in
a footnote.

---

## Class 7: a convenience that silently defeated a security control

### 7.1 A Start Menu item that re-opened the boundary it had no idea it was closing

**Claimed.** The software-sources toggle removed a set of hosts from the agent's
permitted network set, and it did.

**True.** A separate, shipped Start Menu item, for switching model provider, still
carried the full list of those hosts and re-seeded them into the permitted set when
run. Nothing removed them afterwards, and the change survived a reboot. Using a
supported menu item therefore **silently and permanently undid the control**, with no
indication to the user that anything had changed.

**Found by.** A dependency census, done because something was being removed. The
census asks two questions and both have to be answered by execution rather than by
memory: **who uses this**, enumerated tree-wide with a count, and **when is it
needed**, walked across the install and boot sequences. Removing the hosts from two of
the three places they were seeded had already shipped a toggle that did nothing. This
was the third place, and it was the one that persisted to disk.

**Changed.** The provider-switch path no longer carries the toggle-controlled hosts.
The rule that came out of it is now standing practice: **enumerate every site, not
the sites you remember.**

---

## Class 8: the bytes shipped were not the bytes in the repository

### 8.1 Ten bundled files whose content differed from their committed form

**Claimed.** A stranger can audit the source that produced the installer. That claim
requires the files the installer bundles to be the files the repository contains.

**True.** They were not. Ten files that the installer bundles had a working-copy form
that differed from their committed form. **Six of the ten already carried the rule
that was supposed to prevent exactly this.**

**Found by.** Asking the question directly with the one command that answers it, which
reports the index form and the working-tree form side by side. The ordinary status and
difference commands are **blind to this by construction**: a text attribute makes the
comparison normalise, so a stale working copy compares equal to its committed form for
ever.

**Changed.** All divergent files were re-materialised, a repository-wide baseline rule
was added so the checked-out form no longer depends on how an individual machine is
configured, and a build gate now refuses to build when a bundled file is not its
committed bytes. The content was unaffected: comparing the two releases blob by blob,
exactly one bundled file's committed bytes changed, and that was a version string.

**Why it survived so long.** Writing the rule was never sufficient. Adding an
attribute does not re-normalise files that are already checked out, and nothing
reported that they needed it. The rule was correct, present, and doing nothing.

---

## Class 9: a phase that ran for the first time long after it was believed to have run

### 9.1 An approval path that no run had ever exercised

**Claimed.** Several cards recorded that the approval lifecycle had been tested.

**True.** The phase read the command-line tool's output as structured data. The tool
does not emit it in that form, so the value the approval step needed was always empty,
and the approve path had **never executed in any run of that suite**.

**Found by.** Three failures and a void all pointing at the same missing value, and a
transcript printing that value as empty. The convergence is what did it; any one of
the four alone would have been triaged as its own problem.

**Changed.** The parser was fixed and the path ran. The wider lesson is about
bookkeeping: **a card saying a thing was tested is not evidence that it was**, and
several cards agreeing with each other is not corroboration if they share a source.

---

## Class 10: audit instruments carrying the defect they were auditing

The recursive class, and the reason this catalogue's method is what it is.

### 10.1 An audit probe with the very defect it was hunting

**Claimed.** A sweep proved a class of defect was absent from a set of files.

**True.** The sweep itself contained an instance of the defect it was searching for.

**Found by.** Deliberately planting one instance of the defect and confirming the
sweep found it, before trusting a clean result from it.

**Changed.** The standing rule: **after fixing a class of defect, the search used to
prove the files clean is itself a measurement and can be wrong in the same way the
code was.** Plant one, confirm it is found, then believe the result.

### 10.2 A canary that certified only the shape of the canary

**Claimed.** A pattern was proven to detect a defect class, because it had been
canaried.

**True.** It detected the canary and missed a real instance. The canary had been built
to look like the examples already found, so it certified the pattern against the
familiar shape and said nothing about the unfamiliar one. One pattern was certified by
a canary that shared its accidental structure and then missed a case that differed in
a single character class.

**Changed.** The sharpened rule: **build the canary to look like the thing you are
afraid of missing, not like the things you already know are there.** And where the
question is enumeration rather than detection, parse the structure instead of matching
text.

### 10.3 The enumerator written for this release, which failed its own canary

**Claimed.** Nothing yet. This one was caught before it reported.

**True.** Preparing the v1.4.3 validation run required enumerating every pinned value
in the validation harness. The enumerator parsed the source structurally, which is the
method rule 10.2 prescribes. It was then canaried against six deliberately planted
pin shapes, chosen to be things that would be easy to miss rather than things already
known to be there. **It found four of six.** It missed a digest held as an array
element and a digest inside a multi-line string body, both of which are shapes a real
pin could take.

**Found by.** The canary, doing exactly what it is for, before any result was trusted.

**Changed.** A second and deliberately cruder pass was added, scanning every string in
the file including multi-line bodies. It was re-canaried and found all six. Run
against the real harness it surfaced one value the structural pass had missed, which
on inspection was a deliberately wrong hash used as a negative control, and correctly
not a pin.

The entry is here rather than omitted because it is the only kind of evidence that
matters about a practice: not that it is written down, but that it was followed on a
day when following it produced an inconvenient answer.

---

## What this catalogue does not contain

**Known residuals are not in here.** The things that are still true of the shipped
product, including the ones that are weaker than their names suggest, are in
[`SECURITY_FINDINGS.md`](../SECURITY_FINDINGS.md), stated as current limitations
rather than as history. Two documents, because a fixed defect and a live one call for
different decisions from a reader.

**No user-reported issues appear here**, because there have not been any. The product
is being published now.

---

## The practices these produced

Nothing in this list was designed. Each one is the residue of a specific failure
above, and each is applied mechanically rather than remembered.

1. **Every block assertion carries a positive control that must succeed in the same
   run.** A refusal is only evidence if the thing is otherwise working.
2. **A control that did not fire voids the result.** A missing precondition is never a
   product verdict. It is recorded as void, with a named reason.
3. **Every injected fault carries proof that the fault landed.** A fault injection that
   does not inject scores a false pass and looks exactly like a working control.
4. **Calibrate before measuring.** Run each probe once against a rigged input whose
   answer is already known. A probe that cannot produce a known-correct result on a
   rigged input may not report one on a real one.
5. **A search for an absence must first prove its target is searchable.** A search over
   a compressed payload finds nothing and reads as clean.
6. **A held copy of a list is compared against what the product reports.** An
   uncompared copy is a second stale list, not independence.
7. **Read the instrument's error output, not only its transcript.** A probe that dies
   early is invisible in its own transcript by construction.
8. **Name the real subject.** Where a control protects a specific location, measure at
   that location, not at a convenient one that resembles it.
9. **An audit pattern is itself a probe.** Plant one instance, confirm it is found,
   then trust a clean result.
10. **Enumerate, do not recall.** When something is removed, find every site that
    references it by execution, and walk the sequence for every window where it is
    still needed.

---

*Corrections to this document are welcome. If something here is wrong, or reads as
more flattering than the facts support, that is a defect in the same sense as any
other and we would like to know.*
