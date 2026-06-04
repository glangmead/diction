import Foundation
import WebKit

/// Serves, over the `glk://app/...` origin, the bundled interpreter assets (the
/// classic Glk stack + ZVM/Quixe), the current story bytes, the resume snapshot,
/// and the manual save slot. A custom scheme rather than `file://` because local
/// script fetches are blocked from a `file://` page.
@MainActor
final class GlkSchemeHandler: NSObject, WKURLSchemeHandler {
  var storyData: Data?
  /// VM autosave snapshot (JSON) to resume from, served at /restore. Nil → 404,
  /// so the bridge starts fresh.
  var restoreData: Data?
  /// The game's manual SAVE slot bytes, served at /savedata so the bridge can
  /// seed `saveSlot` before a RESTORE. Nil → 404, so the bridge starts with no
  /// save (the game's RESTORE then reports "no saved game").
  var saveData: Data?
  var gameID = ""

  func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
    guard let url = task.request.url else { task.didFailWithError(URLError(.badURL)); return }
    let path = url.path
    let (data, mime) = resource(for: path)
    let status = data == nil ? 404 : 200
    // /restore and /savedata 404 by design when there's nothing to resume/seed;
    // don't treat that as an error worth logging.
    if data == nil && path != "/restore" && path != "/savedata" {
      FileHandle.standardError.write(Data("[glk] scheme 404: \(path)\n".utf8))
    }
    let response = HTTPURLResponse(
      url: url, statusCode: status, httpVersion: "HTTP/1.1",
      headerFields: ["Content-Type": mime, "Content-Length": "\(data?.count ?? 0)"])!
    task.didReceive(response)
    if let data { task.didReceive(data) }
    task.didFinish()
  }

  func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}

  /// Static bundle assets, keyed by request path → (resource name, extension).
  /// MIME is derived from the extension. The classic Glk stack (glkapi/dialog/
  /// dispatch) plus the VMs (Quixe for Glulx, ZVM for Z-machine). Dynamic paths
  /// (story / restore / save) are handled separately.
  private static let bundleAssets: [String: (name: String, ext: String)] = [
    "": ("glk-bridge", "html"),
    "/": ("glk-bridge", "html"),
    "/index.html": ("glk-bridge", "html"),
    "/glk-bridge.html": ("glk-bridge", "html"),
    "/glk-bridge.js": ("glk-bridge", "js"),
    "/glkapi.js": ("glkapi", "js"),
    "/gi_blorb.js": ("gi_blorb", "js"),
    "/gi_dispa.js": ("gi_dispa", "js"),
    "/gi_load.js": ("gi_load", "js"),
    "/quixe.min.js": ("quixe.min", "js"),
    "/zvm.js": ("zvm", "js"),
    "/zvm_dispatch.js": ("zvm_dispatch", "js")
  ]

  private static func mime(forExt ext: String) -> String {
    switch ext {
    case "html": "text/html"
    case "js": "text/javascript"
    default: "application/octet-stream"
    }
  }

  private func resource(for path: String) -> (Data?, String) {
    if let asset = Self.bundleAssets[path] {
      return (bundleData(asset.name, asset.ext), Self.mime(forExt: asset.ext))
    }
    switch path {
    case "/file/storyfile": return (storyData, "application/octet-stream")
    case "/restore": return (restoreData, "application/json")
    case "/savedata": return (saveData, "application/octet-stream")
    default: return (nil, "application/octet-stream")
    }
  }

  /// Synchronized root groups flatten resources to the bundle root; fall back to
  /// an `Interpreter/Resources` subdirectory in case a future project layout
  /// preserves the folder.
  private func bundleData(_ name: String, _ ext: String) -> Data? {
    let url = Bundle.main.url(forResource: name, withExtension: ext)
      ?? Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Resources")
    guard let url else {
      FileHandle.standardError.write(Data("[glk] bundle missing: \(name).\(ext)\n".utf8))
      return nil
    }
    return try? Data(contentsOf: url)
  }
}
