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

## Squash/Rebase Merge — Why Notes Break and How to Fix

### The problem

Git notes are linked to a commit by its SHA. When GitHub performs a squash or rebase merge via the web UI, it creates **new commits with new SHAs**. The original commits (and their notes) are no longer reachable from the target branch.

```
PR branch:   A ← B ← C     (each has a git-ai note)
                  ↓ squash merge on GitHub
main:        ...← S          (new SHA, no note)
```

Result: all AI authorship data for that PR is lost. The code looks 100% human-written.

### When does this happen?

| Merge strategy | Notes survive? |
|----------------|---------------|
| **Create a merge commit** | Yes — original commits stay in history |
| **Squash and merge** | No — single new commit replaces all |
| **Rebase and merge** | No — new commits with new SHAs |

The merge strategy is chosen per-PR via the dropdown next to the merge button. It can be restricted per-repo in **Settings > General > Pull Requests**.

### The fix: CI reconstructs notes after merge

`git-ai squash-authorship` reads the notes from the original commits, merges them, and attaches the combined note to the new commit:

```
Before:  S → (no note)
After:   S → note: {ai_additions: 65, human_additions: 10, tool: "cursor/claude-4.5-opus"...}
```

CI runs automatically on every merged PR — no manual intervention needed.

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

## Windows Performance & Troubleshooting

Windows environments require extra attention during rollout. These are common issues and their fixes.

### Windows Defender / Antivirus Exclusions

Real-time scanning adds latency to every `git-ai` invocation. Exclude the binary and data directories:

```powershell
# Run as Administrator
Add-MpPreference -ExclusionPath "$env:USERPROFILE\.git-ai"
Add-MpPreference -ExclusionProcess "$env:USERPROFILE\.git-ai\bin\git-ai.exe"
Add-MpPreference -ExclusionProcess "$env:USERPROFILE\.git-ai\bin\git.exe"
```

For enterprise MDM (Intune / GPO), deploy these exclusions via policy before rolling out git-ai.

### PATH Resolution

`~/.git-ai/bin` must appear **before** Git for Windows in PATH. Verify:

```powershell
(Get-Command git).Source   # should show ~\.git-ai\bin\git.exe
```

If it shows `C:\Program Files\Git\cmd\git.exe`, the PATH order is wrong. Fix:

```powershell
$gitAiBin = "$env:USERPROFILE\.git-ai\bin"
$currentPath = [Environment]::GetEnvironmentVariable("PATH", "User")
# Remove existing entry, then prepend
$cleaned = ($currentPath -split ';' | Where-Object { $_ -notlike '*\.git-ai\bin*' }) -join ';'
[Environment]::SetEnvironmentVariable("PATH", "$gitAiBin;$cleaned", "User")
```

Restart the terminal after PATH changes.

### BeyondTrust / Restricted Admin Environments

When Machine-level PATH updates are blocked (e.g., BeyondTrust, CyberArk):

- Use **User-level PATH only** (Option B from Distribution) — this does not require admin
- If User PATH is also locked, request IT to add `%USERPROFILE%\.git-ai\bin` to Machine PATH via GPO
- The installer detects this and prints manual instructions when Machine PATH update fails

### Git Bash Integration

Git Bash uses its own PATH from `~/.bashrc`, separate from PowerShell/CMD. The installer configures this automatically, but verify:

```bash
# In Git Bash
which git          # should show ~/.git-ai/bin/git
git-ai --version   # should show version
```

If not working, add manually to `~/.bashrc`:

```bash
export PATH="$HOME/.git-ai/bin:$PATH"
```

### Common Windows Issues

| Issue | Solution |
|-------|----------|
| `git-ai` slow on first run after reboot | Windows Defender scanning — add exclusions above |
| PATH correct in PowerShell but not CMD | Restart CMD or log out/in to pick up User PATH changes |
| PATH correct in CMD but not Git Bash | Add to `~/.bashrc` manually |
| `git-og` not found | `git-og.cmd` shim missing — reinstall or create manually |
| Symlink creation fails (Option C) | Enable Developer Mode or run as Administrator |
| `EPERM` or access denied on `.git-ai` | Antivirus quarantine — add exclusion and restore files |

---

## Free vs Paid Comparison

### What we have (free tier + our CI)

| Feature | Free CLI | Our DIY (CI/GitHub Pages) | Teams (paid) | Enterprise (paid) |
|---------|----------|--------------------------|--------------|-------------------|
| AI Blame | ✅ | — | ✅ | ✅ |
| AI Stats per commit | ✅ | — | ✅ | ✅ |
| Git notes attribution | ✅ | — | ✅ | ✅ |
| /ask skill (cross-agent) | ✅ | — | ✅ | ✅ |
| Personal dashboard (CLI) | ✅ | — | ✅ | ✅ |
| Prompt storage in notes | ✅ | — | ✅ | ✅ |
| Web dashboard | ❌ | ✅ `ai-dashboard.yml` | ✅ | ✅ |
| PR AI comment | ❌ | ✅ `pr-ai-comment.yml` | ✅ | ✅ |
| Squash/rebase note fix | ❌ | ✅ CI workflow per repo | ✅ auto (SCM app) | ✅ auto (SCM app) |
| Per-developer breakdown | ❌ | Buildable (stats + author filter) | ✅ | ✅ |
| AI-Code Halflife | ❌ | Buildable (blame snapshots over time) | ✅ | ✅ |
| Prompt traces in dashboard | ❌ | Buildable (show-prompt + UI) | ✅ | ✅ |
| Token usage / cost tracking | ❌ | **Not possible** — data not in notes | ✅ | ✅ |
| SDLC tracking (commit → prod) | ❌ | **Not possible** — needs APM integration | ✅ | ✅ |
| Code durability evals (A/B) | ❌ | **Not possible** — needs statistical pipeline | ✅ | ✅ |
| Data warehouse export | ❌ | ❌ | ❌ | ✅ |
| Self-hosted deployment | — | — | ❌ | ✅ |

### What we cannot build

| Feature | Why |
|---------|-----|
| **Token usage / cost** | The CLI does not capture token counts or API costs. This data comes from LLM provider billing, which the paid platform intercepts. |
| **SDLC-wide tracking** | Tracking AI code from commit through review, deploy, to production incidents requires integration with APM, CI/CD, and incident management systems. |
| **Code durability evals** | A/B testing the impact of new MCPs, skills, or agent configs on code longevity requires a statistical pipeline across many repos and time periods. |

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