import CoreGraphics
import Foundation

extension RenderTreeBuilder {
  /// The characters that a `<text>` element or one of its spans renders, and where each of them is in the user space
  /// of the text, or `nil` for a character that isn't rendered, or `nil` if the document has no such element or it
  /// isn't text or a span of text.
  ///
  /// The characters are the ones after their white space is processed, and their lengths are resolved as the
  /// rendering resolves them, also for text that isn't rendered, such as text with `display: none`.
  package func characterGeometry(of id: ElementID) -> (text: [Character], characters: [CharacterGeometry?])? {
    guard let svg = base.root, let chain = Self.chain(to: id, from: svg),
      let textIndex = chain.lastIndex(where: { $0 is SVGTextElement }),
      let text = chain[textIndex] as? SVGTextElement
    else { return nil }
    // The element is the text, or a span in it.
    let isText = chain.last?.base.elementID == text.base.elementID
    guard isText || chain.last is SVGTSpanElement else { return nil }
    var context = ResolveContext(
      base: base, viewPort: viewPort, scale: scale, viewBox: svg.getViewBox(size: viewPort.size))
    // The viewports that the text is in resolve its percentages, as `geometry(of:)` finds them.
    for ancestor in chain[..<textIndex] {
      context = context.styled(by: ancestor)
      if let svg = ancestor as? SVGSVGElement {
        let isRoot = svg.base.elementID == base.root?.base.elementID
        context = viewport(of: svg, context: context, isRoot: isRoot).layout?.context ?? context
      }
    }
    context = context.styled(by: text)
    return text.characterGeometry(of: isText ? nil : id, in: context)
  }
}
