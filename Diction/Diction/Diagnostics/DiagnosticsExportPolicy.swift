import Foundation

/// Bounds on what the diagnostics export pulls out of `OSLogStore`: a recent time
/// window and an entry ceiling, whichever is hit first. Sized to keep the export
/// fast and the file small while covering a "reproduce, then export" session.
enum DiagnosticsExportPolicy {
  /// How far back the export reaches. Long enough to capture the lead-up to a
  /// reproduced issue, short enough that the read and file stay small.
  static let window: TimeInterval = 30 * 60

  /// Hard ceiling on entries serialized, so a chatty session can't produce a
  /// multi-megabyte file or a slow read.
  static let entryCap = 5000

  /// The earliest timestamp the export should include, given the current time.
  static func windowStart(from now: Date) -> Date {
    now.addingTimeInterval(-window)
  }
}
