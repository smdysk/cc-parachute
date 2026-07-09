# Compaction Survival Benchmark — design (help wanted)

Status: design proposal, not yet implemented. Discussion and implementation
help welcome — see the tracking issue.

## Why

Every compaction tool claims to "preserve context". None of them, including
this one, has published a number. The failure mode that matters is specific
and measurable: after compaction, does the agent **re-propose rejected ideas**
or **execute steps that were awaiting verification**? A benchmark that
measures exactly that would let users pick tools on evidence — and force the
tools (this one included) to improve on the dimension that matters instead of
the dimensions that demo well.

## Method: seeded sessions (trap-based evaluation)

Each benchmark case is a scripted session transcript with a **known decision
structure** planted in it:

- an adopted approach A, chosen over B for a stated reason R
- an explicitly rejected idea C, with its rejection reason
- a promise: "verify V before doing D"
- a current phase marker ("we are in step 3 of the plan at docs/plan.md")
- filler work (tool calls, file edits) long enough to trigger compaction

Because the planted structure is known, post-compaction behavior can be
scored mechanically against it.

## Procedure

1. Replay/seed the session into a live agent (target: Claude Code headless
   `claude -p`; the transcript format is documented enough to construct
   fixtures).
2. Trigger compaction — both variants matter:
   - manual `/compact` (the prepared path)
   - auto-compact (the unprepared path; fill context with filler work)
3. Post-compaction, run a fixed set of **probes**:
   - "What approaches were considered and rejected, and why?"
   - "Should we go ahead and do D now?"  (correct answer: not before V)
   - "Which phase of the plan are we in?"
   - "What was the next step you intended?"
4. Score the answers against the planted truth.

## Metrics

| Metric | Definition |
|---|---|
| Rejected-idea re-proposal rate | probe answers that re-surface C as viable |
| Verification-skip rate | answers that green-light D without mentioning V |
| Decision recall | planted adopted/rejected pairs correctly recalled, with reasons |
| Phase accuracy | correct identification of the current plan phase |

## Conditions to compare

- Bare Claude Code (no tooling)
- cc-parachute, prepared path (`/compact-prep` before compaction)
- cc-parachute, unprepared path (mechanical snapshot only)
- compact-plus (LLM-authored state file) — measured under identical seeds

## Fairness rules

- Same seeded sessions, same probes, same scoring rubric for every condition.
- Publish everything: seeds, harness, raw outputs, scoring.
- Report the losses too. If compact-plus wins a metric, that goes in the
  README of the benchmark with the same font size as the wins.
- No cherry-picking runs: fixed N per condition, all runs reported.

## Scoring

Prefer mechanical scoring (string/semantic match against planted facts) where
possible. Where a judgment call is unavoidable, use a rubric-driven LLM judge
with the rubric published, and spot-check a sample by hand.

## Open questions

- Auto-compact triggering: reliably filling the context window in a headless
  run needs a repeatable filler workload; candidates welcome.
- Cross-version stability: compaction behavior changes across Claude Code
  releases; the benchmark must pin and report the version.
- Cost: each condition × N runs consumes real tokens; start with small N and
  report confidence intervals honestly.
