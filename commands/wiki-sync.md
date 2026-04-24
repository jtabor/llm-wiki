Delegate to the `wiki-update` subagent to record what happened in this session.

Before delegating, retrieve the session token that was injected at session start (format: `cc-<uuid>`). It appears in the system context at the top of the conversation. Include it verbatim in the subagent prompt.

Give the subagent the following context:

**Session token:** cc-<paste the actual session token UUID here — do NOT leave this as a placeholder>

**From the conversation:** summarize the key things that happened:
- Decisions made (architectural, design, approach choices)
- Technical facts established or confirmed
- Bugs found and how they were fixed
- Pitfalls encountered (include severity: critical/moderate/minor)
- User preferences stated
- Action items left open

**From the code changes:** run `git diff HEAD` (or `git diff main...HEAD` if on a feature branch) in the project repo to see what changed. Summarize:
- Which files changed and what each change does
- New symbols/functions added (use nvim:// refs)
- Existing symbols modified (use nvim:// refs)
- Anything removed

**Instructions for the wiki-update agent:**
1. Read `$WIKI_ROOT/CLAUDE.md` first
2. File decisions and technical facts to the appropriate `concepts/` or `codebases/` pages — create pages if they don't exist
3. File any pitfalls to `projects/<name>/pitfalls.md`
4. Update `projects/<name>/log.md` with a one-line summary of today's work
5. Update `projects/<name>/index.md` if new pages were created
6. Every claim needs a ref: nvim:// for code, [conv:cc-<token>](conv://cc-<token>) for things from this conversation
7. Commit with: `wk-commit update '<brief summary>' --session cc-<token>`

If $ARGUMENTS is provided, treat it as additional instructions or a focus area (e.g. "focus on the DMA changes" or "also update user preferences").
