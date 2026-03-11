# AI Code Tracker

Track AI-generated vs human-written code in every commit.

## How It Works

```
Copilot Agent stops → captures AI proposal → dev commits → compares diff → attaches stats as Git Note
```

| Step | Hook | What happens |
|------|------|-------------|
| 1 | `agentStop` (Copilot) | Saves the AI's raw code proposal to `.git/ai_buffer/proposals/` (accumulates all proposals between commits) |
| 2 | `pre-commit` (Git) | Compares staged lines against all accumulated AI proposals using normalized + fuzzy matching |
| 3 | `post-commit` (Git) | Attaches the stats as a Git Note on the commit and cleans up the proposals directory |
| 4 | GitHub Action | Collects all notes on merge to master and exports a report |

## Matching Algorithm

The pre-commit comparison uses a three-tier approach:

| Tier | Method | Result |
|------|--------|--------|
| 1 | **Normalized exact match** -- trim whitespace, collapse spaces, then compare | `ai_lines` |
| 2 | **Token similarity (Jaccard ≥ 0.7)** -- split into tokens, calculate overlap ratio | `ai_modified_lines` |
| 3 | **No match** | `human_lines` |

Trivial lines (`{`, `}`, `return`, short boilerplate) are excluded from all counts and tracked separately as `trivial_lines`.

### Output Example

```json
{
  "ai_lines": 45,
  "ai_modified_lines": 12,
  "human_lines": 8,
  "trivial_lines": 15,
  "total_added": 80,
  "ai_percentage": 71.3,
  "files_changed": ["src/app.js"],
  "proposals_count": 3
}
```

`ai_percentage` = `(ai_lines + ai_modified_lines) / (ai_lines + ai_modified_lines + human_lines) × 100`

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
  log_ai_output.ps1 / .sh      # Step 1 - capture & accumulate AI output
  pre_commit.ps1 / .sh         # Step 2 - normalized + fuzzy diff comparison
  post_commit.ps1 / .sh        # Step 3 - attach Git Note + cleanup proposals
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
