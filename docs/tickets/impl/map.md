# Implementation

**Type:** map  
**Status:** open  
**Opened:** 2026-08-23  

## Destination

One flat, global list of implementation tickets for Diction. Decisions are made elsewhere (wayfinder maps under `docs/tickets/<effort>/`, ADRs under `docs/adr/`); tickets here only build what those decided. A ticket is done when its code is on `main` with tests.

## Notes

- Layout and header fields: see [issue-tracker.md](../../agents/issue-tracker.md) § Implementation tickets.
- One spec per feature under [specs/](specs/); every ticket names its spec and the decision it implements.
- Skills: `/tdd` for the work; `swiftui-pro` and `swift-accessibility-skill` on any view; `/code-review` against the spec before resolving.
- `Blocked by` is global across features — a UI ticket may wait on an engine ticket from another feature.

## Specs

<!-- one bullet per spec under specs/, linking the map and ADRs it came from -->

- [Free-to-try voice commands](specs/free-to-try-voice-commands.md) — from [Paywall revisit](../paywall/map.md) and [ADR 0001](../../adr/0001-paywall-gates-voice-features-with-free-to-try-voice-commands.md). Not yet sliced.

## Decisions so far

<!-- not used: decisions live in the wayfinder maps -->

## Not yet specified

<!-- features decided but not yet written up as a spec here -->

## Out of scope
