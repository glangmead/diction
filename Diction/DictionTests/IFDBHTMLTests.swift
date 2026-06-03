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

@Suite("IFDB HTML to plain text")
struct IFDBPlainTextTests {
  @Test("line breaks become newlines")
  func breaks() {
    #expect(plainText(fromIFDBHTML: "a<br>b") == "a\nb")
    #expect(plainText(fromIFDBHTML: "a<br/>b") == "a\nb")
    #expect(plainText(fromIFDBHTML: "a<br />b") == "a\nb")
  }

  @Test("paragraphs become blank-line separated")
  func paragraphs() {
    #expect(plainText(fromIFDBHTML: "<p>one</p><p>two</p>") == "one\n\ntwo")
  }

  @Test("inline tags are stripped, text kept")
  func inlineStripped() {
    #expect(plainText(fromIFDBHTML: "<i>Hi</i> <a href=\"x\">there</a>") == "Hi there")
  }

  @Test("list items become bullets, one per line")
  func lists() {
    #expect(plainText(fromIFDBHTML: "<ul><li>a</li><li>b</li></ul>") == "• a\n• b")
  }

  @Test("Violet's blurb renders cleanly")
  func violet() {
    let raw = "And you have all day, except it&#039;s already noon. [blurb from IF Comp 2008]"
    #expect(plainText(fromIFDBHTML: raw) == "And you have all day, except it's already noon. [blurb from IF Comp 2008]")
  }

  @Test("Anchorhead-style markup leaves no tags or raw entities")
  func anchorheadSmoke() {
    let raw = "<p>A horror game.</p><br><i>Award winner.</i> See <a href=\"http://x\">site</a>.&#039;"
    let out = plainText(fromIFDBHTML: raw)
    #expect(!out.contains("<"))
    #expect(!out.contains("&#"))
    #expect(out.contains("A horror game."))
    #expect(out.contains("Award winner."))
    #expect(out.hasSuffix("'"))
  }
}
