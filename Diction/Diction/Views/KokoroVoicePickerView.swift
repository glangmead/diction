import AVFoundation
import SwiftUI

/// Picks one of the bundled neural voices, grouped by accent and gender. Each
/// row has an audition button that synthesizes a sample line in that voice via
/// a self-contained `KokoroSpeechEngine` (no dependency on a running game).
struct KokoroVoicePickerView: View {
  let title: String
  @Binding var selectedVoiceID: String
  @Environment(\.dismiss) private var dismiss

  @State private var audition = KokoroSpeechEngine()
  @State private var auditioningVoice: String?

  /// Shared speech-rate setting, so auditions play at the rate the user picked.
  @AppStorage("speechRate") private var speechRate: Double = Double(
    AVSpeechUtteranceDefaultSpeechRate
  )

  /// IF-flavored sample: caps proper nouns and a period boundary, where these
  /// models' grapheme-to-phoneme frontends tend to stumble.
  private static let sampleLine =
    "West of House. You are standing in an open field, west of a white house."

  /// Voices grouped by accent/gender, in catalog order. Static: depends only on
  /// the bundled-voice list, so it's built once rather than every `body` pass.
  private static let groups: [(label: String, ids: [String])] = {
    var order: [String] = []
    var map: [String: [String]] = [:]
    for id in KokoroSpeechEngine.bundledEnglishVoiceIDs {
      let label = KokoroSpeechEngine.accentLabel(for: id)
      if map[label] == nil { order.append(label) }
      map[label, default: []].append(id)
    }
    return order.map { ($0, map[$0] ?? []) }
  }()

  var body: some View {
    List {
      Section {
        LabeledContent("Engine", value: audition.statusDescription)
      } footer: {
        Text("Loads the neural model on this device. If it says Unavailable, narration uses the system voice.")
      }
      ForEach(Self.groups, id: \.label) { group in
        Section(group.label) {
          ForEach(group.ids, id: \.self) { id in
            row(for: id)
          }
        }
      }
    }
    .navigationTitle(title)
    .navigationBarTitleDisplayMode(.inline)
    .task {
      audition.managesSession = true  // no recognizer here; configure the session
      await audition.prepareIfNeeded()
    }
  }

  private func row(for id: String) -> some View {
    HStack {
      Button {
        selectedVoiceID = id
        dismiss()
      } label: {
        HStack {
          Text(KokoroSpeechEngine.displayName(for: id))
            .foregroundStyle(.primary)
          Spacer()
          if id == selectedVoiceID {
            Image(systemName: "checkmark")
              .foregroundStyle(.tint)
              .accessibilityHidden(true)  // selection conveyed by the trait below
          }
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityAddTraits(id == selectedVoiceID ? [.isSelected] : [])

      Button {
        auditionVoice(id)
      } label: {
        if auditioningVoice == id {
          ProgressView()
        } else {
          Image(systemName: "play.circle")
        }
      }
      .buttonStyle(.borderless)
       .contentShape(Rectangle())
      .accessibilityLabel("Audition \(KokoroSpeechEngine.displayName(for: id))")
    }
  }

  private func auditionVoice(_ id: String) {
    audition.stop()
    auditioningVoice = id
    Task {
      await audition.prepareIfNeeded()
      let speed = KokoroSpeechEngine.speed(forStoredRate: Float(speechRate))
      await audition.speak(Self.sampleLine, voice: id, speed: speed)
      if auditioningVoice == id { auditioningVoice = nil }
    }
  }
}
