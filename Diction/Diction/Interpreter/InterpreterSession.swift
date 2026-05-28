import Foundation
import Darwin

/// Bridges the Swift app to an in-process C interpreter (Bocfel or Glulxe).
/// Runs the interpreter on a detached thread, with stdin/stdout redirected
/// to pipes so we can speak RemGlk JSON to it.
///
/// Lifecycle:
///   1. `load(_:)` detects format, opens pipes, dups them onto stdio,
///      spawns the interpreter thread, and reads the first update.
///   2. `send(_:)` writes a RemGlk line input and reads the next update.
///   3. The session is single-use; create a new one for a different game.
@Observable
@MainActor
final class InterpreterSession {
  /// Output entries appended over the course of play, in order.
  private(set) var transcript: [StyledText] = []

  /// True when the interpreter is blocked waiting for line input.
  private(set) var isAwaitingInput = false

  /// Vocabulary words from the story file, used to bias speech recognition.
  private(set) var dictionary: Set<String> = []

  /// Last interpreter error message, if any.
  private(set) var lastError: String?

  /// Detected format of the loaded story file.
  private(set) var format: StoryFormat?

  /// Stable per-game identifier used to scope save files, transcripts,
  /// command records, and data resources on disk.
  private(set) var gameID: String = ""

  /// Held so their underlying fds stay valid for the session's lifetime.
  /// Foundation's `Pipe` closes its fds on dealloc.
  private var toPipe: Pipe?
  private var fromPipe: Pipe?

  /// Raw fds for reading interpreter output and writing input. We bypass
  /// `FileHandle.read(upToCount:)` because its dispatch-source-based readiness
  /// signal does not fire reliably for our pipe + detached-task setup.
  private var readerFD: Int32 = -1
  private var writerFD: Int32 = -1

  private var pipeReadBuffer = Data()
  private var currentGen = 1
  private var currentWindow = 0

  /// Cached window-id → window-type map, populated from each update's
  /// `windows` array. Lets us distinguish the buffer (where the prose
  /// lives) from grids (status line, which clears every turn) so we only
  /// honor `clear` flags on the buffer.
  private var windowTypes: [Int: RemGlkUpdate.WindowType] = [:]

  /// Saved real stdin/stdout file descriptors so we can restore them on tear-down.
  /// nonisolated because `deinit` runs in an unspecified isolation context.
  nonisolated(unsafe) private var savedStdin: Int32 = -1
  nonisolated(unsafe) private var savedStdout: Int32 = -1

  deinit {
    // Restore process-wide stdio if we redirected it.
    if savedStdin >= 0 {
      _ = dup2(savedStdin, STDIN_FILENO)
      close(savedStdin)
    }
    if savedStdout >= 0 {
      _ = dup2(savedStdout, STDOUT_FILENO)
      close(savedStdout)
    }
  }

  func load(_ storyURL: URL) async throws {
    guard let detected = try FormatDetector.detect(url: storyURL) else {
      throw InterpreterError.unknownFormat
    }
    format = detected
    gameID = SaveStorage.gameID(for: storyURL)
    dictionary = (try? DictionaryExtractor.extract(from: storyURL)) ?? []

    let sortedDict = dictionary.sorted().joined(separator: ", ")
    let dictMsg = "[diction-dict] \(gameID) — \(dictionary.count) words: \(sortedDict)\n"
    FileHandle.standardError.write(Data(dictMsg.utf8))

    let toPipe = Pipe()
    let fromPipe = Pipe()
    self.toPipe = toPipe
    self.fromPipe = fromPipe

    let stdinFD = toPipe.fileHandleForReading.fileDescriptor
    let stdoutFD = fromPipe.fileHandleForWriting.fileDescriptor
    readerFD = fromPipe.fileHandleForReading.fileDescriptor
    writerFD = toPipe.fileHandleForWriting.fileDescriptor

    // Save and redirect process-wide stdio. The app doesn't use them for
    // anything else (print uses oslog), so this is safe.
    savedStdin = dup(STDIN_FILENO)
    savedStdout = dup(STDOUT_FILENO)
    _ = dup2(stdinFD, STDIN_FILENO)
    _ = dup2(stdoutFD, STDOUT_FILENO)

    // Close the now-duplicated originals so each pipe end has exactly one
    // open writer / reader. (The Pipe object will close the surviving end
    // on dealloc; we hold the Pipe in a property so that doesn't happen yet.)
    try? toPipe.fileHandleForReading.close()
    try? fromPipe.fileHandleForWriting.close()

    let storyPath = storyURL.path
    let chosenFormat = detected

    // Run the interpreter on a background thread. It blocks on stdin
    // forever (until glk_exit), so we cannot run it on the main actor.
    Thread.detachNewThread {
      storyPath.withCString { cpath in
        switch chosenFormat {
        case .zMachine:
          _ = bocfel_run(cpath)
        case .glulx:
          _ = glulxe_run(cpath)
        }
      }
    }

    // RemGlk uses fixed metrics (80x50) supplied by our bridge; the
    // interpreter emits its first update via glk_select before reading any
    // input, so we just consume that.
    try await readNextUpdate()
  }

  /// Sends a parser command and reads the next interpreter update.
  /// The command is also appended to the transcript as a visible input echo.
  func send(_ command: String) async {
    guard isAwaitingInput else { return }
    isAwaitingInput = false

    transcript.append(.userInput(command))

    let input = RemGlkLineInput(
      gen: currentGen,
      window: currentWindow,
      value: command
    )
    do {
      try writeJSON(input)
      try await readNextUpdate()
    } catch {
      lastError = "send failed: \(error)"
    }
  }

  // MARK: - Internals

  private func sendInitialArrange() async throws {
    let arrange = RemGlkArrangeInput(
      gen: 0,
      metrics: .init(width: 80, height: 50)
    )
    try writeJSON(arrange)
  }

  private func writeJSON<T: Encodable>(_ value: T) throws {
    guard writerFD >= 0 else { throw InterpreterError.pipeBroken }
    var data = try JSONEncoder().encode(value)
    data.append(0x0A)  // newline terminator
    let pipeFD = writerFD
    try data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
      var ptr = raw.baseAddress!
      var remaining = raw.count
      while remaining > 0 {
        let written = Darwin.write(pipeFD, ptr, remaining)
        if written < 0 {
          if errno == EINTR { continue }
          throw InterpreterError.pipeBroken
        }
        if written == 0 { throw InterpreterError.pipeBroken }
        ptr = ptr.advanced(by: written)
        remaining -= written
      }
    }
  }

  /// Read bytes from the interpreter until we have one complete JSON object.
  /// RemGlk outputs each update as a single self-contained JSON object with
  /// no trailing newline guarantee, so we track brace depth across reads.
  ///
  /// If the update carries a `specialinput` (fileref dialog), we
  /// auto-respond with an appropriate path and recurse to read the
  /// interpreter's continuation. This is what makes `save` / `restore` /
  /// `script` work without a user-visible file picker.
  private func readNextUpdate() async throws {
    let data = try await readOneJSONObject()
    guard !data.isEmpty else { return }

    let update = try JSONDecoder().decode(RemGlkUpdate.self, from: data)
    apply(update)

    if let special = update.specialinput {
      try await respondToFileref(special, gen: update.gen ?? currentGen)
      try await readNextUpdate()
    }
  }

  /// Resolves an autosave-style path for the requested fileref and writes
  /// a `specialresponse` back to the interpreter. Returning `value: nil`
  /// tells the game the user cancelled — used when a read request asks
  /// for a file that doesn't exist yet.
  private func respondToFileref(
    _ request: RemGlkUpdate.SpecialRequest,
    gen: Int
  ) async throws {
    let path = SaveStorage.resolvePath(
      gameID: gameID,
      filetype: request.filetype,
      mode: request.filemode
    )
    let response = RemGlkSpecialResponse(gen: gen, value: path)
    try writeJSON(response)
  }

  private func readOneJSONObject() async throws -> Data {
    guard readerFD >= 0 else { throw InterpreterError.pipeBroken }
    var parser = JSONStanzaParser()
    while true {
      if pipeReadBuffer.isEmpty {
        pipeReadBuffer = try await readChunk(fd: readerFD)
      }
      let byte = pipeReadBuffer.removeFirst()
      if let done = parser.consume(byte) { return done }
    }
  }

  private func readChunk(fd pipeFD: Int32) async throws -> Data {
    let chunk = await Task.detached { () -> Data? in
      var buf = [UInt8](repeating: 0, count: 4096)
      let bytesRead = buf.withUnsafeMutableBufferPointer { ptr in
        Darwin.read(pipeFD, ptr.baseAddress, 4096)
      }
      if bytesRead <= 0 { return nil }
      return Data(buf.prefix(bytesRead))
    }.value
    guard let chunk, !chunk.isEmpty else { throw InterpreterError.pipeBroken }
    return chunk
  }

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
      isAwaitingInput = true
    } else {
      currentGen = update.gen ?? currentGen
    }
  }
}

enum InterpreterError: Error, CustomStringConvertible {
  case unknownFormat
  case pipeBroken
  case loadFailed

  var description: String {
    switch self {
    case .unknownFormat: "Story file format not recognized."
    case .pipeBroken: "Interpreter I/O pipe closed unexpectedly."
    case .loadFailed: "Failed to load story file."
    }
  }
}

/// Brace-counting scanner that collects bytes until one complete top-level
/// JSON object has been read. Handles quoted strings and escape sequences so
/// braces inside strings don't confuse the depth counter. RemGlk pretty-prints
/// its JSON with embedded newlines, so we can't simply split on `\n`.
private struct JSONStanzaParser {
  private static let whitespace: Set<UInt8> = [0x20, 0x09, 0x0A, 0x0D]

  private var depth = 0
  private var inString = false
  private var escape = false
  private var collected = Data()

  mutating func consume(_ byte: UInt8) -> Data? {
    if depth == 0 && collected.isEmpty && Self.whitespace.contains(byte) {
      return nil
    }
    collected.append(byte)

    if inString {
      consumeInString(byte)
      return nil
    }

    switch byte {
    case 0x22: inString = true        // opening quote
    case 0x7B: depth += 1             // {
    case 0x7D:                        // }
      depth -= 1
      if depth == 0 { return collected }
    default: break
    }
    return nil
  }

  private mutating func consumeInString(_ byte: UInt8) {
    if escape {
      escape = false
    } else if byte == 0x5C {          // backslash
      escape = true
    } else if byte == 0x22 {          // closing quote
      inString = false
    }
  }
}
