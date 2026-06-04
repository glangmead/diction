import Testing
import Foundation
@testable import Diction

@Test("z-machine version byte is read from raw and blorb headers")
func zMachineVersionDetection() {
  #expect(FormatDetector.zMachineVersion(header: Data([3, 0, 0, 0])) == 3)
  #expect(FormatDetector.zMachineVersion(header: Data([8, 0, 0, 0])) == 8)
  #expect(FormatDetector.zMachineVersion(header: Data([6, 0, 0, 0])) == 6)
  // Glulx magic "Glul" is not a Z-machine header.
  #expect(FormatDetector.zMachineVersion(header: Data([0x47, 0x6C, 0x75, 0x6C])) == nil)
}

@Test("supported Z-machine versions are 3/4/5/8")
func supportedZVersions() {
  #expect(FormatDetector.supportedZMachineVersions == [3, 4, 5, 8])
}

@MainActor
@Test("loading an unsupported Z-machine version throws before reaching the VM")
func unsupportedZVersionRejected() async throws {
  let tmp = FileManager.default.temporaryDirectory
    .appendingPathComponent("\(UUID().uuidString).z6")
  try Data([6, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]).write(to: tmp)
  defer { try? FileManager.default.removeItem(at: tmp) }

  let session = InterpreterSession()
  await #expect(throws: InterpreterError.self) {
    try await session.load(tmp)
  }
}
