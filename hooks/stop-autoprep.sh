#!/bin/bash
# cc-parachute Stop hook: if the statusline armed the auto-prep marker during
# this turn, keep the session going just long enough to save its own state
# before it goes idle. Without this, a session that crosses the threshold and
# is then left alone can be compacted (idle compaction) before the next
# prompt ever reaches the UserPromptSubmit hook.
# Costs one extra continuation, only on the turn the marker is armed.
# Fail-open: always exit 0.

set -uo pipefail

INPUT=$(cat)
SID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
ACTIVE=$(printf '%s' "$INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null)
# Session ids become filenames; strip path separators and other risky chars.
SID=$(printf '%s' "$SID" | tr -cd 'A-Za-z0-9._-' | head -c 128)
[[ -z "$SID" ]] && exit 0
# Already continuing because of a Stop hook: never block twice in a row.
[[ "$ACTIVE" == "true" ]] && exit 0

BASE="$HOME/.claude/compact-state"
# shellcheck source=autoprep-lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/autoprep-lib.sh"
CTX=$(autoprep_take "$BASE" "$SID" "Before ending this turn, save the working state now. Do not start new work.") || exit 0

jq -n --arg reason "$CTX" '{decision:"block", reason:$reason}'
exit 0
