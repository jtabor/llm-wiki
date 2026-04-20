#!/usr/bin/env bash
# On session stop, copy the JSONL and any subagent transcripts to the wiki.

INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "unknown"')
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // ""')

if [ -z "$WIKI_ROOT" ]; then
    echo "wiki-archive-session: WIKI_ROOT not set, skipping" >&2
    exit 0
fi

DEST_DIR="$WIKI_ROOT/conversations/claude-code"
mkdir -p "$DEST_DIR"

# Copy parent JSONL
if [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ]; then
    cp "$TRANSCRIPT_PATH" "$DEST_DIR/${SESSION_ID}.jsonl"
else
    echo "wiki-archive-session: transcript_path missing or not found" >&2
fi

# Copy subagent transcripts if the subdir exists
SUBAGENT_DIR="$(dirname "$TRANSCRIPT_PATH")/${SESSION_ID}"
if [ -d "$SUBAGENT_DIR" ]; then
    mkdir -p "$DEST_DIR/${SESSION_ID}"
    cp "$SUBAGENT_DIR"/*.jsonl "$DEST_DIR/${SESSION_ID}/" 2>/dev/null
fi
