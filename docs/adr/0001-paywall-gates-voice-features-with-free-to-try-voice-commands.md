# Paywall gates voice features, with voice commands free to try in bundled games

**Status:** accepted — 2026-08-24

Diction's single one-time purchase (`com.luminous.diction.full`) gates the two voice features — neural narration and voice commands — and nothing else: any game plays free with the accessibility voice (the June 2026 decision that moved the paywall off games and onto features). This ADR adds one exception: **voice commands are free to try in a bundled game**, keyed on `StoryFile.Source.bundled`, not on the game's name. Neural narration stays locked everywhere. The goal is try-before-you-buy on a game we vouch for — with screenshots, App Store previews, and App Review without a sandbox purchase as side effects — so the exception has no turn or time limit.

## Considered options

- **Both voice features free in the bundled game.** Rejected: neural narration is story-blind in three places (the synthesizer, the library warm-up, the Settings toggle), so this roughly doubles the plumbing and gives free users a Kokoro cold start on entering the game; it is also the feature with the higher perceived value, so leaving it locked keeps the paywall pitch meaningful.
- **Key the exception to the `devours` entry by name.** Rejected: "bundled game" is the concept — a game we ship and vouch for — and a second bundled game should get the same treatment without touching `DemoPolicy`.
- **Gate the wake-word field now that free users can reach speech recognition.** Rejected: it configures how the app is addressed ("game, stop"); it is not a feature.

## Consequences

- `DemoPolicy` gains a story axis for voice commands only. The narration rule and refund/lapse handling are unchanged: the exception is not entitlement-driven.
- "Play using my voice" is a preference, not a gate. Free users get a real toggle; the gate is applied where the story is known (the game). A free user's choice in the bundled game persists globally and takes effect in every game the moment they unlock.
- The June rationale for leaving the wake word ungated ("inert for locked users") no longer holds; the standing reason is that it is not a paid feature.
- Every surface that pitches voice commands must say they are free to try in All Things Devours, or the pitch misleads — including the paywall itself, so a user who only wants to try does not buy by accident.
- Terms: see [CONTEXT.md](../../CONTEXT.md) § Paywall. "Paywall" is the internal name; user-facing copy says "Unlock".
