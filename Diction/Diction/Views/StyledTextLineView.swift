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

  private var readingFont: Font {
    let typeface = ReadingTypeface(rawValue: typefaceRaw) ?? .sansSerif
    let multiplier = (ReadingTextSize(rawValue: sizeRaw) ?? .medium).multiplier
    return .system(size: baseSize * multiplier, design: typeface.design)
  }

  var body: some View {
    entry.runs.reduce(Text("")) { result, run in
      result + styledRun(run)
    }
    .font(readingFont)
    .foregroundStyle(Color(white: 0.92))
    .accessibilityLabel(entry.plainText)
  }

  private func styledRun(_ run: StyledText.Run) -> Text {
    var text = Text(run.text)
    switch run.style {
    case .header, .subheader:
      text = text.bold()
    case .emphasized:
      text = text.italic()
    case .input:
      text = text.foregroundColor(.gray)
    case .alert, .note:
      text = text.foregroundColor(.orange)
    default:
      break
    }
    return text
  }
}
