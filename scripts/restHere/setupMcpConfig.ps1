# PowerShell script to setup GitHub Copilot MCP configuration
# Works on Windows, macOS, and Linux

# Detect OS and set appropriate path
if ($IsWindows -or $env:OS -eq "Windows_NT") {
    $mcpPath = "$env:USERPROFILE\AppData\Roaming\Code\User\mcp.json"
} elseif ($IsMacOS) {
    $mcpPath = "$env:HOME/Library/Application Support/Code/User/mcp.json"
} elseif ($IsLinux) {
    $mcpPath = "$env:HOME/.config/Code/User/mcp.json"
} else {
    Write-Host "Unsupported operating system" -ForegroundColor Red
    exit 1
}

Write-Host "Detected OS path: $mcpPath"

$githubCopilotConfig = @{
    type = "http"
    url = "https://api.githubcopilot.com/mcp/"
    headers = @{
        "X-MCP-Toolsets" = "copilot_spaces"
    }
}

# Check if the file exists
if (-not (Test-Path $mcpPath)) {
    Write-Host "File does not exist ! Creating new mcp.json..."
    
    # Create the directory if it doesn't exist !
    $directory = Split-Path -Parent $mcpPath
    if (-not (Test-Path $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
    
    # Create new JSON structure
    $newConfig = @{
        servers = @{
            githubCopilot = $githubCopilotConfig
        }
    }
    
    # Convert to JSON and save
    $newConfig | ConvertTo-Json -Depth 10 | Set-Content -Path $mcpPath -Encoding UTF8
    Write-Host "Successfully created mcp.json with GitHub Copilot configuration !"
} else {
    Write-Host "File exists ! Updating mcp.json ..."
    
    try {
        # Read existing JSON
        $existingContent = Get-Content -Path $mcpPath -Raw -Encoding UTF8
        
        # Check if file is empty or invalid
        if ([string]::IsNullOrWhiteSpace($existingContent)) {
            Write-Host "File is empty. Creating new configuration..."
            $existingConfig = [PSCustomObject]@{
                servers = [PSCustomObject]@{}
            }
        } else {
            $existingConfig = $existingContent | ConvertFrom-Json
            
            # Ensure servers object exists
            if (-not $existingConfig.servers) {
                $existingConfig | Add-Member -MemberType NoteProperty -Name "servers" -Value ([PSCustomObject]@{})
            }
        }
        
        # Add or update githubCopilot configuration
        if ($existingConfig.servers.PSObject.Properties.Name -contains "githubCopilot") {
            Write-Host "Updating existing githubCopilot configuration !"
            $existingConfig.servers.githubCopilot = [PSCustomObject]$githubCopilotConfig
        } else {
            Write-Host "Adding githubCopilot configuration !"
            $existingConfig.servers | Add-Member -MemberType NoteProperty -Name "githubCopilot" -Value ([PSCustomObject]$githubCopilotConfig) -Force
        }
        
        # Save updated JSON
        $existingConfig | ConvertTo-Json -Depth 10 | Set-Content -Path $mcpPath -Encoding UTF8
        Write-Host "Successfully updated mcp.json with GitHub Copilot configuration !"
    } catch {
        Write-Host "Error updating mcp.json :$_" -ForegroundColor Red
        exit 1
    }
}

Write-Host "`nConfiguration applied to: $mcpPath"

# Pause before exiting
    Read-Host -Prompt "`nPress Enter to exit"
