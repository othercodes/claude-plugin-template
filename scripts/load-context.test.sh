#!/bin/bash
# load-context.test.sh: self-check for load-context.sh. No framework, plain asserts.
# Run: bash scripts/load-context.test.sh   (exits non-zero on any failure)

set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/load-context.sh"
FAILS=0
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP"   # hermetic: the walk-up never leaves the fixture

# A multi-repo workspace: one flat repo, one grouped repo, and a repo nested in a repo.
WS="$TMP/ws"
C="$WS/.claude/context"
mkdir -p "$C/cards" "$WS/svc-a/.git" "$WS/svc-a/src" "$WS/svc-a/vendor/.git" "$WS/group/svc-b/.git"
printf '# Registry of {{ROOT_DIR}}\nCards live in {{CONTEXT_DIR}}/cards\n' > "$C/00-registry.md"
printf '# Overview\n' > "$C/10-overview.md"
printf 'not markdown\n' > "$C/notes.txt"
printf '# Card A of {{ROOT_DIR}}\n' > "$C/cards/a.md"
printf '# Card B\n' > "$C/cards/b.md"
# Comment, anchored regexes, a second line for the same card, a key with no card file.
printf '# a comment\n^svc-a/\ta\n^group/svc-b/\tb\nsvc-b\tb\n^ghost/\tghost' > "$C/cards.map"
TRANSCRIPT="$TMP/transcript.jsonl"

run() { printf '%s' "$1" | "$HOOK"; }
ctx() { run "$1" | jq -r '.hookSpecificOutput.additionalContext // ""'; }
evt() { run "$1" | jq -r '.hookSpecificOutput.hookEventName // ""'; }
session()  { jq -nc --arg c "$1" '{hook_event_name: "SessionStart", cwd: $c}'; }
subagent() { jq -nc --arg c "$1" '{hook_event_name: "SubagentStart", cwd: $c}'; }
touching() { jq -nc --arg c "$WS" --arg f "$1" --arg t "$TRANSCRIPT" \
  '{hook_event_name: "PreToolUse", cwd: $c, transcript_path: $t, tool_input: {file_path: $f}}'; }

check() { # desc, want (substring, or "EMPTY"), got
  local desc="$1" want="$2" got="$3"
  if [ "$want" = "EMPTY" ]; then
    if [ -z "$got" ]; then echo "ok   - $desc"; else echo "FAIL - $desc (expected empty, got: $got)"; FAILS=$((FAILS + 1)); fi
  else
    case "$got" in *"$want"*) echo "ok   - $desc" ;; *) echo "FAIL - $desc (missing '$want' in: $got)"; FAILS=$((FAILS + 1)) ;; esac
  fi
}
lacks() { # desc, unwanted, got
  case "$3" in *"$2"*) echo "FAIL - $1 (found '$2')"; FAILS=$((FAILS + 1)) ;; *) echo "ok   - $1" ;; esac
}

S="$(ctx "$(session "$WS")")"
check "SessionStart emits the event"    "SessionStart"      "$(evt "$(session "$WS")")"
check "always-on file injected"         "# Registry of ws"  "$S"
check "{{CONTEXT_DIR}} substituted"     "$C/cards"          "$S"
check "second always-on file injected"  "# Overview"        "$S"
case "$S" in *Registry*Overview*) echo "ok   - lexical order" ;; *) echo "FAIL - lexical order"; FAILS=$((FAILS + 1)) ;; esac
lacks "non-.md files are skipped"       "not markdown"      "$S"
lacks "cards are not always-on"         "# Card"            "$S"
check "workspace lists a flat repo"     "svc-a"             "$S"
check "workspace lists a grouped repo"  "group/svc-b"       "$S"
lacks "a repo inside a repo is not listed" "svc-a/vendor"   "$S"
R="$(ctx "$(session "$WS/svc-a")")"
check "found walking up from a repo"    "# Registry of ws"  "$R"
lacks "a single repo lists no repos"    "Local Repositories" "$R"
check "no .claude/context, silent"      "EMPTY"             "$(ctx "$(session "$TMP/nowhere")")"
check "kill switch"                     "EMPTY"             "$(export CLAUDE_CONTEXT_ENGINE_NO_CONTEXT=1; ctx "$(session "$WS")")"
check "master kill switch"              "EMPTY"             "$(export CLAUDE_CONTEXT_ENGINE_NO_HOOKS=1; ctx "$(session "$WS")")"

A="$(ctx "$(subagent "$WS/svc-a/src")")"
check "SubagentStart emits the event"   "SubagentStart"     "$(evt "$(subagent "$WS")")"
check "subagent gets always-on"         "# Registry of ws"  "$A"
check "subagent gets its cwd's card"    "# Card A of ws"    "$A"
lacks "subagent at the root, no card"   "# Card"            "$(ctx "$(subagent "$WS")")"

T="$(ctx "$(touching "$WS/svc-a/src/main.py")")"
check "PreToolUse injects the card"     "# Card A of ws"    "$T"
check "card carries its marker"         "injected-card: a"  "$T"
lacks "PreToolUse skips always-on"      "Registry"          "$T"
check "same card twice, silent"         "EMPTY"             "$(ctx "$(touching "$WS/svc-a/README.md")")"
B="$(ctx "$(touching "$WS/group/svc-b/x.go")")"
check "second card injected"            "# Card B"          "$B"
[ "$(printf '%s' "$B" | grep -c '# Card B')" = 1 ] && echo "ok   - two map lines, one card" || { echo "FAIL - two map lines, one card"; FAILS=$((FAILS + 1)); }
check "no matching card, silent"        "EMPTY"             "$(ctx "$(touching "$WS/other/x.py")")"
check "key without a card file, silent" "EMPTY"             "$(ctx "$(touching "$WS/ghost/x.py")")"
[ -f "$TRANSCRIPT.context-cards" ] && echo "ok   - dedup state beside the transcript" || { echo "FAIL - dedup state beside the transcript"; FAILS=$((FAILS + 1)); }

# The shipped example must keep working.
EX="$(cd "$HERE/../examples" && pwd)"
check "example always-on loads"         "# examples"        "$(ctx "$(session "$EX")")"
check "example card maps to src/"       "injected-card: src" "$(ctx "$(jq -nc --arg c "$EX" --arg f "$EX/src/app.py" \
  '{hook_event_name: "PreToolUse", cwd: $c, session_id: "example-test", tool_input: {file_path: $f}}')")"
rm -f "${TMPDIR:-/tmp}/claude-context-cards-example-test"

echo
if [ "$FAILS" -eq 0 ]; then echo "ALL PASS"; else echo "$FAILS FAILURE(S)"; exit 1; fi
