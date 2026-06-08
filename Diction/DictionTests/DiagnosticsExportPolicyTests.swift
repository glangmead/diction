import Foundation
import Testing
@testable import Diction

@Suite("Diagnostics export policy")
struct DiagnosticsExportPolicyTests {
  @Test("the export window starts 30 minutes before now")
  func window() {
    let now = Date(timeIntervalSince1970: 10_000)
    #expect(DiagnosticsExportPolicy.windowStart(from: now) == now.addingTimeInterval(-1800))
  }

  @Test("the entry cap bounds the export size")
  func cap() {
    #expect(DiagnosticsExportPolicy.entryCap == 5000)
  }
}
