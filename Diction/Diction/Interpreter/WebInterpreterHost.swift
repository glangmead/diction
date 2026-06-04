import Foundation
import WebKit

/// Drives an emglken interpreter in a headless WKWebView, exchanging RemGlk
/// JSON. `start`/`send` are async and resume on the next "settled" update — one
/// with no pending `specialinput`. Fileref `specialinput`s (save/restore) are
/// answered internally and their bytes routed to `SaveStorage`. Each game gets a
/// fresh page load (and thus fresh emglken globals), so re-entrancy is solved by
/// construction.
@MainActor
final class WebInterpreterHost: NSObject {
  enum HostError: Error { case loadFailed, bridge(String) }

  private var webView: WKWebView!
  private let scheme = EmglkenSchemeHandler()
  /// Resolved when the bridge posts `bridge_loaded` after a page load.
  private var bootContinuation: CheckedContinuation<Void, Error>?
  /// Resolved by the next settled update after a `start`/`send` trigger.
  private var pending: CheckedContinuation<RemGlkUpdate, Error>?
  /// Latest generation seen; used to stamp the fileref response.
  private var lastGen = 0
  private var gameID = ""
  /// Latest VM autosave snapshot (JSON) posted by the bridge after a move, or
  /// nil. This is the engine artifact `InterpreterSession` pairs with its
  /// presentation snapshot and persists via `GameSnapshotStore`.
  private(set) var latestAutosave: String?

  override init() {
    super.init()
    let config = WKWebViewConfiguration()
    config.setURLSchemeHandler(scheme, forURLScheme: "emglken")
    let ucc = WKUserContentController()
    ucc.add(self, name: "interp")
    config.userContentController = ucc
    webView = WKWebView(frame: .zero, configuration: config)
    webView.navigationDelegate = self
  }

  /// Loads the story into a fresh ZVM/Quixe instance and returns the first update
  /// (the opening room + input request). `engine` is "zvm" (Z-machine) or "quixe"
  /// (Glulx). `restore`, if present, is a VM autosave snapshot (JSON) to resume
  /// from; it is served at /restore so the bridge can read it synchronously
  /// before `prepare()`.
  func start(story: Data, engine: String, gameID: String, restore: Data? = nil) async throws -> RemGlkUpdate {
    self.gameID = gameID
    scheme.gameID = gameID
    scheme.storyData = story
    scheme.restoreData = restore
    lastGen = 0
    latestAutosave = nil
    // 1) Load the classic-Glk bridge page; wait for its scripts to evaluate.
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      bootContinuation = continuation
      webView.load(URLRequest(url: URL(string: "emglken://app/glk-bridge.html")!))
    }
    // 2) Boot the VM; the first settled update resolves `pending`.
    return try await awaitNextUpdate {
      self.webView.evaluateJavaScript("window.glkStart('\(engine)'); 0", completionHandler: nil)
    }
  }

  /// Tears down the webview/instance. Safe to call once; resolves any in-flight
  /// awaiter with an error so callers don't hang.
  func teardown() {
    webView.stopLoading()
    // Break the WKUserContentController → self strong reference (set up by
    // `ucc.add(self, …)` in init) so this host — and its webview + WASM
    // instance — can actually deinit when the game closes. Without this, every
    // game open leaks one webview, defeating "fresh instance per game".
    webView.configuration.userContentController.removeAllScriptMessageHandlers()
    bootContinuation?.resume(throwing: HostError.loadFailed)
    bootContinuation = nil
    pending?.resume(throwing: HostError.loadFailed)
    pending = nil
  }

  /// Runs `trigger` (which injects a JS event) and suspends until the next
  /// settled update arrives on the message handler.
  func awaitNextUpdate(_ trigger: @escaping () -> Void) async throws -> RemGlkUpdate {
    try await withCheckedThrowingContinuation { continuation in
      pending = continuation
      trigger()
    }
  }

  func send(line: String, gen: Int, window: Int) async throws -> RemGlkUpdate {
    try await awaitNextUpdate { self.send(RemGlkLineInput(gen: gen, window: window, value: line)) }
  }

  func send(char: String, gen: Int, window: Int) async throws -> RemGlkUpdate {
    try await awaitNextUpdate { self.send(RemGlkCharInput(gen: gen, window: window, value: char)) }
  }

  /// Fire-and-forget event injection: encode to JSON, escape for a single-quoted
  /// JS string literal, and hand it to the bridge.
  func send<T: Encodable>(_ event: T) {
    guard let data = try? JSONEncoder().encode(event),
          let json = String(data: data, encoding: .utf8) else { return }
    let escaped = json
      .replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "'", with: "\\'")
      .replacingOccurrences(of: "\n", with: "\\n")
      .replacingOccurrences(of: "\r", with: "\\r")
    webView.evaluateJavaScript("window.glkSendEvent('\(escaped)'); 0", completionHandler: nil)
  }

  func log(_ message: String) { FileHandle.standardError.write(Data("[emglken] \(message)\n".utf8)) }
}

extension WebInterpreterHost: WKNavigationDelegate {
  func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
    bootContinuation?.resume(throwing: HostError.loadFailed)
    bootContinuation = nil
  }

  func webView(
    _ webView: WKWebView,
    didFailProvisionalNavigation navigation: WKNavigation!,
    withError error: Error
  ) {
    bootContinuation?.resume(throwing: HostError.loadFailed)
    bootContinuation = nil
  }
}

extension WebInterpreterHost: WKScriptMessageHandler {
  func userContentController(
    _ userContentController: WKUserContentController,
    didReceive message: WKScriptMessage
  ) {
    guard let dict = message.body as? [String: Any] else { return }
    let payload = dict["payload"]

    switch dict["stage"] as? String ?? "?" {
    case "bridge_loaded": handleBridgeLoaded()
    case "error": handleError(payload)
    case "autosave": handleAutosave(payload)
    case "update": handleUpdate(payload)
    default: break
    }
  }

  /// The VM's per-move autosave snapshot (JSON), or nil when the bridge signals a
  /// delete (no snapshot). Held until the caller captures it after a move.
  private func handleAutosave(_ payload: Any?) {
    latestAutosave = payload as? String
  }

  private func handleBridgeLoaded() {
    bootContinuation?.resume()
    bootContinuation = nil
  }

  private func handleError(_ payload: Any?) {
    let msg = String(describing: payload ?? "unknown")
    log("bridge error: \(msg)")
    bootContinuation?.resume(throwing: HostError.bridge(msg))
    bootContinuation = nil
    pending?.resume(throwing: HostError.bridge(msg))
    pending = nil
  }

  private func handleUpdate(_ payload: Any?) {
    guard let raw = payload,
          let data = try? JSONSerialization.data(withJSONObject: raw),
          let update = try? JSONDecoder().decode(RemGlkUpdate.self, from: data) else { return }
    if let gen = update.gen { lastGen = gen }
    pending?.resume(returning: update)
    pending = nil
  }
}

/// Serves the bundled interpreter assets (the classic Glk stack + ZVM/Quixe),
/// the current story bytes, and the resume snapshot over the `glk://app/...`
/// origin (script + wasm fetch are blocked from file://). The scheme is still
/// registered as "emglken" for now; renaming it is a cosmetic follow-up.
@MainActor
final class EmglkenSchemeHandler: NSObject, WKURLSchemeHandler {
  var storyData: Data?
  /// VM autosave snapshot (JSON) to resume from, served at /restore. Nil → 404,
  /// so the bridge starts fresh.
  var restoreData: Data?
  var gameID = ""

  func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
    guard let url = task.request.url else { task.didFailWithError(URLError(.badURL)); return }
    let path = url.path
    let (data, mime) = resource(for: path)
    let status = data == nil ? 404 : 200
    if data == nil && !path.hasPrefix("/save/") {
      FileHandle.standardError.write(Data("[emglken] scheme 404: \(path)\n".utf8))
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
  /// (story / restore) are handled separately.
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
    case "wasm": "application/wasm"
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
      FileHandle.standardError.write(Data("[emglken] bundle missing: \(name).\(ext)\n".utf8))
      return nil
    }
    return try? Data(contentsOf: url)
  }
}
