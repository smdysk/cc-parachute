# Architecture

cc-parachute is a marker-relay system built on four constraints of the Claude
Code hook surface. Understanding the constraints explains every design choice.

## The four constraints

1. **A statusline can display but cannot inject.** It renders continuously and
   is the only component that sees `context_window.used_percentage` cheaply —
   but its stdout goes to the human, not the model.
2. **UserPromptSubmit can inject but cannot see usage.** Its
   `additionalContext` output lands in the model's context, once, at prompt
   time.
3. **Hooks are stateless and short-lived.** Anything that must survive between
   events needs a file.
4. **Compaction replaces the context.** Whatever the session "knew" — including
   any intention to save state — is gone unless it was written to disk first.

The marker relay is the minimal structure that satisfies all four: the
statusline *detects* and leaves a marker; the prompt hook *consumes* the marker
and injects; the skill *persists* the session's own knowledge; the recovery
hook *restores* it into the replacement context.

## Component walk-through

### statusline.sh — detect

Renders `[model] folder | ctx N%`. Two tiers: at
`N ≥ CC_PARACHUTE_THRESHOLD` (default 60) it appends `⚠ /compact-prep` and
writes `markers/<sid>.warn`; at `N ≥ CC_PARACHUTE_AUTOPREP_THRESHOLD`
(default 85) it appends `⚠⚠ saving state next turn` and writes
`markers/<sid>.autoprep` instead. Each tier has its own cooldown marker
(`.warned` / `.autoprepped`), so each fires once per crossing — statuslines
render often, and the guard keeps that from becoming marker spam.

### userpromptsubmit-notify.sh — nudge, direct (and point)

Three jobs. Every turn it refreshes `current-session-<cwd-slug>` with the
session id — this is how the `/compact-prep` skill later learns which session
it belongs to, since skills cannot read their own session id. If an
`.autoprep` marker exists, it injects a directive rather than a nudge: write
the state file first, then continue the user's request in the same response.
The hook knows the exact session id, so the directive carries the exact state
file path — no pointer lookup, no same-folder race on this path. Otherwise, if
a `.warn` marker exists, it consumes it, writes `.warned` (cooldown), and
injects a one-shot reminder telling the model to suggest `/compact-prep` at a
natural break — explicitly *not* to interrupt work in progress. The no-marker
fast path is two `test -f`.

### /compact-prep — persist

A skill rather than a hook, deliberately: the session itself holds the decision
structure (what was adopted, what was rejected and why, what is still
unverified), and it evaporates at compaction. An external summarizer — human or
LLM — reconstructs it secondhand at best. The skill guides the session to write
a state file with nine fixed headings, then read it back to verify all nine
exist (a forcing function against lazy saves).

Hard gates: never fabricate a session id (fall back to the cwd-slug name and
say so), and never write secrets into state files — reference sensitive
material by path.

The pointer freshness check (2 minutes) catches hooks that aren't installed
and reduces — but cannot eliminate — same-folder races (see Failure modes).
Stale pointer → slug-named state file → the recovery hook still finds it via
its own slug fallback.

### precompact-backup.sh — insure

Before compaction (manual or auto), copies the raw transcript to
`compact-state/transcripts/` — the summary is lossy and irreversible, the
backup is neither. Retention: 5 per session, 7 days overall. On `trigger ==
"auto"` it drops an `.autocompact` marker: auto-compact means nobody prepared,
so recovery should distrust the summary more. (Transcript backup approach
adapted from [u-ichi/compact-plus](https://github.com/u-ichi/compact-plus), MIT.)

If no `/compact-prep` state exists for the session, it also writes
`<sid>.auto.md` — a mechanical snapshot assembled with jq and git alone: the
branch and status, the last user messages from the transcript, recently edited
files. Facts only, and labeled as such; it exists so that "no prep" never
again means "nothing at all".

### sessionstart-recovery.sh — restore

Runs with matcher `compact`, i.e. only on post-compaction restarts.
SessionStart stdout is appended directly to the fresh context, so no relay is
needed here. It locates the best available state (session id first, cwd-slug
fallback, then the mechanical `<sid>.auto.md` — injected with an explicit
facts-only warning), injects up to 8KB of it, renames it to `.used` (one-shot;
keeps forensics for 7 days), consumes the `.autocompact` marker, and resets
both threshold cooldowns so the next crossing in the slimmed-down session can
fire again.

If there is no state file, it says exactly that and instructs the model to
rebuild its bearings before acting — a compaction without prep is a known-bad
situation, and pretending otherwise is how sessions go off the rails.

## Marker lifecycle

```
.warn      created by statusline at the 60% threshold (if no .warned)
           consumed by userpromptsubmit-notify → injects reminder, writes .warned
.warned    cooldown; suppresses further .warn writes
           deleted by sessionstart-recovery after compaction
.autoprep  created by statusline at the 85% threshold (if no .autoprepped)
           consumed by userpromptsubmit-notify → injects save-now directive,
           writes .autoprepped and .warned, removes any .warn
.autoprepped  cooldown; deleted by sessionstart-recovery after compaction
.autocompact  created by precompact-backup on trigger=auto
              consumed by sessionstart-recovery → harsher skepticism
<sid>.md   created by /compact-prep (manually or via the directive)
           injected + renamed to .used by sessionstart-recovery
<sid>.auto.md  mechanical snapshot from precompact-backup when no <sid>.md
               exists; injected (facts-only label) + renamed to .used by recovery
```

Every marker has exactly one writer and exactly one remover (the statusline
additionally *reads* `.warned` to stay quiet during cooldown). That
single-writer discipline is what keeps four independent processes coherent
without a daemon.

## The skepticism guardrails

The recovery injection ends with behavioral instructions, not just data:
treat the compaction summary as a record, not instructions; don't execute
steps that were awaiting verification; don't re-propose rejected ideas; after
auto-compact, distrust the summary's judgments specifically.

These lines are the distilled cost of real incidents. The observed failure
mode of compaction is not amnesia — it's *confident action on a summary that
kept the conclusions and dropped the reasons*. A summary says "next: deploy
fix"; the dropped context said "after the client confirms". The guardrails
push the fresh session back toward primary sources: the plan file, project
rules, the state file.

## Why not…

**…have a hook run /compact-prep automatically?** In the useful sense, v0.2
does: past the autoprep threshold, the prompt hook injects a directive and the
session writes its own state file before continuing — automation without a
second LLM call. What a hook still cannot do is act *between* prompts: a
mid-turn auto-compact never passes a prompt boundary, which is why the
mechanical PreCompact snapshot exists as the floor.

**…call an LLM to write the state file (compact-plus's approach)?** If you
want zero-touch state files, that is exactly what compact-plus offers. The
trade-offs we chose against for this project: per-compaction token cost, an
API/subscription dependency, and a summarizer that reads the transcript
secondhand instead of the session reporting firsthand. Both philosophies are
legitimate; pick by taste.

**…a daemon that watches usage continuously?** A daemon is a new failure
domain (startup, crash, platform service management) to earn slightly earlier
warnings. The statusline already runs continuously for free.

**…store state per-project instead of in ~/.claude?** State files can
reference work across multiple repos in one session, and keeping them out of
project trees means they can never end up in a commit.

## Failure modes, honestly

- **Two sessions, one folder:** not fully supported. The pointer names the
  most recent prompter; invoking /compact-prep refreshes it to the invoking
  session, which closes most of the window, but a concurrent prompt from the
  other session in those same seconds can still misattribute the state file
  (and the other session's recovery would then inject it). The skill cannot
  verify its own session id — that limitation is inherent to the pointer
  design. Prefer one session per folder when you intend to /compact-prep.
- **State file > 8KB:** truncated at injection. The headings put the
  highest-value content (decisions, recovery notes) where truncation hits last
  in practice; still, keep state files terse.
- **Mid-turn auto-compact:** the auto-prep directive needs a prompt boundary
  to fire; a compaction landing mid-turn gets the mechanical snapshot instead.
  Facts survive; decision structure that was never written down does not —
  prepping at natural breaks remains the only real cure.
- **Thresholds too low/high:** defaults assume you want slack to finish a work
  unit before compacting (60) and a last-call margin before auto-compact (85).
  Tune with `CC_PARACHUTE_THRESHOLD` and `CC_PARACHUTE_AUTOPREP_THRESHOLD`.
- **Hook input schema drift:** every jq read has a `// empty` fallback and
  every hook fails open; schema drift degrades to silence, not breakage.
