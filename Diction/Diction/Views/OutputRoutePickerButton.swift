import AVKit
import SwiftUI

/// Wraps `AVRoutePickerView`, the only sanctioned control for choosing the audio
/// *output* device (AirPods, speaker, AirPlay). iOS reserves output-route
/// selection for this system UI, so this is the one place the app reaches for
/// UIKit on the audio path. Follows the `InterpreterWebView` representable pattern.
struct OutputRoutePickerButton: UIViewRepresentable {
  func makeUIView(context: Context) -> AVRoutePickerView {
    let picker = AVRoutePickerView()
    picker.prioritizesVideoDevices = false
    picker.tintColor = .label
    picker.activeTintColor = .systemBlue
    picker.accessibilityLabel = "Choose audio output"
    return picker
  }

  func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
