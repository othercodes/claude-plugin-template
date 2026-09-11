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
  wiki.md                  using-wiki config (optional, see Skills)
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

## Skills

### using-wiki

An LLM-maintained knowledge base in a team-shared Notion database. The skill
consults it (Query), writes to it through a propose-and-approve gate (Ingest),
health-checks it (Lint) and creates or adopts it (Setup). It needs a Notion MCP
connected (`/mcp`) and uses whichever one is installed.

#### Using it

Talk to Claude as usual: the skill loads on its own when the prompt is about the
wiki. To call it explicitly: `/claude-plugin-template:using-wiki <request>`.

| Operation | Ask for example | What happens |
| --- | --- | --- |
| Setup | "set up the wiki" | Asks whether to adopt an existing database or create one, proposes the schema, creates the database and its views (or lists the views to add by hand), then proposes `.claude/wiki.md`. Runs on its own the first time, when there is no config. |
| Query | "what does the wiki say about token caching?" | Searches the database scoped by `Area` (the area in play plus the shared area), opens only the relevant pages, and answers citing pages and code. |
| Ingest | "document this in the wiki", "write a post-mortem of today's outage" | Drafts the note (properties and full body), shows it as a preview, and writes to Notion only after your OK. |
| Lint | "lint the wiki" | Lists notes with missing properties, broken naming, stale or duplicated facts, each with a suggested fix. Fixes go through the same OK. |

Every write to Notion (a note, a new `Type`, `Tag` or `Area` option, the
schema) waits for your OK, because the base is shared.

#### Notes

Each note is a row of the database with the properties `Name`, `Summary`,
`Type`, `Tags` and `Area`. `Type` is one of `knowledge` (how something works
now), `procedure` (a runbook), `report` (a dated incident or investigation) or
`feature design` (a proposal). The full schema and writing conventions are in
`skills/using-wiki/SKILL.md`.

#### Configuration

Which database, and what varies by project (shared area, secrets store,
language, sources), lives in the project's `.claude/wiki.md`. When the skill
loads, a `` !`...` `` line in its `SKILL.md` runs
`skills/using-wiki/scripts/wiki-config.sh`, which finds `.claude/wiki.md` from
`${CLAUDE_PROJECT_DIR}` up (the same walk the hooks do) and prints it into the
skill. The config costs tokens only when the wiki is used. With no config the
skill starts with Setup, which creates or adopts the database and writes
`.claude/wiki.md`. The script always exits 0, because a failing `` !`...` ``
command aborts the whole skill. `examples/.claude/wiki.md` shows the format.

| Field | Used for |
| --- | --- |
| `Database` | the database name, to find it again with a search if an id stops resolving |
| `Page id` | the Notion database every note lives in |
| `Data source` | `collection://...`, for SQL queries over the notes |
| `Shared area` | the `Area` option for cross-cutting notes, always included when searching |
| `Secrets store` | where secrets live, cited instead of pasted into a note |
| `Language` | the language notes are written in (English if unset) |
| `Sources` | the systems notes cite (chat, tracker, VCS, error monitor, source code) |

Commit `.claude/wiki.md` so the whole team works against the same database.

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
