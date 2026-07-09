#!/bin/bash
# cc-parachute statusline: shows model / folder / context usage, and drops
# marker files when usage crosses the thresholds. The actual reminder text is
# injected by the UserPromptSubmit hook (a statusline cannot add context).
# Two tiers, both configurable:
#   CC_PARACHUTE_THRESHOLD          (default 60) -> suggest /compact-prep
#   CC_PARACHUTE_AUTOPREP_THRESHOLD (default 85) -> direct the session to
#                                                   save state itself
# Fail-open: always exit 0.

set -uo pipefail

INPUT=$(cat)
MODEL=$(printf '%s' "$INPUT" | jq -r '.model.display_name // .model.id // "?"' 2>/dev/null)
DIR=$(printf '%s' "$INPUT" | jq -r '.workspace.current_dir // .cwd // ""' 2>/dev/null)
PCT=$(printf '%s' "$INPUT" | jq -r '.context_window.used_percentage // empty' 2>/dev/null)
SID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
# Session ids become filenames; strip path separators and other risky chars.
SID=$(printf '%s' "$SID" | tr -cd 'A-Za-z0-9._-' | head -c 128)

THRESHOLD="${CC_PARACHUTE_THRESHOLD:-60}"
AUTOPREP="${CC_PARACHUTE_AUTOPREP_THRESHOLD:-85}"
[[ "$THRESHOLD" =~ ^[0-9]+$ ]] || THRESHOLD=60
[[ "$AUTOPREP" =~ ^[0-9]+$ ]] || AUTOPREP=85
BASENAME="${DIR##*/}"
BASENAME="${BASENAME##*\\}"

LINE="[${MODEL:-?}] ${BASENAME:-?}"
if [[ -n "$PCT" ]]; then
  INT_PCT=${PCT%%.*}
  if [[ "$INT_PCT" =~ ^[0-9]+$ ]]; then
    LINE="$LINE | ctx ${INT_PCT}%"
    MARKERS="$HOME/.claude/compact-state/markers"
    if [[ -n "$SID" && "$INT_PCT" -ge "$AUTOPREP" ]]; then
      # Second tier: arm the auto-prep directive (fires on the next prompt).
      LINE="$LINE ⚠⚠ saving state next turn"
      if [[ ! -f "$MARKERS/$SID.autoprepped" ]]; then
        mkdir -p "$MARKERS" 2>/dev/null || true
        printf '%s\n' "$INT_PCT" > "$MARKERS/$SID.autoprep" 2>/dev/null || true
      fi
    elif [[ -n "$SID" && "$INT_PCT" -ge "$THRESHOLD" ]]; then
      LINE="$LINE ⚠ /compact-prep"
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
