import Testing
import Foundation
@testable import Diction

// The Kokoro duration model pads roughly 290 ms of leading and 490 ms of
// trailing silence onto every clip. Because the engine synthesizes one clip
// per sentence, those pads stack into a ~780 ms gap at each sentence boundary.
// `KokoroPCM.trimSilence` cuts each clip down to a short, controlled gap.

@Test("Trims leading and trailing model silence to a small controlled gap")
func trimsSilence() {
  let sampleRate = 1000
  var samples = [Float](repeating: 0, count: 1000)   // 1.0 s leading silence
  samples += [Float](repeating: 1.0, count: 500)     // 0.5 s tone
  samples += [Float](repeating: 0, count: 1000)      // 1.0 s trailing silence

  let out = KokoroPCM.trimSilence(
    samples, sampleRate: sampleRate, head: 0.02, tail: 0.12, relativeThreshold: 0.02
  )

  #expect(out.count == 640)                                       // 20 + 500 + 120
  #expect(out.filter { $0 == 1.0 }.count == 500)                  // tone preserved whole
  #expect(out.prefix(while: { $0 == 0 }).count == 20)             // 20 ms head pre-roll
  #expect(out.reversed().prefix(while: { $0 == 0 }).count == 120) // 120 ms tail gap
}

@Test("An all-silence clip trims to nothing")
func trimsAllSilence() {
  #expect(KokoroPCM.trimSilence([Float](repeating: 0, count: 500), sampleRate: 1000).isEmpty)
}

@Test("Empty input is returned unchanged")
func trimsEmpty() {
  #expect(KokoroPCM.trimSilence([], sampleRate: 24_000).isEmpty)
}

@Test("wavData writes a 44-byte PCM header sized to the samples")
func wavHeader() {
  let data = KokoroPCM.wavData([0, 0.5, -0.5, 1.0], sampleRate: 24_000)

  #expect(data.count == 44 + 4 * 2)
  #expect(data.prefix(4) == Data("RIFF".utf8))
  #expect(data.subdata(in: 8..<12) == Data("WAVE".utf8))
  #expect(data.subdata(in: 36..<40) == Data("data".utf8))

  // data-chunk byte count lives at offset 40 as a little-endian UInt32.
  let sizeBytes = Array(data[40..<44])
  let dataSize = UInt32(sizeBytes[0]) | UInt32(sizeBytes[1]) << 8
    | UInt32(sizeBytes[2]) << 16 | UInt32(sizeBytes[3]) << 24
  #expect(dataSize == 8)
}
