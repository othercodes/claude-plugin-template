#!/bin/bash
# wiki-config.sh: prints the project's .claude/wiki.md into the using-wiki skill.
# Found walking up from the project dir ($1, else the cwd), the same walk the
# context engine does. It runs as a !`...` injection in SKILL.md, where a
# non-zero exit aborts the whole skill, so it always exits 0 and says what is
# missing instead.

. "$(cd "$(dirname "$0")/../../.." && pwd)/scripts/hooks.sh"
START="${1:-$PWD}"
CONFIG=$(find_claude_dir "$START" wiki.md)
if [ -n "$CONFIG" ]; then
  printf 'Config: %s\n\n' "$CONFIG"
  cat "$CONFIG"
else
  echo "No .claude/wiki.md found from $START up to \$HOME: the wiki is not set up for this project. Run the Setup operation before any other."
fi
exit 0
