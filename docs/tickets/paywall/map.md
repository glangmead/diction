# Paywall revisit

**Type:** map  
**Status:** open  
**Opened:** 2026-08-23  

## Destination

_Provisional — confirm at the first grilling._ A decided feature matrix for the single unlock (`com.luminous.diction.full`): what is free, what is paid, and any per-game exceptions — recorded as an ADR under `docs/adr/` and a spec under `docs/tickets/impl/specs/`, ready to slice into build tickets. The effort was opened with one concrete change in mind (free speak-to-command in the bundled game); whatever else "revisit how the paywall works" covers is fog until grilled.

## Notes

- Domain: StoreKit 2, one non-consumable, no server. `StoreManager` (`Diction/Diction/Store/StoreManager.swift`) is the live entitlement; `DemoPolicy` (`Diction/Diction/Models/DemoPolicy.swift`) is the one pure home for free-vs-unlocked rules and the unit-test target. Keep it that way — a gate that reads the story must still be expressible as a pure function there.
- Prior decision, local-only (`nocommit/docs/2026-06-07-voice-paywall-design.md`, not in git): the paywall was moved *off games and onto features* — every game plays free with Apple voices; the unlock buys neural (Kokoro) narration and speak-to-command. Standing preferences from that design: one combined IAP, not two; toggles are opt-in after purchase, never auto-flipped; the wake-word field is ungated.
- Bundled game identity: `StoryFile.Source.bundled` and the single `devours` entry in `StoryFileManager.bundledGames`.
- Skills every session should consult: `/grilling`, `/domain-modeling` (there is no `CONTEXT.md` yet — the first resolved ticket should seed it with the paywall vocabulary), `storekit` for anything touching entitlement plumbing.
- Screenshots of the current paywall surfaces are under `nocommit/iap_*.png`.

## Decisions so far

<!-- the index — one line per closed ticket: enough to judge relevance, then zoom the link for the detail the ticket holds -->

## Not yet specified

<!-- see "Fog of war": in-scope fog you can't ticket yet; graduates as the frontier advances -->

- The rest of "revisit how the paywall works": the user named one exception but opened the effort more broadly. Whether the price, what the unlock covers, the promo placements (library row, settings row, in-game mic), or the one-IAP decision are also on the table is unknown until the first grilling — expect it to graduate into several tickets or none.

## Out of scope

<!-- see "Out of scope": work ruled beyond the destination; closed, never graduates -->
