import CoreGraphics
import Foundation

final class SVGGroupElement: SVGDrawableElement {
  static var type: SVGElementName {
    .g
  }

  var type: SVGElementName {
    .g
  }

  let base: SVGBaseElement

  let children: [any SVGElement]

  init(base: SVGBaseElement, contents children: [any SVGElement]) {
    self.base = base
    self.children = children
  }

  init(base _: SVGBaseElement, text _: String, attributes _: [String: String]) {
    fatalError()
  }

  func toPath(context _: SVGContext) -> CGPath? {
    nil
  }

  func frame(context: SVGContext, path _: CGPath?) async -> CGRect {
    var rect: CGRect? = nil
    for content in children {
      guard let content = content as? (any SVGDrawableElement) else { continue }
      if case .none = content.display ?? .inline {
        continue
      }
      let context = context.styled(by: content)
      if rect != nil {
        rect = await CGRectUnion(rect!, content.frame(context: context, path: content.toPath(context: context)).applying(content.transform ?? .identity))
      } else {
        rect = await content.frame(context: context, path: content.toPath(context: context)).applying(content.transform ?? .identity)
      }
    }
    return rect ?? .zero
  }

  func drawWithoutFilter(_ context: SVGContext, mode: DrawMode) async {
    let context = context.styled(by: self)
    context.saveGState()
    if mode != .filter(isRoot: true) {
      context.concatenate(transform ?? .identity)
    }
    context.setAlpha(opacity)
    let gContext = context.graphics
    gContext.beginTransparencyLayer(auxiliaryInfo: nil)
    switch mode {
    case .root, .filter:
      context.pushClipIdStack()
      context.pushMaskIdStack()
    default:
      break
    }
    await clipPath?.clipIfNeeded(frame: frame(context: context, path: nil), context: context, cgContext: context.graphics)
    for content in children {
      guard let content = content as? (any SVGDrawableElement) else { continue }
      await content.draw(context, mode: mode == .filter(isRoot: true) ? .filter(isRoot: false) : mode)
    }
    switch mode {
    case .root, .filter:
      context.popClipIdStack()
      context.popMaskIdStack()
    default:
      break
    }
    gContext.endTransparencyLayer()
    context.restoreGState()
  }

  func draw(_ context: SVGContext, mode: DrawMode) async {
    guard !Task.isCancelled else { return }
    await Task.yield()
    let filter = filter ?? SVGFilter.none
    if case .url(let id) = filter,
      let server = context.filters[id]
    {
      await server.filter(content: self, context: context, cgContext: context.graphics)
      return
    }
    await drawWithoutFilter(context, mode: mode)
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

  func contains(index: ObjectIdentifier, context _: SVGContext) -> Bool {
    children.contains(where: { $0.index == index })
  }
}

extension SVGGroupElement {
  func encode(to encoder: any Encoder) throws {
    fatalError()
  }
}
