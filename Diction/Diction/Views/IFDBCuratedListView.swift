import SwiftUI

/// The landing content shown on the IFDB search screen before the user types.
/// Presents a curated, heading-grouped catalog of interactive fiction; tapping a
/// playable title invokes `onSelectGame`, which routes to the same detail page a
/// live search result would. Section sources (e.g. the book the titles are drawn
/// from) render as web links.
struct IFDBCuratedListView: View {
  let list: CuratedIFDBList
  let onSelectGame: (IFDBSearchResult) -> Void

  init(
    list: CuratedIFDBList = .all,
    onSelectGame: @escaping (IFDBSearchResult) -> Void
  ) {
    self.list = list
    self.onSelectGame = onSelectGame
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 28) {
        Text("Search for interactive fiction by title or author. Or use the curated list below.")
          .font(.subheadline)
          .foregroundStyle(.secondary)

        Text("Note: some games may not have downloads on IFDB and must be found elsewhere.")
          .font(.subheadline)
          .foregroundStyle(.secondary)

        ForEach(list.sections) { section in
          sectionView(section)
        }
      }
      .padding()
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private func sectionView(_ section: CuratedIFDBSection) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      sectionHeader(section)
      ForEach(section.groups) { group in
        groupView(group)
      }
    }
  }

  private func sectionHeader(_ section: CuratedIFDBSection) -> some View {
    // A link run inside the title is tappable on its own (opening the web) while
    // the surrounding header text stays plain, non-tappable.
    Text(styledSectionTitle(section.title))
      .font(.title3.bold())
      .multilineTextAlignment(.leading)
      .accessibilityAddTraits(.isHeader)
  }

  /// Renders any link run in a section title as a blue, underlined web link.
  private func styledSectionTitle(_ title: AttributedString) -> AttributedString {
    var styled = title
    let linkRanges = styled.runs.compactMap { $0.link != nil ? $0.range : nil }
    for range in linkRanges {
      styled[range].foregroundColor = .blue
      styled[range].underlineStyle = .single
    }
    return styled
  }

  private func groupView(_ group: CuratedIFDBGroup) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      if let heading = group.heading {
        Text(heading)
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(.secondary)
          .accessibilityAddTraits(.isHeader)
      }
      ForEach(group.sortedGames) { game in
        gameRow(game, groupHeading: group.heading)
      }
    }
  }

  @ViewBuilder
  private func gameRow(_ game: CuratedIFDBGame, groupHeading: String?) -> some View {
    if game.isPlayable {
      Button {
        onSelectGame(IFDBSearchResult(tuid: game.tuid, title: game.title))
      } label: {
        gameLabel(game, linked: true)
      }
      .buttonStyle(.plain)
      .accessibilityHint("Shows description and details")
    } else {
      gameLabel(game, linked: false)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel(for: game, groupHeading: groupHeading))
    }
  }

  private func gameLabel(_ game: CuratedIFDBGame, linked: Bool) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 6) {
      Text(game.title)
        .foregroundStyle(linked ? Color.blue : Color.primary)
        .multilineTextAlignment(.leading)
      if let annotation = game.annotation {
        Text(annotation)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    // Playable rows are buttons, so keep them at the 44pt minimum touch target.
    .frame(maxWidth: .infinity, minHeight: linked ? 44 : nil, alignment: .leading)
    .contentShape(Rectangle())
  }

  /// Folds the annotation and (for non-playable items) the group heading into a
  /// single VoiceOver label, since those rows aren't read via a sub-heading
  /// focus path the way a button row is.
  private func accessibilityLabel(for game: CuratedIFDBGame, groupHeading: String?) -> String {
    var label = game.title
    if let annotation = game.annotation { label += ", \(annotation)" }
    if let groupHeading { label += ", \(groupHeading)" }
    return label
  }
}
