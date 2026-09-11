#!/bin/bash
# wiki-config.test.sh: self-check for wiki-config.sh. No framework, plain asserts.
# Run: bash skills/using-wiki/scripts/wiki-config.test.sh   (exits non-zero on any failure)

set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
CFG="$HERE/wiki-config.sh"
FAILS=0
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP"   # hermetic: the walk-up never leaves the fixture

check()   { case "$3" in *"$2"*) echo "ok   - $1" ;; *) echo "FAIL - $1 (missing '$2' in: $3)"; FAILS=$((FAILS+1)) ;; esac; }
checkrc() { [ "$2" = "$3" ] && echo "ok   - $1" || { echo "FAIL - $1 (rc want $2 got $3)"; FAILS=$((FAILS+1)); }; }

P="$TMP/p"
mkdir -p "$P/.claude" "$P/repo/src" "$TMP/empty"
printf -- '- Page id: abc\n' > "$P/.claude/wiki.md"

O=$(bash "$CFG" "$P"); RC=$?
check   "prints the config"                "- Page id: abc"       "$O"
check   "names the file it read"           "$P/.claude/wiki.md"   "$O"
checkrc "exits 0 with a config"            0 "$RC"
check   "found walking up from a subdir"   "- Page id: abc"       "$(bash "$CFG" "$P/repo/src")"
check   "no argument falls back to cwd"    "- Page id: abc"       "$(cd "$P/repo" && bash "$CFG")"
check   "empty argument falls back to cwd" "- Page id: abc"       "$(cd "$P/repo" && bash "$CFG" "")"

# A failing !`...` command aborts the whole skill, so a missing config must still exit 0.
O=$(bash "$CFG" "$TMP/empty"); RC=$?
check   "missing config says so"           "No .claude/wiki.md"   "$O"
check   "missing config points to Setup"   "Setup"                "$O"
checkrc "missing config still exits 0"     0 "$RC"

# The shipped example must keep working.
check   "example config loads"             "- Page id:"           "$(bash "$CFG" "$HERE/../../../examples")"

echo
if [ "$FAILS" -eq 0 ]; then echo "ALL PASS"; else echo "$FAILS FAILURE(S)"; exit 1; fi
