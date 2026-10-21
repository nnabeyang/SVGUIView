import CoreGraphics
import Foundation

private enum LineCapType: String {
  case butt
  case round
  case square
  case inherit
}

private enum JoinType: String {
  case miter
  case round
  case bevel
}

struct SVGUIStroke {
  let fill: SVGFill?
  let opacity: CGFloat?
  let width: SVGLength?
  let cap: CGLineCap?
  let join: CGLineJoin?
  let miterLimit: CGFloat?
  let dashes: [CGFloat]?
  let offset: CGFloat?

  init(attributes: [String: String]) {
    fill = SVGFill(description: attributes["stroke", default: ""])
    opacity = Self.parseNumber(description: attributes["stroke-opacity", default: ""])
    width = SVGLength(attributes["stroke-width"])
    cap = Self.getCap(attribute: attributes["stroke-linecap", default: ""])
    join = Self.getStrokeJoin(attribute: attributes["stroke-linejoin", default: ""])
    miterLimit = Self.parseNumber(description: attributes["stroke-miterlimit", default: ""])
    dashes = Self.parseDashes(description: attributes["stroke-dasharray", default: ""])
    offset = Self.parseNumber(description: attributes["stroke-dashoffset", default: ""])
  }

  /// The stroke with the cascaded values of the `stroke` properties.
  init(cascaded: CascadedValues) {
    fill = SVGFill(paint: cascaded[StrokeProperty.self], opacity: nil)
    opacity = cascaded.declared(StrokeOpacityProperty.self).map { CGFloat($0) }
    width = cascaded.declared(StrokeWidthProperty.self)
    cap = cascaded.declared(StrokeLinecapProperty.self)
    join = cascaded.declared(StrokeLinejoinProperty.self)
    miterLimit = cascaded.declared(StrokeMiterlimitProperty.self).map { CGFloat($0) }
    dashes = cascaded.declared(StrokeDasharrayProperty.self).flatMap { $0.isEmpty ? nil : $0 }
    offset = cascaded.declared(StrokeDashoffsetProperty.self)
  }

  init(lhs: SVGUIStroke, rhs: SVGUIStroke?) {
    guard let rhs = rhs else {
      self = lhs
      return
    }
    fill = lhs.fill ?? rhs.fill
    opacity = lhs.opacity ?? rhs.opacity
    width = lhs.width ?? rhs.width
    cap = lhs.cap ?? rhs.cap
    join = lhs.join ?? rhs.join
    miterLimit = lhs.miterLimit ?? rhs.miterLimit
    dashes = lhs.dashes ?? rhs.dashes
    offset = lhs.offset ?? rhs.offset
  }

  private static func getCap(attribute: String) -> CGLineCap? {
    guard let type = LineCapType(rawValue: attribute.trimmingCharacters(in: .whitespaces)) else {
      return nil
    }
    switch type {
    case .butt:
      return .butt
    case .round:
      return .round
    case .square:
      return .square
    case .inherit:
      return .butt
    }
  }

  private static func getStrokeJoin(attribute: String) -> CGLineJoin? {
    guard let type = JoinType(rawValue: attribute.trimmingCharacters(in: .whitespaces)) else {
      return nil
    }
    switch type {
    case .miter:
      return .miter
    case .round:
      return .round
    case .bevel:
      return .bevel
    }
  }

  private static func parseDashes(description: String) -> [CGFloat]? {
    var data = description
    let dashes = data.withUTF8 {
      let bytes = BufferView(unsafeBufferPointer: $0)!
      var scanner = SVGAttributeScanner(bytes: bytes)
      return scanner.scanDashes()
    }
    return dashes.isEmpty ? nil : dashes
  }

  private static func parseNumber(description: String) -> CGFloat? {
    var data = description
    return data.withUTF8 {
      let bytes = BufferView(unsafeBufferPointer: $0)!
      var scanner = SVGAttributeScanner(bytes: bytes)
      return scanner.scanNumber().flatMap { CGFloat($0) }
    }
  }
}
