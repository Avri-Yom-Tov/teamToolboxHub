#!/bin/bash
GIT_DIR=$(git rev-parse --git-dir 2>/dev/null)
[ -z "$GIT_DIR" ] && exit 0

BUFFER_DIR="$GIT_DIR/ai_buffer"
METADATA_FILE="$BUFFER_DIR/metadata.json"

if [ ! -f "$METADATA_FILE" ]; then
    echo "[AI Tracker] No AI metadata found for this commit."
    exit 0
fi

METADATA=$(cat "$METADATA_FILE")
COMMIT_SHA=$(git rev-parse HEAD)

if git notes --ref=ai_stats add -f -m "$METADATA" "$COMMIT_SHA" 2>/dev/null; then
    echo "[AI Tracker] Attached AI stats to commit ${COMMIT_SHA:0:7}"
else
    echo "[AI Tracker] Warning: Failed to attach note to ${COMMIT_SHA:0:7}"
fi

rm -f "$BUFFER_DIR/last_proposal.txt"
rm -f "$METADATA_FILE"

if [ "$AI_TRACKER_PUSH_NOTES" = "true" ]; then
    if git push origin refs/notes/ai_stats 2>/dev/null; then
        echo "[AI Tracker] Notes pushed to remote."
    fi
fi
