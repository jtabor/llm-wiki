---
type: concept
project: llm-wiki
created: 2026-04-20
updated: 2026-04-20
tags: [hooks, session-token, jsonl, archiving, subagents]
sources: []
conversations: [cc-AsJmgyeR]
confidence: high
---

# Wiki Session Hooks

How the wiki's Claude Code hooks work: session token injection, JSONL archiving, and subagent behavior.

## Session Token

**Hook:** `UserPromptSubmit` → `~/.claude/hooks/wiki-session-token.sh`

On the first user message of each session, the hook:
1. Reads `session_id` from hook stdin JSON
2. Checks `~/.claude/wiki-tokens/<session_id>` — if absent, creates it
3. Injects `additionalContext` into the model: `"Wiki session token for this session: cc-<session_id>. Use it in wiki refs and commit trailers this session."`
4. On all subsequent messages: exits 0, injects nothing

The token is `cc-` prefixed Claude Code session UUID. Stable across resume/continue of the same session. A new UUID only appears on a genuinely fresh session.

**Why `UserPromptSubmit` and not `SessionStart`:** `SessionStart` hooks do not support `additionalContext` injection into the model — the field is silently ignored. `UserPromptSubmit` does.

**Token storage:** `~/.claude/wiki-tokens/` accumulates one file per session UUID. Safe to `rm -rf` anytime.

## JSONL Archiving

**Hooks:** `UserPromptSubmit` + `SessionEnd` → `~/.claude/hooks/wiki-archive-session.sh`

### Hook timing — lessons learned

**`Stop` fires after every assistant turn**, not on process exit. Ctrl-D / EOF triggers `SessionEnd`, not `Stop`. Using only `Stop` for archiving means the final response after Ctrl-D is never captured.

**`Stop` fires before the JSONL is committed to disk** for that turn, so archiving from `Stop` misses the current response.

**Solution:** archive on both `UserPromptSubmit` (captures the just-completed exchange before the next user message) and `SessionEnd` (captures everything on Ctrl-D / process exit). Together they guarantee full coverage.

### What gets archived

Reads `session_id` and `transcript_path` from stdin and copies:
- Parent transcript → `$WIKI_ROOT/conversations/claude-code/<session_id>.jsonl`
- Subagent transcripts → `$WIKI_ROOT/conversations/claude-code/<session_id>/<agent_id>.jsonl`

Requires `$WIKI_ROOT` to be set in the environment. If unset, logs a warning to stderr and exits cleanly.

**Recovery for force-killed sessions:** The JSONL is written incrementally to disk, so it survives kills. `cleanupPeriodDays: 365` gives a year to recover manually via `wk-ingest-cc <session_id>`. For important killed sessions, resuming and having the agent update the wiki directly is the preferred path.

## Subagent Behavior

Confirmed via `SubagentStart` probe hook (`cat >> /tmp/subagent-probe.json`):

| Field | Value |
|---|---|
| `session_id` | Same as parent — shared, not unique per subagent |
| `transcript_path` | Points to parent JSONL |
| `agent_id` | Unique short hex ID per subagent instance |
| `agent_type` | e.g. `general-purpose`, `Explore`, etc. |

Subagent transcripts are stored in a subdir named after `session_id` alongside the parent JSONL. The `cc-<session_id>` token is the correct cross-reference for all subagent work in that session.

## Settings Summary

```json
"cleanupPeriodDays": 365,
"hooks": {
  "UserPromptSubmit": [wiki-session-token.sh, wiki-archive-session.sh],
  "SessionEnd": [wiki-archive-session.sh],
  "SubagentStart": [cat >> /tmp/subagent-probe.json]
}
```

The `SubagentStart` probe hook should be removed once archive completeness is confirmed (see Future Work).

## Future Work

- **Sanity check for archive completeness:** Periodically diff the source JSONL (`~/.claude/projects/.../<session_id>.jsonl`) against the archived copy in the wiki to verify no exchanges are missing. Run this check for a while after any hook changes before fully trusting the archive. Remove the `SubagentStart` probe once this passes consistently.
