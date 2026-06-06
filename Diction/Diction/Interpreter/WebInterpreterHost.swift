import Foundation
import WebKit

/// Drives a classic-Glk interpreter (ZVM for Z-machine, Quixe for Glulx, both
/// JavaScript) in a headless WKWebView, exchanging RemGlk JSON. `start`/`send`
/// are async and resume on the next "settled" update — one with no pending
/// `specialinput`. Fileref `specialinput`s (save/restore) are answered internally
/// and their bytes routed to `SaveStorage`. Each game gets a fresh page load (and
/// thus fresh interpreter globals), so re-entrancy is solved by construction.
@MainActor
final class WebInterpreterHost: NSObject {
  enum HostError: Error { case loadFailed, bridge(String) }

  /// The interpreter's WKWebView. Surfaced for display: now that the real GlkOte
  /// renders text/grid/graphics/images inside this page, the rendered output is
  /// the on-screen surface, so the view layer wraps this same instance rather
  /// than a separate native transcript.
  private(set) var webView: WKWebView!
  private let scheme = GlkSchemeHandler()
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

  /// Invoked for every update received from the bridge — settled or intermediate
  /// — so the session can apply content / window / narration state from each.
  /// The async `start`/`send` complete only on a *settled* update (see
  /// `handleUpdate`), so this fires for the arrange/redraw frames that real GlkOte
  /// emits mid-turn before the game re-requests input.
  var onUpdate: ((RemGlkUpdate) -> Void)?

  /// Backs the game's manual SAVE slot. Seeded into the bridge at `start` and
  /// updated whenever the bridge mirrors a SAVE. Injected so tests isolate; the
  /// default is rooted in Documents.
  var saveStore = SaveStorage.default

  /// The most recently applied theme stylesheet, retained so it can be re-applied
  /// whenever the bridge (re)loads. Each game open / restore is a fresh page load
  /// that drops any previously injected `<style>`, so without this the theme
  /// would only survive until the next load. Re-applied from `handleBridgeLoaded`.
  private var latestThemeCSS: String?

  /// Whether the transcript background is dark. Seeded into the bridge at
  /// `glkStart` (so per-style colours are lifted on first paint) and pushed live
  /// on a light/dark toggle via `setDarkBackground`.
  private var darkBackground = false

  override init() {
    super.init()
    let config = WKWebViewConfiguration()
    config.setURLSchemeHandler(scheme, forURLScheme: "glk")
    let ucc = WKUserContentController()
    ucc.add(self, name: "interp")
    config.userContentController = ucc
    webView = WKWebView(frame: .zero, configuration: config)
    webView.navigationDelegate = self
    #if DEBUG
    // iOS 16.4+ hides a third-party app's WKWebView from Safari's Develop menu
    // unless it opts in. Enable it in DEBUG so the GlkOte DOM/console can be
    // inspected on device (e.g. diagnosing graphics-window layout). Never in release.
    webView.isInspectable = true
    #endif
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
    scheme.saveData = saveStore.read(gameID: gameID)
    lastGen = 0
    latestAutosave = nil
    // 1) Load the classic-Glk bridge page; wait for its scripts to evaluate.
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      bootContinuation = continuation
      webView.load(URLRequest(url: URL(string: "glk://app/glk-bridge.html")!))
    }
    // 2) Boot the VM; the first settled update resolves `pending`.
    return try await awaitNextUpdate {
      self.webView.evaluateJavaScript(
        "window.glkStart('\(engine)', \(self.darkBackground)); 0", completionHandler: nil)
    }
  }

  /// Tears down the webview/instance. Safe to call once; resolves any in-flight
  /// awaiter with an error so callers don't hang.
  func teardown() {
    webView.stopLoading()
    // Break the WKUserContentController → self strong reference (set up by
    // `ucc.add(self, …)` in init) so this host — and its webview + interpreter
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

  func log(_ message: String) { FileHandle.standardError.write(Data("[glk] \(message)\n".utf8)) }

  /// Inject (or replace) the theme stylesheet into the page head as a
  /// `<style id="diction-theme">`. Appended after glkote.css so its
  /// equal-specificity class selectors win the cascade. The CSS is run through
  /// `JSONEncoder` to produce a safely-escaped JS string literal — far safer than
  /// hand-escaping for an arbitrary stylesheet. Stored so it can be re-applied
  /// after the next page (re)load (see `handleBridgeLoaded`).
  func applyThemeCSS(_ css: String) {
    latestThemeCSS = css
    injectThemeCSS(css)
  }

  private func injectThemeCSS(_ css: String) {
    injectCSS(css, id: "diction-theme")
  }

  /// Tell the bridge whether the transcript background is dark, so it lifts the
  /// game's per-style colours accordingly. Stored so `glkStart` seeds it on the
  /// next (re)load; pushed live here for a light/dark toggle mid-game.
  func setDarkBackground(_ dark: Bool) {
    darkBackground = dark
    webView.evaluateJavaScript("window.dictionSetDark && window.dictionSetDark(\(dark)); 0",
                               completionHandler: nil)
  }

  /// Create-or-replace a `<style id=…>` in the head from an arbitrary stylesheet.
  /// The CSS is run through `JSONEncoder` to produce a safely-escaped JS string
  /// literal — far safer than hand-escaping for an arbitrary stylesheet.
  private func injectCSS(_ css: String, id: String) {
    guard let data = try? JSONEncoder().encode(css),
          let literal = String(data: data, encoding: .utf8) else { return }
    let script = """
    (function () {
      var el = document.getElementById('\(id)');
      if (!el) {
        el = document.createElement('style');
        el.id = '\(id)';
        document.head.appendChild(el);
      }
      el.textContent = \(literal);
    })(); 0
    """
    webView.evaluateJavaScript(script, completionHandler: nil)
  }
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
    case "savewrite": handleSaveWrite(payload)
    case "savedelete": saveStore.delete(gameID: gameID)
    case "update": handleUpdate(payload)
    default: break
    }
  }

  /// The bridge mirrors the game's SAVE bytes (base64) here; persist them to the
  /// slot so a later launch can seed and RESTORE. A decode failure is dropped —
  /// the in-memory slot still works for the rest of this session.
  private func handleSaveWrite(_ payload: Any?) {
    guard let b64 = payload as? String, let data = Data(base64Encoded: b64) else { return }
    saveStore.write(gameID: gameID, data: data)
  }

  /// The VM's per-move autosave snapshot (JSON), or nil when the bridge signals a
  /// delete (no snapshot). Held until the caller captures it after a move.
  private func handleAutosave(_ payload: Any?) {
    latestAutosave = payload as? String
  }

  private func handleBridgeLoaded() {
    // The page just (re)loaded, dropping any prior injected style; re-apply the
    // retained theme so it survives game open / restore. (Per-style colours are
    // re-seeded by the bridge itself at glkStart, so they need no re-apply here.)
    if let css = latestThemeCSS { injectThemeCSS(css) }
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
    // Apply EVERY update so content / window / narration state stays current, but
    // only COMPLETE the pending send/start on a SETTLED update (the game is waiting
    // for input again, or has exited). Real GlkOte emits several updates per turn —
    // content, then arrange/redraw when a graphics window changes the layout — so
    // resolving on an intermediate one would drop the later input request and
    // strand the prompt (Counterfeit Monkey's map).
    onUpdate?(update)
    if Self.isSettled(update) {
      pending?.resume(returning: update)
      pending = nil
    }
  }

  /// A "settled" update ends a turn: the game is waiting for input again (ANY
  /// kind — a graphics window requesting only hyperlink/mouse input counts, or
  /// the turn would hang), or it has exited / disabled the UI. Intermediate
  /// updates (pure content, arrange, redraw) are applied but don't complete the
  /// await.
  private static func isSettled(_ update: RemGlkUpdate) -> Bool {
    if update.exit == true || update.disable == true { return true }
    return !(update.input?.isEmpty ?? true)
  }
}
