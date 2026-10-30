import CoreGraphics
import Foundation

package enum SpreadMethod: String, Sendable {
  case pad
  case `repeat`
  case reflect
}

protocol SVGGradientServer: SVGElement {
  var parentId: String? { get }
  var parentIds: [String] { get }
  var id: String? { get }
  var children: [any SVGElement] { get }
  func merged(other: any SVGGradientServer) -> any SVGGradientServer
  func paint(context: any SVGLengthContext, opacity: Double) -> GradientPaint?
  func stops(context: any SVGLengthContext) -> [SVGStopElement]
  var gradientTransform: TransformList? { get }
  init(lhs: Self, rhs: SVGLinearGradientServer)
  init(lhs: Self, rhs: SVGRadialGradientServer)
}

extension SVGGradientServer {
  func merged(other: any SVGGradientServer) -> any SVGGradientServer {
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

  /// The colors of the stops at their locations, or `nil` if no stop has a color, which paints none.
  ///
  /// An offset is clamped to 0...1 and to the offset of the stop before it, and a single stop paints its color
  /// everywhere.
  func colorStops(context: any SVGLengthContext, opacity: Double) -> (colors: [CGColor], locations: [CGFloat])? {
    var colors = [CGColor]()
    var locations = [CGFloat]()
    for stop in stops(context: context) {
      guard let color = stop.color.toCGColor(opacity: stop.opacity * opacity) else { continue }
      colors.append(color)
      locations.append(max(min(stop.offset.value, 1), locations.last ?? 0))
    }
    guard let color = colors.first else { return nil }
    return colors.count == 1 ? ([color, color], [0, 1]) : (colors, locations)
  }

  /// The transform from the coordinates of the gradient to the coordinates of its units.
  func transform(context: any SVGLengthContext) -> CGAffineTransform {
    gradientTransform?.matrix(box: context.viewBoxSize, context: context) ?? .identity
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
  let children: [any SVGElement]
  let id: String?
  let parentId: String?
  let gradientUnits: SVGUnitType?
  let gradientTransform: TransformList?
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

    x1 = SVGLength(attributes["x1"])
    y1 = SVGLength(attributes["y1"])
    x2 = SVGLength(attributes["x2"])
    y2 = SVGLength(attributes["y2"])

    parentId = Self.parseLink(description: attributes["href"])
    gradientUnits = SVGUnitType(rawValue: attributes["gradientUnits", default: ""])
    gradientTransform = TransformList(attribute: attributes["gradientTransform", default: ""])
    spreadMethod = Self.parseSpreadMethod(attributes["spreadMethod", default: ""])

    if let parentId = parentId {
      parentIds = [parentId]
    } else {
      parentIds = []
    }
  }

  init(lhs: SVGLinearGradientServer, rhs: SVGLinearGradientServer) {
    parentIds = lhs.parentIds
    id = lhs.id
    self.base = lhs.base
    x1 = lhs.x1 ?? rhs.x1
    y1 = lhs.y1 ?? rhs.y1
    x2 = lhs.x2 ?? rhs.x2
    y2 = lhs.y2 ?? rhs.y2
    children = lhs.children.isEmpty ? rhs.children : lhs.children
    parentId = rhs.parentId
    gradientUnits = lhs.gradientUnits ?? rhs.gradientUnits
    gradientTransform = lhs.gradientTransform ?? rhs.gradientTransform
    spreadMethod = lhs.spreadMethod ?? rhs.spreadMethod
  }

  init(lhs: SVGLinearGradientServer, rhs: SVGRadialGradientServer) {
    parentIds = lhs.parentIds
    id = lhs.id
    base = lhs.base
    x1 = lhs.x1
    y1 = lhs.y1
    x2 = lhs.x2
    y2 = lhs.y2
    children = lhs.children.isEmpty ? rhs.children : lhs.children
    parentId = rhs.parentId
    gradientUnits = lhs.gradientUnits ?? rhs.gradientUnits
    gradientTransform = lhs.gradientTransform ?? rhs.gradientTransform
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

  /// The gradient with its lengths resolved, or `nil` if it has no stop with a color.
  func paint(context: any SVGLengthContext, opacity: Double) -> GradientPaint? {
    let gradientUnits = gradientUnits ?? .objectBoundingBox
    let x1 = (x1 ?? .percent(0)).value(context: context, mode: .width, unitType: gradientUnits)
    let y1 = (y1 ?? .percent(0)).value(context: context, mode: .height, unitType: gradientUnits)
    let x2 = (x2 ?? .percent(100)).value(context: context, mode: .width, unitType: gradientUnits)
    let y2 = (y2 ?? .percent(0)).value(context: context, mode: .height, unitType: gradientUnits)
    guard let (colors, locations) = colorStops(context: context, opacity: opacity) else { return nil }
    return .linear(
      LinearGradientPaint(
        units: gradientUnits, transform: transform(context: context), x1: x1, y1: y1, x2: x2, y2: y2,
        spreadMethod: spreadMethod ?? .pad, colors: colors, locations: locations))
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
  let children: [any SVGElement]
  let spreadMethod: SpreadMethod?
  let gradientUnits: SVGUnitType?
  let gradientTransform: TransformList?

  let id: String?
  let parentId: String?
  let parentIds: [String]

  let cx: SVGLength?
  let cy: SVGLength?
  let fx: SVGLength?
  let fy: SVGLength?
  /// The radius of the focal circle, which is a point without it.
  let fr: SVGLength?
  let r: SVGLength?

  private enum CodingKeys: String, CodingKey {
    case stops
  }

  init(base: SVGBaseElement, contents children: [any SVGElement]) {
    self.base = base
    self.children = children
    let attributes = base.attributes
    id = attributes["id"]?.trimmingCharacters(in: .whitespaces)
    cx = SVGLength(attributes["cx"])
    cy = SVGLength(attributes["cy"])
    fx = SVGLength(attributes["fx"])
    fy = SVGLength(attributes["fy"])
    fr = SVGLength(attributes["fr"])
    r = SVGLength(attributes["r"])
    spreadMethod = Self.parseSpreadMethod(attributes["spreadMethod", default: ""])
    parentId = Self.parseLink(description: attributes["href"])
    gradientUnits = SVGUnitType(rawValue: attributes["gradientUnits", default: ""])
    gradientTransform = TransformList(attribute: attributes["gradientTransform", default: ""])

    if let parentId = parentId {
      parentIds = [parentId]
    } else {
      parentIds = []
    }
  }

  init(lhs: SVGRadialGradientServer, rhs: SVGRadialGradientServer) {
    parentIds = lhs.parentIds
    id = lhs.id
    base = lhs.base
    cx = lhs.cx ?? rhs.cx
    cy = lhs.cy ?? rhs.cy
    fx = lhs.fx ?? rhs.fx
    fy = lhs.fy ?? rhs.fy
    fr = lhs.fr ?? rhs.fr
    r = lhs.r ?? rhs.r
    children = lhs.children.isEmpty ? rhs.children : lhs.children
    spreadMethod = lhs.spreadMethod ?? rhs.spreadMethod
    parentId = rhs.parentId
    gradientUnits = lhs.gradientUnits ?? rhs.gradientUnits
    gradientTransform = lhs.gradientTransform ?? rhs.gradientTransform
  }

  init(lhs: SVGRadialGradientServer, rhs: SVGLinearGradientServer) {
    parentIds = lhs.parentIds
    id = lhs.id
    base = lhs.base
    cx = lhs.cx
    cy = lhs.cy
    fx = lhs.fx
    fy = lhs.fy
    fr = lhs.fr
    r = lhs.r
    children = lhs.children.isEmpty ? rhs.children : lhs.children
    spreadMethod = lhs.spreadMethod ?? rhs.spreadMethod
    parentId = rhs.parentId
    gradientUnits = lhs.gradientUnits ?? rhs.gradientUnits
    gradientTransform = lhs.gradientTransform ?? rhs.gradientTransform
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

  /// The gradient with its lengths resolved, or `nil` if it has no stop with a color.
  func paint(context: any SVGLengthContext, opacity: Double) -> GradientPaint? {
    let gradientUnits = gradientUnits ?? .objectBoundingBox
    let cx = (cx ?? .percent(50)).value(context: context, mode: .width, unitType: gradientUnits)
    let cy = (cy ?? .percent(50)).value(context: context, mode: .height, unitType: gradientUnits)
    let r = (r ?? .percent(50)).value(context: context, mode: .other, unitType: gradientUnits)
    // The focal point is the center unless it's given.
    let fx = fx?.value(context: context, mode: .width, unitType: gradientUnits) ?? cx
    let fy = fy?.value(context: context, mode: .height, unitType: gradientUnits) ?? cy
    // A negative radius of the focal circle is an error, which leaves the circle a point.
    let fr = max((fr ?? .percent(0)).value(context: context, mode: .other, unitType: gradientUnits), 0)
    guard let (colors, locations) = colorStops(context: context, opacity: opacity) else { return nil }
    return .radial(
      RadialGradientPaint(
        units: gradientUnits, transform: transform(context: context), cx: cx, cy: cy, r: r, fx: fx, fy: fy, fr: fr,
        spreadMethod: spreadMethod ?? .pad, colors: colors, locations: locations))
  }
}

extension SVGRadialGradientServer {
  func encode(to encoder: any Encoder) throws {
    fatalError()
  }
}
