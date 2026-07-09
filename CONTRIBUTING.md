# Contributing to cc-parachute

Thanks for considering a contribution. This project values being small enough
to read end-to-end, so the bar for adding surface area is deliberately high —
and the bar for making the existing surface better is low.

## Ground rules

1. **Fail-open, always.** Hooks must exit 0 on every path. A bug in
   cc-parachute may cost the user a warning; it must never cost them a session.
2. **jq is the only dependency.** No Python, no Node, no curl at runtime.
   (Installers may assume git, since you cloned this repo.)
3. **Stay auditable.** If a script grows past ~100 lines, we probably took a
   wrong turn. Prefer deleting over abstracting.
4. **The 9-heading state format is a contract.** `skills/compact-prep/SKILL.md`
   and `hooks/sessionstart-recovery.sh` must stay in sync. Changing the format
   is a breaking change and needs a migration note.
5. **Tests accompany behavior.** `bash test/run-tests.sh` must pass on your
   machine; CI runs it on Linux, macOS, and Windows.

## Dev loop

```bash
bash test/run-tests.sh        # 37 checks, no network, throwaway HOME
bash -n hooks/*.sh install.sh # quick syntax pass
```

To try your changes live, run `./install.sh --claude-dir /tmp/claude-sandbox`
and inspect the generated `settings.json`, or install for real (it backs up).

## Good first issues

If one of these appeals to you, open an issue to claim it first:

1. **`uninstall.sh` / `uninstall.ps1`** — remove the three hook entries, the
   statusline (only if it's ours), and the copied folders.
2. **Localized injected messages** — `CC_PARACHUTE_LANG=ja` switching the
   recovery/reminder text (the model reads English fine; humans differ).
3. **Configurable retention** — env vars for backup generations (now 5) and
   prune days (now 7).
4. **Configurable state directory** — env var overriding
   `~/.claude/compact-state`.
5. **`npx` installer** — a thin npm wrapper so `npx cc-parachute` works.
6. **Claude Code plugin packaging** — ship hooks+skill as an installable
   plugin while keeping the script path for people who prefer auditable files.
7. **Statusline integration notes** — a doc for merging the threshold-marker
   logic into popular statuslines instead of replacing them.
8. **State file viewer** — a tiny `parachute-states` script listing recent
   state files and `.used` history.
9. **Demo GIF** — a 20-second recording for the README: warning → prep →
   compact → recovery.
10. **Codex CLI exploration** — investigate what a port of the marker relay
    would look like on Codex CLI's hook surface; write up findings.

## Conventions

- Conventional Commits (`feat:`, `fix:`, `docs:`, `test:`, `chore:`).
- One logical change per PR; include the test that proves it.
- Comments explain constraints the code can't show, in English.
