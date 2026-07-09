#!/bin/bash
# cc-parachute statusline: shows model / folder / context usage, and drops a
# warning marker when usage crosses the threshold. The actual reminder text is
# injected by the UserPromptSubmit hook (a statusline cannot add context).
# Threshold is configurable via CC_PARACHUTE_THRESHOLD (default 60).
# Fail-open: always exit 0.

set -uo pipefail

INPUT=$(cat)
MODEL=$(printf '%s' "$INPUT" | jq -r '.model.display_name // .model.id // "?"' 2>/dev/null)
DIR=$(printf '%s' "$INPUT" | jq -r '.workspace.current_dir // .cwd // ""' 2>/dev/null)
PCT=$(printf '%s' "$INPUT" | jq -r '.context_window.used_percentage // empty' 2>/dev/null)
SID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)

THRESHOLD="${CC_PARACHUTE_THRESHOLD:-60}"
[[ "$THRESHOLD" =~ ^[0-9]+$ ]] || THRESHOLD=60
BASENAME="${DIR##*/}"
BASENAME="${BASENAME##*\\}"

LINE="[${MODEL:-?}] ${BASENAME:-?}"
if [[ -n "$PCT" ]]; then
  INT_PCT=${PCT%%.*}
  if [[ "$INT_PCT" =~ ^[0-9]+$ ]]; then
    LINE="$LINE | ctx ${INT_PCT}%"
    if [[ -n "$SID" && "$INT_PCT" -ge "$THRESHOLD" ]]; then
      LINE="$LINE ⚠ /compact-prep"
      MARKERS="$HOME/.claude/compact-state/markers"
      # Skip while in cooldown (this session was already notified once).
      if [[ ! -f "$MARKERS/$SID.warned" ]]; then
        mkdir -p "$MARKERS" 2>/dev/null || true
        printf '%s\n' "$INT_PCT" > "$MARKERS/$SID.warn" 2>/dev/null || true
      fi
    fi
  fi
fi

printf '%s\n' "$LINE"
exit 0
