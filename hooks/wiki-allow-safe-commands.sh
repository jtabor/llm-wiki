#!/usr/bin/env bash
# Auto-approve a short allowlist of safe, read-only Bash commands so they
# never trigger a permission prompt.  Add more cases as needed.
#
# Receives a JSON object on stdin; outputs {"decision":"approve"} to
# short-circuit the normal permission check, or exits 0 silently to defer.

WIKI_ROOT="${WIKI_ROOT:-$HOME/notes/wiki}"

INPUT=$(cat)
TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // ""')

case "$TOOL" in
    Bash)
        CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""')
        case "$CMD" in
            "echo $WIKI_ROOT")
                printf '{"decision":"approve"}\n'
                ;;
        esac
        ;;
    Read|Edit|Write)
        FILE=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // ""')
        ABS=$(realpath -m "$FILE" 2>/dev/null)
        if [[ "$ABS" == "$WIKI_ROOT"/* ]]; then
            printf '{"decision":"approve"}\n'
        fi
        ;;
esac
