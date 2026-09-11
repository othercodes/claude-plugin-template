#!/bin/bash
# reminder.sh: claude-context-engine, the reminders half (UserPromptSubmit).
# Matches the prompt against the project's .claude/reminders/*.rules, found
# walking up from the cwd, and injects the message of every rule that matches:
# a skill nudge, a git-discipline reminder, a convention, anything. A strong
# nudge, not enforcement. One rule per line, '#' and blank lines skipped:
#     <extended-regex, case-insensitive>\t<message>

# Kill switches (see README): master, or reminders only.
[ -n "${CLAUDE_CONTEXT_ENGINE_NO_HOOKS}${CLAUDE_CONTEXT_ENGINE_NO_REMINDERS}" ] && exit 0

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/hooks.sh"
[ -t 0 ] && exit 0                                   # no stdin, nothing to do
INPUT=$(cat)
PROMPT=$(printf '%s' "$INPUT" | jq -r '.prompt // empty' 2>/dev/null)
[ -n "$PROMPT" ] || exit 0
DIR=$(find_claude_dir "$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)" reminders)
[ -n "$DIR" ] || exit 0

for RULES in "$DIR"/*.rules; do
  [ -f "$RULES" ] || continue                        # no .rules files present
  # `|| [ -n "$PATTERN" ]` keeps a last line that has no trailing newline.
  while IFS=$'\t' read -r PATTERN MESSAGE || [ -n "$PATTERN" ]; do
    case "$PATTERN" in ''|'#'*) continue ;; esac
    [ -n "$MESSAGE" ] || continue                    # pattern with no message: skip
    printf '%s' "$PROMPT" | grep -qiE -- "$PATTERN" && printf '%s\n' "$MESSAGE"
  done < "$RULES"
done | emit_context UserPromptSubmit
