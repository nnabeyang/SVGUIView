import Foundation
import _CShims

struct SVGAttributeScanner {
  var reader: BufferReader

  init(bytes: BufferView<UInt8>) {
    reader = BufferReader(bytes: bytes)
  }

  mutating func consume(ascii: UInt8) -> Bool {
    guard let ch = reader.consumeWhitespace(),
      ch == ascii
    else { return false }
    reader.advance()
    return true
  }

  /// The name at the reader, or `nil` if the next character can't be in a name.
  mutating func scanIdentity() -> String? {
    guard reader.peek().isName else { return nil }
    return consumeName()
  }

  mutating func consumeName() -> String {
    let ch = reader.peek()
    precondition(ch.isName)
    let start = reader.readIndex
    var size = 0
    while true {
      let c = reader.peek(offset: size)
      guard c > 0 else {
        reader.moveReaderIndex(forwardBy: size)
        let end = reader.readIndex
        return String(decoding: reader.bytes[start..<end], as: UTF8.self)
      }
      if c.isName {
        size += 1
        continue
      }
      reader.moveReaderIndex(forwardBy: size)
      let end = reader.readIndex
      return String(decoding: reader.bytes[start..<end], as: UTF8.self)
    }
  }

  /// The string in quotes at the reader. A string without the closing quote ends at the end of the value, as in
  /// CSS.
  mutating func consumeString() -> String {
    let endingCodePoint = reader.peek()
    precondition(endingCodePoint == UInt8(ascii: "'") || endingCodePoint == UInt8(ascii: "\""))
    _ = reader.read()
    let start = reader.readIndex
    var size = 0
    while case let c = reader.peek(offset: size), c > 0, c != endingCodePoint {
      size += 1
    }
    reader.moveReaderIndex(forwardBy: size)
    let end = reader.readIndex
    if !reader.isEOF {
      reader.advance()
    }
    return String(decoding: reader.bytes[start..<end], as: UTF8.self)
  }

  mutating func scanNumber() -> Double? {
    let ch = reader.peek()
    guard ch > 0 else { return nil }
    switch ch {
    case asciiNumbers, UInt8(ascii: "+"), UInt8(ascii: "-"), UInt8(ascii: "."):
      break
    default:
      return nil
    }
    let start = reader.readIndex
    reader.skipNumber()
    let end = reader.readIndex
    return Double(prevalidatedBuffer: reader.bytes[start..<end])
  }

  mutating func scanBool() -> Bool? {
    guard let ascii = reader.read() else { return nil }
    switch ascii {
    case UInt8(ascii: "0"): return false
    case UInt8(ascii: "1"): return true
    default:
      return nil
    }
  }

  @discardableResult
  mutating func consumeWhitespaceIfNext(_ ch: UInt8) -> UInt8? {
    let cc = reader.consumeWhitespace()
    if let cc = cc, cc == ch {
      reader.advance()
      return reader.consumeWhitespace()
    }
    return cc
  }
}

// for points attribute of polyline and polygon tags
extension SVGAttributeScanner {
  mutating func scanPoints() -> [CGPoint] {
    var points = [CGPoint]()
    while !reader.isEOF {
      consumeWhitespaceIfNext(UInt8(ascii: ","))
      guard let x = scanNumber() else { break }
      consumeWhitespaceIfNext(UInt8(ascii: ","))
      guard let y = scanNumber() else { break }
      points.append(CGPoint(x: x, y: y))
    }
    return points
  }
}

// for font attributes
extension SVGAttributeScanner {
  private static let familyNames = [
    "cursive",
    "fantasy",
    "monospace",
    "sans-serif",
    "serif",
    "standard",
  ]

  /// The families of a `font-family` value, or none if a character is neither in a name nor in quotes.
  mutating func scanFontFamilies() -> [String] {
    var families = [String]()
    guard reader.consumeWhitespace() != nil else { return families }
    while !reader.isEOF {
      let family: String
      let ch = reader.peek()
      if ch == UInt8(ascii: "\"") || ch == UInt8(ascii: "'") {
        family = consumeString()
      } else if let name = scanIdentity() {
        family = name
      } else {
        return []
      }
      let prefix = Self.familyNames.contains(family) ? "-webkit-" : ""
      families.append("\(prefix)\(family)")
      consumeWhitespaceIfNext(UInt8(ascii: ","))
    }
    return families
  }
}

// for stroke attribute
extension SVGAttributeScanner {
  mutating func scanDashes() -> [CGFloat] {
    var dashes = [CGFloat]()
    guard reader.consumeWhitespace() != nil else { return dashes }
    while !reader.isEOF {
      guard let r = scanNumber() else { return dashes }
      dashes.append(CGFloat(r))
      consumeWhitespaceIfNext(UInt8(ascii: ","))
    }
    return dashes
  }

  mutating func scanHex() -> String? {
    guard consume(ascii: UInt8(ascii: "#")) else { return nil }
    let start = reader.readIndex
    reader.skipHex()
    let end = reader.readIndex
    guard start != end else { return nil }
    return String(decoding: reader.bytes[start..<end], as: UTF8.self)
  }
}

// for fill/color attribute
extension SVGAttributeScanner {
  mutating func scanColorDimension() -> ColorDimension? {
    guard let value = scanNumber() else { return nil }
    if let ch = reader.consumeWhitespace(), ch == UInt8(ascii: "%") {
      reader.advance()
      return .percent(value)
    } else {
      return .absolute(value)
    }
  }

  /// A value of `fill` or `stroke`. A name that isn't a color paints black if anything follows it.
  mutating func scanPaint() -> Paint? {
    guard let ascii = reader.consumeWhitespace() else { return nil }
    if ascii == UInt8(ascii: "#") {
      guard let hex = scanHex(), let color = SVGHexColor(hex: hex) else { return nil }
      return .color(.hex(color))
    }

    guard let name = scanIdentity() else {
      return nil
    }
    guard let type = SVGFillType(rawValue: name.lowercased()) else {
      _ = reader.consumeWhitespace()
      guard reader.isEOF else { return .color(.named(SVGColorName(name: "black"))) }
      return name.lowercased() == "none" ? Paint.none : .color(.named(SVGColorName(name: name)))
    }
    switch type {
    case .current:
      return .currentColor
    case .inherit:
      return nil
    case .rgb, .rgba:
      return scanColor(type: type).map { .color($0) }
    case .url:
      guard consume(ascii: UInt8(ascii: "(")) else { return nil }
      consumeWhitespaceIfNext(UInt8(ascii: "#"))
      guard let id = scanIdentity() else { return nil }
      guard consume(ascii: UInt8(ascii: ")")) else { return nil }
      return .url(id)
    }
  }

  mutating func scanColor() -> SVGColor? {
    guard let ascii = reader.consumeWhitespace() else { return nil }
    if ascii == UInt8(ascii: "#") {
      guard let hex = scanHex() else { return nil }
      return SVGHexColor(hex: hex).flatMap({ .hex($0) })
    }

    guard let name = scanIdentity() else {
      return nil
    }
    guard let type = SVGFillType(rawValue: name) else {
      return .named(SVGColorName(name: name))
    }
    return scanColor(type: type)
  }

  private mutating func scanColor(type: SVGFillType) -> SVGColor? {
    switch type {
    case .rgb:
      guard consume(ascii: UInt8(ascii: "(")) else { return nil }
      _ = reader.consumeWhitespace()
      guard let r = scanColorDimension() else { return nil }
      consumeWhitespaceIfNext(UInt8(ascii: ","))
      guard let g = scanColorDimension() else { return nil }
      consumeWhitespaceIfNext(UInt8(ascii: ","))
      guard let b = scanColorDimension() else { return nil }
      guard consume(ascii: UInt8(ascii: ")")) else { return nil }
      return .rgb(SVGRGBColor(r: r, g: g, b: b))
    case .rgba:
      guard consume(ascii: UInt8(ascii: "(")) else { return nil }
      _ = reader.consumeWhitespace()
      guard let r = scanColorDimension() else { return nil }
      consumeWhitespaceIfNext(UInt8(ascii: ","))
      guard let g = scanColorDimension() else { return nil }
      consumeWhitespaceIfNext(UInt8(ascii: ","))
      guard let b = scanColorDimension() else { return nil }
      consumeWhitespaceIfNext(UInt8(ascii: ","))
      guard let a = scanNumber() else { return nil }
      guard consume(ascii: UInt8(ascii: ")")) else { return nil }
      return .rgba(SVGRGBAColor(r: r, g: g, b: b, a: a))
    case .url, .inherit, .current:
      return nil
    }
  }

  static func parseColor(description: String) -> SVGColor? {
    var data = description
    return data.withUTF8 {
      let bytes = BufferView(unsafeBufferPointer: $0)!
      var scanner = SVGAttributeScanner(bytes: bytes)
      return scanner.scanColor()
    }
  }
}

extension SVGAttributeScanner {
  mutating func scanStdDeviation() -> StdDeviation? {
    _ = reader.consumeWhitespace()
    guard let x = scanNumber() else { return nil }
    _ = reader.consumeWhitespace()
    guard let y = scanNumber() else { return .iso(SVGLength(value: x, unit: .number)) }
    _ = reader.consumeWhitespace()
    if reader.isEOF {
      return .hetero(
        x: SVGLength(value: x, unit: .number),
        y: SVGLength(value: y, unit: .number))
    }
    return nil
  }
}

// for preserveAspectRatio attribute
extension SVGAttributeScanner {
  mutating func scanPreserveAspectRatio() -> PreserveAspectRatio? {
    _ = reader.consumeWhitespace()
    if reader.isEOF { return nil }
    guard let alignValue = scanIdentity(),
      let type = PreserveAspectRatio.AlignType(rawValue: alignValue)
    else {
      return nil
    }
    _ = reader.consumeWhitespace()
    let option: PreserveAspectRatio.Option = {
      guard !reader.isEOF,
        let optionValue = scanIdentity()
      else {
        return .meet
      }
      return PreserveAspectRatio.Option(rawValue: optionValue) ?? .meet
    }()
    switch type {
    case .xMinYMin:
      return .normal(x: .min, y: .min, option: option)
    case .xMidYMin:
      return .normal(x: .mid, y: .min, option: option)
    case .xMaxYMin:
      return .normal(x: .max, y: .min, option: option)
    case .xMinYMid:
      return .normal(x: .min, y: .mid, option: option)
    case .xMidYMid:
      return .normal(x: .mid, y: .mid, option: option)
    case .xMaxYMid:
      return .normal(x: .max, y: .mid, option: option)
    case .xMinYMax:
      return .normal(x: .min, y: .max, option: option)
    case .xMidYMax:
      return .normal(x: .mid, y: .max, option: option)
    case .xMaxYMax:
      return .normal(x: .max, y: .max, option: option)
    case .none:
      return PreserveAspectRatio.none
    }
  }
}

extension SVGAttributeScanner {
  mutating func scanClipPath() -> SVGClipPath? {
    guard let name = scanIdentity() else {
      return nil
    }
    guard let type = SVGClipPathType(rawValue: name.lowercased()) else {
      return nil
    }
    switch type {
    case .none:
      return SVGClipPath.none
    case .url:
      guard consume(ascii: UInt8(ascii: "(")) else { return nil }
      consumeWhitespaceIfNext(UInt8(ascii: "#"))
      guard let id = scanIdentity() else { return nil }
      guard consume(ascii: UInt8(ascii: ")")) else { return nil }
      return .url(url: id)
    }
  }
}

extension SVGAttributeScanner {
  mutating func scanMask() -> SVGMask? {
    guard let name = scanIdentity() else {
      return nil
    }
    guard let type = SVGClipPathType(rawValue: name.lowercased()) else {
      return nil
    }
    switch type {
    case .none:
      return SVGMask.none
    case .url:
      guard consume(ascii: UInt8(ascii: "(")) else { return nil }
      consumeWhitespaceIfNext(UInt8(ascii: "#"))
      guard let id = scanIdentity() else { return nil }
      guard consume(ascii: UInt8(ascii: ")")) else { return nil }
      return .url(url: id)
    }
  }
}

extension SVGAttributeScanner {
  mutating func scanFilter() -> SVGFilter? {
    guard let name = scanIdentity() else {
      return nil
    }
    guard let type = SVGFilterType(rawValue: name.lowercased()) else {
      return nil
    }
    switch type {
    case .none:
      return SVGFilter.none
    case .url:
      guard consume(ascii: UInt8(ascii: "(")) else { return nil }
      consumeWhitespaceIfNext(UInt8(ascii: "#"))
      guard let id = scanIdentity() else { return nil }
      guard consume(ascii: UInt8(ascii: ")")) else { return nil }
      return .url(url: id)
    }
  }
}

// for svg length
extension SVGAttributeScanner {
  mutating func scanLengthType() -> SVGLengthType {
    if reader.isEOF {
      return .number
    }
    guard let first = reader.read() else { return .unknown }
    if reader.isEOF {
      switch first {
      case UInt8(ascii: "%"):
        return .percentage
      case UInt8(ascii: "Q"):
        return .q
      default:
        return .unknown
      }
    }
    guard let second = reader.read() else { return .unknown }
    if reader.isEOF {
      switch (first, second) {
      case (UInt8(ascii: "e"), UInt8(ascii: "m")):
        return .ems
      case (UInt8(ascii: "e"), UInt8(ascii: "x")):
        return .exs
      case (UInt8(ascii: "p"), UInt8(ascii: "x")):
        return .pixels
      case (UInt8(ascii: "c"), UInt8(ascii: "m")):
        return .centimeters
      case (UInt8(ascii: "m"), UInt8(ascii: "m")):
        return .millimeters
      case (UInt8(ascii: "i"), UInt8(ascii: "n")):
        return .inches
      case (UInt8(ascii: "p"), UInt8(ascii: "t")):
        return .points
      case (UInt8(ascii: "p"), UInt8(ascii: "c")):
        return .picas
      case (UInt8(ascii: "c"), UInt8(ascii: "h")):
        return .chs
      case (UInt8(ascii: "i"), UInt8(ascii: "c")):
        return .ic
      case (UInt8(ascii: "l"), UInt8(ascii: "h")):
        return .lhs
      case (UInt8(ascii: "v"), UInt8(ascii: "w")):
        return .vw
      case (UInt8(ascii: "v"), UInt8(ascii: "h")):
        return .vh
      case (UInt8(ascii: "v"), UInt8(ascii: "i")):
        return .vi
      case (UInt8(ascii: "v"), UInt8(ascii: "b")):
        return .vb
      default:
        return .unknown
      }
    }
    guard let third = reader.read() else { return .unknown }
    if reader.isEOF {
      switch (first, second, third) {
      case (UInt8(ascii: "r"), UInt8(ascii: "e"), UInt8(ascii: "m")):
        return .rems
      case (UInt8(ascii: "r"), UInt8(ascii: "l"), UInt8(ascii: "h")):
        return .rlhs
      default:
        return .unknown
      }
    }
    guard let fourth = reader.read() else { return .unknown }
    guard reader.isEOF else { return .unknown }
    switch (first, second, third, fourth) {
    case (UInt8(ascii: "v"), UInt8(ascii: "m"), UInt8(ascii: "a"), UInt8(ascii: "x")):
      return .vmax
    case (UInt8(ascii: "v"), UInt8(ascii: "m"), UInt8(ascii: "i"), UInt8(ascii: "n")):
      return .vmin
    default:
      return .unknown
    }
  }
}

extension Double {
  init?(prevalidatedBuffer buffer: BufferView<UInt8>) {
    let value = buffer.withUnsafePointer { nptr, count -> Double? in
      var endPtr: UnsafeMutablePointer<CChar>?
      let decodedValue = strtod_l(nptr, &endPtr, nil)
      if let endPtr, nptr.advanced(by: count) == endPtr {
        return decodedValue
      } else {
        return nil
      }
    }
    guard let value = value else {
      return nil
    }
    self = value
  }
}

extension UInt64 {
  init?(prevalidatedBuffer buffer: BufferView<UInt8>) {
    let value = buffer.withUnsafePointer { nptr, count -> UInt64? in
      var endPtr: UnsafeMutablePointer<CChar>?

      let decodedValue = strtoull_l(nptr, &endPtr, 16, nil)
      if let endPtr, nptr.advanced(by: count) == endPtr {
        return decodedValue
      } else {
        return nil
      }
    }
    guard let value = value else {
      return nil
    }
    self = value
  }
}

private var asciiNumbers: ClosedRange<UInt8> { UInt8(ascii: "0")...UInt8(ascii: "9") }
