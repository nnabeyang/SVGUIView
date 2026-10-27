import Foundation

extension SVGBaseContext {
  /// The context of the document with attributes of its elements set or removed, with the animations at time zero.
  ///
  /// The elements whose computed values a change can change are made again from the changed document: the changed
  /// elements, their later siblings when the style sheets have sibling combinators, and the descendants of both. Their
  /// ancestors are copied with the new children, and every other element is shared. The SMIL animations, what
  /// animations can change and the elements that references find are found again in the new tree. The style sheets
  /// stay the same, since they come from the contents of `<style>` elements.
  ///
  /// This is for the context of a document at time zero, such as the one that parsing makes, whose elements have no
  /// animated values.
  ///
  /// - Parameter changes: The values to set by the elements and the names of the attributes, with `nil` to remove an
  ///   attribute.
  package func changingAttributes(_ changes: [ElementID: [String: String?]]) -> SVGBaseContext {
    guard !changes.isEmpty else { return self }
    let document = document.changingAttributes(changes)
    var changed = Set<ElementID>()
    var containing = Set<ElementID>()
    for id in changes.keys {
      guard var cursor = document.cursor(at: id) else { continue }
      changed.insert(id)
      if stylesheet.hasSiblingCombinators {
        var sibling = cursor.nextSibling
        while let current = sibling {
          changed.insert(current.element.id)
          sibling = current.nextSibling
        }
      }
      while let parent = cursor.parent, containing.insert(parent.element.id).inserted {
        cursor = parent
      }
    }
    let root = root?.remade(
      changing: changed, containing: containing, in: document, with: stylesheet, parent: nil, root: nil)
    return SVGBaseContext(
      document: document, stylesheet: stylesheet, root: root as? SVGSVGElement,
      animations: DocumentAnimations(
        keyframes: stylesheet.keyframes, smil: SMILAnimation.animations(of: document), time: 0))
  }
}

extension SVGElement {
  /// The element made again for a changed document: the elements in `changed` are made from the document with
  /// their descendants, the elements in `containing` are copied with their children made again, and other elements
  /// are the same.
  ///
  /// - Parameters:
  ///   - parent: The computed values of the parent element, or `nil` for the root element.
  ///   - root: The computed values of the root element, or `nil` for the root element itself.
  fileprivate func remade(
    changing changed: Set<ElementID>, containing: Set<ElementID>, in document: DocumentTree,
    with stylesheet: Stylesheet, parent: ComputedStyle?, root: ComputedStyle?
  ) -> (any SVGElement)? {
    let id = base.elementID
    if changed.contains(id) {
      return document.cursor(at: id)?.makeElement(with: stylesheet, parent: parent, root: root)
    }
    guard containing.contains(id) else { return self }
    let style = base.style
    return Self(
      base: base,
      contents: children.compactMap {
        $0.remade(
          changing: changed, containing: containing, in: document, with: stylesheet, parent: style,
          root: root ?? style)
      })
  }
}
