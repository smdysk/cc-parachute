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
- Cross-platform test suite (37 checks), CI on Linux/macOS/Windows
