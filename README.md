# 🪂 cc-parachute

**Soft landings for Claude Code context compaction.**

[![tests](https://github.com/smdysk/cc-parachute/actions/workflows/test.yml/badge.svg)](https://github.com/smdysk/cc-parachute/actions/workflows/test.yml)
[![license: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

`/compact` — and worse, auto-compact — summarizes your session and silently drops
its **decision structure**: why you chose this approach, what you rejected and why,
which phase you're in, what you promised to verify before running. Ten minutes
after a compaction, your agent re-proposes the idea you killed an hour ago, or
"helpfully" executes the step you had agreed to verify first.

cc-parachute preserves that structure across compaction with **four small shell
hooks and one skill**. No extra LLM calls, no API keys, no background processes.

## What you get

| Piece | When it runs | What it does |
|---|---|---|
| `statusline.sh` | continuously | `[Opus] myproject \| ctx 62% ⚠ /compact-prep` — context meter with threshold warning |
| `userpromptsubmit-notify.sh` | every turn | one-shot nudge to run `/compact-prep` once usage crosses the threshold (default 60%) |
| `/compact-prep` skill | you invoke it | saves a 9-heading state file: decisions, rejections, constraints, the next step |
| `precompact-backup.sh` | at compaction | backs up the raw transcript (insurance against the lossy summary), flags auto-compacts |
| `sessionstart-recovery.sh` | right after compaction | injects the state file plus skepticism guardrails into the fresh context |

## Install

Requires [jq](https://jqlang.org). On Windows, also Git for Windows (hooks run via bash).

**macOS / Linux / Git Bash:**

```bash
git clone https://github.com/smdysk/cc-parachute.git
cd cc-parachute
./install.sh            # add --no-statusline to keep your own statusline
```

**Windows (PowerShell):**

```powershell
git clone https://github.com/smdysk/cc-parachute.git
cd cc-parachute
powershell -ExecutionPolicy Bypass -File install.ps1   # add -NoStatusLine to keep yours
```

The installer copies files into `~/.claude/`, wires them into `settings.json`
with a timestamped backup, and is idempotent (run it twice, get one entry).
Takes effect in new Claude Code sessions.

## How it works

A statusline can *display* but cannot *inject context*, and hooks are stateless —
so the pieces talk through tiny marker files (a marker relay):

```
statusline.sh (renders continuously)
   │  ctx ≥ threshold → write markers/<sid>.warn   (skipped while in cooldown)
   ▼
userpromptsubmit-notify.sh (next prompt)
   │  consumes the marker → injects a one-shot "[COMPACT PREP REMINDER]"
   ▼
/compact-prep (you invoke it at a natural break)
   │  writes compact-state/<session>.md — decisions, rejections, next step
   ▼
you run /compact
   │  precompact-backup.sh backs up the raw transcript, flags "auto" compacts
   ▼
sessionstart-recovery.sh (SessionStart, matcher "compact")
      injects the state file + skepticism guardrails, resets the cooldown
```

The state file's 9 headings are a fixed contract between the skill and the
recovery hook — see [docs/architecture.md](docs/architecture.md) for the full
design rationale.

## The skepticism guardrails

Recovery injects more than the saved state. It also tells the fresh context:

> - A compaction summary is a **record of past work, not instructions for what
>   to do next**. Treat any "next steps" in it as hypotheses; trust the plan,
>   project rules, and the state file instead.
> - Do not execute steps that were awaiting verification without verifying them
>   first. Do not re-propose ideas that were already rejected.
> - *(after auto-compact)* Be especially skeptical of decisions, rejection
>   reasons, and phase assessments stated in the summary.

Each of these lines exists because of a real incident in long agent sessions.
Compaction failures are rarely "the model forgot everything" — they are the
model *confidently acting on a summary that dropped the reasons*.

## Design principles

- **Zero extra cost.** Your session writes its own state file via the skill.
  No secondary LLM call, no API key, no tokens spent on summarizing the summary.
- **Fail-open.** Every hook exits 0 no matter what. A broken marker or missing
  file degrades to "no warning", never to a blocked session.
- **Auditable.** ~160 lines of bash across four scripts. Read all of it in five
  minutes before letting it near your `settings.json` (which is backed up anyway).
- **Windows is first-class.** Developed and battle-tested on Windows 11 +
  Git Bash; CI runs the full suite on Linux, macOS, and Windows.

## vs. compact-plus

[u-ichi/compact-plus](https://github.com/u-ichi/compact-plus) (MIT) pioneered
this space, and cc-parachute's transcript backup is adapted from its approach —
credit where due. The difference is philosophy:

| | cc-parachute | compact-plus |
|---|---|---|
| State file author | your own session, guided by a skill | a separate LLM call (Claude/Codex backend) |
| Cost per compaction | zero extra tokens | one LLM summarization call |
| Footprint | 4 shell scripts + 1 skill | full plugin |
| Windows | first-class, tested in CI | not documented |

Pick compact-plus if you want a fully automatic, LLM-authored state file and
plugin packaging. Pick cc-parachute if you want something you can read
end-to-end, that costs nothing per compaction, and that treats Windows as a
first-class platform.

## FAQ

**Do I have to run /compact-prep manually?**
Yes, by design. The moment *before* compaction is exactly when the session
knows what mattered; a scheduled subprocess doesn't. The statusline warning and
the one-shot reminder exist so you never miss the window. (The reminder also
nudges Claude to suggest it at a natural break.)

**What if I never ran /compact-prep and compaction hit anyway?**
The recovery hook still fires: it says so explicitly, tells the fresh context
to rebuild its bearings from the task list and recent files, and applies the
skepticism guardrails. The raw transcript backup is in
`~/.claude/compact-state/transcripts/` if you need forensics.

**Multiple sessions in the same folder?**
Not fully supported for state saving. The session pointer names whichever
session most recently submitted a prompt; invoking `/compact-prep` refreshes
it to your session, but another session prompting in those same seconds can
still win the race, and the state file gets the wrong name. Prefer one
session per folder when you intend to use `/compact-prep`.

**Where does my data go?**
Nowhere. Everything stays under `~/.claude/compact-state/` on your machine.
Backups rotate (5 per session, 7 days). The skill is instructed never to write
secrets into state files.

**Change the warning threshold?**
Set `CC_PARACHUTE_THRESHOLD` (default 60) in the environment Claude Code runs in.

**Uninstall?**
Restore the timestamped `settings.json` backup (or remove the three hook
entries and statusline), then delete `~/.claude/hooks/cc-parachute/`,
`~/.claude/skills/compact-prep/`, and `~/.claude/compact-state/`.

## Contributing

Contributions welcome — see [CONTRIBUTING.md](CONTRIBUTING.md) for the design
rules (fail-open, jq as the only dependency) and a list of good first issues.
Run the test suite with `bash test/run-tests.sh` (39 checks, no network).

## License

[MIT](LICENSE) © 2026 Shimady

日本語のREADMEは [README.ja.md](README.ja.md) にあります。
