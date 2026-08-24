# 01 — Free speak-to-command in All Things Devours

**Type:** grilling  
**Status:** open  
**Blocked by:** None  
**Assignee:** —  
**Opened:** 2026-08-23  

## Question

Should speak-to-command ("Play with my voice") be free when the story being played is All Things Devours, the bundled game — while staying paid for every other game? And if so, what exactly is the rule, where does it read the story, and how does the UI explain it?

The June 2026 paywall design deliberately moved the gate *off games and onto features* (`nocommit/docs/2026-06-07-voice-paywall-design.md`). This change puts a game-keyed rule back into `DemoPolicy`. That is not necessarily wrong — a demo tier on a game we ship is a different thing from locking imported games — but the grilling should say which principle now holds, because the ADR will have to.

Branches to resolve:

1. **What the exception buys.** Try-before-you-buy of the headline feature on a game we control? Conversion? Reviewer goodwill? Name the goal, since it decides the scope of the next branches.
2. **Which voice feature.** "Voice commands" reads as speak-to-command only; neural narration stays locked in Devours, so a free Devours session is mic in, Apple voice out. Confirm, or widen.
3. **What the rule keys on.** `StoryFile.Source == .bundled` (any bundled game) or the specific `devours` entry in `StoryFileManager.bundledGames`? Today they're the same one game. `SystemVoiceCatalog.supportedLanguageCodes` has a comment about bundled French and Spanish games that don't exist in the list — stale, or does the exception need to survive more bundled games?
4. **Where the gate reads the story.** `DemoPolicy.voiceInputUnlocked(fullVersion:)` is story-blind. Its consumers:
   - `GameView.micToggle` (`Diction/Diction/Views/GameView.swift:243`) keys on `store.isFullVersion` and has the story in hand.
   - `VoiceCoordinator.startOnAppear` (`Diction/Diction/Voice/VoiceCoordinator.swift:173`) auto-listens on `isFullVersion() && voiceInput`; it gets the entitlement as a closure and does not know the story.
   - `VoiceSettingsSection.gatedToggle` (`Diction/Diction/Views/VoiceSettingsSection.swift:117`) renders "Play with my voice" as a lock for free users. Settings has no story context. Does a free user now get a real toggle there (it applies in Devours), the lock, or a toggle with a footer? The `voiceInput` mirror (Settings toggle ⇄ in-game mic, one `@AppStorage` key) was designed around one global truth; a per-game exception strains it.
5. **Discoverability.** How a free user learns voice works in Devours and nowhere else: `PaywallView` subtitle/bullets, the `LibraryUnlockRow` prompt, the `UnlockSettingsRow` footer, and the locked mic tap in another game — does that paywall say "Try it free in All Things Devours"?
6. **Wake word.** Left ungated in June because ASR was locked anyway. With ASR free in Devours the field is live for free users. Fine, or gate it?
7. **Tests.** `DemoPolicyTests` gains a story axis. State the matrix (full × bundled) the pure function must satisfy.

Not in question: refund/lapse handling — the exception is not entitlement-driven, so `usesNeuralVoice` and the re-lock path are untouched.

Resolution should land as an ADR (`docs/adr/`) stating the paywall principle after this change, and seed `CONTEXT.md` with the terms *unlock*, *speak-to-command*, *neural narration*, *bundled game*, and whatever the exception ends up being called.

## Comments
