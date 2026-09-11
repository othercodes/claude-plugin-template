#!/bin/bash
# reminder.test.sh: self-check for reminder.sh. No framework, plain asserts.
# Run: bash scripts/reminder.test.sh   (exits non-zero on any failure)

set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/reminder.sh"
FAILS=0
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP"   # hermetic: the walk-up never leaves the fixture

PROJ="$TMP/project"
R="$PROJ/.claude/reminders"
mkdir -p "$R"
# Two files, to exercise multi-file loading and comment skipping.
printf 'apple\t[reminder] APPLE\n# a comment line\nbanana\t[reminder] BANANA\n' > "$R/one.rules"
printf 'cherry\t[reminder] CHERRY\n' > "$R/two.rules"
# A pattern with no message, then a final line with NO trailing newline.
printf 'grape\t[reminder] GRAPE\nnomessage\n' > "$R/edge.rules"
printf 'kiwi\t[reminder] KIWI' >> "$R/edge.rules"
printf 'mango\t[reminder] MANGO\n' > "$R/not-rules.txt"

ctx() { # prompt [cwd]
  jq -nc --arg p "$1" --arg c "${2-$PROJ}" '{prompt: $p, cwd: $c}' \
    | "$HOOK" | jq -r '.hookSpecificOutput.additionalContext // ""'
}

check() { # desc, want (substring, or "EMPTY"), got
  local desc="$1" want="$2" got="$3"
  if [ "$want" = "EMPTY" ]; then
    if [ -z "$got" ]; then echo "ok   - $desc"; else echo "FAIL - $desc (expected empty, got: $got)"; FAILS=$((FAILS + 1)); fi
  else
    case "$got" in *"$want"*) echo "ok   - $desc" ;; *) echo "FAIL - $desc (missing '$want' in: $got)"; FAILS=$((FAILS + 1)) ;; esac
  fi
}

check "simple match fires"            "APPLE"  "$(ctx 'an apple a day')"
check "matching is case-insensitive"  "APPLE"  "$(ctx 'AN APPLE')"
check "no match is silent"            "EMPTY"  "$(ctx 'nothing to see')"
check "comment line is not a rule"    "EMPTY"  "$(ctx 'a comment line')"
check "match in a second file"        "CHERRY" "$(ctx 'one cherry')"
M="$(ctx 'apple and cherry')"
check "multi-match keeps apple"       "APPLE"  "$M"
check "multi-match keeps cherry"      "CHERRY" "$M"
check "final line w/o newline"        "KIWI"   "$(ctx 'one kiwi')"
check "rule before it still fires"    "GRAPE"  "$(ctx 'one grape')"
check "pattern w/o message is silent" "EMPTY"  "$(ctx 'nomessage')"
check "only *.rules files load"       "EMPTY"  "$(ctx 'mango')"
check "found from a nested cwd"       "APPLE"  "$(ctx 'apple' "$PROJ/repo/src")"
check "no .claude/reminders, silent"  "EMPTY"  "$(ctx 'apple' "$TMP/elsewhere")"
check "no cwd, silent"                "EMPTY"  "$(ctx 'apple' '')"
check "kill switch"                   "EMPTY"  "$(export CLAUDE_CONTEXT_ENGINE_NO_REMINDERS=1; ctx 'apple')"
check "master kill switch"            "EMPTY"  "$(export CLAUDE_CONTEXT_ENGINE_NO_HOOKS=1; ctx 'apple')"

# The shipped example must keep working.
check "example rule fires"            "merge"  "$(ctx 'it got merged' "$HERE/../examples")"

echo
if [ "$FAILS" -eq 0 ]; then echo "ALL PASS"; else echo "$FAILS FAILURE(S)"; exit 1; fi
