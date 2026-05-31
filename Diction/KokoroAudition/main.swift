import Foundation
import FluidAudio

// KokoroAudition — a macOS dev tool to audition the app's KokoroPhonemizer.
//
// Runs the app's `KokoroPhonemizer` (shared into this target by symlink, so
// edits to the app's copy are picked up here) on a line of text, prints the
// resulting KokoroAne IPA, then synthesizes it through
// `KokoroAneManager.synthesizeFromPhonemes` and plays the WAV — the exact IPA
// path `KokoroSpeechEngine` uses in the app, minus the UI.
//
//   KokoroAudition "your text" [--voice af_heart] [--speed 1.0]
//                              [--output out.wav] [--no-play] [--bundle <path>]

func fail(_ message: String) -> Never {
  FileHandle.standardError.write(Data((message + "\n").utf8))
  exit(1)
}

func usage() -> Never {
  FileHandle.standardError.write(Data("""
  Usage: KokoroAudition "<text>" [--voice af_heart] [--speed 1.0] \
  [--output <path.wav>] [--no-play] [--bundle <KokoroModels.bundle>]
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
  case "--no-play": play = false
  case "-h", "--help": usage()
  default:
    if arg.hasPrefix("-") { usage() }
    if text != nil { usage() }
    text = arg
  }
  index += 1
}

guard let text, !text.isEmpty else { usage() }

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

// MARK: - Phonemize → synthesize → play

let ipa: String
if let ipaOverride {
  ipa = ipaOverride  // feed IPA directly, bypassing the phonemizer
} else {
  guard let phonemizer = await KokoroPhonemizer.load(bundleRoot: bundleRoot) else {
    fail("KokoroPhonemizer failed to load from \(bundleRoot.path)")
  }
  // bf_/bm_ are the British voice packs; everything else is US.
  let british = voice.hasPrefix("bf_") || voice.hasPrefix("bm_")
  ipa = try await phonemizer.phonemize(text, british: british)
}
print(ipa)  // stdout: the phoneme string fed to the model

let manager = KokoroAneManager(variant: .english, directory: bundleRoot)
let wav = try await manager.synthesizeFromPhonemes(ipa, voice: voice, speed: speed)
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
