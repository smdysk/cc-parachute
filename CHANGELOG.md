# Changelog

## 0.3.0 — 2026-10-27

Thresholds now work on 1M-token context windows.

- Token thresholds: each tier fires on whichever comes first, percent or
  absolute tokens (`CC_PARACHUTE_WARN_TOKENS`, default 150000;
  `CC_PARACHUTE_AUTOPREP_TOKENS`, default 180000). On 1M windows the used
  percent is measured against the whole window while compaction (including
  idle compaction from about 200k tokens) runs much earlier, so the percent
  thresholds alone never fired
- Stop hook (`stop-autoprep.sh`): when auto-prep is armed, the session saves
  its state at the end of that turn instead of on the next prompt, so a
  session left idle is covered too. Costs one short continuation
- Re-arm: after an auto-prep save, the directive fires again once usage grows
  by `CC_PARACHUTE_REARM_TOKENS` (default 150000), so the saved state does not
  go stale before a late compaction
- Statusline shows the token count next to the percent (`ctx 16% 162k`)
- Test suite: 54 → 72 checks

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
