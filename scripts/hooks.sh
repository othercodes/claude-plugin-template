#!/bin/bash
# hooks.sh: shared helpers for claude-context-engine. Source it.

# emit_context <EVENT>: wraps stdin in the envelope Claude Code expects from a
# hook (hookSpecificOutput.additionalContext). The one place that knows that
# JSON shape. Empty stdin prints nothing, so a hook with nothing to say is silent.
emit_context() {
  local ctx
  ctx=$(cat)
  [ -n "$ctx" ] || return 0
  jq -n --arg name "$1" --arg ctx "$ctx" \
    '{hookSpecificOutput: {hookEventName: $name, additionalContext: $ctx}}'
}

# find_claude_dir <cwd> <sub>: the first <dir>/.claude/<sub> (a directory or a
# file) walking up from cwd. The cwd is not the session root: in a multi-repo
# workspace it moves into a repo as soon as anything cds there. $HOME is the last
# directory checked, so ~/.claude/<sub> is a global fallback and nothing above it
# is ever read.
find_claude_dir() {
  local dir="$1"
  case "$dir" in /*) ;; *) return 0 ;; esac          # dirname of a relative path never reaches /
  while [ "$dir" != "/" ]; do
    [ -e "$dir/.claude/$2" ] && { echo "$dir/.claude/$2"; return 0; }
    [ "$dir" = "$HOME" ] && return 0
    dir=$(dirname "$dir")
  done
}
