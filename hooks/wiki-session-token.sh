#!/usr/bin/env bash
# Injects the Claude Code session UUID as a wiki token, once per session.

SESSION_ID=$(jq -r '.session_id // "unknown"')
TOKEN_FILE="$HOME/.claude/wiki-tokens/${SESSION_ID}"

if [ -f "$TOKEN_FILE" ]; then
    exit 0
fi

touch "$TOKEN_FILE"
printf '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"Wiki session token for this session: cc-%s. Use it in wiki refs and commit trailers this session."}}\n' "$SESSION_ID"
