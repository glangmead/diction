import SwiftUI

/// The read-only card that surfaces a `VoiceReadout` (the answer to `help`,
/// `windows`, `history`, or `keywords`) while the coordinator narrates it. The
/// coordinator owns dismissal — it clears `activeReadout` when narration ends —
/// so this view carries no buttons. It doesn't take hits, so the game underneath
/// (input bar included) stays interactive while the card is up.
struct VoiceReadoutOverlay: View {
  let readout: VoiceReadout
  /// Ceiling for the scrolling line list, so a 20-line `history` can't outgrow the
  /// screen; the caller sizes it to the device. Short readouts shrink to fit.
  var maxLinesHeight: CGFloat = 360

  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  /// Measured height of the line list, so the scroller shrinks to its content
  /// (no empty card) yet caps at `maxLinesHeight` and scrolls when it overruns.
  @State private var linesContentHeight: CGFloat = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(readout.title)
        .font(.headline)
        .accessibilityAddTraits(.isHeader)

      if !readout.lines.isEmpty {
        ScrollView {
          lineList.background(
            GeometryReader { proxy in
              Color.clear.preference(key: LinesHeightKey.self, value: proxy.size.height)
            })
        }
        .frame(height: min(linesContentHeight, maxLinesHeight))
        .onPreferenceChange(LinesHeightKey.self) { linesContentHeight = $0 }
      }
    }
    .padding()
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(cardBackground)
    .accessibilityElement(children: .contain)
  }

  private var lineList: some View {
    VStack(alignment: .leading, spacing: 6) {
      ForEach(Array(readout.lines.enumerated()), id: \.offset) { _, line in
        lineRow(line)
      }
    }
  }

  private func lineRow(_ line: VoiceReadout.Line) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      if let number = line.number {
        Text("\(number).")
          .font(.subheadline.monospacedDigit())
          .foregroundStyle(.secondary)
      }
      Text(line.text)
        .font(.body)
        .foregroundStyle(.primary)
      Spacer(minLength: 0)
    }
    .accessibilityElement(children: .combine)
  }

  /// Carries the measured line-list height up so the scroller can size to it.
  private struct LinesHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
      value = max(value, nextValue())
    }
  }

  /// Translucent by default, opaque when Reduce Transparency is on.
  @ViewBuilder
  private var cardBackground: some View {
    let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
    if reduceTransparency {
      shape.fill(Color(.gameSurface))
    } else {
      shape.fill(.regularMaterial)
    }
  }
}

#Preview("Help readout (centered)") {
  Color(.gameBackground)
    .ignoresSafeArea()
    .voiceReadoutOverlay(VoiceCommandCatalog.helpReadout(), reduceMotion: false)
}

#Preview("Windows readout") {
  Color(.gameBackground)
    .ignoresSafeArea()
    .voiceReadoutOverlay(
      VoiceReadout(title: "Windows", lines: [
        .init(number: 1, text: "main story text"),
        .init(number: 2, text: "status bar above the story, 1 row"),
        .init(number: 3, text: "panel below the story")
      ]),
      reduceMotion: false)
}

extension View {
  /// Floats a `VoiceReadout` card centered over this view, animating in/out unless
  /// Reduce Motion is on. Pass `coordinator.activeReadout`; nil shows nothing. The
  /// card's scroll cap is sized to the available height (70%), so the full `help`
  /// list fits while a long `history` still can't overrun the screen. Read-only:
  /// the whole overlay declines hits, so the game underneath stays interactive.
  func voiceReadoutOverlay(_ readout: VoiceReadout?, reduceMotion: Bool) -> some View {
    overlay {
      if let readout {
        GeometryReader { proxy in
          VoiceReadoutOverlay(readout: readout, maxLinesHeight: proxy.size.height * 0.7)
            .padding(.horizontal, 24)
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .allowsHitTesting(false)
        .transition(reduceMotion ? .opacity : .scale(scale: 0.95).combined(with: .opacity))
      }
    }
    .animation(reduceMotion ? nil : .snappy, value: readout)
  }
}
