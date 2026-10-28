import Foundation

extension SVGBaseContext {
  /// The elements whose painting can change with the time in other ways than their transform and their opacity,
  /// with their descendants.
  ///
  /// An animation of a property that the descendants inherit, such as `fill`, changes them too, so the descendants of
  /// an element count as well. An animation inside a clip path, a mask, a pattern, a gradient or a filter changes the
  /// elements that use it, directly or through other resources, such as a mask whose content uses the filter.
  ///
  /// This looks at every animation of the document, so a renderer calls it once for a document, not for the
  /// documents at each time.
  package func elementsWithAnimatedPainting() -> Set<ElementID> {
    guard isAnimated, let documentRoot = document.root else { return [] }
    var painting = Set<ElementID>()
    for element in root?.elements ?? []
    where animatedProperties(of: element).contains(where: { !Self.compositingProperties.contains($0) }) {
      painting.insert(element.base.elementID)
    }
    for animation in animations.smil where !animation.changesCompositing {
      painting.insert(animation.target)
    }
    painting.formUnion(elementsUsingResources(thatChange: painting.union(elementsWithAnimatedCompositing())))
    var elements = Set<ElementID>()
    func visit(_ element: DocumentElement, isChanging: Bool) {
      let isChanging = isChanging || painting.contains(element.id)
      if isChanging { elements.insert(element.id) }
      for child in element.children {
        visit(child, isChanging: isChanging)
      }
    }
    visit(documentRoot, isChanging: false)
    return elements
  }

  /// The elements that use a resource whose content changes: the ones that reference the resource, or an element in
  /// it, and the ones that use a resource that contains such an element, such as a mask with a shape that uses the
  /// resource, until nothing more is found.
  ///
  /// - Parameter changing: The elements whose painting or compositing changes.
  private func elementsUsingResources(thatChange changing: Set<ElementID>) -> Set<ElementID> {
    guard let root else { return [] }
    // The IDs that find an element in a resource, or the resource: its own and those of its ancestors up to the
    // outermost resource around it.
    var names = [ElementID: [String]]()
    var references = [(element: ElementID, names: [String])]()
    var changed = Set<String>()
    func collect(_ element: any SVGElement, resourceNames: [String]?) {
      let id = element.base.elementID
      var resourceNames = resourceNames
      if resourceNames != nil || Self.resources.contains(element.base.name) {
        resourceNames = (resourceNames ?? []) + (element.base.id.map { [$0] } ?? [])
      }
      if let resourceNames {
        names[id] = resourceNames
        if changing.contains(id) { changed.formUnion(resourceNames) }
      }
      let referenced = RestyleScope.references(of: element)
      if !referenced.isEmpty { references.append((id, referenced)) }
      for child in element.children {
        collect(child, resourceNames: resourceNames)
      }
    }
    collect(root, resourceNames: nil)
    var elements = Set<ElementID>()
    var found = !changed.isEmpty
    while found {
      found = false
      for (element, referenced) in references where !elements.contains(element) && referenced.contains(where: changed.contains) {
        elements.insert(element)
        // An element in a resource changes the elements that use the resource in turn.
        changed.formUnion(names[element] ?? [])
        found = true
      }
    }
    return elements
  }

  /// The elements whose content other elements paint with.
  private static let resources: Set<SVGElementName> = [
    .clipPath, .mask, .pattern, .linearGradient, .radialGradient, .stop, .filter,
  ]
}
