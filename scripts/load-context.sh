#!/bin/bash
# load-context.sh: claude-context-engine, the context half.
# Injects the project's .claude/context/, found walking up from the hook's cwd:
#   SessionStart  -> every context/*.md, plus the repo list when cwd is a multi-repo workspace
#   SubagentStart -> every context/*.md, plus the cards matching the subagent's cwd
#   PreToolUse    -> the cards matching the touched file, once per session
# Cards are context/cards/<key>.md, picked by context/cards.map, one rule per
# line ('#' and blank lines skipped):
#     <extended-regex on the path relative to the project root>\t<key>
# Placeholders replaced in every file: {{ROOT_DIR}} (the project root's
# basename) and {{CONTEXT_DIR}} (absolute path of .claude/context).

# Kill switches (see README): master, or context only.
[ -n "${CLAUDE_CONTEXT_ENGINE_NO_HOOKS}${CLAUDE_CONTEXT_ENGINE_NO_CONTEXT}" ] && exit 0

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/hooks.sh"
[ -t 0 ] && exit 0                                   # no stdin, nothing to do
INPUT=$(cat)
field() { printf '%s' "$INPUT" | jq -r "$1 // empty" 2>/dev/null; }
EVENT=$(field .hook_event_name)
CWD=$(field .cwd)
DIR=$(find_claude_dir "$CWD" context)
[ -n "$DIR" ] || exit 0
ROOT="${DIR%/.claude/context}"

# ROOT_DIR is a basename (no '/'), CONTEXT_DIR a path, hence the two delimiters.
# ponytail: a '&' or '|' in the project path breaks this sed; move to awk
# index/substr the day a real path carries one.
subst() { sed "s/{{ROOT_DIR}}/$(basename "$ROOT")/g; s|{{CONTEXT_DIR}}|$DIR|g"; }

# The path relative to the project root, so cards.map rules can anchor with '^'.
rel() { case "$1" in "$ROOT"/*) printf '%s' "${1#"$ROOT/"}" ;; *) printf '%s' "$1" ;; esac; }

always() { for f in "$DIR"/*.md; do [ -f "$f" ] && cat "$f" && echo; done; }

# Keys of the cards whose regex matches $1, once each, skipping keys with no card file.
cards_for() {
  [ -f "$DIR/cards.map" ] || return 0
  # `|| [ -n "$re" ]` keeps a last line that has no trailing newline.
  while IFS=$'\t' read -r re key || [ -n "$re" ]; do
    case "$re" in ''|'#'*) continue ;; esac
    [ -n "$key" ] && [ -f "$DIR/cards/$key.md" ] || continue
    printf '%s' "$1" | grep -qE -- "$re" && echo "$key"
  done < "$DIR/cards.map" | awk '!seen[$0]++'
}

card() { printf '<!-- injected-card: %s -->\n' "$1"; cat "$DIR/cards/$1.md"; echo; }

# Git repos under a workspace root that is not itself a repo, two levels deep:
# flat (repo/) and grouped (group/repo/). A repo nested in a repo is not listed.
repos() {
  [ -d "$1" ] && [ ! -e "$1/.git" ] || return 0
  # ponytail: over 50 subdirectories reads as "not a workspace" (a home dir, say);
  # a real workspace that big needs a smarter guard.
  [ "$(ls -1d "$1"/*/ 2>/dev/null | wc -l | tr -d ' ')" -le 50 ] || return 0
  local list
  list=$(cd "$1" && for d in */ */*/; do
    [ -e "$d.git" ] || continue
    # The leading '(' is what lets bash 3.2 parse a case inside $(...).
    case "$d" in (*/*/*) [ -e "${d%%/*}/.git" ] && continue ;; esac
    echo "${d%/}"
  done | sort)
  [ -n "$list" ] || return 0
  printf '## Local Repositories\n\nGit repos detected relative to `%s/`:\n\n%s\n' "$(basename "$1")" "$list"
}

case "$EVENT" in
  SessionStart)
    { always; repos "$CWD"; } | subst | emit_context SessionStart
    ;;
  SubagentStart)
    { always; cards_for "$(rel "$CWD/")" | while read -r k; do card "$k"; done; } \
      | subst | emit_context SubagentStart
    ;;
  PreToolUse)
    FILE=$(field .tool_input.file_path)
    [ -n "$FILE" ] || exit 0
    # Dedup state beside the transcript: it survives a resume and, unlike
    # grepping the transcript for a marker, conversation content cannot fool it.
    TRANSCRIPT=$(field .transcript_path)
    STATE="${TRANSCRIPT:+$TRANSCRIPT.context-cards}"
    STATE="${STATE:-${TMPDIR:-/tmp}/claude-context-cards-$(field .session_id)}"
    cards_for "$(rel "$FILE")" | while read -r k; do
      grep -qxF "$k" "$STATE" 2>/dev/null && continue
      echo "$k" >> "$STATE"
      card "$k"
    done | subst | emit_context PreToolUse
    ;;
esac
exit 0
