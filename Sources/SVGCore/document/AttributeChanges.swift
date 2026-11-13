import Foundation

/// What changed in a document since a context was made of it, which tells the elements to make again.
package struct DocumentChanges: Sendable {
  /// The elements whose attributes changed.
  package var attributes = Set<ElementID>()
  /// The elements that got or lost children, or whose children changed their order.
  package var restructured = Set<ElementID>()
  /// The elements that were inserted, with their descendants, which includes the ones that were moved.
  package var inserted = Set<ElementID>()
  /// The elements that followed an element when it was removed from their parent, which sibling combinators can
  /// match in another way without it.
  package var followingRemoved = Set<ElementID>()
  /// The elements whose character data changed.
  package var texts = Set<ElementID>()
  /// Whether the `<style>` elements of the tree changed: one was inserted or removed, or its character data or its
  /// type changed. The style sheets are made again from the tree, and every element with them.
  package var stylesheets = false

  package init() {}

  package var isEmpty: Bool {
    attributes.isEmpty && restructured.isEmpty && inserted.isEmpty && followingRemoved.isEmpty && texts.isEmpty
      && !stylesheets
  }
}

extension SVGBaseContext {
  /// The context of the document with attributes of its elements set or removed, with the animations at time zero,
  /// as ``changing(to:changes:at:startsTransitions:)`` makes it.
  ///
  /// - Parameters:
  ///   - changes: The values to set by the elements and the names of the attributes, with `nil` to remove an
  ///     attribute.
  ///   - time: The time of the timeline at which the change is made, in seconds.
  ///   - startsTransitions: Whether the change starts transitions.
  package func changingAttributes(
    _ changes: [ElementID: [String: String?]], at time: Double = 0, startsTransitions: Bool = true
  ) -> SVGBaseContext {
    guard !changes.isEmpty else { return self }
    var documentChanges = DocumentChanges()
    documentChanges.attributes = Set(changes.keys)
    return changing(
      to: document.changingAttributes(changes), changes: documentChanges, at: time, startsTransitions: startsTransitions)
  }

  /// The context of a changed version of the document, with the animations at time zero.
  ///
  /// The elements whose computed values a change can change are made again from the changed document: the elements
  /// whose attributes changed, the inserted elements, their later siblings when the style sheets have sibling
  /// combinators, and the descendants of them all. An element that got or lost children keeps its computed values and
  /// the children that it had, in their new order, unless the style sheets have pseudo-classes of the structure of
  /// the tree, such as `:nth-child()`, which make the element and its descendants again. Their ancestors are copied
  /// with the new children, and every other element is shared. The SMIL animations, what animations can change and
  /// the elements that references find are found again in the new tree. The elements whose character data changed
  /// are made again as the ones whose attributes changed. When the `<style>` elements changed, the style sheets are
  /// made again from the tree, without the rules of the style sheets in other files, which the next rendering reads
  /// again, and every element is made again with them.
  ///
  /// This is for the context of a document at time zero, such as the one that parsing makes, whose elements have no
  /// animated values.
  ///
  /// The CSS animations that the change makes the elements run start at the time of the change, and the ones that
  /// the elements keep running play on as before. A change of `animation-play-state` pauses an animation at the
  /// local time that it's at then, or plays it on from the local time that it's paused at. The CSS animations of an
  /// inserted element start at the time of the change, also the ones of an element that was removed and inserted
  /// again.
  ///
  /// The change starts transitions of the properties that it changes, as `transition-*` gives, from the values at
  /// the time, and reverses or cancels the running ones. Transitions that have ended are left out. An element that
  /// isn't rendered, since its `display` or that of an ancestor is `none`, starts no transitions, and the ones of an
  /// element that the change stops rendering are cancelled, unless a transition of `display` keeps it rendered. An
  /// inserted element starts no transitions, since it has no values to start from, and the transitions of the
  /// removed and the inserted elements are cancelled.
  ///
  /// - Parameters:
  ///   - document: The changed document.
  ///   - changes: What changed in the document since this context was made. Elements that the changed document
  ///     doesn't have are ignored.
  ///   - time: The time of the timeline at which the change is made, in seconds.
  ///   - startsTransitions: Whether the change starts transitions. If it doesn't, the running transitions are
  ///     cancelled too, so the values change at once.
  package func changing(
    to document: DocumentTree, changes: DocumentChanges, at time: Double = 0, startsTransitions: Bool = true
  ) -> SVGBaseContext {
    guard !changes.isEmpty else { return self }
    // The style sheets are made again from the `<style>` elements of the tree. The ones of the processing
    // instructions stay, and the ones in other files are read again by the next rendering.
    let stylesheet =
      changes.stylesheets
      ? StyleSheetSources(
        document: document, processingInstructions: self.stylesheet.sources?.processingInstructions ?? []
      ).stylesheet : self.stylesheet
    var changed = Set<ElementID>()
    var reordered = Set<ElementID>()
    var containing = Set<ElementID>()
    /// Makes an element again with its descendants, and its later siblings where sibling combinators can match them
    /// in another way.
    func change(_ start: ElementCursor) {
      var cursor = start
      changed.insert(cursor.element.id)
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
    if changes.stylesheets, let root = document.root {
      // Every element is cascaded with the new style sheets.
      change(ElementCursor(root: root))
    }
    for id in changes.attributes.union(changes.inserted).union(changes.texts) {
      guard let cursor = document.cursor(at: id) else { continue }
      change(cursor)
    }
    if stylesheet.hasSiblingCombinators {
      for id in changes.followingRemoved {
        guard let cursor = document.cursor(at: id) else { continue }
        change(cursor)
      }
    }
    for id in changes.restructured {
      guard var cursor = document.cursor(at: id) else { continue }
      // The pseudo-classes of the structure of the tree can match the element and any of its children in another
      // way, and text keeps its character data by its spans, so they are made again.
      if stylesheet.hasStructuralPseudoClasses || cursor.element.name == .text || cursor.isInText {
        change(cursor)
        continue
      }
      reordered.insert(id)
      while let parent = cursor.parent, containing.insert(parent.element.id).inserted {
        cursor = parent
      }
    }
    let root = root?.remade(
      changing: changed, reordering: reordered, containing: containing, in: document, with: stylesheet, parent: nil,
      root: nil)
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
    animations.findSMILStartedAnimations(in: document, stylesheet: stylesheet)
    // The inserted elements and their descendants, whose animations start and whose transitions are cancelled.
    let inserted = changes.inserted.isEmpty ? [] : Self.elements(of: root, in: changes.inserted)
    animations.playback = playback(of: root, at: time, starting: inserted)
    let context = SVGBaseContext(
      document: document, stylesheet: stylesheet, root: root as? SVGSVGElement, animations: animations)
    guard startsTransitions else { return context }
    animations.transitions = transitions(
      changingTo: context, of: Self.elements(of: root, in: changed).subtracting(inserted), at: time)
    if !changes.restructured.isEmpty || !changes.inserted.isEmpty {
      // The removed elements have no transitions any more, and the inserted ones start none.
      let present = Set((root?.elements ?? []).map(\.base.elementID))
      animations.transitions = animations.transitions.filter { present.contains($0.key) && !inserted.contains($0.key) }
    }
    guard !animations.transitions.isEmpty else { return context }
    let transitioned = SVGBaseContext(
      document: document, stylesheet: stylesheet, root: root as? SVGSVGElement, animations: animations)
    // The transitions of the elements that the change stops rendering are cancelled. Whether an element is rendered
    // is found with the transitions, since a transition of `display` keeps it rendered until it ends.
    guard !context.elementsNotRendered().isDisjoint(with: animations.transitions.keys) else { return transitioned }
    let hidden = transitioned.at(time: time).elementsNotRendered()
    let rendered = animations.transitions.filter { !hidden.contains($0.key) }
    guard rendered.count < animations.transitions.count else { return transitioned }
    animations.transitions = rendered
    guard !rendered.isEmpty else { return context }
    return SVGBaseContext(
      document: document, stylesheet: stylesheet, root: root as? SVGSVGElement, animations: animations)
  }

  /// The context with another style sheet: the computed values of the elements cascaded with it, and its
  /// animations. The SMIL animations keep the times that the document API begins and ends them at, the CSS
  /// animations play on, and the transitions run on.
  ///
  /// - Parameter time: The time of the document in seconds, which the CSS animations that the style sheet starts
  ///   start at.
  func replacingStylesheet(_ stylesheet: Stylesheet, at time: Double) -> SVGBaseContext {
    let root = document.root.flatMap {
      ElementCursor(root: $0).makeElement(with: stylesheet, languages: document.languages) as? SVGSVGElement
    }
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
    animations.findSMILStartedAnimations(in: document, stylesheet: stylesheet)
    animations.playback = playback(of: root, at: time)
    animations.transitions = self.animations.transitions
    return SVGBaseContext(document: document, stylesheet: stylesheet, root: root, animations: animations)
  }

  /// The elements of a tree that are in a set, and their descendants.
  private static func elements(of root: (any SVGElement)?, in set: Set<ElementID>) -> Set<ElementID> {
    var elements = Set<ElementID>()
    func visit(_ element: any SVGElement, isInSet: Bool) {
      let isInSet = isInSet || set.contains(element.base.elementID)
      if isInSet { elements.insert(element.base.elementID) }
      for child in element.children {
        visit(child, isInSet: isInSet)
      }
    }
    if let root { visit(root, isInSet: false) }
    return elements
  }

  /// The playback of the CSS animations of a new tree of the document, whose elements run the animations that start
  /// at the time, and the ones that play on from this context.
  ///
  /// - Parameter starting: The elements whose animations start at the time, though this context has them, such as
  ///   the ones that were removed and inserted again.
  private func playback(of root: (any SVGElement)?, at time: Double, starting: Set<ElementID> = [])
    -> [CSSAnimationID: AnimationPlayback]
  {
    let before = Dictionary(uniqueKeysWithValues: cssAnimationStates(of: self.root))
    var playback = [CSSAnimationID: AnimationPlayback]()
    for (id, isPaused) in cssAnimationStates(of: root) {
      var current: AnimationPlayback
      if let wasPaused = before[id], !starting.contains(id.element) {
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
  /// their descendants, the elements in `reordered` are copied with the children that the document gives them, the
  /// elements in `containing` are copied with their children made again, and other elements are the same.
  ///
  /// - Parameters:
  ///   - parent: The computed values of the parent element, or `nil` for the root element.
  ///   - root: The computed values of the root element, or `nil` for the root element itself.
  fileprivate func remade(
    changing changed: Set<ElementID>, reordering reordered: Set<ElementID>, containing: Set<ElementID>,
    in document: DocumentTree, with stylesheet: Stylesheet, parent: ComputedStyle?, root: ComputedStyle?
  ) -> (any SVGElement)? {
    let id = base.elementID
    if changed.contains(id) {
      return document.cursor(at: id)?.makeElement(
        with: stylesheet, languages: document.languages, parent: parent, root: root)
    }
    let style = base.style
    if reordered.contains(id), let cursor = document.cursor(at: id) {
      // The children that the element keeps are made again where they changed, and the ones that it got are made
      // from the document. An element that isn't text doesn't render the spans of text.
      let kept = Dictionary(children.map { ($0.base.elementID, $0) }, uniquingKeysWith: { first, _ in first })
      return Self(
        base: base,
        contents: cursor.children.compactMap { child -> (any SVGElement)? in
          guard child.element.name != .tspan, child.element.name != .textPath else { return nil }
          if let element = kept[child.element.id] {
            return element.remade(
              changing: changed, reordering: reordered, containing: containing, in: document, with: stylesheet,
              parent: style, root: root ?? style)
          }
          return child.makeElement(with: stylesheet, languages: document.languages, parent: style, root: root ?? style)
        })
    }
    guard containing.contains(id) else { return self }
    return Self(
      base: base,
      contents: children.compactMap {
        $0.remade(
          changing: changed, reordering: reordered, containing: containing, in: document, with: stylesheet,
          parent: style, root: root ?? style)
      })
  }
}
