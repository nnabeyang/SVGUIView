import CoreGraphics
import Foundation

enum SVGOverflow: String, CaseIterable, Sendable {
  case visible
  case hidden
  case scroll
  case auto
}

private struct SVGLengthContextProxy: SVGLengthContext {
  let context: any SVGLengthContext
  let size: CGSize
  var viewBoxSize: CGSize { size }
  /// The viewport that the element is placed in, which viewport units such as `10vw` are relative to.
  var viewPort: CGRect { CGRect(origin: .zero, size: size) }
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
  let overflow: SVGOverflow
  let x: SVGLength?
  let y: SVGLength?
  let width: SVGLength?
  let height: SVGLength?
  let viewBox: SVGElementRect?
  let children: [any SVGElement]

  var textScale: Double { 1.0 }

  init(base: SVGBaseElement, contents children: [any SVGElement]) {
    self.base = base
    self.children = children
    let attributes = base.attributes
    // The position and the size of a nested `<svg>` element and of a `<symbol>` are attributes, which style sheets
    // don't set. Those of the outermost `<svg>` element are properties (``outermost``). They take math functions, as
    // SVG 2 makes them geometry properties, whose presentation attributes are read as CSS.
    x = attributes["x"].flatMap { SVGLength(property: $0) }
    y = attributes["y"].flatMap { SVGLength(property: $0) }
    width = attributes["width"].flatMap { SVGLength(property: $0, isNonNegative: true) }
    height = attributes["height"].flatMap { SVGLength(property: $0, isNonNegative: true) }
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

  private init(other: SVGSVGElement, x: SVGLength?, y: SVGLength?, width: SVGLength?, height: SVGLength?) {
    base = other.base
    self.x = x
    self.y = y
    self.width = width
    self.height = height
    viewBox = other.viewBox
    children = other.children
    preserveAspectRatio = other.preserveAspectRatio
    overflow = other.overflow
  }

  /// The element as the outermost `<svg>` element of a document, whose position and size are properties that style
  /// sheets can set, as in `style="width: 10vw"`. SVG 2 doesn't apply these properties to nested `<svg>` elements
  /// (w3c/svgwg#1059), as browsers don't.
  var outermost: SVGSVGElement {
    guard base.name == .svg else { return self }
    return SVGSVGElement(other: self, x: style.x, y: style.y, width: style.width, height: style.height)
  }

  /// The element with the width and height of the `<use>` element that shows it, where that element has them.
  func sized(width: SVGLength?, height: SVGLength?) -> SVGSVGElement {
    SVGSVGElement(other: self, width: width, height: height)
  }

  /// No viewport, since the element resolves its own size as a context before it's placed in a view, for the
  /// intrinsic size of the view. Viewport units, such as `10vw`, are 0 then, as percentages are without a view box.
  var viewPort: CGRect {
    .zero
  }

  static func parseViewBox(_ value: String?) -> SVGElementRect? {
    // The numbers are separated by whitespace or a comma with optional whitespace, as in `0, 0, 620, 340`.
    guard let numbers = value.flatMap(numberList), numbers.count == 4 else { return nil }
    return SVGElementRect(x: numbers[0], y: numbers[1], width: numbers[2], height: numbers[3])
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
    outermostSize { length, mode in length.value(context: self, mode: mode) }
  }

  /// The width and the height of the element as the outermost `svg` element, with the lengths resolved by a closure.
  ///
  /// A missing width or height is 100%, except where the other one is there and isn't a percentage, and the element
  /// has a view box with an area: it then takes the ratio of the view box, as CSS sizes a replaced element that has
  /// one size and an aspect ratio, and as browsers size an SVG image whose root has only a width or a height.
  func outermostSize(resolve: (SVGLength, SVGLengthMode) -> CGFloat) -> CGSize {
    let box = viewBox?.toCGRect()
    let ratio: CGFloat? = box.flatMap { $0.width > 0 && $0.height > 0 ? $0.width / $0.height : nil }
    switch (width, height, ratio) {
    case (let width?, nil, let ratio?) where !width.hasPercent:
      let value = resolve(width, .width)
      return CGSize(width: value, height: value / ratio)
    case (nil, let height?, let ratio?) where !height.hasPercent:
      let value = resolve(height, .height)
      return CGSize(width: value * ratio, height: value)
    default:
      return CGSize(
        width: resolve(width ?? .percent(100), .width), height: resolve(height ?? .percent(100), .height))
    }
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
