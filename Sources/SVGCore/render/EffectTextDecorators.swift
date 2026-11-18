import Synchronization

/// The elements that declare lines of `text-decoration` around the clip paths, masks, patterns and markers of a
/// document, by the elements whose content they're around, which the text in the content draws the lines of.
///
/// The content of those elements is built in a context of its own, where the elements around them aren't, so the
/// table is found once from the tree of the document, the first time that content is built. A copy of the context of
/// the document shares it, and the context of the document at another time or after a change finds it again.
final class EffectTextDecoratorsCache: Sendable {
  private let table = Mutex<[ElementID: TextDecorators]?>(nil)

  /// The elements that declare lines around an element, which are none if no element around it declares a line.
  func decorators(around element: ElementID, in root: SVGSVGElement?) -> TextDecorators {
    table.withLock { table in
      if table == nil {
        var found = [ElementID: TextDecorators]()
        if let root { Self.find(in: root, around: TextDecorators(), into: &found) }
        table = found
      }
      return table?[element] ?? TextDecorators()
    }
  }

  /// Finds the elements that declare lines around the clip paths, masks, patterns and markers in an element and its
  /// descendants, after the ones around the element.
  private static func find(
    in element: any SVGElement, around decorators: TextDecorators, into table: inout [ElementID: TextDecorators]
  ) {
    var decorators = decorators
    if let drawable = element as? any SVGDrawableElement,
      let lines = ResolveContext.textDecorations(declaredBy: drawable)
    {
      decorators.declare(lines, by: drawable)
    }
    switch element {
    case is SVGClipPathElement, is SVGMaskElement, is SVGPatternElement, is SVGMarkerElement:
      if !decorators.isEmpty { table[element.base.elementID] = decorators }
    default:
      break
    }
    for child in element.children {
      find(in: child, around: decorators, into: &table)
    }
  }
}
