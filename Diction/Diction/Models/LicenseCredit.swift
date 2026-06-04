import Foundation

/// A third-party component credited in Settings, with a link to its source and
/// the full license text bundled under `Resources/Licenses/<licenseResource>.txt`.
/// One source of truth for both the Acknowledgements section and the Licenses
/// screen.
nonisolated struct LicenseCredit: Identifiable, Sendable {
  let name: String
  let role: String
  let license: String        // "MIT" / "Apache 2.0"
  let author: String
  let urlString: String
  /// Filename stem under `Resources/Licenses/`. Apache components share one file.
  let licenseResource: String

  var id: String { name }
  var url: URL? { URL(string: urlString) }

  /// `host + path` for a compact, link-styled subtitle, e.g.
  /// "github.com/curiousdannii/emglken".
  var displayLink: String {
    guard let url, let host = url.host else { return urlString }
    return host + url.path
  }

  /// The bundled license text. Tries the bundle root, then a `Licenses`
  /// subdirectory, so it works whichever way the resources are copied.
  func licenseText() -> String {
    let bundle = Bundle.main
    let url = bundle.url(forResource: licenseResource, withExtension: "txt")
      ?? bundle.url(forResource: licenseResource, withExtension: "txt", subdirectory: "Licenses")
    guard let url, let text = try? String(contentsOf: url, encoding: .utf8) else {
      return "License text unavailable. See \(urlString)"
    }
    return text
  }

  /// Interpreters + Glk stack first, then the neural stack.
  static let all: [LicenseCredit] = [
    LicenseCredit(
      name: "Quixe", role: "Glulx interpreter + classic Glk stack", license: "MIT",
      author: "Andrew Plotkin", urlString: "https://github.com/erkyrath/quixe",
      licenseResource: "quixe"),
    LicenseCredit(
      name: "ifvms.js (ZVM)", role: "Z-machine interpreter", license: "MIT",
      author: "Dannii Willis", urlString: "https://github.com/curiousdannii/ifvms.js",
      licenseResource: "ifvms"),
    LicenseCredit(
      name: "FluidAudio", role: "Neural-voice runtime", license: "Apache 2.0",
      author: "FluidInference", urlString: "https://github.com/FluidInference/FluidAudio",
      licenseResource: "apache-2.0"),
    LicenseCredit(
      name: "Kokoro", role: "Neural-voice model", license: "Apache 2.0",
      author: "hexgrad", urlString: "https://github.com/hexgrad/kokoro",
      licenseResource: "apache-2.0"),
    LicenseCredit(
      name: "MisakiSwift", role: "Phonemizer — Swift port of misaki", license: "Apache 2.0",
      author: "mlalma", urlString: "https://github.com/mlalma/MisakiSwift",
      licenseResource: "apache-2.0"),
    LicenseCredit(
      name: "misaki", role: "Phonemizer — upstream", license: "Apache 2.0",
      author: "hexgrad", urlString: "https://github.com/hexgrad/misaki",
      licenseResource: "apache-2.0")
  ]
}
