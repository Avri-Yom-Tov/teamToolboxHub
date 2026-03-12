# Git AI — Free Tier Organization Rollout Guide

Deploy Git AI across your organization using only the free open-source tier. All data stored in your company's GitHub via git notes — no cloud accounts, no payments.

## Architecture Overview

```
Developer Machine                    GitHub (your org)
┌─────────────────────┐              ┌──────────────────────┐
│ Coding Agent         │              │ Repository           │
│ (Cursor/Claude/etc)  │              │ ├── branches         │
│      │               │   git push   │ ├── tags             │
│      ▼               │ ──────────►  │ └── refs/notes/ai    │
│ git-ai checkpoint    │              │     (authorship logs) │
│      │               │   git fetch  │                      │
│      ▼               │ ◄──────────  │                      │
│ git commit           │              │                      │
│ (note attached)      │              │                      │
└─────────────────────┘              └──────────────────────┘
```

- Authorship logs stored as git notes in `refs/notes/ai`
- Notes sync automatically on push/fetch
- No external services required
- Works 100% offline

## Rollout Checklist

```
- [ ] Phase 1: Pilot group (5-10 developers)
- [ ] Phase 2: Define org-wide config
- [ ] Phase 3: Distribute to all developers
- [ ] Phase 4: Verify and monitor
```

---

## Phase 1: Pilot Group

**Recommended pilot**: 10–20 engineers, 1–3 repositories, 2–4 weeks. Goals: confirm Git AI doesn't get in the way, and verify data accuracy.

### 1.1 Install on pilot machines

**Mac / Linux / WSL:**

```bash
curl -sSL https://usegitai.com/install.sh | bash
```

**Windows (PowerShell):**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Command "irm http://usegitai.com/install.ps1 | iex"
```

### 1.2 Verify installation

```bash
which git              # ~/.git-ai/bin/git
git-ai --version       # shows version
git-ai install-hooks   # configure agent integrations
```

### 1.3 Test the flow

1. Open Cursor (or any supported agent), generate some code with 2–3 agents from the team's normal workflow
2. Run `git-ai status` to see AI vs human attribution
3. Commit: `git commit -a -m "test AI tracking"`
4. Check blame: `git-ai blame src/example.ts` — every AI-written line is attributed to the agent/model
5. Check note: `git log --show-notes=ai`
6. Push and verify notes sync: `git push`
7. On another machine: `git fetch` then `git-ai blame <file>`

### 1.4 Test history-rewriting operations

Attribution should survive all of these:

```bash
git rebase main
git cherry-pick <sha>
git commit --amend
git add -p              # partial staging
```

Run `git-ai blame` after each one to verify.

---

## Phase 2: Organization Configuration

### 2.1 Standard config.json

Create the standard config for all developers:

```json
{
    "prompt_storage": "notes",
    "allow_repositories": [
        "https://github.com/YOUR_ORG/*"
    ],
    "telemetry_oss": "off",
    "disable_auto_updates": true,
    "update_channel": "latest"
}
```

**Key settings explained:**

| Setting | Value | Why |
|---------|-------|-----|
| `prompt_storage` | `"notes"` | Store prompts in git notes so all team members can access attribution |
| `allow_repositories` | org glob | Only track repos in your org |
| `telemetry_oss` | `"off"` | No anonymous data sent to Git AI maintainers |
| `disable_auto_updates` | `true` | Control updates via your own rollout schedule |

**Additional config options for advanced setups:**

| Setting | Value | Why |
|---------|-------|-----|
| `include_prompts_in_repositories` | Pattern[] | Override prompt storage for specific repos |
| `default_prompt_storage` | `"local"` or `"notes"` | Fallback storage mode for repos not in include list |
| `feature_flags` | object | Feature flag overrides, set with dot notation (`feature_flags.my_flag`) |

### 2.2 Optional: Exclude sensitive repos

```json
{
    "prompt_storage": "notes",
    "allow_repositories": ["https://github.com/YOUR_ORG/*"],
    "exclude_repositories": [
        "https://github.com/YOUR_ORG/secret-project"
    ],
    "exclude_prompts_in_repositories": [
        "https://github.com/YOUR_ORG/classified-*"
    ],
    "telemetry_oss": "off",
    "disable_auto_updates": true
}
```

- `exclude_repositories`: Git AI disabled entirely for these repos
- `exclude_prompts_in_repositories`: AI attribution tracked but prompt content excluded

### 2.3 Create .git-ai-ignore per repo (optional)

In repository root, create `.git-ai-ignore` to exclude files from stats:

```
docs/generated/**
*.snap
vendor/**
*.lock
```

---

## Phase 3: Distribution

### Option A: Share install command (small teams)

Share the install command via Slack/email and the config.json as a file or snippet.

Each developer runs:

```bash
# Install
curl -sSL https://usegitai.com/install.sh | bash

# Apply org config
cat > ~/.git-ai/config.json << 'EOF'
{
    "prompt_storage": "notes",
    "allow_repositories": ["https://github.com/YOUR_ORG/*"],
    "telemetry_oss": "off",
    "disable_auto_updates": true
}
EOF

# Setup agent hooks
git-ai install-hooks
```

### Option B: MDM / Endpoint Management — User-Scoped Directory (large teams)

For enterprise-scale rollout without manual steps. Installs to `~/.git-ai/bin/`:

1. **Download the binary** from the official install scripts:
   - Windows: https://github.com/git-ai-project/git-ai/blob/main/install.ps1
   - Unix: https://github.com/git-ai-project/git-ai/blob/main/install.sh

2. **Install binary** to `~/.git-ai/bin/git-ai`

3. **Create symlinks**:
   - `git-og` → original git binary
   - `git` → `git-ai`

4. **Deploy config.json** to `~/.git-ai/config.json`

5. **Update PATH**: Add `~/.git-ai/bin` before other git directories

6. **Run `git-ai install-hooks`** to set up agent integrations

#### Windows MDM specifics

```powershell
# Install binary
$installDir = "$env:USERPROFILE\.git-ai\bin"
New-Item -ItemType Directory -Path $installDir -Force

# Create git-og.cmd pointing to original git
$originalGit = (Get-Command git).Source
"@echo off`n`"$originalGit`" %*" | Set-Content "$installDir\git-og.cmd"

# Copy git-ai binary and create git.exe
Copy-Item "path\to\git-ai.exe" "$installDir\git-ai.exe"
Copy-Item "$installDir\git-ai.exe" "$installDir\git.exe"

# Deploy config
@"
{
    "git_path": "$installDir\\git-og.cmd",
    "prompt_storage": "notes",
    "allow_repositories": ["https://github.com/YOUR_ORG/*"],
    "telemetry_oss": "off",
    "disable_auto_updates": true
}
"@ | Set-Content "$env:USERPROFILE\.git-ai\config.json"

# Add to PATH (user level)
$currentPath = [Environment]::GetEnvironmentVariable("PATH", "User")
if ($currentPath -notlike "*\.git-ai\bin*") {
    [Environment]::SetEnvironmentVariable("PATH", "$installDir;$currentPath", "User")
}
```

### Option C: MDM — Overwrite Existing Git Symlink

Use when your fleet already exposes `git` from a shared directory locked into PATH (e.g. `/usr/local/bin/git`). No PATH changes needed — just replace the existing `git` entry.

> macOS SIP prevents modifying `/usr/bin`, so pick a writable directory like `/usr/local/bin`.

#### Unix/Linux/macOS

```bash
git_path="$(command -v git)"
git_dir="$(dirname "$git_path")"

# Preserve original git
if [ -L "$git_path" ]; then
    sudo ln -sf "$(readlink "$git_path")" "$git_dir/git-og"
else
    sudo mv "$git_path" "$git_dir/git-og"
fi

# Install git-ai and point git at it
sudo install -m 0755 /path/to/git-ai "$git_dir/git-ai"
sudo ln -sf "$git_dir/git-ai" "$git_path"
```

#### Windows

```powershell
$gitPath = (Get-Command git).Source
$gitDir = Split-Path $gitPath

# Preserve original git
if ((Get-Item $gitPath).Attributes -band [IO.FileAttributes]::ReparsePoint) {
    $target = (Get-Item $gitPath).Target
    New-Item -ItemType SymbolicLink -Path (Join-Path $gitDir 'git-og.exe') -Target $target | Out-Null
    Remove-Item $gitPath
} else {
    Rename-Item -Path $gitPath -NewName 'git-og.exe'
}

# Install git-ai
Copy-Item -Path 'C:\path\to\git-ai.exe' -Destination (Join-Path $gitDir 'git-ai.exe')

# Replace git.exe (symlink requires Developer Mode or elevated privileges)
New-Item -ItemType SymbolicLink -Path (Join-Path $gitDir 'git.exe') -Target (Join-Path $gitDir 'git-ai.exe')

# Fallback when symlinks are unavailable
# Copy-Item -Path (Join-Path $gitDir 'git-ai.exe') -Destination (Join-Path $gitDir 'git.exe')
```

For Option C, `config.json` `git_path` should point to the absolute path of the preserved binary (e.g. `/usr/local/bin/git-og` or `C:\Program Files\Git\cmd\git-og.exe`).

#### Verify installation (all platforms)

```bash
which git          # should show .git-ai/bin/git (Option B) or existing path (Option C)
git-ai --version   # should show version
git-og --version   # should show original git version
git-ai config      # should show org config
```

---

## CI Workflows (Squash/Rebase Merge Attribution)

GitHub/GitLab/Bitbucket web UIs perform squash and rebase merges server-side where git-ai isn't running. CI scripts reconstruct authorship after these merges.

> Git AI has a Cloud + Self-Hosted SCM App under development that will do this automatically. For now, use CI scripts.

### GitHub Actions

```bash
git-ai ci github install    # creates .github/workflows/git-ai.yaml
```

Generated workflow:

```yaml
name: Git AI
on:
  pull_request:
    types: [closed]
jobs:
  git-ai:
    if: github.event.pull_request.merged == true
    runs-on: ubuntu-latest
    permissions:
      contents: write
    steps:
      - name: Install git-ai
        run: |
          curl -fsSL https://usegitai.com/install.sh | bash
          echo "$HOME/.git-ai/bin" >> $GITHUB_PATH
      - name: Run git-ai
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: |
          git config --global user.name "github-actions[bot]"
          git config --global user.email "github-actions[bot]@users.noreply.github.com"
          git-ai ci github run
```

### GitLab CI

```bash
git-ai ci gitlab install    # prints YAML snippet to add to .gitlab-ci.yml
```

The default `CI_JOB_TOKEN` often lacks API query permissions. Create a dedicated access token:

1. **Settings > Access tokens > Add new token** — Name: `git-ai`, Role: Maintainer, Scopes: `api`, `write_repository`
2. **Settings > CI/CD > Variables > Add variable** — Key: `GITLAB_TOKEN`, Value: paste token, check Masked

```yaml
git-ai:
  stage: build
  rules:
    - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH && $CI_PIPELINE_SOURCE == "push"
      when: always
  script:
    - curl -fsSL https://usegitai.com/install.sh | bash
    - export PATH="$HOME/.git-ai/bin:$PATH"
    - git config --global user.name "gitlab-ci[bot]"
    - git config --global user.email "gitlab-ci[bot]@users.noreply.gitlab.com"
    - git-ai ci gitlab run
```

### BitBucket Pipelines / Azure Repos

Not currently supported. PRs welcome on the Git AI GitHub repo.

---

## Pilot Dashboard Review

After the pilot group has committed for 1–2 weeks, review metrics (Teams dashboards populate automatically; free tier uses CLI stats).

### AI Usage — what to check

| Metric | What to check |
|--------|---------------|
| % AI-assisted PRs | Does this match how often the team uses agents? |
| % AI code | Is this consistent with what developers self-report? |
| Merged AI code (week) | Is the trend increasing as adoption grows? |

Teams using agents heavily typically see 40–70% AI-authored code.

### Contributor Metrics

Per-developer breakdowns reveal adoption patterns. Look for outliers — developers who are not showing AI usage despite using agents may have a configuration issue.

---

## Phase 4: Verify & Monitor

### 4.1 Check a developer's setup

```bash
git-ai config                    # verify config
git-ai status                    # check if checkpoints are recording
git log --show-notes=ai -5       # see recent authorship notes
```

### 4.2 View AI stats for a repo

```bash
# Stats for last 50 commits
git-ai stats HEAD~50..HEAD

# Full repo history
git-ai stats 4b825dc642cb6eb9a060e54bf8d69288fbee4904..HEAD

# JSON for programmatic analysis
git-ai stats HEAD~50..HEAD --json
```

### 4.3 AI blame a file

```bash
git-ai blame src/main.ts
```

### 4.4 Common issues

| Issue | Solution |
|-------|----------|
| `which git` doesn't show `.git-ai/bin` | PATH not updated; restart shell or check shell config |
| No AI attributions on commit | Run `git-ai install-hooks` then restart agent |
| Notes not syncing | Verify remote supports notes; check `git ls-remote origin refs/notes/ai` |
| Agent not calling checkpoint | Check agent hooks: Cursor uses `~/.cursor/hooks.json` |

---

## Free vs Paid Comparison

| Feature | Free (OSS) | Teams | Enterprise |
|---------|-----------|-------|------------|
| AI Blame | Yes | Yes | Yes |
| AI Stats per commit | Yes | Yes | Yes |
| Local prompt storage | Yes | Yes | Yes |
| Git notes attribution | Yes | Yes | Yes |
| Personal dashboard | Yes | Yes | Yes |
| Prompt storage in notes | Yes | Yes | Yes |
| /ask skill (cross-agent) | Yes | Yes | Yes |
| Team prompt store | No | Yes | Yes |
| PR-level metrics | No | Yes | Yes |
| Team dashboards | No | Yes | Yes |
| AI durability / rework | No | Yes | Yes |
| Cost tracking | No | Yes | Yes |
| Code durability evals | No | Yes | Yes |
| Data warehouse export | No | No | Yes |
| Self-hosted | N/A | No | Yes |
| Web UI squash/rebase fix | CI scripts (OSS) | Automatic | Automatic |

**Bottom line**: The free tier provides full commit-level AI attribution, blame, stats, note syncing, personal dashboard, and the /ask skill. The paid tiers add PR-level analytics, team dashboards, cloud prompt storage, and code durability tracking.

---

## Using /ask Skill for Team Context

Even on the free tier with `prompt_storage: "notes"`, the `/ask` skill can surface intent behind AI code:

```
/ask Why didn't we use the SDK here?
```

Add to your project's `AGENTS.md`:

```
- In plan mode, always use the /ask skill to read the code and the original prompts that generated it.
```

---

## Platform Requirements

| Platform | Minimum Version |
|----------|----------------|
| macOS | 14.0+ |
| Ubuntu / Linux | 18+ |
| Windows | 10+ |
| Git | 2.23+ |