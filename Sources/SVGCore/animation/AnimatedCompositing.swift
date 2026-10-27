import Foundation

extension SVGBaseContext {
  /// The elements whose transform or opacity can change with the time: the ones that an animation changes
  /// `transform`, `transform-origin`, `transform-box` or `opacity` of, or moves with `<animateMotion>`.
  ///
  /// A renderer can give each of them a layer of its own, and change only the transform and the opacity of the layer
  /// when they change. The elements may also have other properties that change.
  ///
  /// This looks at every animation of the document, so a renderer calls it once for a document, not for the
  /// documents at each time.
  package func elementsWithAnimatedCompositing() -> Set<ElementID> {
    guard isAnimated, let root else { return [] }
    var elements = Set<ElementID>()
    for element in root.elements {
      let changesCompositing = element.style.animationName.contains { name in
        guard case .keyframes(let name) = name, let rule = animations.keyframes[name] else { return false }
        return rule.keyframes.contains { keyframe in
          let declarations = keyframe.declarations
          return declarations[TransformProperty.self] != nil || declarations[TransformOriginProperty.self] != nil
            || declarations[TransformBoxProperty.self] != nil || declarations[OpacityProperty.self] != nil
        }
      }
      if changesCompositing {
        elements.insert(element.base.elementID)
      }
    }
    for animation in animations.smil {
      let changesCompositing =
        switch animation.kind {
        case .animateMotion: true
        case .animateTransform: animation.attributeName == "transform"
        case .animate, .set: animation.attributeName.map(Self.compositingAttributes.contains) ?? false
        }
      if changesCompositing {
        elements.insert(animation.target)
      }
    }
    return elements
  }

  /// The properties other than `transform` that `<animate>` and `<set>` change the compositing of an element with.
  private static let compositingAttributes: Set<String> = ["opacity", "transform-origin", "transform-box"]
}
