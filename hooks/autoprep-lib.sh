#!/bin/bash
# cc-parachute shared helper, sourced by userpromptsubmit-notify.sh and
# stop-autoprep.sh (not wired as a hook itself).
#
# autoprep_take <base> <sid> <lead>
#   If the statusline armed markers/<sid>.autoprep, consume it, record the
#   cooldown (with the token count, so the statusline can re-arm later), and
#   print the save-state directive. <lead> says when to save. Returns 1 when
#   there is nothing to do.

autoprep_take() {
  local base=$1 sid=$2 lead=$3
  local mark="$base/markers/$sid.autoprep" pct tok
  [[ -f "$mark" ]] || return 1
  pct=$(head -1 "$mark" 2>/dev/null)
  pct=${pct:-"?"}
  tok=$(sed -n 's/^tokens=//p' "$mark" 2>/dev/null | head -1)
  tok=${tok:-"?"}
  rm -f "$mark" "$base/markers/$sid.warn" 2>/dev/null || true
  mkdir -p "$base/markers" 2>/dev/null || true
  printf 'at=%s\ntokens=%s\n' "$(date +%s)" "$tok" > "$base/markers/$sid.autoprepped" 2>/dev/null || true
  date +%s > "$base/markers/$sid.warned" 2>/dev/null || true

  # The hook knows the exact session id, so it hands the model the exact
  # state file path - no pointer lookup, no race.
  cat <<EOF
[COMPACT PREP - ACT NOW] Context usage has reached ${pct}% (${tok} tokens); compaction may run soon.
- ${lead}
- Write the state file to: ${base}/${sid}.md (exact path for this session - no pointer lookup needed). Overwrite it if it already exists.
- Follow the compact-prep contract: a '# Compact Prep State' title, a 'saved: <ISO time> / session: <id> / cwd: <cwd>' line, then these 8 sections in this order: ## Active Plan, ## Current Phase, ## TaskList Summary, ## Session Decisions, ## Constraints and Blockers, ## Worker Topology, ## Editing Files, ## Recovery Notes.
- Be terse everywhere except Session Decisions (adopted/rejected, with reasons) and Recovery Notes (next single step, do-nots, unverified promises). Mark empty sections as none. Never write secrets into the file.
- Afterwards, tell the user in one short line that the state was saved, in the language of the conversation.
EOF
}
