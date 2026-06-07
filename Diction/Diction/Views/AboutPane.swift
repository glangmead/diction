import Foundation
import SwiftUI

/// Renders the About text as the Settings sheet's "About" segment: H1/H2 headers,
/// paragraphs and `-` bullet items with inline markdown links, and bare http(s) URLs
/// auto-linked. The content is inlined here rather than bundled as a resource so we
/// don't have to edit the Xcode project file every time it changes — it's small and
/// stable. Wrapped in a single-Section Form for visual parity with the Settings segment;
/// the section header is suppressed because the sheet's nav bar already says "About".
struct AboutPane: View {
  var body: some View {
    Form {
      Section {
        VStack(alignment: .leading, spacing: 10) {
          ForEach(Array(AboutContent.blocks.enumerated()), id: \.offset) { _, block in
            AboutBlockView(block: block)
          }
        }
        .padding(.vertical, 6)
      }
      // Open-source credits live under the help text rather than in the Settings tab.
      AcknowledgementsSection()
    }
  }
}

private struct AboutBlockView: View {
  let block: AboutContent.Block

  var body: some View {
    switch block {
    case .heading1(let text):
      Text(text)
        .font(.title)
        .fontWeight(.bold)
        .padding(.top, 6)
    case .heading2(let text):
      Text(text)
        .font(.title2)
        .fontWeight(.semibold)
        .padding(.top, 4)
    case .paragraph(let attributed):
      Text(attributed)
        .font(.body)
        .fixedSize(horizontal: false, vertical: true)
        .textSelection(.enabled)
    case .bullet(let attributed):
      HStack(alignment: .firstTextBaseline, spacing: 6) {
        Text("•")
          .font(.body)
        Text(attributed)
          .font(.body)
          .fixedSize(horizontal: false, vertical: true)
          .textSelection(.enabled)
      }
    }
  }
}

enum AboutContent {
  enum Block: Equatable {
    case heading1(String)
    case heading2(String)
    case paragraph(AttributedString)
    case bullet(AttributedString)
  }

  // Source markdown for the About pane. Long bullet/paragraph lines stay unwrapped so
  // the rendered text matches the source 1:1 — a bullet can't be wrapped without
  // splitting it into two — so the line-length rule is suppressed here rather than
  // breaking the prose.
  // swiftlint:disable line_length
  private static let markdown: String = """
# Welcome to Diction

Play interactive fiction games with your voice, while the device reads the game to you!

Try Find to see a list of classic games that are a click away.

## Tips

* The mic is automatically listening and can tell when you're done talking.
* Mute the mic or speaker in the top toolbar if you only want some of the voice features.
* You can use Apple's voices, or an experimental CoreML family of voices.
* To add to the Apple voices you have to first visit your device's Settings > Accessibility > Read & Speak > Voices > English > Voice.

"""
  // swiftlint:enable line_length

  /// Pre-parsed list of renderable blocks. Pure compute; safe to evaluate once.
  static let blocks: [Block] = parse(markdown: markdown)

  /// CommonMark unordered-list markers: a line is a bullet when it starts with one of
  /// these followed by a space (so `*emphasis*` stays a paragraph).
  private static let bulletMarkers: Set<Character> = ["-", "*", "+"]

  /// Minimal CommonMark subset: H1 (`# `), H2 (`## `), blank lines split paragraphs,
  /// `-`/`*`/`+` bullet items, inline link syntax `[text](url)`, and bare http(s)
  /// URLs are auto-linked.
  static func parse(markdown source: String) -> [Block] {
    var result: [Block] = []
    var paragraph: [String] = []

    func renderInline(_ text: String) -> AttributedString {
      let withAutoLinks = autolinkBareURLs(in: text)
      if let attributed = try? AttributedString(
        markdown: withAutoLinks,
        options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
      ) {
        return attributed
      }
      return AttributedString(text)
    }

    func flushParagraph() {
      guard !paragraph.isEmpty else { return }
      let joined = paragraph.joined(separator: " ")
      result.append(.paragraph(renderInline(joined)))
      paragraph.removeAll()
    }

    for rawLine in source.components(separatedBy: "\n") {
      let line = rawLine.trimmingCharacters(in: .whitespaces)
      if line.isEmpty {
        flushParagraph()
        continue
      }
      if line.hasPrefix("## ") {
        flushParagraph()
        result.append(.heading2(String(line.dropFirst(3))))
        continue
      }
      if line.hasPrefix("# ") {
        flushParagraph()
        result.append(.heading1(String(line.dropFirst(2))))
        continue
      }
      if let marker = line.first, bulletMarkers.contains(marker), line.dropFirst().hasPrefix(" ") {
        flushParagraph()
        result.append(.bullet(renderInline(String(line.dropFirst(2)))))
        continue
      }
      paragraph.append(line)
    }
    flushParagraph()
    return result
  }

  /// Wrap any bare `http://` / `https://` URL in `[url](url)` so that
  /// `AttributedString(markdown:)` produces a tappable link. Markdown link
  /// syntax already in the source is left untouched (the regex skips URLs
  /// that already sit inside parentheses adjacent to a `]`).
  static func autolinkBareURLs(in text: String) -> String {
    let pattern = #"(?<![\(\[])\bhttps?://[^\s\)\]]+"#
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
    let range = NSRange(text.startIndex..., in: text)
    let matches = regex.matches(in: text, range: range)
    guard !matches.isEmpty else { return text }
    var output = text
    for match in matches.reversed() {
      guard let swiftRange = Range(match.range, in: output) else { continue }
      let url = String(output[swiftRange])
      output.replaceSubrange(swiftRange, with: "[\(url)](\(url))")
    }
    return output
  }
}
