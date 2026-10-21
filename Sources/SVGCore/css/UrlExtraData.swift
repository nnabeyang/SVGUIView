import Foundation
import _CSSParser

public struct URLExtraData {
  public let value: URL

  public init(_ value: URL) {
    self.value = value
  }

  public var chromeRulesEnabled: Bool {
    value.scheme == "chrome"
  }
}

extension URLExtraData: From {
  public static func from(_ other: URL) -> URLExtraData {
    Self(other)
  }
}
