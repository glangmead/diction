# 01 — Free-to-try voice commands in the bundled game

**Type:** feature  
**Status:** claimed  
**Blocked by:** None  
**From:** [Free speak-to-command in All Things Devours](../../paywall/issues/01-free-voice-input-in-all-things-devours.md) · [ADR 0001](../../../adr/0001-paywall-gates-voice-features-with-free-to-try-voice-commands.md)  
**Spec:** [Free-to-try voice commands](../specs/free-to-try-voice-commands.md)  
**Assignee:** glangmead  
**Opened:** 2026-08-24  

## Task

Implement the whole of the [Free-to-try voice commands](../specs/free-to-try-voice-commands.md) spec in one change: voice commands work without the paywall in any bundled game (`StoryFile.Source.bundled`), stay locked in imported and downloaded games, neural narration stays locked everywhere, "Play using my voice" becomes a plain preference for every user, and every surface that pitches voice commands says they are free to try in All Things Devours. Vocabulary: [CONTEXT.md](../../../../CONTEXT.md) § Paywall.

### Changes

**Policy and plumbing**
- `Models/DemoPolicy.swift` — replace `voiceInputUnlocked(fullVersion:)` with `voiceCommandsAllowed(fullVersion:source:)` returning `fullVersion || source == .bundled`; update the type's doc comment. `neuralVoiceUnlocked` and `usesNeuralVoice` untouched.
- `Views/GameView.swift` — computed `voiceCommandsAllowed` from `store.isFullVersion` and `storyFile.source`, read in `body`; `micToggle` branches on it instead of `store.isFullVersion`; locked-branch accessibility hint gains "Free to try in All Things Devours."; after `useEntitlement(store)`, hand the coordinator the gate closure (capture the `Source` value, not the view). `.onChange(of: voiceInput)` unchanged.
- `Voice/VoiceCoordinator.swift` — new `useVoiceCommandGate(_:)` storing a `@MainActor () -> Bool`; `startOnAppear` auto-listens on `voiceCommandsAllowed() && voiceInput`; `setListening(true)` early-returns unless the gate allows (the one choke point, so the now-live Settings toggle is safe inside a locked game); `isFullVersion` stays for the synthesizer; fix the two "owner-only" comments.

**Copy and Settings**
- `Views/VoiceSettingsSection.swift` — "Play using my voice" is a plain `Toggle` for everyone (`gatedToggle` remains for "Use neural voice" only); below it, free state only, a footnote in the wake-word-explanation style: "Free to try in All Things Devours. Unlock to play every game by voice."; update the header comment.
- `Views/PaywallView.swift` — between `featureList` and `actions`, a centred secondary `Text`: "Want to try voice commands first? They're free in All Things Devours." No button, no navigation.
- `Views/UnlockSettingsRow.swift` — footer: "Unlock to narrate with premium neural voices and to play by speaking your commands. Voice commands are free to try in All Things Devours."
- `Views/AboutPane.swift` — "Acccessibility" → "Accessibility" (line 78); drop the `_(Full version)_` marker on the mic tip (line 102): "* Mute the mic in the top toolbar to stop giving voice commands."
- `Views/LibraryUnlockRow.swift` — no change.

**Cleanups**
- `Voice/SystemVoiceCatalog.swift` — rewrite the `supportedLanguageCodes` comment so it no longer claims bundled French and Spanish games exist. Do not change the set.
- `README.md` lines 22–23 — append "Voice commands are free to try in the bundled game."
- `Resources/minizork.z3` and `zdungeon.z5` are already deleted in the working tree (2026-08-24); confirm the deletion is part of the change.

### Tests

- `DictionTests/DemoPolicyTests.swift` — replace `voiceInputGate` with the full matrix: `(false, .bundled) → true`, `(false, .imported) → false`, `(false, .downloaded) → false`, `(true, .bundled/.imported/.downloaded) → true`. Neural rows unchanged.
- All existing tests pass (`xcodebuild test` through `xcsift`).
- `swiftlint` clean on every touched file.

### Acceptance (free state, on the simulator via `ios-simulator-skill`)

1. Open All Things Devours with "Play using my voice" on → listening starts on appear; the mic toolbar button is the live `Menu` with the input picker.
2. Open an imported game with the same preference → grey `mic.slash` paywall button, no listening; the preference is still on in Settings.
3. Tap the mic in Devours → the preference flips and Settings mirrors it.
4. Settings → Voice: "Play using my voice" is a real toggle with the free-to-try footer beneath it; "Use neural voice" is still the locked row.
5. Open the paywall from any entry point → the free-to-try sentence sits above the Unlock button.
6. Flip "Play using my voice" on from Settings while inside an imported game → no listening starts.
7. Owner (StoreKit test purchase) → everything behaves as before; the Settings footer is absent.
8. `swift-accessibility-skill` review of every touched view: VoiceOver reads the paywall sentence before the purchase button; the locked mic's hint mentions the free-to-try game.

## Comments

## Answer
