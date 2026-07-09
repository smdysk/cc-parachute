#!/usr/bin/env bash
# cc-parachute test suite. Run: bash test/run-tests.sh
# Uses a throwaway HOME so nothing touches your real ~/.claude.

set -uo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
HOOKS="$ROOT/hooks"

command -v jq >/dev/null 2>&1 || { echo "tests require jq" >&2; exit 1; }

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
export HOME="$WORK/home"
mkdir -p "$HOME"
BASE="$HOME/.claude/compact-state"

PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); echo "ok   - $1"; }
fail() { FAIL=$((FAIL+1)); echo "FAIL - $1"; }
assert() { local name=$1; shift; if "$@" >/dev/null 2>&1; then ok "$name"; else fail "$name"; fi; }

sl_input() { # $1=pct $2=sid
  printf '{"model":{"display_name":"TestModel"},"workspace":{"current_dir":"/tmp/proj"},"context_window":{"used_percentage":%s},"session_id":"%s"}' "$1" "$2"
}

# --- syntax ---------------------------------------------------------------
for f in "$HOOKS"/*.sh "$ROOT/install.sh" "$ROOT/test/run-tests.sh"; do
  assert "syntax: $(basename "$f")" bash -n "$f"
done

# --- statusline -----------------------------------------------------------
OUT=$(sl_input 42.5 s1 | bash "$HOOKS/statusline.sh")
assert "statusline: shows model, folder, ctx%" grep -q '\[TestModel\] proj | ctx 42%' <<<"$OUT"
assert "statusline: below threshold leaves no marker" test ! -e "$BASE/markers/s1.warn"

OUT=$(sl_input 72.3 s1 | bash "$HOOKS/statusline.sh")
assert "statusline: above threshold shows warning" grep -q '/compact-prep' <<<"$OUT"
assert "statusline: writes warn marker" grep -q '^72$' "$BASE/markers/s1.warn"

echo x > "$BASE/markers/s2.warned"
sl_input 80 s2 | bash "$HOOKS/statusline.sh" >/dev/null
assert "statusline: cooldown suppresses marker" test ! -e "$BASE/markers/s2.warn"

OUT=$(sl_input 72 s3 | CC_PARACHUTE_THRESHOLD=80 bash "$HOOKS/statusline.sh")
assert "statusline: custom threshold respected" test ! -e "$BASE/markers/s3.warn"

OUT=$(sl_input 91.2 s10 | bash "$HOOKS/statusline.sh")
assert "statusline: autoprep tier shows double warning" grep -q 'saving state next turn' <<<"$OUT"
assert "statusline: autoprep marker written" grep -q '^91$' "$BASE/markers/s10.autoprep"
assert "statusline: autoprep tier suppresses warn marker" test ! -e "$BASE/markers/s10.warn"

echo x > "$BASE/markers/s11.autoprepped"
sl_input 95 s11 | bash "$HOOKS/statusline.sh" >/dev/null
assert "statusline: autoprep cooldown suppresses marker" test ! -e "$BASE/markers/s11.autoprep"

OUT=$(sl_input 90 s12 | CC_PARACHUTE_AUTOPREP_THRESHOLD=95 bash "$HOOKS/statusline.sh")
assert "statusline: custom autoprep threshold falls back to warn tier" \
  bash -c 'test ! -e "$1/markers/s12.autoprep" && test -e "$1/markers/s12.warn"' _ "$BASE"

printf '{"model":{"display_name":"M"},"workspace":{"current_dir":"/tmp/p"},"context_window":{"used_percentage":90},"session_id":"../evil"}' \
  | bash "$HOOKS/statusline.sh" >/dev/null
assert "hardening: session id cannot escape the markers dir" \
  bash -c 'test ! -e "$1/evil.warn" && test ! -e "$1/evil.autoprep"' _ "$BASE"

# --- userpromptsubmit-notify ----------------------------------------------
UPS_IN='{"session_id":"s1","cwd":"/tmp/proj"}'
OUT=$(printf '%s' "$UPS_IN" | bash "$HOOKS/userpromptsubmit-notify.sh")
assert "notify: consumes marker and injects context" \
  bash -c 'printf "%s" "$1" | jq -e ".hookSpecificOutput.additionalContext | contains(\"72%\")"' _ "$OUT"
assert "notify: marker removed after injection" test ! -e "$BASE/markers/s1.warn"
assert "notify: cooldown marker created" test -e "$BASE/markers/s1.warned"
assert "notify: session pointer written" grep -q '^s1$' "$BASE/current-session--tmp-proj"

OUT=$(printf '%s' "$UPS_IN" | bash "$HOOKS/userpromptsubmit-notify.sh")
assert "notify: silent when no marker" test -z "$OUT"

OUT=$(printf '{"session_id":"s10","cwd":"/tmp/proj"}' | bash "$HOOKS/userpromptsubmit-notify.sh")
assert "notify: autoprep directive injected with exact state path" \
  bash -c 'printf "%s" "$1" | jq -e ".hookSpecificOutput.additionalContext | (contains(\"ACT NOW\") and contains(\"s10.md\"))"' _ "$OUT"
assert "notify: autoprep marker consumed" test ! -e "$BASE/markers/s10.autoprep"
assert "notify: autoprep cooldowns created" \
  bash -c 'test -e "$1/markers/s10.autoprepped" && test -e "$1/markers/s10.warned"' _ "$BASE"

echo 90 > "$BASE/markers/s13.autoprep"
echo 65 > "$BASE/markers/s13.warn"
OUT=$(printf '{"session_id":"s13","cwd":"/tmp/proj"}' | bash "$HOOKS/userpromptsubmit-notify.sh")
assert "notify: autoprep outranks warn and clears it" \
  bash -c 'printf "%s" "$1" | grep -q "ACT NOW" && test ! -e "$2/markers/s13.warn"' _ "$OUT" "$BASE"

# --- precompact-backup ------------------------------------------------------
TRANSCRIPT="$WORK/transcript.jsonl"
echo '{"role":"user"}' > "$TRANSCRIPT"
PC_IN=$(printf '{"session_id":"s4","trigger":"manual","transcript_path":"%s"}' "$TRANSCRIPT")
printf '%s' "$PC_IN" | bash "$HOOKS/precompact-backup.sh"
assert "precompact: transcript backed up" bash -c 'ls "$1"/transcripts/s4-*.jsonl' _ "$BASE"
assert "precompact: manual trigger leaves no auto marker" test ! -e "$BASE/markers/s4.autocompact"

PC_IN=$(printf '{"session_id":"s4","trigger":"auto","transcript_path":"%s"}' "$TRANSCRIPT")
printf '%s' "$PC_IN" | bash "$HOOKS/precompact-backup.sh"
assert "precompact: auto trigger writes marker" test -e "$BASE/markers/s4.autocompact"

T2="$WORK/transcript2.jsonl"
cat > "$T2" <<'EOF'
{"type":"user","message":{"role":"user","content":"please fix the login bug"}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Edit","input":{"file_path":"src/login.js"}}]}}
{"type":"user","isMeta":true,"message":{"role":"user","content":"meta noise"}}
{"type":"user","message":{"role":"user","content":[{"type":"text","text":"now add tests"}]}}
EOF
PC_IN=$(printf '{"session_id":"s14","trigger":"manual","transcript_path":"%s","cwd":"/tmp/notgit"}' "$T2")
printf '%s' "$PC_IN" | bash "$HOOKS/precompact-backup.sh"
SNAP="$BASE/s14.auto.md"
assert "precompact: mechanical snapshot created without prep state" \
  bash -c 'grep -q "mechanical fallback" "$1" && grep -q "please fix the login bug" "$1" && grep -q "src/login.js" "$1"' _ "$SNAP"
assert "precompact: snapshot excludes meta messages" bash -c '! grep -q "meta noise" "$1"' _ "$SNAP"

echo "# Compact Prep State" > "$BASE/s15.md"
PC_IN=$(printf '{"session_id":"s15","trigger":"manual","transcript_path":"%s","cwd":"/tmp/notgit"}' "$T2")
printf '%s' "$PC_IN" | bash "$HOOKS/precompact-backup.sh"
assert "precompact: snapshot skipped when prep state exists" test ! -e "$BASE/s15.auto.md"

# --- sessionstart-recovery --------------------------------------------------
cat > "$BASE/s4.md" <<'EOF'
# Compact Prep State
## Session Decisions
Adopted: marker relay / Rejected: polling (reason: overhead)
EOF
SS_IN='{"session_id":"s4","cwd":"/tmp/proj"}'
OUT=$(printf '%s' "$SS_IN" | bash "$HOOKS/sessionstart-recovery.sh")
assert "recovery: banner present" grep -q 'COMPACTION RECOVERY' <<<"$OUT"
assert "recovery: state file content injected" grep -q 'marker relay' <<<"$OUT"
assert "recovery: auto-compact skepticism included" grep -q 'AUTO-compact' <<<"$OUT"
assert "recovery: auto marker consumed" test ! -e "$BASE/markers/s4.autocompact"
assert "recovery: state file renamed to .used" test -e "$BASE/s4.md.used"

OUT=$(printf '%s' "$SS_IN" | bash "$HOOKS/sessionstart-recovery.sh")
assert "recovery: mechanical snapshot used as last resort" grep -q 'MECHANICAL snapshot' <<<"$OUT"
assert "recovery: mechanical snapshot renamed to .used" test -e "$BASE/s4.auto.md.used"

OUT=$(printf '{"session_id":"s6","cwd":"/tmp/proj"}' | bash "$HOOKS/sessionstart-recovery.sh")
assert "recovery: no-state path handled" grep -q 'No state file was found' <<<"$OUT"

cat > "$BASE/-tmp-proj.md" <<'EOF'
# Compact Prep State
slug fallback content
EOF
OUT=$(printf '{"cwd":"/tmp/proj"}' | bash "$HOOKS/sessionstart-recovery.sh")
assert "recovery: cwd-slug fallback works" grep -q 'slug fallback content' <<<"$OUT"

echo x > "$BASE/markers/s5.warned"
echo x > "$BASE/markers/s5.autoprepped"
printf '{"session_id":"s5","cwd":"/tmp/proj"}' | bash "$HOOKS/sessionstart-recovery.sh" >/dev/null
assert "recovery: warn cooldown reset" test ! -e "$BASE/markers/s5.warned"
assert "recovery: autoprep cooldown reset" test ! -e "$BASE/markers/s5.autoprepped"

# --- install.sh -------------------------------------------------------------
CD="$WORK/claude"
bash "$ROOT/install.sh" --claude-dir "$CD" >/dev/null
S="$CD/settings.json"
assert "install: hooks copied" test -f "$CD/hooks/cc-parachute/statusline.sh"
assert "install: skill copied" test -f "$CD/skills/compact-prep/SKILL.md"
assert "install: settings is valid JSON" jq -e . "$S"
assert "install: PreCompact wired" \
  jq -e '.hooks.PreCompact[0].hooks[0].command | endswith("precompact-backup.sh\"")' "$S"
assert "install: SessionStart matcher is compact" \
  jq -e '.hooks.SessionStart[0].matcher == "compact"' "$S"
assert "install: statusline set" jq -e '.statusLine.command | endswith("statusline.sh\"")' "$S"

bash "$ROOT/install.sh" --claude-dir "$CD" >/dev/null
assert "install: idempotent (no duplicate hooks)" \
  jq -e '(.hooks.PreCompact | length) == 1 and (.hooks.UserPromptSubmit | length) == 1' "$S"

CD2="$WORK/claude2"
bash "$ROOT/install.sh" --claude-dir "$CD2" --no-statusline >/dev/null
assert "install: --no-statusline respected" \
  jq -e '.statusLine == null' "$CD2/settings.json"

CD3="$WORK/claude3"
mkdir -p "$CD3"
printf '{"statusLine":{"type":"command","command":"my-own-statusline"}}' > "$CD3/settings.json"
bash "$ROOT/install.sh" --claude-dir "$CD3" >/dev/null
assert "install: existing statusline preserved" \
  jq -e '.statusLine.command == "my-own-statusline"' "$CD3/settings.json"

CD4="$WORK/claude dir with spaces"
bash "$ROOT/install.sh" --claude-dir "$CD4" >/dev/null
SLCMD=$(jq -r '.statusLine.command' "$CD4/settings.json")
OUT=$(sl_input 42.5 s9 | sh -c "$SLCMD")
assert "install: generated command survives spaces in path" grep -q 'ctx 42%' <<<"$OUT"

# --- summary ----------------------------------------------------------------
echo ""
echo "$PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
