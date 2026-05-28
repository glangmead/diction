import SwiftUI

/// Renders one `StyledText` transcript entry, mapping RemGlk text styles
/// (header, emphasized, input, alert, …) to SwiftUI text formatting.
/// Extracted from GameView so the per-row rendering can evolve
/// independently and the parent view stays focused on coordination.
struct StyledTextLineView: View {
  let entry: StyledText

  var body: some View {
    entry.runs.reduce(Text("")) { result, run in
      result + styledRun(run)
    }
    .font(.system(.body, design: .monospaced))
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
