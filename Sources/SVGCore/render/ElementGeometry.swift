import CoreGraphics
import Foundation

/// The geometry of an element of a document, as SVG 2 defines its bounding boxes and its current transformation
/// matrix.
package struct ElementGeometry: Sendable {
  /// The object bounding box, in the user space of the element: the coordinates that its own `transform` applies
  /// to. For an `<svg>` element, they're the coordinates of its content.
  package let boundingBox: CGRect
  /// The stroke bounding box, in the same coordinates, if it was asked for.
  package let strokeBoundingBox: CGRect?
  /// The shape of the element, in the same coordinates, if it was asked for and the element has one.
  package let path: RenderPath?
  /// The transform from the user space of the element to the coordinates that the document is rendered in, with its
  /// own `transform`.
  package let transformToViewPort: CGAffineTransform

  /// The geometry with a transform after the one to the coordinates that the document is rendered in.
  package func concatenating(_ transform: CGAffineTransform) -> ElementGeometry {
    ElementGeometry(
      boundingBox: boundingBox, strokeBoundingBox: strokeBoundingBox, path: path,
      transformToViewPort: transformToViewPort.concatenating(transform))
  }
}

extension RenderTreeBuilder {
  /// The geometry of an element of the document, as if it were rendered, or `nil` if the document has no such element,
  /// the element isn't a graphics element, or the task is cancelled.
  ///
  /// SVG 2 gives an element that isn't rendered, such as one with `display: none` or one in a `<defs>` element, the
  /// bounding box that it would have if it were rendered, while it adds nothing to the bounding boxes of its
  /// ancestors.
  ///
  /// - Parameters:
  ///   - fit: How the document is placed in the rectangle that it's rendered into.
  ///   - includesStroke: Whether to find the stroke bounding box.
  ///   - includesPath: Whether to find the shape.
  package func geometry(
    of id: ElementID, fit: ContentFit, includesStroke: Bool, includesPath: Bool
  ) async -> ElementGeometry? {
    guard let svg = base.root, let chain = Self.chain(to: id, from: svg),
      let element = chain.last as? any SVGDrawableElement, Self.hasGeometry(element)
    else { return nil }
    var context = ResolveContext(
      base: base, viewPort: viewPort, scale: scale, viewBox: svg.getViewBox(size: viewPort.size))
    // The view places the box of the width and the height of the root element, as `build(fit:)` does.
    let (width, height) = rootSize(of: svg, context: context)
    var toViewPort =
      width > 0 && height > 0 ? fit.transform(size: CGSize(width: width, height: height), in: viewPort.size) : .identity
    let references = ReferenceGuard()
    // The text that a `<tspan>` or `<textPath>` element is in, which lays out its characters, in its own context.
    var text: (element: SVGTextElement, context: ResolveContext)?
    for ancestor in chain.dropLast() {
      context = context.styled(by: ancestor)
      switch ancestor {
      case let ancestor as SVGTextElement:
        // The spans of a text are in its user space, and have no transform of their own.
        let path = await self.path(of: ancestor, context: context, guard: references)
        let frame = await self.frame(of: ancestor, context: context, path: path, guard: references)
        toViewPort = await transform(of: ancestor, context: context, frame: frame, guard: references)
          .concatenating(toViewPort)
        text = (ancestor, context)
      case let svg as SVGSVGElement:
        let (local, inner) = await placement(of: svg, context: context, guard: references)
        toViewPort = local.concatenating(toViewPort)
        context = inner
      case let group as SVGGroupElement:
        toViewPort = await transform(of: group, context: context, frame: nil, guard: references)
          .concatenating(toViewPort)
      case let defs as SVGDefsElement:
        toViewPort = await transform(of: defs, context: context, frame: nil, guard: references)
          .concatenating(toViewPort)
      default:
        // A `<symbol>` that no `<use>` element shows establishes no viewport, and the elements that aren't graphics
        // elements, such as `<clipPath>` and `<mask>`, have no transform of their own.
        break
      }
    }
    context = context.styled(by: element)
    let boundingBox: CGRect
    let strokeBoundingBox: CGRect?
    var path: CGPath?
    switch element {
    case let svg as SVGSVGElement:
      // The bounding box of a viewport is in the coordinates of its content, which its view box and its position
      // place.
      let (local, inner) = await placement(of: svg, context: context, guard: references)
      toViewPort = local.concatenating(toViewPort)
      boundingBox = await frame(of: svg.children, context: inner, guard: references) ?? .zero
      strokeBoundingBox =
        includesStroke
        ? await frame(of: svg.children, context: inner, includesStroke: true, guard: references) ?? .zero : nil
    case let span as SVGTSpanElement:
      // A span has the bounds and the shape of its characters, in the user space of its text.
      let geometry = text.flatMap { $0.element.spanGeometry(of: span.base.elementID, in: $0.context) }
      boundingBox = geometry?.frame ?? .zero
      // The cells of the glyphs hold their outlines, so the stroke adds nothing to the bounds, as it adds nothing to
      // the bounds of a text.
      strokeBoundingBox = includesStroke ? boundingBox : nil
      path = geometry?.path
    case let symbol as SVGSymbolElement:
      boundingBox = await frame(of: symbol.children, context: context, guard: references) ?? .zero
      strokeBoundingBox =
        includesStroke
        ? await frame(of: symbol.children, context: context, includesStroke: true, guard: references) ?? .zero : nil
    default:
      path = await self.path(of: element, context: context, guard: references)
      boundingBox = await frame(of: element, context: context, path: path, guard: references)
      strokeBoundingBox =
        includesStroke
        ? await frame(of: element, context: context, path: path, includesStroke: true, guard: references) : nil
      toViewPort = await transform(of: element, context: context, frame: boundingBox, guard: references)
        .concatenating(toViewPort)
    }
    guard !Task.isCancelled else { return nil }
    return ElementGeometry(
      boundingBox: boundingBox, strokeBoundingBox: strokeBoundingBox,
      path: includesPath ? path.map(RenderPath.init) : nil, transformToViewPort: toViewPort)
  }

  /// The transform from the content of an `<svg>` element to its parent, which its view box, its position and its
  /// own transform make, and the context of its content, in a context styled by the element.
  private func placement(
    of svg: SVGSVGElement, context: ResolveContext, guard references: ReferenceGuard
  ) async -> (transform: CGAffineTransform, context: ResolveContext) {
    let isRoot = svg.base.elementID == base.root?.base.elementID
    let transform = await self.transform(of: svg, context: context, frame: nil, guard: references)
    let (translation, layout) = viewport(of: svg, context: context, isRoot: isRoot)
    let viewBoxTransform = layout?.viewBoxTransform ?? .identity
    return (viewBoxTransform.concatenating(translation).concatenating(transform), layout?.context ?? context)
  }

  /// Whether an element is a graphics element of SVG 2, or a text content element, that SVGUIView finds the geometry
  /// of. The ones that aren't, such as `<mask>` and `<pattern>`, have no bounding box.
  private static func hasGeometry(_ element: any SVGDrawableElement) -> Bool {
    switch element {
    case is SVGMaskElement, is SVGPatternElement, is SVGFilterElement: false
    default: true
    }
  }

  /// The elements from the root to the element of the identifier, or `nil` if the tree has no such element.
  private static func chain(to id: ElementID, from element: any SVGElement) -> [any SVGElement]? {
    if element.base.elementID == id { return [element] }
    for child in element.children {
      if let chain = chain(to: id, from: child) {
        return [element] + chain
      }
    }
    return nil
  }
}
