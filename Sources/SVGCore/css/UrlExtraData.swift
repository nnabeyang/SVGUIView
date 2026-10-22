import Foundation
import _CSSParser

struct URLExtraData {
  let value: URL

  init(_ value: URL) {
    self.value = value
  }

  var chromeRulesEnabled: Bool {
    value.scheme == "chrome"
  }
}

extension URLExtraData: From {
  static func from(_ other: URL) -> URLExtraData {
    Self(other)
  }
}
