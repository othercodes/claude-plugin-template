#!/bin/bash
# engine.doctor.test.sh: self-check for engine.doctor.sh. No framework, plain asserts.
# Run: bash scripts/engine.doctor.test.sh   (exits non-zero on any failure)

set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
DOC="$HERE/engine.doctor.sh"
FAILS=0
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP"   # hermetic: the walk-up never leaves the fixture

check()   { case "$3" in *"$2"*) echo "ok   - $1" ;; *) echo "FAIL - $1 (missing '$2' in: $3)"; FAILS=$((FAILS+1)) ;; esac; }
checkrc() { [ "$2" = "$3" ] && echo "ok   - $1" || { echo "FAIL - $1 (rc want $2 got $3)"; FAILS=$((FAILS+1)); }; }

P="$TMP/p"
mkdir -p "$P/.claude/context/cards" "$P/.claude/reminders" "$TMP/empty"
printf '# Hi\n' > "$P/.claude/context/00-hi.md"
printf '# A\n' > "$P/.claude/context/cards/a.md"
printf '# comment\n^a/\ta\n^b/\tmissing\nno tab here\n' > "$P/.claude/context/cards.map"
printf 'ok\tmsg\n# comment\n\nno tab rule\n' > "$P/.claude/reminders/x.rules"

O=$(cd "$P" && bash "$DOC"); RC=$?
check   "jq is checked"                "ok	claude-context-engine	jq found"          "$O"
check   "context dir is reported"      "$P/.claude/context (1 always-on"            "$O"
check   "missing card is flagged"      "bad	claude-context-engine	cards.map points to a missing card: missing" "$O"
check   "untabbed map line is flagged" "cards.map:4"                                "$O"
check   "reminders dir is reported"    "$P/.claude/reminders (1 rules)"             "$O"
check   "untabbed rule is flagged"     "x.rules:4"                                  "$O"
checkrc "content problems do not block" 0 "$RC"

O=$(cd "$TMP/empty" && bash "$DOC")
check   "no context is a note"         "note	claude-context-engine	no .claude/context/"   "$O"
check   "no reminders is a note"       "note	claude-context-engine	no .claude/reminders/" "$O"
check   "kill switch is reported"      "CLAUDE_CONTEXT_ENGINE_NO_HOOKS is set" "$(cd "$TMP/empty" && CLAUDE_CONTEXT_ENGINE_NO_HOOKS=1 bash "$DOC")"

echo
if [ "$FAILS" -eq 0 ]; then echo "ALL PASS"; else echo "$FAILS FAILURE(S)"; exit 1; fi
