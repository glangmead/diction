import SwiftUI

/// Full license texts for the bundled third-party components, listed from
/// `LicenseCredit.all`. Each row pushes a detail showing the verbatim license.
struct LicensesView: View {
  var body: some View {
    List(LicenseCredit.all) { credit in
      NavigationLink {
        detail(for: credit)
      } label: {
        VStack(alignment: .leading, spacing: 2) {
          Text(credit.name)
          Text("\(credit.license) · \(credit.author)")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(credit.name), \(credit.license), \(credit.author)")
      }
    }
    .navigationTitle("Licenses")
    .navigationBarTitleDisplayMode(.inline)
  }

  private func detail(for credit: LicenseCredit) -> some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 12) {
        VStack(alignment: .leading, spacing: 4) {
          Text(credit.role)
            .font(.subheadline)
            .foregroundStyle(.secondary)
          if let url = credit.url {
            Link(credit.displayLink, destination: url)
              .font(.caption)
          }
        }

        Text(credit.licenseText())
          .font(.caption.monospaced())
          .textSelection(.enabled)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      .padding()
    }
    .navigationTitle(credit.name)
    .navigationBarTitleDisplayMode(.inline)
  }
}
