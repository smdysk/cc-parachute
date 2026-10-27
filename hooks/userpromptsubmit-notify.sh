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

# (2) auto-prep directive (normally already handled by the Stop hook at the
# end of the previous turn; this catches markers armed after it ran)
# shellcheck source=autoprep-lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/autoprep-lib.sh"
if CTX=$(autoprep_take "$BASE" "$SID" "FIRST, at the start of this very response, save the working state; THEN continue the user's request in the same response."); then
  jq -n --arg ctx "$CTX" '{hookSpecificOutput:{hookEventName:"UserPromptSubmit",additionalContext:$ctx}}'
  exit 0
fi

# (3) consume the lower-tier warning marker, if any
WARN="$BASE/markers/$SID.warn"
[[ -f "$WARN" ]] || exit 0

PCT=$(head -1 "$WARN" 2>/dev/null)
PCT=${PCT:-"?"}
TOK=$(sed -n 's/^tokens=//p' "$WARN" 2>/dev/null | head -1)
rm -f "$WARN" 2>/dev/null || true
mkdir -p "$BASE/markers" 2>/dev/null || true
date +%s > "$BASE/markers/$SID.warned" 2>/dev/null || true

jq -n --arg ctx "[COMPACT PREP REMINDER] Context usage has reached ${PCT}% (${TOK:-?} tokens).
- At the next natural break in the work, suggest that the user run /compact-prep and then /compact.
- Suggest it once; do not interrupt work in progress.
- Prefer saving state before compaction over shrinking scope or splitting the session." \
  '{hookSpecificOutput:{hookEventName:"UserPromptSubmit",additionalContext:$ctx}}'
exit 0
