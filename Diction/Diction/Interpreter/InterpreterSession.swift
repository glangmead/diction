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
        windowTypes[window.id] = window.type
      }
    }

    if let content = update.content {
      for window in content {
        // RESTORE / RESTART blow away the buffer and redraw the current
        // state. Without clearing our transcript here, the old play
        // history piles up under the new state and the voice reads it
        // all back. Grid clears (status line) are a per-turn no-op and
        // must not trigger a transcript wipe.
        if window.clear == true && windowTypes[window.id] == .buffer {
          transcript.removeAll()
        }
        guard let lines = window.text else { continue }
        for line in lines {
          guard let runs = line.content, !runs.isEmpty else { continue }
          let entry = StyledText(from: runs)
          if line.append == true, var last = transcript.last {
            last.runs.append(contentsOf: entry.runs)
            transcript[transcript.count - 1] = last
          } else {
            transcript.append(entry)
          }
        }
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
