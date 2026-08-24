# 03 — VoiceCoordinator and InterpreterSession are created four times per game open

**Type:** bug  
**Status:** resolved  
**Blocked by:** None  
**From:** device trace gathered for [02 — Narration is near-mute after the mic is turned off](02-mic-off-narration-near-mute.md), 2026-08-24  
**Spec:** None — bug; the fix is specified below  
**Assignee:** glangmead  
**Opened:** 2026-08-24  
**Closed:** 2026-08-24  

## Task

### Symptom

Opening a game constructs `VoiceCoordinator` four times. The instrumented build for ticket 02 logged `coordinator.init` at 14:59:22.671, 22.726, 22.864 and 32.672 for a single open of All Things Devours (and the same pattern in every later round). Only one instance is ever used.

### Diagnosis

`GameView` declares its services as `@State` with inline initial values:

```swift
@State private var session = InterpreterSession()
@State private var coordinator = VoiceCoordinator()
```

SwiftUI evaluates a `@State` initial-value expression every time the `GameView` *struct* is initialised — each time the parent (`LibraryView`'s navigation destination) re-evaluates its body — and keeps only the first instance as the persisted state. The other three are built and thrown away. `VoiceCoordinator.init` is not cheap: it creates a `SpeechRecognizer` (an `SFSpeechRecognizer`), a `SpeechSynthesizer` (an `AVSpeechSynthesizer` plus a private `KokoroSpeechEngine`), and an `AudioRouteController` (reads the live audio route and registers a `routeChangeNotification` observer). `InterpreterSession()` presumably pays a similar cost. The fourth init, ten seconds after the others, suggests the parent re-renders again later (a store or warmer property changing), so it is not only a first-open cost.

Confirm before fixing: add a temporary counter or `os_signpost` in `VoiceCoordinator.init` and `InterpreterSession.init`, open a game from the library, and record the count. Then remove the instrumentation.

### Fix

Preferred: create both objects once, when the game actually starts, rather than in the property initialiser. `GameView` already has the `.task(id: reloadToken)` where it wires the coordinator (`attach`, `useSharedVoice`, `useEntitlement`, …); creating them there means `@State private var coordinator: VoiceCoordinator?` and unwrapping in `body` — acceptable if the loading state (`isLoading`) already gates the game UI. If the optional makes `body` ugly, the alternative is to keep the non-optional `@State` and make construction cheap: `VoiceCoordinator` and `InterpreterSession` own their expensive services lazily, so a discarded instance costs an allocation and nothing else. Either is fine; pick the one with the smaller diff and say why in the ticket.

Do not move the objects up to `LibraryView` or the app — a game's session and coordinator must not outlive the game (see `tearDown`).

### Acceptance

- One `VoiceCoordinator` and one `InterpreterSession` per game open, verified with the temporary counter on device or simulator (before: 4; after: 1).
- No behaviour change: opening narration, mic auto-start in a bundled game, Settings sheet from within the game, reset ("Start Over" re-creates the session via `reloadToken`), and leaving the game (`tearDown`) all work as before.
- `VoiceCommandGateTests` and the rest of the suite pass; `swiftlint` clean.
- Review the change with `swiftui-pro`.

## Comments

## Answer

_glangmead — 2026-08-24_

Fixed in `490b148` by the ticket's second option: `GameView` is untouched and the two owners build their expensive services on first use — `VoiceCoordinator.recognizer` / `synthesizer` / `audioRoute` and `InterpreterSession.host` are now `@ObservationIgnored … lazy var`s, with the two callbacks `VoiceCoordinator.init` used to install moved into the lazy initialisers. Chosen because it is the smaller diff: the optional-`@State` route would have meant unwrapping `coordinator` and `session` at every one of the dozens of reads in `GameView`'s body and toolbar, or splitting the view. The SwiftUI-level cause (`LibraryView`'s body re-evaluating its navigation destination) is left alone, as the ticket asked; a discarded copy is now a bare allocation.

Worth knowing: the throwaway `InterpreterSession`s were not just slow, they leaked. `WebInterpreterHost.init` registers itself as the `WKUserContentController` message handler and only breaks that cycle in `teardown()`, which a discarded session never gets — so every extra evaluation retained a `WKWebView` for the life of the process.

Confirmed with temporary `Logger` counters in the six inits (removed before commit), iPhone 17 Pro simulator, opening All Things Devours from the library:

- Before: 2 × each of `InterpreterSession`, `VoiceCoordinator`, `WebInterpreterHost`, `SpeechRecognizer`, `SpeechSynthesizer`, `AudioRouteController` per open (the device trace in the ticket showed 4; the simulator's library re-renders less, the pattern is the same). The first `WebInterpreterHost` alone took ~90 ms.
- After: exactly 1 × each per open.
- Start Over: 1 new `InterpreterSession` + 1 `WebInterpreterHost`; the voice services are reused. Game restarted from the opening.
- Settings sheet from in-game: opens and dismisses, builds nothing.
- Back to the library and re-open: one fresh stack of all six.
- Mic auto-started in the bundled game; a typed `look` dispatched through the coordinator and rendered. Opening narration is not checkable on the simulator (narration is disabled there) — the narration path is unchanged apart from when the synthesizer is allocated. Verified on device by glangmead, 2026-08-24.

Tests: `VoiceCoordinatorServicesTests` (stable service identity; route-controller callback still installed) and `InterpreterSessionHostTests` (stable web view) added; `VoiceCommandGateTests` and the full suite pass (289). `swiftlint` clean on the touched files. Reviewed with `swiftui-pro` (no findings) and `/code-review` (mechanism sound; the review's comment-trimming and test-wording notes were applied before commit).

Side change, separate commit `3de128a`: `.swiftlint.yml` now excludes `Diction/Build`, because a root `swiftlint` run was sweeping the FluidAudio SwiftPM checkout.

Not done: the synthesizer's `isRecognizerLive` wiring isn't pinned by a test — its default is `{ false }`, so nothing distinguishes wired from unwired without plumbing a fake audio session through the coordinator, which this ticket doesn't justify.
