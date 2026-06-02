import SwiftUI

/// A non-primary buffer window (e.g. Blue Lacuna's bottom "Topics" window the
/// `keywords` screen opens) shown as a flowing-text panel above the input bar.
/// Reuses `StyledTextLineView` so it inherits the reading font and run styling.
/// Sized to the window's reported line count, but capped and scrollable so a
/// tall secondary window can't swallow the transcript.
struct BufferWindowPanelView: View {
  let window: BufferWindowSnapshot

  @AppStorage("readingTextSize") private var sizeRaw = ReadingTextSize.medium.rawValue
  /// Rough per-line height at the default reading size, scaled by Dynamic Type;
  /// multiplied by the chosen reading size so the cap tracks the rendered text.
  @ScaledMetric(relativeTo: .body) private var baseLineHeight: CGFloat = 22

  /// A panel grows to its content, but never past this many lines before it
  /// scrolls — keeps a large secondary window from dominating the screen.
  private static let maxLines = 8

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 2) {
        ForEach(window.lines) { line in
          StyledTextLineView(entry: line)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
      }
      .padding(.horizontal)
      .padding(.vertical, 8)
    }
    .frame(maxHeight: maxHeight)
    .background(Color(white: 0.11))
    .overlay(alignment: .top) {
      Rectangle().fill(Color(white: 0.32)).frame(height: 1)
    }
    .accessibilityElement(children: .contain)
  }

  private var maxHeight: CGFloat {
    let lines = min(max(window.height, 1), Self.maxLines)
    let multiplier = (ReadingTextSize(rawValue: sizeRaw) ?? .medium).multiplier
    return CGFloat(lines) * baseLineHeight * multiplier + 16  // + vertical padding
  }
}
