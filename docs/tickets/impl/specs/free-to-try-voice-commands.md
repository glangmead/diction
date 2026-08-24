# Free-to-try voice commands

**From:** [Free speak-to-command in All Things Devours](../../paywall/issues/01-free-voice-input-in-all-things-devours.md) · [ADR 0001](../../../adr/0001-paywall-gates-voice-features-with-free-to-try-voice-commands.md)  
**Vocabulary:** [CONTEXT.md](../../../../CONTEXT.md) § Paywall  
**Written:** 2026-08-24  
**Status:** ready to slice  

## Summary

Voice commands work without the paywall in any **bundled game** (`StoryFile.Source.bundled`). They stay locked in imported and downloaded games; neural narration stays locked everywhere. "Play using my voice" becomes a plain preference for every user; the gate is applied in the game, the only place that knows the story. Every surface that pitches voice commands says they are free to try in All Things Devours.

## Behaviour

| Scenario | Expected |
|---|---|
| Free, preference on, opens All Things Devours | Auto-listens on appear, as for an owner. Mic-permission prompt on first use. |
| Free, preference on, opens an imported or downloaded game | Grey `mic.slash` paywall button; no listening; preference untouched. |
| Free, in Devours, taps the mic | Flips the preference (mirrors to Settings) like an owner; press-and-hold input menu available. |
| Free, leaves Devours for another game, comes back | Locked in the other game; listening resumes in Devours from the preference. |
| Refund mid-session in Devours | Voice commands unaffected — not entitlement-driven. Neural falls back to the accessibility voice as today. |
| Owner | Unchanged everywhere. |
| Free, wake word | Works in Devours ("game, stop"); the field is ungated. |
| Free, opens the paywall (any entry point) | Sees, before the Unlock button, that voice commands are free to try in All Things Devours. |

## Policy — `Models/DemoPolicy.swift`

Replace `voiceInputUnlocked(fullVersion:)`:

```swift
/// Voice commands require the unlock — except in a bundled game, where they are
/// free to try (ADR 0001). Keyed on the source, not the game's name, so a second
/// bundled game gets the same treatment without touching this file.
static func voiceCommandsAllowed(fullVersion: Bool, source: StoryFile.Source) -> Bool {
  fullVersion || source == .bundled
}
```

`neuralVoiceUnlocked` and `usesNeuralVoice` are untouched. Update the type's doc comment: the non-voice experience is free; the unlock buys neural narration and voice commands; voice commands are free to try in a bundled game.

## Plumbing

**`Views/GameView.swift`** (`storyFile: StoryFile` is already in scope; `coordinator.useEntitlement(store)` is called at line 126)

- Add a computed `voiceCommandsAllowed: Bool` = `DemoPolicy.voiceCommandsAllowed(fullVersion: store.isFullVersion, source: storyFile.source)`. Read it in `body` (it depends on the `@Observable` store — see the CLAUDE.md gotcha on reading tracked properties inside `body`).
- `micToggle`: branch on `voiceCommandsAllowed` instead of `store.isFullVersion`. Locked-branch accessibility hint becomes: "Opens the in-app purchase to play by speaking your commands. Free to try in All Things Devours."
- After `useEntitlement(store)`, hand the coordinator the gate: `coordinator.useVoiceCommandGate { [weak store] in DemoPolicy.voiceCommandsAllowed(fullVersion: store?.isFullVersion ?? false, source: storyFile.source) }` (capture the `Source` value, not the view).
- `.onChange(of: voiceInput)` is unchanged: it still calls `setListening(enabled)`; the coordinator refuses when the gate says no (below). One choke point.

**`Voice/VoiceCoordinator.swift`**

- Add `private var voiceCommandsAllowed: @MainActor () -> Bool = { false }` and `func useVoiceCommandGate(_ allowed: @escaping @MainActor () -> Bool)`.
- `startOnAppear`: `if voiceCommandsAllowed() && UserDefaults.standard.bool(forKey: "voiceInput")` — replaces `isFullVersion()` there. `isFullVersion` stays for the synthesizer (neural).
- `setListening(true)`: early-return (leaving `isListening == false`) unless `voiceCommandsAllowed()`. This makes the Settings toggle safe to flip from inside a locked game.
- Fix the two comments that say listening is owner-only (the `isFullVersion` doc comment and the `startOnAppear` doc comment).

**`Views/VoiceSettingsSection.swift`**

- "Play using my voice" becomes a plain `Toggle` for everyone (drop `gatedToggle` for this row; `gatedToggle` remains for "Use neural voice"). Keep the accessibility hint "Speak your commands instead of typing."
- Below it, **free state only** (`!store.isFullVersion`), a footnote in the same style as the wake-word explanation: "Free to try in All Things Devours. Unlock to play every game by voice."
- Update the header comment ("Both voice features default off — they're the paid unlock") to mention the exception.

**`Views/PaywallView.swift`**

- Between `featureList` and `actions`, a centred secondary-style sentence: "Want to try voice commands first? They're free in All Things Devours." Plain `Text` (VoiceOver reads it in order, before the purchase button). No button, no navigation. Shown unconditionally — the paywall only appears in the free state and dismisses on purchase.

**`Views/UnlockSettingsRow.swift`**

- Footer becomes: "Unlock to narrate with premium neural voices and to play by speaking your commands. Voice commands are free to try in All Things Devours."

**`Views/AboutPane.swift`** (line 78 already updated by the user)

- Line 78: "Acccessibility" → "Accessibility".
- Line 102: drop the `_(Full version)_` marker: "* Mute the mic in the top toolbar to stop giving voice commands."

**`Views/LibraryUnlockRow.swift`** — no change (decided). Drive-by worth a separate chore: `prompt` has a dead `if let price` branch that returns the same string on both paths.

**`Voice/SystemVoiceCatalog.swift`**

- Rewrite the `supportedLanguageCodes` comment so it no longer claims bundled French and Spanish games exist. Do not change the set; that is a voice-picker question, out of scope here.

**`README.md`** lines 22–23 — append: "Voice commands are free to try in the bundled game."

**`Resources/`** — `minizork.z3` and `zdungeon.z5` were removed on 2026-08-24 (no permission to distribute; they were never in `bundledGames`). Nothing else references them.

## Tests

**`DictionTests/DemoPolicyTests.swift`** — replace `voiceInputGate` with the matrix:

| `fullVersion` | `source` | allowed |
|---|---|---|
| false | `.bundled` | true |
| false | `.imported` | false |
| false | `.downloaded` | false |
| true | `.bundled` | true |
| true | `.imported` | true |
| true | `.downloaded` | true |

Neural rows unchanged.

Behaviour rows above are verified on the simulator (`ios-simulator-skill`) in the free state: Devours listens, an imported game shows the paywall mic, the Settings toggle is live with its footer, the paywall shows the free-to-try line above Unlock. Run `swift-accessibility-skill` over every touched view.

## Suggested slices

1. Policy + plumbing + tests: `DemoPolicy`, `DemoPolicyTests`, `GameView`, `VoiceCoordinator`.
2. Copy and Settings: `VoiceSettingsSection`, `PaywallView`, `UnlockSettingsRow`, `AboutPane`.
3. Comment/README cleanups: `SystemVoiceCatalog`, `README.md`, `DemoPolicy` doc comment (can ride with slice 1).

## Out of scope

Price; a second IAP; `LibraryUnlockRow`; neural narration in the bundled game; trimming the voice-picker language set; navigating from the paywall into Devours; App Store Connect description (manual, not in the repo).
