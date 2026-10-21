import CoreGraphics
import Foundation

final class SVGUseElement: SVGDrawableElement {
  static var type: SVGElementName {
    .use
  }

  var type: SVGElementName {
    .use
  }

  let base: SVGBaseElement
  let x: SVGLength?
  let y: SVGLength?
  let width: SVGLength?
  let height: SVGLength?
  let parentId: String?
  let children: [any SVGElement]

  init(base: SVGBaseElement, contents children: [any SVGElement]) {
    self.base = base
    self.children = children
    let attributes = base.attributes
    x = SVGLength(attributes["x"])
    y = SVGLength(attributes["y"])
    width = SVGLength(attributes["width"])
    height = SVGLength(attributes["height"])
    parentId = Self.parseLink(description: attributes["href"])
  }

  init(base _: SVGBaseElement, text _: String, attributes _: [String: String]) {
    fatalError()
  }

  private static func parseLink(description: String?) -> String? {
    guard let description = description else { return nil }
    let hashId = description.trimmingCharacters(in: .whitespaces)
    if hashId.hasPrefix("#") {
      return String(hashId.dropFirst())
    }
    return nil
  }

  /// Calls `body` with the element that the `<use>` element shows, with its computed values computed again with the
  /// `<use>` element as its parent, or returns `nil` if there is none or showing it would make a cycle. While `body`
  /// runs, the elements are in the stack of IDs that finds cycles.
  private func withReferencedElement<T>(
    context: SVGContext, _ body: (any SVGDrawableElement) async -> T
  ) async -> T? {
    let isUseAdded = context.check(tagId: index)
    defer {
      if isUseAdded { context.remove(tagId: index) }
    }
    guard let parentId = parentId,
      let element = context[parentId],
      context.check(tagId: element.index)
    else {
      return nil
    }
    defer {
      context.remove(tagId: element.index)
    }
    guard !element.contains(index: index, context: context) else { return nil }
    let restyled = element.restyled(parent: style, root: context.base.root?.style ?? style)
    if let svg = restyled as? SVGSVGElement {
      return await body(svg.sized(width: width, height: height))
    }
    guard let restyled = restyled as? (any SVGDrawableElement) else { return nil }
    return await body(restyled)
  }

  private func translation(context: SVGContext) -> CGAffineTransform {
    let x = x?.value(context: context, mode: .width) ?? 0
    let y = y?.value(context: context, mode: .height) ?? 0
    return CGAffineTransform(translationX: x, y: y)
  }

  /// The path of the referenced element, moved by `x` and `y`.
  func toPath(context: SVGContext) async -> CGPath? {
    let path = await withReferencedElement(context: context) { element in
      await element.toPath(context: context)
    }
    var translation = translation(context: context)
    return path.flatMap { $0 }.flatMap { $0.copy(using: &translation) }
  }

  /// The bounds of the referenced element, moved by `x` and `y`.
  func frame(context: SVGContext, path _: CGPath?) async -> CGRect {
    let frame = await withReferencedElement(context: context) { element in
      return await element.frame(context: context, path: element.toPath(context: context))
    }
    return (frame ?? .zero).applying(translation(context: context))
  }

  func draw(_ context: SVGContext, mode: DrawMode) async {
    guard !Task.isCancelled else { return }
    await Task.yield()
    if let display = display, case .none = display {
      return
    }
    // Finding the referenced element checks for cycles, which needs a level of the stacks of IDs, also when a filter
    // finds the bounds of the content.
    switch mode {
    case .root, .filter:
      context.pushIdStacks()
    default:
      break
    }
    defer {
      switch mode {
      case .root, .filter:
        context.popIdStacks()
      default:
        break
      }
    }
    let filter = filter ?? SVGFilter.none
    if case .url(let id) = filter,
      let server = context.filters[id]
    {
      await server.filter(content: self, context: context, cgContext: context.graphics)
      return
    }
    await drawWithoutFilter(context, mode: .normal)
  }

  func drawWithoutFilter(_ context: SVGContext, mode: DrawMode) async {
    context.saveGState()
    defer {
      context.restoreGState()
    }
    // A filter draws the content in a context of its own, without the transform.
    let isFilterRoot = mode == .filter(isRoot: true)
    if isFilterRoot {
      context.pushIdStacks()
    } else {
      context.concatenate(transform ?? .identity)
    }
    defer {
      if isFilterRoot {
        context.popIdStacks()
      }
    }
    if let clipPath {
      await clipPath.clipIfNeeded(frame: frame(context: context, path: nil), context: context, cgContext: context.graphics)
    }
    await withReferencedElement(context: context) { element in
      context.concatenate(translation(context: context))
      font.map {
        context.push(font: $0)
      }
      writingMode.map {
        context.push(writingMode: $0)
      }
      context.setAlpha(opacity)
      let gContext = context.graphics
      gContext.beginTransparencyLayer(auxiliaryInfo: nil)
      await element.draw(context, mode: .normal)
      gContext.endTransparencyLayer()
      font.map { _ in
        _ = context.popFont()
      }
      writingMode.map { _ in
        _ = context.popWritingMode()
      }
    }
  }

  func contains(index: ObjectIdentifier, context _: SVGContext) -> Bool {
    self.index == index || children.contains(where: { $0.index == index })
  }
}

extension SVGUseElement: Encodable {
  func encode(to _: any Encoder) throws {
    fatalError()
  }
}
