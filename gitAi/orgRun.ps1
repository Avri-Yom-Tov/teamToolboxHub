# 1. Detect real git path (skip git-ai shim, check known install locations)




$gitAiBin = "$env:USERPROFILE\.git-ai\bin"

$candidates = @(
    (Get-Command git -ErrorAction SilentlyContinue -All |
        Where-Object { $_.Source -notlike "$gitAiBin*" } |
        Select-Object -First 1 -ExpandProperty Source)
    "$env:ProgramFiles\Git\cmd\git.exe"
    "${env:ProgramFiles(x86)}\Git\cmd\git.exe"
    "$env:LOCALAPPDATA\Programs\Git\cmd\git.exe"
) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1



if (-not $candidates) {
    Write-Error "Could not find git.exe. Please install Git first !"
    exit 1
}


$realGit = (Resolve-Path $candidates).Path
Write-Host "Detected git at: $realGit"

# 2. מתקין git-ai
irm http://usegitai.com/install.ps1 | iex

# 3. קונפיג git-ai
$configDir = "$env:USERPROFILE\.git-ai"
$configPath = "$configDir\config.json"
New-Item -ItemType Directory -Force -Path $configDir | Out-Null

$escapedGitPath = $realGit -replace '\\', '\\\\'
@"
{
    "git_path": "$escapedGitPath",
    "prompt_storage": "notes",
    "telemetry_oss": "off",
    "allow_repositories": ["https://github.com/nice-cxone/*"],
    "disable_auto_updates": true,
    "disable_version_checks": true,
    "quiet": true
}
"@ | Set-Content -Path $configPath

# 4. קונפיג git גלובלי - דחיפת notes אוטומטית
git config --global --add remote.origin.push 'refs/notes/*'