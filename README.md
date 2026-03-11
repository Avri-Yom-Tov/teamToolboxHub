# AI Code Tracker

Track AI-generated vs human-written code in every commit.

## How It Works

```
Copilot Agent stops → captures AI proposal → dev commits → compares diff → attaches stats as Git Note
```

| Step | Hook | What happens |
|------|------|-------------|
| 1 | `agentStop` (Copilot) | Saves the AI's raw code proposal to `.git/ai_buffer/` |
| 2 | `pre-commit` (Git) | Compares staged lines against the AI proposal, counts AI vs human lines |
| 3 | `post-commit` (Git) | Attaches the stats as a Git Note on the commit |
| 4 | GitHub Action | Collects all notes on merge to master and exports a report |

## Setup

```powershell
# Windows
powershell -File scripts\setup_hooks.ps1
```

```bash
# Linux / Mac
bash scripts/setup_hooks.sh
```

## Project Structure

```
.github/
  hooks/capture_ai.json        # Copilot agentStop hook config
  workflows/collect_ai_metrics.yml  # GitHub Action for merge-time collection
scripts/
  log_ai_output.ps1 / .sh      # Step 1 - capture AI output
  pre_commit.ps1 / .sh         # Step 2 - diff comparison
  post_commit.ps1 / .sh        # Step 3 - attach Git Note
  setup_hooks.ps1 / .sh        # One-time local setup
```

## View Stats

```bash
# Show AI stats for last 5 commits
git log -5 --show-notes=ai_stats

# Push notes to remote
git push origin refs/notes/ai_stats
```

## Auto-Push Notes

```powershell
$env:AI_TRACKER_PUSH_NOTES = "true"   # Windows
export AI_TRACKER_PUSH_NOTES=true      # Bash
```
