import Foundation
import _CSSParser

public struct NamespacePair<Prefix: Equatable, Url: Equatable>: Equatable {
  public let prefix: Prefix
  public let url: Url
  public init(prefix: Prefix, url: Url) {
    self.prefix = prefix
    self.url = url
  }
}

public struct AttrSelectorWithOptionalNamespace<Impl: SelectorImpl>: Equatable {
  public let namespace: NamespaceConstraint<NamespacePair<Impl.NamespacePrefix, Impl.NamespaceUrl>>?
  public let localName: Impl.LocalName
  public let localNameLower: Impl.LocalName
  public let operation: ParsedAttrSelectorOperation<Impl.AttrValue>

  public func getNamespace() -> NamespaceConstraint<Impl.NamespaceUrl>? {
    namespace.map {
      switch $0 {
      case .any: .any
      case .specific(let pair): .specific(pair.url)
      }
    }
  }
}

extension AttrSelectorWithOptionalNamespace: ToCSS {
  public func toCSS(to dest: inout some TextOutputStream) {
    dest.write("[")
    switch namespace {
    case .specific(let pair):
      pair.prefix.toCSS(to: &dest)
      dest.write("|")
    case .any:
      dest.write("*|")
    case .none:
      break
    }
    localName.toCSS(to: &dest)
    switch operation {
    case .exists:
      break
    case .withValue(let op, let caseSensitivity, let value):
      op.toCSS(to: &dest)
      value.toCSS(to: &dest)
      switch caseSensitivity {
      case .caseSensitive, .asciiCaseInsensitiveIfInHtmlElementInHtmlDocument:
        break
      case .asciiCaseInsensitive:
        dest.write(" i")
      case .explicitCaseSensitive:
        dest.write(" s")
      }
    }
    dest.write("]")
  }
}

public enum NamespaceConstraint<NamespaceUrl: Equatable>: Equatable {
  case any
  case specific(NamespaceUrl)
}

public enum ParsedAttrSelectorOperation<AttrValue: Equatable>: Equatable {
  case exists
  case withValue(operator: AttrSelectorOperator, caseSensitivity: ParsedCaseSensitivity, value: AttrValue)
}

public enum AttrSelectorOperation<AttrValue> {
  case exists
  case withValue(operator: AttrSelectorOperator, CaseSensitivity: CaseSensitivity, value: AttrValue)

  public func evalString(elementAttrValue: String) -> Bool where AttrValue: StringProtocol {
    switch self {
    case .exists:
      return true
    case .withValue(let op, let CaseSensitivity, let value):
      return op.evalString(elementAttrValue: elementAttrValue, attrSelectorValue: String(value), caseSensitivity: CaseSensitivity)
    }
  }
}

let SELECTOR_WHITESPACE: Set<Character> = [" ", "\t", "\n", "\r", "\u{000C}"]

public enum AttrSelectorOperator: Equatable {
  case equal
  case includes
  case dashMatch
  case prefix
  case substring
  case suffix

  public func evalString(elementAttrValue: String, attrSelectorValue: String, caseSensitivity: CaseSensitivity) -> Bool {
    let e = Data(elementAttrValue.utf8)
    let s = Data(attrSelectorValue.utf8)

    return switch self {
    case .equal:
      caseSensitivity.equals(e, s)
    case .prefix:
      !s.isEmpty && e.count >= s.count && caseSensitivity.equals(e[..<s.count], s)
    case .suffix:
      !s.isEmpty && e.count >= s.count && caseSensitivity.equals(e[(e.count - s.count)...], s)
    case .substring:
      !s.isEmpty && caseSensitivity.contains(haystack: elementAttrValue, needle: attrSelectorValue)
    case .includes:
      !s.isEmpty
        && !elementAttrValue.split(
          omittingEmptySubsequences: false,
          whereSeparator: { SELECTOR_WHITESPACE.contains($0) }
        ).contains(where: { !caseSensitivity.equals(Data($0.utf8), s) })
    case .dashMatch:
      caseSensitivity.equals(e, s) || (e.last == UInt8(ascii: "-") && caseSensitivity.equals(e[..<s.count], s))
    }
  }
}

extension AttrSelectorOperator: ToCSS {
  public func toCSS(to dest: inout some TextOutputStream) {
    // https://drafts.csswg.org/cssom/#serializing-selectors
    let css =
      switch self {
      case .equal: "="
      case .includes: "~="
      case .dashMatch: "|="
      case .prefix: "^="
      case .substring: "*="
      case .suffix: "$="
      }
    dest.write(css)
  }
}

public enum CaseSensitivity {
  case caseSensitive
  case asciiCaseInsensitive

  public func equals(_ lhs: Data, _ rhs: Data) -> Bool {
    switch self {
    case .caseSensitive: lhs == rhs
    case .asciiCaseInsensitive: lhs.isEqualAsciiCaseInsensitive(to: rhs)
    }
  }

  public func contains(haystack: String, needle: String) -> Bool {
    switch self {
    case .caseSensitive:
      return haystack.contains(needle)
    case .asciiCaseInsensitive:
      if let (firstByte, restBytes) = Data(needle.utf8).splitFirst() {
        return haystack.utf8.enumerated().contains { i, byte in
          if !byte.isEqualAsciiCaseInsensitive(firstByte) {
            return false
          }
          let haystackBytes = Data(haystack.utf8)
          let afterThisBytes = haystackBytes[(i + 1)...]
          if afterThisBytes.count < restBytes.count { return false }
          let haystackSlice = afterThisBytes[..<restBytes.count]
          return haystackSlice.isEqualAsciiCaseInsensitive(to: restBytes)
        }
      } else {
        return false
      }
    }
  }
}

public enum ParsedCaseSensitivity: Equatable {
  case explicitCaseSensitive
  case asciiCaseInsensitive
  case caseSensitive
  case asciiCaseInsensitiveIfInHtmlElementInHtmlDocument
}

extension Data {
  func isEqualAsciiCaseInsensitive(to other: Data) -> Bool {
    if count != other.count { return false }
    return withUnsafeBytes { lhs in
      return other.withUnsafeBytes { rhs in
        let lhs = lhs.bindMemory(to: UInt8.self)
        let rhs = rhs.bindMemory(to: UInt8.self)

        for i in 0..<lhs.count {
          let a = lhs[i]
          let b = rhs[i]
          if !a.isEqualAsciiCaseInsensitive(b) { return false }
        }
        return true
      }
    }
  }
}

extension Substring {
  func toAsciiLowercase() -> String {
    var data = Data(utf8)
    data.withUnsafeMutableBytes { rawBuffer in
      let count = rawBuffer.count
      guard count > 0, let baseAddress = rawBuffer.baseAddress else { return }
      let ptr = baseAddress.assumingMemoryBound(to: UInt8.self)
      for i in 0..<count {
        ptr.advanced(by: i).pointee.makeAsciiLowercase()
      }
    }
    return String(decoding: data, as: UTF8.self)
  }
}

private let ASCII_CASE_MASK: UInt8 = 0x20
extension UInt8 {
  func isEqualAsciiCaseInsensitive(_ other: UInt8) -> Bool {
    toAsciiLowercase == other.toAsciiLowercase
  }

  var toAsciiLowercase: Self {
    self | (isAsciiUppercase ? ASCII_CASE_MASK : 0)
  }

  mutating func makeAsciiLowercase() {
    self = toAsciiLowercase
  }

  var isAsciiUppercase: Bool {
    (UInt8(ascii: "A")...UInt8(ascii: "Z")).contains(self)
  }
}

extension Collection {
  func splitFirst() -> (Element, SubSequence)? {
    guard let first else { return nil }
    let rest = self.dropFirst()
    return (first, rest)
  }
}
