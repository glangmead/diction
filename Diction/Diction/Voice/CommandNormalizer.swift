import Foundation
import FoundationModels

/// Maps natural-language speech to interactive-fiction parser commands.
/// Uses Apple's on-device foundation model via `FoundationModels`.
@Observable
@MainActor
final class CommandNormalizer {
  private var session: LanguageModelSession?
  private var configuredVocabulary: [String] = []
  private(set) var lastError: String?

  /// Re-prime the session with the current game's vocabulary. Cheap enough
  /// to call whenever the game changes.
  func configure(context: any GameContext) {
    let vocabulary = Array(context.contextualStrings.prefix(200))
    if vocabulary == configuredVocabulary, session != nil { return }
    configuredVocabulary = vocabulary

    let verbList = vocabulary.joined(separator: ", ")
    let instructions = Instructions {
      """
      You convert spoken English into interactive-fiction parser commands.
      The game's parser knows these words: \(verbList).

      Rules:
      - Output the command in UPPERCASE.
      - Use the simplest form. "TAKE LANTERN", not "PICK UP THE BRASS LANTERN".
      - Convert directions to single words: "go north" -> "NORTH".
      - "what do I have" -> "INVENTORY".
      - "where am I" or "look around" -> "LOOK".
      - "hit the troll with the sword" -> "ATTACK TROLL WITH SWORD".

      Confidence:
      - high if the mapping is unambiguous.
      - medium if you had to guess between two parser verbs.
      - low if the user said something that doesn't map cleanly to a command.
      """
    }
    session = LanguageModelSession(instructions: instructions)
  }

  /// Normalize a speech transcription into a parser command.
  /// Falls back to uppercasing the input if the model is unavailable.
  func normalize(_ speech: String, context: any GameContext) async -> NormalizedCommand {
    configure(context: context)
    guard let session else {
      return NormalizedCommand(
        command: speech.uppercased(),
        confidence: .low
      )
    }

    do {
      let response = try await session.respond(
        to: "Convert this to a parser command: \"\(speech)\"",
        generating: NormalizedCommand.self
      )
      return response.content
    } catch {
      lastError = "Normalization failed: \(error)"
      return NormalizedCommand(
        command: speech.uppercased(),
        confidence: .low
      )
    }
  }
}

@Generable
struct NormalizedCommand: Sendable {
  @Guide(description: "The parser command in uppercase")
  var command: String

  var confidence: Confidence

  @Generable
  enum Confidence: String, Sendable {
    case high
    case medium
    case low
  }
}
