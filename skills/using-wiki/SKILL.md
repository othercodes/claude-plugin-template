---
name: using-wiki
description: >-
  Use this skill whenever consulting, documenting, updating, health-checking or
  setting up the team's engineering knowledge base, an LLM-maintained Notion
  database: searching it for an answer, ingesting a source into a note, filing
  an incident or migration report, writing up a feature design, linting the
  base, or creating it for a project. Triggers: "search the wiki", "what does
  the wiki say about X", "is there a note on X", "consult the knowledge base",
  "document this in the wiki", "add to knowledge", "ingest into the wiki",
  "write a post-mortem", "write a feature design", "document this design",
  "lint the wiki", "set up the wiki".
allowed-tools:
  - Read
  - Grep
---

# Using the Wiki

The wiki is an LLM-maintained knowledge base living in a team-shared Notion
database. The LLM writes, maintains, and consults it; humans curate sources,
direct, and ask questions. **This file is the schema**, the single source of
truth for how the wiki is structured and maintained. Follow it; do not
improvise structure.

All Notion operations go through the Notion MCP: `notion-search`,
`notion-fetch`, `notion-create-pages`, `notion-update-page`,
`notion-query-data-sources`, `notion-update-data-source`, and for Setup
`notion-create-database` and `notion-create-view`. The full tool name carries a
prefix that depends on how the Notion MCP was installed (`mcp__notion__...`,
`mcp__plugin_<plugin>_notion__...`); use the Notion MCP that is connected. If
none is, stop and ask the user to connect one (`/mcp`).

## This project's wiki

The database, and the settings that vary by project, come from the project's
`.claude/wiki.md`, injected here when the skill loads:

!`bash "${CLAUDE_SKILL_DIR}/scripts/wiki-config.sh" "${CLAUDE_PROJECT_DIR}"`

What the config names:

- **Database**, **Page id**, **Data source** (`collection://...`, for SQL queries): the Notion database every note lives in. If an id stops resolving, find the database with `notion-search` by its name and propose updating `.claude/wiki.md`.
- **Shared area**: the `Area` option for cross-cutting notes (fleet, ops, secrets, observability), always included when scoping a query.
- **Secrets store**: where secrets live. Never in a note.
- **Language**: the language notes are written in; English if unset. Chat may use another.
- **Sources**: the systems notes cite (chat, tracker, VCS, error monitor, source code).

No config means the wiki is not set up for this project: run **Setup** before
any other operation.

## The database

Every note is a **page (row) in the database**. Classification lives in the page
**properties**, not in frontmatter or folders.

## Note properties

| Property                | Value                                                                             |
|-------------------------|-----------------------------------------------------------------------------------|
| **Name** (title)        | the note title                                                                    |
| **Summary** (text)      | one line, ≤120 chars: what it covers                                              |
| **Type** (select)       | `knowledge` \| `procedure` \| `report` \| `feature design`                        |
| **Tags** (multi-select) | topical labels from the existing option set; add a new option only when none fits |
| **Area** (multi-select) | the part(s) of the system the note concerns, from the existing option set: services, components, or the config's shared area for fleet/ops/secrets/observability. Fetch the data source for the current options; never invent one. Optional: leave blank for cross-cutting tooling or meta notes with no home |

**Type semantics:**

- `knowledge`: how a part of the system works *now* (evergreen).
- `procedure`: a runbook / how-to.
- `report`: a dated, point-in-time account of an event or investigation
  (incident post-mortem, RCA, migration write-up). An incident report is
  `Type: report` with `incident` in **Tags**.
- `feature design`: a proposal for something that does not exist yet. When it
  ships, the note is either rewritten as `knowledge` (present tense, what the
  system now does) or archived. `feature design` is a **Type**, never a Tag.

**Name conventions**, by type:

- `report`: `INC-<n> <YYYY-MM-DD> <Title>` for incidents; other reports lead with the date.
- `feature design`: `[Feature Design] <Title>`.
- `procedure`: `How to <do the thing>`.
- `knowledge`: the plain topic name, no prefix.

## Conventions

Two sets, by type.

### Evergreen: `knowledge` + `procedure`

- **Authoritative, present tense.** Describe how the system works *now*. No
  evolution narration: drop "historically / previously / used to / after MR X".
- **Behavior first, gotchas second.** Lead with how it works; put traps under a
  `Constraints` / `Gotchas` section. Never open with the bug.
- **Facts stand alone.** No provenance breadcrumbs in prose: drop ticket/MR/
  commit IDs and one-off measurements. Demote evidence to a `Verified: file:line`
  citation, or link the related `report` note.
- **Knowledge is not proposal.** Document only what exists. Anything proposed
  belongs in a `feature design` note, not here.
- **Delete on resolution:** no "Verified and closed" or history sections.

### Not evergreen: `report` + `feature design`

Both are anchored to a moment, so the present-tense / no-history rules above do
not apply to them.

- A `report` is historical: **past tense and narrative are fine**, it is dated,
  and it tells what happened.
- A `feature design` is forward-looking: **future and conditional are fine**
  ("would", "the change adds"). State the current behavior it changes and why,
  then the proposal. Still verified against code: the *current* behavior it
  builds on cites `path/file.ext:line`.
- If either surfaces an evergreen fact, also file that fact as a `knowledge`
  note (one fact, one home) and link between them.

### Shared: all types

- **Verified against code.** Business rules cite `path/file.ext:line`.
- **Cite raw sources, never copy them wholesale.** The config's sources, the
  source code and API docs are cited, not pasted in.
- **One fact, one home.** Don't restate a fact across notes; link its canonical
  page inline at first mention (Notion @mention / page link).
- **Language:** notes are written in the config's language (English if unset),
  whatever language the chat uses.
- **Secrets** live in the config's secrets store, never in a note.

## Example: a `knowledge` note

- `Name`: Session token caching
- `Summary`: how the API caches and refreshes session tokens
- `Type`: knowledge
- `Tags`: `["authentication", "security"]`
- `Area`: `["api"]`

Body (illustrative):

> The API authenticates each request against a token cache refreshed from the
> identity service on a fixed interval (`Verified: api/auth/cache.py:NN`).
>
> **Constraints:** a revoked token keeps authenticating until the next refresh;
> expect a short overlap after revocation.

## Diagrams

Architecture, request-path, and lifecycle notes benefit from a diagram; skip it
for simple notes. Use a fenced code block with language `mermaid`; Notion
renders it natively. The diagram must match the prose: same component names,
same flows. Never draw structure the note doesn't describe.

- Keep it legible: label edges, group per-node/per-service components in
  `subgraph`s, prefer one focused diagram over a sprawling one.
- A new Mermaid block shows in Notion's Split view (code + diagram). Switching it
  to Preview-only is a manual per-block toggle in Notion (top-right of the
  block), not settable via the MCP, so flag it on handoff.
- The diagram is body content: include it in the propose-and-approve preview.

## Index

The database's **Views** (All / Knowledge / Procedures / Feature Designs /
Reports) are the index, maintained by Notion. There is no manual index step.

## Operations

- **Setup.** When there is no config, or the user asks to set up the wiki.
  1. Ask the user: adopt an existing database, or create a new one (then the
     parent Notion page and the database name); the shared area; the initial
     `Area` options; the secrets store; the language; the sources.
  2. Existing database: `notion-fetch` it and compare it with the properties
     above. Propose the missing properties or `Type` options as one
     `notion-update-data-source` change and wait for the OK. Never rename or
     drop what is already there.
  3. New database: propose the schema (the properties above, `Type` options
     `knowledge`, `procedure`, `report`, `feature design`, the initial `Area`
     options) and wait for the OK, then create it with `notion-create-database`
     under the parent page. Add the Views (All, plus one per `Type` filtered on
     it) with `notion-create-view`; any view the MCP cannot create, list for
     the user to add by hand.
  4. `notion-fetch` the database to read its page id and its data source
     (`collection://...`).
  5. Propose `${CLAUDE_PROJECT_DIR}/.claude/wiki.md` in this format, wait for the
     OK, then write it. Suggest committing it so the whole team shares the same
     wiki.

     ```markdown
     - Database: <name>
     - Page id: <id>
     - Data source: collection://<id>
     - Shared area: <area>
     - Secrets store: <store>
     - Language: <language>
     - Sources: <systems notes cite>
     ```
- **Ingest.** Read the source; strip any credentials, tokens, or PII before
  carrying anything over (cite the source, never paste secrets, which live in
  the config's secrets store); verify claims against code with citations; set
  `Name` / `Summary` / `Type` / `Tags` / `Area`. Before setting
  `Type`/`Tags`/`Area`, fetch the data source for the current options
  (`notion-fetch` on the config's `collection://...`); values follow the schema
  (`Tags` and `Area` are JSON-array strings). A `Type`/`Tag`/`Area` that is not
  already an option is rejected on create; adding one is a separate
  `notion-update-data-source` change to the shared base and needs its own human
  OK. **Propose the note: show the properties block and the full body as a
  preview, then wait for the OK** (the base is shared and team-facing). On
  approval, create the page with `notion-create-pages`, or update an existing
  one (find it via `notion-search`, then `notion-update-page`); link the related
  page at first mention. An incident/investigation becomes a `report`; a
  proposal for something not built yet becomes a `feature design`; a durable
  fact either one surfaces also becomes a `knowledge` note.
- **Query.** Reach for the wiki before digging into code or running commands: a
  documented business rule, runbook, or incident often answers the question
  faster. Search first (`notion-search` scoped to the database, or
  `notion-query-data-sources` SQL over the data source, or a View). Scope by
  `Area`: the area in play plus the config's shared area. Read the titles first
  and open a page only when it is relevant; escalate to cross-area or broader
  searches only on demand. Open pages with `notion-fetch`, synthesize with
  citations to pages and code. File valuable answers back as a `knowledge` note
  (through the same propose-and-approve gate); explorations compound.
- **Lint.** Health-check via `notion-query-data-sources`: notes missing
  `Summary` or `Type`; an area-specific note missing `Area`; non-authoritative
  noise in `knowledge`/`procedure` (past-tense narration, provenance
  breadcrumbs, bug-first articles, a proposal filed as `knowledge` instead of
  `feature design`); a Name that breaks its type's prefix convention; a shipped
  `feature design` never rewritten as `knowledge`; contradictions; stale claims
  vs current code; duplicates (same fact in two pages). Output a grouped list of
  issues (page, problem, suggested fix); fixes are writes, so they go through
  Ingest's propose-and-approve gate.
