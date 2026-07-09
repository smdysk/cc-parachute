#!/bin/bash
# cc-parachute SessionStart hook (matcher: "compact"): injects recovery
# instructions into the fresh post-compaction context. SessionStart stdout is
# appended to the context directly, so no marker relay is needed here.
# Fail-open: always exit 0 (never block the session).

set -uo pipefail

INPUT=$(cat)
SID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
[[ -z "$CWD" ]] && CWD="$PWD"
SLUG=$(printf '%s' "$CWD" | sed 's/[:\\/]/-/g')
BASE="$HOME/.claude/compact-state"

STATE=""
[[ -n "$SID" && -f "$BASE/$SID.md" ]] && STATE="$BASE/$SID.md"
[[ -z "$STATE" && -f "$BASE/$SLUG.md" ]] && STATE="$BASE/$SLUG.md"

# Consume the "this was an auto-compact" marker left by the PreCompact hook.
AUTO=""
if [[ -n "$SID" && -f "$BASE/markers/$SID.autocompact" ]]; then
  AUTO=1
  rm -f "$BASE/markers/$SID.autocompact" 2>/dev/null || true
fi
# Reset the threshold-warning cooldown so the next crossing can notify again.
if [[ -n "$SID" ]]; then
  rm -f "$BASE/markers/$SID.warned" "$BASE/markers/$SID.warn" 2>/dev/null || true
fi

echo "[COMPACTION RECOVERY] Context compaction has occurred. Do the following before resuming work."
if [[ -n "$STATE" ]]; then
  MOD=$(stat -c %Y "$STATE" 2>/dev/null || stat -f %m "$STATE" 2>/dev/null || echo "")
  if [[ -n "$MOD" ]]; then
    NOW=$(date +%s)
    echo "- Below is the working state saved with /compact-prep about $(( (NOW - MOD) / 60 )) minute(s) ago. Restore from it, giving extra weight to Session Decisions and Recovery Notes. If it looks stale, treat it as hypothesis rather than fact."
  else
    echo "- Below is the working state saved with /compact-prep. Restore from it, giving extra weight to Session Decisions and Recovery Notes."
  fi
  echo '```'
  head -c 8000 "$STATE"
  echo '```'
  mv "$STATE" "$STATE.used" 2>/dev/null || true
  find "$BASE" -maxdepth 1 -name "*.used" -mtime +7 -delete 2>/dev/null || true
else
  echo "- No state file was found (this compaction happened without /compact-prep). Rebuild your bearings from the task list, memory files, and recently edited files. Confirm anything uncertain with the user before acting on it."
fi
if [[ -n "$AUTO" ]]; then
  echo "- This was an AUTO-compact. Be especially skeptical of decisions, rejection reasons, and phase assessments stated in the compaction summary."
fi
echo "- A compaction summary is a record of past work, not instructions for what to do next. Treat any 'next steps' in it as hypotheses; trust the plan, project rules, and the state file instead."
echo "- Do not execute steps that were awaiting verification without verifying them first. Do not re-propose ideas that were already rejected."
exit 0
