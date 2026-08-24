# 01 — Free speak-to-command in All Things Devours

**Type:** grilling  
**Status:** resolved  
**Blocked by:** None  
**Assignee:** glangmead  
**Opened:** 2026-08-23  
**Closed:** 2026-08-24  

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

### glangmead — 2026-08-24

Grilled in two rounds (eight questions, then five). Facts surfaced on the way: `Resources/` shipped `minizork.z3` and `zdungeon.z5` unlisted in `bundledGames` (removed — no permission to distribute); the `SystemVoiceCatalog` comment about bundled French/Spanish games is stale; `GameView`'s `onChange(of: voiceInput)` drives the recognizer ungated, which is safe today only because free users cannot write the key.

## Answer

_glangmead — 2026-08-24_

**Yes.** Voice commands are free to try in any **bundled game** (`StoryFile.Source.bundled`), with no turn or time limit; they stay locked in imported and downloaded games. Neural narration stays locked everywhere. The principle after this change: **the paywall gates features, and a bundled game is where a free user tries voice commands** — recorded as [ADR 0001](../../../adr/0001-paywall-gates-voice-features-with-free-to-try-voice-commands.md). Vocabulary seeded in [CONTEXT.md](../../../../CONTEXT.md) § Paywall; the exception is called **free-to-try voice commands**.

Branch by branch:

1. **Goal** — try-before-you-buy on a game we vouch for, plus screenshots/previews and App Review without a sandbox purchase. Not a trial period.
2. **Feature** — voice commands only: mic in, accessibility voice out.
3. **Key** — `Source.bundled`, not the `devours` name. The rule survives a second bundled game with no `DemoPolicy` edit.
4. **Where the gate reads the story** — `DemoPolicy.voiceCommandsAllowed(fullVersion:source:)` returns `fullVersion || source == .bundled` (replaces `voiceInputUnlocked`). `GameView`, the only place with both store and story, computes it and hands it to `VoiceCoordinator` as the listening-gate closure; the synthesizer keeps the raw entitlement. "Play using my voice" becomes a real toggle for everyone — it is a preference, not a gate — with a free-state footer "Free to try in All Things Devours." The Settings ⇄ mic mirror is untouched.
5. **Discoverability** — `PaywallView` gets a sentence between the feature list and the Unlock button so a user who only wants to try does not buy by accident; `UnlockSettingsRow` footer and the Settings toggle footer say the same; `AboutPane` already says it (user's edit; drop the `(Full version)` marker on the mic tip and fix "Acccessibility"). `LibraryUnlockRow` unchanged. Inside Devours the live mic is the announcement.
6. **Wake word** — ungated; it is not a feature.
7. **Tests** — `DemoPolicyTests`: `(false, .bundled) → true`, `(false, .imported) → false`, `(false, .downloaded) → false`, `(true, any) → true`; neural rows unchanged.

Behaviour matrix (confirmed): free + preference on + Devours → auto-listens as for an owner; free + preference on + imported game → grey paywall mic, no listening, preference untouched; a free user's mic tap in Devours flips the global preference and mirrors to Settings; leaving for another game locks, returning resumes; refund mid-session leaves voice commands in Devours alone; owners unchanged; wake word works for free users in Devours.

Spec, ready to slice: [Free-to-try voice commands](../../impl/specs/free-to-try-voice-commands.md).

Scope rulings from Q1 (map updated): price, the one-IAP decision, and promo-placement changes beyond copy are out of scope.
