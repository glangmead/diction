# 02 — Narration is near-mute after the mic is turned off

**Type:** bug  
**Status:** resolved  
**Blocked by:** None  
**From:** bug report by glangmead, 2026-08-24 (on-device, Apple TTS); introduced by commit `f2ccb42` (free narration with the mic off)  
**Spec:** None — bug; the fix is specified below  
**Assignee:** glangmead  
**Opened:** 2026-08-24  
**Closed:** 2026-08-24  

## Task

### Symptom

On device, with Apple TTS (`AVSpeechSynthesizer`, not Kokoro):

- Mic **on** → narration plays at full volume from the bottom speaker. Correct.
- Mic **off** (after having been on) → narration is almost inaudible. The system volume HUD shows no change; the long-press readout under the route button says "Output: Speaker", and it *is* the speaker — both the bottom speaker and the earpiece speaker carry it faintly, so at first it sounds like a receiver route. It isn't.
- Toggling the mic button moves it back and forth every time, so it's state-dependent, not a stuck one-off.

### Diagnosis

The recognizer leaves the shared `AVAudioSession` in `.playAndRecord` when it stops, and the synthesizer then reuses that leftover session for narration.

1. Mic on → `SpeechRecognizer.startEngine()` (`Diction/Diction/Voice/SpeechRecognizer.swift`, the `setCategory` at ~line 141) sets `.playAndRecord`, mode `.default`, options `[.duckOthers, .defaultToSpeaker]` from `ListeningSessionConfig`, activates, and enables voice-processing I/O on the engine's input node. Narration is loud because VPIO's speaker path is live.
2. Mic off → `SpeechRecognizer.stopContinuous()` (~line 122) stops the engine and calls `setActive(false, options: .notifyOthersOnDeactivation)` but never changes the category. The session is now inactive but still `.playAndRecord` + those options.
3. Narration → `SpeechSynthesizer.activatePlaybackSession()` (`Diction/Diction/Voice/SpeechSynthesizer.swift`, ~line 189) treats `.playAndRecord` as "already compatible", skips `setCategory`, and calls `setActive(true)`. `AVSpeechSynthesizer` (`usesApplicationAudioSession` default `true`) renders under a `.playAndRecord` session that has no I/O unit behind it → near-mute. `KokoroSpeechEngine.ensureSessionForPlayback()` has the identical check but is only active in audition (`managesSession`), so Kokoro in-game is unaffected only because it never reaches it; it will inherit the same problem if that changes.

Evidence gathered:

- A throwaway simulator test (deleted, not committed) drove the exact sequence — `setCategory(.playAndRecord, .default, [.duckOthers, .defaultToSpeaker])` → `setActive(true)` → `inputNode.setVoiceProcessingEnabled(true)` → `engine.start()` / `stop()` → `setActive(false)` → `setActive(true)` — dumping `category`/`mode`/`categoryOptions`/`currentRoute.outputs` after every step. All seven dumps were identical: `PlayAndRecord`, `Default`, options raw value `11` (`mixWithOthers|duckOthers|defaultToSpeaker`), output `Speaker`. So nothing in the chain rewrites the session's visible state; the only difference between the loud and near-mute cases is whether VPIO is running.
- Apple's docs on `.defaultToSpeaker`: "Route changes and interruptions don't reset this override. Only changing the audio session category resets this option." Consistent with the probe — and with the fix being a category change.
- Known iOS behaviour, [Apple Developer Forums thread 721535](https://developer.apple.com/forums/thread/721535): once voice-processing I/O has been used under `.playAndRecord`, other audio sources play at heavily reduced gain, the reduction persists after VPIO stops, and it's cleared by re-setting the category (`setCategory(session.category)`) or `overrideOutputAudioPort(.speaker)`. Reported across iOS 13–16, no Apple fix. The godot engine hit the same "ultra-low, sounds like a phone call" symptom under `.playAndRecord` ([godotengine/godot#88893](https://github.com/godotengine/godot/issues/88893)).
- History: `activatePlaybackSession()` was added in `f2ccb42` (paywall rework — Apple-voice narration became free with the mic off). Before that, narration only ever ran under the recognizer's live session, so the mic-off narration path is new and this bug came in with it. Ticket [01](01-free-to-try-voice-commands.md) did not touch it.

### Fix

Principle: only a live recognizer may own a `.playAndRecord` session. Narration with the mic off runs under a real `.playback` session, never a leftover one.

1. `SpeechRecognizer.stopContinuous()` — after `setActive(false, …)`, restore `setCategory(.playback, mode: .default, options: [.duckOthers])`. The recognizer put the session into `.playAndRecord`; it puts it back. This is the explicit category change that clears iOS's hidden post-VPIO gain state, and it also covers `VoiceCoordinator.tearDown()` so the next game doesn't inherit the stale category. `reconfigureListeningIfNeeded()` calls `stopContinuous()` then `startRecognizer()` back to back; the extra category flip there is harmless (one more route-change notification), but note it in a comment.
2. `SpeechSynthesizer.activatePlaybackSession()` and `KokoroSpeechEngine.ensureSessionForPlayback()` — drop `.playAndRecord` from the "compatible, leave it" check. After (1) the only time the synthesizer can see `.playAndRecord` is while the recognizer is listening, and then the recognizer owns the session and the synthesizer must not touch it. The cleanest shape: the synthesizer asks whether a recognizer is live (a `@MainActor () -> Bool` injected by `VoiceCoordinator`, in the style of `useVoiceCommandGate`) and only when it isn't, and the category isn't already `.playback`, sets `.playback`. Don't use `session.category == .playAndRecord` as the proxy for "recognizer is live" — that's the ambiguity that caused the bug.
3. Consider extracting the narration-only session parameters (`.playback`, `.default`, `[.duckOthers]`) into a small value next to `ListeningSessionConfig` so the two call sites and `stopContinuous()` share one definition rather than three copies of the same literal.

Side benefit: with the mic off the app no longer holds an active record-capable session, so the orange mic indicator can't linger.

### Tests

- Unit test (Swift Testing) for the restore-on-stop policy. `AVAudioSession` can't be asserted on the test host reliably, so put the policy behind a pure value: e.g. `ListeningSessionConfig`-style "what category/mode/options does the recognizer restore when it stops", and a `SpeechSynthesizer` test that `activatePlaybackSession` sets `.playback` when the recognizer-live closure returns `false` and leaves the session alone when it returns `true` (inject the session mutation as a closure if needed to keep it testable).
- Existing `ListeningSessionConfigTests` unchanged and passing.
- All tests pass via `xcodebuild test` through `xcsift`; `swiftlint` clean on touched files.

### Acceptance (on device — the simulator has no real VPIO path and cannot reproduce the volume drop)

1. Open a game with the mic **off**, Apple voice selected → opening narration at full media volume from the speaker.
2. Turn the mic **on** → narration still full volume; barge-in and recognition unchanged.
3. Turn the mic **off** → the very next utterance is full volume (this is the bug case).
4. Repeat 2–3 several times → no drift.
5. Mic off, then background the app and play music → Diction's narration ducks the music (`.duckOthers` still in effect under `.playback`).
6. Leave the game and open another with the mic off → full volume (covers `tearDown`).
7. Mic off → the orange mic indicator is not shown in the status bar.
8. With AirPods: mic on → off → on; narration stays on the AirPods throughout and the `.bluetooth` policy in `ListeningSessionConfig` still applies when the mic comes back. This is the regression risk for change (1): the `.playback` category between listening sessions must not kick narration off the AirPods.
9. Kokoro voice, mic off → unchanged (it already worked, because in-game Kokoro never reconfigures the session; confirm it still doesn't).

## Comments

## Answer

_glangmead — 2026-08-24_

Implemented in commit `933f41c`.

What changed, against the three fix items:

1. `SpeechRecognizer` — `stopContinuous()` now goes through a new private `releaseSession()`: `setActive(false, .notifyOthersOnDeactivation)` then `setCategory` back to `ListeningSessionConfig.restoredOnStop` (= `NarrationSessionConfig.standard`: `.playback` / `.default` / `[.duckOthers]`). The failed-`startEngine` path in `startContinuous` calls it too, since `startEngine` can set `.playAndRecord` before throwing. The `reconfigureListeningIfNeeded` double-flip is noted in the doc comment. `VoiceCoordinator.tearDown()` clears `isListening` *before* stopping the recognizer so the route-change notification the category flip fires can't restart it.
2. `SpeechSynthesizer.activatePlaybackSession()` and `KokoroSpeechEngine.ensureSessionForPlayback()` — the `.playAndRecord`-is-compatible check is gone. Both now call the pure `NarrationSessionConfig.shouldApply(recognizerLive:currentCategory:)` = `!recognizerLive && category != .playback`. "Recognizer live" is `SpeechRecognizer.ownsAudioSession` (true from `startContinuous` until `stopContinuous`/failed start), injected as a `@MainActor () -> Bool` closure: `VoiceCoordinator.init` wires it into the synthesizer (via a new `VoiceCoordinator.isRecognizerLive`); for the Kokoro audition — reachable from Settings *inside a game with the mic on* (`GameView` presents `SettingsView`) — a new `EnvironmentValues.isRecognizerLive` key is set by `GameView` on its Settings sheet and read by `KokoroVoicePickerView` into `audition.isRecognizerLive`. From the library it defaults to `{ false }`. The Kokoro `managesSession` flag keeps its meaning (audition configures the session; in-game the synthesizer does it before every pass).
3. `NarrationSessionConfig` (new, next to `ListeningSessionConfig`) is the one definition of the narration session, with `standard`, `shouldApply`, and `apply(to:)`; the three former literal copies are gone.

Tests (Swift Testing):
- `NarrationSessionConfigTests` — `standard` is `.playback`/`.default`/`[.duckOthers]`; `shouldApply` matrix: applies when no recognizer is live and the category is `.playAndRecord`/`.soloAmbient`/`.ambient`; skips when already `.playback`; never applies while a recognizer is live, whatever the category.
- `ListeningSessionConfigTests.restoredOnStopLeavesPlayAndRecord` — the restore config is `.playback` / `.default` / `[.duckOthers]` and its category differs from the listening category (the invariant that clears iOS's post-VPIO gain state). The six existing tests are unchanged.
- Deviation from the ticket's test list: no `SpeechSynthesizer`-level test with an injected session-mutation closure. `speak`/`speakCommandEcho` no-op on the simulator test host (`isAvailable == false`), so `activatePlaybackSession` isn't reachable through the public interface; the decision it makes is the pure `shouldApply`, which is what's tested, and the method is a two-line application of it.

Verification:
- `xcodebuild test` through `xcsift`: 285 pass, 1 fail — `MisakiPhonemizerTests.problemCorpus()`, the same pre-existing failure recorded in [ticket 01](01-free-to-try-voice-commands.md). Zero build warnings.
- `swiftlint` clean on every touched file.
- **Not verified on device** — acceptance 1–9 need real VPIO hardware and remain to be run by a human. The AirPods case (8) is the one to watch: between listening sessions the session is `.playback`, under which A2DP output is allowed by default, so narration should stay on the AirPods.
- `/code-review` (standards + spec, HEAD vs. the change): no hard violations, nothing spec-wrong. Acted on: the root-cause story now lives once in `NarrationSessionConfig` and the other comments point there; "mic on" wording replaced with "listening" per CONTEXT.md; the two `recognizer.ownsAudioSession` closures collapsed onto `VoiceCoordinator.isRecognizerLive`; `NarrationSessionConfig` fields are `let` and it is not `Equatable`; the `tearDown` comment no longer claims the reorder is load-bearing (route changes are delivered asynchronously, so either order works). Kept: `ListeningSessionConfig.restoredOnStop` as a named, tested policy even though it aliases `.standard`.

