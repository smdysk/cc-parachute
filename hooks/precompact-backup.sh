#!/bin/bash
# cc-parachute PreCompact hook (no matcher = fires on both manual and auto):
#  1) back up the raw transcript before compaction, as insurance against the
#     lossy summary (approach adapted from u-ichi/compact-plus, MIT)
#  2) if no /compact-prep state file exists for this session, write a
#     mechanical fallback snapshot (<sid>.auto.md): git status, recent user
#     messages, recently edited files - facts only, no LLM, no judgment
#  3) on auto-compact, record a marker so that SessionStart(compact) can add
#     extra skepticism to the recovery instructions
# Retention: 5 most recent backups per session, everything pruned after 7 days.
# Fail-open: always exit 0.

set -uo pipefail

INPUT=$(cat)
SID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
TRIGGER=$(printf '%s' "$INPUT" | jq -r '.trigger // .matcher // empty' 2>/dev/null)
TRANSCRIPT=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
# Session ids become filenames; strip path separators and other risky chars.
SID=$(printf '%s' "$SID" | tr -cd 'A-Za-z0-9._-' | head -c 128)
[[ -z "$SID" ]] && exit 0
[[ -z "$CWD" ]] && CWD="$PWD"

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

# Mechanical fallback snapshot: only when nobody saved real state.
if [[ ! -f "$BASE/$SID.md" ]]; then
  {
    echo "# Compact Prep State (mechanical fallback)"
    echo "saved: $(date +%Y-%m-%dT%H:%M:%S%z) / session: $SID / cwd: $CWD / source: precompact snapshot"
    echo
    echo "## Git"
    if git -C "$CWD" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
      echo "branch: $(git -C "$CWD" branch --show-current 2>/dev/null)"
      git -C "$CWD" status --short 2>/dev/null | head -20
      git -C "$CWD" log --oneline -5 2>/dev/null
    else
      echo "not a git repository"
    fi
    echo
    echo "## Recent user messages"
    if [[ -n "$TRANSCRIPT" && -f "$TRANSCRIPT" ]]; then
      jq -r 'select(.type=="user" and .isMeta != true) | .message.content
             | if type=="string" then . else ([.[]? | select(.type=="text") | .text] | join(" ")) end' \
        "$TRANSCRIPT" 2>/dev/null | grep -v '^[[:space:]]*$' | tail -3 | cut -c1-400 || true
    fi
    echo
    echo "## Recently edited files"
    if [[ -n "$TRANSCRIPT" && -f "$TRANSCRIPT" ]]; then
      jq -r 'select(.type=="assistant") | .message.content[]? | select(.type=="tool_use")
             | select(.name=="Edit" or .name=="Write" or .name=="NotebookEdit")
             | .input.file_path // empty' "$TRANSCRIPT" 2>/dev/null | tail -20 | sort -u | head -10 || true
    fi
    echo
    echo "## Note"
    echo "Generated mechanically at compaction because no /compact-prep state existed."
    echo "Facts only: decisions, rejections, and next steps are UNKNOWN."
  } > "$BASE/$SID.auto.md" 2>/dev/null || true
fi
find "$BASE" -maxdepth 1 -name "*.auto.md" -mtime +7 -delete 2>/dev/null || true

if [[ "$TRIGGER" == "auto" ]]; then
  date +%s > "$BASE/markers/$SID.autocompact" 2>/dev/null || true
fi
exit 0
