$ErrorActionPreference = "SilentlyContinue"

$gitDir = git rev-parse --git-dir 2>$null
if (-not $gitDir) { exit 0 }

$bufferDir = Join-Path $gitDir "ai_buffer"
$allProposalsFile = Join-Path $bufferDir "all_proposals.txt"

$stagedDiff = git diff --cached --unified=0
if (-not $stagedDiff) { exit 0 }

$addedLines = ($stagedDiff -split "`n") |
    Where-Object { $_ -match '^\+[^+]' } |
    ForEach-Object { ($_ -replace '^\+', '').Trim() } |
    Where-Object { $_ -ne "" }

$totalAdded = $addedLines.Count
if ($totalAdded -eq 0) { exit 0 }

function Normalize-Line([string]$line) {
    return ($line.Trim() -replace '\s+', ' ')
}

function Get-Tokens([string]$line) {
    return [regex]::Split($line, '\W+') | Where-Object { $_ -ne "" }
}

function Get-JaccardSimilarity([string[]]$tokensA, [string[]]$tokensB) {
    if ($tokensA.Count -eq 0 -and $tokensB.Count -eq 0) { return 1.0 }
    if ($tokensA.Count -eq 0 -or $tokensB.Count -eq 0) { return 0.0 }
    $setA = [System.Collections.Generic.HashSet[string]]::new([string[]]$tokensA)
    $setB = [System.Collections.Generic.HashSet[string]]::new([string[]]$tokensB)
    $intersection = [System.Collections.Generic.HashSet[string]]::new($setA)
    $intersection.IntersectWith($setB)
    $union = [System.Collections.Generic.HashSet[string]]::new($setA)
    $union.UnionWith($setB)
    return $intersection.Count / $union.Count
}

function Test-Trivial([string]$line) {
    $stripped = $line -replace '\s', ''
    if ($stripped.Length -lt 4) { return $true }
    $trivialPatterns = '^[\{\}\(\)\[\];,]+$', '^(else|break|continue|return;?)$'
    foreach ($p in $trivialPatterns) {
        if ($stripped -match $p) { return $true }
    }
    return $false
}

$aiCount = 0
$aiModifiedCount = 0
$humanCount = 0
$trivialCount = 0

if (Test-Path $allProposalsFile) {
    $aiProposal = Get-Content $allProposalsFile -Raw -Encoding UTF8
    $aiLines = ($aiProposal -split "`n") |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ -ne "" }

    $normalizedSet = @{}
    $aiTokensList = @()
    foreach ($line in $aiLines) {
        $normalized = Normalize-Line $line
        $normalizedSet[$normalized] = $true
        $aiTokensList += , (Get-Tokens $normalized)
    }

    $proposalsCount = 0
    $proposalsDir = Join-Path $bufferDir "proposals"
    if (Test-Path $proposalsDir) {
        $proposalsCount = (Get-ChildItem $proposalsDir -Filter "*.txt").Count
    }

    foreach ($line in $addedLines) {
        if (Test-Trivial $line) {
            $trivialCount++
            continue
        }

        $normalized = Normalize-Line $line
        if ($normalizedSet.ContainsKey($normalized)) {
            $aiCount++
            continue
        }

        $lineTokens = Get-Tokens $normalized
        $bestSim = 0.0
        foreach ($aiTokens in $aiTokensList) {
            $sim = Get-JaccardSimilarity $lineTokens $aiTokens
            if ($sim -gt $bestSim) { $bestSim = $sim }
            if ($bestSim -ge 0.7) { break }
        }

        if ($bestSim -ge 0.7) {
            $aiModifiedCount++
        } else {
            $humanCount++
        }
    }
} else {
    $proposalsCount = 0
    foreach ($line in $addedLines) {
        if (Test-Trivial $line) {
            $trivialCount++
        } else {
            $humanCount++
        }
    }
}

$meaningful = $aiCount + $aiModifiedCount + $humanCount
$aiPercentage = 0
if ($meaningful -gt 0) {
    $aiPercentage = [math]::Round(($aiCount + $aiModifiedCount) / $meaningful * 100, 1)
}

$changedFiles = (git diff --cached --name-only) -split "`n" | Where-Object { $_ -ne "" }

$metadata = @{
    timestamp         = (Get-Date -Format "o")
    ai_lines          = $aiCount
    ai_modified_lines = $aiModifiedCount
    human_lines       = $humanCount
    trivial_lines     = $trivialCount
    total_added       = $totalAdded
    ai_percentage     = $aiPercentage
    files_changed     = $changedFiles
    proposals_count   = $proposalsCount
    author            = (git config user.name)
} | ConvertTo-Json -Compress

if (-not (Test-Path $bufferDir)) {
    New-Item -ItemType Directory -Path $bufferDir -Force | Out-Null
}

$metadataFile = Join-Path $bufferDir "metadata.json"
Set-Content -Path $metadataFile -Value $metadata -Encoding UTF8

Write-Host "[AI Tracker] AI: $aiCount | Modified: $aiModifiedCount | Human: $humanCount | Trivial: $trivialCount | AI%%: $aiPercentage%"
exit 0
