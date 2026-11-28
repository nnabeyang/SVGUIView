import CoreGraphics
import Foundation

extension RenderTreeBuilder {
  /// The path of a shape measured along its length, in its user space, or `nil` if the document has no such element or
  /// it isn't a shape: a `<path>` element or a basic shape.
  ///
  /// The path is the path data whose length `getTotalLength()` finds, as `<textPath>` measures a shape: the path data of
  /// a `<path>` element, and the path of the same shape that SVG 2 specifies for a basic shape. Its lengths are
  /// resolved as the rendering resolves them, also for a shape that isn't rendered, such as one with `display: none`
  /// or one in a `<defs>` element. The `pathLength` of the shape doesn't scale it.
  package func pathMeasure(of id: ElementID) -> PathMeasure? {
    guard let svg = base.root, let chain = Self.chain(to: id, from: svg),
      let shape = chain.last as? any ShapeGeometry, !(shape is SVGImageElement), !(shape is SVGTextElement)
    else { return nil }
    var context = ResolveContext(
      base: base, viewPort: viewPort, scale: scale, viewBox: svg.getViewBox(size: viewPort.size))
    // The viewports that the shape is in resolve its percentages, as `geometry(of:)` finds them.
    for ancestor in chain.dropLast() {
      context = context.styled(by: ancestor)
      if let svg = ancestor as? SVGSVGElement {
        let isRoot = svg.base.elementID == base.root?.base.elementID
        context = viewport(of: svg, context: context, isRoot: isRoot).layout?.context ?? context
      }
    }
    context = context.styled(by: shape)
    return PathMeasure(shape.markerPath(in: context) ?? PathData(commands: []))
  }
}

/// The `pathLength` of a shape: the length that the author gives its path, which the distances along the path, such
/// as the dashes of its stroke and the start offset of text on it, are relative to, or `nil` if the element isn't a
/// `<path>` or a basic shape, or has no valid `pathLength`, which is a number that isn't negative.
func authorPathLength(of element: any SVGElement) -> Double? {
  guard element is any ShapeGeometry, !(element is SVGImageElement), !(element is SVGTextElement),
    let text = element.base.attributes["pathLength"],
    let value = Double(text.trimmingCharacters(in: .whitespaces)), value.isFinite, value >= 0
  else { return nil }
  return value
}
