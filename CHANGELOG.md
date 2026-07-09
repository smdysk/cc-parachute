# Changelog

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
