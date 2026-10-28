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
  /// The CSS animations that the change makes the elements run start at the time of the change, and the ones that
  /// the elements keep running play on as before. A change of `animation-play-state` pauses an animation at the
  /// local time that it's at then, or plays it on from the local time that it's paused at.
  ///
  /// - Parameters:
  ///   - changes: The values to set by the elements and the names of the attributes, with `nil` to remove an
  ///     attribute.
  ///   - time: The time of the timeline at which the change is made, in seconds.
  package func changingAttributes(_ changes: [ElementID: [String: String?]], at time: Double = 0) -> SVGBaseContext {
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
    // The times that the document API begins and ends the SMIL animations at stay with their elements.
    let added = Dictionary(
      self.animations.smil.map { ($0.elementID, ($0.addedBegins, $0.addedEnds)) }, uniquingKeysWith: { first, _ in first })
    var animations = DocumentAnimations(
      keyframes: stylesheet.keyframes,
      smil: SMILAnimation.animations(of: document).map { animation in
        var animation = animation
        if let (begins, ends) = added[animation.elementID] {
          animation.addedBegins = begins
          animation.addedEnds = ends
        }
        return animation
      }, time: 0)
    animations.playback = playback(of: root, at: time)
    return SVGBaseContext(
      document: document, stylesheet: stylesheet, root: root as? SVGSVGElement, animations: animations)
  }

  /// The playback of the CSS animations of a new tree of the document, whose elements run the animations that start
  /// at the time, and the ones that play on from this context.
  private func playback(of root: (any SVGElement)?, at time: Double) -> [CSSAnimationID: AnimationPlayback] {
    let before = Dictionary(uniqueKeysWithValues: cssAnimationStates(of: self.root))
    var playback = [CSSAnimationID: AnimationPlayback]()
    for (id, isPaused) in cssAnimationStates(of: root) {
      var current: AnimationPlayback
      if let wasPaused = before[id] {
        current = animations.playback(of: id, isPaused: wasPaused)
        if isPaused != wasPaused {
          if isPaused {
            current.pause(at: time)
          } else {
            current.play(at: time)
          }
        }
      } else {
        current = AnimationPlayback(startTime: time, isPaused: isPaused)
      }
      // The animations that play from the time that the document was loaded need no playback of their own.
      if current != AnimationPlayback(isPaused: isPaused) {
        playback[id] = current
      }
    }
    return playback
  }

  /// The CSS animations of the elements of a tree, and whether `animation-play-state` pauses them.
  private func cssAnimationStates(of root: (any SVGElement)?) -> [(CSSAnimationID, Bool)] {
    (root?.elements ?? []).flatMap { element in
      let style = element.style
      return style.cssAnimations(keyframes: animations.keyframes).map { name, occurrence, index in
        (
          CSSAnimationID(element: element.base.elementID, name: name, occurrence: occurrence),
          ElementAnimation.timing(of: style, at: index).isPaused
        )
      }
    }
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
