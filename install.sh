#!/usr/bin/env bash
# cc-parachute installer (macOS / Linux / Git Bash on Windows).
# Copies the hooks and the compact-prep skill into your Claude Code config
# directory and wires them into settings.json, with a timestamped backup.
#
# Usage: ./install.sh [--claude-dir DIR] [--no-statusline]
# Takes effect in NEW Claude Code sessions. Requires jq.

set -euo pipefail

CLAUDE_DIR="$HOME/.claude"
WITH_STATUSLINE=1
while [[ $# -gt 0 ]]; do
  case "$1" in
    --claude-dir) CLAUDE_DIR="$2"; shift 2 ;;
    --no-statusline) WITH_STATUSLINE=0; shift ;;
    *) echo "unknown option: $1" >&2; exit 1 ;;
  esac
done

if ! command -v jq >/dev/null 2>&1; then
  echo "cc-parachute requires jq (https://jqlang.org). Install it and re-run." >&2
  exit 1
fi

SRC_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
HOOK_DST="$CLAUDE_DIR/hooks/cc-parachute"
SKILL_DST="$CLAUDE_DIR/skills/compact-prep"
SETTINGS="$CLAUDE_DIR/settings.json"

mkdir -p "$HOOK_DST" "$SKILL_DST"
cp "$SRC_DIR"/hooks/*.sh "$HOOK_DST/"
cp "$SRC_DIR/skills/compact-prep/SKILL.md" "$SKILL_DST/"
echo "Copied hooks  -> $HOOK_DST"
echo "Copied skill  -> $SKILL_DST"

# settings.json wants forward slashes; on Git Bash convert /c/... to C:/...
CMD_DIR="$HOOK_DST"
if command -v cygpath >/dev/null 2>&1; then
  CMD_DIR=$(cygpath -m "$HOOK_DST")
fi

[[ -f "$SETTINGS" ]] || printf '{}\n' > "$SETTINGS"
STAMP=$(date +%Y%m%d-%H%M%S)
cp "$SETTINGS" "$SETTINGS.bak-$STAMP"
echo "Backup        -> $SETTINGS.bak-$STAMP"

EXISTING_SL=$(jq -r '.statusLine.command // empty' "$SETTINGS")

TMP=$(mktemp)
jq \
  --arg pre  "bash $CMD_DIR/precompact-backup.sh" \
  --arg rec  "bash $CMD_DIR/sessionstart-recovery.sh" \
  --arg note "bash $CMD_DIR/userpromptsubmit-notify.sh" \
  --arg sl   "bash $CMD_DIR/statusline.sh" \
  --argjson with_sl "$WITH_STATUSLINE" '
  .hooks = (.hooks // {})
  | .hooks.PreCompact = ((.hooks.PreCompact // []) as $l
      | if [$l[] | (.hooks // [])[] | .command] | index($pre) then $l
        else $l + [{hooks: [{type: "command", command: $pre}]}] end)
  | .hooks.SessionStart = ((.hooks.SessionStart // []) as $l
      | if [$l[] | (.hooks // [])[] | .command] | index($rec) then $l
        else $l + [{matcher: "compact", hooks: [{type: "command", command: $rec}]}] end)
  | .hooks.UserPromptSubmit = ((.hooks.UserPromptSubmit // []) as $l
      | if [$l[] | (.hooks // [])[] | .command] | index($note) then $l
        else $l + [{hooks: [{type: "command", command: $note}]}] end)
  | if $with_sl == 1 and .statusLine == null
    then .statusLine = {type: "command", command: $sl}
    else . end
' "$SETTINGS" > "$TMP"
mv "$TMP" "$SETTINGS"

echo "Hooks wired   -> $SETTINGS"
if [[ "$WITH_STATUSLINE" == "1" ]]; then
  if [[ -n "$EXISTING_SL" && "$EXISTING_SL" != "bash $CMD_DIR/statusline.sh" ]]; then
    echo "statusLine    -> kept your existing statusline. To get the threshold"
    echo "                 warning, add the marker logic from hooks/statusline.sh to it."
  else
    echo "statusLine    -> installed ([model] folder | ctx N%)"
  fi
else
  echo "statusLine    -> skipped (--no-statusline). Threshold warnings are off."
fi
echo ""
echo "Done. Takes effect in new Claude Code sessions."
echo "To undo: restore the backup over settings.json and delete the copied folders."
