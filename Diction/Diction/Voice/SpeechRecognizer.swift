import Speech
import AVFoundation

/// Push-to-talk speech recognition with vocabulary hints sourced from the
/// loaded story file. Uses on-device recognition where available.
@Observable
@MainActor
final class SpeechRecognizer {
  /// Live updated transcription text while listening.
  private(set) var transcription = ""

  private(set) var isListening = false

  private(set) var errorMessage: String?

  private let recognizer: SFSpeechRecognizer?
  private var audioEngine: AVAudioEngine?
  private var request: SFSpeechAudioBufferRecognitionRequest?
  private var task: SFSpeechRecognitionTask?

  init(locale: Locale = Locale(identifier: "en-US")) {
    recognizer = SFSpeechRecognizer(locale: locale)
    if recognizer?.supportsOnDeviceRecognition == true {
      // On-device recognition keeps data local and avoids network use.
    }
  }

  func requestAuthorization() async -> Bool {
    let speech = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
      SFSpeechRecognizer.requestAuthorization { status in
        continuation.resume(returning: status == .authorized)
      }
    }
    guard speech else { return false }

    let mic = await AVAudioApplication.requestRecordPermission()
    return mic
  }

  func startListening(contextualStrings: [String]) throws {
    guard let recognizer, recognizer.isAvailable else {
      errorMessage = "Speech recognition not available"
      return
    }
    errorMessage = nil

    let session = AVAudioSession.sharedInstance()
    try session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
    try session.setActive(true, options: .notifyOthersOnDeactivation)

    let req = SFSpeechAudioBufferRecognitionRequest()
    req.shouldReportPartialResults = true
    req.contextualStrings = Array(contextualStrings.prefix(200))
    if recognizer.supportsOnDeviceRecognition {
      req.requiresOnDeviceRecognition = true
    }
    self.request = req

    let engine = AVAudioEngine()
    self.audioEngine = engine

    let input = engine.inputNode
    let format = input.outputFormat(forBus: 0)
    input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
      req.append(buffer)
    }

    engine.prepare()
    try engine.start()

    transcription = ""
    isListening = true

    task = recognizer.recognitionTask(with: req) { [weak self] result, error in
      guard let self else { return }
      Task { @MainActor in
        if let result {
          self.transcription = result.bestTranscription.formattedString
        }
        if error != nil || (result?.isFinal ?? false) {
          self.isListening = false
        }
      }
    }
  }

  /// Stops listening and returns the final transcription string.
  @discardableResult
  func stopListening() -> String {
    audioEngine?.stop()
    audioEngine?.inputNode.removeTap(onBus: 0)
    request?.endAudio()
    task?.finish()

    audioEngine = nil
    request = nil
    task = nil
    isListening = false

    let result = transcription
    transcription = ""
    return result
  }
}
