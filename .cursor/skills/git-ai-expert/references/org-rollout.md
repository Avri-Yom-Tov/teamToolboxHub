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

1. Open Cursor (or any supported agent), generate some code
2. Run `git-ai status` to see AI vs human attribution
3. Commit: `git commit -a -m "test AI tracking"`
4. Check note: `git log --show-notes=ai`
5. Push and verify notes sync: `git push`
6. On another machine: `git fetch` then `git-ai blame <file>`

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

### Option B: MDM / Endpoint Management (large teams)

For enterprise-scale rollout without manual steps:

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

#### Verify installation (all platforms)

```bash
which git          # should show .git-ai/bin/git
git-ai --version   # should show version
git-og --version   # should show original git version
git-ai config      # should show org config
```

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