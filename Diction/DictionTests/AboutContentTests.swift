import Testing
import Foundation
@testable import Diction

@Suite("About content markdown parsing")
struct AboutContentTests {
  @Test("a lone '# ' line parses to a single H1 block")
  func headerOnly() {
    #expect(
      AboutContent.parse(markdown: "# Welcome to Diction") == [.heading1("Welcome to Diction")]
    )
  }

  @Test("blank lines split paragraphs; '## ' is an H2")
  func paragraphsAndH2() {
    let blocks = AboutContent.parse(markdown: "## Section\n\nfirst para\n\nsecond para")
    #expect(blocks.count == 3)
    #expect(blocks.first == .heading2("Section"))
  }

  @Test("a bare http(s) URL is rewritten as a markdown link")
  func autolinkBareURL() {
    let out = AboutContent.autolinkBareURLs(in: "see https://example.com now")
    #expect(out == "see [https://example.com](https://example.com) now")
  }

  @Test("an explicit markdown link is left untouched by the autolinker")
  func leavesExplicitLinks() {
    let input = "see [the site](https://example.com) now"
    #expect(AboutContent.autolinkBareURLs(in: input) == input)
  }

  @Test("a paragraph with an inline link yields an attributed run carrying a .link")
  func paragraphProducesLinkRun() {
    let blocks = AboutContent.parse(markdown: "visit [here](https://example.com)")
    guard case .paragraph(let attributed)? = blocks.first else {
      Issue.record("expected a paragraph block, got \(String(describing: blocks.first))")
      return
    }
    let hasLink = attributed.runs.contains { $0.link != nil }
    #expect(hasLink)
  }
}
