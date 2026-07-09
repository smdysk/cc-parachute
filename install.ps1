# cc-parachute installer for Windows (PowerShell).
# Copies the hooks and the compact-prep skill into %USERPROFILE%\.claude and
# wires them into settings.json, with a timestamped backup.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File install.ps1 [-NoStatusLine] [-ClaudeDir DIR]
#
# Takes effect in NEW Claude Code sessions.
# Requires Git for Windows (hooks run via bash) and jq on PATH.

param(
    [switch]$NoStatusLine,
    [string]$ClaudeDir = "$env:USERPROFILE\.claude"
)

$ErrorActionPreference = "Stop"

$src = $PSScriptRoot
$hookDst = Join-Path $ClaudeDir "hooks\cc-parachute"
$skillDst = Join-Path $ClaudeDir "skills\compact-prep"
$settingsPath = Join-Path $ClaudeDir "settings.json"

New-Item -ItemType Directory -Force -Path $hookDst, $skillDst | Out-Null
Copy-Item (Join-Path $src "hooks\*.sh") $hookDst -Force
Copy-Item (Join-Path $src "skills\compact-prep\SKILL.md") $skillDst -Force
Write-Host "Copied hooks  -> $hookDst"
Write-Host "Copied skill  -> $skillDst"

if (-not (Test-Path $settingsPath)) {
    Set-Content -Path $settingsPath -Value "{}" -Encoding UTF8
}
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
Copy-Item $settingsPath "$settingsPath.bak-$stamp"
Write-Host "Backup        -> $settingsPath.bak-$stamp"

$cfg = Get-Content $settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
$cmdDir = $hookDst.Replace('\', '/')

function New-HookEntry([string]$matcher, [string]$script) {
    $hook = [pscustomobject]@{ type = "command"; command = "bash $cmdDir/$script" }
    if ($matcher -ne "") {
        return [pscustomobject]@{ matcher = $matcher; hooks = @($hook) }
    }
    return [pscustomobject]@{ hooks = @($hook) }
}

if (-not $cfg.PSObject.Properties["hooks"]) {
    $cfg | Add-Member -NotePropertyName hooks -NotePropertyValue ([pscustomobject]@{})
}

function Add-HookEvent([string]$eventName, $entry) {
    $existing = $cfg.hooks.PSObject.Properties[$eventName]
    if ($existing) {
        $already = @($cfg.hooks.$eventName) | Where-Object {
            ($_.hooks | ForEach-Object { $_.command }) -contains $entry.hooks[0].command
        }
        if ($already) {
            Write-Host "  $eventName : already wired, skipped"
            return
        }
        $cfg.hooks.$eventName = @($cfg.hooks.$eventName) + @($entry)
    } else {
        $cfg.hooks | Add-Member -NotePropertyName $eventName -NotePropertyValue @($entry)
    }
    Write-Host "  $eventName : added"
}

Write-Host "Wiring hooks:"
Add-HookEvent "PreCompact"       (New-HookEntry ""        "precompact-backup.sh")
Add-HookEvent "SessionStart"     (New-HookEntry "compact" "sessionstart-recovery.sh")
Add-HookEvent "UserPromptSubmit" (New-HookEntry ""        "userpromptsubmit-notify.sh")

$statusLinePending = $false
if ($NoStatusLine) {
    Write-Host "statusLine : skipped (-NoStatusLine). Threshold warnings are off."
} elseif (-not $cfg.PSObject.Properties["statusLine"]) {
    $cfg | Add-Member -NotePropertyName statusLine -NotePropertyValue ([pscustomobject]@{
        type = "command"; command = "bash $cmdDir/statusline.sh"
    })
    Write-Host "statusLine : installed ([model] folder | ctx N%)"
} else {
    Write-Host "statusLine : kept your existing statusline. To get the threshold warning, add the marker logic from hooks/statusline.sh to it." -ForegroundColor Yellow
    $statusLinePending = $true
}

$json = $cfg | ConvertTo-Json -Depth 30
[System.IO.File]::WriteAllText($settingsPath, $json)

Write-Host ""
if ($statusLinePending) {
    Write-Host "Done, with one manual step left (statusline integration above)." -ForegroundColor Yellow
} else {
    Write-Host "Done. Takes effect in new Claude Code sessions." -ForegroundColor Green
}
Write-Host "To undo: restore the backup over settings.json and delete the copied folders."
