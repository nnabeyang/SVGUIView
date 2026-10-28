import Foundation

extension SVGBaseContext {
  /// Whether the values that animations change are the same in this context and another one, so that they render
  /// the same: the computed values of the elements that animations can change, and the attributes that SMIL
  /// animations change.
  ///
  /// Both contexts are the document at a time, which `at(time:)` makes from the same context, so that every other
  /// value is the same in both.
  package func hasSameAnimatedValues(as other: SVGBaseContext) -> Bool {
    guard isAnimated, let scope = restyleScope else { return true }
    guard
      SMILEffect.attributes(of: animations.smilEffects, in: document)
        == SMILEffect.attributes(of: other.animations.smilEffects, in: other.document)
    else { return false }
    return animatedStyles(in: scope) == other.animatedStyles(in: scope)
  }

  /// The computed values of the elements that animations can change.
  private func animatedStyles(in scope: RestyleScope) -> [ElementID: ComputedStyle] {
    var styles = [ElementID: ComputedStyle]()
    func collect(_ element: any SVGElement) {
      let id = element.base.elementID
      guard scope.containing.contains(id) else { return }
      if scope.changing.contains(id) { styles[id] = element.style }
      for child in element.children {
        collect(child)
      }
    }
    if let root { collect(root) }
    return styles
  }
}
