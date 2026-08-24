import SwiftUI

/// A small downward chevron badged on a toolbar control's lower-right corner to
/// signal a press-and-hold menu. Decorative — the control's own label and menu
/// carry the meaning for assistive tech, so it's hidden from them.
struct MenuChevron: View {
  var body: some View {
    Image(systemName: "chevron.down")
      .font(.system(size: 9, weight: .semibold))
      .foregroundStyle(.secondary)
      .offset(x: 4, y: 3)
      .accessibilityHidden(true)
  }
}
