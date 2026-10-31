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

enum DrawMode: Hashable, Sendable {
  case normal
  case root
  case filter(isRoot: Bool)
}

/// The attributes of an element, with the values that the cascade gives its properties.
final class SVGBaseElement: Sendable {
  /// The identifier of the element in its document, which the nodes of the render tree that it makes keep.
  let elementID: ElementID
  let name: SVGElementName
  /// The character data of `<text>`, `<tspan>` and `<style>` before each `<tspan>` child and after the last one,
  /// which is one more than the `<tspan>` children.
  let texts: [String]
  let id: String?
  var index: ObjectIdentifier { ObjectIdentifier(self) }
  let className: String?
  let attributes: [String: String]
  /// The values that the element's presentation attributes, the style sheets and its `style` attribute declare.
  let cascaded: CascadedValues
  /// The computed values of the element's properties.
  let style: ComputedStyle
  /// Whether the conditional processing attributes of the element evaluate to true, which renders it.
  let passesConditions: Bool

  /// The character data of the element itself, without its children's.
  var text: String { texts.joined() }

  init(
    elementID: ElementID, name: SVGElementName, texts: [String], attributes: [String: String],
    cascaded: CascadedValues, style: ComputedStyle, passesConditions: Bool
  ) {
    self.elementID = elementID
    self.name = name
    self.texts = texts
    self.attributes = attributes
    self.cascaded = cascaded
    self.style = style
    self.passesConditions = passesConditions
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
      elementID: elementID, name: name, texts: texts, attributes: attributes, cascaded: cascaded,
      style: ComputedStyle(
        cascaded: cascaded, parent: parent, root: root, animations: animations,
        smil: animations?.smilEffects[elementID] ?? [], element: elementID),
      passesConditions: passesConditions)
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
  /// The path data whose vertices markers are drawn at, or `nil` for an element without markers. Shapes other than
  /// paths have the path data of the same shape that SVG 2 specifies, whose vertices are the ends of their arcs.
  func markerPath(in context: any GeometryContext) -> PathData?
}

extension ShapeGeometry {
  func markerPath(in _: any GeometryContext) -> PathData? {
    nil
  }

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

}

extension ElementCursor {
  /// Makes the element to render, with the values of the cascade applied, or `nil` for an element that isn't
  /// rendered, such as `<style>`, an unknown element or an animation element, whose descendants aren't rendered
  /// either.
  ///
  /// - Parameters:
  ///   - languages: The languages of the user, in the order of preference, which `systemLanguage` matches.
  ///   - parent: The computed values of the parent element, or `nil` for the root element.
  ///   - root: The computed values of the root element, or `nil` for the root element itself.
  ///   - animations: The animations of the document at its time, or `nil` for no animations.
  func makeElement(
    with css: Stylesheet, languages: [String], parent: ComputedStyle? = nil, root: ComputedStyle? = nil,
    animations: DocumentAnimations? = nil
  ) -> (any SVGElement)? {
    let name = element.name
    if !name.isRendered { return nil }
    let cascaded = cascade(element: self, stylesheet: css)
    let style = ComputedStyle(
      cascaded: cascaded, parent: parent, root: root, animations: animations,
      smil: animations?.smilEffects[element.id] ?? [], element: element.id)
    let isText = name == .text || isInText
    var contents = [any SVGElement]()
    // The character data of text before each span child and after the last one. The other children of text aren't
    // rendered, so the character data around them goes together.
    var texts = [element.texts[0]]
    for index in element.children.indices {
      // A `<tspan>` is rendered only in text, and text renders only its spans: `<tspan>` and `<a>` children.
      let childName = element.children[index].name
      if isText ? (childName == .tspan || childName == .a) : childName != .tspan,
        let child = child(at: index).makeElement(
          with: css, languages: languages, parent: style, root: root ?? style, animations: animations)
      {
        contents.append(child)
        if isText {
          texts.append("")
        }
      }
      texts[texts.count - 1] += element.texts[index + 1]
    }
    let base = SVGBaseElement(
      elementID: element.id, name: name, texts: texts, attributes: element.attributes, cascaded: cascaded,
      style: style, passesConditions: ConditionalProcessing.passes(attributes: element.attributes, languages: languages))
    let rendered: any SVGElement =
      switch name {
      case .svg:
        SVGSVGElement(base: base, contents: contents)
      case .g, .switch:
        SVGGroupElement(base: base, contents: contents)
      case .a:
        // An `<a>` is a span in text, and a group elsewhere.
        isInText ? SVGTSpanElement(base: base, contents: contents) : SVGGroupElement(base: base, contents: contents)
      case .clipPath:
        SVGClipPathElement(base: base, contents: contents)
      case .mask:
        SVGMaskElement(base: base, contents: contents)
      case .marker:
        SVGMarkerElement(base: base, contents: contents)
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
      case .tspan:
        SVGTSpanElement(base: base, contents: contents)
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
      case .symbol:
        SVGSymbolElement(base: base, contents: contents)
      case .style, .unknown, .animate, .set, .animateTransform, .animateMotion, .mpath:
        preconditionFailure("\(name.rawValue) isn't rendered")
      }
    return rendered
  }
}
