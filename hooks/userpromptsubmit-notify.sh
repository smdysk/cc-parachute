#!/bin/bash
# cc-parachute UserPromptSubmit hook:
#  1) every turn, write the current session_id to a pointer file
#     (the /compact-prep skill reads it to name the state file)
#  2) if the statusline left a threshold-warning marker, inject a one-shot
#     /compact-prep suggestion via additionalContext
# Overhead: a single `test -f` per turn when no marker exists.
# Fail-open: always exit 0.

set -uo pipefail

INPUT=$(cat)
SID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
BASE="$HOME/.claude/compact-state"

# (1) refresh the session-id pointer for this working directory
if [[ -n "$SID" && -n "$CWD" ]]; then
  SLUG=$(printf '%s' "$CWD" | sed 's/[:\\/]/-/g')
  mkdir -p "$BASE" 2>/dev/null || true
  printf '%s\n' "$SID" > "$BASE/current-session-$SLUG" 2>/dev/null || true
fi

[[ -z "$SID" ]] && exit 0

# (2) consume the threshold-warning marker, if any
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
