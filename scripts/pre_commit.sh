#!/bin/bash
GIT_DIR=$(git rev-parse --git-dir 2>/dev/null)
[ -z "$GIT_DIR" ] && exit 0

BUFFER_DIR="$GIT_DIR/ai_buffer"
PROPOSAL_FILE="$BUFFER_DIR/last_proposal.txt"

STAGED_DIFF=$(git diff --cached --unified=0)
[ -z "$STAGED_DIFF" ] && exit 0

ADDED_LINES=$(echo "$STAGED_DIFF" | grep '^+[^+]' | sed 's/^+//' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | grep -v '^$')
TOTAL_ADDED=$(echo "$ADDED_LINES" | grep -c .)

[ "$TOTAL_ADDED" -eq 0 ] && exit 0

AI_COUNT=0
HUMAN_COUNT=0

if [ -f "$PROPOSAL_FILE" ]; then
    while IFS= read -r line; do
        trimmed=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        [ -z "$trimmed" ] && continue
        if grep -qF "$trimmed" "$PROPOSAL_FILE"; then
            AI_COUNT=$((AI_COUNT + 1))
        else
            HUMAN_COUNT=$((HUMAN_COUNT + 1))
        fi
    done <<< "$ADDED_LINES"
else
    HUMAN_COUNT=$TOTAL_ADDED
fi

if [ "$TOTAL_ADDED" -gt 0 ]; then
    AI_PERCENTAGE=$(awk "BEGIN {printf \"%.1f\", ($AI_COUNT/$TOTAL_ADDED)*100}")
else
    AI_PERCENTAGE="0.0"
fi

CHANGED_FILES=$(git diff --cached --name-only | tr '\n' ',' | sed 's/,$//')
AUTHOR=$(git config user.name)
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

mkdir -p "$BUFFER_DIR"
cat > "$BUFFER_DIR/metadata.json" <<EOF
{"timestamp":"$TIMESTAMP","ai_lines":$AI_COUNT,"human_lines":$HUMAN_COUNT,"total_added":$TOTAL_ADDED,"ai_percentage":$AI_PERCENTAGE,"files_changed":"$CHANGED_FILES","author":"$AUTHOR"}
EOF

echo "[AI Tracker] AI: $AI_COUNT lines ($AI_PERCENTAGE%) | Human: $HUMAN_COUNT lines | Total: $TOTAL_ADDED"
exit 0
