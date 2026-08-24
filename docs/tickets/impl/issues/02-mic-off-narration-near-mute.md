# 02 — Narration is near-mute after the mic is turned off

**Type:** bug  
**Status:** claimed  
**Blocked by:** None  
**From:** bug report by glangmead, 2026-08-24 (on-device, Apple TTS); introduced by commit `f2ccb42` (free narration with the mic off)  
**Spec:** None — bug; the fix is specified below  
**Assignee:** glangmead  
**Opened:** 2026-08-24  

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
