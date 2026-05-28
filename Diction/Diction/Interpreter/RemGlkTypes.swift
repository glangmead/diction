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

  struct Window: Codable, Sendable {
    var id: Int
    var type: WindowType
    var rock: Int?
  }

  enum WindowType: String, Codable, Sendable {
    case buffer
    case grid
    case graphics
    case pair
  }

  struct Content: Codable, Sendable {
    var id: Int
    var text: [Line]?
    var clear: Bool?
  }

  struct Line: Codable, Sendable {
    var content: [TextRun]?
    var append: Bool?

    enum CodingKeys: String, CodingKey {
      case content
      case append
    }

    init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      append = try container.decodeIfPresent(Bool.self, forKey: .append)
      if let runs = try? container.decode([TextRun].self, forKey: .content) {
        content = runs
      } else {
        content = nil
      }
    }

    init(content: [TextRun]?, append: Bool? = nil) {
      self.content = content
      self.append = append
    }

    func encode(to encoder: Encoder) throws {
      var container = encoder.container(keyedBy: CodingKeys.self)
      try container.encodeIfPresent(content, forKey: .content)
      try container.encodeIfPresent(append, forKey: .append)
    }
  }

  struct TextRun: Codable, Sendable {
    var style: TextStyle?
    var text: String

    init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      style = try container.decodeIfPresent(TextStyle.self, forKey: .style)
      text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
    }

    init(style: TextStyle? = nil, text: String) {
      self.style = style
      self.text = text
    }

    enum CodingKeys: String, CodingKey {
      case style
      case text
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
    var type: InputType
    var maxlen: Int?
    var gen: Int?
    var initial: String?
  }

  enum InputType: String, Codable, Sendable {
    case line
    case char
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

/// JSON payload for window arrangement (sent on init to set metrics).
nonisolated struct RemGlkArrangeInput: Codable, Sendable {
  var type: String = "arrange"
  var gen: Int
  var metrics: Metrics

  struct Metrics: Codable, Sendable {
    var width: Double
    var height: Double
  }
}
