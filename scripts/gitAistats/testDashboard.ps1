# Test Git AI Dashboard Generation
# Quick test script to verify dashboard works

Write-Host "=== Git AI Dashboard Test ===" -ForegroundColor Cyan
Write-Host ""

# Check if Git AI is installed
Write-Host "Checking Git AI installation..." -ForegroundColor Yellow
try {
    $version = git-ai --version 2>&1
    Write-Host "✓ Git AI is installed: $version" -ForegroundColor Green
}
catch {
    Write-Host "✗ Git AI is not installed" -ForegroundColor Red
    Write-Host "Install with: irm https://usegitai.com/install.ps1 | iex" -ForegroundColor Yellow
    exit 1
}

# Check if logged in
Write-Host "`nChecking Git AI login status..." -ForegroundColor Yellow
$loginCheck = git-ai stats 2>&1
if ($LASTEXITCODE -ne 0 -and $loginCheck -match "not logged in") {
    Write-Host "✗ Not logged in to Git AI" -ForegroundColor Red
    Write-Host "Login with: git-ai login" -ForegroundColor Yellow
    exit 1
}
else {
    Write-Host "✓ Logged in to Git AI" -ForegroundColor Green
}

# Display current stats
Write-Host "`nCurrent Git AI Statistics:" -ForegroundColor Yellow
Write-Host "---" -ForegroundColor Gray
git-ai stats
Write-Host "---" -ForegroundColor Gray

# Generate dashboard
Write-Host "`nGenerating dashboard..." -ForegroundColor Yellow
$scriptPath = Join-Path $PSScriptRoot "generateDashboard.ps1"
& $scriptPath

# Check if dashboard was created
$dashboardPath = Join-Path $PSScriptRoot "gitAistats\dashboard.html"
$dataPath = Join-Path $PSScriptRoot "gitAistats\dashboard-data.json"

if ((Test-Path $dashboardPath) -and (Test-Path $dataPath)) {
    # Check if data has null metrics
    $data = Get-Content $dataPath -Raw | ConvertFrom-Json
    if ($null -eq $data.ai_metrics.ai_percentage) {
        Write-Host "`n⚠ Dashboard generated with incomplete data" -ForegroundColor Yellow
        Write-Host "Git AI statistics are not available. The dashboard will show limited information." -ForegroundColor Yellow
        Write-Host "Make sure you're in a Git repository with Git AI notes." -ForegroundColor Gray
    }
    else {
        Write-Host "`n✓ Dashboard generated successfully!" -ForegroundColor Green
    }
    Write-Host "Location: $dashboardPath" -ForegroundColor Cyan
    
    # Ask to open
    $response = Read-Host "`nOpen dashboard in browser? (Y/n)"
    if ($response -ne 'n' -and $response -ne 'N') {
        Start-Process $dashboardPath
        Write-Host "Opening dashboard..." -ForegroundColor Green
    }
}
else {
    Write-Host "`n✗ Dashboard generation failed" -ForegroundColor Red
}

Write-Host "`nTest complete!" -ForegroundColor Cyan
