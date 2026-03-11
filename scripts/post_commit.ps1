$ErrorActionPreference = "SilentlyContinue"

$gitDir = git rev-parse --git-dir 2>$null
if (-not $gitDir) { exit 0 }

$bufferDir = Join-Path $gitDir "ai_buffer"
$metadataFile = Join-Path $bufferDir "metadata.json"

if (-not (Test-Path $metadataFile)) {
    Write-Host "[AI Tracker] No AI metadata found for this commit."
    exit 0
}

$metadata = Get-Content $metadataFile -Raw -Encoding UTF8
$commitSha = git rev-parse HEAD

git notes --ref=ai_stats add -f -m "$metadata" $commitSha 2>$null

if ($LASTEXITCODE -eq 0) {
    Write-Host "[AI Tracker] Attached AI stats to commit $($commitSha.Substring(0,7))"
} else {
    Write-Host "[AI Tracker] Warning: Failed to attach note to $($commitSha.Substring(0,7))"
}

$proposalFile = Join-Path $bufferDir "last_proposal.txt"
if (Test-Path $proposalFile) {
    Remove-Item $proposalFile -Force
}
if (Test-Path $metadataFile) {
    Remove-Item $metadataFile -Force
}

$pushNotes = $env:AI_TRACKER_PUSH_NOTES
if ($pushNotes -eq "true") {
    git push origin refs/notes/ai_stats 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "[AI Tracker] Notes pushed to remote."
    }
}
