import Foundation

/// A non-primary buffer window — e.g. Blue Lacuna's bottom "Topics" panel that
/// the `keywords` screen opens beside the main story window. Unlike the
/// fixed-grid `GridWindowSnapshot` this is flowing styled text, accumulated with
/// the same clear/append semantics as the transcript (via
/// `StyledText.applyBufferContent`). `top`/`height` come from RemGlk's geometry;
/// because the app feeds emglken 1×1 cell metrics, `height` is a line count and
/// `top` orders the panel (Blue Lacuna's sits at the bottom, `top` 47).
nonisolated struct BufferWindowSnapshot: Identifiable, Sendable {
  let id: Int
  var top: Int = 0
  var height: Int = 0
  var lines: [StyledText] = []

  mutating func apply(content: RemGlkUpdate.Content, styleTable: [String: StyleAttributes]?) {
    StyledText.applyBufferContent(content, styleTable: styleTable, into: &lines)
  }
}
