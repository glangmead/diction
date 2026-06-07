import Foundation
import FluidAudio

// KokoroAudition — a macOS dev tool to audition the app's neural-voice pipeline.
//
// Shares the app's `KokoroPhonemizer`, `KokoroText`, `KokoroPCM`, and the
// `Interventions/` types by symlink, so edits to the app's copies are picked up
// here. By default it also loads the repo's `global.json` and applies its TTS
// interventions (pronunciations / textRules / pausePolicy), so the audition
// matches the app; `--no-profile` auditions the raw phonemizer.
//
// By default it reproduces the app's pipeline faithfully: `KokoroText.sentences`
// chunking (sentence split, dialogue-merge, trailing-terminator strip) →
// per-chunk synth → `KokoroPCM.trimSilence` → concatenate, *no* peak-
// normalization — the same audio `KokoroSpeechEngine` produces, minus the UI and
// the real-time inter-clip player gap. Each chunk's text and IPA are printed.
//
//   --raw   one phonemize of the whole text + one `synthesizeFromPhonemes`
//           (normalized WAV) — the old single-pass behavior.
//   --ipa   synthesize the given IPA directly; bypasses the phonemizer and
//           segmentation, so it implies --raw.
//   --file  read the text from a file instead of the positional argument,
//           preserving newlines exactly (path "-" reads stdin). Use this to feed
//           a whole multi-line chunk the way a game would; pair with --raw to see
//           whether embedded newlines reach the phonemizer.
//
//   KokoroAudition "your text" [--voice af_heart] [--speed 1.0] [--raw]
//                              [--file chunk.txt] [--output out.wav] [--no-play]
//                              [--bundle <path>]

func fail(_ message: String) -> Never {
  FileHandle.standardError.write(Data((message + "\n").utf8))
  exit(1)
}

func usage() -> Never {
  FileHandle.standardError.write(Data("""
  Usage: KokoroAudition "<text>" [--voice af_heart] [--speed 1.0] [--raw] \
  [--ipa <phonemes>] [--file <path | ->] [--output <path.wav>] [--no-play] \
  [--bundle <KokoroModels.bundle>] [--profile <profile.json>] [--no-profile]
  """.utf8))
  exit(2)
}

// MARK: - Arguments

var text: String?
var voice = "af_heart"
var speed: Float = 1.0
var play = true
var outputPath: String?
var bundlePath: String?
var ipaOverride: String?  // --ipa: synthesize this IPA directly, bypassing KokoroPhonemizer
var raw = false           // --raw: old single phonemize + single synthesize (normalized)
var filePath: String?     // --file: read text from a file (or "-" for stdin), newlines intact
var profilePath: String?  // --profile: a specific speech-profile JSON (default: repo global.json)
var noProfile = false     // --no-profile: audition the raw phonemizer, no interventions

let args = Array(CommandLine.arguments.dropFirst())
var index = 0
while index < args.count {
  let arg = args[index]
  func value() -> String {
    index += 1
    guard index < args.count else { usage() }
    return args[index]
  }
  switch arg {
  case "--voice": voice = value()
  case "--speed": speed = Float(value()) ?? speed
  case "--output", "-o": outputPath = value()
  case "--bundle": bundlePath = value()
  case "--ipa": ipaOverride = value()
  case "--file": filePath = value()
  case "--profile": profilePath = value()
  case "--no-profile": noProfile = true
  case "--raw": raw = true
  case "--no-play": play = false
  case "-h", "--help": usage()
  default:
    if arg.hasPrefix("-") { usage() }
    if text != nil { usage() }
    text = arg
  }
  index += 1
}

// Resolve the input: a file (or stdin via "-") overrides the positional text,
// preserving newlines exactly so they reach the pipeline as a game's chunk would.
let inputText: String?
if let filePath {
  if text != nil { fail("Provide either inline text or --file, not both.") }
  if filePath == "-" {
    inputText = String(data: FileHandle.standardInput.readDataToEndOfFile(), encoding: .utf8)
  } else if let contents = try? String(contentsOf: URL(fileURLWithPath: filePath), encoding: .utf8) {
    inputText = contents
  } else {
    fail("Could not read text file at \(filePath)")
  }
} else {
  inputText = text
}

guard let text = inputText, !text.isEmpty else { usage() }

// KokoroModels.bundle: default to the repo copy, derived from this source
// file's location (#filePath → …/Diction/KokoroAudition/main.swift), overridable.
let bundleRoot =
  bundlePath.map { URL(fileURLWithPath: $0) }
  ?? URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()  // KokoroAudition/
    .deletingLastPathComponent()  // Diction/ (project root)
    .appendingPathComponent("Diction/Resources/KokoroModels.bundle")

guard FileManager.default.fileExists(atPath: bundleRoot.path) else {
  fail("KokoroModels.bundle not found at \(bundleRoot.path)\nPass --bundle <path> to override.")
}

let output =
  outputPath.map { URL(fileURLWithPath: $0) }
  ?? URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("kokoro-audition.wav")

// Resolve the TTS interventions to apply. By default the tool mirrors the app:
// it loads the repo's global.json (derived from #filePath, like bundleRoot) so
// pronunciations / textRules / pausePolicy match what the app produces. --no-profile
// auditions the raw phonemizer; --profile <path> uses a specific profile file.
let ttsInterventions: TTSInterventions
if noProfile {
  ttsInterventions = .empty
} else {
  let profileURL =
    profilePath.map { URL(fileURLWithPath: $0) }
    ?? URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()  // KokoroAudition/
      .deletingLastPathComponent()  // Diction/ (project root)
      .appendingPathComponent("Diction/Resources/SpeechProfiles/global.json")
  guard let data = try? Data(contentsOf: profileURL) else {
    fail("Speech profile not found at \(profileURL.path)\nPass --profile <path> or --no-profile.")
  }
  guard let profile = try? SpeechProfile.decode(data) else {
    fail("Could not decode speech profile at \(profileURL.path)")
  }
  ttsInterventions = profile.tts
  FileHandle.standardError.write(
    Data("[audition] applying TTS interventions from \(profileURL.path)\n".utf8))
}

// MARK: - Synthesize → play

let manager = KokoroAneManager(variant: .english, directory: bundleRoot)
// bf_/bm_ are the British voice packs; everything else is US — same as the app.
let british = voice.hasPrefix("bf_") || voice.hasPrefix("bm_")

let wav: Data
if let ipaOverride {
  // Feed IPA directly, bypassing the phonemizer and segmentation.
  print(ipaOverride)
  wav = try await manager.synthesizeFromPhonemes(ipaOverride, voice: voice, speed: speed)
} else {
  guard var phonemizer = await KokoroPhonemizer.load(bundleRoot: bundleRoot) else {
    fail("KokoroPhonemizer failed to load from \(bundleRoot.path)")
  }
  phonemizer.tts = ttsInterventions   // apply global.json's pronunciations/textRules/pausePolicy
  if raw {
    // Old single-pass: whole text in one phonemize + one normalized synth.
    let ipa = try await phonemizer.phonemize(text, british: british)
    print(ipa)
    wav = try await manager.synthesizeFromPhonemes(ipa, voice: voice, speed: speed)
  } else {
    // App-faithful: chunk → per-chunk synth → trimSilence → concatenate (no norm).
    let chunks = KokoroText.sentences(text)
    guard !chunks.isEmpty else { fail("No speakable text after segmentation.") }
    var samples: [Float] = []
    var sampleRate = 24_000
    for (chunkIndex, chunk) in chunks.enumerated() {
      let ipa = try await phonemizer.phonemize(chunk, british: british)
      print("[chunk \(chunkIndex + 1)/\(chunks.count)] \"\(chunk)\" -> \(ipa)")
      let result = try await manager.synthesizeFromPhonemesDetailed(ipa, voice: voice, speed: speed)
      sampleRate = result.sampleRate
      samples += KokoroPCM.trimSilence(result.samples, sampleRate: result.sampleRate)
    }
    wav = KokoroPCM.wavData(samples, sampleRate: sampleRate)
  }
}
try wav.write(to: output)
FileHandle.standardError.write(
  Data("Wrote \(wav.count) bytes → \(output.path)  (voice=\(voice), speed=\(speed))\n".utf8))

if play {
  let player = Process()
  player.executableURL = URL(fileURLWithPath: "/usr/bin/afplay")
  player.arguments = [output.path]
  try player.run()
  player.waitUntilExit()
}
