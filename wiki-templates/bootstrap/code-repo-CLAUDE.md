# CLAUDE.md — <Project Name>

## Wiki

This project's wiki lives at: `$WIKI_ROOT/projects/<name>/`

Read the wiki's `CLAUDE.md` for documentation conventions.
Read the wiki's `projects/<name>/index.md` before any documentation task.
Read user preferences at: `$WIKI_ROOT/user/preferences.md`

**Before any documentation task:** delegate to the `wiki-read` subagent.
**For any wiki edit:** delegate to the `wiki-update` subagent. Do NOT edit wiki pages from the main thread.

## Project

- Language: (fill in)
- Build: (fill in)
- Repo root: (fill in absolute path)

## Session Token

A session token is injected at startup via the `UserPromptSubmit` hook. Format: `cc-<session-uuid>`.

Use this token in all wiki references made during this session. Pass it to `wiki-update` when delegating.

To find the full transcript later:
```bash
grep -rl "<session-id>" ~/.claude/projects/ --include="*.jsonl" --exclude="*history.jsonl"
```

## File References

All code references in wiki pages use paths relative to this repo root. Example:
`src/drivers/dma.c::dma_init` refers to the `dma_init` symbol in that file.
Wiki pages use `nvim://` URIs — read the nvim skill for the full format.

## After Feature Completion

When a feature is implemented, delegate to `wiki-update` to:
1. Update relevant codebase/concept pages with what changed
2. Reference the conversation (by session token) where the work happened
3. Add any new pitfalls discovered during implementation
4. Update `projects/<name>/index.md` and `projects/<name>/log.md`
5. Commit the wiki: `wk-commit update '<feature description>' --session cc-<token>`
