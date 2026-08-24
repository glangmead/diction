import Foundation
import NaturalLanguage

nonisolated extension NLTag {
  var isProperNoun: Bool {
    return self == .personalName || self == .organizationName || self == .placeName
  }
}
