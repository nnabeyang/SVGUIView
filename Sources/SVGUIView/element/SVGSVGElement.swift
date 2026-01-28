import UIKit

enum SVGOverflow: String {
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

final class SVGSVGElement: SVGDrawableElement, SVGLengthContext {
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

  let textAnchor: TextAnchor?

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
    textAnchor = TextAnchor(rawValue: attributes["text-anchor", default: ""].trimmingCharacters(in: .whitespaces))
    preserveAspectRatio = PreserveAspectRatio(description: attributes["preserveAspectRatio", default: ""])
    overflow = SVGOverflow(rawValue: attributes["overflow", default: ""].trimmingCharacters(in: .whitespaces))
  }

  init(base _: SVGBaseElement, text _: String, attributes _: [String: String]) {
    fatalError()
  }

  init(other: SVGSVGElement, attributes: [String: String]) {
    base = SVGBaseElement(other: other.base, attributes: attributes)

    x = other.x
    y = other.y
    width = .init(attributes["width"]) ?? other.width
    height = .init(attributes["height"]) ?? other.height
    viewBox = other.viewBox
    textAnchor = other.textAnchor
    children = other.children
    preserveAspectRatio = other.preserveAspectRatio
    overflow = other.overflow
  }

  init(other: SVGSVGElement, css _: SVGUIStyle) {
    base = other.base
    preserveAspectRatio = other.preserveAspectRatio
    overflow = other.overflow
    x = other.x
    y = other.y
    width = other.width
    height = other.height
    viewBox = other.viewBox
    children = other.children
    textAnchor = other.textAnchor
  }

  var viewPort: CGRect {
    fatalError("not implemented")
  }

  func style(with _: Stylesheet) -> any SVGElement {
    Self(other: self, css: SVGUIStyle(decratations: [:]))
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
  var rootFont: SVGUIFont? { font }

  func frame(context: SVGContext, path _: UIBezierPath?) async -> CGRect {
    var rect: CGRect = .zero
    for child in children {
      guard let content = child as? (any SVGDrawableElement) else { continue }
      rect = await CGRectUnion(rect, content.frame(context: context, path: content.toBezierPath(context: context)))
    }
    return rect
  }

  func drawWithoutFilter(_ context: SVGContext, mode: DrawMode) async {
    context.saveGState()
    let x = (x ?? .pixel(0)).value(context: context, mode: .width)
    let y = (y ?? .pixel(0)).value(context: context, mode: .height)
    context.concatenate(CGAffineTransform(translationX: x, y: y))
    let width = (width ?? .percent(100)).value(context: context, mode: .width)
    let height = (height ?? .percent(100)).value(context: context, mode: .height)

    guard height > 0, width > 0 else {
      context.restoreGState()
      return
    }
    let viewPortSize = CGSize(width: width, height: height)
    let transform = viewBox.map { getTransform(viewBox: $0.toCGRect(), size: viewPortSize) } ?? .identity
    context.concatenate(transform)
    let rect = CGRect(origin: .zero, size: viewPortSize).applying(transform.inverted())
    if let viewBox = viewBox {
      context.push(viewBox: viewBox.toCGRect())
    } else {
      context.push(viewBox: rect)
    }

    let gContext = context.graphics
    let overflow = overflow ?? .hidden
    switch overflow {
    case .visible, .auto:
      break
    default:
      if self.width != nil, self.height != nil {
        gContext.addPath(UIBezierPath(roundedRect: rect, cornerSize: .zero).cgPath)
        gContext.clip()
      }
    }

    gContext.beginTransparencyLayer(auxiliaryInfo: nil)
    let font: SVGUIFont?
    if mode == .root {
      font = self.font ?? SVGUIFont(name: nil, size: nil, weight: nil)
    } else {
      font = self.font
    }
    font.map {
      context.push(font: $0)
    }
    textAnchor.map {
      context.push(textAnchor: $0)
    }
    writingMode.map {
      context.push(writingMode: $0)
    }
    switch mode {
    case .root, .filter:
      context.pushClipIdStack()
      context.pushMaskIdStack()
    default:
      break
    }
    await clipPath?.clipIfNeeded(frame: context.viewBox, context: context, cgContext: context.graphics)
    for child in children {
      guard let content = child as? (any SVGDrawableElement) else { continue }
      await content.draw(context, mode: mode)
    }
    switch mode {
    case .root, .filter:
      context.popClipIdStack()
      context.popMaskIdStack()
    default:
      break
    }
    font.map { _ in
      _ = context.popFont()
    }
    textAnchor.map { _ in
      _ = context.popTextAnchor()
    }
    writingMode.map { _ in
      _ = context.popWritingMode()
    }
    context.popViewBox()
    gContext.endTransparencyLayer()
    context.restoreGState()
  }

  func draw(_ context: SVGContext, mode: DrawMode) async {
    guard !Task.isCancelled else { return }
    let filter = filter ?? SVGFilter.none
    if case .url(let id) = filter,
      let server = context.filters[id]
    {
      await server.filter(content: self, context: context, cgContext: context.graphics)
      return
    }
    await drawWithoutFilter(context, mode: mode)
  }

  func contains(index: ObjectIdentifier, context _: SVGContext) -> Bool {
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

  var size: CGSize {
    let width = width ?? .percent(100)
    let height = height ?? .percent(100)
    return CGSize(
      width: width.value(context: self, mode: .width),
      height: height.value(context: self, mode: .height))
  }

  func toBezierPath(context _: SVGContext) -> UIBezierPath? {
    nil
  }
}

extension SVGSVGElement {
  func encode(to encoder: any Encoder) throws {
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
