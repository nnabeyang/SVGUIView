import CoreGraphics
import Foundation

enum SVGOverflow: String, CaseIterable {
  case visible
  case hidden
  case scroll
  case auto
}

private struct SVGLengthContextProxy: SVGLengthContext {
  let context: any SVGLengthContext
  let size: CGSize
  var viewBoxSize: CGSize { size }
  var viewPort: CGRect { context.viewPort }
  var font: SVGUIFont? { context.font }
  var rootFont: SVGUIFont? { context.rootFont }
  var writingMode: WritingMode? { context.writingMode }
  var textScale: Double { 1.0 }
}

package final class SVGSVGElement: SVGDrawableElement, SVGLengthContext {
  static var type: SVGElementName {
    .svg
  }

  var type: SVGElementName {
    .svg
  }

  let base: SVGBaseElement
  let preserveAspectRatio: PreserveAspectRatio?
  let overflow: SVGOverflow?
  let x: SVGLength?
  let y: SVGLength?
  let width: SVGLength?
  let height: SVGLength?
  let viewBox: SVGElementRect?
  let children: [any SVGElement]

  var textScale: Double { 1.0 }

  private enum CodingKeys: String, CodingKey {
    case width
    case height
    case viewBox
  }

  init(base: SVGBaseElement, contents children: [any SVGElement]) {
    self.base = base
    self.children = children
    let attributes = base.attributes
    x = SVGLength(attributes["x"])
    y = SVGLength(attributes["y"])
    width = SVGLength(attributes["width"])
    height = SVGLength(attributes["height"])
    viewBox = Self.parseViewBox(attributes["viewBox"])
    preserveAspectRatio = PreserveAspectRatio(description: attributes["preserveAspectRatio", default: ""])
    overflow = base.style.overflow
  }

  init(base _: SVGBaseElement, text _: String, attributes _: [String: String]) {
    fatalError()
  }

  private init(other: SVGSVGElement, width: SVGLength?, height: SVGLength?) {
    base = other.base
    x = other.x
    y = other.y
    self.width = width ?? other.width
    self.height = height ?? other.height
    viewBox = other.viewBox
    children = other.children
    preserveAspectRatio = other.preserveAspectRatio
    overflow = other.overflow
  }

  /// The element with the width and height of the `<use>` element that shows it, where that element has them.
  func sized(width: SVGLength?, height: SVGLength?) -> SVGSVGElement {
    SVGSVGElement(other: self, width: width, height: height)
  }

  var viewPort: CGRect {
    fatalError("not implemented")
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

  var viewBoxSize: CGSize { viewBox?.toCGRect().size ?? .zero }
  var font: SVGUIFont? { style.font }
  var rootFont: SVGUIFont? { style.font }
  var writingMode: WritingMode? { style.writingMode }

  func contains(index: ObjectIdentifier) -> Bool {
    children.contains(where: { $0.index == index })
  }

  func clip(context: inout SVGBaseContext) {
    for child in children {
      child.clip(context: &context)
    }
  }

  func mask(context: inout SVGBaseContext) {
    for child in children {
      child.mask(context: &context)
    }
  }

  func pattern(context: inout SVGBaseContext) {
    for child in children {
      child.pattern(context: &context)
    }
  }

  func filter(context: inout SVGBaseContext) {
    for child in children {
      child.filter(context: &context)
    }
  }

  package var size: CGSize {
    let width = width ?? .percent(100)
    let height = height ?? .percent(100)
    return CGSize(
      width: width.value(context: self, mode: .width),
      height: height.value(context: self, mode: .height))
  }

}

extension SVGSVGElement {
  package func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: Self.CodingKeys.self)
    try container.encode(width, forKey: .width)
    try container.encode(height, forKey: .height)
    try container.encodeIfPresent(viewBox, forKey: .viewBox)
  }
}

extension SVGSVGElement {
  func getViewBox(size: CGSize) -> CGRect {
    if let viewBox = viewBox {
      return viewBox.toCGRect()
    }
    let context = SVGLengthContextProxy(context: self, size: size)
    let width = width ?? .percent(100)
    let height = height ?? .percent(100)

    return CGRect(
      x: 0,
      y: 0,
      width: width.value(context: context, mode: .width),
      height: height.value(context: context, mode: .height))
  }

  func getTransform(viewBox: CGRect, size: CGSize) -> CGAffineTransform {
    let preserveAspectRatio = preserveAspectRatio ?? PreserveAspectRatio()
    return preserveAspectRatio.getTransform(viewBox: viewBox, size: size)
  }
}
