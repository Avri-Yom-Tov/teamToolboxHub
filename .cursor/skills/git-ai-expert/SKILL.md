---
name: git-ai-expert
description: >
  Complete knowledge base for Git AI — the open-source git extension tracking AI-generated code
  via git notes. Use whenever the user mentions Git AI, git-ai, AI code tracking, AI blame,
  AI authorship, or needs help installing/configuring git-ai, troubleshooting issues, planning
  organizational rollout, MDM deployment, enterprise config, CI workflows, SCM integration,
  prompt storage, data warehouse export, or integrating custom coding agents. Also trigger when
  asking about tracking AI vs human code, AI code metrics, or comparing agent usage across teams —
  even without explicitly saying "Git AI". Also trigger for searching AI prompt history,
  continuing AI sessions, restoring conversation context from git history, or using git-ai search
  and git-ai continue commands.
---

# Git AI Expert

You are an expert on **Git AI** — an open-source git extension that tracks AI-generated code in
repositories by linking every AI-written line to the agent, model, and prompts that generated it.

Git AI is **not** a code detector. It integrates directly with coding agents (Cursor, Claude Code,
GitHub Copilot, Gemini CLI, Codex, OpenCode, Continue, and more) which explicitly mark the code
they write. This is a fundamental design choice — no heuristics, no guessing.

**Key facts:**
- Open source: https://github.com/git-ai-project/git-ai
- Written in Rust — minimal overhead (10-20ms per git command)
- Uses Git Notes (refs/notes/ai) to store authorship data
- Install per-machine, not per-repo. Works offline, no API keys needed
- No background daemons, keyloggers, or filewatchers
- Preserves attribution through rebase, cherry-pick, merge, squash, amend, stash
- Open standard: https://github.com/git-ai-project/git-ai/blob/main/specs/git_ai_standard_v3.0.0.md
- Docs site: https://usegitai.com/docs (CLI, Teams, Guides sections)

## Three tiers

| Tier | What it is | Cost |
|------|-----------|------|
| **CLI (Open Source)** | Git extension installed on developer machines. Tracks AI authorship at commit level via git notes. Includes blame, diff, stats, status commands. All data stays in git. | Free |
| **Teams (Platform)** | Cloud pipeline + dashboards. Joins CLI data with PR metrics, token usage, cost, prompt traces, APM incidents. Tracks AI code through entire SDLC. | Paid |
| **Enterprise** | Self-hosted or cloud. Adds data warehouse export, self-hosted deployment, and automatic web UI squash/rebase fix. | Paid |

**The user's organization wants to use the free CLI tier only**, with all data stored in their own GitHub repositories via git notes.

## When to read reference files

This skill uses progressive disclosure. Read the appropriate reference file based on what the user needs:

### `references/cli-reference.md`
Read when the user needs help with:
- Full CLI command reference (blame, diff, stats, status, show, show-prompt, config, checkpoint)
- Configuration options (config.json keys, prompt storage modes, repository patterns)
- Config options: `ignore_prompts`, `include_prompts_in_repositories`, `default_prompt_storage`, `feature_flags`
- `git-ai ci github install` / `git-ai ci gitlab install` commands
- Git note format and schema details
- History rewriting support table (which operations preserve attribution)
- Performance characteristics, timing breakdown, git notes sync benchmarks, and debugging
- Plumbing commands (checkpoint, squash-authorship, git-path)
- `.git-ai-ignore` file format
- The `/ask` skill for querying AI intent behind code
- **Personal Dashboard** — what CLI-based stats look like, `git-ai status` output, `git-ai stats` metrics
- **Teams/Enterprise Dashboard** — what the paid web dashboard offers (PR metrics, durability, cost tracking)
- Commit stats JSON fields and their meanings (ai_accepted, mixed_additions, tool_model_breakdown, etc.)
- Uninstalling git-ai

### `references/org-rollout.md`
Read when the user needs help with:
- Planning a phased rollout (pilot → org config → distribution → monitoring)
- Pilot evaluation guide (10–20 engineers, 1–3 repos, 2–4 weeks)
- Organization-wide config.json (prompt_storage, allow/exclude repos, telemetry)
- MDM / endpoint management deployment — Option B (user-scoped) or Option C (overwrite existing git symlink)
- PATH configuration across developer fleet
- CI workflows for squash/rebase merge attribution: GitHub Actions, GitLab CI, BitBucket/Azure status
- Pilot dashboard review: AI usage metrics, contributor metrics, expected adoption percentages
- Free vs paid tier feature comparison table
- The `/ask` skill and AGENTS.md integration
- Excluding sensitive repos or prompts from tracking
- `.git-ai-ignore` per-repo setup
- Windows performance: Defender exclusions, PATH resolution, BeyondTrust/restricted admin, Git Bash integration
- Windows-specific troubleshooting during rollout

### `references/agent-integrations.md`
Read when the user needs help with:
- Setting up specific agent integrations (Cursor, Claude Code, Copilot, Codex, Gemini CLI, Windsurf, OpenCode, Continue, Droid, Junie, Rovo Dev, Amp)
- How hooks work for each agent (exact JSON config shown)
- Troubleshooting agent-specific issues
- Adding support for a custom/internal coding agent (agent-v1 preset)
- The checkpoint API for custom integrations
- VS Code extension for AI Blame gutter decorations (install, blame modes, supported editors)
- Testing integrations with mock_ai

### `references/search-continue.md`
Read when the user needs help with:
- Searching AI prompt sessions by commit, file, pattern, or author (`git-ai search`)
- Continuing someone else's AI session (`git-ai continue`)
- Viewing prompt transcripts (`git-ai show-prompt`)
- PR review workflows with AI context
- Auditing AI involvement in files
- Output formats (default, --json, --verbose, --porcelain, --count)
- Piping git-ai search output to other tools and CI/CD integration

## Quick install reference

```bash
# Mac, Linux, Windows (WSL)
curl -sSL https://usegitai.com/install.sh | bash

# Windows (non-WSL)
powershell -NoProfile -ExecutionPolicy Bypass -Command "irm http://usegitai.com/install.ps1 | iex"
```

🎊 That's it! **No per-repo setup.** The install script automatically:
1. Downloads the correct binary for the platform
2. Creates symlinks/shims so `git` calls route through git-ai
3. Runs `git-ai install-hooks` to set up IDE/agent hooks (Cursor hooks.json, Claude Code settings.json, etc.)
4. Configures PATH so git-ai takes precedence over standard git
5. On Windows: also configures Git Bash shell profiles if Git Bash is detected

**`git-ai install-hooks` runs automatically during installation.** Users only need to run it manually if:
- The automatic setup failed (installer prints a warning in that case)
- They want to re-configure hooks after updating agents or IDEs
- They installed a new coding agent after git-ai was already installed

The install script also installs the **VS Code / Cursor extension** automatically. The extension provides:
- **AI Blame gutter decorations** in the editor (modes: All, Line, Off)
- **Experimental AI tab tracking** (`gitai.experiments.aiTabTracking`) for tracking tab-completion insertions
- **Debug logging** (`gitai.enableCheckpointLogging`) to see checkpoint toast messages
- Works in VS Code, Cursor, Windsurf, and Antigravity
- If auto-install didn't work, install manually from VS Code Marketplace or Open VSX by searching "git-ai"
- The extension is NOT required for core agent tracking (Cursor agent mode, Claude Code, etc.) — that works via CLI hooks alone
- The extension IS needed for tab-completion tracking (experimental) and in-editor AI blame visualization

On **Windows (non-WSL)** specifically, the install script also:
- Creates a `git-og.cmd` shim to access the original git binary directly
- Attempts to update both User and Machine PATH (Machine requires admin/elevated PowerShell)
- If Machine PATH update fails (e.g. BeyondTrust restrictions), prints instructions for manual PATH editing
- Configures Git Bash `.bashrc` if Git Bash is detected

**Uninstalling git-ai:**
```bash
git-ai uninstall-hooks          # Remove agent hooks
rm -rf ~/.git-ai                # Remove binary (Linux/macOS)
# Windows: rmdir /s /q %USERPROFILE%\.git-ai
# Optionally remove PATH entry from shell config
```

Verify installation:
```bash
which git          # Should show ~/.git-ai/bin/git
git-ai status      # Should show checkpoint history
git-ai blame <file> # See AI attribution per line
```

## Core CLI commands cheat sheet

| Command | Purpose |
|---------|---------|
| `git-ai blame <file>` | Show AI authorship per line (drop-in replacement for git blame) |
| `git-ai diff <commit>` | Unified diff with AI/human annotations per line |
| `git-ai stats [commit\|range]` | AI vs human code statistics for a commit or range |
| `git-ai status` | Live view of current working changes with AI/human breakdown |
| `git-ai show <commit>` | Display raw authorship log for a commit |
| `git-ai show-prompt <id>` | Show prompt record by ID |
| `git-ai search [options]` | Search AI prompt sessions by commit, file, pattern, or author |
| `git-ai continue [options]` | Restore AI session context for continuation |
| `git-ai config` | View/set configuration |
| `git-ai install-hooks` | Configure agent hooks (runs automatically during install) |
| `git-ai uninstall-hooks` | Remove agent hooks (for uninstalling git-ai) |
| `git-ai git-hooks ensure` | (Beta) Install/heal repo-local git-ai hooks for current repo |
| `git-ai git-hooks remove` | (Beta) Remove repo-local git-ai hooks for current repo |
| `git-ai checkpoint` | Mark code changes (used by agents, not typically by users) |

## How it works (summary)

1. **Agents call `git-ai checkpoint`** before and after editing files — marking which lines they wrote
2. **On commit**, checkpoints are condensed into an Authorship Log attached as a git note
3. **Attribution survives** rebase, merge, cherry-pick, squash, amend, stash, reset
4. **Notes sync** automatically on push/fetch to remote repositories
5. **`git-ai blame`** overlays AI attribution on top of standard git blame

## Supported agents

| Agent | Authorship | Prompts | Notes |
|-------|-----------|---------|-------|
| Cursor (>1.7) | ✅ | ✅ | Agent mode, CLI. Tab completions beta. |
| Claude Code | ✅ | ✅ | Fully supported |
| GitHub Copilot | ✅ | ✅ | VS Code only (JetBrains ✗) |
| Gemini CLI | ✅ | ✅ | CLI |
| Continue | ✅ | ✅ | CLI only; VS Code/IntelliJ in-progress |
| OpenCode | ✅ | ✅ | Fully supported |
| Atlassian Rovo Dev | ✅ | ✅ | CLI |
| Droid | ✅ | ✅ | Supported |
| Windsurf | 🔄 | 🔄 | In-progress |
| Augment Code | 🔄 | 🔄 | In-progress |
| AWS Kiro | 🔄 | 🔄 | In-progress |
| Codex (OpenAI) | ✅ | ✅ | Fully supported (has own docs page) |
| Junie & JetBrains IDEs | — | — | Planned |
| Amp (Sourcegraph) | ✅ | ✅ | Supported |
| Ona | — | — | Planned |
| Google Antigravity | — | — | Planned |

## System requirements

- macOS 14.0+, Ubuntu 18+, Windows 10+
- Git 2.23+

## Licensing

Git AI is licensed under **Apache 2.0** — full commercial and organizational use is permitted.
No per-user fees, no usage limits, no obligation to share code back.

## Organization implementation plan

The organization uses **only the free open-source CLI**. All data stays in-house.

**Architecture:**
- git-ai CLI installed on developer machines via MDM
- AI authorship data stored as git notes in the organization's GitHub repos
- GitHub Actions workflow (`pr-ai-comment.yml`) runs on every PR, posts AI stats as a PR comment
- PR comments include a hidden `AGENT_EXPERIENCE_RECORD` JSON block
- Power BI connects to GitHub API, pulls PR comment data, and builds org-wide dashboards
- No external services, no paid tiers, no third-party data sharing

**PR comment provides (per PR):**
- AI vs Human code %, lines added, acceptance rate
- Agent/model breakdown, AI wait time, wasted LOC
- Structured JSON matching the AgentExperienceRecord schema

**Fields Power BI enriches from other sources:**
- SP (Story Points) — from Jira
- cost — from token usage tracking
- successful_tests — from CI pipeline
- human_feedback / quality_score — manual input

**AI Code Durability** (how long AI code survives) can be built in-house using
`git-ai blame` comparisons over time — the raw data is in git notes.