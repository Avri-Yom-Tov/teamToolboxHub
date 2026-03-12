


# ── Install Git AI ──
# irm http://usegitai.com/install.ps1 | iex
irm https://raw.githubusercontent.com/git-ai-project/git-ai/main/install.ps1 | iex


# ── Configuration ──
# Run git-ai in quiet mode - minimizes console output, only shows errors and critical information
git-ai config set quiet true
# Disable telemetry data collection
git-ai config set telemetry_oss off
git-ai config set allow_repositories "https://github.com/nice-cxone/*" --add








# ── Optional ──
# git-ai config set prompt_storage notes        # Store prompts in git notes (not just locally)
# git-ai config set disable_auto_updates true
# git-ai config set disable_version_checks true




# ── Notes sync ( safety net ) ──
# Git AI proxy handles notes sync automatically on push/fetch.
# These refspecs are a fallback for edge cases where git runs outside the proxy
# git config --global --add remote.origin.push 'refs/notes/*'
# git config --global --add remote.origin.fetch '+refs/notes/*:refs/notes/*'
