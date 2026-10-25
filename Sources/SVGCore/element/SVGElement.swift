import CoreGraphics
import Foundation
import _SelectorParser

protocol SVGElement: AnyObject, Encodable, Sendable {
  static var type: SVGElementName { get }
  var type: SVGElementName { get }
  var base: SVGBaseElement { get }
  var index: ObjectIdentifier { get }
  func contains(index: ObjectIdentifier) -> Bool
  func clip(context: inout SVGBaseContext)
  func mask(context: inout SVGBaseContext)
  func pattern(context: inout SVGBaseContext)
  func filter(context: inout SVGBaseContext)

  var children: [any SVGElement] { get }
  var elements: [any SVGElement] { get }

  init(base: SVGBaseElement, contents: [any SVGElement])
}

extension SVGElement {
  var index: ObjectIdentifier {
    base.index
  }

  var children: [any SVGElement] {
    []
  }

  var elements: [any SVGElement] {
    var elements = [any SVGElement]()
    elements.append(self)
    for child in children {
      elements.append(contentsOf: child.elements)
    }
    return elements
  }

  func contains(index _: ObjectIdentifier) -> Bool {
    false
  }

  func clip(context _: inout SVGBaseContext) {}
  func mask(context _: inout SVGBaseContext) {}
  func pattern(context _: inout SVGBaseContext) {}
  func filter(context _: inout SVGBaseContext) {}

}

enum WritingMode: String, CaseIterable {
  case horizontalTB = "horizontal-tb"
  case verticalRL = "vertical-rl"
  case verticalLR = "vertical-lr"
}

enum DrawMode: Equatable {
  case normal
  case root
  case filter(isRoot: Bool)
}

/// The attributes of an element, with the values that the cascade gives its properties.
final class SVGBaseElement: Sendable {
  /// The identifier of the element in its document, which the nodes of the render tree that it makes keep.
  let elementID: ElementID
  let name: SVGElementName
  let text: String
  let id: String?
  var index: ObjectIdentifier { ObjectIdentifier(self) }
  let className: String?
  let attributes: [String: String]
  /// The values that the element's presentation attributes, the style sheets and its `style` attribute declare.
  let cascaded: CascadedValues
  /// The computed values of the element's properties.
  let style: ComputedStyle

  init(
    elementID: ElementID, name: SVGElementName, text: String, attributes: [String: String], cascaded: CascadedValues,
    style: ComputedStyle
  ) {
    self.elementID = elementID
    self.name = name
    self.text = text
    self.attributes = attributes
    self.cascaded = cascaded
    self.style = style
    id = attributes["id"]?.trimmingCharacters(in: .whitespaces)
    className = attributes["class"]?.trimmingCharacters(in: .whitespaces)
  }

  /// The element with its computed values computed again for another parent, or with animations.
  ///
  /// - Parameters:
  ///   - parent: The computed values of the parent, or `nil` for the root element.
  ///   - root: The computed values of the root element, or `nil` for the root element itself.
  ///   - animations: The animations of the document at its time, or `nil` for no animations.
  func restyled(parent: ComputedStyle?, root: ComputedStyle?, animations: DocumentAnimations?) -> SVGBaseElement {
    SVGBaseElement(
      elementID: elementID, name: name, text: text, attributes: attributes, cascaded: cascaded,
      style: ComputedStyle(cascaded: cascaded, parent: parent, root: root, animations: animations))
  }
}

extension SVGElement {
  var style: ComputedStyle {
    base.style
  }

  /// The element and its descendants with their computed values computed again for another parent, such as a
  /// `<use>` element that shows them, or with the animations of the document at its time. Their cascaded values
  /// stay the ones of their places in the document.
  ///
  /// - Parameters:
  ///   - parent: The computed values of the parent, or `nil` for the root element.
  ///   - root: The computed values of the root element, or `nil` for the root element itself.
  ///   - animations: The animations of the document at its time, or `nil` for no animations.
  func restyled(parent: ComputedStyle?, root: ComputedStyle?, animations: DocumentAnimations?) -> any SVGElement {
    let base = base.restyled(parent: parent, root: root, animations: animations)
    return Self(
      base: base,
      contents: children.map { $0.restyled(parent: base.style, root: root ?? base.style, animations: animations) })
  }
}

protocol SVGDrawableElement: SVGElement {
  var id: String? { get }
  var base: SVGBaseElement { get }
  var type: SVGElementName { get }
  var opacity: Double { get }
  var className: String? { get }
  var display: CSSDisplay? { get }
  var visibility: CSSVisibility? { get }
  init(base: SVGBaseElement, text: String, attributes: [String: String])
}

/// An element whose shape doesn't depend on other elements: a shape, text or an image.
protocol ShapeGeometry: SVGDrawableElement {
  /// The shape, or `nil` for an element without one.
  func path(in context: any GeometryContext) -> CGPath?
  /// The bounds that units relative to the element use.
  func frame(in context: any GeometryContext, path: CGPath?) -> CGRect
}

extension ShapeGeometry {
  func frame(in _: any GeometryContext, path: CGPath?) -> CGRect {
    path?.boundingBoxOfPath ?? .zero
  }
}

extension SVGDrawableElement {
  var id: String? { base.id }
  var index: ObjectIdentifier { base.index }
  var opacity: Double { style.opacity }
  var className: String? { base.className }
  // `nil` for `none`, so that the frame of an element without a clip path isn't found for it.
  var clipPath: SVGClipPath? { if case .url = style.clipPath { style.clipPath } else { nil } }
  var mask: SVGMask? { if case .url = style.mask { style.mask } else { nil } }
  var filter: SVGFilter? { if case .url = style.filter { style.filter } else { nil } }
  var display: CSSDisplay? { style.display }
  var visibility: CSSVisibility? { style.visibility }

  /// The fill rule of the element's path.
  var pathFillRule: CGPathDrawingMode {
    style.fillRule == .evenodd ? .eoFill : .fill
  }

  init(base: SVGBaseElement, contents: [any SVGElement]) {
    self.init(base: base, text: base.text, attributes: base.attributes)
  }

  /// The transform that `patternContentUnits` of `objectBoundingBox` scales the element's shape by.
  func scale(context: any GeometryContext) -> CGAffineTransform {
    let contentUnit = context.patternContentUnit ?? .userSpaceOnUse
    switch contentUnit {
    case .userSpaceOnUse:
      return .identity
    case .objectBoundingBox:
      let size = context.viewBox.size
      return CGAffineTransform(scaleX: size.width, y: size.height)
    }
  }

}

extension ElementCursor {
  /// Makes the element to render, with the values of the cascade applied, or `nil` for an element that isn't
  /// rendered, such as `<style>` or an unknown element, whose descendants aren't rendered either.
  ///
  /// - Parameters:
  ///   - parent: The computed values of the parent element, or `nil` for the root element.
  ///   - root: The computed values of the root element, or `nil` for the root element itself.
  func makeElement(with css: Stylesheet, parent: ComputedStyle? = nil, root: ComputedStyle? = nil) -> (any SVGElement)? {
    let name = element.name
    if name == .style || name == .unknown { return nil }
    let cascaded = cascade(element: self, stylesheet: css)
    let style = ComputedStyle(cascaded: cascaded, parent: parent, root: root)
    let contents = element.children.indices.compactMap {
      child(at: $0).makeElement(with: css, parent: style, root: root ?? style)
    }
    let base = SVGBaseElement(
      elementID: element.id, name: name, text: element.text, attributes: element.attributes, cascaded: cascaded, style: style)
    let rendered: any SVGElement =
      switch name {
      case .svg:
        SVGSVGElement(base: base, contents: contents)
      case .g:
        SVGGroupElement(base: base, contents: contents)
      case .clipPath:
        SVGClipPathElement(base: base, contents: contents)
      case .mask:
        SVGMaskElement(base: base, contents: contents)
      case .pattern:
        SVGPatternElement(base: base, contents: contents)
      case .filter:
        SVGFilterElement(base: base, contents: contents)
      case .feMerge:
        SVGFeMergeElement(base: base, contents: contents)
      case .feGaussianBlur:
        SVGFeGaussianBlurElement(base: base, contents: contents)
      case .feFlood:
        SVGFeFloodElement(base: base, contents: contents)
      case .feBlend:
        SVGFeBlendElement(base: base, contents: contents)
      case .feOffset:
        SVGFeOffsetElement(base: base, contents: contents)
      case .feMergeNode:
        SVGFeMergeNodeElement(base: base, contents: contents)
      case .text:
        SVGTextElement(base: base, contents: contents)
      case .image:
        SVGImageElement(base: base, contents: contents)
      case .line:
        SVGLineElement(base: base, contents: contents)
      case .circle:
        SVGCircleElement(base: base, contents: contents)
      case .ellipse:
        SVGEllipseElement(base: base, contents: contents)
      case .rect:
        SVGRectElement(base: base, contents: contents)
      case .path:
        SVGPathElement(base: base, contents: contents)
      case .polyline:
        SVGPolylineElement(base: base, contents: contents)
      case .polygon:
        SVGPolygonElement(base: base, contents: contents)
      case .stop:
        SVGStopElement(base: base, contents: contents)
      case .use:
        SVGUseElement(base: base, contents: contents)
      case .linearGradient:
        SVGLinearGradientServer(base: base, contents: contents)
      case .radialGradient:
        SVGRadialGradientServer(base: base, contents: contents)
      case .defs:
        SVGDefsElement(base: base, contents: contents)
      case .style, .unknown:
        preconditionFailure("\(name.rawValue) isn't rendered")
      }
    return rendered
  }
}
