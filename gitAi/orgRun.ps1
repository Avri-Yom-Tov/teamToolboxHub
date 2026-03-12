



irm https://raw.githubusercontent.com/git-ai-project/git-ai/main/install.ps1 | iex



git-ai config set quiet true
git-ai config set telemetry_oss off
git-ai config set allow_repositories "https://github.com/nice-cxone/*" --add



# Push AI notes to remote - uploads attribution metadata (agent/model/lines) with every commit
# Required for: dashboard to show stats, other developers to see your AI attribution
# Without this: AI authorship data stays local only !
git config --global --add remote.origin.push 'refs/notes/*'



# Store prompts in git notes ( optional for dashboard )
# git-ai config set prompt_storage notes


# Fetch AI notes from remote - downloads attribution metadata from other developers

# Enables: git-ai blame to show who wrote what with which AI agent
# Without this: you only see your own AI attribution, not your teammates'
# Note: Dashboard works without this (GitHub Actions fetches notes manually)


# git config --global --add remote.origin.fetch '+refs/notes/*:refs/notes/*'







# git-ai install-hooks
# git-ai config set disable_auto_updates true
# git-ai config set disable_version_checks true