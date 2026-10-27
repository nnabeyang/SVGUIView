import Foundation

/// The elements whose computed values animations can change, which a document at another time computes again, and
/// the elements that have them in their subtrees, which it makes again around them. Every other element stays as it
/// is at every time.
struct RestyleScope: Sendable {
  /// The elements that run CSS animations or that SMIL animations change, with their descendants, which inherit
  /// their properties and resolve their lengths against them.
  let changing: Set<ElementID>
  /// The elements in `changing` and their ancestors.
  let containing: Set<ElementID>

  /// The elements of a tree whose computed values animations can change.
  ///
  /// - Parameter animations: The animations of the document that the tree comes from.
  init(root: some SVGElement, animations: DocumentAnimations) {
    let targets = Set(animations.smil.map(\.target))
    var changing = Set<ElementID>()
    var containing = Set<ElementID>()
    /// Collects the elements of a subtree, and returns whether any of them changes.
    func visit(_ element: any SVGElement, isInChangingElement: Bool) -> Bool {
      let id = element.base.elementID
      let runsAnimations = element.style.animationName.contains {
        if case .keyframes(let name) = $0 { animations.keyframes[name] != nil } else { false }
      }
      let changes = isInChangingElement || runsAnimations || targets.contains(id)
      if changes { changing.insert(id) }
      var contains = changes
      for child in element.children where visit(child, isInChangingElement: changes) {
        contains = true
      }
      if contains { containing.insert(id) }
      return contains
    }
    _ = visit(root, isInChangingElement: false)
    self.changing = changing
    self.containing = containing
  }
}

extension SVGElement {
  /// The element and its descendants with the computed values of the ones that animations can change computed again
  /// for the animations at their time. A subtree without such an element is the same subtree, and an element that
  /// doesn't change keeps its computed values.
  ///
  /// - Parameters:
  ///   - root: The computed values of the root element, or `nil` for the root element itself.
  func restyled(
    parent: ComputedStyle?, root: ComputedStyle?, animations: DocumentAnimations, in scope: RestyleScope
  ) -> any SVGElement {
    let id = base.elementID
    guard scope.containing.contains(id) else { return self }
    // An element that doesn't change has a parent that doesn't change either, so its computed values stay valid.
    let base = scope.changing.contains(id) ? base.restyled(parent: parent, root: root, animations: animations) : base
    return Self(
      base: base,
      contents: children.map {
        $0.restyled(parent: base.style, root: root ?? base.style, animations: animations, in: scope)
      })
  }
}
