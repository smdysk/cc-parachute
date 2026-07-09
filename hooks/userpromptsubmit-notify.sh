#!/bin/bash
# cc-parachute UserPromptSubmit hook:
#  1) every turn, write the current session_id to a pointer file
#     (the /compact-prep skill reads it to name the state file)
#  2) if the statusline armed the auto-prep marker (high threshold), inject a
#     directive: the session writes its own state file THIS turn, then
#     continues the user's request (still zero extra LLM calls)
#  3) else, if the warn marker exists (lower threshold), inject a one-shot
#     /compact-prep suggestion
# Overhead: two `test -f` per turn when no marker exists.
# Fail-open: always exit 0.

set -uo pipefail

INPUT=$(cat)
SID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
# Session ids become filenames; strip path separators and other risky chars.
SID=$(printf '%s' "$SID" | tr -cd 'A-Za-z0-9._-' | head -c 128)
BASE="$HOME/.claude/compact-state"

# (1) refresh the session-id pointer for this working directory
if [[ -n "$SID" && -n "$CWD" ]]; then
  SLUG=$(printf '%s' "$CWD" | sed 's/[:\\/]/-/g')
  mkdir -p "$BASE" 2>/dev/null || true
  printf '%s\n' "$SID" > "$BASE/current-session-$SLUG" 2>/dev/null || true
fi

[[ -z "$SID" ]] && exit 0

# (2) auto-prep directive: the hook knows the exact session id, so it hands
# the model the exact state file path - no pointer lookup, no race.
AUTOPREP_MARK="$BASE/markers/$SID.autoprep"
if [[ -f "$AUTOPREP_MARK" ]]; then
  PCT=$(cat "$AUTOPREP_MARK" 2>/dev/null)
  PCT=${PCT:-"?"}
  rm -f "$AUTOPREP_MARK" "$BASE/markers/$SID.warn" 2>/dev/null || true
  mkdir -p "$BASE/markers" 2>/dev/null || true
  date +%s > "$BASE/markers/$SID.autoprepped" 2>/dev/null || true
  date +%s > "$BASE/markers/$SID.warned" 2>/dev/null || true
  STATE_PATH="$BASE/$SID.md"
  jq -n --arg ctx "[COMPACT PREP - ACT NOW] Context usage has reached ${PCT}%; auto-compaction is imminent.
- FIRST, at the start of this very response, save the working state; THEN continue the user's request in the same response.
- Write the state file to: ${STATE_PATH} (exact path for this session - no pointer lookup needed).
- Follow the compact-prep contract: a '# Compact Prep State' title, a 'saved: <ISO time> / session: <id> / cwd: <cwd>' line, then these 8 sections in this order: ## Active Plan, ## Current Phase, ## TaskList Summary, ## Session Decisions, ## Constraints and Blockers, ## Worker Topology, ## Editing Files, ## Recovery Notes.
- Be terse everywhere except Session Decisions (adopted/rejected, with reasons) and Recovery Notes (next single step, do-nots, unverified promises). Mark empty sections as none. Never write secrets into the file.
- Afterwards, tell the user the state was saved and that running /compact now is safer than waiting for auto-compact." \
    '{hookSpecificOutput:{hookEventName:"UserPromptSubmit",additionalContext:$ctx}}'
  exit 0
fi

# (3) consume the lower-tier warning marker, if any
WARN="$BASE/markers/$SID.warn"
[[ -f "$WARN" ]] || exit 0

PCT=$(cat "$WARN" 2>/dev/null)
PCT=${PCT:-"?"}
rm -f "$WARN" 2>/dev/null || true
mkdir -p "$BASE/markers" 2>/dev/null || true
date +%s > "$BASE/markers/$SID.warned" 2>/dev/null || true

jq -n --arg ctx "[COMPACT PREP REMINDER] Context usage has reached ${PCT}%.
- At the next natural break in the work, suggest that the user run /compact-prep and then /compact.
- Suggest it once; do not interrupt work in progress.
- Prefer saving state before compaction over shrinking scope or splitting the session." \
  '{hookSpecificOutput:{hookEventName:"UserPromptSubmit",additionalContext:$ctx}}'
exit 0
