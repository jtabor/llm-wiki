# CLAUDE.md — <Project Name>

## Wiki

This project's wiki lives at: `$WIKI_ROOT/projects/llm-wiki/`

Read the wiki's `CLAUDE.md` for documentation conventions.
Read the wiki's `projects/llm-wiki/index.md` before any documentation task.
Read user preferences at: `$WIKI_ROOT/user/preferences.md`

**Before any documentation task:** delegate to the `wiki-read` subagent.
**For any wiki edit:** delegate to the `wiki-update` subagent. Do NOT edit wiki pages from the main thread.

## Project

- Language: bash, python, md (for agents, etc)
- Repo root: ~/tools/llm-wiki

## Session Token

A session token is injected at startup via the `UserPromptSubmit` hook. Format: `cc-<session-uuid>`.

Use this token in all wiki references made during this session. Pass it to `wiki-update` when delegating.

To find the full transcript later:
```bash
grep -rl "<session-id>" ~/.claude/projects/ --include="*.jsonl" --exclude="*history.jsonl"
```

## File References

All text-based file references in wiki pages use `nvim://` URIs — read the nvim skill for the full format. This applies to source code, markdown, yaml, shell scripts, config files, and logs. Use semantic anchors (`::symbol`) for code; use line numbers for files without named symbols.

Examples:
- `nvim://llm-wiki/hooks/wiki-session-token.sh` — a script in this repo
- `nvim://llm-wiki/wiki-templates/CLAUDE.md` — a markdown file
- `nvim:///home/jtabor/.config/nvim-goto/projects.json/3` — a config file at an absolute path

## After Feature Completion

When a feature is implemented ask the user if it's time to update the wiki.  It is your job to make sure the user doesn't forget.
