$ErrorActionPreference = "SilentlyContinue"

$gitDir = git rev-parse --git-dir 2>$null
if (-not $gitDir) { exit 0 }

$bufferDir = Join-Path $gitDir "ai_buffer"
$proposalFile = Join-Path $bufferDir "last_proposal.txt"

$stagedDiff = git diff --cached --unified=0
if (-not $stagedDiff) { exit 0 }

$addedLines = ($stagedDiff -split "`n") |
    Where-Object { $_ -match '^\+[^+]' } |
    ForEach-Object { ($_ -replace '^\+', '').Trim() } |
    Where-Object { $_ -ne "" }

$totalAdded = $addedLines.Count
if ($totalAdded -eq 0) { exit 0 }

$aiCount = 0
$humanCount = 0

if (Test-Path $proposalFile) {
    $aiProposal = Get-Content $proposalFile -Raw -Encoding UTF8
    $aiLines = ($aiProposal -split "`n") |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ -ne "" }

    $aiSet = @{}
    foreach ($line in $aiLines) {
        $aiSet[$line] = $true
    }

    foreach ($line in $addedLines) {
        if ($aiSet.ContainsKey($line)) {
            $aiCount++
        } else {
            $humanCount++
        }
    }
} else {
    $humanCount = $totalAdded
}

$aiPercentage = 0
if ($totalAdded -gt 0) {
    $aiPercentage = [math]::Round(($aiCount / $totalAdded) * 100, 1)
}

$changedFiles = (git diff --cached --name-only) -split "`n" | Where-Object { $_ -ne "" }

$metadata = @{
    timestamp      = (Get-Date -Format "o")
    ai_lines       = $aiCount
    human_lines    = $humanCount
    total_added    = $totalAdded
    ai_percentage  = $aiPercentage
    files_changed  = $changedFiles
    author         = (git config user.name)
} | ConvertTo-Json -Compress

if (-not (Test-Path $bufferDir)) {
    New-Item -ItemType Directory -Path $bufferDir -Force | Out-Null
}

$metadataFile = Join-Path $bufferDir "metadata.json"
Set-Content -Path $metadataFile -Value $metadata -Encoding UTF8

Write-Host "[AI Tracker] AI: $aiCount lines ($aiPercentage%) | Human: $humanCount lines | Total: $totalAdded"
exit 0
