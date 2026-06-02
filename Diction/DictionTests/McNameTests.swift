import Testing
@testable import Diction

// The neural OOV G2P swallows the consonant in "McB…"/"McW…" (it hears
// "McCain"). `mcNameRemainder` decides which "Mc" names to split off and
// pronounce as /mək/ + the remainder, leaving the merge (C/K/Q) and vowel cases
// to the neural, which already handles them.

@MainActor
@Suite("Mc-name split")
struct McNameTests {
  @Test("Mc + a pronounced consonant returns the remainder")
  func splitsPronouncedConsonants() {
    #expect(KokoroPhonemizer.mcNameRemainder("McBain") == "Bain")
    #expect(KokoroPhonemizer.mcNameRemainder("McWain") == "Wain")
    #expect(KokoroPhonemizer.mcNameRemainder("McDonald") == "Donald")
    #expect(KokoroPhonemizer.mcNameRemainder("McMain") == "Main")
  }

  @Test("Mc + C/K/Q merges to one /k/, so it isn't split")
  func leavesMergingInitials() {
    #expect(KokoroPhonemizer.mcNameRemainder("McKay") == nil)
    #expect(KokoroPhonemizer.mcNameRemainder("McCain") == nil)
    #expect(KokoroPhonemizer.mcNameRemainder("McQueen") == nil)
  }

  @Test("Mc + a vowel attaches to the c, so it isn't split")
  func leavesVowels() {
    #expect(KokoroPhonemizer.mcNameRemainder("McArthur") == nil)
    #expect(KokoroPhonemizer.mcNameRemainder("McEwan") == nil)
  }

  @Test("Non-Mc, bare Mc, and lowercase remainders are ignored")
  func ignoresNonNames() {
    #expect(KokoroPhonemizer.mcNameRemainder("Mc") == nil)
    #expect(KokoroPhonemizer.mcNameRemainder("Mcbain") == nil)   // lowercase remainder
    #expect(KokoroPhonemizer.mcNameRemainder("machine") == nil)
    #expect(KokoroPhonemizer.mcNameRemainder("Bain") == nil)
  }
}
