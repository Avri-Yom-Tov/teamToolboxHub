$ErrorActionPreference = "Stop"

$repoRoot = git rev-parse --show-toplevel 2>$null
if (-not $repoRoot) {
    Write-Host "Error: Not inside a git repository." -ForegroundColor Red
    exit 1
}

$gitDir = git rev-parse --git-dir 2>$null
$hooksDir = Join-Path $gitDir "hooks"
$scriptsDir = Join-Path $repoRoot "scripts"

if (-not (Test-Path $hooksDir)) {
    New-Item -ItemType Directory -Path $hooksDir -Force | Out-Null
}

$preCommitHook = Join-Path $hooksDir "pre-commit"
$preCommitContent = @"
#!/bin/bash
if command -v powershell &>/dev/null || command -v pwsh &>/dev/null; then
    pwsh -File "$repoRoot/scripts/pre_commit.ps1" 2>/dev/null || powershell -File "$repoRoot/scripts/pre_commit.ps1" 2>/dev/null
else
    bash "$repoRoot/scripts/pre_commit.sh"
fi
"@
Set-Content -Path $preCommitHook -Value $preCommitContent -Encoding UTF8 -NoNewline

$postCommitHook = Join-Path $hooksDir "post-commit"
$postCommitContent = @"
#!/bin/bash
if command -v powershell &>/dev/null || command -v pwsh &>/dev/null; then
    pwsh -File "$repoRoot/scripts/post_commit.ps1" 2>/dev/null || powershell -File "$repoRoot/scripts/post_commit.ps1" 2>/dev/null
else
    bash "$repoRoot/scripts/post_commit.sh"
fi
"@
Set-Content -Path $postCommitHook -Value $postCommitContent -Encoding UTF8 -NoNewline

$bufferDir = Join-Path $gitDir "ai_buffer"
if (-not (Test-Path $bufferDir)) {
    New-Item -ItemType Directory -Path $bufferDir -Force | Out-Null
}

Write-Host ""
Write-Host "AI Code Tracker - Setup Complete" -ForegroundColor Green
Write-Host "================================" -ForegroundColor Green
Write-Host ""
Write-Host "Installed hooks:"
Write-Host "  pre-commit  -> scripts/pre_commit.ps1" -ForegroundColor Cyan
Write-Host "  post-commit -> scripts/post_commit.ps1" -ForegroundColor Cyan
Write-Host ""
Write-Host "Copilot agentStop hook:"
Write-Host "  .github/hooks/capture_ai.json -> scripts/log_ai_output.ps1" -ForegroundColor Cyan
Write-Host ""
Write-Host "Buffer directory: $bufferDir" -ForegroundColor DarkGray
Write-Host ""
Write-Host "To auto-push notes to remote, set:" -ForegroundColor Yellow
Write-Host '  $env:AI_TRACKER_PUSH_NOTES = "true"' -ForegroundColor Yellow
