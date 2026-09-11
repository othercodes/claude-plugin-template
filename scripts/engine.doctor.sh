#!/bin/bash
# engine.doctor.sh: doctor contributor for claude-context-engine.
# Prints TSV for the doctor engine:  status <TAB> group <TAB> message <TAB> fix
# Looks for .claude/ from $PWD up, the same walk the hooks do from the session cwd.
# Only a missing jq blocks: without it every hook silently does nothing.

set -u
. "$(cd "$(dirname "$0")" && pwd)/hooks.sh"
G="claude-context-engine"
emit() { printf '%s\t%s\t%s\t%s\n' "$1" "$G" "$2" "${3:-}"; }
# Rule lines (not '#', not blank) with no TAB-separated second field, as file:line.
untabbed() { awk -F'\t' '!/^(#|$)/ && $2 == "" { print FILENAME ":" FNR }' "$@" 2>/dev/null; }

rc=0
if command -v jq >/dev/null 2>&1; then
  emit ok "jq found"
else
  emit bad "jq not found, every hook is a no-op without it" "install jq"
  rc=1
fi
for v in NO_HOOKS NO_CONTEXT NO_REMINDERS; do
  var="CLAUDE_CONTEXT_ENGINE_$v"
  [ -n "${!var:-}" ] && emit note "$var is set, that part of the engine is off"
done

C=$(find_claude_dir "$PWD" context)
if [ -n "$C" ]; then
  files=$(ls "$C"/*.md 2>/dev/null | wc -l | tr -d ' ')
  bytes=$(cat "$C"/*.md 2>/dev/null | wc -c | tr -d ' ')
  emit ok "context: $C ($files always-on files, ${bytes}B on every session and subagent)"
  if [ -f "$C/cards.map" ]; then
    untabbed "$C/cards.map" | while read -r at; do
      emit bad "$at has no TAB-separated card key" "separate the regex and the key with a TAB"
    done
    awk -F'\t' '!/^(#|$)/ && $2 != "" { print $2 }' "$C/cards.map" | sort -u | while read -r k; do
      [ -f "$C/cards/$k.md" ] || emit bad "cards.map points to a missing card: $k" "create $C/cards/$k.md or drop its line"
    done
  fi
else
  emit note "no .claude/context/ from $PWD up to \$HOME, nothing to inject"
fi

R=$(find_claude_dir "$PWD" reminders)
if [ -n "$R" ]; then
  rules=$(awk -F'\t' '!/^(#|$)/ && $2 != ""' "$R"/*.rules 2>/dev/null | wc -l | tr -d ' ')
  emit ok "reminders: $R ($rules rules)"
  untabbed "$R"/*.rules | while read -r at; do
    emit bad "$at has no TAB-separated message" "separate the regex and the message with a TAB"
  done
else
  emit note "no .claude/reminders/ from $PWD up to \$HOME, no reminders"
fi
exit "$rc"
