import Foundation

/// One recovered log entry, decoupled from `OSLogEntryLog` (which has no public
/// initializer) so the formatting is pure and unit-testable.
struct DiagnosticsEntry: Sendable, Equatable {
  let date: Date
  let category: String
  let level: String
  let message: String
}

/// The device/app context stamped into the export header, gathered once by
/// `DiagnosticsExport` so the formatter stays pure.
struct DiagnosticsEnvironment: Sendable, Equatable {
  let appVersion: String
  let build: String
  let systemVersion: String
  let deviceModel: String
  let locale: String
}

/// Pure rendering of recovered log entries into the plain-text export. No I/O, no
/// platform reads — every input is passed in, so the output is deterministic and
/// testable. `DiagnosticsExport` supplies the entries and environment.
enum DiagnosticsFormatter {
  /// `2026-06-08T13:11:18.267Z [asr] notice  cycle end (final) …`
  static func line(for entry: DiagnosticsEntry) -> String {
    "\(timestamp(entry.date)) [\(entry.category)] \(entry.level)  \(entry.message)"
  }

  /// The file preamble: app build, OS, device, locale, and export time, so a log
  /// arriving by email carries its own context.
  static func header(environment: DiagnosticsEnvironment, exportedAt: Date) -> String {
    """
    Diction diagnostics
    App \(environment.appVersion) (\(environment.build)) · \(environment.systemVersion) \
    · \(environment.deviceModel) · \(environment.locale)
    Exported \(timestamp(exportedAt))
    ----------------------------------------
    """
  }

  private static func timestamp(_ date: Date) -> String {
    isoFormatter.string(from: date)
  }

  private static let isoFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    formatter.timeZone = TimeZone(identifier: "UTC")
    return formatter
  }()
}
