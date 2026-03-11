#!/bin/bash
set -e

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null)
if [ -z "$REPO_ROOT" ]; then
    echo "Error: Not inside a git repository."
    exit 1
fi

GIT_DIR=$(git rev-parse --git-dir 2>/dev/null)
HOOKS_DIR="$GIT_DIR/hooks"
SCRIPTS_DIR="$REPO_ROOT/scripts"

mkdir -p "$HOOKS_DIR"

cat > "$HOOKS_DIR/pre-commit" <<HOOK
#!/bin/bash
bash "$SCRIPTS_DIR/pre_commit.sh"
HOOK
chmod +x "$HOOKS_DIR/pre-commit"

cat > "$HOOKS_DIR/post-commit" <<HOOK
#!/bin/bash
bash "$SCRIPTS_DIR/post_commit.sh"
HOOK
chmod +x "$HOOKS_DIR/post-commit"

mkdir -p "$GIT_DIR/ai_buffer"

echo ""
echo "AI Code Tracker - Setup Complete"
echo "================================"
echo ""
echo "Installed hooks:"
echo "  pre-commit  -> scripts/pre_commit.sh"
echo "  post-commit -> scripts/post_commit.sh"
echo ""
echo "Copilot agentStop hook:"
echo "  .github/hooks/capture_ai.json -> scripts/log_ai_output.sh"
echo ""
echo "To auto-push notes to remote, set:"
echo "  export AI_TRACKER_PUSH_NOTES=true"
