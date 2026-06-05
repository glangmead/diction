import Testing
import Foundation
@testable import Diction

// Contract tests for the GlkOte theme stylesheet generator. `GlkThemeCSS` is a
// pure string builder, so these lock the intent — that the reading typeface,
// computed point size, and app palette reach the right GlkOte buffer selectors —
// without needing a live WebView. (The grid/status windows are hidden in GlkOte
// and rendered natively by StatusWindowView, so they're not themed here.)

@Suite("Glk theme CSS")
struct GlkThemeCSSTests {
  /// A representative invocation: serif reading face, a non-default px size, and
  /// two distinct hex colours so each can be matched independently.
  private func sampleCSS() -> String {
    GlkThemeCSS.stylesheet(
      readingFamily: "ui-serif, Georgia, serif",
      pointSize: 19.5,
      textHex: "#112233",
      backgroundHex: "#445566"
    )
  }

  @Test("Buffer text uses the reading family, the computed px size, and the text colour")
  func bufferTextStyling() {
    let css = sampleCSS()
    #expect(css.contains("ui-serif, Georgia, serif"))
    #expect(css.contains("19.5px"))
    #expect(css.contains("#112233"))
  }

  @Test("Both resolved palette colours appear")
  func paletteColours() {
    let css = sampleCSS()
    #expect(css.contains("#112233"))   // gameText
    #expect(css.contains("#445566"))   // gameBackground
  }

  @Test("The buffer and page-background selectors are overridden")
  func selectors() {
    let css = sampleCSS()
    #expect(css.contains(".BufferWindow"))
    #expect(css.contains(".BufferWindow .Input"))
    #expect(css.contains("#gameport"))
  }

  @Test("Whole-number sizes drop the trailing .0")
  func wholeNumberSize() {
    let css = GlkThemeCSS.stylesheet(
      readingFamily: "-apple-system", pointSize: 17, textHex: "#000000", backgroundHex: "#FFFFFF")
    #expect(css.contains("17px"))
    #expect(!css.contains("17.0px"))
  }
}
