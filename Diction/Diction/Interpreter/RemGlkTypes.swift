import Foundation

/// Decoded payload of a single RemGlk JSON output update.
/// One update is one round-trip with the interpreter.
nonisolated struct RemGlkUpdate: Codable, Sendable {
  var type: String
  var gen: Int?
  var windows: [Window]?
  var content: [Content]?
  var input: [InputRequest]?
  var disable: Bool?
  var exit: Bool?
  /// Repeating timer interval in milliseconds, or null to cancel. The game
  /// arms this via `glk_request_timer_events`; we don't yet drive the round-trip.
  var timer: Int?
  /// Present when the interpreter is blocked waiting for a fileref dialog
  /// (save / restore / transcript / command-record / data resource).
  /// `WebInterpreterHost` answers it internally and routes the bytes to
  /// `SaveStorage`, so the session itself never sees this set.
  var specialinput: SpecialRequest?

  struct Window: Codable, Sendable {
    var id: Int
    var type: WindowType
    var rock: Int?
    // Pixel/character geometry, present on window create/rearrange. Grid
    // windows also report `gridwidth`/`gridheight` (character cells).
    var left: Int?
    var top: Int?
    var width: Int?
    var height: Int?
    var gridwidth: Int?
    var gridheight: Int?
    /// Per-window computed style table, keyed by `.Style_<name>` (e.g.
    /// `.Style_user2`). This is where a named style's colour/weight/etc. lives
    /// — a native client has no stylesheet, so RemGlk serializes it here. A
    /// run's effective look is this entry merged with the run's own
    /// `cssStyles` override (the run wins on conflict).
    var styles: [String: StyleAttributes]?
  }

  enum WindowType: String, Codable, Sendable {
    case buffer
    case grid
    case graphics
    case pair
    case blank
  }

  struct Content: Codable, Sendable {
    var id: Int
    /// Buffer-window content: lines appended (or merged) into the scrollback.
    var text: [Line]?
    /// Grid-window content: specific rows replaced by line number.
    var lines: [GridLine]?
    var clear: Bool?
    // swiftlint:disable identifier_name
    /// Window default foreground / background colour (CSS strings), set via
    /// stylehints or `glk_window_set_background_color`. Often null. Names mirror
    /// RemGlk's literal `fg`/`bg` keys so auto-`Codable` matches the wire format
    /// — renaming would force a `CodingKeys` enum that trips the nesting rule.
    var fg: String?
    var bg: String?
    // swiftlint:enable identifier_name
  }

  /// One row of a grid (status) window. Each update replaces the named rows;
  /// untouched rows persist.
  struct GridLine: Codable, Sendable {
    var line: Int
    var content: [TextRun]?
  }

  struct Line: Codable, Sendable {
    var content: [TextRun]?
    var append: Bool?
    /// Forces a paragraph break around a floated image. Rare; informational.
    var flowbreak: Bool?

    enum CodingKeys: String, CodingKey {
      case content
      case append
      case flowbreak
    }

    init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      append = try container.decodeIfPresent(Bool.self, forKey: .append)
      flowbreak = try container.decodeIfPresent(Bool.self, forKey: .flowbreak)
      if let runs = try? container.decode([TextRun].self, forKey: .content) {
        content = runs
      } else {
        content = nil
      }
    }

    init(content: [TextRun]?, append: Bool? = nil, flowbreak: Bool? = nil) {
      self.content = content
      self.append = append
      self.flowbreak = flowbreak
    }

    func encode(to encoder: Encoder) throws {
      var container = encoder.container(keyedBy: CodingKeys.self)
      try container.encodeIfPresent(content, forKey: .content)
      try container.encodeIfPresent(append, forKey: .append)
      try container.encodeIfPresent(flowbreak, forKey: .flowbreak)
    }
  }

  struct TextRun: Codable, Sendable {
    var style: TextStyle?
    var text: String
    /// Hyperlink target value if this run is a link (`glk_set_hyperlink`).
    var hyperlink: Int?
    /// Per-run inline style override (e.g. `{"reverse": 1}` for AMFV's status
    /// bar). Merged over the window's named-style entry to get the effective look.
    var cssStyles: StyleAttributes?

    init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      style = try container.decodeIfPresent(TextStyle.self, forKey: .style)
      text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
      hyperlink = try container.decodeIfPresent(Int.self, forKey: .hyperlink)
      cssStyles = try container.decodeIfPresent(StyleAttributes.self, forKey: .cssStyles)
    }

    init(style: TextStyle? = nil, text: String, hyperlink: Int? = nil,
         cssStyles: StyleAttributes? = nil) {
      self.style = style
      self.text = text
      self.hyperlink = hyperlink
      self.cssStyles = cssStyles
    }

    enum CodingKeys: String, CodingKey {
      case style
      case text
      case hyperlink
      case cssStyles = "css_styles"
    }
  }

  enum TextStyle: String, Codable, Sendable {
    case normal
    case emphasized
    case preformatted
    case header
    case subheader
    case alert
    case note
    case blockQuote = "blockquote"
    case input
    case user1
    case user2
  }

  struct InputRequest: Codable, Sendable {
    var id: Int
    /// The input kind, or nil. RemGlk lists EVERY window awaiting input here; a
    /// window requesting only hyperlink/mouse input — e.g. a graphics window —
    /// has an entry with NO `type` key, so it decodes to nil. The session acts
    /// only on `.line`/`.char`, so nil entries are ignored. This MUST be optional:
    /// a required `type` threw and dropped the WHOLE update the instant a graphics
    /// window opened, hanging the turn and stranding the prompt (Counterfeit
    /// Monkey's map). RemGlk only ever sends "line", "char", or omits `type`, so
    /// the synthesized `decodeIfPresent` (absent → nil) is sufficient.
    var type: InputType?
    var maxlen: Int?
    var gen: Int?
    var initial: String?
    /// Cursor column/row for input in a GRID window (glkapi.js:696-730 sets these
    /// from `win.cursorx`/`win.cursory` for both char and line input). Nil for
    /// buffer-window input. Used to draw a blinking cursor over the native status
    /// bar so the player can see where a form (e.g. Bureaucracy) is taking input.
    var xpos: Int?
    var ypos: Int?
  }

  enum InputType: String, Codable, Sendable {
    case line
    case char
  }

  struct SpecialRequest: Codable, Sendable {
    /// Always "fileref_prompt" in current RemGlk. Decoded leniently so an
    /// unknown future variant doesn't crash; the responder checks it.
    var type: String
    var filemode: FileMode
    var filetype: FileType
    var gameid: String?
  }

  enum FileMode: String, Codable, Sendable {
    case read
    case write
    case readwrite
    case writeappend
  }

  enum FileType: String, Codable, Sendable {
    case save
    case transcript
    case command
    case data
  }
}

/// A computed style description, shared by a window's named-style table and a
/// run's per-run `css_styles` override. Carries the CSS-ish properties RemGlk
/// emits; unknown keys are ignored, so new ones don't break decoding.
///
/// `reverse` and `monospace` arrive as JSON numbers (0/1), the rest as strings
/// (`color: "#0000FF"`, `font-weight: "bold"`, `font-size: "1em"`).
nonisolated struct StyleAttributes: Codable, Sendable, Equatable {
  var color: String?
  var backgroundColor: String?
  var reverse: Bool?
  var fontWeight: String?
  var fontStyle: String?
  var monospace: Bool?
  var fontSize: String?
  var textAlign: String?

  enum CodingKeys: String, CodingKey {
    case color
    case backgroundColor = "background-color"
    case reverse
    case fontWeight = "font-weight"
    case fontStyle = "font-style"
    case monospace
    case fontSize = "font-size"
    case textAlign = "text-align"
  }

  init(
    color: String? = nil, backgroundColor: String? = nil, reverse: Bool? = nil,
    fontWeight: String? = nil, fontStyle: String? = nil, monospace: Bool? = nil,
    fontSize: String? = nil, textAlign: String? = nil
  ) {
    self.color = color
    self.backgroundColor = backgroundColor
    self.reverse = reverse
    self.fontWeight = fontWeight
    self.fontStyle = fontStyle
    self.monospace = monospace
    self.fontSize = fontSize
    self.textAlign = textAlign
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    color = try container.decodeIfPresent(String.self, forKey: .color)
    backgroundColor = try container.decodeIfPresent(String.self, forKey: .backgroundColor)
    fontWeight = try container.decodeIfPresent(String.self, forKey: .fontWeight)
    fontStyle = try container.decodeIfPresent(String.self, forKey: .fontStyle)
    fontSize = try container.decodeIfPresent(String.self, forKey: .fontSize)
    textAlign = try container.decodeIfPresent(String.self, forKey: .textAlign)
    reverse = (try container.decodeIfPresent(Int.self, forKey: .reverse)).map { $0 != 0 }
    monospace = (try container.decodeIfPresent(Int.self, forKey: .monospace)).map { $0 != 0 }
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encodeIfPresent(color, forKey: .color)
    try container.encodeIfPresent(backgroundColor, forKey: .backgroundColor)
    try container.encodeIfPresent(reverse.map { $0 ? 1 : 0 }, forKey: .reverse)
    try container.encodeIfPresent(fontWeight, forKey: .fontWeight)
    try container.encodeIfPresent(fontStyle, forKey: .fontStyle)
    try container.encodeIfPresent(monospace.map { $0 ? 1 : 0 }, forKey: .monospace)
    try container.encodeIfPresent(fontSize, forKey: .fontSize)
    try container.encodeIfPresent(textAlign, forKey: .textAlign)
  }

  /// Overlay `override`'s set fields onto these — the override wins on any
  /// field it specifies, unset fields fall through. Resolves a run's effective
  /// look: `windowNamedStyle.overlaying(run.cssStyles)`.
  func overlaying(_ override: StyleAttributes?) -> StyleAttributes {
    guard let override else { return self }
    return StyleAttributes(
      color: override.color ?? color,
      backgroundColor: override.backgroundColor ?? backgroundColor,
      reverse: override.reverse ?? reverse,
      fontWeight: override.fontWeight ?? fontWeight,
      fontStyle: override.fontStyle ?? fontStyle,
      monospace: override.monospace ?? monospace,
      fontSize: override.fontSize ?? fontSize,
      textAlign: override.textAlign ?? textAlign
    )
  }
}

/// JSON payload we send back to the interpreter for line input.
nonisolated struct RemGlkLineInput: Codable, Sendable {
  var type: String = "line"
  var gen: Int
  var window: Int
  var value: String
}

/// JSON payload for character input.
nonisolated struct RemGlkCharInput: Codable, Sendable {
  var type: String = "char"
  var gen: Int
  var window: Int
  var value: String
}
