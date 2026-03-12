# Git AI — Agent Integrations

Per-agent setup details for integrating Git AI with coding agents.

## Cursor

**Support**: Agent mode, Tab completion (beta), Cursor CLI, Prompt saving

Cursor has native hook support. Git AI installs hooks at `~/.cursor/hooks.json`:

```json
{
  "hooks": {
    "afterFileEdit": [
      {
        "command": "<path-to-git-ai> checkpoint cursor --hook-input stdin"
      }
    ],
    "beforeSubmitPrompt": [
      {
        "command": "echo 'them'"
      },
      {
        "command": "<path-to-git-ai> checkpoint cursor --hook-input stdin"
      }
    ]
  },
  "version": 1
}
```

**Install**: `git-ai install-hooks` (automatic)

**Troubleshooting**:
- Verify: `which git` should show `~/.git-ai/bin/git`
- Check hooks: `CTRL+SHIFT+P` → "Output: Show Output Channels" → "Hooks"
- If no attributions: `git-ai install-hooks` then restart Cursor
- If using a Git GUI client (Sublime Merge, Sourcetree): set its git binary to `~/.git-ai/bin/git`

## Claude Code

**Support**: Fully supported (PreToolUse + PostToolUse hooks)

Git AI installs hooks in `~/.claude/settings.json`:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "hooks": [
          {
            "command": "git-ai checkpoint 2>/dev/null || true",
            "type": "command"
          }
        ],
        "matcher": "Write|Edit|MultiEdit"
      }
    ],
    "PostToolUse": [
      {
        "hooks": [
          {
            "command": "git-ai checkpoint claude --hook-input \"$(cat)\" 2>/dev/null || true",
            "type": "command"
          }
        ],
        "matcher": "Write|Edit|MultiEdit"
      }
    ]
  }
}
```

**Install**: `git-ai install-hooks` (automatic)

## GitHub Copilot

**Support**: VS Code only (JetBrains not supported)

**Install**: `git-ai install-hooks` (automatic)

## Codex (OpenAI)

**Support**: Fully supported

**Install**: `git-ai install-hooks` (automatic)

## Gemini CLI

**Support**: CLI

**Install**: `git-ai install-hooks` (automatic)

## Windsurf

**Support**: All features except model name tracking

**Install**: `git-ai install-hooks` (automatic)

## Other Agents

Amp, Droid, Junie, Rovo Dev, OpenCode, Continue — all supported via `git-ai install-hooks`.

---

## VS Code Extension (AI Blame gutter)

Works in VS Code, Cursor, Windsurf, Antigravity.

**Install** (usually automatic with git-ai install):
- Official: https://marketplace.visualstudio.com/items?itemName=git-ai.git-ai-vscode
- Open VSX (Cursor): https://open-vsx.org/extension/git-ai/git-ai-vscode

**Blame Modes** (change in Extension Settings or Status Bar):
| Mode | Behavior |
|------|----------|
| `All` | Show AI decorations for all AI-authored lines |
| `Line` | Show for current line and same session lines (default) |
| `Off` | No decorations |

**Editor Support**:
| Editor | Status |
|--------|--------|
| VS Code | Supported |
| Cursor | Supported |
| Windsurf | Supported |
| Antigravity | Supported |
| Emacs (magit) | Supported (https://github.com/jwiegley/magit-ai) |
| JetBrains | Not yet |
| Neovim | Not yet |

---

## Adding a Custom Agent

If your organization uses a custom or internal agent, integrate via the `agent-v1` preset:

### Pre-edit checkpoint (marks human changes)

```bash
echo '{
  "type": "human",
  "repo_working_dir": "<git-project-dir>",
  "will_edit_filepaths": ["<file1>"]
}' | git-ai checkpoint agent-v1 --hook-input stdin
```

### Post-edit checkpoint (marks AI changes)

```bash
echo '{
  "type": "ai_agent",
  "repo_working_dir": "<git-project-dir>",
  "transcript": {
    "messages": [
      { "type": "user", "text": "Add error handling", "timestamp": "2024-01-15T10:30:00Z" },
      { "type": "assistant", "text": "Adding Result types", "timestamp": "2024-01-15T10:30:15Z" }
    ]
  },
  "agent_name": "your-agent",
  "edited_filepaths": ["<file1>"],
  "model": "model-name",
  "conversation_id": "conv_12345"
}' | git-ai checkpoint agent-v1 --hook-input stdin
```

### Testing with mock_ai

```bash
# Write code manually, then mark as AI
git-ai checkpoint mock_ai

# Edit a line (marked as human)
git-ai checkpoint

# Commit
git commit -a -m "test"

# Verify
git-ai blame <file>
```

---

## Verification After Setup

For any agent, verify the integration:

```bash
# 1. Generate code with your agent
# 2. Check checkpoints are recording
git-ai status

# 3. Commit
git commit -a -m "test AI tracking"

# 4. Check authorship note
git log --show-notes=ai -1

# 5. Blame
git-ai blame <file>
```