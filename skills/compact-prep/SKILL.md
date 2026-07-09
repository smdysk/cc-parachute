---
name: compact-prep
description: Before running /compact, save the session's decision structure and working state to a state file that survives compaction. Triggers: /compact-prep, "compact prep", "prepare for compaction". Do not activate for post-compact recovery or routine progress reports.
argument-hint: "[recovery notes]"
user-invocable: true
---

# compact-prep — save state before compaction

A /compact summary is a record of past work. What it loses is the decision
structure: why an approach was chosen, what was rejected and why, and which
phase the work is in. This skill saves exactly that, in a fixed format, to
`~/.claude/compact-state/`. Restoration is automatic via the cc-parachute
SessionStart(compact) hook (without the hook, read the state file back in
manually after compaction).

## Hard gates

- If the session_id cannot be determined, **never fabricate one**. If the
  cwd-slug fallback is also unavailable, report "prep incomplete" and stop.
- **Never write secrets into the state file** (API keys, tokens, confidential
  client data). Reference sensitive material by file path instead.

## Steps

1. **Resolve the session_id.**
   - Slugify the cwd: replace every `:`, `/`, and `\` with `-`
     (e.g. `C:\Users\you\work` → `C--Users-you-work`, `/home/you/proj` → `-home-you-proj`).
   - Read `~/.claude/compact-state/current-session-<slug>` — a pointer file
     that the cc-parachute UserPromptSubmit hook refreshes every turn. Its
     first line is the session_id.
   - **Freshness check**: if the pointer is older than 2 minutes (hook not
     installed, or another session raced it), do not trust it — fall back and
     say so. With multiple sessions in the same folder, the pointer names the
     session that most recently submitted a prompt — a concurrent prompt from
     another session can misattribute the state file, so treat same-folder
     parallel sessions as best-effort.
   - If the pointer is missing or stale: fall back to `<slug>.md` as the state
     file name and record `unknown` in the session field.
2. Decide the destination: `~/.claude/compact-state/<session_id>.md`
   (fallback: `<slug>.md`).
3. Gather the material:
   - Task list (summarize in-progress items if you use task tracking)
   - **Approaches adopted and rejected this session, with rejection reasons**
     (this is the most important section)
   - Constraints, blockers, unfinished verifications
   - Files being edited (highlights of `git status --short`; note anything
     unsaved or unverified)
   - Current phase (if a plan exists, its path and your position in it)
   - If `$ARGUMENTS` is present, include it under Recovery Notes
4. **Write with exactly these headings, in this order** (no omissions, no
   reordering — they are the contract with the recovery hook):

   ```
   # Compact Prep State
   saved: <ISO 8601 time> / session: <session_id> / cwd: <cwd>

   ## Active Plan
   ## Current Phase
   ## TaskList Summary
   ## Session Decisions
   ## Constraints and Blockers
   ## Worker Topology
   ## Editing Files
   ## Recovery Notes
   ```

   - Mark sections that don't apply as "none" (never leave them empty).
   - Write Session Decisions as pairs: "Adopted: … / Rejected: … (reason: …)".
   - Recovery Notes is a letter to your post-compaction self: the next single
     step, things you must not do, promises awaiting verification.
5. **Read the file back** and confirm all 9 headings exist — the `#` title
   plus the 8 `##` sections (forcing function). Fix any gaps before
   proceeding.
6. Completion receipt:
   - the state file path
   - what was saved, and what could not be saved (with reasons)
   - "Prep complete. Please run `/compact`."

## Never

- Modify any file other than the state file
- Run `/compact` yourself (the user does that)
- Omit or rename headings (they are the contract with the recovery hook)
