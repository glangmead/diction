import SwiftUI

/// Renders one `StyledText` transcript entry, mapping RemGlk text styles
/// (header, emphasized, input, alert, …) to SwiftUI text formatting.
/// Extracted from GameView so the per-row rendering can evolve
/// independently and the parent view stays focused on coordination.
struct StyledTextLineView: View {
  let entry: StyledText

  // Flowing-text font, configurable in Settings (the grid/status windows keep
  // their own monospaced font). Defaults must match SettingsView's defaults.
  @AppStorage("readingTypeface") private var typefaceRaw = ReadingTypeface.sansSerif.rawValue
  @AppStorage("readingTextSize") private var sizeRaw = ReadingTextSize.medium.rawValue
  // 17 pt body scaled by the device's Dynamic Type setting; the semantic size
  // step multiplies on top, so the two compound.
  @ScaledMetric(relativeTo: .body) private var baseSize: CGFloat = 17
  @Environment(\.colorScheme) private var colorScheme

  private var readingFont: Font {
    let typeface = ReadingTypeface(rawValue: typefaceRaw) ?? .sansSerif
    let multiplier = (ReadingTextSize(rawValue: sizeRaw) ?? .medium).multiplier
    return .system(size: baseSize * multiplier, design: typeface.design)
  }

  var body: some View {
    Text(attributedLine)
      .font(readingFont)
      .foregroundStyle(.gameText)
      .accessibilityLabel(entry.plainText)
  }

  /// The line as a single `AttributedString` (Text `+` concatenation is
  /// deprecated in iOS 26). Per-run bold/italic ride as inline presentation
  /// intent so they compose with the reading font; colour overrides the line
  /// default. Background fills and reverse-video are deferred to the
  /// windows-and-audio pass.
  private var attributedLine: AttributedString {
    entry.runs.reduce(into: AttributedString()) { line, run in
      var piece = AttributedString(run.text)
      var intent: InlinePresentationIntent = []
      if Self.isBold(run) { intent.insert(.stronglyEmphasized) }
      if Self.isItalic(run) { intent.insert(.emphasized) }
      if !intent.isEmpty { piece.inlinePresentationIntent = intent }
      if let color = color(for: run) { piece.foregroundColor = color }
      line.append(piece)
    }
  }

  /// Bold when the resolved style says so, or for the semantic header styles
  /// that games often leave to the reader to embolden.
  private static func isBold(_ run: StyledText.Run) -> Bool {
    if run.attributes.fontWeight?.lowercased() == "bold" { return true }
    return run.style == .header || run.style == .subheader
  }

  private static func isItalic(_ run: StyledText.Run) -> Bool {
    switch run.attributes.fontStyle?.lowercased() {
    case "italic", "oblique": return true
    default: return run.style == .emphasized
    }
  }

  /// A game-specified colour wins (lifted so dark hues stay readable on the dark
  /// transcript). With no game colour, fall back to the app's own conventions
  /// for input echo and alerts; otherwise inherit the line's default colour.
  private func color(for run: StyledText.Run) -> Color? {
    if let css = run.attributes.color, let parsed = RunColor.parse(css: css) {
      let legible = parsed.legible(onDark: colorScheme == .dark)
      return Color(.sRGB, red: legible.red, green: legible.green, blue: legible.blue)
    }
    switch run.style {
    case .input: return .gray
    case .alert, .note: return .orange
    default: return nil
    }
  }
}
