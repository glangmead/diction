import SwiftUI

/// One grid (status) window — AMFV's mode/location/time bar, etc. — rendered as a
/// compacted monospaced block whose font grows toward the Reading Text size and
/// shrinks to fit the width: a short bar reads large, a full 80-column row stays
/// readable, and the bar's height follows the chosen font. Recomputed as the
/// content changes. `GridReflow` does the space compaction (and the ASCII-art
/// guard); this view does the fit-to-width sizing.
struct StatusWindowView: View {
  let window: GridWindowSnapshot

  @AppStorage("readingTextSize") private var sizeRaw = ReadingTextSize.medium.rawValue
  /// 17 pt body scaled by Dynamic Type; the Reading Text step caps the font.
  @ScaledMetric(relativeTo: .body) private var baseSize: CGFloat = 17
  @State private var availableWidth: CGFloat = 0

  /// SF Mono's advance is ≈0.6 em; underestimating keeps text from overflowing,
  /// and `minimumScaleFactor` covers any remainder.
  private static let monospaceAdvance: CGFloat = 0.6

  private var maxFontSize: CGFloat {
    baseSize * (ReadingTextSize(rawValue: sizeRaw) ?? .medium).multiplier
  }

  var body: some View {
    let rows = GridReflow.reflow(window.lines.map { Self.rowText($0, width: window.width) })
    let columns = rows.map(\.count).max() ?? 0
    let fontSize = fittedFontSize(columns: columns)

    VStack(alignment: .leading, spacing: 0) {
      ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
        Text(row)
          .lineLimit(1)
          .minimumScaleFactor(0.5)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
    .font(.system(size: fontSize, design: .monospaced))
    .foregroundStyle(.gameText)
    .padding(.horizontal, 8)
    .padding(.vertical, 6)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.gameSurface)
    .overlay(alignment: .bottom) {
      Rectangle().fill(.gameSurfaceBorder).frame(height: 1)
    }
    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { availableWidth = $0 }
    .animation(.easeInOut(duration: 0.2), value: fontSize)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(Self.accessibilityLabel(window))
  }

  /// The largest font (≤ the Reading Text cap) at which `columns` monospaced
  /// cells fit the measured width; the bar's height then follows the font.
  private func fittedFontSize(columns: Int) -> CGFloat {
    guard columns > 0, availableWidth > 0 else { return maxFontSize }
    let usable = max(0, availableWidth - 16)   // horizontal padding (8 + 8)
    let fit = usable / (CGFloat(columns) * Self.monospaceAdvance)
    return min(maxFontSize, fit)
  }

  /// One grid row as exactly `width` monospaced columns — trailing-padded so the
  /// reflow sees a rectangular block and the columns line up.
  private static func rowText(_ row: StyledText, width: Int) -> String {
    let text = row.plainText
    if text.count >= width { return String(text.prefix(width)) }
    return text + String(repeating: " ", count: width - text.count)
  }

  /// VoiceOver: collapse the positional padding to single spaces and join rows,
  /// so the bar reads as "Mode: Communications Mode, Time: 7:07pm, …".
  private static func accessibilityLabel(_ window: GridWindowSnapshot) -> String {
    let rows = window.lines
      .map { $0.plainText.split(whereSeparator: \.isWhitespace).joined(separator: " ") }
      .filter { !$0.isEmpty }
    return "Status. " + rows.joined(separator: ", ")
  }
}
