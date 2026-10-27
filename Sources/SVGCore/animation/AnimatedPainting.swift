import Foundation

extension SVGBaseContext {
  /// The elements whose painting can change with the time in other ways than their transform and their opacity,
  /// with their descendants, or `nil` if the elements that paint the changes can't be told.
  ///
  /// An animation of a property that the descendants inherit, such as `fill`, changes them too, so the descendants of
  /// an element count as well. An animation inside a clip path, a mask, a pattern, a gradient or a filter changes the
  /// elements that reference it, so then the elements can't be told, and a renderer paints everything again.
  ///
  /// This looks at every animation of the document, so a renderer calls it once for a document, not for the
  /// documents at each time.
  package func elementsWithAnimatedPainting() -> Set<ElementID>? {
    guard isAnimated, let root, let documentRoot = document.root else { return [] }
    var painting = Set<ElementID>()
    for element in root.elements
    where animatedProperties(of: element).contains(where: { !Self.compositingProperties.contains($0) }) {
      painting.insert(element.base.elementID)
    }
    for animation in animations.smil where !animation.changesCompositing {
      painting.insert(animation.target)
    }
    let changing = painting.union(elementsWithAnimatedCompositing())
    var elements = Set<ElementID>()
    func visit(_ element: DocumentElement, isInResource: Bool, isChanging: Bool) -> Bool {
      let isInResource = isInResource || Self.resources.contains(element.name)
      if isInResource, changing.contains(element.id) { return false }
      let isChanging = isChanging || painting.contains(element.id)
      if isChanging { elements.insert(element.id) }
      return element.children.allSatisfy { visit($0, isInResource: isInResource, isChanging: isChanging) }
    }
    return visit(documentRoot, isInResource: false, isChanging: false) ? elements : nil
  }

  /// The elements whose content other elements paint with.
  private static let resources: Set<SVGElementName> = [
    .clipPath, .mask, .pattern, .linearGradient, .radialGradient, .stop, .filter,
  ]
}
