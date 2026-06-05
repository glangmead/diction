import SwiftUI
import WebKit

/// Displays the interpreter's GlkOte-rendered output. Wraps the `WKWebView`
/// owned by `WebInterpreterHost` (already configured with the glk:// scheme and
/// message handler) so the same instance that runs the VM is the one on screen.
struct InterpreterWebView: UIViewRepresentable {
  let webView: WKWebView

  func makeUIView(context: Context) -> WKWebView {
    webView.isOpaque = false
    webView.backgroundColor = .clear
    webView.scrollView.backgroundColor = .clear
    return webView
  }

  func updateUIView(_ uiView: WKWebView, context: Context) {}
}
