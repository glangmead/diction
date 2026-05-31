import Foundation

/// Pure helpers for a Kokoro neural-TTS clip: trimming the model's leading and
/// trailing silence, and wrapping raw fp32 PCM as a 16-bit WAV that
/// `AVAudioPlayer` can read. Kept out of `KokoroSpeechEngine` so the silence
/// logic is unit-testable without loading the CoreML models.
enum KokoroPCM {
  /// Trim near-silent head and tail from `samples`, keeping a short `head`
  /// pre-roll before speech starts and `tail` seconds of gap after it ends.
  ///
  /// The Kokoro duration model pads roughly 290 ms of leading and 490 ms of
  /// trailing silence onto every clip (measured against the bundled voices).
  /// Because the engine synthesizes one clip per sentence, those pads stack
  /// into a ~780 ms gap at each sentence boundary — the "super long" pause.
  /// Trimming to a small controlled `tail` is what shortens it; the head/tail
  /// margins keep onsets and final-phoneme decays from sounding clipped.
  ///
  /// `relativeThreshold` is the silence cutoff as a fraction of the clip's
  /// peak amplitude (2 % matches the model's noise floor).
  static func trimSilence(
    _ samples: [Float],
    sampleRate: Int,
    head: Double = 0.02,
    tail: Double = 0.12,
    relativeThreshold: Float = 0.02
  ) -> [Float] {
    guard !samples.isEmpty else { return samples }

    var peak: Float = 0
    for sample in samples { peak = max(peak, abs(sample)) }
    guard peak > 0 else { return [] }

    let threshold = peak * relativeThreshold
    guard let first = samples.firstIndex(where: { abs($0) >= threshold }),
          let last = samples.lastIndex(where: { abs($0) >= threshold }) else {
      return []
    }

    let start = max(0, first - Int(head * Double(sampleRate)))
    let end = min(samples.count, last + 1 + Int(tail * Double(sampleRate)))
    return Array(samples[start..<end])
  }

  /// Wrap mono fp32 PCM as a little-endian 16-bit PCM WAV.
  static func wavData(_ samples: [Float], sampleRate: Int) -> Data {
    let bytesPerSample = 2
    let dataSize = samples.count * bytesPerSample
    let byteRate = sampleRate * bytesPerSample

    var data = Data(capacity: 44 + dataSize)
    func appendLE<T: FixedWidthInteger>(_ value: T) {
      var little = value.littleEndian
      withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
    }

    data.append(contentsOf: Array("RIFF".utf8))
    appendLE(UInt32(36 + dataSize))
    data.append(contentsOf: Array("WAVE".utf8))

    data.append(contentsOf: Array("fmt ".utf8))
    appendLE(UInt32(16))                  // fmt chunk size
    appendLE(UInt16(1))                   // audio format: PCM
    appendLE(UInt16(1))                   // channels: mono
    appendLE(UInt32(sampleRate))
    appendLE(UInt32(byteRate))
    appendLE(UInt16(bytesPerSample))      // block align
    appendLE(UInt16(16))                  // bits per sample

    data.append(contentsOf: Array("data".utf8))
    appendLE(UInt32(dataSize))
    for sample in samples {
      let clamped = max(-1, min(1, sample))
      appendLE(Int16(clamped * 32_767))
    }
    return data
  }
}
