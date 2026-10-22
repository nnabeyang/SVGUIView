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
  let patternTransform: CGAffineTransform?
  let preserveAspectRatio: PreserveAspectRatio?
  let viewBox: SVGElementRect?
  let parentId: String?

  static var type: SVGElementName {
    .pattern
  }

  var type: SVGElementName {
    .pattern
  }

  var transform: CGAffineTransform {
    .identity
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

    patternTransform = CGAffineTransform(description: attributes["patternTransform", default: ""])
    patternUnits = SVGUnitType(rawValue: attributes["patternUnits", default: ""])
    patternContentUnits = SVGUnitType(rawValue: attributes["patternContentUnits", default: ""])
    preserveAspectRatio = PreserveAspectRatio(description: attributes["preserveAspectRatio", default: ""])
    viewBox = Self.parseViewBox(attributes["viewBox"])
    parentId = Self.parseLink(description: attributes["href"])
  }

  init(lhs: SVGPatternElement, rhs: SVGPatternElement) {
    base = rhs.base
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
    if !rhs.children.isEmpty {
      children = rhs.children
    } else {
      children = lhs.children
    }
  }

  static func parseViewBox(_ value: String?) -> SVGElementRect? {
    guard let value = value?.trimmingCharacters(in: .whitespaces) else { return nil }
    let nums = value.components(separatedBy: .whitespaces)
    if nums.count == 4,
      let x = Double(nums[0]),
      let y = Double(nums[1]),
      let width = Double(nums[2]),
      let height = Double(nums[3])
    {
      return SVGElementRect(x: x, y: y, width: width, height: height)
    }
    return nil
  }

  private static func parseLink(description: String?) -> String? {
    guard let description = description else { return nil }
    let hashId = description.trimmingCharacters(in: .whitespaces)
    if hashId.hasPrefix("#") {
      return String(hashId.dropFirst())
    }
    return nil
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

extension SVGPatternElement: Encodable {
  private enum CodingKeys: String, CodingKey {
    case d
    case fill
  }

  func encode(to _: any Encoder) throws {
    fatalError()
  }
}
