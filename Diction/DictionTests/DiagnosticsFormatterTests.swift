import Foundation
import Testing
@testable import Diction

@Suite("Diagnostics formatter")
struct DiagnosticsFormatterTests {
  @Test("a log line is timestamp, category, level, then message")
  func line() {
    let entry = DiagnosticsEntry(
      date: Date(timeIntervalSince1970: 0), category: "asr",
      level: "notice", message: "cycle end (final)")
    #expect(DiagnosticsFormatter.line(for: entry)
      == "1970-01-01T00:00:00.000Z [asr] notice  cycle end (final)")
  }

  @Test("the header carries app, OS, device, and locale context")
  func header() {
    let environment = DiagnosticsEnvironment(
      appVersion: "1.2", build: "34", systemVersion: "iOS 26.4",
      deviceModel: "iPhone17,1", locale: "en_US")
    let header = DiagnosticsFormatter.header(
      environment: environment, exportedAt: Date(timeIntervalSince1970: 0))
    #expect(header.contains("1.2 (34)"))
    #expect(header.contains("iOS 26.4"))
    #expect(header.contains("iPhone17,1"))
    #expect(header.contains("en_US"))
    #expect(header.contains("1970-01-01T00:00:00.000Z"))
  }
}
