


# ── Install Git AI ──
irm http://usegitai.com/install.ps1 | iex
# irm https://raw.githubusercontent.com/git-ai-project/git-ai/main/install.ps1 | iex
# powershell -NoProfile -ExecutionPolicy Bypass -Command "irm http://usegitai.com/install.ps1 | iex"

# ── Configuration ──
# Run git-ai in quiet mode - minimizes console output, only shows errors and critical information
git-ai config set quiet true
# Disable telemetry data collection
git-ai config set telemetry_oss off
git-ai config set allow_repositories "https://github.com/nice-cxone/*" --add




# ── Disable VS Code extension (not required for CLI-only tracking) ──
foreach ($editor in @('cursor', 'code')) {
    if (Get-Command $editor -ErrorAction SilentlyContinue) {
        & $editor --disable-extension git-ai.git-ai-vscode 2>$null
    }
}




# ── Optional Configuration ──
# Uncomment any of the following commands to enable additional features or customizations

# Store AI prompts in git notes for team-wide sharing
# By default, prompts are stored locally only. Enabling this syncs them across the team.
# Useful for: collaborative workflows, sharing AI-generated commit messages across team members
# git-ai config set prompt_storage notes

# Disable automatic updates of Git AI
# Prevents Git AI from automatically updating itself to newer versions
# Useful for: maintaining version consistency across team, controlled update schedules
# git-ai config set disable_auto_updates true

# Disable version compatibility checks
# Stops Git AI from checking if you're using the latest version
# Useful for: air-gapped environments, reducing network calls
# git-ai config set disable_version_checks true




# ── Notes sync ( safety net ) ──
# Git AI proxy handles notes sync automatically on push/fetch.
# These refspecs are a fallback for edge cases where git runs outside the proxy
# git config --global --add remote.origin.push 'refs/notes/*'
# git config --global --add remote.origin.fetch '+refs/notes/*:refs/notes/*'



# To remove the notes sync configuration 
# git config --global --unset-all remote.origin.push
# git config --global --unset-all remote.origin.fetch

