# Paywall revisit

**Type:** map  
**Status:** resolved  
**Opened:** 2026-08-23  
**Closed:** 2026-08-24  

## Destination

_Confirmed 2026-08-24, narrowed: the exception plus the language that must change to match._ A decided feature matrix for the single unlock (`com.luminous.diction.full`): what is free, what is paid, and any per-game exceptions — recorded as an ADR under `docs/adr/` and a spec under `docs/tickets/impl/specs/`, ready to slice into build tickets. The effort was opened with one concrete change in mind (free speak-to-command in the bundled game); whatever else "revisit how the paywall works" covers is fog until grilled.

## Notes

- Domain: StoreKit 2, one non-consumable, no server. `StoreManager` (`Diction/Diction/Store/StoreManager.swift`) is the live entitlement; `DemoPolicy` (`Diction/Diction/Models/DemoPolicy.swift`) is the one pure home for free-vs-unlocked rules and the unit-test target. Keep it that way — a gate that reads the story must still be expressible as a pure function there.
- Prior decision, local-only (`nocommit/docs/2026-06-07-voice-paywall-design.md`, not in git): the paywall was moved *off games and onto features* — every game plays free with Apple voices; the unlock buys neural (Kokoro) narration and speak-to-command. Standing preferences from that design: one combined IAP, not two; toggles are opt-in after purchase, never auto-flipped; the wake-word field is ungated.
- Bundled game identity: `StoryFile.Source.bundled` and the single `devours` entry in `StoryFileManager.bundledGames`.
- Skills every session should consult: `/grilling`, `/domain-modeling` (there is no `CONTEXT.md` yet — the first resolved ticket should seed it with the paywall vocabulary), `storekit` for anything touching entitlement plumbing.
- Screenshots of the current paywall surfaces are under `nocommit/iap_*.png`.

## Decisions so far

<!-- the index — one line per closed ticket: enough to judge relevance, then zoom the link for the detail the ticket holds -->

- [Free speak-to-command in All Things Devours](issues/01-free-voice-input-in-all-things-devours.md) — yes: voice commands are free to try in any bundled game (`Source.bundled`), neural stays locked, "Play using my voice" is an ungated preference, wake word ungated, paywall/settings/about copy says so. [ADR 0001](../../adr/0001-paywall-gates-voice-features-with-free-to-try-voice-commands.md) · [spec](../impl/specs/free-to-try-voice-commands.md) · `CONTEXT.md` seeded.

**The way is clear** — no open tickets, no fog. Build from the spec.

## Not yet specified

<!-- see "Fog of war": in-scope fog you can't ticket yet; graduates as the frontier advances -->

_(empty — the broader "revisit" fog was resolved at the first grilling: the effort is the exception plus matching language; see Out of scope.)_

## Out of scope

<!-- see "Out of scope": work ruled beyond the destination; closed, never graduates -->

- **Price** — an App Store Connect knob, not a code decision (Q1 of the first grilling).
- **Two IAPs instead of one** — decided against in June 2026; nothing here reopens it.
- **Promo-placement changes beyond copy** — `LibraryUnlockRow` stays as it is; only `PaywallView`, `UnlockSettingsRow`, the Settings toggle footer, and `AboutPane` get the free-to-try sentence.
- **Neural narration free in the bundled game** — rejected in [ADR 0001](../../adr/0001-paywall-gates-voice-features-with-free-to-try-voice-commands.md); would be a fresh effort.
- **Trimming `SystemVoiceCatalog.supportedLanguageCodes`** (fr/es survive only because of a stale comment about bundled games that don't exist) — a voice-picker question, not a paywall one. The spec fixes the comment only.
