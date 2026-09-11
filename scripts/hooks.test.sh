#!/bin/bash
# hooks.test.sh: self-check for hooks.sh. No framework, plain asserts.
# Run: bash scripts/hooks.test.sh   (exits non-zero on any failure)

set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/hooks.sh"
FAILS=0
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

pass() { echo "ok   - $1"; }
fail() { echo "FAIL - $1"; FAILS=$((FAILS + 1)); }
same() { [ "$2" = "$3" ] && pass "$1" || fail "$1 (want '$2', got '$3')"; }

OUT="$(printf 'hello world' | emit_context SessionStart)"
same "event name is set"         "SessionStart" "$(printf '%s' "$OUT" | jq -r .hookSpecificOutput.hookEventName)"
same "context is passed through" "hello world"  "$(printf '%s' "$OUT" | jq -r .hookSpecificOutput.additionalContext)"
same "no data, no envelope"      ""             "$(printf '' | emit_context Stop)"

# find_claude_dir: first .claude/<sub> walking up from cwd, $HOME is the last stop.
mkdir -p "$TMP/.claude/context" "$TMP/home/.claude/reminders" "$TMP/home/ws/.claude/context"
export HOME="$TMP/home"
same "found in cwd"                   "$HOME/ws/.claude/context"  "$(find_claude_dir "$HOME/ws" context)"
same "found walking up"               "$HOME/ws/.claude/context"  "$(find_claude_dir "$HOME/ws/repo/src" context)"
same "\$HOME/.claude is the last stop" "$HOME/.claude/reminders"  "$(find_claude_dir "$HOME/ws/repo" reminders)"
same "never above \$HOME"             ""                          "$(find_claude_dir "$HOME/other" context)"
same "outside \$HOME it walks to /"   "$TMP/.claude/context"      "$(find_claude_dir "$TMP/x/y" context)"
same "empty cwd finds nothing"        ""                          "$(find_claude_dir "" context)"
same "relative cwd finds nothing"     ""                          "$(find_claude_dir "ws" context)"

echo
if [ "$FAILS" -eq 0 ]; then echo "ALL PASS"; else echo "$FAILS FAILURE(S)"; exit 1; fi
