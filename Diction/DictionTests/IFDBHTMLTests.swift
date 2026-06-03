import Foundation
import Testing
@testable import Diction

@Suite("IFDB HTML entity decoding")
struct IFDBEntityTests {
  @Test("zero-padded and bare decimal entities decode (the Violet case)")
  func decimalEntities() {
    #expect(decodeHTMLEntities("it&#039;s") == "it's")
    #expect(decodeHTMLEntities("it&#39;s") == "it's")
    #expect(decodeHTMLEntities("&#8217;") == "\u{2019}")   // right single quote
  }

  @Test("hex entities decode")
  func hexEntities() {
    #expect(decodeHTMLEntities("&#x27;") == "'")
    #expect(decodeHTMLEntities("caf&#xE9;") == "café")
  }

  @Test("common named entities decode")
  func namedEntities() {
    #expect(decodeHTMLEntities("a&mdash;b") == "a—b")
    #expect(decodeHTMLEntities("&amp;") == "&")
    #expect(decodeHTMLEntities("&quot;hi&quot;") == "\"hi\"")
  }

  @Test("a bare ampersand with no entity is left intact")
  func bareAmpersand() {
    #expect(decodeHTMLEntities("AT&T") == "AT&T")
    #expect(decodeHTMLEntities("Tom & Jerry") == "Tom & Jerry")
  }

  @Test("an unknown entity is left literal rather than dropped")
  func unknownEntity() {
    #expect(decodeHTMLEntities("&bogusentity;") == "&bogusentity;")
  }

  @Test("double-encoded entity survives as a literal entity reference")
  func doubleEncoded() {
    #expect(decodeHTMLEntities("x &amp;#039; y") == "x &#039; y")
  }
}

@Suite("IFDB HTML to Markdown")
struct IFDBMarkdownTests {
  @Test("italic and bold tags become Markdown emphasis")
  func emphasis() {
    #expect(markdown(fromIFDBHTML: "<i>Hi</i>") == "*Hi*")
    #expect(markdown(fromIFDBHTML: "<em>Hi</em>") == "*Hi*")
    #expect(markdown(fromIFDBHTML: "<b>Hi</b>") == "**Hi**")
    #expect(markdown(fromIFDBHTML: "<strong>Hi</strong>") == "**Hi**")
  }

  @Test("anchors become Markdown links, href entities decoded")
  func links() {
    #expect(markdown(fromIFDBHTML: "<a href=\"http://x.com\">site</a>") == "[site](http://x.com)")
    #expect(markdown(fromIFDBHTML: "<a href=\"http://x?a=1&amp;b=2\">q</a>") == "[q](http://x?a=1&b=2)")
  }

  @Test("line breaks and paragraphs become newlines")
  func structure() {
    #expect(markdown(fromIFDBHTML: "a<br>b") == "a\nb")
    #expect(markdown(fromIFDBHTML: "<p>one</p><p>two</p>") == "one\n\ntwo")
  }

  @Test("list items become bullets, one per line")
  func lists() {
    #expect(markdown(fromIFDBHTML: "<ul><li>a</li><li>b</li></ul>") == "• a\n• b")
  }

  @Test("entities are decoded in text runs")
  func entities() {
    #expect(markdown(fromIFDBHTML: "it&#039;s") == "it's")
  }

  @Test("Markdown metacharacters in prose are escaped so they render literally")
  func escapesProse() {
    #expect(markdown(fromIFDBHTML: "5 * 3 _x_ [note]") == "5 \\* 3 \\_x\\_ \\[note\\]")
  }

  @Test("emphasis keeps the tag's markers but escapes inner specials")
  func escapeInsideEmphasis() {
    #expect(markdown(fromIFDBHTML: "<i>a*b</i>") == "*a\\*b*")
  }

  @Test("link text is escaped but the URL is not")
  func linkTextEscaped() {
    #expect(markdown(fromIFDBHTML: "<a href=\"http://x?y=1\">a[b]</a>") == "[a\\[b\\]](http://x?y=1)")
  }

  @Test("Violet's blurb keeps its bracketed credit as literal text")
  func violet() {
    let raw = "except it&#039;s already noon. [blurb from IF Comp 2008]"
    #expect(markdown(fromIFDBHTML: raw) == "except it's already noon. \\[blurb from IF Comp 2008\\]")
  }

  @Test("renders to attributed text with a live link")
  func rendersAttributed() throws {
    var options = AttributedString.MarkdownParsingOptions()
    options.interpretedSyntax = .inlineOnlyPreservingWhitespace
    let source = markdown(fromIFDBHTML: "<i>Hi</i> <a href=\"http://x.com\">there</a>")
    let attributed = try AttributedString(markdown: source, options: options)
    #expect(String(attributed.characters) == "Hi there")
    #expect(attributed.runs.contains { $0.link != nil })
  }
}
