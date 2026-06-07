import Testing
@testable import Diction

/// Appending a double-tapped word to the command field with smart spacing and
/// punctuation cleaning. See `CommandWordComposer`.
struct CommandWordComposerTests {
  @Test("Appends to an empty field with a trailing space, no leading space")
  func emptyField() {
    #expect(CommandWordComposer.append("sword", to: "") == "sword ")
  }

  @Test("Appends after a word with one separating space")
  func afterWord() {
    #expect(CommandWordComposer.append("sword", to: "take") == "take sword ")
  }

  @Test("Doesn't double the space when the field already ends with one")
  func afterTrailingSpace() {
    #expect(CommandWordComposer.append("sword", to: "take ") == "take sword ")
  }

  @Test("Strips surrounding punctuation")
  func stripsPunctuation() {
    #expect(CommandWordComposer.append("sword.", to: "take") == "take sword ")
    #expect(CommandWordComposer.append("(north)", to: "") == "north ")
  }

  @Test("Keeps internal apostrophes and hyphens")
  func keepsInternalPunctuation() {
    #expect(CommandWordComposer.append("don't", to: "") == "don't ")
    #expect(CommandWordComposer.append("north-east", to: "go") == "go north-east ")
  }

  @Test("A word that's empty after cleaning leaves the field unchanged")
  func emptyAfterClean() {
    #expect(CommandWordComposer.append("...", to: "take") == "take")
    #expect(CommandWordComposer.append("   ", to: "take ") == "take ")
  }
}
