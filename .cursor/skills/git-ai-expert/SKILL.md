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
- New config options: `include_prompts_in_repositories`, `default_prompt_storage`, `feature_flags`
- Git note format and schema details
- History rewriting support table (which operations preserve attribution)
- Performance characteristics and debugging
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
- Organization-wide config.json (prompt_storage, allow/exclude repos, telemetry)
- MDM / endpoint management deployment (Windows PowerShell scripts, Unix)
- PATH configuration across developer fleet
- Free vs paid tier feature comparison table
- The `/ask` skill and AGENTS.md integration
- Excluding sensitive repos or prompts from tracking
- `.git-ai-ignore` per-repo setup

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

After install, configure agent hooks:
```bash
git-ai install-hooks
```

Verify:
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
| `git-ai install-hooks` | Configure agent hooks (Cursor, Claude Code, Copilot, etc.) |
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
| OpenAI Codex | — | — | Waiting on upstream (openai/codex #2109) |
| Junie & JetBrains IDEs | — | — | Planned |
| Amp (Sourcegraph) | ✅ | ✅ | Supported |
| Ona | — | — | Planned |
| Google Antigravity | — | — | Planned |

## System requirements

- macOS 14.0+, Ubuntu 18+, Windows 10+
- Git 2.23+

## Important notes for the organization's use case

The organization wants to use **only the free open-source CLI** without the paid Teams platform.
This means:
- All AI authorship data is stored as git notes in the organization's own GitHub repos
- No external dashboard — use CLI commands (blame, stats, diff) to query data locally
- CI workflows (GitHub Actions) can handle squash/rebase merge attribution
- MDM deployment distributes the binary across developer machines
- Enterprise config.json controls repository scope, update behavior, and telemetry
- No prompt storage in the cloud — prompts stay local or in git notes only

## Dashboard / Analytics overview

**Free tier (CLI-based):**
- `git-ai status` — real-time terminal progress bar (human vs AI %), acceptance rate, wait time, and chronological checkpoint list with agent/model per change
- `git-ai stats` — aggregate AI vs human stats per commit or range, JSON output, per-tool/model breakdown
- No web UI — all data viewed via terminal commands

**Teams/Enterprise tier (paid, web UI):**
- AI authorship breakdown per PR
- AI code % tracked through entire SDLC (commit → review → production)
- Agent/model accepted-rate comparison
- AI-Code Halflife (code durability)
- Token usage and cost tracking
- Team dashboards, prompt traces, cross-team agent comparison
- Enterprise adds: self-hosted, data warehouse export, automatic squash/rebase via SCM bot