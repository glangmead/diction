import Testing
import Foundation
@testable import Diction

@Test("EmglkenFilerefResponse encodes type/gen/response + value.filename")
func filerefResponseJSON() throws {
  let response = EmglkenFilerefResponse(gen: 4, response: "fileref_prompt", value: .init(filename: "save"))
  let data = try JSONEncoder().encode(response)
  let obj = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
  #expect(obj["type"] as? String == "specialresponse")
  #expect(obj["gen"] as? Int == 4)
  #expect(obj["response"] as? String == "fileref_prompt")
  #expect((obj["value"] as? [String: Any])?["filename"] as? String == "save")
}
