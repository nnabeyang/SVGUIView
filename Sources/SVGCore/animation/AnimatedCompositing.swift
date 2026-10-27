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
      let changesCompositing = animatedProperties(of: element).contains(where: Self.compositingProperties.contains)
      if changesCompositing {
        elements.insert(element.base.elementID)
      }
    }
    for animation in animations.smil {
      if animation.changesCompositing {
        elements.insert(animation.target)
      }
    }
    return elements
  }

  /// The properties that a layer composites an element with.
  static let compositingProperties: Set<PropertyID> = [.transform, .transformOrigin, .transformBox, .opacity]

  /// The properties that the keyframes of the CSS animations of an element set.
  func animatedProperties(of element: any SVGElement) -> Set<PropertyID> {
    var properties = Set<PropertyID>()
    for name in element.style.animationName {
      guard case .keyframes(let name) = name, let rule = animations.keyframes[name] else { continue }
      for keyframe in rule.keyframes {
        properties.formUnion(keyframe.declarations.properties)
      }
    }
    return properties
  }
}

extension SMILAnimation {
  /// Whether the animation changes how a layer composites its target: its transform, its motion or its opacity.
  var changesCompositing: Bool {
    switch kind {
    case .animateMotion: true
    case .animateTransform: attributeName == "transform"
    case .animate, .set:
      attributeName.flatMap(PropertyID.init(rawValue:)).map(SVGBaseContext.compositingProperties.contains) ?? false
    }
  }
}
