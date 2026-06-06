import Testing
@testable import Diction

/// The catalog is the single source for parsing the wake-word command vocabulary
/// (and, separately, rendering the help readout). These exercise the parser seam
/// directly — synonyms, the numbered `window N` / `input N` forms, and the
/// number-word and glued spellings the recognizer emits.
@Suite("Voice command catalog parsing")
struct VoiceCommandCatalogTests {
  @Test("existing plain commands still parse")
  func existingCommands() {
    #expect(VoiceCommandCatalog.parse("reread") == .reread)
    #expect(VoiceCommandCatalog.parse("stop") == .stop)
    #expect(VoiceCommandCatalog.parse("faster") == .faster)
    #expect(VoiceCommandCatalog.parse("slower") == .slower)
    #expect(VoiceCommandCatalog.parse("say that again") == .reread)
    #expect(VoiceCommandCatalog.parse("shut up") == .stop)
  }

  @Test("new plain commands and their synonyms parse")
  func newPlainCommands() {
    #expect(VoiceCommandCatalog.parse("help") == .help)
    #expect(VoiceCommandCatalog.parse("commands") == .help)
    #expect(VoiceCommandCatalog.parse("windows") == .windows)
    #expect(VoiceCommandCatalog.parse("panels") == .windows)
    #expect(VoiceCommandCatalog.parse("history") == .history)
    #expect(VoiceCommandCatalog.parse("inputs") == .history)
    #expect(VoiceCommandCatalog.parse("keywords") == .keywords)
    #expect(VoiceCommandCatalog.parse("bolded") == .keywords)
    #expect(VoiceCommandCatalog.parse("bold") == .keywords)
  }

  @Test("numbered window command parses digits, number words, and the glued form")
  func numberedWindow() {
    #expect(VoiceCommandCatalog.parse("window 2") == .window(2))
    #expect(VoiceCommandCatalog.parse("window two") == .window(2))
    #expect(VoiceCommandCatalog.parse("window2") == .window(2))
  }

  @Test("numbered input command parses one- and two-digit numbers")
  func numberedInput() {
    #expect(VoiceCommandCatalog.parse("input 1") == .input(1))
    #expect(VoiceCommandCatalog.parse("input 15") == .input(15))
    #expect(VoiceCommandCatalog.parse("input fifteen") == .input(15))
  }

  @Test("parsing is case-insensitive and tolerant of surrounding whitespace")
  func caseAndWhitespace() {
    #expect(VoiceCommandCatalog.parse("  Window   3 ") == .window(3))
    #expect(VoiceCommandCatalog.parse("KEYWORDS") == .keywords)
  }

  @Test("an unknown utterance does not parse")
  func unknown() {
    #expect(VoiceCommandCatalog.parse("flibbertigibbet") == nil)
    #expect(VoiceCommandCatalog.parse("window") == nil)   // numbered command needs a number
    #expect(VoiceCommandCatalog.parse("input banana") == nil)
  }
}
