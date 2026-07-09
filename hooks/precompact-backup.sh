#!/bin/bash
# cc-parachute PreCompact hook (no matcher = fires on both manual and auto):
#  1) back up the raw transcript before compaction, as insurance against the
#     lossy summary (approach adapted from u-ichi/compact-plus, MIT)
#  2) on auto-compact, record a marker so that SessionStart(compact) can add
#     extra skepticism to the recovery instructions
# Retention: 5 most recent backups per session, everything pruned after 7 days.
# Fail-open: always exit 0.

set -uo pipefail

INPUT=$(cat)
SID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
TRIGGER=$(printf '%s' "$INPUT" | jq -r '.trigger // .matcher // empty' 2>/dev/null)
TRANSCRIPT=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
# Session ids become filenames; strip path separators and other risky chars.
SID=$(printf '%s' "$SID" | tr -cd 'A-Za-z0-9._-' | head -c 128)
[[ -z "$SID" ]] && exit 0

BASE="$HOME/.claude/compact-state"
TDIR="$BASE/transcripts"
mkdir -p "$TDIR" "$BASE/markers" 2>/dev/null || true

if [[ -n "$TRANSCRIPT" && -f "$TRANSCRIPT" ]]; then
  cp "$TRANSCRIPT" "$TDIR/$SID-$(date +%Y%m%d-%H%M%S).jsonl" 2>/dev/null || true
  ls -1t "$TDIR/$SID-"*.jsonl 2>/dev/null | tail -n +6 | while read -r old; do
    rm -f "$old" 2>/dev/null || true
  done
  find "$TDIR" -name "*.jsonl" -mtime +7 -delete 2>/dev/null || true
fi

if [[ "$TRIGGER" == "auto" ]]; then
  date +%s > "$BASE/markers/$SID.autocompact" 2>/dev/null || true
fi
exit 0
