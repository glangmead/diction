import Testing
@testable import Diction

// AMFV's "[Hit any key to continue.]" prompt takes char input. The keypress's
// response (RemGlk update 1 in nocommit/glk-capture/amfv-capture.json) redraws
// the story window — `clear: true` on the primary buffer — then prints
// 'You "hear" a message coming in…' (append:true), 'A Mind Forever Voyaging',
// and the rest. Slicing the transcript by a pre-send index skips the response's
// first lines once the clear has wiped the old scrollback; the report was
// narration starting at 'A Mind Forever Voyaging', skipping 'You "hear"…'.
//
// `InterpreterSession.responseWindow` is the fix: given the post-apply transcript
// and whether the update redrew, it returns the entries to narrate. A redraw
// means the whole transcript is the response (start 0); otherwise it runs from
// the input echo, onto which the response's first line may have merged.

@MainActor
@Suite("Char response narration")
struct CharResponseNarrationTests {
  /// Update-1-shaped content. `cleared` toggles AMFV's screen redraw.
  private func amfvResponse(cleared: Bool) -> RemGlkUpdate.Content {
    RemGlkUpdate.Content(
      id: 2,
      text: [
        .init(content: [.init(text: "You \"hear\" a message coming in.")], append: true),
        .init(content: [.init(text: "")], append: false),
        .init(content: [.init(text: "A Mind Forever Voyaging")], append: false),
        .init(content: [.init(text: "Copyright (c) 1985 by Infocom, Inc.")], append: false)
      ],
      clear: cleared
    )
  }

  /// Replays the transcript mutations a send performs (append the input echo,
  /// apply the buffer content), then asks for the narration window.
  private func narrated(cleared: Bool) -> String {
    var transcript: [StyledText] = [
      StyledText(from: [.init(text: "[Hit any key to continue.]")])
    ]
    let echoIndex = transcript.count
    transcript.append(.userInput("[SPACE]"))
    StyledText.applyBufferContent(amfvResponse(cleared: cleared), styleTable: nil, into: &transcript)

    let window = InterpreterSession.responseWindow(
      transcript: transcript, echoIndex: echoIndex, didClear: cleared
    )
    return window.entries.map(\.plainText).joined(separator: "\n")
  }

  @Test("a redraw response keeps its first line (the AMFV bug)")
  func clearedResponseKeepsFirstLine() {
    let spoken = narrated(cleared: true)
    #expect(spoken.contains("You \"hear\" a message coming in"))
    #expect(spoken.contains("A Mind Forever Voyaging"))
  }

  @Test("a non-redraw response keeps its appended first line")
  func appendedResponseKeepsFirstLine() {
    let spoken = narrated(cleared: false)
    #expect(spoken.contains("You \"hear\" a message coming in"))
    #expect(spoken.contains("A Mind Forever Voyaging"))
  }
}
