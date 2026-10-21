import CoreGraphics
import Foundation

enum SpreadMethod: String {
  case pad
  case `repeat`
  case reflect
}

protocol SVGGradientServer: SVGElement {
  var parentId: String? { get }
  var parentIds: [String] { get }
  var id: String? { get }
  var display: CSSDisplay? { get }
  var children: [any SVGElement] { get }
  func merged(other: any SVGGradientServer) -> (any SVGGradientServer)?
  func draw(path: CGPath, context: SVGContext, opacity: Double)
  func paint(context: any SVGLengthContext, opacity: Double) -> GradientPaint?
  func stops(context: any SVGLengthContext) -> [SVGStopElement]
  init?(lhs: Self, rhs: SVGLinearGradientServer)
  init?(lhs: Self, rhs: SVGRadialGradientServer)
}

extension SVGGradientServer {
  func merged(other: any SVGGradientServer) -> (any SVGGradientServer)? {
    switch other {
    case let other as SVGLinearGradientServer:
      return Self(lhs: self, rhs: other)
    case let other as SVGRadialGradientServer:
      return Self(lhs: self, rhs: other)
    default:
      fatalError("not implemented")
    }
  }

  func stops(context _: any SVGLengthContext) -> [SVGStopElement] {
    children.compactMap { $0 as? SVGStopElement }
  }

}

final class SVGLinearGradientServer: SVGGradientServer {
  static var type: SVGElementName {
    .linearGradient
  }

  var type: SVGElementName {
    .linearGradient
  }

  let base: SVGBaseElement
  let display: CSSDisplay?
  let children: [any SVGElement]
  let id: String?
  let parentId: String?
  let gradientUnits: SVGUnitType?
  let spreadMethod: SpreadMethod?
  let x1: SVGLength?
  let y1: SVGLength?
  let x2: SVGLength?
  let y2: SVGLength?

  let parentIds: [String]

  private enum CodingKeys: String, CodingKey {
    case stops
  }

  init(base: SVGBaseElement, contents children: [any SVGElement]) {
    self.base = base
    self.children = children
    let attributes = base.attributes
    id = attributes["id"]?.trimmingCharacters(in: .whitespaces)
    display = base.cascaded.declared(DisplayProperty.self)

    x1 = SVGLength(attributes["x1"])
    y1 = SVGLength(attributes["y1"])
    x2 = SVGLength(attributes["x2"])
    y2 = SVGLength(attributes["y2"])

    parentId = Self.parseLink(description: attributes["href"])
    gradientUnits = SVGUnitType(rawValue: attributes["gradientUnits", default: ""])
    spreadMethod = Self.parseSpreadMethod(attributes["spreadMethod", default: ""])

    if let parentId = parentId {
      parentIds = [parentId]
    } else {
      parentIds = []
    }
  }

  init?(lhs: SVGLinearGradientServer, rhs: SVGLinearGradientServer) {
    if let id = lhs.id {
      guard !rhs.parentIds.contains(id) else { return nil }
      parentIds = lhs.parentIds + rhs.parentIds
    } else {
      parentIds = lhs.parentIds
    }
    id = lhs.id
    self.base = lhs.base
    display = lhs.display ?? rhs.display
    x1 = lhs.x1 ?? rhs.x1
    y1 = lhs.y1 ?? rhs.y1
    x2 = lhs.x2 ?? rhs.x2
    y2 = lhs.y2 ?? rhs.y2
    children = lhs.children.isEmpty ? rhs.children : lhs.children
    parentId = rhs.parentId
    gradientUnits = lhs.gradientUnits ?? rhs.gradientUnits
    spreadMethod = lhs.spreadMethod ?? rhs.spreadMethod
  }

  init?(lhs: SVGLinearGradientServer, rhs: SVGRadialGradientServer) {
    if let id = lhs.id {
      guard !lhs.parentIds.contains(id) else { return nil }
      parentIds = lhs.parentIds + rhs.parentIds
    } else {
      parentIds = lhs.parentIds
    }
    id = lhs.id
    base = lhs.base
    display = lhs.display ?? rhs.display
    x1 = lhs.x1
    y1 = lhs.y1
    x2 = lhs.x2
    y2 = lhs.y2
    children = lhs.children.isEmpty ? rhs.children : lhs.children
    parentId = rhs.parentId
    gradientUnits = lhs.gradientUnits ?? rhs.gradientUnits
    spreadMethod = lhs.spreadMethod ?? rhs.spreadMethod
  }

  private static func parseLink(description: String?) -> String? {
    guard let description = description else { return nil }
    let hashId = description.trimmingCharacters(in: .whitespaces)
    if hashId.hasPrefix("#") {
      return String(hashId.dropFirst())
    }
    return nil
  }

  private static func parseSpreadMethod(_ src: String) -> SpreadMethod? {
    SpreadMethod(rawValue: src.trimmingCharacters(in: .whitespaces))
  }

  func draw(path: CGPath, context: SVGContext, opacity: Double) {
    paint(context: context, opacity: opacity)?.paint(path, in: context.graphics)
  }

  /// The gradient with its lengths resolved, or `nil` if it has no stop with a color.
  func paint(context: any SVGLengthContext, opacity: Double) -> GradientPaint? {
    let stops = stops(context: context)
    let gradientUnits = gradientUnits ?? .objectBoundingBox
    let x1 = (x1 ?? .percent(0)).value(context: context, mode: .width, unitType: gradientUnits)
    let y1 = (y1 ?? .percent(0)).value(context: context, mode: .height, unitType: gradientUnits)
    let x2 = (x2 ?? .percent(100)).value(context: context, mode: .width, unitType: gradientUnits)
    let y2 = (y2 ?? .percent(0)).value(context: context, mode: .height, unitType: gradientUnits)
    let colors = stops.compactMap { $0.color.toCGColor(opacity: $0.opacity * opacity) }
    guard !colors.isEmpty else { return nil }
    return .linear(
      LinearGradientPaint(
        units: gradientUnits, x1: x1, y1: y1, x2: x2, y2: y2, spreadMethod: spreadMethod ?? .pad, colors: colors,
        locations: stops.map(\.offset.value)))
  }
}

extension SVGLinearGradientServer {
  func encode(to encoder: any Encoder) throws {
    fatalError()
  }
}

final class SVGRadialGradientServer: SVGGradientServer {
  static var type: SVGElementName {
    .radialGradient
  }

  var type: SVGElementName {
    .radialGradient
  }

  let base: SVGBaseElement
  let display: CSSDisplay?
  let children: [any SVGElement]
  let spreadMethod: SpreadMethod?
  let gradientUnits: SVGUnitType?

  let id: String?
  let parentId: String?
  let parentIds: [String]

  let cx: SVGLength?
  let cy: SVGLength?
  let fx: SVGLength?
  let fy: SVGLength?
  let r: SVGLength?

  private enum CodingKeys: String, CodingKey {
    case stops
  }

  init(base: SVGBaseElement, contents children: [any SVGElement]) {
    self.base = base
    self.children = children
    let attributes = base.attributes
    id = attributes["id"]?.trimmingCharacters(in: .whitespaces)
    display = base.cascaded.declared(DisplayProperty.self)
    cx = SVGLength(attributes["cx"])
    cy = SVGLength(attributes["cy"])
    fx = SVGLength(attributes["fx"])
    fy = SVGLength(attributes["fy"])
    r = SVGLength(attributes["r"])
    spreadMethod = Self.parseSpreadMethod(attributes["spreadMethod", default: ""])
    parentId = Self.parseLink(description: attributes["href"])
    gradientUnits = SVGUnitType(rawValue: attributes["gradientUnits", default: ""])

    parentIds = []
  }

  init?(lhs: SVGRadialGradientServer, rhs: SVGRadialGradientServer) {
    if let id = rhs.id {
      guard !lhs.parentIds.contains(id) else { return nil }
      parentIds = lhs.parentIds + [id]
    } else {
      parentIds = lhs.parentIds
    }
    id = lhs.id
    base = lhs.base
    display = lhs.display ?? rhs.display
    cx = lhs.cx ?? rhs.cx
    cy = lhs.cy ?? rhs.cy
    fx = lhs.fx ?? rhs.fx
    fy = lhs.fy ?? rhs.fy
    r = lhs.r ?? rhs.r
    children = lhs.children.isEmpty ? rhs.children : lhs.children
    spreadMethod = lhs.spreadMethod ?? rhs.spreadMethod
    parentId = rhs.parentId
    gradientUnits = lhs.gradientUnits ?? rhs.gradientUnits
  }

  init?(lhs: SVGRadialGradientServer, rhs: SVGLinearGradientServer) {
    if let id = rhs.id {
      guard !lhs.parentIds.contains(id) else { return nil }
      parentIds = lhs.parentIds + [id]
    } else {
      parentIds = lhs.parentIds
    }
    id = lhs.id
    base = lhs.base
    display = lhs.display ?? rhs.display
    cx = lhs.cx
    cy = lhs.cy
    fx = lhs.fx
    fy = lhs.fy
    r = lhs.r
    children = lhs.children.isEmpty ? rhs.children : lhs.children
    spreadMethod = lhs.spreadMethod ?? rhs.spreadMethod
    parentId = rhs.parentId
    gradientUnits = lhs.gradientUnits ?? rhs.gradientUnits
  }

  private static func parseLink(description: String?) -> String? {
    guard let description = description else { return nil }
    let hashId = description.trimmingCharacters(in: .whitespaces)
    if hashId.hasPrefix("#") {
      return String(hashId.dropFirst())
    }
    return nil
  }

  private static func parseSpreadMethod(_ src: String) -> SpreadMethod? {
    SpreadMethod(rawValue: src.trimmingCharacters(in: .whitespaces))
  }

  func draw(path: CGPath, context: SVGContext, opacity: Double) {
    paint(context: context, opacity: opacity)?.paint(path, in: context.graphics)
  }

  /// The gradient with its lengths resolved, or `nil` if it has no stop with a color.
  func paint(context: any SVGLengthContext, opacity: Double) -> GradientPaint? {
    let stops = stops(context: context)
    let gradientUnits = gradientUnits ?? .objectBoundingBox
    let cx = (cx ?? .percent(50)).value(context: context, mode: .width, unitType: gradientUnits)
    let cy = (cy ?? .percent(50)).value(context: context, mode: .width, unitType: gradientUnits)
    let r = (r ?? .percent(50)).value(context: context, mode: .height, unitType: gradientUnits)
    let colors = stops.compactMap { $0.color.toCGColor(opacity: $0.opacity * opacity) }
    guard !colors.isEmpty else { return nil }
    return .radial(
      RadialGradientPaint(
        units: gradientUnits, cx: cx, cy: cy, r: r, colors: colors, locations: stops.map(\.offset.value)))
  }
}

extension SVGRadialGradientServer {
  func encode(to encoder: any Encoder) throws {
    fatalError()
  }
}
