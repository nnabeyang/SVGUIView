import CoreGraphics

extension RenderTree {
  /// The node of an element of the document, and the transform from the coordinates of its parent to the
  /// coordinates of the rendered rectangle, or `nil` if the tree has no node of the element.
  ///
  /// The transform has the transforms of the ancestors, the view boxes of the viewports around the element and the
  /// root transforms, but not the opacities, the clips, the masks and the filters of the ancestors. The nodes in the
  /// content of a `<use>` element aren't elements of the document, so they aren't found.
  package func subtree(of element: ElementID) -> (node: RenderNode, transform: CGAffineTransform)? {
    guard let root else { return nil }
    // The root transforms apply one after another, so the last one maps to the rectangle.
    let fit = rootTransforms.reversed().reduce(CGAffineTransform.identity) { $0.concatenating($1) }
    return Self.find(RenderID(element: element, instance: []), in: [root], transform: fit)
  }

  /// The node with an ID among nodes or their descendants, whose parent has a transform to the rendered rectangle.
  private static func find(
    _ id: RenderID, in nodes: [RenderNode], transform: CGAffineTransform
  ) -> (node: RenderNode, transform: CGAffineTransform)? {
    for node in nodes {
      // A filtered node has the ID of its element, as the source inside it does, so the filtered one is found.
      if node.id == id { return (node, transform) }
      let inside: (nodes: [RenderNode], transform: CGAffineTransform)? =
        switch node {
        case .shape, .use: nil
        case .group(let group): (group.children, group.transform.concatenating(transform))
        case .viewport(let viewport):
          viewport.content.map { content in
            (
              content.children,
              content.viewBoxTransform.concatenating(viewport.translation).concatenating(viewport.transform)
                .concatenating(transform)
            )
          }
        case .filtered(let filtered): filtered.source.map { ([$0], filtered.transform.concatenating(transform)) }
        }
      if let inside, let found = find(id, in: inside.nodes, transform: inside.transform) {
        return found
      }
    }
    return nil
  }
}
