



irm https://raw.githubusercontent.com/git-ai-project/git-ai/main/install.ps1 | iex

git-ai config set prompt_storage notes
git-ai config set telemetry_oss off
git-ai config set allow_repositories "https://github.com/nice-cxone/*" --add
# git-ai config set disable_auto_updates true
# git-ai config set disable_version_checks true
git-ai config set quiet true

git config --global --add remote.origin.push 'refs/notes/*'

# git-ai install-hooks