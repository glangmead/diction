import SwiftUI

/// The Settings credits group: one tappable row per third-party component (name
/// + license, with its GitHub URL as a tinted, tappable subtitle), plus a
/// "View Licenses" link to the full bundled license texts.
struct AcknowledgementsSection: View {
  var body: some View {
    Section {
      ForEach(LicenseCredit.all) { credit in
        creditRow(credit)
      }
      NavigationLink {
        LicensesView()
      } label: {
        Text("View Licenses")
      }
    } header: {
      Text("Acknowledgements")
    } footer: {
      Text(
        """
        Diction is built on these open-source projects. Tap a name to open its \
        source, or view the full license texts.
        """
      )
    }
  }

  @ViewBuilder
  private func creditRow(_ credit: LicenseCredit) -> some View {
    if let url = credit.url {
      Link(destination: url) {
        VStack(alignment: .leading, spacing: 2) {
          HStack {
            Text(credit.name)
              .foregroundStyle(.primary)
            Spacer(minLength: 8)
            Text(credit.license)
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          Text(credit.displayLink)
            .font(.caption)
            .foregroundStyle(.tint)
        }
        .contentShape(Rectangle())
      }
      .accessibilityElement(children: .combine)
      .accessibilityLabel("\(credit.name), \(credit.license)")
      .accessibilityHint("Opens \(credit.name) on GitHub")
    }
  }
}
