import Foundation

/// Picks which transcript entries to narrate when voice mode first becomes
/// active on a freshly loaded game. Strips the title / copyright / serial-
/// number boilerplate that typically opens Z-machine and Glulx games, so
/// only the actual room description and prompt are spoken.
///
/// Heuristic, in order:
/// 1. Find the last entry (within the first ~12) that contains both
///    "release" and "serial" — the canonical Z-machine/Inform metadata
///    line. Everything after it is gameplay content.
/// 2. Failing that, fall back to keyword matching on broader metadata
///    terms (copyright, trademark, all rights reserved).
/// 3. If neither matches, narrate the whole transcript.
nonisolated enum InitialNarration {
  static func entries(from transcript: [StyledText]) -> [StyledText] {
    let searchLimit = min(12, transcript.count)
    let texts = (0..<searchLimit).map { transcript[$0].plainText.lowercased() }

    // Strong signal: "Release N / Serial number XXX" line.
    if let pivot = texts.lastIndex(where: { $0.contains("release") && $0.contains("serial") }) {
      return slice(transcript, after: pivot)
    }

    // Fallback: any line containing one of these metadata terms.
    if let pivot = texts.lastIndex(where: { text in
      fallbackTerms.contains(where: text.contains)
    }) {
      return slice(transcript, after: pivot)
    }

    return transcript
  }

  private static let fallbackTerms: [String] = [
    "copyright", "©", "(c)", "all rights reserved",
    "trademark", "registered",
    "interactive fiction by"
  ]

  private static func slice(_ transcript: [StyledText], after index: Int) -> [StyledText] {
    let start = index + 1
    guard start < transcript.count else { return [] }
    return Array(transcript[start...])
  }
}
