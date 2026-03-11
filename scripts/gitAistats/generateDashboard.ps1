# Git AI Dashboard Generator
# Extracts Git AI statistics and generates an HTML dashboard

param(
    [string]$OutputPath = "gitAistats",
    [string]$Branch = "main"
)

Write-Host "=== Git AI Dashboard Generator ===" -ForegroundColor Cyan
Write-Host "Generating dashboard for repository: $(Split-Path -Leaf (Get-Location))" -ForegroundColor Green

# Ensure output directory exists
$rootPath = Get-Location
$outputDir = Join-Path $rootPath $OutputPath
if (!(Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

# Function to get Git AI stats in JSON format
function Get-GitAiStats {
    try {
        Write-Host "Fetching Git AI statistics..." -ForegroundColor Yellow
        
        # Try to find git-ai executable
        $gitAiPath = $null
        if (Get-Command git-ai -ErrorAction SilentlyContinue) {
            $gitAiPath = "git-ai"
        }
        elseif (Test-Path "$env:USERPROFILE\.git-ai\bin\git-ai.exe") {
            $gitAiPath = "$env:USERPROFILE\.git-ai\bin\git-ai.exe"
        }
        
        if (-not $gitAiPath) {
            Write-Host "Warning: git-ai not found. Install with: irm https://usegitai.com/install.ps1 | iex" -ForegroundColor Yellow
            return $null
        }
        
        $statsJson = & $gitAiPath stats --json 2>&1
        
        if ($LASTEXITCODE -ne 0) {
            Write-Host "Warning: git-ai stats returned non-zero exit code" -ForegroundColor Yellow
            return $null
        }
        
        # Parse JSON
        $stats = $statsJson | ConvertFrom-Json
        return $stats
    }
    catch {
        Write-Host "Error getting Git AI stats: $_" -ForegroundColor Red
        return $null
    }
}

# Function to extract commit history with AI notes
function Get-CommitHistory {
    param([int]$Limit = 10)
    
    Write-Host "Extracting commit history with AI notes (limit: $Limit)..." -ForegroundColor Yellow
    
    $commits = @()
    $gitLog = git log --format="%H|%an|%ae|%ad|%s" --date=iso -n $Limit 2>&1
    
    $counter = 0
    foreach ($line in $gitLog) {
        if ($line -match '^([a-f0-9]+)\|(.+?)\|(.+?)\|(.+?)\|(.+)$') {
            $counter++
            Write-Progress -Activity "Analyzing commits" -Status "Processing commit $counter of $Limit" -PercentComplete (($counter / $Limit) * 100)
            
            $sha = $Matches[1]
            $author = $Matches[2]
            $email = $Matches[3]
            $date = $Matches[4]
            $message = $Matches[5]
            
            # Check if AI notes exist (faster - just check, don't read content)
            git notes --ref=ai show $sha 2>&1 | Out-Null
            $hasAiContent = $LASTEXITCODE -eq 0
            
            # Store as flat PSCustomObject for better JSON serialization
            $commits += [PSCustomObject]@{
                sha = $sha.Substring(0, [Math]::Min(40, $sha.Length))
                author = $author
                date = $date
                message = $message.Substring(0, [Math]::Min(100, $message.Length))
                hasAiNote = $hasAiContent
            }
        }
    }
    
    Write-Progress -Activity "Analyzing commits" -Completed
    return $commits
}

# Function to calculate repository stats
function Get-RepoStats {
    Write-Host "Calculating repository statistics..." -ForegroundColor Yellow
    
    # Get contributors count from recent commits only (faster)
    $contributorsCount = (git log --format='%ae' -n 200 | Sort-Object -Unique | Measure-Object).Count
    
    $stats = [PSCustomObject]@{
        totalCommits = [int](git rev-list --count HEAD 2>&1)
        contributorsCount = $contributorsCount  
        lastCommitDate = (git log -1 --format='%ad' --date=iso 2>&1)
        firstCommitDate = (git log --reverse --format='%ad' --date=iso -1 2>&1)
    }
    
    return $stats
}

# Function to generate AgentExperienceRecord structure
function New-AgentExperienceRecord {
    param(
        [object]$GitAiStats,
        [object]$RepoStats,
        [object]$CommitHistory
    )
    
    # Use PSCustomObject for flatter JSON structure
    $record = [PSCustomObject]@{
        generated_at = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
        repository = [PSCustomObject]@{
            name = Split-Path -Leaf (Get-Location)
            path = (Get-Location).Path
            branch = $Branch
            total_commits = $RepoStats.totalCommits
            contributors_count = $RepoStats.contributorsCount
            first_commit = $RepoStats.firstCommitDate
            last_commit = $RepoStats.lastCommitDate
        }
        ai_metrics = [PSCustomObject]@{
            ai_percentage = if ($GitAiStats) { $GitAiStats.ai_percentage } else { 0 }
            human_percentage = if ($GitAiStats) { $GitAiStats.human_percentage } else { 100 }
            total_lines = if ($GitAiStats) { $GitAiStats.total_lines } else { 0 }
            ai_lines = if ($GitAiStats) { $GitAiStats.ai_lines } else { 0 }
            human_lines = if ($GitAiStats) { $GitAiStats.human_lines } else { 0 }
            acceptance_rate = if ($GitAiStats -and $GitAiStats.acceptance_rate) { $GitAiStats.acceptance_rate } else { 100 }
            models_used = @()
            tools_used = @()
        }
        commit_analysis = [PSCustomObject]@{
            total_analyzed = $CommitHistory.Count
            commits_with_ai = @($CommitHistory | Where-Object { $_.hasAiNote }).Count
            recent_commits = @($CommitHistory | Select-Object -First 10)
        }
        agent_experience = [PSCustomObject]@{
            task_count = @($CommitHistory | Where-Object { $_.hasAiNote }).Count
            avg_ai_contribution = if ($GitAiStats) { $GitAiStats.ai_percentage } else { 0 }
            quality_indicators = [PSCustomObject]@{
                acceptance_rate = if ($GitAiStats -and $GitAiStats.acceptance_rate) { $GitAiStats.acceptance_rate } else { 100 }
                commit_retention = "N/A"
            }
        }
    }
    
    return $record
}

# Main execution
try {
    # Collect data
    Write-Host "`nStep 1/4: Collecting Git AI statistics..." -ForegroundColor Cyan
    $gitAiStats = Get-GitAiStats
    
    Write-Host "Step 2/4: Calculating repository stats..." -ForegroundColor Cyan
    $repoStats = Get-RepoStats
    
    Write-Host "Step 3/4: Analyzing commit history..." -ForegroundColor Cyan
    $commitHistory = Get-CommitHistory -Limit 10
    
    # Generate AgentExperienceRecord
    Write-Host "Step 4/4: Generating dashboard data..." -ForegroundColor Cyan
    $dashboardData = New-AgentExperienceRecord -GitAiStats $gitAiStats -RepoStats $repoStats -CommitHistory $commitHistory
    
    # Save JSON data with sufficient depth
    $jsonPath = Join-Path $outputDir "dashboard-data.json"
    $dashboardData | ConvertTo-Json -Depth 10 -Compress:$false | Out-File -FilePath $jsonPath -Encoding UTF8
    Write-Host "Dashboard data saved to: $jsonPath" -ForegroundColor Green
    
    # Generate HTML dashboard
    $htmlPath = Join-Path $outputDir "dashboard.html"
    $templatePath = Join-Path $PSScriptRoot "dashboardTemplate.html"
    
    if (Test-Path $templatePath) {
        # Use template if exists
        $template = Get-Content $templatePath -Raw
        
        # Replace placeholders
        $html = $template -replace '{{DASHBOARD_DATA}}', ($dashboardData | ConvertTo-Json -Depth 10 -Compress)
        $html = $html -replace '{{GENERATED_AT}}', $dashboardData.generated_at
        $html = $html -replace '{{REPO_NAME}}', $dashboardData.repository.name
        
        $html | Out-File -FilePath $htmlPath -Encoding UTF8
    }
    else {
        # Generate basic HTML
        $html = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Git AI Dashboard - $($dashboardData.repository.name)</title>
    <style>
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, Cantarell, sans-serif; margin: 0; padding: 20px; background: #0d1117; color: #c9d1d9; }
        .container { max-width: 1200px; margin: 0 auto; }
        .header { text-align: center; margin-bottom: 40px; }
        .header h1 { color: #58a6ff; margin: 0; }
        .header .subtitle { color: #8b949e; margin-top: 10px; }
        .stats-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(250px, 1fr)); gap: 20px; margin-bottom: 40px; }
        .stat-card { background: #161b22; border: 1px solid #30363d; border-radius: 8px; padding: 20px; }
        .stat-card h3 { margin: 0 0 10px 0; color: #58a6ff; font-size: 14px; text-transform: uppercase; }
        .stat-card .value { font-size: 32px; font-weight: bold; color: #ffffff; }
        .stat-card .label { color: #8b949e; font-size: 12px; margin-top: 5px; }
        .progress-bar { background: #21262d; height: 30px; border-radius: 6px; overflow: hidden; margin: 20px 0; }
        .progress-fill { height: 100%; background: linear-gradient(90deg, #58a6ff, #1f6feb); display: flex; align-items: center; justify-content: center; color: white; font-weight: bold; transition: width 0.3s ease; }
        .section { background: #161b22; border: 1px solid #30363d; border-radius: 8px; padding: 20px; margin-bottom: 20px; }
        .section h2 { margin: 0 0 20px 0; color: #58a6ff; }
        .commit-list { list-style: none; padding: 0; margin: 0; }
        .commit-item { padding: 15px; border-bottom: 1px solid #30363d; display: flex; align-items: center; }
        .commit-item:last-child { border-bottom: none; }
        .commit-sha { font-family: monospace; background: #1f6feb; color: white; padding: 2px 6px; border-radius: 3px; margin-right: 10px; font-size: 12px; }
        .ai-badge { background: #238636; color: white; padding: 2px 8px; border-radius: 12px; font-size: 11px; margin-left: 10px; }
        .timestamp { color: #8b949e; font-size: 12px; margin-left: auto; }
        .footer { text-align: center; margin-top: 40px; color: #8b949e; font-size: 12px; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🤖 Git AI Dashboard</h1>
            <div class="subtitle">$($dashboardData.repository.name) - Last updated: $($dashboardData.generated_at)</div>
        </div>
        
        <div class="stats-grid">
            <div class="stat-card">
                <h3>AI Code Contribution</h3>
                <div class="value">$($dashboardData.ai_metrics.ai_percentage)%</div>
                <div class="label">of total codebase</div>
            </div>
            <div class="stat-card">
                <h3>Total Commits</h3>
                <div class="value">$($dashboardData.repository.total_commits)</div>
                <div class="label">in repository</div>
            </div>
            <div class="stat-card">
                <h3>AI Commits</h3>
                <div class="value">$($dashboardData.commit_analysis.commits_with_ai)</div>
                <div class="label">with AI contributions</div>
            </div>
            <div class="stat-card">
                <h3>Contributors</h3>
                <div class="value">$($dashboardData.repository.contributors_count)</div>
                <div class="label">unique contributors</div>
            </div>
        </div>
        
        <div class="section">
            <h2>Code Authorship</h2>
            <div style="display: flex; justify-content: space-between; margin-bottom: 10px;">
                <span>AI: $($dashboardData.ai_metrics.ai_lines) lines ($($dashboardData.ai_metrics.ai_percentage)%)</span>
                <span>Human: $($dashboardData.ai_metrics.human_lines) lines ($($dashboardData.ai_metrics.human_percentage)%)</span>
            </div>
            <div class="progress-bar">
                <div class="progress-fill" style="width: $($dashboardData.ai_metrics.ai_percentage)%">
                    $($dashboardData.ai_metrics.ai_percentage)% AI
                </div>
            </div>
        </div>
        
        <div class="section">
            <h2>Recent Commits</h2>
            <ul class="commit-list">
$(@($dashboardData.commit_analysis.recent_commits | ForEach-Object {
    $aiBadge = if ($_.hasAiNote) { '<span class="ai-badge">AI</span>' } else { '' }
    @"
                <li class="commit-item">
                    <span class="commit-sha">$($_.sha.Substring(0,7))</span>
                    <span>$($_.message)</span>
                    $aiBadge
                    <span class="timestamp">$($_.date)</span>
                </li>
"@
}) -join "`n")
            </ul>
        </div>
        
        <div class="footer">
            Powered by Git AI • Generated automatically on push to $Branch
        </div>
    </div>
    
    <script>
        // Store dashboard data for potential JavaScript processing
        const dashboardData = $($dashboardData | ConvertTo-Json -Depth 10 -Compress);
        console.log('Dashboard data loaded:', dashboardData);
    </script>
</body>
</html>
"@
        $html | Out-File -FilePath $htmlPath -Encoding UTF8
    }
    
    Write-Host "HTML dashboard saved to: $htmlPath" -ForegroundColor Green
    Write-Host ""
    Write-Host "=== Dashboard Generation Complete ===" -ForegroundColor Cyan
    Write-Host "View dashboard: file:///$($htmlPath -replace '\\', '/')" -ForegroundColor Green
    
}
catch {
    Write-Host "Error generating dashboard: $_" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor Red
    exit 1
}
