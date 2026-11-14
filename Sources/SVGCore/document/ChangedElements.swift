import Foundation

/// The elements that changes of a document make again, which tell a renderer the render nodes and the painting that
/// can differ from a rendering of the document before the changes.
package struct ChangedElements: Sendable {
  /// The elements that are made again with their descendants.
  var remade = Set<ElementID>()
  /// The elements in `remade` whose painting can change with that of their descendants. The others only moved.
  var repainted = Set<ElementID>()
  /// The elements whose children changed their order, or that some of them left, which keep their children.
  var reordered = Set<ElementID>()
  /// The ancestors of the elements in `remade` and in `reordered`, which are copied with their new children.
  var containing = Set<ElementID>()
  /// Whether every element is made again, with style sheets made again.
  var isEverything = false

  package init() {}

  /// Adds the elements that other changes make again.
  package mutating func formUnion(_ other: ChangedElements) {
    remade.formUnion(other.remade)
    repainted.formUnion(other.repainted)
    reordered.formUnion(other.reordered)
    containing.formUnion(other.containing)
    isEverything = isEverything || other.isEverything
  }
}

/// The render nodes that can differ from a rendering of a document before changes, and the elements whose painting
/// can differ.
package struct ChangedNodes: Sendable {
  /// The elements whose render nodes can differ: the ones that the changes make again, their ancestors, and the
  /// ones that reference them.
  package let nodes: Set<ElementID>
  /// The elements whose painting can differ, with the ones whose children changed, without the ancestors that only
  /// contain them, nor the elements that only moved.
  package let painting: Set<ElementID>
}

extension SVGBaseContext {
  /// The elements that changes of a document make again, as ``changing(to:changes:at:startsTransitions:)`` of the
  /// context before the changes makes them. This is the context after the changes.
  package func changedElements(by changes: DocumentChanges) -> ChangedElements {
    Self.changedElements(by: changes, in: document, with: stylesheet)
  }

  /// The elements that changes of a document make again with a style sheet.
  static func changedElements(
    by changes: DocumentChanges, in document: DocumentTree, with stylesheet: Stylesheet
  ) -> ChangedElements {
    var elements = ChangedElements()
    elements.isEverything = changes.stylesheets
    /// Makes an element again with its descendants, and its later siblings where sibling combinators can match them
    /// in another way.
    func change(_ start: ElementCursor, repaints: Bool) {
      var cursor = start
      elements.remade.insert(cursor.element.id)
      if repaints { elements.repainted.insert(cursor.element.id) }
      if stylesheet.hasSiblingCombinators {
        var sibling = cursor.nextSibling
        while let current = sibling {
          elements.remade.insert(current.element.id)
          if repaints { elements.repainted.insert(current.element.id) }
          sibling = current.nextSibling
        }
      }
      while let parent = cursor.parent, elements.containing.insert(parent.element.id).inserted {
        cursor = parent
      }
    }
    if changes.stylesheets, let root = document.root {
      // Every element is cascaded with the new style sheets.
      change(ElementCursor(root: root), repaints: true)
    }
    for id in changes.attributes.union(changes.inserted).union(changes.texts) {
      guard let cursor = document.cursor(at: id) else { continue }
      // A change of only the transform of an element moves what it paints, unless a selector can match the
      // attribute.
      let moves =
        !changes.paintingAttributes.contains(id) && !changes.inserted.contains(id) && !changes.texts.contains(id)
        && !stylesheet.hasAttributeSelectors
      change(cursor, repaints: !moves)
    }
    if stylesheet.hasSiblingCombinators {
      for id in changes.followingRemoved {
        guard let cursor = document.cursor(at: id) else { continue }
        change(cursor, repaints: true)
      }
    }
    for id in changes.restructured {
      guard var cursor = document.cursor(at: id) else { continue }
      // The pseudo-classes of the structure of the tree can match the element and any of its children in another
      // way, and text keeps its character data by its spans, so they are made again.
      if stylesheet.hasStructuralPseudoClasses || cursor.element.name == .text || cursor.isInText {
        change(cursor, repaints: true)
        continue
      }
      elements.reordered.insert(id)
      while let parent = cursor.parent, elements.containing.insert(parent.element.id).inserted {
        cursor = parent
      }
    }
    return elements
  }

  /// The render nodes of this context that can differ from those of a context before changes, or `nil` if every node
  /// can.
  ///
  /// An element that references an element whose node changes, such as a `<use>` element or one painted with a
  /// gradient, changes with it, and so does one that references an ID that names other elements after the changes.
  ///
  /// - Parameters:
  ///   - old: The context before the changes, whose renderings the nodes are compared with.
  ///   - changes: The elements that the changes make again.
  package func changedNodes(since old: SVGBaseContext, by changes: ChangedElements) -> ChangedNodes? {
    guard !changes.isEverything, let root else { return nil }
    var nodes = changes.reordered.union(changes.containing)
    // An element whose children changed paints other children.
    var painting = changes.reordered
    var elementsByID = [String: [ElementID]]()
    var references = [ElementID: [String]]()
    var parents = [ElementID: ElementID]()
    func collect(_ element: any SVGElement, parent: ElementID?, isRemade: Bool, isRepainted: Bool) {
      let id = element.base.elementID
      let isRemade = isRemade || changes.remade.contains(id)
      let isRepainted = isRepainted || changes.repainted.contains(id)
      if isRemade { nodes.insert(id) }
      if isRepainted { painting.insert(id) }
      if let parent { parents[id] = parent }
      if let name = element.base.id { elementsByID[name, default: []].append(id) }
      let referenced = RestyleScope.references(of: element)
      if !referenced.isEmpty { references[id] = referenced }
      for child in element.children {
        collect(child, parent: id, isRemade: isRemade, isRepainted: isRepainted)
      }
    }
    collect(root, parent: nil, isRemade: false, isRepainted: false)
    // The IDs that name other elements after the changes, such as of a removed element, or one whose `id` changed.
    var oldElementsByID = [String: [ElementID]]()
    func collectIDs(_ element: any SVGElement) {
      if let name = element.base.id { oldElementsByID[name, default: []].append(element.base.elementID) }
      for child in element.children {
        collectIDs(child)
      }
    }
    if let oldRoot = old.root { collectIDs(oldRoot) }
    let renamed = Set(elementsByID.keys).union(oldElementsByID.keys).filter { elementsByID[$0] != oldElementsByID[$0] }
    // Marking an element marks its ancestors, since their nodes contain its node, and the elements that reference
    // them, until nothing more is marked.
    var marked = Set<ElementID>()
    var changed = true
    while changed {
      changed = false
      for (element, names) in references where !marked.contains(element) {
        guard
          names.contains(where: {
            renamed.contains($0) || (elementsByID[$0]?.contains(where: nodes.contains) ?? false)
          })
        else { continue }
        marked.insert(element)
        painting.insert(element)
        var current: ElementID? = element
        while let id = current {
          nodes.insert(id)
          current = parents[id]
        }
        changed = true
      }
    }
    return ChangedNodes(nodes: nodes, painting: painting)
  }
}
