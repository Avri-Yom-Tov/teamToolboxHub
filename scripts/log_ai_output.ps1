$ErrorActionPreference = "SilentlyContinue"

$gitDir = git rev-parse --git-dir 2>$null
if (-not $gitDir) { exit 0 }

$bufferDir = Join-Path $gitDir "ai_buffer"
if (-not (Test-Path $bufferDir)) {
    New-Item -ItemType Directory -Path $bufferDir -Force | Out-Null
}

$debugLog = Join-Path $bufferDir "debug.log"

$input_json = [Console]::In.ReadToEnd()
Add-Content -Path $debugLog -Value "$(Get-Date -Format 'o') INPUT: $input_json"

if (-not $input_json) { exit 0 }

$payload = $input_json | ConvertFrom-Json -Depth 10
if (-not $payload) { exit 0 }

$transcriptPath = $payload.transcript_path
Add-Content -Path $debugLog -Value "$(Get-Date -Format 'o') transcript_path: $transcriptPath"

if (-not $transcriptPath -or -not (Test-Path $transcriptPath)) {
    Add-Content -Path $debugLog -Value "$(Get-Date -Format 'o') transcript file not found, exiting"
    exit 0
}

$lines = Get-Content -Path $transcriptPath -Encoding UTF8
$assistantMessages = @()
foreach ($line in $lines) {
    if (-not $line.Trim()) { continue }
    $entry = $line | ConvertFrom-Json -Depth 20 -ErrorAction SilentlyContinue
    if ($entry -and $entry.type -eq "assistant.message" -and $entry.data -and $entry.data.content) {
        $assistantMessages += $entry.data.content
    }
}
Add-Content -Path $debugLog -Value "$(Get-Date -Format 'o') parsed $($lines.Count) lines, found $($assistantMessages.Count) assistant messages"

if ($assistantMessages.Count -eq 0) { exit 0 }
$aiCode = $assistantMessages[-1]
Add-Content -Path $debugLog -Value "$(Get-Date -Format 'o') extracted assistant message, length: $($aiCode.Length)"

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
    session_id = $payload.session_id
    proposal_length = $aiCode.Length
    proposal_lines = ($aiCode -split "`n").Count
} | ConvertTo-Json -Compress

$logFile = Join-Path $bufferDir "proposals.log"
Add-Content -Path $logFile -Value $logEntry
