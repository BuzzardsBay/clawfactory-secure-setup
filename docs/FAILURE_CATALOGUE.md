# ClawFactory: what was wrong, and how it was found

*Companion to [`SECURITY_FINDINGS.md`](../SECURITY_FINDINGS.md). Covers development
through v1.4.4, the first release of this product to be published.*

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
conditional, and the log carries a read-back line stating what is left.

**Confirmed, in the direction that matters, before v1.4.4 was published.** The fix
above was only ever observed succeeding, and a marker that has only ever succeeded is
exactly what this class is about. So the failure was manufactured: a single file
inside the sandbox was made undeletable, the uninstall was run through the real
dialog by hand, and the product was watched. It logged the incomplete state, named
what it had left behind, showed the user a dialog saying the Linux cleanup did not
finish, and told them the command to finish it by hand.

**The line that justifies the whole exercise** is that on that run the in-distro
cleanup **exited zero while leaving files behind**. An uninstaller that had merely
checked the exit code, which is the obvious fix and the one a reviewer would most
likely have accepted, would have reported unqualified success. The requirement that
the terminal marker be present *as well* is the only thing standing between that run
and a false success, and it is now measured rather than argued.

The injected fault was then removed, and the same directory removal the product had
attempted succeeded immediately, which is what rules out the reading that the
teardown could never have removed it at all.

**This one reached a release.** It is the reason the release that contained it was
refused, and the reason this catalogue exists in the shape it does.

### 2.2 A kill switch that printed a success banner over two commands that had failed

**Claimed.** A Start Menu item that stops everything: it unmounts your granted
folders, stops the local gateway, and kills any running agent turn. It was listed as
a **proven structural guarantee** in the security document, and it printed a banner
saying the gateway was stopped and any running turn killed.

**True.** It stopped nothing inside the sandbox. Both of the commands it sent in died
on a quoting fault, the script ignored their exit codes, and it printed the banner
regardless, over a gateway that was still answering and an agent process that was
still alive. Only the third action, unmounting the folders, worked. **This was true
of every release of the product from the first.**

**Found by.** A validation pass that executed the shipped script itself. The suite
had, until that day, extracted the shell fragments these Windows scripts build and
run *those*, so a defect in the wrapper that builds them was invisible to it by
construction. The first run that executed the wrappers found this and one other
ship-blocker in the same hour, and both had been present for months.

**Changed.** The quoting is fixed, and the more important half is that the script now
**measures**: after issuing the stop it counts the agent's processes inside the
sandbox and prints only what that count supports, per claim, exiting non-zero when it
cannot confirm. It can now report its own failure, which is the property it lacked.

The claim was moved as well as the code. The row was **removed from the structural
table** rather than marked fixed, because a kill switch is an action you take and not
a boundary that holds, and it now has a residual section of its own that says what it
does and does not promise. A wrapper-execution phase was added to the suite, and both
halves of the fixed switch were then measured from a clean install: it stops a
running gateway and turn, and with every sandbox call made to fail it refuses to
claim success.

**The rewrite's own first two verifiers were also wrong**, and it is worth recording
which way. Both read the process count into a shell variable through a channel that
silently empties such assignments, so the script could not verify and **said so**,
exiting non-zero. A false "could not verify" is a bug, and it was fixed. A false
"everything is stopped" is the defect that had shipped for months. The discipline the
rewrite introduced caught the rewrite's own bug.

### 2.3 A provider switch broken by the explanatory comments of the commit that fixed something else

**Claimed.** A Start Menu item that switches the agent's model provider: it updates
the stored key, adjusts the firewall allowlist, and restarts the local gateway.

**True.** It exited with an error before changing anything, **for every provider**.
An earlier commit had added four explanatory comments mentioning a variable by name.
Under the strict-mode setting the script runs with, the interpreter expands variables
inside those comment lines, the variable does not exist at that point, and the script
dies. **The prose added to explain a fix is what broke the file.** It failed safely,
leaving the firewall untouched, but the function did not work at all.

**Found by.** The same pass as 2.2, on the same day, for the same reason: it was the
first run that executed the shipped scripts rather than fragments extracted from
them.

**Changed.** The four references were escaped, and the script now completes, applies
its firewall change, and leaves the software-source address set untouched. A ninth
build gate was added that parses every shipped script at build time and fails the
build if any of them references a variable the file never defines. That gate is the
class fix; the four escapes are the instance.

**A second correction rode along.** The same script had printed an unconditional
success line claiming a local model was running. It now prints a warning when that
model is not actually installed, and says the firewall change still applies either
way. That correction proved itself on a real failure rather than a rigged one: the
model genuinely could not install on the validation machine, and the script said so.

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

### 3.6 Two empty readings agreeing perfectly, reported as verification

**Claimed.** Two files were moved out of the way before a run, and the transcript
recorded that each archived copy was identical to the original.

**True.** Nothing had been compared. The one-letter helper written to compute the
digests shared its name with a built-in command, and the built-in won every call, so
the helper returned nothing every time. The identity check was therefore comparing
nothing against nothing, which is always true. **Two empty readings agreed perfectly
and were reported as verification.**

**Found by.** Reading the error output that arrived beside the result, rather than
only the result. The result looked clean; the exception naming the built-in was in
the same response.

**Changed.** Re-verified with a properly named function and, more to the point, with
**two controls on the instrument itself**: that a digest of a real file is 64
characters and looks like one, and that a digest of a missing file returns the string
`ABSENT` rather than nothing. A function that returns nothing and a function that
returns `ABSENT` are different instruments, and only the second can be trusted to
report a mismatch.

The two archives were then reported to **different standards, and labelled as such**.
One had been copied, so the original survived and a digest-to-digest comparison was
possible. The other had been moved, so its pre-move digest can never be recovered;
its identity rests on four properties recorded by an independent read-only pass before
the move, all four of which matched. That is weaker than a digest comparison and it
is written down as weaker rather than presented as one.

The name collision was already on this project's standing list of traps, contributed
by an earlier session. It was violated by the person who had written it down, the day
after writing it down.

### 3.7 A command that exited zero and returned half its output

**Claimed.** A product log was retrieved from a validation machine for the record.

**True.** The transport truncates its output at a size limit, silently. The command
exited zero, the retrieval looked successful, and the file that came back was
incomplete.

**Found by.** Checking the decoded byte count against the size the machine had
already reported for the same file, rather than trusting a command that exited zero.

**Changed.** The log was retrieved in pieces and reassembled, and the result verified
byte-identical to the copy on the machine by digest before the machine was destroyed.
The general rule was already standing practice for errors: **an errored command's
empty output is not evidence.** This extends it: a *successful* command's truncated
output is not evidence either, and it is harder to see.

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

### 4.3 An assertion left stale while the measurement beside it was corrected

**Claimed.** A close-out and the job card that followed it both recorded that a
failing check had been corrected.

**True.** Only half of it had. The check reads a machine and then decides. The
**reading** had been enriched, and the **decision** had not been touched. The row
still asserted that the whole Windows application directory is gone, on the uninstall
branch where the user has explicitly chosen to keep the Linux environment whose disk
image lives inside that directory. Run as written it would have failed again,
identically, and read as **"the uninstaller leaves the application directory behind"**,
which is a ship-blocker-shaped claim about correct behaviour.

**Found by.** Reading the file before running it, prompted by the card asserting that
a correction existed. A card saying a thing was fixed is not evidence that it was.

**Changed.** The row now asserts what is actually load-bearing on that branch: the
three artifacts the installer places by name are gone, **and** a recursive count of
every file under that directory outside the sandbox's backing store is zero. On the
machine it was corrected against, that count went from 56 to 0.

**It was calibrated in four directions before it measured anything**, and two of the
four are the ones that matter. One rig proves the row was not merely *inverted* into
a check that passes only when the directory survives, which would be a different
wrong answer rather than a fix. Another proves the row is not satisfied by the three
named files alone, which is **the short-list defect of entry 8.1 reproduced in
miniature inside the instrument**: a check that names a subset of its subject reports
a clean sweep over the wrong set.

The surviving directory did not vanish from the record when the assertion stopped
naming it. It became an informational row and a card of its own, because an assertion
is not the place to hide a fact.

### 4.4 A log that appends, and a run plan that did not know it

**Claimed.** Nothing yet. This one was caught before it reported.

**True.** The final measurement of the entire validation cycle needed a second
uninstall on a machine that had already been uninstalled once. The product's uninstall
log **appends** rather than truncating, so the second run would have produced a file
containing both the earlier success marker and the new failure marker. The probe
classifies that state deliberately, by name, as ambiguous. The check requires the
failure marker alone. **It would therefore have failed on a run where the product did
exactly the right thing**, and a failure there is indistinguishable, from the
transcript alone, from the defect under test: the exact costume of entry 2.1, on the
last row of the last machine.

**Found by.** Reading the product's own logging call before dispatching anything, and
then measuring the live log's marker counts on the machine. The first run's log was
archived before the operator was asked to do anything.

**Changed.** The log was rotated, and the rotation was proven necessary *and*
sufficient by the resulting file: one start line, one marker, and it is the failing
one.

**The probe was not at fault and neither was the product.** What was wrong was the
*order*, and no calibration rule in this project governs order. See class 11.

### 4.5 A by-hand check that would have failed correct behaviour

**Claimed.** A checklist step asserting that after removing one allowed website, one
entry remains in the panel, so that the panel is proven to render a stored entry at
load rather than only one added in the same session.

**True.** The entry it expected is seeded by a setup path that the run in question did
not use. No entry was ever there. The panel correctly said that nothing was allowed
yet. The check would have produced **a failure against correct behaviour**, recorded
by a person, on a product surface.

**Found by.** Reading the checklist against the first screenshot the operator sent,
rather than trusting the checklist. It was caught before the step was handed over.

**Changed.** The check is recorded as void with that reason, and the checklist is
what needs fixing: either the seeding becomes part of the setup, or the check states
its own precondition. The property it exists to prove **remains unmeasured** and is
recorded as unmeasured rather than folded into the passing count.

### 4.6 A conclusion drawn from one eighth of the evidence

**Claimed.** A first reading of an intermittent-connectivity finding, generalised
from what had been measured.

**True.** One host of eight had been measured. The reading was retracted the same
session and replaced with a full sample: 96 attempts across all eight hosts, 12 each,
with both controls firing in the same run. Four of the eight then turned out to answer
on every attempt, which the first reading would not have predicted.

**Found by.** The standing requirement to discover the subject rather than assume it,
applied to the question of how many subjects there were.

**Changed.** The retraction is in the record beside the measurement. **No verdict was
taken on the finding itself**, in that session or the two after it, because it is a
product decision rather than a measurement, and three separate sessions declining to
take it is deliberate rather than an oversight. It is disclosed in the release notes
with its mechanism labelled as inferred, because the split is measured and the cause
is not.

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

### 6.6 One sentence promising a standard of proof that three rows could not meet

**Claimed.** Above the table of structural guarantees stood a single sentence: *every*
claim in it was proven by asking the agent itself to cross the boundary and recording
what it did.

**True.** That sentence was false for three of the nine rows, and only one of the
three was a defect.

- **Inbound deny** is a claim about a machine other than this one. It was measured as
  the absence of a listening surface plus the presence of the firewall rule. No run
  has ever driven a connection from a second host.
- **Credential protection** is a claim about where a secret rests. It was measured as
  file ownership and file mode. It cannot be measured any other way: the agent is
  given its own key by design, so asking it to fetch one would not produce a refusal.
- **The kill switch** had no evidence at all. See entry 2.2.

**Found by.** Enumerating the table one row at a time and asking of each what evidence
stood behind it, during the release that had to correct the kill-switch row anyway.
The enumeration was the deliverable; the row that prompted it was not.

**Changed.** The kill switch left the table. The other two rows now carry **their own
method in their own cell**, so the claim and the evidence sit together, and the
paragraph above the table states the exception instead of speaking for every row.

**The transferable finding is not the kill switch.** It is that a universal sentence
was carried over a table containing rows that cannot be proven that way at all. Rows
three and seven were always weaker than the sentence claimed. Nobody noticed, because
nobody read a summary sentence as a claim about each row underneath it.

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

### 10.4 The tool built to measure a text-encoding bug, corrupted by that bug

**Claimed.** Nothing. Caught before it reported.

**True.** A customer-facing dialog was found rendering em dashes as garbage, because
the script holding it is saved without the mark that tells the interpreter how to read
it. The obvious next step is to sweep every shipped script for the same problem. The
first version of that sweep contained the character it was searching for, written as a
literal, in a file saved the same way. **The bug corrupted the tool built to measure
the bug.**

**Found by.** Calibrating the sweep before running it, which is rule 9 of the list at
the foot of this document.

**Changed.** The sweep was rewritten to contain no non-ASCII character at all and to
work on raw bytes rather than on decoded text. It then reported the class honestly:
five shipped scripts affected, twenty-one occurrences, of which **seven are visible to
a customer and the rest are in comments**, counted per occurrence rather than asserted
per file. That distinction is the whole finding: a garbled comment is untidy, and a
garbled sentence in a dialog whose only job is to explain a decision is a defect the
customer reads.

### 10.5 A sweep certified by a canary shaped like the cases already known

**Claimed.** A pattern had been proven to find every stale value of a given kind,
because it had been canaried.

**True.** It found the canaries and missed a real instance, which was written in a
shape the canaries did not have. The canaries had been built to resemble the examples
already in hand.

**Found by.** The stale value failing a check downstream, and the sweep then being
re-run against it and found blind.

**Changed.** This is entry 10.2's rule, restated because it recurred after being
written down: **build the canary to look like the thing you are afraid of missing, not
like the things you already know are there.** Where the question is enumeration rather
than detection, parse the structure instead of matching text.

---

### 10.6 A scanner that could not run, reporting a clean tree

**Claimed.** That all ten shipped `.ps1` files are free of the non-ASCII bytes that
produce the v1.5 mojibake. Produced on 2026-08-29 while re-deriving that census from
the tree, by the obvious one-liner: a `grep -cP` with a negated hex character class,
run per file under `LC_ALL=C`, inside a loop whose per-file expression ended `|| echo 0`.

**True.** Five of the ten carry non-ASCII bytes and no BOM, exactly as
`docs/V1_5_BACKLOG.md` already recorded: `setup.ps1`, `post-install.ps1`,
`bootstrap.ps1`, `rename-agent.ps1`, `launcher.ps1`.

**What went wrong.** `grep -P` on this platform refuses under `LC_ALL=C` — *"grep: -P
supports only unibyte and UTF-8 locales"* — and exits **2**. The `|| echo 0` converted
that refusal into the number zero. **Ten files, ten zeroes, a perfectly uniform clean
result, produced by a program that never ran.** The uniformity is what makes it
convincing: a real clean tree and a scanner that cannot start look identical.

**Found by.** The rule, applied mechanically rather than remembered. An em dash was
planted in a copy of a clean shipped script and the pattern was required to find it
before the clean result was believed. It did not. A byte-value scan then found 3 bytes
in the canary, 0 in the control, and reproduced the published census file-for-file and
line-for-line.

**Why this is in Class 10 and not Class 2.** It is both, and Class 10 is the sharper
reading: the instrument was built specifically to audit a *text-encoding* defect and was
itself defeated by a *text-encoding* constraint — the locale. Entry 10.4 records the
first sweep for this same defect containing the defect. This is the second, by a
different mechanism, on the same subject.

**Changed.** Three requirements written into the staleness-gate specification in
`docs/V1_5_BACKLOG.md`: match on byte values and never on a regex engine's character
classes; run the canary and the clean control in the *same invocation* as the real scan;
and treat any scanner exiting non-zero as **VOID, never clean**. That last one is the
whole entry. A practice is added below as rule 21.

---

## Class 11: a probe calibrated correctly, run in the wrong order

This class was named at the end of the cycle, because it is the one that none of the
existing rules covered. Every practice at the foot of this document governs an
*instrument*. None of them governs the *order the instruments run in*, and two of the
last cycle's defects lived there.

### 11.1 Correct probes, placed in a plan that did not account for the machine's state

**Claimed.** A run plan for the final measurement of the cycle, listing the probes to
dispatch and the order to dispatch them in.

**True.** Two of its steps were unsound, and neither probe was at fault.

- The uninstall log **appends**, so a second uninstall on an
  already-uninstalled machine would produce an ambiguous file and a false failure.
  That is entry 4.4.
- The dispatcher retrieves each probe's evidence file **by name**, and both probes due
  to run had left files with those exact names on the machine the day before. A probe
  that died early would have handed back **yesterday's verdict as today's**, with no
  error anywhere.

Both probes classify these situations correctly. Both are documented in their own
source. What was wrong was that the plan assumed a fresh machine and the machine was
not fresh.

**Found by.** A read-only pass over the machine before any change was made, asking
what each probe would find at the moment it read.

**Changed.** The log was rotated and the stale evidence files moved to an archive,
both before the operator was asked to do anything, and all seven retrieval paths were
confirmed empty before the first dispatch.

**The rule this produced:**

> A probe is calibrated against a rigged input. **A run is not.** Before the first
> dispatch, read what the machine already holds that the probes will read: logs that
> append, evidence files fetched by name, snapshots about to be overwritten. State
> what each will contain at the moment the probe reads it. **A second run over a
> machine that has already been run is not the same measurement as the first.**

---

## Class 12: an assertion made with no instrument at all

Every class above is a defect in something built to measure. This one is a defect in a
sentence said between measurements. The project had eleven classes of rule governing
probes, controls, gates and run plans, and none governing what is claimed in a chat
session about the product itself, which is where the operator actually receives most of
what he knows about it.

### 12.1 A false claim about the chat surface, asserted from memory and never measured

**Claimed.** That the ClawFactory desktop icon launches a chat session in Windows
Terminal. Stated in `README.md` line 53, which **is bundled into the installer**
(`ClawFactory-Secure-Setup.iss:46`) and **carries its own Start Menu shortcut**
(`ClawFactory-Secure-Setup.iss:186`), so a customer could open the false sentence without
ever visiting GitHub. Stated again in `CLAUDE_ClawFactory.md` section 14.4, which is where
the README sentence came from. Restated in a chat session, and from there into a handoff
document, and from there used as a premise in a product argument about what a user
experiences in their first minute.

**True.** The `[Icons]` section of the installer script has always been the answer and
takes ten seconds to read. `{commondesktop}\ClawFactory` and `{group}\ClawChat` both carry
`Filename: {app}\ClawChat.exe`. The icon opens ClawChat, a desktop chat window. No
`[Icons]` entry names `wt.exe` or any terminal. `grep` for `wt.exe` over the `.iss` and
over `launcher.ps1` returns nothing. Even `launcher.ps1`, which no shortcut invokes, opens
a **browser**, not a terminal.

**How it propagated.** Not by measurement. Every step in the chain was a restatement of the
step before it, and no step consulted the installer script. The documentation defect
(Class 6) is the ordinary half of this. The new half is that the false sentence was then
spoken in conversation, where nothing in this catalogue's practices applied to it, and
conversation is faster and more trusted than documentation.

**Found by.** The operator asking a direct question about his own product. Not by a probe,
not by a gate, not by a sweep. There was no instrument pointed at this, which is the entry.

**Aggravating detail.** When the claim was finally corrected, correcting it surfaced three
further stale facts in the same fifteen lines: that `launcher.ps1` is run by the desktop
shortcut, which stopped being true when the icon was repointed at ClawChat; a poll timeout
documented as 15 seconds that the parameter block sets to 120; and two whole steps missing
from the description. The sentence had been wrong long enough for the paragraph around it
to rot, and nothing had ever read it against the script.

**Changed.** A clause added to `docs/VALIDATION_PREAMBLE.md`, which is the file every
ClawFactory job now pastes its preamble from:

> **Chat does not assert product behaviour from memory.** Any claim in a chat session
> about what the product does, what ships, or how a user reaches it cites a repo file and
> line, a validation close-out, or the installer script. **Otherwise it is labelled
> INFERRED.**

**The second-order rule, from the correction rather than the defect.** The correction was
first made in two places. A tree-wide census afterwards found the same claim standing in
`SUPPORT_MATRIX.md`, in seven separate customer-facing answers, telling every non-technical
persona to skip the desktop icon and use a Linux terminal instead. **A claim removed from
the place it was noticed is not a claim removed.** That is the WHO half of the dependency
census, applied to sentences instead of to code, and it is the same rule that Class 8 and
the toolchain-hostname defect produced.

### 12.2 The same off-by-one, asserted a second time, against a record that already refuted it

**Claimed.** That Studio has **six** panels which are not in this release. Written in a
chat-authored job brief on 2026-08-29.

**True.** There are **seven**. `docs/RELEASE_NOTES_v1.4.4.md:29`,
`docs/RELEASE_v1.4.4_GITHUB_BODY.md:31` and `validation/MANUAL_CHECKS_studio.md` section 9
all say seven of Studio's eleven panels are not in this release.

**Why this is a separate entry and not a footnote to 12.1.** Because it is the second time.
Section 1.2 of the v1.4.4 release-prep close-out, in this repository, is *titled* **"The
card names six not-in-this-release panels. There are seven"**. The refutation was already
written down, in this repository, under a heading that says the number, before the brief
asserted six again. The number was not merely unverified; it was **contradicted by an
existing record that the assertion did not consult**.

**How it propagated.** Identically to 12.1, and from the same cause. A number entered a
chat session from memory, was not checked against the repository, and was carried into a
written brief where it acquired the authority of a specification. The first time this class
fired it produced a novel error. This time it reproduced a **known** one.

**Found by.** Deriving the number from the tree while writing it into
`docs/V1_5_BACKLOG.md`, rather than copying it from the brief. The brief had explicitly
instructed that a different number in it not be taken on faith; that instruction was
generalised to every number in it, which is the only reason this was caught.

**Changed.** Nothing new is added to the practices list, because rule 18 already covers it
exactly and the entry exists to show that rule 18 has a repeat offence behind it rather than
a single incident. What is added is a sharper reading of rule 18:

> **A chat assertion is not merely unverified. It can be actively contradicted by a record
> the assertion never consulted.** The question is not "is there evidence for this" but
> "has this already been settled somewhere I have not looked". The second is a search, not
> a memory.

The corrected count and this history are both written into `docs/V1_5_BACKLOG.md`, so a
third occurrence has somewhere to be checked against that is nearer to hand than a close-out
section title.

### 12.3 A citation that satisfied rule 18 to the letter and was still false, because the file cited was not the file that ships

**Claimed.** That `clawfactory.app` carries a ClawAgent download button which resolves to a
release page with no asset, and that publishing this repository would therefore fix only one
of the site's two broken download links. Asserted in a chat session on 2026-08-29, repeated
across four consecutive messages, and written into
`docs/session_reports/2026-08-29_prepublication_sweep_closeout.md` as "Prompt corrections"
item 1 - where it had the additional effect of **contradicting a premise in the job brief that
was correct**, under a heading that exists specifically for correcting the brief.

**True.** The live site is served from **`BuzzardsBay/clawfactory-site`**, not from this
repository. `gh api repos/BuzzardsBay/clawfactory-secure-setup/pages` returns **404**;
`gh api repos/BuzzardsBay/clawfactory-site/pages` returns
`{"cname":"clawfactory.app","status":"built"}`, and that repository's `index.html` is
byte-identical to what the domain serves. Every GitHub link on the live site:

```
3 x  https://github.com/BuzzardsBay/clawfactory-secure-setup/releases/latest
1 x  https://github.com/BuzzardsBay/clawfactory-site
```

Three download links, one URL, no ClawAgent button anywhere. ClawAgent appears only as FAQ
prose already stating it is superseded and unmaintained.

**How it happened, and why the existing rule did not stop it.** Rule 18 and PROMPT 15 clause
3 require that a chat claim about product behaviour cite a repo file and line. **The claim
did.** It cited `docs/index.html:973`, that line said exactly what was claimed, and the
citation was accurate. The file was a **stale, unpublished copy** last touched six days
earlier that serves nothing - a fact this repository had already written down in
`CHANGELOG.md:99`, which calls it *"the unpublished `docs/index.html`"*. The instrument
introduced to prevent 12.1 was used correctly and produced a false claim anyway, because it
verifies the **provenance of a sentence** and not the **provenance of the artefact the
sentence sits in**.

This is the Class 10 pattern arriving in Class 12: the remedy for an earlier defect carrying
a defect of its own. It is worse than an uncited claim, because a citation buys confidence.
Three sessions' worth of practice would have flagged "I think the site says X"; nothing
flagged "`docs/index.html:973` says X".

**A second cost, nearly paid.** Acting on "fix the button" without finding the button would
most plausibly have meant re-uploading the ClawAgent installer to restore the download. Those
binaries were deleted **deliberately**, on the operator's revised instruction, because the
installer *"was not maintained and it was not safe to treat as sandboxed"* - recorded in
`docs/session_reports/2026-08-29_doc_truth_and_clawagent_hazard_closeout.md` section 6. A
false premise about a public surface was one inference away from republishing a withdrawn
unsafe binary.

**Changed.** Rule 18 gains the clause that this entry earned, added to
`docs/VALIDATION_PREAMBLE.md` in the same commit:

> **A citation proves the provenance of a sentence, not the provenance of the artefact.**
> Before citing a file as evidence of what a user sees, establish that the file cited is the
> file that ships. For anything served, that means naming the repository, branch and path
> the live surface is actually built from and confirming the deployed bytes match - not
> reading the nearest local copy with a plausible name. A stale copy answers every question
> you ask it, fluently and wrongly.

The general form, which is not limited to web pages: **the same question applies to any
artefact with more than one copy** - a bundled file versus its repo original, a built
installer versus its source, a vendored dependency versus upstream. Class 8 of this catalogue
is the same failure at the byte level; this is it at the citation level.

---

## The instrument-defect record

This is the most transferable thing in the project, and it is the least flattering.

The five sessions that validated v1.4.4 each counted their own defects at the end, in
the same shape: defects in the **product**, defects in the **instruments and the run
plan**, how many of those would have produced a **false finding** if they had not been
caught, how many were **ship-blocker-shaped**, and how many were caught **before the
operator was asked to touch anything**. The counts were taken by the person who made
the mistakes, in the same document that reports the results.

**The four validation machines:**

| | Box A | Boxes B and C | Box D | Box D completion | Total |
|---|---|---|---|---|---|
| **Product defects found** | 1, cosmetic | **0** | **0** | **0** | **1** |
| Instrument and run-plan defects | 8 | 5 | 5 | 5 | **23** |
| of those, would have produced a **false finding** | 3 | 2 | 3 | 3 | **11** |
| of those, **ship-blocker-shaped** | 2 | 0 | 2 | 1 | **5** |
| caught **before the operator was asked for anything** | 1 of 8 | 2 of 5 | 3 of 5 | 4 of 5 | **10 of 23** |
| Product observations carded | 1 | 0 | 1 | 2 | 4 |

**Across the final four machines, the product looked better than the instruments
measuring it.** One cosmetic product defect against twenty-three defects in the
measuring apparatus. Eleven of those twenty-three would have produced a finding that
was not true, and five of those eleven would have looked like a reason not to ship.

**The fifth session is the one that produced the release**, and it is counted
differently because it was not a measurement pass. It fixed the two product defects of
entries 2.2 and 2.3, and in doing so found **six defects in its own work**, all before
the build. Two of those six were **the exact defect class the session existed to fix,
found in the fixes themselves**. That is not a comfortable observation and it is the
honest one: the gates and the canaries are load-bearing precisely because this keeps
happening to the people who wrote them.

### What the numbers are for

They are not an apology and they are not a boast. They are the answer to a specific
question a reader of a security document should ask, which is: **when this project
reports that a boundary held, how much is that report worth?**

Three things follow from the table, and each is uncomfortable in a different way.

**A finding is a measurement, and measurements have defects at the same rate
everything else does.** Eleven false findings were prevented across four machines. The
mechanism that prevented them was not care. It was the standing requirement that every
block assertion carry a positive control which must succeed in the same run, and that
a control which did not fire voids the result rather than producing a verdict. Those
two rules did almost all of the work, mechanically, without anyone having to be
suspicious on the right day.

**Ten of the twenty-three were caught before the operator touched anything, and the
proportion rose across the cycle**: one of eight on the first machine, four of five on
the last. What changed was not skill. What changed was that reading the machine and
the probes *before dispatching* became a step rather than an instinct, which is what
class 11 is about.

**The defects that recurred were the ones already written down.** A name collision on
this project's own standing trap list was walked into by the person who had added it
to that list, the day after adding it. An expectation was left stale beside a
corrected measurement in the session immediately after a session that had named
exactly that failure and asked for it to be carried forward. **Writing a lesson down
does not apply it.** Only a rule the instrument enforces mechanically survives
contact, which is why the practices below are checks in scripts and required rows in
phases rather than paragraphs of advice.

---

## What this catalogue does not contain

**Known residuals are not in here.** The things that are still true of the shipped
product, including the ones that are weaker than their names suggest, are in
[`SECURITY_FINDINGS.md`](../SECURITY_FINDINGS.md), stated as current limitations
rather than as history. Two documents, because a fixed defect and a live one call for
different decisions from a reader.

**No user-reported issues appear here**, because there have not been any. The product
was published on 2026-08-29: this repository is public, and `v1.4.4` is its first GitHub
Release. Anything reported from here on is a user report and belongs in a different
document from this one.

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
11. **Execute the shipped thing, not a fragment of it.** A suite that extracts and
    runs the payload a wrapper builds is blind, by construction, to every defect in
    the wrapper. Two ship-blockers lived in that gap for months. Entries 2.2 and 2.3.
12. **A success marker that has never failed is not evidence.** Manufacture the
    failure it is supposed to report, and confirm it reports it. Entry 2.1.
13. **The measurement being right does not make the expectation right.** When a probe
    is edited to read something new, the assertion is a separate edit and needs its
    own calibration. Adding the reader and leaving the verdict alone produces a probe
    that gathers the right evidence and still returns the wrong answer. Entry 4.3.
14. **A probe is calibrated against a rigged input; a run is not.** Before the first
    dispatch, read what the machine already holds that the probes will read. Class 11.
15. **A record saying a thing was done is not evidence that it was.** Entries 4.3 and
    9.1. Several records agreeing is not corroboration when they share a source.
16. **A command that exits zero can still have returned half its output.** Check the
    size of what came back against the size the source reported. Entry 3.7.
17. **A summary sentence above a table is a claim about every row underneath it.**
    Where a row cannot meet it, the row carries its own method in its own cell.
    Entry 6.6.
18. **Chat does not assert product behaviour from memory.** Any claim in a chat session
    about what the product does, what ships, or how a user reaches it cites a repo file
    and line, a close-out, or the installer script. Otherwise it is labelled INFERRED.
    Every other rule here governs an instrument; this one governs the sentences said
    between measurements, which had no guard at all. Entry 12.1.
19. **A claim removed from the place it was noticed is not a claim removed.** The WHO
    half of the dependency census applies to sentences, not only to code. Entry 12.1,
    and Class 8.
20. **A citation proves the provenance of a sentence, not the provenance of the
    artefact.** Before citing a file as evidence of what a user sees, establish that the
    file cited is the file that ships. For anything served, name the repository, branch
    and path the live surface is built from and confirm the deployed bytes match. The
    same question applies to any artefact with more than one copy: a bundled file versus
    its repo original, a built installer versus its source, a vendored dependency versus
    upstream. Entry 12.3. *(This clause was written into
    `docs/VALIDATION_PREAMBLE.md` when 12.3 was recorded and was missing from this list
    until 2026-08-29.)*
21. **A measuring program that exits non-zero has not measured anything.** Its output is
    VOID, never clean. Any step that converts a non-zero exit into a count — `|| echo 0`,
    a swallowed `catch`, a default — has removed the only signal that distinguishes "found
    nothing" from "could not look". Entry 10.6.
22. **A specification for a derivation is itself a derivation, and needs running.**
    Writing down how a number must be derived is not the same as deriving it. A
    cross-check specified in `docs/V1_5_BACKLOG.md` as "both, and they must agree"
    disagreed on a correct tree the first time anyone ran it, because one comment header
    covers two gates. Class 10, one level up: the instrument was still on paper.

---

*Corrections to this document are welcome. If something here is wrong, or reads as
more flattering than the facts support, that is a defect in the same sense as any
other and we would like to know.*
