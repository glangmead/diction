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

  /// Loads the story into a fresh emglken instance and returns the first update
  /// (the opening room + input request).
  func start(story: Data, engine: String, gameID: String) async throws -> RemGlkUpdate {
    self.gameID = gameID
    scheme.gameID = gameID
    scheme.storyData = story
    lastGen = 0
    // 1) Load the page and wait for the bridge module to finish evaluating.
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      bootContinuation = continuation
      webView.load(URLRequest(url: URL(string: "emglken://app/index.html")!))
    }
    // 2) Instantiate the engine; the first settled update resolves `pending`.
    return try await awaitNextUpdate {
      self.webView.evaluateJavaScript("window.emglkenStart('\(engine)'); 0", completionHandler: nil)
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
    webView.evaluateJavaScript("window.emglkenSendEvent('\(escaped)'); 0", completionHandler: nil)
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
    case "save_bytes": handleSaveBytes(payload)
    case "specialinput": handleSpecialInput(payload)
    case "update": handleUpdate(payload)
    default: break
    }
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

  private func handleSaveBytes(_ payload: Any?) {
    guard let body = payload as? [String: Any], let name = body["name"] as? String,
          let b64 = body["b64"] as? String, let data = Data(base64Encoded: b64),
          let url = SaveStorage.emglkenFileURL(gameID: gameID, basename: name) else { return }
    do {
      try data.write(to: url)
      log("save -> \(url.lastPathComponent) (\(data.count) bytes)")
    } catch { log("save write failed: \(error)") }
  }

  /// Answer fileref prompts. We send the filetype's name as the token; remglk-rs
  /// appends its own extension and Dialog.read/write surface the resulting
  /// basename, which we store per-game. The follow-up update (with the save
  /// written / restore applied) is what resolves `pending`.
  private func handleSpecialInput(_ payload: Any?) {
    guard let json = payload as? String, let data = json.data(using: .utf8),
          let req = try? JSONDecoder().decode(RemGlkUpdate.SpecialRequest.self, from: data) else { return }
    let response = EmglkenFilerefResponse(
      gen: lastGen, response: req.type, value: .init(filename: req.filetype.rawValue))
    send(response)
  }

  private func handleUpdate(_ payload: Any?) {
    guard let raw = payload,
          let data = try? JSONSerialization.data(withJSONObject: raw),
          let update = try? JSONDecoder().decode(RemGlkUpdate.self, from: data) else { return }
    if let gen = update.gen { lastGen = gen }
    // A specialinput update is NOT settled — we answer it (above) and keep
    // waiting. Any other update is what the caller awaited.
    if update.specialinput == nil {
      pending?.resume(returning: update)
      pending = nil
    }
  }
}

/// The fileref answer remglk-rs (WASM) requires: it is stricter than C RemGlk and
/// needs both `response` (which prompt is being answered) and `value` as an object
/// `{filename}`. (The old `RemGlkSpecialResponse`, with `value: String?`, is the
/// C-RemGlk shape and is deleted in a later task.)
struct EmglkenFilerefResponse: Encodable {
  let type = "specialresponse"
  let gen: Int
  let response: String
  struct Value: Encodable { let filename: String }
  let value: Value
}

/// Serves the bundled emglken assets, the current story bytes, and per-game save
/// files over the `emglken://app/...` origin (ES-module import + wasm fetch are
/// blocked from file://). A missing save returns 404 (normal pre-save) so the
/// JS `fetch` resolves with `!ok` rather than throwing.
@MainActor
final class EmglkenSchemeHandler: NSObject, WKURLSchemeHandler {
  var storyData: Data?
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

  private func resource(for path: String) -> (Data?, String) {
    switch path {
    case "", "/", "/index.html": return (bundleData("emglken-bridge", "html"), "text/html")
    case "/emglken-bridge.js": return (bundleData("emglken-bridge", "js"), "text/javascript")
    case "/glulxe.js": return (bundleData("glulxe", "js"), "text/javascript")
    case "/glulxe.wasm": return (bundleData("glulxe", "wasm"), "application/wasm")
    case "/bocfel.js": return (bundleData("bocfel", "js"), "text/javascript")
    case "/bocfel.wasm": return (bundleData("bocfel", "wasm"), "application/wasm")
    case "/file/storyfile": return (storyData, "application/octet-stream")
    case let savePath where savePath.hasPrefix("/save/"):
      let name = String(savePath.dropFirst("/save/".count))
      let url = SaveStorage.emglkenFileURL(gameID: gameID, basename: name)
      return (url.flatMap { try? Data(contentsOf: $0) }, "application/octet-stream")
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
