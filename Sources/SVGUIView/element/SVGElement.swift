import UIKit
import _SelectorParser

protocol SVGElement: AnyObject, Encodable {
  static var type: SVGElementName { get }
  var type: SVGElementName { get }
  var base: SVGBaseElement { get }
  var index: ObjectIdentifier { get }
  func draw(_ context: SVGContext, mode: DrawMode) async
  func drawWithoutFilter(_ context: SVGContext, mode: DrawMode) async
  func style(with style: Stylesheet) -> any SVGElement
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

enum WritingMode: String {
  case horizontalTB = "horizontal-tb"
  case verticalRL = "vertical-rl"
  case verticalLR = "vertical-lr"
}

enum DrawMode: Equatable {
  case normal
  case root
  case filter(isRoot: Bool)
}

final class SVGBaseElement: Element {
  typealias Impl = SVGSelectorImpl

  let name: SVGElementName
  let text: String
  weak var parent: SVGBaseElement?
  weak var prevSibling: SVGBaseElement?
  weak var nextSibling: SVGBaseElement?
  let children: [SVGBaseElement]
  let id: String?
  var index: ObjectIdentifier { ObjectIdentifier(self) }
  let opacity: Double
  let eoFill: Bool
  let clipRule: Bool?
  let className: String?
  let transform: CGAffineTransform?
  let font: SVGUIFont?
  let fill: SVGFill?
  let stroke: SVGUIStroke
  let color: SVGColor?
  let clipPath: SVGClipPath?
  let mask: SVGMask?
  let filter: SVGFilter?
  let display: CSSDisplay?
  let visibility: CSSVisibility?
  let writingMode: WritingMode?
  let style: SVGUIInlineStyle
  let attributes: [String: String]

  init(name: SVGElementName, text: String, attributes: [String: String], children: [SVGBaseElement]) {
    self.name = name
    self.text = text
    self.children = children
    self.attributes = attributes
    id = attributes["id"]?.trimmingCharacters(in: .whitespaces)
    className = attributes["class"]?.trimmingCharacters(in: .whitespaces)
    style = SVGUIInlineStyle(description: attributes["style", default: ""])
    color = SVGAttributeScanner.parseColor(description: attributes["color", default: ""])
    clipPath = SVGClipPath(description: attributes["clip-path", default: ""])
    mask = SVGMask(description: attributes["mask", default: ""])
    filter = SVGFilter(description: attributes["filter", default: ""])
    font = Self.parseFont(attributes: attributes)
    fill = SVGFill(attributes: attributes)
    stroke = SVGUIStroke(attributes: attributes)
    opacity = Double(attributes["opacity", default: "1"]) ?? 1.0
    transform = CGAffineTransform(description: attributes["transform", default: ""])
    writingMode = WritingMode(rawValue: attributes["writing-mode", default: ""])
    eoFill = attributes["fill-rule", default: ""].trimmingCharacters(in: .whitespaces) == "evenodd"
    clipRule = attributes["clip-rule"].map { $0.trimmingCharacters(in: .whitespaces) == "evenodd" }
    display = CSSDisplay(rawValue: attributes["display", default: ""].trimmingCharacters(in: .whitespaces))
    visibility = CSSVisibility(rawValue: attributes["visibility", default: ""].trimmingCharacters(in: .whitespaces))
  }

  static func create(name: SVGElementName, text: String, attributes: [String: String], children: [SVGBaseElement]) -> SVGBaseElement {
    let element = SVGBaseElement(name: name, text: text, attributes: attributes, children: children)
    let n = element.children.count
    var i = 0
    while i < n {
      let child = element.children[i]
      child.parent = element
      if i > 0 {
        child.prevSibling = element.children[i - 1]
      }
      if i < n - 1 {
        child.nextSibling = element.children[i + 1]
      }
      i += 1
    }
    return element
  }

  init(other: SVGBaseElement, attributes: [String: String]) {
    self.name = other.name
    self.text = other.text
    self.children = other.children
    self.attributes = attributes
    id = other.id
    className = other.className
    style = other.style
    color = other.color ?? SVGAttributeScanner.parseColor(description: attributes["color", default: ""])
    clipPath = other.clipPath
    mask = other.mask
    filter = other.filter ?? SVGFilter(description: attributes["filter", default: ""])
    font = other.font.flatMap { SVGUIFont(lhs: $0, rhs: Self.parseFont(attributes: attributes)) } ?? Self.parseFont(attributes: attributes)
    fill = SVGFill(lhs: other.fill, rhs: SVGFill(attributes: attributes))
    stroke = SVGUIStroke(lhs: other.stroke, rhs: SVGUIStroke(attributes: attributes))
    opacity = other.opacity * (Double(attributes["opacity", default: "1"]) ?? 1.0)

    let transform =
      CGAffineTransform(description: attributes["transform", default: ""])
      .flatMap { other.transform?.concatenating($0) ?? $0 } ?? other.transform
    self.transform = transform
    writingMode = other.writingMode
    eoFill = other.eoFill
    clipRule = other.clipRule
    let display = CSSDisplay(rawValue: attributes["display", default: ""].trimmingCharacters(in: .whitespaces))
    self.display = display ?? other.display
    let visibility = CSSVisibility(rawValue: attributes["visibility", default: ""].trimmingCharacters(in: .whitespaces))
    self.visibility = visibility ?? other.visibility
  }

  init(other: SVGBaseElement, css: SVGUIStyle) {
    self.name = other.name
    self.text = other.text
    self.children = other.children
    self.attributes = other.attributes
    id = other.id
    style = other.style
    className = other.className
    font = other.font
    fill = SVGFill(style: css) ?? other.fill
    clipPath = SVGClipPath(style: css) ?? other.clipPath
    mask = other.mask
    filter = other.filter
    color = other.color
    stroke = SVGUIStroke(lhs: SVGUIStroke(style: css), rhs: other.stroke)
    opacity = other.opacity
    transform = CGAffineTransform(style: css[.transform]) ?? other.transform
    writingMode = other.writingMode
    eoFill = other.eoFill
    clipRule = other.clipRule
    display = other.display
    visibility = other.visibility
  }

  func createElement(with css: Stylesheet) -> any SVGElement {
    var contents = [any SVGElement]()
    for child in children {
      contents.append(child.createElement(with: css))
    }
    let element: any SVGElement =
      switch name {
      case .svg:
        SVGSVGElement(base: self, contents: contents)
      case .g:
        SVGGroupElement(base: self, contents: contents)
      case .clipPath:
        SVGClipPathElement(base: self, contents: contents)
      case .mask:
        SVGMaskElement(base: self, contents: contents)
      case .pattern:
        SVGPatternElement(base: self, contents: contents)
      case .filter:
        SVGFilterElement(base: self, contents: contents)
      case .feMerge:
        SVGFeMergeElement(base: self, contents: contents)
      case .feGaussianBlur:
        SVGFeGaussianBlurElement(base: self, contents: contents)
      case .feFlood:
        SVGFeFloodElement(base: self, contents: contents)
      case .feBlend:
        SVGFeBlendElement(base: self, contents: contents)
      case .feOffset:
        SVGFeOffsetElement(base: self, contents: contents)
      case .feMergeNode:
        SVGFeMergeNodeElement(base: self, contents: contents)
      case .text:
        SVGTextElement(base: self, contents: contents)
      case .image:
        SVGImageElement(base: self, contents: contents)
      case .line:
        SVGLineElement(base: self, contents: contents)
      case .circle:
        SVGCircleElement(base: self, contents: contents)
      case .ellipse:
        SVGEllipseElement(base: self, contents: contents)
      case .rect:
        SVGRectElement(base: self, contents: contents)
      case .path:
        SVGPathElement(base: self, contents: contents)
      case .polyline:
        SVGPolylineElement(base: self, contents: contents)
      case .polygon:
        SVGPolygonElement(base: self, contents: contents)
      case .stop:
        SVGStopElement(base: self, contents: contents)
      case .use:
        SVGUseElement(base: self, contents: contents)
      case .linearGradient:
        SVGLinearGradientServer(base: self, contents: contents)
      case .radialGradient:
        SVGRadialGradientServer(base: self, contents: contents)
      case .defs:
        SVGDefsElement(base: self, contents: contents)
      case .style, .unknown:
        fatalError("unknown element: \(name.rawValue)")
      }
    return element.style(with: css)
  }

  private static func parseFont(attributes: [String: String]) -> SVGUIFont? {
    let name = attributes["font-family"]?.trimmingCharacters(in: .whitespaces)
    let size = attributes["font-size"]?.trimmingCharacters(in: .whitespaces)
    let weight = attributes["font-weight"]?.trimmingCharacters(in: .whitespaces)
    if name == nil,
      size == nil,
      weight == nil
    {
      return nil
    }
    return SVGUIFont(name: name, size: size, weight: weight)
  }

  func hasLocalName(_ localName: Impl.LocalName) -> Bool {
    Impl.LocalName.from(name.rawValue) == localName
  }

  func hasId(id: GenericAtomIdent<IdentStaticSet>, caseSensitivity _: _SelectorParser.CaseSensitivity) -> Bool {
    self.id == id.rawValue
  }

  func hasClass(name: GenericAtomIdent<IdentStaticSet>, caseSensitivity _: _SelectorParser.CaseSensitivity) -> Bool {
    self.className == name.rawValue
  }
}

protocol SVGDrawableElement: SVGElement {
  var id: String? { get }
  var base: SVGBaseElement { get }
  var type: SVGElementName { get }
  var opacity: Double { get }
  var eoFill: Bool { get }
  var clipRule: Bool? { get }
  var className: String? { get }
  var transform: CGAffineTransform? { get }
  var writingMode: WritingMode? { get }
  var font: SVGUIFont? { get }
  var fill: SVGFill? { get }
  var stroke: SVGUIStroke { get }
  var color: SVGColor? { get }
  var style: SVGUIInlineStyle { get }
  var display: CSSDisplay? { get }
  var visibility: CSSVisibility? { get }
  func frame(context: SVGContext, path: UIBezierPath?) async -> CGRect
  func scale(context: SVGContext) -> CGAffineTransform
  init(text: String, attributes: [String: String])
  init(base: SVGBaseElement, text: String, attributes: [String: String])
  init(other: Self, css: SVGUIStyle)
  init(other: Self, attributes: [String: String])
  func use(attributes: [String: String]) -> Self
  func toBezierPath(context: SVGContext) async -> UIBezierPath?
  func applySVGStroke(stroke: SVGUIStroke, path: UIBezierPath, context: SVGContext)
  func applySVGFill(fill: SVGFill?, path: UIBezierPath, context: SVGContext, mode: DrawMode) async
}

extension SVGDrawableElement {
  var id: String? { base.id }
  var index: ObjectIdentifier { base.index }
  var opacity: Double { base.opacity }
  var eoFill: Bool { base.eoFill }
  var clipRule: Bool? { base.clipRule }
  var className: String? { base.className }
  var transform: CGAffineTransform? { base.transform }
  var writingMode: WritingMode? { base.writingMode }
  var font: SVGUIFont? { base.font }
  var fill: SVGFill? { base.fill }
  var stroke: SVGUIStroke { base.stroke }
  var clipPath: SVGClipPath? { base.clipPath }
  var mask: SVGMask? { base.mask }
  var filter: SVGFilter? { base.filter }
  var color: SVGColor? { base.color }
  var style: SVGUIInlineStyle { base.style }
  var display: CSSDisplay? { base.display }
  var visibility: CSSVisibility? { base.visibility }

  init(base: SVGBaseElement, contents: [any SVGElement]) {
    self.init(base: base, text: base.text, attributes: base.attributes)
  }

  init(text: String, attributes: [String: String]) {
    let base = SVGBaseElement(name: Self.type, text: text, attributes: attributes, children: [])
    self.init(base: base, text: text, attributes: attributes)
  }

  init(other: Self, attributes: [String: String]) {
    let base = SVGBaseElement(other: other.base, attributes: attributes)
    self.init(base: base, text: "", attributes: attributes)
  }

  func use(attributes: [String: String]) -> Self {
    Self(other: self, attributes: attributes)
  }

  func style(with style: Stylesheet) -> any SVGElement {
    let css = cascadeElement(element: base, stylesheets: [style], inlineStyle: self.style.declarations)
    return Self(other: self, css: css)
  }

  func frame(context _: SVGContext, path: UIBezierPath?) -> CGRect {
    path?.cgPath.boundingBoxOfPath ?? .zero
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
    let path = await toBezierPath(context: context)
    if let path = path {
      let frame = await frame(context: context, path: path)
      await clipPath?.clipIfNeeded(frame: frame, context: context, cgContext: context.graphics)
      let lineWidth = stroke.width?.value(context: context, mode: .other)

      if mask != nil, type == .line, frame.width == lineWidth || frame.height == lineWidth {
        context.graphics.clip(to: .zero)
      } else {
        await mask?.clipIfNeeded(frame: frame, context: context, cgContext: context.graphics)
      }
    }
    let gContext = context.graphics
    gContext.setAlpha(opacity)
    gContext.beginTransparencyLayer(auxiliaryInfo: nil)
    if let path = path {
      await applySVGFill(fill: fill, path: path, context: context, mode: mode)
      applySVGStroke(stroke: stroke, path: path, context: context)
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

  private func applyStrokeFill(fill: SVGFill, opacity: Double, path: UIBezierPath, context: SVGContext) {
    let cgContext = context.graphics
    switch fill {
    case .inherit:
      if let fill = context.fill {
        applyStrokeFill(fill: fill, opacity: opacity, path: path, context: context)
      }
    case .current:
      if let color = context.color, let uiColor = color.toUIColor(opacity: opacity) {
        cgContext.setStrokeColor(uiColor.cgColor)
      }
    case .color(let color, let colorOpacity):
      if case .url = color { return }
      let colorOpacity = colorOpacity?.value ?? 1.0
      if let uiColor = color?.toUIColor(opacity: opacity * colorOpacity) {
        cgContext.setStrokeColor(uiColor.cgColor)
      } else {
        cgContext.setStrokeColor(UIColor.clear.cgColor)
      }
    case .image:
      fatalError("Images not supported in stroke fill")
    }
  }

  func applySVGStroke(stroke elementStroke: SVGUIStroke, path: UIBezierPath, context: SVGContext) {
    let stroke = SVGUIStroke(lhs: elementStroke, rhs: context.stroke)
    guard let fill = stroke.fill else { return }
    let dashes = stroke.dashes ?? []
    let offset = stroke.offset ?? 0
    applyStrokeFill(fill: fill, opacity: stroke.opacity ?? 1.0, path: path, context: context)
    let cgContext = context.graphics
    if !dashes.filter({ $0 > 0 }).isEmpty {
      cgContext.setLineDash(phase: offset, lengths: dashes)
    }
    let lineWidth = stroke.width?.value(context: context, mode: .other) ?? 1.0
    cgContext.addPath(path.cgPath)
    cgContext.setLineWidth(lineWidth)
    cgContext.setLineCap(stroke.cap ?? .butt)
    cgContext.setLineJoin(stroke.join ?? .miter)
    cgContext.setMiterLimit(stroke.miterLimit ?? 4.0)
    cgContext.drawPath(using: .stroke)
  }

  func applyPServerFill(server: any SVGGradientServer, path: UIBezierPath, context: SVGContext, opacity: CGFloat) {
    if let id = server.parentId,
      let parent = context.pservers[id],
      let merged = server.merged(other: parent)
    {
      applyPServerFill(server: merged, path: path, context: context, opacity: opacity)
      return
    }
    server.draw(path: path, context: context, opacity: opacity)
  }

  func applySVGFill(fill: SVGFill?, path: UIBezierPath, context: SVGContext, mode: DrawMode) async {
    path.usesEvenOddFillRule = eoFill
    let cgContext = context.graphics
    guard let fill = fill ?? context.fill else {
      cgContext.setFillColor(UIColor.black.cgColor)
      cgContext.addPath(path.cgPath)
      cgContext.drawPath(using: eoFill ? .eoFill : .fill)
      return
    }
    switch fill {
    case .inherit:
      if let fill = context.fill {
        if case .inherit = fill {
          let fill = context.popFill()
          if let fill = context.fill {
            await applySVGFill(fill: fill, path: path, context: context, mode: mode)
          }
          fill.map {
            context.push(fill: $0)
          }
        } else {
          await applySVGFill(fill: fill, path: path, context: context, mode: mode)
        }
      } else {
        cgContext.setFillColor(UIColor.black.cgColor)
        cgContext.addPath(path.cgPath)
        cgContext.drawPath(using: eoFill ? .eoFill : .fill)
      }
    case .current:
      if let color = context.color, let uiColor = color.toUIColor(opacity: opacity) {
        cgContext.setFillColor(uiColor.cgColor)
      } else {
        cgContext.setFillColor(UIColor.black.cgColor)
      }
      cgContext.addPath(path.cgPath)
      cgContext.drawPath(using: eoFill ? .eoFill : .fill)
    case .color(let color, let opacity):
      let opacity = opacity?.value ?? 1.0
      if case .url(let id) = color {
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
        cgContext.setFillColor(UIColor.black.cgColor)
        cgContext.addPath(path.cgPath)
        cgContext.drawPath(using: eoFill ? .eoFill : .fill)
      } else if let uiColor = color?.toUIColor(opacity: opacity) {
        cgContext.setFillColor(uiColor.cgColor)
        cgContext.addPath(path.cgPath)
        cgContext.drawPath(using: eoFill ? .eoFill : .fill)
      }
    case .image(let data):
      if let data = data,
        let image = UIImage(data: data),
        let cgImage = image.cgImage
      {
        let bounds = path.bounds
        let imageWidth = CGFloat(cgImage.width)
        let imageHeight = CGFloat(cgImage.height)
        let scale = scale(width: bounds.width, height: bounds.height, imageSize: .init(width: imageWidth, height: imageHeight))
        let frame = CGRect(origin: bounds.origin, size: .init(width: imageWidth * scale, height: imageHeight * scale))
        cgContext.scaleBy(x: 1, y: -1)
        cgContext.draw(cgImage, in: CGRect(x: frame.minX, y: -frame.height - frame.minY, width: frame.width, height: frame.height))
      }
    }
  }

  private func scale(width: CGFloat, height: CGFloat, imageSize size: CGSize) -> CGFloat {
    let sx = width / size.width
    let sy = height / size.height
    if width == 0 { return sy }
    if height == 0 { return sx }
    return width > height ? sy : sx
  }
}
