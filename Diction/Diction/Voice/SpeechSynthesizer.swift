import Foundation
import AVFoundation

/// Speaks game output and command echoes. Echoes use a lower pitch so the
/// user can hear them as distinct from the game's voice.
@Observable
@MainActor
final class SpeechSynthesizer: NSObject {
  private(set) var isSpeaking = false

  private let synthesizer = AVSpeechSynthesizer()
  private var pendingContinuations: [CheckedContinuation<Void, Never>] = []

  override init() {
    super.init()
    synthesizer.delegate = self
  }

  func speakCommandEcho(_ command: String) async {
    let utterance = AVSpeechUtterance(string: command)
    utterance.voice = selectedVoice()
    utterance.rate = AVSpeechUtteranceDefaultSpeechRate
    utterance.pitchMultiplier = 0.85
    utterance.preUtteranceDelay = 0.1
    utterance.postUtteranceDelay = 0.4
    await enqueue(utterance)
  }

  /// Speaks the plain text of a styled entry, applying minor prosody from style.
  func speak(_ styledText: StyledText) async {
    for run in styledText.runs {
      let speakable = Self.cleanForSpeech(run.text)
      guard !speakable.isEmpty else { continue }

      let utterance = AVSpeechUtterance(string: speakable)
      utterance.voice = selectedVoice()
      utterance.rate = speechRate

      switch run.style {
      case .header, .subheader:
        utterance.rate = speechRate * 0.9
        utterance.preUtteranceDelay = 0.3
        utterance.postUtteranceDelay = 0.3
      case .emphasized:
        utterance.pitchMultiplier = 1.1
      case .alert, .note:
        utterance.preUtteranceDelay = 0.2
      default:
        break
      }

      await enqueue(utterance)
    }
  }

  func stop() {
    synthesizer.stopSpeaking(at: .immediate)
    isSpeaking = false
    for continuation in pendingContinuations {
      continuation.resume()
    }
    pendingContinuations.removeAll()
  }

  // MARK: - Internals

  private func enqueue(_ utterance: AVSpeechUtterance) async {
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      pendingContinuations.append(continuation)
      isSpeaking = true
      synthesizer.speak(utterance)
    }
  }

  private var speechRate: Float {
    let stored = UserDefaults.standard.float(forKey: "speechRate")
    return stored > 0 ? Float(stored) : AVSpeechUtteranceDefaultSpeechRate
  }

  private func selectedVoice() -> AVSpeechSynthesisVoice? {
    let id = UserDefaults.standard.string(forKey: "speechVoiceId") ?? ""
    return id.isEmpty ? nil : AVSpeechSynthesisVoice(identifier: id)
  }

  /// Strips leading/trailing whitespace and parser prompt characters (`>`)
  /// from text before synthesis. AVSpeechSynthesizer would otherwise
  /// pronounce ">" as "greater than sign", which is just noise.
  nonisolated private static let promptCharacters = CharacterSet(charactersIn: ">")

  nonisolated private static func cleanForSpeech(_ text: String) -> String {
    text.trimmingCharacters(in: .whitespacesAndNewlines)
      .trimmingCharacters(in: promptCharacters)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func didFinishUtterance() {
    if let next = pendingContinuations.first {
      pendingContinuations.removeFirst()
      next.resume()
    }
    if pendingContinuations.isEmpty {
      isSpeaking = false
    }
  }
}

extension SpeechSynthesizer: AVSpeechSynthesizerDelegate {
  nonisolated func speechSynthesizer(
    _ synthesizer: AVSpeechSynthesizer,
    didFinish utterance: AVSpeechUtterance
  ) {
    Task { @MainActor in
      didFinishUtterance()
    }
  }

  nonisolated func speechSynthesizer(
    _ synthesizer: AVSpeechSynthesizer,
    didCancel utterance: AVSpeechUtterance
  ) {
    Task { @MainActor in
      didFinishUtterance()
    }
  }
}
