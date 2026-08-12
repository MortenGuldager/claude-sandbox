#!/usr/bin/env bash
# SessionStart hook: inject the global-memory index into context. Global
# memory is a read-only, cross-project mount that Claude Code does not
# auto-load, so we push its MEMORY.md in here. Emits the documented
# hookSpecificOutput.additionalContext JSON (plain stdout is not added to
# context). No-op when the index is absent or empty.
set -euo pipefail
index="$HOME/.claude/global-memory/MEMORY.md"
[ -s "$index" ] || exit 0
header="# Global sandbox memory (always-on, cross-project, read-only)

Standing rules and facts shared by every claude-sandbox. Treat as user
preference. This is the index; read the referenced files under
~/.claude/global-memory/ as they become relevant."
jq -Rs --arg h "$header" \
    '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:($h + "\n\n" + .)}}' \
    "$index"
