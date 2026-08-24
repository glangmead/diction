# Issue tracker: Local Markdown

Issues, specs, and wayfinder maps for this repo live as markdown files under `docs/tickets/`, tracked in git. The repo's GitHub Issues are a public intake for app users only: skills never create, edit, or close GitHub issues. When a GitHub issue is worth working, import it as a ticket in the format below with an `**Imported from:**` link to the issue, and treat the ticket as the source of truth from then on.

`bin/tickets` renders the tracker in the terminal: frontier by default, `-a` for resolved/closed, `--fog` for the map's fog, `-n NN` to print one ticket.

## Layout

- One effort or feature per directory: `docs/tickets/<effort-slug>/`
- A wayfinder effort has `map.md` plus `issues/NN-<slug>.md`; a to-tickets feature has `spec.md` plus `issues/NN-<slug>.md`
- One file per ticket — never a single combined tickets file
- `NN` is the ticket's id within its effort. New efforts number from `01`

## Ticket file format

Header block first, then the body. `bin/tickets` and the wayfinder frontier query parse these fields, so keep the names and the two-trailing-space line breaks:

```markdown
# NN — <Title>

**Type:** research | prototype | grilling | task  
**Status:** open | claimed | resolved | closed  
**Blocked by:** [NN — <Title>](NN-<slug>.md), [NN — <Title>](NN-<slug>.md)   ← or `None`
**Assignee:** <login> or —  
**Opened:** YYYY-MM-DD  
**Closed:** YYYY-MM-DD   ← only once closed

## Question

<body>

## Comments

### <login> — YYYY-MM-DD

<comment>

## Answer

_<login> — YYYY-MM-DD_

<resolution>
```

- `Status:` carries the wayfinder states above; for triage tickets it carries the role strings in [triage-labels.md](triage-labels.md) instead
- A ticket closed without a decision uses `Status: closed` and a `## Closed without resolution` heading in place of `## Answer`
- An imported GitHub issue adds `**Imported from:** <issue URL>  ` to the header block
- Refer to tickets by name, linked: `[Title](NN-slug.md)` between siblings, `[Title](issues/NN-slug.md)` from `map.md`, `[Title](../map.md)` up to the map. From elsewhere in `docs/`, link relatively into `tickets/<effort>/…`
- Comments and conversation history append under `## Comments`

## When a skill says "publish to the issue tracker"

Create a new file under `docs/tickets/<effort-slug>/issues/` (creating the directory if needed).

## When a skill says "fetch the relevant ticket"

Read the file. The user will normally pass the path or the ticket number; `bin/tickets -n NN` prints it.

## Implementation tickets

Building what a wayfinder map or ADR decided. One global effort, `docs/tickets/impl/`, so `Blocked by` can cross features:

- `docs/tickets/impl/map.md` — title and notes only; decisions stay in the wayfinder maps.
- `docs/tickets/impl/specs/<feature>.md` — one spec per feature, written from the map's decisions and ADRs before its tickets are sliced.
- `docs/tickets/impl/issues/NN-<slug>.md` — the standard ticket format plus two header lines after `**Blocked by:**`:

```markdown
**From:** [<decision ticket or ADR title>](../../<effort>/issues/NN-<slug>.md)  
**Spec:** [<feature>](../specs/<feature>.md)  
```

- `**Type:**` is one of `feature | bug | chore | test`.
- `**Status:**` uses the triage roles from [triage-labels.md](triage-labels.md) while open (`ready-for-agent`, `ready-for-human`, `needs-info`), `claimed` while being worked, and `resolved` / `wontfix` when done. `bin/tickets` treats anything not done as open.
- The body is `## Task` (what to build, acceptance criteria, test list) instead of `## Question`; the resolution under `## Answer` names the commit(s).

## Wayfinding operations

Used by `/wayfinder`. The **map** is a file with one **child** file per ticket.

- **Map**: `docs/tickets/<effort>/map.md` — header (`**Type:** map`, `**Status:**`, `**Opened:**`) then Destination / Notes / Decisions-so-far / Not yet specified / Out of scope.
- **Child ticket**: `docs/tickets/<effort>/issues/NN-<slug>.md` in the format above, with the question in the body.
- **Blocking**: the `**Blocked by:**` line. A ticket is unblocked when every ticket it lists has `Status: resolved` or `closed`.
- **Frontier**: the open, unblocked, unassigned tickets; first by number wins. `bin/tickets` shows it.
- **Claim**: set `**Status:** claimed` and `**Assignee:**`, save, before any work.
- **Resolve**: append the answer under `## Answer`, set `**Status:** resolved` and `**Closed:**`, then append a one-line gist plus link to the map's Decisions-so-far.
- **Rule out of scope**: set `**Status:** closed`, record why under `## Closed without resolution`, and add a line to the map's Out of scope.
- **Commit**: never. Ticket and map updates, `CONTEXT.md`, ADRs, and findings under `docs/` are left as working-tree changes, the same as code — the user reviews, stages, and commits them.
