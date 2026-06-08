import Foundation
import OSLog

/// Builds the user-shareable diagnostics file: reads this process's own entries for
/// the `DiagnosticsLog` subsystem back out of `OSLogStore`, renders them with
/// `DiagnosticsFormatter`, and writes a `.txt` to a temporary URL for a share sheet.
///
/// The read can be slow, so the work runs on a detached background task; only the
/// resulting `URL` returns to the caller. Every environment value is gathered off
/// the main actor (no `UIDevice`), so nothing here hops back to `@MainActor`.
enum DiagnosticsExport {
  /// Produce the log file and return its URL. Throws if the log store can't be
  /// opened; an empty window still yields a file (header + a "no entries" note) so
  /// the user always has something to send.
  static func makeLogFile(now: Date = Date()) async throws -> URL {
    try await Task.detached(priority: .utility) {
      try buildFile(now: now)
    }.value
  }

  private static func buildFile(now: Date) throws -> URL {
    let store = try OSLogStore(scope: .currentProcessIdentifier)
    let position = store.position(date: DiagnosticsExportPolicy.windowStart(from: now))
    let predicate = NSPredicate(format: "subsystem == %@", DiagnosticsLog.subsystem)

    var lines: [String] = []
    for case let log as OSLogEntryLog in try store.getEntries(at: position, matching: predicate) {
      lines.append(DiagnosticsFormatter.line(for: DiagnosticsEntry(
        date: log.date, category: log.category,
        level: levelName(log.level), message: log.composedMessage)))
      if lines.count >= DiagnosticsExportPolicy.entryCap { break }
    }

    let environment = DiagnosticsEnvironment(
      appVersion: infoString("CFBundleShortVersionString"),
      build: infoString("CFBundleVersion"),
      systemVersion: systemVersion(),
      deviceModel: deviceModel(),
      locale: Locale.current.identifier)
    let header = DiagnosticsFormatter.header(environment: environment, exportedAt: now)
    let body = lines.isEmpty ? "(no entries in the last 30 minutes)" : lines.joined(separator: "\n")
    let text = "\(header)\n\(body)\n"

    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("diction-diagnostics-\(fileStamp(now)).txt")
    try text.write(to: url, atomically: true, encoding: .utf8)
    return url
  }

  // MARK: - Environment (all off-main-actor safe)

  private static func infoString(_ key: String) -> String {
    Bundle.main.object(forInfoDictionaryKey: key) as? String ?? "?"
  }

  private static func systemVersion() -> String {
    let version = ProcessInfo.processInfo.operatingSystemVersion
    let patch = version.patchVersion > 0 ? ".\(version.patchVersion)" : ""
    return "iOS \(version.majorVersion).\(version.minorVersion)\(patch)"
  }

  /// The hardware identifier ("iPhone17,1") via `uname` — `UIDevice.model` only
  /// reports "iPhone", and `UIDevice` is main-actor-isolated.
  private static func deviceModel() -> String {
    var info = utsname()
    uname(&info)
    return withUnsafePointer(to: &info.machine) { pointer in
      pointer.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
    }
  }

  private static func levelName(_ level: OSLogEntryLog.Level) -> String {
    switch level {
    case .debug: return "debug"
    case .info: return "info"
    case .notice: return "notice"
    case .error: return "error"
    case .fault: return "fault"
    case .undefined: return "undefined"
    @unknown default: return "?"
    }
  }

  private static func fileStamp(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    return formatter.string(from: date)
  }
}
