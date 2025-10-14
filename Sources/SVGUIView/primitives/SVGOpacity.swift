import Foundation

enum SVGOpacity: Equatable, Encodable {
  case number(CGFloat)
  case percent(CGFloat)

  init(value: Double, unit: CSSUnitType) {
    switch unit {
    case .percentage:
      self = .percent(value)
    default:
      self = .number(value)
    }
  }

  init?(_ description: String?) {
    guard var data = description?.trimmingCharacters(in: .whitespaces) else {
      return nil
    }
    let v: SVGOpacity? = data.withUTF8 {
      let bytes = BufferView(unsafeBufferPointer: $0)!
      var scanner = SVGAttributeScanner(bytes: bytes)
      guard let value = scanner.scanNumber() else { return nil }
      let lengthType = scanner.scanLengthType()
      switch lengthType {
      case .percentage:
        return .percent(value)
      case .number:
        return .number(value)
      default:
        return nil
      }
    }

    if let v = v {
      self = v
      return
    }
    return nil
  }

  var value: CGFloat {
    switch self {
    case .number(let v):
      return v
    case .percent(let v):
      return v / 100
    }
  }
}
