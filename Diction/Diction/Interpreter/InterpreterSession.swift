import Foundation

/// Bridges the Swift app to an emglken interpreter (Bocfel or Glulxe compiled to
/// WASM) running inside a headless `WKWebView`, exchanging RemGlk JSON. The
/// transport lives in `WebInterpreterHost`: it answers save/restore fileref
/// prompts internally and routes their bytes to `SaveStorage`, so the updates
/// this session sees are always settled (never carry `specialinput`).
///
/// Lifecycle:
///   1. `load(_:)` detects format, extracts the dictionary, starts a fresh
///      emglken instance, and applies the first update.
///   2. `send(_:)` / `sendCharacter(_:)` forward a RemGlk input event and apply
///      the resulting update.
///   3. The session is single-use; create a new one for a different game. Each
///      session owns its own webview + WASM instance, so interpreter globals
///      never carry across games.
@Observable
@MainActor
final class InterpreterSession {
  /// Output entries appended over the course of play, in order.
  private(set) var transcript: [StyledText] = []

  /// Monotonic counter bumped on every transcript mutation, including the
  /// in-place merge path (`line.append == true`) that doesn't change
  /// `transcript.count`. View code observes this for auto-scroll triggers
  /// that need to fire on any visible change, not just append events.
  private(set) var transcriptRevision: Int = 0

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

  /// One emglken instance per session (per game open). GameView creates a fresh
  /// InterpreterSession for each game, so each gets a fresh webview + WASM
  /// instance — interpreter globals never carry across games.
  private let host = WebInterpreterHost()

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

  func load(_ storyURL: URL) async throws {
    guard let detected = try FormatDetector.detect(url: storyURL) else {
      throw InterpreterError.unknownFormat
    }
    format = detected
    gameID = SaveStorage.gameID(for: storyURL)
    dictionary = (try? DictionaryExtractor.extract(from: storyURL)) ?? []

    let sortedDict = dictionary.sorted().joined(separator: ", ")
    FileHandle.standardError.write(Data(
      "[diction-dict] \(gameID) — \(dictionary.count) words: \(sortedDict)\n".utf8))

    let engine = (detected == .glulx) ? "glulxe.js" : "bocfel.js"
    let storyData = try Data(contentsOf: storyURL)
    do {
      let first = try await host.start(story: storyData, engine: engine, gameID: gameID)
      apply(first)
    } catch {
      lastError = "load failed: \(error)"
      throw InterpreterError.loadFailed
    }
  }

  /// Drops all but the trailing `count` entries from the transcript.
  /// Used after RESTORE / RESTART when the game doesn't auto-clear the
  /// buffer — the prior play log would otherwise pile up under the
  /// post-restore state. No-op if `count` already covers the whole array.
  func trimTranscript(keepingSuffix count: Int) {
    let clamped = max(0, min(count, transcript.count))
    guard clamped < transcript.count else { return }
    transcript = Array(transcript.suffix(clamped))
    transcriptRevision &+= 1
  }

  /// Sends a parser command and applies the next interpreter update.
  /// The command is also appended to the transcript as a visible input echo.
  func send(_ command: String) async {
    guard inputMode == .line else { return }
    inputMode = nil
    transcript.append(.userInput(command))
    transcriptRevision &+= 1
    do {
      apply(try await host.send(line: command, gen: currentGen, window: currentWindow))
    } catch {
      lastError = "send failed: \(error)"
    }
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
    transcript.append(.userInput(displayLabel(forKey: value)))
    transcriptRevision &+= 1
    do {
      apply(try await host.send(char: value, gen: currentGen, window: currentWindow))
    } catch {
      lastError = "send failed: \(error)"
    }
  }

  /// Tears down the emglken instance when leaving the game. Async to match the
  /// existing call site (`await session.shutdown()` in GameView.onDisappear).
  func shutdown() async {
    host.teardown()
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

  // MARK: - Internals

  private func apply(_ update: RemGlkUpdate) {
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

    if let inputReq = update.input?.first(where: { $0.type == .line || $0.type == .char }) {
      currentGen = inputReq.gen ?? (update.gen ?? currentGen)
      currentWindow = inputReq.id
      inputMode = inputReq.type
    } else {
      currentGen = update.gen ?? currentGen
      inputMode = nil
    }

    transcriptRevision &+= 1
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
    StyledText.applyBufferContent(content, styleTable: styleTable, into: &transcript)
  }
}

enum InterpreterError: Error, CustomStringConvertible {
  case unknownFormat
  case loadFailed

  var description: String {
    switch self {
    case .unknownFormat: "Story file format not recognized."
    case .loadFailed: "Failed to load story file."
    }
  }
}
