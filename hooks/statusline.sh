#!/bin/bash
# cc-parachute statusline: shows model / folder / context usage, and drops
# marker files when usage crosses the thresholds. The actual reminder text is
# injected by the UserPromptSubmit / Stop hooks (a statusline cannot add context).
# Two tiers; each fires on whichever comes first, percent or absolute tokens.
# Percent alone is not enough: on 1M-token windows auto-compact (and idle
# compaction) can run long before 60% of the window is used.
#   CC_PARACHUTE_THRESHOLD          (default 60)     -> suggest /compact-prep
#   CC_PARACHUTE_WARN_TOKENS        (default 150000)
#   CC_PARACHUTE_AUTOPREP_THRESHOLD (default 85)     -> direct the session to
#   CC_PARACHUTE_AUTOPREP_TOKENS    (default 180000)    save state itself
#   CC_PARACHUTE_REARM_TOKENS       (default 150000) -> after a save, arm the
#                                                       directive again once usage
#                                                       grows by this much
# Fail-open: always exit 0.

set -uo pipefail

INPUT=$(cat)
MODEL=$(printf '%s' "$INPUT" | jq -r '.model.display_name // .model.id // "?"' 2>/dev/null)
DIR=$(printf '%s' "$INPUT" | jq -r '.workspace.current_dir // .cwd // ""' 2>/dev/null)
PCT=$(printf '%s' "$INPUT" | jq -r '.context_window.used_percentage // empty' 2>/dev/null)
TOKENS=$(printf '%s' "$INPUT" | jq -r '.context_window.total_input_tokens
  // (.context_window.current_usage // empty
      | (.input_tokens // 0) + (.cache_creation_input_tokens // 0) + (.cache_read_input_tokens // 0))
  // empty' 2>/dev/null)
SID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
# Session ids become filenames; strip path separators and other risky chars.
SID=$(printf '%s' "$SID" | tr -cd 'A-Za-z0-9._-' | head -c 128)

int_or() { [[ "$1" =~ ^[0-9]+$ ]] && echo "$1" || echo "$2"; }
THRESHOLD=$(int_or "${CC_PARACHUTE_THRESHOLD:-}" 60)
AUTOPREP=$(int_or "${CC_PARACHUTE_AUTOPREP_THRESHOLD:-}" 85)
WARN_TOKENS=$(int_or "${CC_PARACHUTE_WARN_TOKENS:-}" 150000)
AUTOPREP_TOKENS=$(int_or "${CC_PARACHUTE_AUTOPREP_TOKENS:-}" 180000)
REARM_TOKENS=$(int_or "${CC_PARACHUTE_REARM_TOKENS:-}" 150000)

INT_PCT=${PCT%%.*}
[[ "$INT_PCT" =~ ^[0-9]+$ ]] || INT_PCT=""
INT_TOK=${TOKENS%%.*}
[[ "$INT_TOK" =~ ^[0-9]+$ ]] || INT_TOK=""

BASENAME="${DIR##*/}"
BASENAME="${BASENAME##*\\}"
LINE="[${MODEL:-?}] ${BASENAME:-?}"
[[ -n "$INT_PCT" ]] && LINE="$LINE | ctx ${INT_PCT}%"
[[ -n "$INT_TOK" ]] && LINE="$LINE $((INT_TOK / 1000))k"

reached() { # $1=pct threshold $2=token threshold
  [[ -n "$INT_PCT" && "$INT_PCT" -ge "$1" ]] && return 0
  [[ -n "$INT_TOK" && "$INT_TOK" -ge "$2" ]] && return 0
  return 1
}

# The autoprep cooldown records the token count at the last save, so the
# directive can fire again once the session has grown well past that save.
autoprep_cooling() {
  local done_file="$MARKERS/$SID.autoprepped" last
  [[ -f "$done_file" ]] || return 1
  last=$(sed -n 's/^tokens=\([0-9][0-9]*\)$/\1/p' "$done_file" 2>/dev/null | head -1)
  [[ -n "$last" && -n "$INT_TOK" && "$INT_TOK" -ge $((last + REARM_TOKENS)) ]] && return 1
  return 0
}

MARKERS="$HOME/.claude/compact-state/markers"
if [[ -n "$SID" ]] && reached "$AUTOPREP" "$AUTOPREP_TOKENS"; then
  # Second tier: arm the auto-prep directive (fires at the end of this turn
  # via the Stop hook, or on the next prompt).
  if ! autoprep_cooling; then
    LINE="$LINE ⚠⚠ saving state"
    mkdir -p "$MARKERS" 2>/dev/null || true
    printf '%s\ntokens=%s\n' "${INT_PCT:-?}" "${INT_TOK:-?}" > "$MARKERS/$SID.autoprep" 2>/dev/null || true
  fi
elif [[ -n "$SID" ]] && reached "$THRESHOLD" "$WARN_TOKENS"; then
  LINE="$LINE ⚠ /compact-prep"
  # Skip while in cooldown (this session was already notified once).
  if [[ ! -f "$MARKERS/$SID.warned" ]]; then
    mkdir -p "$MARKERS" 2>/dev/null || true
    printf '%s\ntokens=%s\n' "${INT_PCT:-?}" "${INT_TOK:-?}" > "$MARKERS/$SID.warn" 2>/dev/null || true
  fi
fi

printf '%s\n' "$LINE"
exit 0
