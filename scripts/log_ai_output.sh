#!/bin/bash
INPUT=$(cat)
[ -z "$INPUT" ] && exit 0

AI_CODE=$(echo "$INPUT" | jq -r '.last_assistant_message // empty')
[ -z "$AI_CODE" ] && exit 0

GIT_DIR=$(git rev-parse --git-dir 2>/dev/null)
[ -z "$GIT_DIR" ] && exit 0

BUFFER_DIR="$GIT_DIR/ai_buffer"
mkdir -p "$BUFFER_DIR"

echo "$AI_CODE" > "$BUFFER_DIR/last_proposal.txt"

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
LINE_COUNT=$(echo "$AI_CODE" | wc -l)
CHAR_COUNT=$(echo "$AI_CODE" | wc -c)

echo "{\"timestamp\":\"$TIMESTAMP\",\"proposal_length\":$CHAR_COUNT,\"proposal_lines\":$LINE_COUNT}" >> "$BUFFER_DIR/proposals.log"
