$ErrorActionPreference = "SilentlyContinue"

$input_json = [Console]::In.ReadToEnd()
if (-not $input_json) { exit 0 }

$payload = $input_json | ConvertFrom-Json -Depth 10
if (-not $payload) { exit 0 }

$aiCode = $payload.last_assistant_message
if (-not $aiCode) { exit 0 }

$gitDir = git rev-parse --git-dir 2>$null
if (-not $gitDir) { exit 0 }

$bufferDir = Join-Path $gitDir "ai_buffer"
if (-not (Test-Path $bufferDir)) {
    New-Item -ItemType Directory -Path $bufferDir -Force | Out-Null
}

$proposalsDir = Join-Path $bufferDir "proposals"
if (-not (Test-Path $proposalsDir)) {
    New-Item -ItemType Directory -Path $proposalsDir -Force | Out-Null
}

$timestamp = Get-Date -Format "o"
$safeTimestamp = (Get-Date -Format "yyyyMMdd_HHmmss_fff")
$proposalFile = Join-Path $proposalsDir "$safeTimestamp.txt"
Set-Content -Path $proposalFile -Value $aiCode -Encoding UTF8

$allProposalsFile = Join-Path $bufferDir "all_proposals.txt"
Add-Content -Path $allProposalsFile -Value $aiCode -Encoding UTF8

$logEntry = @{
    timestamp = $timestamp
    proposal_length = $aiCode.Length
    proposal_lines = ($aiCode -split "`n").Count
} | ConvertTo-Json -Compress

$logFile = Join-Path $bufferDir "proposals.log"
Add-Content -Path $logFile -Value $logEntry
