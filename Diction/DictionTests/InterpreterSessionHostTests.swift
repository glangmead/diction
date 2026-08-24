import Testing
@testable import Diction

/// `InterpreterSession` builds its `WebInterpreterHost` on first use (impl
/// ticket 03). `GameView` hands the host's web view to a representable keyed on
/// the session, so the session must keep surfacing the same web view for life.
@MainActor
@Suite("Interpreter session host")
struct InterpreterSessionHostTests {
  @Test("the interpreter web view is a single stable instance")
  func webViewIsStable() {
    let session = InterpreterSession()
    #expect(session.interpreterWebView === session.interpreterWebView)
  }
}
