#!/bin/bash
# doctor.sh: setup health-check engine for the plugin.
# It discovers every *.doctor.sh contributor in the plugin, runs each, and renders
# their results. The engine knows nothing about specific checks; each contributor
# is a standalone script that speaks a small protocol.
#
# Contributor protocol:
#   stdout: one TAB-separated line per result:
#             status <TAB> group <TAB> message <TAB> fix
#           status = ok | bad | note      (fix optional, shown under a bad)
#           messages must not contain tabs.
#   exit:   0 = no blocking problem; non-zero = a blocking problem was found.
#
# The engine renders ok/bad/note as ✓/✗/→, groups by the group field (first-seen
# order), and exits non-zero if any contributor did. Secrets are never printed:
# contributors report "set"/"missing", not values.
#
# DOCTOR_ROOT overrides the search root (used by the test).

set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="${DOCTOR_ROOT:-$(cd "$SCRIPT_DIR/../../.." && pwd)}"
SELF="$SCRIPT_DIR/doctor.sh"

TSV="$(mktemp)"; trap 'rm -f "$TSV"' EXIT
rc=0
while IFS= read -r f; do
  [ "$f" = "$SELF" ] && continue                     # never run the engine as a contributor
  bash "$f" >> "$TSV" || rc=1                         # a non-zero contributor blocks
done < <(find "$ROOT" -type f -name '*.doctor.sh' -not -path '*/node_modules/*' 2>/dev/null | sort)

echo "Setup check"
# Render grouped, groups in first-seen order. Each group re-scans the TSV.
cut -f2 "$TSV" | awk 'NF && !seen[$0]++' | while IFS= read -r g; do
  printf '\n%s\n' "$g"
  while IFS=$'\t' read -r st gg msg fix; do
    [ "$gg" = "$g" ] || continue
    case "$st" in
      ok)   printf '  ✓ %s\n' "$msg" ;;
      bad)  printf '  ✗ %s\n' "$msg"; [ -n "$fix" ] && printf '      → %s\n' "$fix" ;;
      note) printf '  → %s\n' "$msg" ;;
    esac
  done < "$TSV"
done

echo
if [ "$rc" -eq 0 ]; then
  echo "No blocking issues."
else
  echo "Blocking issues above must be fixed for the plugin to work."
fi
exit "$rc"
