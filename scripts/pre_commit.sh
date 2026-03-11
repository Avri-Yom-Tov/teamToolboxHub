#!/bin/bash
GIT_DIR=$(git rev-parse --git-dir 2>/dev/null)
[ -z "$GIT_DIR" ] && exit 0

BUFFER_DIR="$GIT_DIR/ai_buffer"
ALL_PROPOSALS="$BUFFER_DIR/all_proposals.txt"

STAGED_DIFF=$(git diff --cached --unified=0)
[ -z "$STAGED_DIFF" ] && exit 0

ADDED_LINES=$(echo "$STAGED_DIFF" | grep '^+[^+]' | sed 's/^+//' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | grep -v '^$')
TOTAL_ADDED=$(echo "$ADDED_LINES" | grep -c .)

[ "$TOTAL_ADDED" -eq 0 ] && exit 0

normalize() {
    echo "$1" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | sed 's/[[:space:]]\+/ /g'
}

tokenize() {
    echo "$1" | grep -oE '[a-zA-Z0-9_]+' | sort -u
}

jaccard() {
    local tokens_a="$1"
    local tokens_b="$2"
    [ -z "$tokens_a" ] && [ -z "$tokens_b" ] && echo "1.0" && return
    [ -z "$tokens_a" ] || [ -z "$tokens_b" ] && echo "0.0" && return
    local union=$(printf '%s\n%s' "$tokens_a" "$tokens_b" | sort -u | grep -c .)
    local intersection=$(printf '%s\n%s' "$tokens_a" "$tokens_b" | sort | uniq -d | grep -c .)
    awk "BEGIN {printf \"%.2f\", $intersection/$union}"
}

is_trivial() {
    local stripped=$(echo "$1" | tr -d '[:space:]')
    [ ${#stripped} -lt 4 ] && return 0
    echo "$stripped" | grep -qE '^[\{\}\(\)\[\];,]+$' && return 0
    echo "$stripped" | grep -qE '^(else|break|continue|return;?)$' && return 0
    return 1
}

AI_COUNT=0
AI_MODIFIED_COUNT=0
HUMAN_COUNT=0
TRIVIAL_COUNT=0
PROPOSALS_COUNT=0

if [ -f "$ALL_PROPOSALS" ]; then
    NORMALIZED_PROPOSALS=$(while IFS= read -r pline; do
        trimmed=$(echo "$pline" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        [ -z "$trimmed" ] && continue
        normalize "$trimmed"
    done < "$ALL_PROPOSALS")

    PROPOSALS_DIR="$BUFFER_DIR/proposals"
    if [ -d "$PROPOSALS_DIR" ]; then
        PROPOSALS_COUNT=$(find "$PROPOSALS_DIR" -name "*.txt" 2>/dev/null | wc -l)
    fi

    while IFS= read -r line; do
        trimmed=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        [ -z "$trimmed" ] && continue

        if is_trivial "$trimmed"; then
            TRIVIAL_COUNT=$((TRIVIAL_COUNT + 1))
            continue
        fi

        norm=$(normalize "$trimmed")
        if echo "$NORMALIZED_PROPOSALS" | grep -qxF "$norm"; then
            AI_COUNT=$((AI_COUNT + 1))
            continue
        fi

        line_tokens=$(tokenize "$norm")
        best_sim="0.00"
        while IFS= read -r ai_norm; do
            [ -z "$ai_norm" ] && continue
            ai_tokens=$(tokenize "$ai_norm")
            sim=$(jaccard "$line_tokens" "$ai_tokens")
            if awk "BEGIN {exit !($sim > $best_sim)}"; then
                best_sim="$sim"
            fi
            if awk "BEGIN {exit !($best_sim >= 0.7)}"; then
                break
            fi
        done <<< "$NORMALIZED_PROPOSALS"

        if awk "BEGIN {exit !($best_sim >= 0.7)}"; then
            AI_MODIFIED_COUNT=$((AI_MODIFIED_COUNT + 1))
        else
            HUMAN_COUNT=$((HUMAN_COUNT + 1))
        fi
    done <<< "$ADDED_LINES"
else
    while IFS= read -r line; do
        trimmed=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        [ -z "$trimmed" ] && continue
        if is_trivial "$trimmed"; then
            TRIVIAL_COUNT=$((TRIVIAL_COUNT + 1))
        else
            HUMAN_COUNT=$((HUMAN_COUNT + 1))
        fi
    done <<< "$ADDED_LINES"
fi

MEANINGFUL=$((AI_COUNT + AI_MODIFIED_COUNT + HUMAN_COUNT))
if [ "$MEANINGFUL" -gt 0 ]; then
    AI_PERCENTAGE=$(awk "BEGIN {printf \"%.1f\", (($AI_COUNT+$AI_MODIFIED_COUNT)/$MEANINGFUL)*100}")
else
    AI_PERCENTAGE="0.0"
fi

CHANGED_FILES=$(git diff --cached --name-only | jq -R . | jq -s .)
AUTHOR=$(git config user.name)
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

mkdir -p "$BUFFER_DIR"
cat > "$BUFFER_DIR/metadata.json" <<EOF
{"timestamp":"$TIMESTAMP","ai_lines":$AI_COUNT,"ai_modified_lines":$AI_MODIFIED_COUNT,"human_lines":$HUMAN_COUNT,"trivial_lines":$TRIVIAL_COUNT,"total_added":$TOTAL_ADDED,"ai_percentage":$AI_PERCENTAGE,"files_changed":$CHANGED_FILES,"proposals_count":$PROPOSALS_COUNT,"author":"$AUTHOR"}
EOF

echo "[AI Tracker] AI: $AI_COUNT | Modified: $AI_MODIFIED_COUNT | Human: $HUMAN_COUNT | Trivial: $TRIVIAL_COUNT | AI%: $AI_PERCENTAGE%"
exit 0
