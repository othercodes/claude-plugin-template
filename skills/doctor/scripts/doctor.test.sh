#!/bin/bash
# doctor.test.sh: self-check for the doctor engine. No framework, plain asserts.
# Run: bash skills/doctor/scripts/doctor.test.sh   (exits non-zero on any failure)
#
# Drives the engine against fixture *.doctor.sh contributors in a temp root
# (DOCTOR_ROOT), so it tests discovery + rendering + exit aggregation without
# touching the real environment.

set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
DOC="$HERE/doctor.sh"
FAILS=0
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

check()   { case "$3" in *"$2"*) echo "ok   - $1" ;; *) echo "FAIL - $1 (missing '$2')"; FAILS=$((FAILS+1)) ;; esac; }
checkrc() { [ "$2" = "$3" ] && echo "ok   - $1" || { echo "FAIL - $1 (rc want $2 got $3)"; FAILS=$((FAILS+1)); }; }

# A passing contributor (ok + note, exit 0) and a failing one (bad + fix, exit 1).
cat > "$TMP/a.doctor.sh" <<'EOF'
#!/bin/bash
printf 'ok\tGroup A\titem passes\t\n'
printf 'note\tGroup A\ta reminder\t\n'
exit 0
EOF
cat > "$TMP/b.doctor.sh" <<'EOF'
#!/bin/bash
printf 'bad\tGroup B\titem fails\tdo the fix\n'
exit 1
EOF

# 1. Both contributors: every status renders, both groups appear, exit 1 (b failed).
O=$(DOCTOR_ROOT="$TMP" bash "$DOC"); RC=$?
check   "renders ok"     "✓ item passes" "$O"
check   "renders bad"    "✗ item fails"  "$O"
check   "renders fix"    "→ do the fix"  "$O"
check   "renders note"   "→ a reminder"  "$O"
check   "group A header" "Group A"       "$O"
check   "group B header" "Group B"       "$O"
checkrc "exit 1 when a contributor blocks" 1 "$RC"

# 2. Only a passing contributor -> exit 0, no-blocking line.
rm "$TMP/b.doctor.sh"
O=$(DOCTOR_ROOT="$TMP" bash "$DOC"); RC=$?
check   "no blocking line" "No blocking issues" "$O"
checkrc "exit 0 when all pass" 0 "$RC"

echo
if [ "$FAILS" -eq 0 ]; then echo "ALL PASS"; else echo "$FAILS FAILURE(S)"; exit 1; fi
