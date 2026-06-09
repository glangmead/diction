import SwiftUI

/// Output-only audio routing, shown from the speaker button's hold menu. The system
/// route picker (`AVRoutePickerView`) is the only sanctioned way to choose an output
/// device, so it lives here with the current-route readout. Injected via
/// `.environment` so the `@Observable` controller keeps change tracking across the
/// popover boundary (the cover-boundary gotcha in the project guide).
struct OutputRoutePopover: View {
  @Environment(AudioRouteController.self) private var audioRoute

  var body: some View {
    List {
      Section("Audio output") {
        LabeledContent("Device") {
          OutputRoutePickerButton()
            .frame(width: 40, height: 40)
        }
        if !audioRoute.currentOutputName.isEmpty {
          Text(audioRoute.currentOutputName)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Currently playing through \(audioRoute.currentOutputName)")
        }
      }
    }
    .frame(idealWidth: 300, idealHeight: 180)
  }
}
