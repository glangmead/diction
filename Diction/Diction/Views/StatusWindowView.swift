import SwiftUI

/// One grid (status) window — AMFV's mode/location/time bar, etc. — rendered as a
/// compacted monospaced block whose font grows toward the Reading Text size and
/// shrinks to fit the width: a short bar reads large, a full 80-column row stays
/// readable, and the bar's height follows the chosen font. Recomputed as the
/// content changes. `GridReflow` does the space compaction (and the ASCII-art
/// guard); this view does the fit-to-width sizing.
struct StatusWindowView: View {
  let window: GridWindowSnapshot
  /// When set (the library row preview), caps the font at this fixed size instead
  /// of the reading-size slider, so a row shows a compact preview rather than the
  /// live status-bar size. nil for the in-game bar.
  var maxFontSizeOverride: CGFloat?
  /// The bottom hairline separates the in-game bar from the transcript below it.
  /// Off for the library preview, where the bar stands alone in a rounded panel
  /// and the rule just reads as a stray dark line.
  var showsSeparator = true
  /// The interpreter's input cursor in *original* grid coordinates (glkapi's
  /// `xpos`/`ypos`) when this grid window is taking input — e.g. Bureaucracy's
  /// form. nil otherwise. Mapped through the reflow and drawn as a blinking caret.
  var inputCursor: (col: Int, row: Int)?

  @AppStorage("readingTextSize") private var sizeRaw = ReadingTextSize.medium.rawValue
  /// 17 pt body scaled by Dynamic Type; the Reading Text step caps the font.
  @ScaledMetric(relativeTo: .body) private var baseSize: CGFloat = 17
  @State private var availableWidth: CGFloat = 0

  /// SF Mono's advance is ≈0.6 em; underestimating keeps text from overflowing,
  /// and `minimumScaleFactor` covers any remainder.
  private static let monospaceAdvance: CGFloat = 0.6

  /// Max grid rows the in-game bar shows before it becomes vertically scrollable.
  /// A tall grid window (Bureaucracy's whole licence form lives in one) would
  /// otherwise fit-to-width into a screen-filling block. Easily adjustable — bump
  /// this one number to change the cap. The library preview truncates to it instead
  /// of scrolling (a list row can't scroll).
  static let maxVisibleRows = 15

  /// SF Mono's line box is ≈1.25× the point size; sizes the scroll viewport so it
  /// shows about `maxVisibleRows` rows (a sliver of the next row hints at more).
  private static let lineHeightFactor: CGFloat = 1.25

  private var maxFontSize: CGFloat {
    maxFontSizeOverride ?? baseSize * (ReadingTextSize(rawValue: sizeRaw) ?? .medium).multiplier
  }

  var body: some View {
    let reflowed = GridReflow.reflow(window.lines.map { Self.rowText($0, width: window.width) })
    let allRows = reflowed.rows
    let columns = allRows.map(\.count).max() ?? 0
    let fontSize = fittedFontSize(columns: columns)
    let lineHeight = fontSize * Self.lineHeightFactor
    let isPreview = maxFontSizeOverride != nil
    // The library preview is a static list row, so it truncates to the cap; the
    // in-game bar keeps every row and scrolls past the cap.
    let rows = isPreview ? Array(allRows.prefix(Self.maxVisibleRows)) : allRows
    let scrolls = !isPreview && allRows.count > Self.maxVisibleRows
    let cappedHeight = lineHeight * CGFloat(Self.maxVisibleRows)
    // The caret only shows on the live bar, mapped through the same reflow.
    let caret = isPreview ? nil : inputCursor.flatMap { reflowed.cursor(col: $0.col, row: $0.row) }

    Group {
      if scrolls {
        ScrollView(.vertical) { rowsStack(rows, fontSize: fontSize, lineHeight: lineHeight, caret: caret) }
          .frame(height: cappedHeight)
      } else {
        rowsStack(rows, fontSize: fontSize, lineHeight: lineHeight, caret: caret)
      }
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 6)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.gameSurface)
    .overlay(alignment: .bottom) {
      if showsSeparator {
        Rectangle().fill(.gameSurfaceBorder).frame(height: 1)
      }
    }
    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { availableWidth = $0 }
    .animation(.easeInOut(duration: 0.2), value: fontSize)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(Self.accessibilityLabel(window))
  }

  /// The monospaced rows as a left-aligned block, each at a fixed `lineHeight` so a
  /// caret can be placed by row/column. Shared by the scrolling and non-scrolling
  /// layouts so both render identically.
  private func rowsStack(
    _ rows: [String], fontSize: CGFloat, lineHeight: CGFloat, caret: (col: Int, row: Int)?
  ) -> some View {
    let charWidth = fontSize * Self.monospaceAdvance
    return VStack(alignment: .leading, spacing: 0) {
      ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
        Text(row)
          .lineLimit(1)
          .minimumScaleFactor(0.5)
          .frame(height: lineHeight, alignment: .leading)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
    .font(.system(size: fontSize, design: .monospaced))
    .foregroundStyle(.gameText)
    .overlay(alignment: .topLeading) {
      if let caret {
        GridCaret(width: max(1.5, fontSize * 0.09), height: lineHeight * 0.82)
          .offset(x: CGFloat(caret.col) * charWidth, y: CGFloat(caret.row) * lineHeight + lineHeight * 0.09)
      }
    }
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

/// A blinking vertical bar — the in-grid input caret, matching the flashing
/// cursor GlkOte draws (which we hide along with the grid window).
private struct GridCaret: View {
  let width: CGFloat
  let height: CGFloat
  @State private var dim = false

  var body: some View {
    Rectangle()
      .fill(.gameText)
      .frame(width: width, height: height)
      .opacity(dim ? 0 : 1)
      .onAppear {
        withAnimation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true)) { dim = true }
      }
      .accessibilityHidden(true)
  }
}
