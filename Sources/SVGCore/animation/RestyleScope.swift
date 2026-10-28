import Foundation

/// The elements whose computed values animations can change, which a document at another time computes again, and
/// the elements that have them in their subtrees, which it makes again around them. Every other element stays as it
/// is at every time.
struct RestyleScope: Sendable {
  /// The elements that run CSS animations, that SMIL animations change or that have transitions, with their
  /// descendants, which inherit
  /// their properties and resolve their lengths against them.
  let changing: Set<ElementID>
  /// The elements in `changing` and their ancestors.
  let containing: Set<ElementID>
  /// The elements whose render nodes can change: the ones in `containing`, the ones that reference an element whose
  /// render node can change, such as a `<use>` element, an element with a clip path, a mask or a filter, or one
  /// painted with a gradient or a pattern, and their ancestors. Every other element makes the same render node at
  /// every time, which a renderer can reuse.
  let unstable: Set<ElementID>

  /// The elements of a tree whose computed values animations can change.
  ///
  /// - Parameter animations: The animations of the document that the tree comes from.
  init(root: some SVGElement, animations: DocumentAnimations) {
    let targets = Set(animations.smil.map(\.target)).union(animations.transitions.keys)
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
    unstable = Self.unstableElements(of: root, containing: containing)
  }

  /// The elements whose render nodes can change because they contain an element whose computed values change, or
  /// because they reference such an element directly or through other references.
  private static func unstableElements(of root: some SVGElement, containing: Set<ElementID>) -> Set<ElementID> {
    // The elements with each ID. A reference finds the first one of a kind, so every one of them counts.
    var elementsByID = [String: [ElementID]]()
    var references = [ElementID: [String]]()
    var parents = [ElementID: ElementID]()
    func collect(_ element: any SVGElement, parent: ElementID?) {
      let id = element.base.elementID
      if let parent { parents[id] = parent }
      if let name = element.base.id { elementsByID[name, default: []].append(id) }
      let referenced = Self.references(of: element)
      if !referenced.isEmpty { references[id] = referenced }
      for child in element.children {
        collect(child, parent: id)
      }
    }
    collect(root, parent: nil)
    var unstable = containing
    // Marking an element marks its ancestors, since their nodes contain its node, and the elements that reference
    // them, until nothing more is marked.
    var changed = true
    while changed {
      changed = false
      for (element, names) in references where !unstable.contains(element) {
        guard names.contains(where: { elementsByID[$0]?.contains(where: unstable.contains) ?? false }) else { continue }
        var current: ElementID? = element
        while let id = current, unstable.insert(id).inserted {
          current = parents[id]
        }
        changed = true
      }
    }
    return unstable
  }

  /// The IDs of the elements that an element references to make its render node.
  private static func references(of element: any SVGElement) -> [String] {
    let style = element.style
    var names = [String]()
    if case .url(let name) = style.clipPath { names.append(name) }
    if case .url(let name) = style.mask { names.append(name) }
    if case .url(let name) = style.filter { names.append(name) }
    if case .url(let name) = style.fill { names.append(name) }
    if case .url(let name) = style.stroke { names.append(name) }
    switch element {
    case let use as SVGUseElement:
      if let name = use.parentId { names.append(name) }
    case let pattern as SVGPatternElement:
      if let name = pattern.parentId { names.append(name) }
    case let gradient as any SVGGradientServer:
      names.append(contentsOf: gradient.parentIds)
    default:
      break
    }
    return names
  }
}

extension SVGElement {
  /// The element and its descendants with the computed values of the ones that animations can change computed again
  /// for the animations at their time. A subtree without such an element is the same subtree, and an element that
  /// doesn't change keeps its computed values.
  ///
  /// - Parameters:
  ///   - root: The computed values of the root element, or `nil` for the root element itself.
  ///   - replacements: The elements that are made again, by the identities of the elements that they replace.
  func restyled(
    parent: ComputedStyle?, root: ComputedStyle?, animations: DocumentAnimations, in scope: RestyleScope,
    replacements: inout [ObjectIdentifier: any SVGElement]
  ) -> any SVGElement {
    let id = base.elementID
    guard scope.containing.contains(id) else { return self }
    // An element that doesn't change has a parent that doesn't change either, so its computed values stay valid.
    let base = scope.changing.contains(id) ? base.restyled(parent: parent, root: root, animations: animations) : base
    let element = Self(
      base: base,
      contents: children.map {
        $0.restyled(
          parent: base.style, root: root ?? base.style, animations: animations, in: scope, replacements: &replacements)
      })
    replacements[index] = element
    return element
  }
}
