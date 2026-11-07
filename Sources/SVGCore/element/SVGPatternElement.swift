import CoreGraphics
import Foundation

package enum SVGUnitType: String, Sendable {
  case userSpaceOnUse
  case objectBoundingBox
}

final class SVGPatternElement: SVGDrawableElement {
  let base: SVGBaseElement
  let colorInterpolation: SVGColorInterpolation?
  let x: SVGLength?
  let y: SVGLength?
  let width: SVGLength?
  let height: SVGLength?
  let patternContentUnits: SVGUnitType?
  let patternTransform: TransformList?
  let preserveAspectRatio: PreserveAspectRatio?
  let viewBox: SVGElementRect?
  let parentId: String?

  static var type: SVGElementName {
    .pattern
  }

  var type: SVGElementName {
    .pattern
  }

  let children: [any SVGElement]
  let patternUnits: SVGUnitType?

  init(base _: SVGBaseElement, text _: String, attributes _: [String: String]) {
    fatalError()
  }

  init(base: SVGBaseElement, contents children: [any SVGElement]) {
    self.base = base
    self.children = children
    let attributes = base.attributes
    colorInterpolation = base.style.colorInterpolation
    x = SVGLength(attributes["x"])
    y = SVGLength(attributes["y"])
    width = SVGLength(attributes["width"])
    height = SVGLength(attributes["height"])

    patternTransform = TransformList(attribute: attributes["patternTransform", default: ""])
    patternUnits = SVGUnitType(rawValue: attributes["patternUnits", default: ""])
    patternContentUnits = SVGUnitType(rawValue: attributes["patternContentUnits", default: ""])
    preserveAspectRatio = PreserveAspectRatio(description: attributes["preserveAspectRatio", default: ""])
    viewBox = Self.parseViewBox(attributes["viewBox"])
    parentId = fragmentID(of: attributes["href"])
  }

  /// The pattern `lhs` with the attributes and the children of the pattern `rhs` that it references where it has
  /// none of its own.
  init(lhs: SVGPatternElement, rhs: SVGPatternElement) {
    base = lhs.base
    colorInterpolation = lhs.colorInterpolation ?? rhs.colorInterpolation
    x = lhs.x ?? rhs.x
    y = lhs.y ?? rhs.y
    width = lhs.width ?? rhs.width
    height = lhs.height ?? rhs.height
    patternTransform = lhs.patternTransform ?? rhs.patternTransform
    patternUnits = lhs.patternUnits ?? rhs.patternUnits
    patternContentUnits = lhs.patternContentUnits ?? rhs.patternContentUnits
    preserveAspectRatio = lhs.preserveAspectRatio ?? rhs.preserveAspectRatio
    viewBox = lhs.viewBox ?? rhs.viewBox
    parentId = rhs.parentId
    children = lhs.knownChildren.isEmpty ? rhs.children : lhs.children
  }

  static func parseViewBox(_ value: String?) -> SVGElementRect? {
    SVGSVGElement.parseViewBox(value)
  }

  func size(frame: CGRect, context: any SVGLengthContext) -> CGSize {
    let patternUnits = patternUnits ?? .objectBoundingBox
    let width = width?.value(context: context, mode: .width, unitType: patternUnits) ?? 0
    let height = height?.value(context: context, mode: .height, unitType: patternUnits) ?? 0
    switch patternUnits {
    case .userSpaceOnUse:
      return CGSize(width: width, height: height)
    case .objectBoundingBox:
      return CGSize(width: width * frame.width, height: height * frame.height)
    }
  }

  func pattern(context: inout SVGBaseContext) {
    if let id = id, context.patterns[id] == nil {
      context.setPattern(id: id, value: self)
    }
  }

  func getTransform(viewBox: CGRect, size: CGSize) -> CGAffineTransform {
    let preserveAspectRatio = preserveAspectRatio ?? .init(xAlign: .mid, yAlign: .mid, option: .meet)
    return preserveAspectRatio.getTransform(viewBox: viewBox, size: size).translatedBy(x: viewBox.minX, y: viewBox.minY)
  }
}
