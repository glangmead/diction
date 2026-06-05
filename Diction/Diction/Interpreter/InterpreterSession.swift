import Foundation
import CryptoKit
import WebKit

// swiftlint:disable file_length
// Pitch for the exception: this type owns both RemGlk update ingestion (apply +
// window/content handling) and resume snapshot capture/restore. Both mutate its
// `private` state, so they can't move to an extension in another file without
// widening access and scattering tightly-coupled mutation. ~436 lines; prefer
// the exception over leaking internals. The same reasoning covers the
// `type_body_length` disable on the declaration below: the body sits one line
// over the 250 limit and its only members are this coupled state — nothing
// extractable without widening access.

/// Bridges the Swift app to a classic-Glk interpreter (ZVM for Z-machine, Quixe
/// for Glulx, both JavaScript) running inside a headless `WKWebView`, exchanging
/// RemGlk JSON. The transport lives in `WebInterpreterHost`: it answers
/// save/restore fileref prompts internally and routes their bytes to
/// `SaveStorage`, so the updates this session sees are always settled (never
/// carry `specialinput`).
///
/// Lifecycle:
///   1. `load(_:)` detects format, extracts the dictionary, starts a fresh
///      interpreter instance, and applies the first update.
///   2. `send(_:)` / `sendCharacter(_:)` forward a RemGlk input event and apply
///      the resulting update.
///   3. The session is single-use; create a new one for a different game. Each
///      session owns its own webview + WASM instance, so interpreter globals
///      never carry across games.
@Observable
@MainActor
// swiftlint:disable:next type_body_length
final class InterpreterSession {
  /// Output entries appended over the course of play, in order.
  private(set) var transcript: [StyledText] = []

  /// The buffer entries the interpreter produced in response to the most recent
  /// `send` / `sendCharacter`, with the input echo and — when the update redrew
  /// the screen (a `clear`) — the wiped scrollback excluded. This is the
  /// authoritative narration payload: only the session knows a redraw happened,
  /// and slicing the transcript by a pre-send index silently skips the response's
  /// first lines when it does (AMFV clears and redraws after its intro keypress).
  private(set) var lastResponse: [StyledText] = []

  /// Transcript index where `lastResponse` begins — 0 after a redraw, otherwise
  /// the input echo's index. Used to trim scrollback after RESTORE / RESTART.
  private(set) var lastResponseStart = 0

  /// Count of primary-buffer `clear`s applied. A send compares this across its
  /// update to tell whether the screen was redrawn, even though the fresh content
  /// then lands at a lower index than the pre-send transcript.
  private var transcriptClears = 0

  /// The kind of input the interpreter is currently blocked waiting for,
  /// or nil while the interpreter is running. Distinguishes line input
  /// (typed sentences) from char input (single keypress like the SPACE
  /// at Curses's title screen).
  private(set) var inputMode: RemGlkUpdate.InputType?

  /// Convenience derived from `inputMode` so existing view code that
  /// only cares about "is input wanted?" keeps working.
  var isAwaitingInput: Bool { inputMode != nil }

  /// Current grid (status) windows — e.g. AMFV's mode / location / time / date
  /// bar — ordered by their on-screen `top` (then id), so any number of them
  /// stack in the game's intended vertical order. The buffer prose stays in
  /// `transcript`; these are the fixed-grid panels alongside it, as
  /// replace-by-row snapshots. Presentation decides visual and audio treatment.
  var statusWindows: [GridWindowSnapshot] {
    gridSnapshots.values.sorted { ($0.top, $0.id) < ($1.top, $1.id) }
  }

  /// Secondary (non-primary) buffer windows ordered by on-screen `top`, surfaced
  /// as panels beside the transcript — Blue Lacuna's bottom "Topics" window the
  /// `keywords` screen opens sits below the prose at `top` 47.
  var secondaryBufferWindows: [BufferWindowSnapshot] {
    secondaryBuffers.values.sorted { ($0.top, $0.id) < ($1.top, $1.id) }
  }

  /// Vocabulary words from the story file, used to bias speech recognition.
  private(set) var dictionary: Set<String> = []

  /// Last interpreter error message, if any.
  private(set) var lastError: String?

  /// Detected format of the loaded story file.
  private(set) var format: StoryFormat?

  /// Stable per-game identifier used to scope save files, transcripts,
  /// command records, and data resources on disk.
  private(set) var gameID: String = ""

  /// One interpreter instance per session (per game open). GameView creates a
  /// fresh InterpreterSession for each game, so each gets a fresh webview +
  /// interpreter — globals never carry across games.
  private let host = WebInterpreterHost()

  /// The interpreter's WebView, surfaced so the view layer can display GlkOte's
  /// rendered output. Read-only; the session owns the host's lifecycle.
  var interpreterWebView: WKWebView { host.webView }

  private var currentGen = 1
  private var currentWindow = 0

  /// Cached window-id → window-type map, populated from each update's
  /// `windows` array. Lets us distinguish the buffer (where the prose
  /// lives) from grids (status line, which clears every turn) so we only
  /// honor `clear` flags on the buffer.
  private var windowTypes: [Int: RemGlkUpdate.WindowType] = [:]

  /// Per-window named-style tables (`.Style_NAME` → attributes) from
  /// `windows[].styles`, used to resolve each run's effective look.
  private var windowStyles: [Int: [String: StyleAttributes]] = [:]

  /// Live snapshots of grid (status) windows, keyed by window id and rebuilt
  /// replace-by-row as updates arrive. Surfaced in id order via `statusWindows`.
  private var gridSnapshots: [Int: GridWindowSnapshot] = [:]

  /// The main story buffer window (the first buffer id seen). Only it drives the
  /// `transcript`; other buffer windows are surfaced as panels so their `clear`
  /// can't wipe the prose — Blue Lacuna's `keywords` screen opens a second one.
  private var primaryBufferID: Int?

  /// Non-primary buffer windows (e.g. Blue Lacuna's bottom "Topics" panel),
  /// keyed by window id and surfaced via `secondaryBufferWindows`.
  private var secondaryBuffers: [Int: BufferWindowSnapshot] = [:]

  /// The interpreter's latest VM autosave (JSON) — the engine half of a resume
  /// snapshot, paired with `captureSnapshot()` and persisted via
  /// `GameSnapshotStore`. Nil until the first move autosaves.
  var engineSnapshot: Data? { host.latestAutosave.flatMap { Data($0.utf8) } }

  /// Persists/loads per-turn resume snapshots. Injected; nil disables persistence
  /// (the default — tests that don't exercise resume leave it nil).
  var snapshotStore: GameSnapshotStore?

  /// Backs the game's manual SAVE slot (the interpreter's own SAVE verb). Forwarded
  /// to the host at `load`; injected so tests isolate to a temp directory.
  var saveStore = SaveStorage.default

  /// Story content signature, scoping snapshots so a changed/re-imported story
  /// can't restore a stale one.
  private var signature = ""

  /// Loads a story into a fresh VM. If a valid resume snapshot exists in
  /// `snapshotStore` (or `restoring` is passed explicitly), the VM resumes from
  /// it and the saved display is repainted. Otherwise it starts fresh.
  func load(_ storyURL: URL, restoring explicitRestore: Data? = nil) async throws {
    guard let detected = try FormatDetector.detect(url: storyURL) else {
      throw InterpreterError.unknownFormat
    }
    format = detected
    gameID = SaveStorage.gameID(for: storyURL)
    dictionary = (try? DictionaryExtractor.extract(from: storyURL)) ?? []

    let sortedDict = dictionary.sorted().joined(separator: ", ")
    FileHandle.standardError.write(Data(
      "[diction-dict] \(gameID) — \(dictionary.count) words: \(sortedDict)\n".utf8))

    let storyData = try Data(contentsOf: storyURL)
    if detected == .zMachine,
       let version = FormatDetector.zMachineVersion(header: storyData),
       !FormatDetector.supportedZMachineVersions.contains(version) {
      throw InterpreterError.unsupportedZMachineVersion(Int(version))
    }
    let engine = (detected == .glulx) ? "quixe" : "zvm"
    host.saveStore = saveStore
    // Apply every update the host receives — including the arrange/redraw frames
    // real GlkOte emits mid-turn — so window / input / narration state never
    // drifts. The async start/send below complete only on a *settled* update.
    host.onUpdate = { [weak self] update in self?.apply(update) }
    signature = Self.signature(for: storyData)
    // Resume from the store unless an explicit snapshot was passed (tests).
    let stored = explicitRestore == nil ? snapshotStore?.read(gameID: gameID, signature: signature) : nil
    do {
      _ = try await host.start(
        story: storyData, engine: engine, gameID: gameID, restore: explicitRestore ?? stored?.engine)
      // Repaint the saved display over the interpreter's (minimal) post-restore
      // update — but keep the live protocol state the interpreter just set, so
      // the next command targets the right window/generation.
      if let stored,
         let presentation = try? JSONDecoder().decode(PresentationSnapshot.self, from: stored.presentation) {
        let liveGen = currentGen, liveWindow = currentWindow, liveMode = inputMode
        restore(presentation)
        currentGen = liveGen
        currentWindow = liveWindow
        inputMode = liveMode
      }
      persistSnapshot()
    } catch {
      lastError = "load failed: \(error)"
      throw InterpreterError.loadFailed
    }
  }

  /// SHA-256 of the story bytes, used to scope resume snapshots to exact content.
  private static func signature(for data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  /// Persist the current resume snapshot (engine autosave + presentation) after a
  /// settled turn. No-op without a store or before the first autosave exists.
  private func persistSnapshot() {
    guard let snapshotStore, !signature.isEmpty, let engine = engineSnapshot,
          let presentation = try? JSONEncoder().encode(captureSnapshot()) else { return }
    // Small, separate status artifact for the library preview, so a row needn't
    // decode the whole presentation snapshot. Nil for games with no status window.
    let status = statusWindows.isEmpty ? nil : try? JSONEncoder().encode(statusWindows)
    try? snapshotStore.write(
      gameID: gameID, signature: signature,
      snapshot: GameSnapshot(engine: engine, presentation: presentation, status: status))
  }

  /// Drops all but the trailing `count` entries from the transcript.
  /// Used after RESTORE / RESTART when the game doesn't auto-clear the
  /// buffer — the prior play log would otherwise pile up under the
  /// post-restore state. No-op if `count` already covers the whole array.
  func trimTranscript(keepingSuffix count: Int) {
    let clamped = max(0, min(count, transcript.count))
    guard clamped < transcript.count else { return }
    transcript = Array(transcript.suffix(clamped))
  }

  /// Sends a parser command and applies the next interpreter update.
  /// The command is also appended to the transcript as a visible input echo.
  func send(_ command: String) async {
    guard inputMode == .line else { return }
    inputMode = nil
    let echoIndex = transcript.count
    transcript.append(.userInput(command))
    let clearsBefore = transcriptClears
    do {
      // The host applies every update via `onUpdate`; it returns once a settled
      // (input-requesting or exit) update completes the turn.
      _ = try await host.send(line: command, gen: currentGen, window: currentWindow)
    } catch {
      lastError = "send failed: \(error)"
    }
    recordResponse(echoIndex: echoIndex, clearsBefore: clearsBefore)
    persistSnapshot()
  }

  /// Sends a single Glk character event. Used when the interpreter
  /// requested character input via `glk_request_char_event` — common for
  /// "press any key", y/n prompts, and menu single-digit selection.
  ///
  /// `value` is either a single character (`"y"`, `" "`, `"5"`) or one of
  /// RemGlk's special-key names (`"return"`, `"escape"`, `"left"`, etc.).
  func sendCharacter(_ value: String) async {
    guard inputMode == .char else { return }
    inputMode = nil
    let echoIndex = transcript.count
    transcript.append(.userInput(displayLabel(forKey: value)))
    let clearsBefore = transcriptClears
    do {
      // The host applies every update via `onUpdate`; it returns once a settled
      // (input-requesting or exit) update completes the turn.
      _ = try await host.send(char: value, gen: currentGen, window: currentWindow)
    } catch {
      lastError = "send failed: \(error)"
    }
    recordResponse(echoIndex: echoIndex, clearsBefore: clearsBefore)
    persistSnapshot()
  }

  /// Tears down the interpreter instance when leaving the game. Async to match the
  /// existing call site (`await session.shutdown()` in GameView.onDisappear).
  func shutdown() async {
    host.teardown()
  }

  /// Themes GlkOte's rendered output to the app's reading look. The CSS is built
  /// by `GameView` from the current typeface/size/colour-scheme; the host injects
  /// it and re-applies it across page reloads (game open / restore).
  func applyThemeCSS(_ css: String) {
    host.applyThemeCSS(css)
  }

  /// Turns a Glk character-input value into a user-readable echo for the
  /// transcript. The empty / space / control-key values would otherwise
  /// echo as invisible glyphs.
  private func displayLabel(forKey value: String) -> String {
    switch value {
    case " ": return "[SPACE]"
    case "return": return "[RETURN]"
    case "escape": return "[ESC]"
    case "tab": return "[TAB]"
    case "delete": return "[DEL]"
    default: return value
    }
  }

  // MARK: - Snapshot (resume)

  /// Freeze the session's renderable + protocol state for persistence — the
  /// display half of a resume snapshot. Pair with the interpreter's VM autosave
  /// taken on the same settled update so the transcript and VM never diverge.
  func captureSnapshot() -> PresentationSnapshot {
    PresentationSnapshot(
      transcript: transcript,
      lastResponse: lastResponse,
      lastResponseStart: lastResponseStart,
      transcriptClears: transcriptClears,
      inputMode: inputMode,
      currentGen: currentGen,
      currentWindow: currentWindow,
      windowTypes: windowTypes,
      windowStyles: windowStyles,
      gridSnapshots: gridSnapshots,
      primaryBufferID: primaryBufferID,
      secondaryBuffers: secondaryBuffers
    )
  }

  /// Repaint from a captured snapshot. The live interpreter is restored
  /// separately via its own VM autosave; this restores only what the views show.
  func restore(_ snapshot: PresentationSnapshot) {
    transcript = snapshot.transcript
    lastResponse = snapshot.lastResponse
    lastResponseStart = snapshot.lastResponseStart
    transcriptClears = snapshot.transcriptClears
    inputMode = snapshot.inputMode
    currentGen = snapshot.currentGen
    currentWindow = snapshot.currentWindow
    windowTypes = snapshot.windowTypes
    windowStyles = snapshot.windowStyles
    gridSnapshots = snapshot.gridSnapshots
    primaryBufferID = snapshot.primaryBufferID
    secondaryBuffers = snapshot.secondaryBuffers
  }

  // MARK: - Internals

  /// Ingest one settled RemGlk update. The single mutation point for play state,
  /// driven by `load`/`send`; `internal` (not `private`) so tests can feed
  /// updates without a live interpreter.
  func apply(_ update: RemGlkUpdate) {
    if let windows = update.windows {
      for window in windows {
        updateWindowMeta(window)
      }
      // RemGlk lists the full window set on any arrangement change, so any id
      // missing here was closed — e.g. Blue Lacuna's keyword panel after "0".
      pruneWindows(keeping: Set(windows.map(\.id)))
    }

    if let content = update.content {
      for windowContent in content {
        applyContent(windowContent)
      }
    }

    // Input state. When the `input` array is PRESENT it is authoritative — a
    // line/char request sets the mode; an array without one means input was
    // cancelled. When it's ABSENT the update simply doesn't touch input: real
    // GlkOte itself only adjusts input "if arg.input != null" (glkote.js:705-712),
    // and it emits input-less updates for arrange / redraw / graphics events when
    // a window resizes. We must keep the current mode then, or the prompt vanishes
    // the moment a graphics window rearranges the layout (Counterfeit Monkey's map,
    // graphwintest). `exit` ends play, so it clears the mode regardless.
    if update.exit == true {
      currentGen = update.gen ?? currentGen
      inputMode = nil
    } else if let input = update.input {
      if let inputReq = input.first(where: { $0.type == .line || $0.type == .char }) {
        currentGen = inputReq.gen ?? (update.gen ?? currentGen)
        currentWindow = inputReq.id
        inputMode = inputReq.type
      } else {
        currentGen = update.gen ?? currentGen
        inputMode = nil
      }
    } else {
      currentGen = update.gen ?? currentGen
    }
  }

  /// Route one window's content: the primary buffer feeds the `transcript`, a
  /// grid feeds its status snapshot, and any other buffer feeds a panel snapshot.
  private func applyContent(_ windowContent: RemGlkUpdate.Content) {
    let styleTable = windowStyles[windowContent.id]
    switch windowTypes[windowContent.id] {
    case .grid:
      var snapshot = gridSnapshots[windowContent.id]
        ?? GridWindowSnapshot(id: windowContent.id, width: 0, height: 0, lines: [])
      snapshot.apply(content: windowContent, styleTable: styleTable)
      gridSnapshots[windowContent.id] = snapshot
    case .buffer:
      if primaryBufferID == nil { primaryBufferID = windowContent.id }
      if windowContent.id == primaryBufferID {
        applyBufferContent(windowContent, styleTable: styleTable)
      } else {
        var snapshot = secondaryBuffers[windowContent.id]
          ?? BufferWindowSnapshot(id: windowContent.id)
        snapshot.apply(content: windowContent, styleTable: styleTable)
        secondaryBuffers[windowContent.id] = snapshot
      }
    default:
      break   // graphics / pair / blank carry no text we render
    }
  }

  /// Records a window's type and named-style table, and for grids captures the
  /// geometry and resizes its row buffer to match `gridheight`.
  private func updateWindowMeta(_ window: RemGlkUpdate.Window) {
    windowTypes[window.id] = window.type
    if let styles = window.styles { windowStyles[window.id] = styles }
    switch window.type {
    case .grid: updateGridMeta(window)
    case .buffer: updateBufferMeta(window)
    default: break
    }
  }

  private func updateGridMeta(_ window: RemGlkUpdate.Window) {
    var snapshot = gridSnapshots[window.id]
      ?? GridWindowSnapshot(id: window.id, width: 0, height: 0, lines: [])
    if let width = window.gridwidth { snapshot.width = width }
    if let height = window.gridheight { snapshot.height = height }
    if let top = window.top { snapshot.top = top }
    snapshot.resizeRows()
    gridSnapshots[window.id] = snapshot
  }

  /// The first buffer window is the main story window → `transcript`; the rest
  /// become panels. Geometry is in 1×1 cells, so `height` is a line count.
  private func updateBufferMeta(_ window: RemGlkUpdate.Window) {
    if primaryBufferID == nil { primaryBufferID = window.id }
    guard window.id != primaryBufferID else { return }
    var snapshot = secondaryBuffers[window.id] ?? BufferWindowSnapshot(id: window.id)
    if let top = window.top { snapshot.top = top }
    if let height = window.height { snapshot.height = height }
    secondaryBuffers[window.id] = snapshot
  }

  /// Drop tracked state for windows the interpreter has closed. RemGlk includes
  /// the complete window set whenever it changes, so any id not in `liveIDs` is
  /// gone — its snapshot, type, and style table go with it.
  private func pruneWindows(keeping liveIDs: Set<Int>) {
    windowTypes = windowTypes.filter { liveIDs.contains($0.key) }
    windowStyles = windowStyles.filter { liveIDs.contains($0.key) }
    gridSnapshots = gridSnapshots.filter { liveIDs.contains($0.key) }
    secondaryBuffers = secondaryBuffers.filter { liveIDs.contains($0.key) }
    if let primary = primaryBufferID, !liveIDs.contains(primary) { primaryBufferID = nil }
  }

  /// Appends (or in-place merges) a buffer window's lines into the transcript,
  /// resolving each run against the window's style table. A `clear` here is a
  /// RESTORE / RESTART redraw — wipe the scrollback so the old play history
  /// doesn't pile up under the new state (and the voice doesn't reread it).
  private func applyBufferContent(
    _ content: RemGlkUpdate.Content, styleTable: [String: StyleAttributes]?
  ) {
    if content.clear == true { transcriptClears += 1 }
    StyledText.applyBufferContent(content, styleTable: styleTable, into: &transcript)
  }

  /// Capture the narration window for the just-applied input. A redraw (`clear`)
  /// during the update wiped the echo and prior scrollback, so the response is
  /// the whole current transcript; otherwise it runs from the echo (the update's
  /// first line may have merged onto it) to the end.
  private func recordResponse(echoIndex: Int, clearsBefore: Int) {
    let window = Self.responseWindow(
      transcript: transcript,
      echoIndex: echoIndex,
      didClear: transcriptClears != clearsBefore
    )
    lastResponseStart = window.start
    lastResponse = window.entries
  }

  /// Pure narration-window computation, split out so it can be tested without a
  /// live interpreter. `start` is the transcript index the response begins at —
  /// 0 after a redraw, else the echo index — and `entries` is the slice from
  /// there with the input echoes removed.
  nonisolated static func responseWindow(
    transcript: [StyledText], echoIndex: Int, didClear: Bool
  ) -> (start: Int, entries: [StyledText]) {
    let start = didClear ? 0 : echoIndex
    guard start < transcript.count else { return (start, []) }
    return (start, Array(transcript[start...].filter { !$0.isUserInput }))
  }
}

enum InterpreterError: Error, CustomStringConvertible {
  case unknownFormat
  case loadFailed
  case unsupportedZMachineVersion(Int)

  var description: String {
    switch self {
    case .unknownFormat: "Story file format not recognized."
    case .loadFailed: "Failed to load story file."
    case .unsupportedZMachineVersion(let version):
      "Z-machine version \(version) isn't supported. Diction plays versions 3, 4, 5, and 8."
    }
  }
}
