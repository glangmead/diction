// Regression coverage for `FormatDetector.detect(url:)` on image-heavy Blorbs.
//
// The bug: `detect(url:)` read only the first 4 KiB and linearly scanned for
// the inner-VM magic. In Blorbs whose resource index lists `Pict` (image)
// chunks before the `Exec` chunk, the `GLUL`/`ZCOD` chunk lives far past
// 4 KiB, so the scan found nothing and `detect` returned nil. The fix parses
// the RIdx to locate the `Exec` resource's absolute offset and seeks there.

import Testing
import Foundation
@testable import Diction

// MARK: - Synthetic Blorb builder

/// Big-endian 4-byte encoding of an unsigned 32-bit value.
private func be32(_ value: UInt32) -> [UInt8] {
  [
    UInt8((value >> 24) & 0xFF),
    UInt8((value >> 16) & 0xFF),
    UInt8((value >> 8) & 0xFF),
    UInt8(value & 0xFF)
  ]
}

private func ascii(_ string: String) -> [UInt8] { Array(string.utf8) }

/// Assembles a minimal Blorb whose RIdx lists a `Pict` resource *before* the
/// `Exec` resource, with the Pict chunk padded so the Exec chunk's type magic
/// (`execType`, e.g. `GLUL`/`ZCOD`) starts at a file offset past `pushExecPast`.
/// Returns the file bytes plus the absolute offset where the Exec chunk begins.
private func makeImageHeavyBlorb(
  execType: String,
  pushExecPast: Int
) -> (bytes: [UInt8], execChunkStart: Int) {
  // FORM(4) + formLen(4) + IFRS(4) = 12 bytes of preamble.
  let preambleCount = 12
  // RIdx chunk: type(4) + len(4) + count(4) + 2 entries * 12 bytes.
  let entryCount = 2
  let ridxDataCount = 4 + entryCount * 12          // count + entries
  let ridxChunkCount = 8 + ridxDataCount           // type + len + data
  let pictChunkStart = preambleCount + ridxChunkCount

  // Size the Pict chunk so the Exec chunk that follows starts past the window.
  // Exec starts at pictChunkStart + 8 (Pict type+len) + pictDataCount.
  let minExecStart = pushExecPast + 1
  let pictDataCount = max(0, minExecStart - (pictChunkStart + 8))
  let execChunkStart = pictChunkStart + 8 + pictDataCount

  var bytes: [UInt8] = []

  // Preamble. The FORM length nominally covers everything after the length
  // field; detection never validates it, so an approximate value is fine.
  bytes += ascii("FORM")
  bytes += be32(0)                                 // placeholder, fixed up below
  bytes += ascii("IFRS")

  // RIdx chunk.
  bytes += ascii("RIdx")
  bytes += be32(UInt32(ridxDataCount))
  bytes += be32(UInt32(entryCount))
  // Entry 1: a Pict resource pointing at the Pict chunk.
  bytes += ascii("Pict")
  bytes += be32(1)                                 // resource number
  bytes += be32(UInt32(pictChunkStart))            // absolute start
  // Entry 2: the Exec resource pointing at the VM chunk.
  bytes += ascii("Exec")
  bytes += be32(0)
  bytes += be32(UInt32(execChunkStart))            // absolute start

  // Pict chunk: type + length + padded data.
  bytes += ascii("Pict")
  bytes += be32(UInt32(pictDataCount))
  bytes += [UInt8](repeating: 0xAB, count: pictDataCount)

  // Exec chunk: the VM type magic + a small body.
  bytes += ascii(execType)
  bytes += be32(8)
  bytes += [UInt8](repeating: 0x00, count: 8)

  // Fix up the FORM length to span everything past the length field.
  let formLen = UInt32(bytes.count - 8)
  for (index, byte) in be32(formLen).enumerated() {
    bytes[4 + index] = byte
  }

  return (bytes, execChunkStart)
}

private func writeTempBlorb(_ bytes: [UInt8], ext: String) throws -> URL {
  let url = FileManager.default.temporaryDirectory
    .appendingPathComponent("\(UUID().uuidString).\(ext)")
  try Data(bytes).write(to: url)
  return url
}

// MARK: - Tests

@Test("detect(url:) finds a Glulx Exec chunk that begins past the 4 KiB window")
func glulxExecBeyondHeaderWindow() throws {
  let (bytes, execStart) = makeImageHeavyBlorb(execType: "GLUL", pushExecPast: 4096)
  #expect(execStart > 4096)  // the bug's precondition: GLUL is past the old window

  let url = try writeTempBlorb(bytes, ext: "gblorb")
  defer { try? FileManager.default.removeItem(at: url) }

  #expect(try FormatDetector.detect(url: url) == .glulx)
}

@Test("detect(url:) finds a Z-machine Exec chunk that begins past the 4 KiB window")
func zMachineExecBeyondHeaderWindow() throws {
  let (bytes, execStart) = makeImageHeavyBlorb(execType: "ZCOD", pushExecPast: 4096)
  #expect(execStart > 4096)

  let url = try writeTempBlorb(bytes, ext: "zblorb")
  defer { try? FileManager.default.removeItem(at: url) }

  #expect(try FormatDetector.detect(url: url) == .zMachine)
}

@Test("execChunkOffset(inBlorbHeader:) reads the Exec resource's absolute start")
func execChunkOffsetParsesRIdx() {
  let (bytes, execStart) = makeImageHeavyBlorb(execType: "GLUL", pushExecPast: 4096)
  #expect(FormatDetector.execChunkOffset(inBlorbHeader: bytes) == execStart)

  // Non-blorb input yields nil rather than a bogus offset.
  #expect(FormatDetector.execChunkOffset(inBlorbHeader: Array("not a blorb!!".utf8)) == nil)
}

@Test("detect(url:) still resolves a Blorb whose Exec chunk sits within the window")
func execWithinHeaderWindowStillWorks() throws {
  // Push the Exec chunk only slightly past the RIdx, well inside 4 KiB. This
  // guards the in-window path the original scan handled.
  let (bytes, execStart) = makeImageHeavyBlorb(execType: "GLUL", pushExecPast: 64)
  #expect(execStart < 4096)

  let url = try writeTempBlorb(bytes, ext: "gblorb")
  defer { try? FileManager.default.removeItem(at: url) }

  #expect(try FormatDetector.detect(url: url) == .glulx)
}
