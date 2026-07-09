# Changelog

## 0.2.0 — 2026-07-10

Zero-cost automation: unprepped auto-compacts are now covered.

- Auto-prep: second statusline threshold (`CC_PARACHUTE_AUTOPREP_THRESHOLD`,
  default 85). Past it, the prompt hook injects a directive and the session
  writes its own state file — the hook supplies the exact file path, so this
  path has no pointer lookup and no same-folder race
- Mechanical fallback snapshot: if compaction arrives with no state saved,
  the PreCompact hook writes `<sid>.auto.md` (git status, recent user
  messages, recently edited files — jq and git only) and recovery injects it
  with a facts-only label
- Recovery priority: prep state > folder fallback > mechanical snapshot
- Test suite: 39 → 54 checks

## 0.1.0 — 2026-07-10

Initial release.

- Four hooks: `statusline.sh` (context meter + threshold marker),
  `userpromptsubmit-notify.sh` (one-shot reminder + session pointer),
  `precompact-backup.sh` (transcript backup + auto-compact flag),
  `sessionstart-recovery.sh` (state injection + skepticism guardrails)
- `/compact-prep` skill with a fixed 9-section state file contract
- Installers for bash (`install.sh`) and PowerShell (`install.ps1`),
  both idempotent with timestamped `settings.json` backups
- Cross-platform test suite (39 checks), CI on Linux/macOS/Windows
  including a PowerShell installer smoke test
- Hardening from pre-release review: hook commands are quoted (survives
  config paths with spaces), session ids are sanitized before filesystem
  use, PowerShell installer treats `null` settings like absent ones, and
  backup filenames are collision-proof
