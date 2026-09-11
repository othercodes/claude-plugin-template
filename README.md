# claude-plugin-template

A Claude Code plugin template that ships one engine, **claude-context-engine**,
and no content. The content lives in each project's `.claude/`, so the same
plugin serves any repo or workspace without being edited.

## What it does

| Hook | Injects |
| --- | --- |
| `SessionStart` | every `.claude/context/*.md`, plus the list of git repos when the session starts in a multi-repo workspace |
| `SubagentStart` | every `.claude/context/*.md`, plus the cards matching the subagent's cwd |
| `PreToolUse` (Read, Edit, Write) | the cards matching the touched file, once per session |
| `UserPromptSubmit` | the message of every `.claude/reminders/*.rules` rule the prompt matches |

Everything goes through `hookSpecificOutput.additionalContext`. Requires `jq`;
the scripts run on bash 3.2, the macOS default.

## Content layout

```text
<project>/.claude/
  context/*.md             always-on
  context/cards/<key>.md   lazy, injected on the first touch of a matching file
  context/cards.map        <path regex><TAB><key>
  reminders/*.rules        <prompt regex><TAB><message>
```

Each hook walks up from the session cwd to the first directory holding
`.claude/context/` (or `.claude/reminders/`) and stops at `$HOME`, so
`~/.claude/context/` works as a global fallback. Only the first one found is
used; they do not stack.

- **Always-on** files load in lexical order, so prefix them (`00-`, `10-`). They cost tokens on every session and every subagent: keep them small and push detail into cards.
- **`cards.map`** regexes are extended (`grep -E`) and match the file path relative to the project root, the directory holding `.claude/`, so `^services/api/` works. A path can match several cards; each is injected once per session.
- **Reminder** patterns are extended and case-insensitive (`grep -iE`). A strong nudge, not enforcement: keep them tight, noisy reminders get ignored.
- `#` comments and blank lines are skipped in both TSV files.
- **Placeholders** replaced in context files and cards: `{{ROOT_DIR}}` (the project root's basename) and `{{CONTEXT_DIR}}` (absolute path of `.claude/context/`, so "read `{{CONTEXT_DIR}}/cards/x.md`" resolves from any cwd).

`examples/.claude/` is a working sample: copy it to a project root and edit it.

## How it works

Claude Code runs the plugin's hooks (`hooks/hooks.json`) at four points of a
session. Each hook is a bash script that reads the event JSON on stdin, finds
the project's content, and prints a JSON envelope whose `additionalContext`
Claude Code adds to the model's context. A hook with nothing to add prints
nothing, so it costs nothing.

1. **Finding the content.** The hook takes `cwd` from the event and walks up to the first `.claude/context/` (or `.claude/reminders/`), checking `$HOME` last. Walking up matters in a multi-repo workspace, where the cwd moves into a repo as soon as anything cds there. The directory holding `.claude/` is the project root.
2. **Session start.** `scripts/load-context.sh` concatenates every `context/*.md` in lexical order and replaces the placeholders. When the cwd is not a git repo but holds repos one or two levels down (`repo/` or `group/repo/`), it appends a "Local Repositories" list so the model uses real paths instead of guessing them. This is the always-on map.
3. **Subagent start.** A subagent starts with a fresh context, so it gets the same always-on files, plus the cards matching its cwd.
4. **File touch** (`PreToolUse` on Read, Edit, Write). The file path is made relative to the project root and matched against every `cards.map` line. Each matching card is injected under an `<!-- injected-card: <key> -->` marker. The keys already injected are recorded in `<transcript>.context-cards`, beside the session transcript, so a card lands once per session, survives a resume, and later touches are free.
5. **Prompt submit.** `scripts/reminder.sh` matches the prompt against every `reminders/*.rules` pattern and injects the message of each rule that matches, one per line.

The split is about cost. Always-on files are paid on every session and every
subagent; cards are paid only when the model works in their area. Keep the
always-on files as the map (what exists, where, which card to read) and the
cards as the detail.

A session on the shipped example, with the project at `~/work/shop`:

```text
you     claude                                  (cwd ~/work/shop)
engine  .claude/context/00-project.md           injected at session start
model   Read ~/work/shop/src/app.py
engine  cards.map "^src/<TAB>src" matches "src/app.py", cards/src.md injected (once)
model   Edit ~/work/shop/src/db.py
engine  src already injected this session, nothing added
you     "the PR got merged"
engine  git.rules "\bmerged\b" matches, the housekeeping reminder is injected
```

## Install

```shell
/plugin marketplace add <owner>/claude-plugin-template
/plugin install claude-plugin-template@claude-plugin-template
```

To try a local checkout: `claude --plugin-dir ./claude-plugin-template`.

## Doctor

Ask "is the plugin set up correctly" or run the `doctor` skill. It runs every
`*.doctor.sh` in the plugin; `scripts/engine.doctor.sh` checks `jq`, reports
which `.claude/` it found and the always-on size, and flags rule lines without a
TAB and `cards.map` keys with no card file. A new skill adds its own checks by
dropping a `<skill>.doctor.sh` next to it (protocol in `skills/doctor/scripts/doctor.sh`).

## Disabling hooks

Set any of these non-empty in your shell profile. Skills keep working; only the
hooks turn off.

| Variable | Disables |
| --- | --- |
| `CLAUDE_CONTEXT_ENGINE_NO_HOOKS` | everything below (master switch) |
| `CLAUDE_CONTEXT_ENGINE_NO_CONTEXT` | context injection |
| `CLAUDE_CONTEXT_ENGINE_NO_REMINDERS` | reminders |

## Building on the template

Rename `name` in `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json`,
then add skills, agents or commands. Keep project content out of the plugin: it
belongs in the project's `.claude/`.

## Development

```shell
for t in $(git ls-files '*.test.sh'); do /bin/bash "$t" || break; done
```

CI (`.github/workflows/ci.yml`) runs the same self-tests on Ubuntu and macOS,
plus JSON, shell syntax and skill frontmatter checks.
