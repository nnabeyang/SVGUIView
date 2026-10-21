import CoreGraphics
import Foundation
import _SelectorParser

protocol SVGElement: AnyObject, Encodable, Sendable {
  static var type: SVGElementName { get }
  var type: SVGElementName { get }
  var base: SVGBaseElement { get }
  var index: ObjectIdentifier { get }
  func draw(_ context: SVGContext, mode: DrawMode) async
  func drawWithoutFilter(_ context: SVGContext, mode: DrawMode) async
  func contains(index: ObjectIdentifier, context: SVGContext) -> Bool
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

  func contains(index _: ObjectIdentifier, context _: SVGContext) -> Bool {
    false
  }

  func clip(context _: inout SVGBaseContext) {}
  func mask(context _: inout SVGBaseContext) {}
  func pattern(context _: inout SVGBaseContext) {}
  func filter(context _: inout SVGBaseContext) {}

  func draw(_: SVGContext, mode _: DrawMode) async {
    fatalError("Not Implemented")
  }

  func drawWithoutFilter(_: SVGContext, mode _: DrawMode) async {
    fatalError("Not Implemented")
  }
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
  let name: SVGElementName
  let text: String
  let id: String?
  var index: ObjectIdentifier { ObjectIdentifier(self) }
  let className: String?
  let font: SVGUIFont?
  let writingMode: WritingMode?
  let attributes: [String: String]
  /// The values that the element's presentation attributes, the style sheets and its `style` attribute declare.
  let cascaded: CascadedValues
  /// The computed values of the element's properties.
  let style: ComputedStyle

  init(name: SVGElementName, text: String, attributes: [String: String], cascaded: CascadedValues, style: ComputedStyle) {
    self.name = name
    self.text = text
    self.attributes = attributes
    self.cascaded = cascaded
    self.style = style
    id = attributes["id"]?.trimmingCharacters(in: .whitespaces)
    className = attributes["class"]?.trimmingCharacters(in: .whitespaces)
    font = SVGUIFont(
      specifiedName: cascaded.declared(FontFamilyProperty.self), size: cascaded.declared(FontSizeProperty.self),
      weight: cascaded.declared(FontWeightProperty.self))
    writingMode = cascaded.declared(WritingModeProperty.self)
  }

  /// The element with its computed values computed again for another parent.
  func restyled(parent: ComputedStyle, root: ComputedStyle) -> SVGBaseElement {
    SVGBaseElement(
      name: name, text: text, attributes: attributes, cascaded: cascaded,
      style: ComputedStyle(cascaded: cascaded, parent: parent, root: root))
  }
}

extension SVGElement {
  var style: ComputedStyle {
    base.style
  }

  /// The element and its descendants with their computed values computed again for another parent, such as a
  /// `<use>` element that shows them. Their cascaded values stay the ones of their places in the document.
  func restyled(parent: ComputedStyle, root: ComputedStyle) -> any SVGElement {
    let base = base.restyled(parent: parent, root: root)
    return Self(base: base, contents: children.map { $0.restyled(parent: base.style, root: root) })
  }
}

protocol SVGDrawableElement: SVGElement {
  var id: String? { get }
  var base: SVGBaseElement { get }
  var type: SVGElementName { get }
  var opacity: Double { get }
  var className: String? { get }
  var transform: CGAffineTransform? { get }
  var writingMode: WritingMode? { get }
  var font: SVGUIFont? { get }
  var display: CSSDisplay? { get }
  var visibility: CSSVisibility? { get }
  func frame(context: SVGContext, path: CGPath?) async -> CGRect
  func scale(context: SVGContext) -> CGAffineTransform
  init(base: SVGBaseElement, text: String, attributes: [String: String])
  func toPath(context: SVGContext) async -> CGPath?
  func applyStroke(path: CGPath, context: SVGContext)
  func applyFill(path: CGPath, context: SVGContext, mode: DrawMode) async
}

extension SVGDrawableElement {
  var id: String? { base.id }
  var index: ObjectIdentifier { base.index }
  var opacity: Double { style.opacity }
  var className: String? { base.className }
  var transform: CGAffineTransform? { style.transform }
  var writingMode: WritingMode? { base.writingMode }
  var font: SVGUIFont? { base.font }
  // `nil` for `none`, so that `clipPath?.clipIfNeeded(frame:…)` doesn't find the frame of an element without one.
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

  func frame(context _: SVGContext, path: CGPath?) -> CGRect {
    path?.boundingBoxOfPath ?? .zero
  }

  func scale(context: SVGContext) -> CGAffineTransform {
    let contentUnit = context.patternContentUnit ?? .userSpaceOnUse
    switch contentUnit {
    case .userSpaceOnUse:
      return .identity
    case .objectBoundingBox:
      let size = context.viewBox.size
      return CGAffineTransform(scaleX: size.width, y: size.height)
    }
  }

  func drawWithoutFilter(_ context: SVGContext, mode: DrawMode) async {
    context.saveGState()
    if mode != .filter(isRoot: true) {
      context.concatenate(transform ?? .identity)
    }
    writingMode.map {
      context.push(writingMode: $0)
    }
    font.map {
      context.push(font: $0)
    }
    switch mode {
    case .root, .filter:
      context.pushTagIdStack()
      context.pushClipIdStack()
      context.pushMaskIdStack()
      context.pushPatternIdStack()
    default:
      break
    }
    let path = await toPath(context: context)
    if let path = path {
      let frame = await frame(context: context, path: path)
      await clipPath?.clipIfNeeded(frame: frame, context: context, cgContext: context.graphics)
      let lineWidth = style.strokeWidth.value(context: context, mode: .other)

      if case .url = style.mask, type == .line, frame.width == lineWidth || frame.height == lineWidth {
        context.graphics.clip(to: .zero)
      } else {
        await mask?.clipIfNeeded(frame: frame, context: context, cgContext: context.graphics)
      }
    }
    let gContext = context.graphics
    gContext.setAlpha(opacity)
    gContext.beginTransparencyLayer(auxiliaryInfo: nil)
    if let path = path, style.visibility == .visible {
      await applyFill(path: path, context: context, mode: mode)
      applyStroke(path: path, context: context)
    }
    switch mode {
    case .root, .filter:
      context.popTagIdStack()
      context.popClipIdStack()
      context.popMaskIdStack()
      context.popPatternIdStack()
    default:
      break
    }
    writingMode.map { _ in
      _ = context.popWritingMode()
    }
    font.map { _ in
      _ = context.popFont()
    }
    gContext.endTransparencyLayer()
    context.restoreGState()
  }

  func draw(_ context: SVGContext, mode: DrawMode) async {
    guard !Task.isCancelled else { return }
    // A rendering hardly ever suspends otherwise, so let other tasks run on this thread of the cooperative
    // thread pool between elements.
    await Task.yield()
    if let display = display, case .none = display {
      return
    }
    let filter = filter ?? SVGFilter.none
    if case .url(let id) = filter,
      let server = context.filters[id]
    {
      await server.filter(content: self, context: context, cgContext: context.graphics)
      return
    }
    await drawWithoutFilter(context, mode: mode)
  }

  func applyStroke(path: CGPath, context: SVGContext) {
    let cgContext = context.graphics
    switch style.resolved(style.stroke) {
    case .none:
      return
    case .url:
      // Paint servers aren't supported on strokes yet, which keep the stroke color of the context.
      break
    case .color(let color):
      cgContext.setStrokeColor(color.toCGColor(opacity: style.strokeOpacity) ?? CGColor.transparent)
    case .currentColor:
      preconditionFailure("currentColor is resolved")
    }
    if !style.strokeDasharray.filter({ $0 > 0 }).isEmpty {
      cgContext.setLineDash(phase: style.strokeDashoffset, lengths: style.strokeDasharray)
    }
    cgContext.addPath(path)
    cgContext.setLineWidth(style.strokeWidth.value(context: context, mode: .other))
    cgContext.setLineCap(style.strokeLinecap)
    cgContext.setLineJoin(style.strokeLinejoin)
    cgContext.setMiterLimit(style.strokeMiterlimit)
    cgContext.drawPath(using: .stroke)
  }

  func applyPServerFill(server: any SVGGradientServer, path: CGPath, context: SVGContext, opacity: CGFloat) {
    if let id = server.parentId,
      let parent = context.pservers[id],
      let merged = server.merged(other: parent)
    {
      applyPServerFill(server: merged, path: path, context: context, opacity: opacity)
      return
    }
    server.draw(path: path, context: context, opacity: opacity)
  }

  func applyFill(path: CGPath, context: SVGContext, mode: DrawMode) async {
    let cgContext = context.graphics
    let opacity = style.fillOpacity
    switch style.resolved(style.fill) {
    case .none:
      return
    case .color(let color):
      // A color that isn't known, such as a misspelled name, paints nothing.
      guard let cgColor = color.toCGColor(opacity: opacity) else { return }
      cgContext.setFillColor(cgColor)
    case .url(let id):
      if let server = context.pservers[id] {
        switch server.display ?? .inline {
        case .none:
          break
        default:
          applyPServerFill(server: server, path: path, context: context, opacity: opacity)
          return
        }
      } else if let pattern = context.patterns[id],
        context.check(patternId: id)
      {
        let frame = await frame(context: context, path: path)
        let cgContext = context.graphics
        cgContext.saveGState()
        cgContext.setAlpha(opacity)
        cgContext.beginTransparencyLayer(auxiliaryInfo: nil)
        _ = await pattern.pattern(path: path, frame: frame, context: context, cgContext: cgContext, mode: mode)
        cgContext.endTransparencyLayer()
        cgContext.restoreGState()
        context.remove(patternId: id)
        return
      }
      cgContext.setFillColor(CGColor.opaqueBlack)
    case .currentColor:
      preconditionFailure("currentColor is resolved")
    }
    cgContext.addPath(path)
    cgContext.drawPath(using: pathFillRule)
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
      name: name, text: element.text, attributes: element.attributes, cascaded: cascaded, style: style)
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

extension CascadedValues {
  /// The value that the element declares for the property, or `nil` if it declares none or a keyword, which
  /// leaves the value to the inheritance while drawing.
  func declared<P: StyleProperty>(_: P.Type) -> P.Specified? {
    if case .value(let value) = self[P.self] { value } else { nil }
  }
}
