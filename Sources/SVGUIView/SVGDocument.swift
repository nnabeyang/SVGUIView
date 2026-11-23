import CoreGraphics
import Foundation
import SVGCore

/// The document that a view displays, which an app reads and changes from Swift.
///
/// The API follows the DOM where it fits Swift. Find elements with
/// ``element(id:)``, ``querySelector(_:)`` and ``querySelectorAll(_:)``, and
/// change their attributes, their classes and the declarations of their
/// `style` attributes. Create elements with ``createElement(_:)``, and insert,
/// move and remove them with ``Element/append(_:)``,
/// ``Element/insert(_:before:)`` and ``Element/remove()``. A change is visible
/// at once to the methods that read the document, and the view shows it at its
/// next rendering. The changes made in one turn of the run loop are rendered
/// together.
///
/// ```swift
/// if let button = svgView.document.element(id: "play") {
///   button.classList.add("active")
///   button.setAttribute("fill", to: "red")
/// }
/// ```
///
/// Assigning new ``SVGUIView/data`` to the view replaces its document. The
/// document that it replaces can still be read and changed, but the view no
/// longer shows it.
///
/// ``animations`` lists the CSS animations that the elements run, which
/// ``Animation`` pauses, plays, moves and speeds up. A CSS animation that a
/// change starts, such as one that a new class sets, starts at the time of the
/// change.
@MainActor
public final class SVGDocument {
  /// The tree of the document with every change, which reading the document sees.
  private var tree: DocumentTree
  /// The elements that aren't in the tree, by the roots of their trees: the ones that were created and not inserted
  /// yet, and the ones that were removed, with their descendants. The document keeps them, so that they can be
  /// inserted again.
  private var detached = [ElementID: DocumentTree]()
  /// The raw value of the identifier of the next element that is created.
  private var nextElementID: Int
  /// What changed in the tree that the view hasn't rendered yet.
  private var changes = DocumentChanges()
  /// The view that shows the document, or `nil` for a document that a view no longer shows.
  weak var host: (any DocumentHost)?

  init(tree: DocumentTree) {
    self.tree = tree
    nextElementID = (tree.largestElementID ?? -1) + 1
  }

  /// The document as SVG data, with every change made to it so far, which an
  /// app saves or shares as an SVG file.
  ///
  /// The data is UTF-8 XML of the elements in the document's tree, with their
  /// attributes as written, and the character data of the `style`, `text`,
  /// `tspan`, `textPath`, `a`, `title` and `desc` elements. The values that
  /// SMIL animations give attributes aren't written, but their animation
  /// elements are. An element of another namespace, such as the content of a
  /// `foreignObject`, is written in its namespace. An `xlink:href` is written
  /// as it is, and the root declares the XLink namespace for it.
  ///
  /// It doesn't keep what parsing the document left out: comments, processing
  /// instructions, the document type declaration, the attributes of other
  /// namespaces, such as the ones that editors add, and the character data of
  /// the other elements. The elements that were created and not inserted, or
  /// removed, aren't written. References to other files, such as the `href`
  /// of an `image`, are written as they are, so a relative one refers to a
  /// file next to where the data is saved.
  public func svgData() -> Data {
    tree.xmlData()
  }

  /// The root `svg` element, or `nil` if the document has no element.
  public var rootElement: Element? {
    tree.rootElement.map { Element(document: self, id: $0) }
  }

  /// The first element in document order whose `id` attribute is the given
  /// one, or `nil` if there is none.
  ///
  /// The search includes elements that SVGUIView doesn't render, such as
  /// `<style>` elements and animation elements.
  public func element(id: String) -> Element? {
    tree.element(id: id).map { Element(document: self, id: $0) }
  }

  /// The first element in document order that a list of selectors matches,
  /// or `nil` if there is none.
  ///
  /// - Parameter selectors: CSS selectors, separated by commas.
  /// - Throws: ``SelectorError`` if the selectors can't be parsed.
  public func querySelector(_ selectors: String) throws(SelectorError) -> Element? {
    try elements(matching: selectors, in: nil).first
  }

  /// The elements that a list of selectors matches, in document order.
  ///
  /// Selectors match type, class and ID selectors, attribute selectors and
  /// combinators, the pseudo-classes of the structure of the tree, such as
  /// `:first-child` and `:nth-child()`, and `:not()`, `:is()` and `:where()`.
  /// They also match `:lang()`, with the language of `xml:lang` or `lang` of
  /// an element or of its nearest ancestor that has one, and `:link` and
  /// `:any-link`, with the `a` elements that have `href`. A selector with a
  /// pseudo-class that depends on user actions, such as `:hover`, matches no
  /// element.
  ///
  /// - Parameter selectors: CSS selectors, separated by commas.
  /// - Throws: ``SelectorError`` if the selectors can't be parsed.
  public func querySelectorAll(_ selectors: String) throws(SelectorError) -> [Element] {
    try elements(matching: selectors, in: nil)
  }

  /// The CSS animations that the elements run, in document order and in
  /// the order of each element's `animation-name`.
  ///
  /// The list includes the changes made to the document so far, and it's
  /// empty for a document that a view no longer shows. SMIL animations aren't
  /// in it.
  public var animations: [Animation] {
    (host?.cssAnimations() ?? []).map { Animation(element: Element(document: self, id: $0.element), id: $0) }
  }

  /// The time after which the document looks the same, or `nil` if its
  /// animations don't end.
  ///
  /// The time is on the timeline of ``SVGUIView/takeSnapshot(rect:at:scale:)``,
  /// which starts at zero when the document is loaded, so the frames of the
  /// animations are the snapshots from zero to this time. It's zero for a
  /// document without animations, and for a document that no view shows any
  /// more, such as one whose view is released, since the document doesn't
  /// keep its view.
  ///
  /// The time includes the changes made to the document so far, even the ones
  /// that the view hasn't rendered yet. A CSS animation that a change starts
  /// counts from the time of the change, and a paused CSS animation doesn't
  /// count, since it stays where it is. The animations don't end, and the
  /// value is `nil`, when one repeats forever, such as with
  /// `animation-iteration-count: infinite` or `repeatCount="indefinite"`, or
  /// when SMIL animations keep beginning again, such as two that begin when
  /// the other ends.
  ///
  /// ```swift
  /// if let end = svgView.document.animationEnd {
  ///   // Render the frames from zero to `end`.
  /// }
  /// ```
  public var animationEnd: Duration? {
    guard let host else { return .zero }
    let seconds = host.documentAnimationEnd()
    return seconds.isFinite ? .seconds(seconds) : nil
  }

  /// Creates an element of the SVG namespace, which isn't in the tree of the
  /// document until it's inserted, as the DOM's `createElementNS()` does.
  ///
  /// ```swift
  /// let circle = document.createElement("circle")
  /// circle.setAttribute("r", to: "10")
  /// try document.rootElement?.append(circle)
  /// ```
  ///
  /// The attributes, the classes, the style and the children of an element
  /// that isn't in the tree can be read and changed as the ones of any other
  /// element. The view shows the element once it's in the tree.
  ///
  /// - Parameter localName: The name of the element, such as `rect`. An
  ///   element with a name that SVGUIView doesn't know isn't rendered.
  public func createElement(_ localName: String) -> Element {
    let created = DocumentTree(elementNamed: localName, identifier: nextElementID, languages: tree.languages)
    nextElementID += 1
    // The tree has the element that it was made with as its root.
    guard let id = created.rootElement else { preconditionFailure("A created element has no tree") }
    detached[id] = created
    return Element(document: self, id: id)
  }

  /// The frontmost element at a point of the view that shows the document,
  /// as the DOM's `elementFromPoint(_:_:)` finds it, or `nil` if there is
  /// none.
  ///
  /// ```swift
  /// let point = touch.location(in: svgView)
  /// if let shape = await svgView.document.element(at: point, tolerance: 8) {
  ///   select(shape)
  /// }
  /// ```
  ///
  /// ``elements(at:tolerance:)`` describes where an element is hit.
  ///
  /// - Parameters:
  ///   - point: The point, in the coordinates of the view.
  ///   - tolerance: How far from an element the point can be, in points of
  ///     the view, so that a finger can pick a thin line or a small shape.
  public func element(at point: CGPoint, tolerance: CGFloat = 0) async -> Element? {
    await elements(at: point, tolerance: tolerance).first
  }

  /// The elements at a point of the view that shows the document, from the
  /// front, or an empty array if the view doesn't show the document.
  ///
  /// The elements are the shapes, the text and its `tspan` elements, the
  /// images and the `use` elements that are hit at the point, each once, as
  /// SVG 2 hit-tests them for pointer events. Their ancestors, such as `g`
  /// elements and the root `svg` element, aren't in the array, and
  /// ``Element/parent`` finds them. An element is hit:
  ///
  /// - Where its `pointer-events` property targets it. By default, it's hit
  ///   where its fill and its stroke paint, while it's visible: over its fill
  ///   if the fill isn't `none`, and over its stroke, with its dashes, caps
  ///   and joins, if the stroke isn't `none`. Other values hit it over its
  ///   fill or its stroke whatever their paints, also while it's hidden, over
  ///   its bounding box, or never.
  /// - Over the cells of its glyphs, for text, and over its rectangle, for an
  ///   image.
  /// - Where its clip paths and the ones of its ancestors don't clip it out.
  ///   Its opacity, its filter and its mask don't change where it's hit, and
  ///   the markers of a shape aren't hit, as in browsers.
  /// - As the `use` element that shows it, for an element in the content of
  ///   `use` elements.
  ///
  /// An element with `display: none`, or in one, isn't hit. The elements are
  /// the ones of the document with every change made so far, at the time
  /// that the view displays. The view keeps what it finds for hit testing
  /// until the document, its size, its content mode or the time changes, so
  /// hit-testing points one after another doesn't find it again.
  ///
  /// - Parameters:
  ///   - point: The point, in the coordinates of the view.
  ///   - tolerance: How far from an element the point can be, in points of
  ///     the view.
  public func elements(at point: CGPoint, tolerance: CGFloat = 0) async -> [Element] {
    guard let host else { return [] }
    return await host.hits(at: point, tolerance: tolerance).map { Element(document: self, id: $0) }
  }

  /// Takes the tree of the document and what changed in it that the view hasn't rendered yet.
  func takeChanges() -> (tree: DocumentTree, changes: DocumentChanges) {
    defer { changes = DocumentChanges() }
    return (tree, changes)
  }

  /// Where an element is: in the tree of the document, or in one of the trees of the elements that aren't in it.
  private enum Location {
    case connected
    /// - Parameter root: The root of the tree that the element is in.
    case detached(root: ElementID)
  }

  private func location(of id: ElementID) -> Location? {
    if tree.contains(id) { return .connected }
    if detached[id] != nil { return .detached(root: id) }
    return detached.first { $0.value.contains(id) }.map { .detached(root: $0.key) }
  }

  /// The tree that an element is in, or `nil` for an element that the document doesn't have.
  private func tree(containing id: ElementID) -> DocumentTree? {
    switch location(of: id) {
    case .connected: tree
    case .detached(let root): detached[root]
    case nil: nil
    }
  }

  fileprivate func elements(matching selectors: String, in scope: ElementID?) throws(SelectorError) -> [Element] {
    do {
      // The descendants of an element that isn't in the tree are found in the tree that it's in.
      let searched = scope.flatMap { tree(containing: $0) } ?? tree
      return try searched.elements(matching: selectors, in: scope).map { Element(document: self, id: $0) }
    } catch {
      throw SelectorError(selectors: error.selectors)
    }
  }

  fileprivate func localName(of id: ElementID) -> String {
    tree(containing: id)?.localName(of: id) ?? ""
  }

  fileprivate func attribute(_ name: String, of id: ElementID) -> String? {
    tree(containing: id)?.attributes(of: id)?[name]
  }

  /// Sets or removes an attribute, unless it already has the value.
  fileprivate func setAttribute(_ name: String, to value: String?, of id: ElementID) {
    switch location(of: id) {
    case .connected:
      guard let attributes = tree.attributes(of: id), attributes[name] != value else { return }
      tree = tree.changingAttributes([id: [name: value]])
      changes.attributes.insert(id)
      if name != "transform" {
        changes.paintingAttributes.insert(id)
      }
      if name == "id" {
        changes.identifiers.insert(id)
      }
      // The type of a `<style>` element decides whether the document reads its style sheet.
      if name == "type", tree.isStyleElement(id) {
        changes.stylesheets = true
      }
      host?.documentDidChange()
    case .detached(let root):
      // The view doesn't show the element, so it has nothing to render again.
      detached[root] = detached[root]?.changingAttributes([id: [name: value]])
    case nil:
      break
    }
  }

  fileprivate func textContent(of id: ElementID) -> String {
    tree(containing: id)?.textContent(of: id) ?? ""
  }

  /// Replaces the children and the character data of an element with character data, and keeps the children as
  /// elements that aren't in the tree.
  fileprivate func setTextContent(_ text: String, of id: ElementID) {
    guard let location = location(of: id), let current = tree(containing: id) else { return }
    // An element without children that already has the character data stays the same.
    guard !current.children(of: id).isEmpty || current.textContent(of: id) != text,
      let (replaced, removed) = current.replacingChildren(of: id, withText: text)
    else { return }
    for child in removed {
      guard let root = child.rootElement else { continue }
      detached[root] = child
    }
    switch location {
    case .connected:
      tree = replaced
      changes.texts.insert(id)
      if !removed.isEmpty {
        changes.restructured.insert(id)
      }
      if tree.isStyleElement(id) || removed.contains(where: \.hasStyleElement) {
        changes.stylesheets = true
      }
      host?.documentDidChange()
    case .detached(let root):
      detached[root] = replaced
    }
  }

  fileprivate func parent(of id: ElementID) -> Element? {
    tree(containing: id)?.parent(of: id).map { Element(document: self, id: $0) }
  }

  fileprivate func children(of id: ElementID) -> [Element] {
    (tree(containing: id)?.children(of: id) ?? []).map { Element(document: self, id: $0) }
  }

  fileprivate func isConnected(_ id: ElementID) -> Bool {
    tree.contains(id)
  }

  /// Inserts an element among the children of another one, before one of them or after the last one, after removing
  /// it from where it is.
  fileprivate func insert(_ child: ElementID, into parent: ElementID, before reference: ElementID?)
    throws(HierarchyError)
  {
    guard let parentLocation = location(of: parent), let childLocation = location(of: child) else { return }
    guard child != tree.rootElement else { throw HierarchyError(reason: .rootElement) }
    // An element can't be inserted in itself or in one of its descendants.
    if self.tree(containing: child)?.isElement(parent, inSubtreeOf: child) == true {
      throw HierarchyError(reason: .containsParent)
    }
    if let reference, self.tree(containing: parent)?.parent(of: reference) != parent {
      throw HierarchyError(reason: .referenceNotChild)
    }
    // An element that is inserted before itself stays before the sibling after it.
    var reference = reference
    if reference == child {
      let siblings = self.tree(containing: parent)?.children(of: parent) ?? []
      reference = siblings.firstIndex(of: child).flatMap { siblings.dropFirst($0 + 1).first }
    }
    // The element is taken from where it is, with its descendants.
    let subtree: DocumentTree
    switch childLocation {
    case .detached(let root) where root == child:
      guard let taken = detached.removeValue(forKey: root) else { return }
      subtree = taken
    default:
      guard let taken = take(child, from: childLocation) else { return }
      subtree = taken
    }
    let siblings = (self.tree(containing: parent)?.children(of: parent) ?? [])
    let index = reference.flatMap { siblings.firstIndex(of: $0) } ?? siblings.count
    switch parentLocation {
    case .connected:
      guard let inserted = tree.inserting(subtree, into: parent, at: index) else { return }
      tree = inserted
      changes.restructured.insert(parent)
      changes.inserted.insert(child)
      if subtree.hasStyleElement {
        changes.stylesheets = true
      }
      host?.documentDidChange()
    case .detached(let root):
      detached[root] = detached[root]?.inserting(subtree, into: parent, at: index)
    }
  }

  /// Removes an element from its parent, with its descendants, and keeps it as an element that isn't in the tree.
  /// The root element and an element without a parent stay where they are.
  fileprivate func remove(_ id: ElementID) {
    guard let location = location(of: id), let removed = take(id, from: location) else { return }
    detached[id] = removed
  }

  /// Takes an element with its descendants out of the tree that it's in, or returns `nil` if it's the root of the
  /// tree.
  private func take(_ id: ElementID, from location: Location) -> DocumentTree? {
    switch location {
    case .connected:
      guard let parent = tree.parent(of: id), let (remaining, removed) = tree.removing(id) else { return nil }
      // The element that follows the removed one is matched again by the sibling combinators.
      let siblings = tree.children(of: parent)
      if let following = siblings.firstIndex(of: id).flatMap({ siblings.dropFirst($0 + 1).first }) {
        changes.followingRemoved.insert(following)
      }
      tree = remaining
      changes.restructured.insert(parent)
      if removed.hasStyleElement {
        changes.stylesheets = true
      }
      host?.documentDidChange()
      return removed
    case .detached(let root):
      guard let (remaining, removed) = detached[root]?.removing(id) else { return nil }
      detached[root] = remaining
      return removed
    }
  }
}

/// The view that shows a document, which keeps how the animations of the document play.
@MainActor
protocol DocumentHost: AnyObject {
  /// Renders the changes of the document.
  func documentDidChange()
  /// The time in seconds after which the document with its changes looks the same, which is infinite for animations
  /// that don't end.
  func documentAnimationEnd() -> Double
  /// The CSS animations of the document with its changes.
  func cssAnimations() -> [CSSAnimationID]
  /// The playback of a CSS animation and the time of the timeline that the view displays, or `nil` if no element
  /// runs the animation.
  func playback(of id: CSSAnimationID) -> (playback: AnimationPlayback, time: Double)?
  /// Changes the playback of a CSS animation at the time of the timeline that the view displays.
  func changePlayback(of id: CSSAnimationID, _ change: (inout AnimationPlayback, Double) -> Void)
  /// Waits until a CSS animation finishes, or no element runs it, or the view no longer shows the document, or the
  /// task is cancelled.
  func waitUntilFinished(_ id: CSSAnimationID) async
  /// Begins the SMIL animation of an animation element at the time of the timeline that the view displays.
  func beginSMILAnimation(_ element: ElementID)
  /// Ends the SMIL animation of an animation element at the time of the timeline that the view displays.
  func endSMILAnimation(_ element: ElementID)
  /// The geometry of an element of the document with its changes, at the time that the view displays and in the
  /// coordinates of the view, or `nil` if it has none or the task is cancelled.
  func geometry(of element: ElementID, includesStroke: Bool, includesPath: Bool) async -> ElementGeometry?
  /// An image of an element of the document with its changes and its descendants, at the time that the view
  /// displays and in the coordinates of the view, or `nil` if the view doesn't render the element or it paints
  /// nothing.
  func snapshot(of element: ElementID, scale: CGFloat?) async throws(SVGRenderingError) -> SVGDocument.ElementSnapshot?
  /// The elements at a point of the view, from the front.
  func hits(at point: CGPoint, tolerance: CGFloat) async -> [ElementID]
}

extension SVGDocument {
  /// An element of a document.
  ///
  /// An element is a reference to an element of its document: reading it
  /// reads the document as it is, and changing it changes the document.
  public struct Element: Hashable, Sendable {
    /// The document that the element is in.
    public let document: SVGDocument
    let id: ElementID

    nonisolated public static func == (lhs: Element, rhs: Element) -> Bool {
      lhs.document === rhs.document && lhs.id == rhs.id
    }

    nonisolated public func hash(into hasher: inout Hasher) {
      hasher.combine(ObjectIdentifier(document))
      hasher.combine(id)
    }
  }

  /// The error of selectors that can't be parsed.
  public struct SelectorError: Error, Equatable, Sendable {
    /// The selectors as they were given.
    public let selectors: String
  }

  /// The error of an element that can't be inserted where it was asked to
  /// be, as the DOM's `HierarchyRequestError` and `NotFoundError` are.
  public struct HierarchyError: Error, Equatable, Sendable {
    /// Why an element can't be inserted.
    public enum Reason: Equatable, Sendable {
      /// The element is the parent that it would be inserted in, or one of
      /// the ancestors of that parent.
      case containsParent
      /// The element, or the element to insert it before, is an element of
      /// another document.
      case differentDocument
      /// The element to insert before isn't a child of the parent.
      case referenceNotChild
      /// The element is the root element of the document, which stays where
      /// it is.
      case rootElement
    }

    /// Why the element can't be inserted.
    public let reason: Reason
  }
}

@MainActor
extension SVGDocument.Element {
  /// The name of the element as written, without a prefix, such as `rect`.
  public var localName: String {
    document.localName(of: id)
  }

  /// The value of an attribute as written, or `nil` if the element doesn't
  /// have the attribute.
  ///
  /// - Parameter name: The name of the attribute, without a namespace. The
  ///   `href` of the XLink namespace is named `xlink:href`, which is a
  ///   separate attribute from `href`.
  public func attribute(_ name: String) -> String? {
    document.attribute(name, of: id)
  }

  /// Sets the value of an attribute.
  ///
  /// - Parameters:
  ///   - name: The name of the attribute, without a namespace. The `href` of
  ///     the XLink namespace is named `xlink:href`, which is a separate
  ///     attribute from `href`. An element that has both uses `href`.
  ///   - value: The value, as it would be written in the document.
  public func setAttribute(_ name: String, to value: String) {
    document.setAttribute(name, to: value, of: id)
  }

  /// Removes an attribute.
  ///
  /// - Parameter name: The name of the attribute, without a namespace. The
  ///   `href` of the XLink namespace is named `xlink:href`, which is a
  ///   separate attribute from `href`, so removing `href` makes an element that
  ///   has both use its `xlink:href`.
  public func removeAttribute(_ name: String) {
    document.setAttribute(name, to: nil, of: id)
  }

  /// The character data of the element and its descendants, in document
  /// order.
  ///
  /// Setting it replaces the children of the element with the character
  /// data, as the DOM does. The document keeps the children that it removes,
  /// which can be inserted again.
  ///
  /// The character data that the document keeps is the one of `<text>`,
  /// `<tspan>`, `<textPath>`, `<a>` and `<style>`. Other elements keep the
  /// character data that's set, but SVGUIView doesn't render it. Changing
  /// the character data of a `<style>` element makes the style sheets of the
  /// document again, which cascades every element again.
  ///
  /// ```swift
  /// label.textContent = "Score: \(score)"
  /// ```
  public var textContent: String {
    get { document.textContent(of: id) }
    nonmutating set { document.setTextContent(newValue, of: id) }
  }

  /// The parent of the element, or `nil` for the root element and for an
  /// element that isn't in another one.
  public var parent: SVGDocument.Element? {
    document.parent(of: id)
  }

  /// The child elements of the element, in document order.
  ///
  /// The children include the elements that SVGUIView doesn't render, such
  /// as `<style>` elements and animation elements.
  public var children: [SVGDocument.Element] {
    document.children(of: id)
  }

  /// Whether the element is in the tree of the document: whether it's the
  /// root element or one of its descendants.
  ///
  /// It's `false` for an element that ``SVGDocument/createElement(_:)``
  /// created and that wasn't inserted yet, for an element that was removed,
  /// and for their descendants.
  public var isConnected: Bool {
    document.isConnected(id)
  }

  /// Inserts an element after the last child of this element, as the DOM's
  /// `appendChild()` does.
  ///
  /// An element that has a parent is removed from it first, so appending an
  /// element moves it. An element is painted over the siblings before it, so
  /// appending an element to its own parent brings it to the front.
  ///
  /// - Parameter child: The element to insert, with its descendants.
  /// - Throws: ``SVGDocument/HierarchyError`` if the element is this element
  ///   or one of its ancestors, the root element of the document, or an
  ///   element of another document.
  public func append(_ child: SVGDocument.Element) throws(SVGDocument.HierarchyError) {
    try insert(child, before: nil)
  }

  /// Inserts an element before a child of this element, as the DOM's
  /// `insertBefore()` does.
  ///
  /// An element that has a parent is removed from it first, so inserting an
  /// element moves it.
  ///
  /// - Parameters:
  ///   - child: The element to insert, with its descendants.
  ///   - reference: The child of this element to insert the element before,
  ///     or `nil` to insert it after the last child.
  /// - Throws: ``SVGDocument/HierarchyError`` if the element is this element
  ///   or one of its ancestors, the root element of the document, or an
  ///   element of another document, or if `reference` isn't a child of this
  ///   element.
  public func insert(_ child: SVGDocument.Element, before reference: SVGDocument.Element?)
    throws(SVGDocument.HierarchyError)
  {
    guard child.document === document, reference.map({ $0.document === document }) ?? true else {
      throw SVGDocument.HierarchyError(reason: .differentDocument)
    }
    try document.insert(child.id, into: id, before: reference?.id)
  }

  /// Removes the element from its parent, with its descendants, as the DOM's
  /// `remove()` does.
  ///
  /// The document keeps the element, so it can be read, changed and inserted
  /// again. The root element, and an element without a parent, stay where
  /// they are.
  public func remove() {
    document.remove(id)
  }

  /// The first descendant of the element in document order that a list of
  /// selectors matches, or `nil` if there is none.
  ///
  /// The selectors match against the whole document, so they can match
  /// through the ancestors of this element.
  ///
  /// - Parameter selectors: CSS selectors, separated by commas.
  /// - Throws: ``SVGDocument/SelectorError`` if the selectors can't be parsed.
  public func querySelector(_ selectors: String) throws(SVGDocument.SelectorError) -> SVGDocument.Element? {
    try document.elements(matching: selectors, in: id).first
  }

  /// The descendants of the element that a list of selectors matches, in
  /// document order.
  ///
  /// The selectors match against the whole document, so they can match
  /// through the ancestors of this element.
  ///
  /// - Parameter selectors: CSS selectors, separated by commas.
  /// - Throws: ``SVGDocument/SelectorError`` if the selectors can't be parsed.
  public func querySelectorAll(_ selectors: String) throws(SVGDocument.SelectorError) -> [SVGDocument.Element] {
    try document.elements(matching: selectors, in: id)
  }

  /// The CSS animations that the element runs, in the order of its
  /// `animation-name`.
  public var animations: [SVGDocument.Animation] {
    document.animations.filter { $0.element == self }
  }

  /// Begins the SMIL animation of an animation element, such as
  /// `<animate>`, at the current time, as the DOM's `beginElement()` does.
  ///
  /// The animation begins whatever its `begin` attribute is, such as
  /// `indefinite` or an event that SVGUIView doesn't have, and as its
  /// `restart` attribute allows. Other elements do nothing.
  public func beginElement() {
    document.host?.beginSMILAnimation(id)
  }

  /// Ends the SMIL animation of an animation element at the current time, as
  /// the DOM's `endElement()` does. Other elements do nothing.
  public func endElement() {
    document.host?.endSMILAnimation(id)
  }

  /// The classes of the element, in its `class` attribute.
  public var classList: SVGDocument.ClassList {
    SVGDocument.ClassList(element: self)
  }

  /// The declarations of the element's `style` attribute.
  public var style: SVGDocument.Style {
    SVGDocument.Style(element: self)
  }

  /// The bounding box of the element in its user space, as the DOM's
  /// `getBBox()` finds it, or `nil` if it has none.
  ///
  /// The user space of the element is the coordinates that its own
  /// `transform` applies to, and those of the content of an `svg` element.
  /// ``transformToView()`` moves the box into the coordinates of the view:
  ///
  /// ```swift
  /// if let box = await shape.boundingBox(),
  ///   let transform = await shape.transformToView() {
  ///   selectionLayer.path = CGPath(rect: box, transform: [transform])
  /// }
  /// ```
  ///
  /// The box is the one of the document with every change made to it so far,
  /// at the time that the view displays. It includes the fill of the element,
  /// or of the elements in it, and with `includingStroke` their strokes
  /// without their dashes, as SVG 2 defines the object and stroke bounding
  /// boxes. The box of a container is the union of the boxes of the elements
  /// that it renders, each with its transform, and is zero for a container
  /// that renders none. An element that isn't rendered, such as one in a
  /// `defs` element or with `display: none`, has the box that it would have if
  /// it were rendered.
  ///
  /// The box of a `tspan` or `textPath` element, or of an `a` element in
  /// text, is the union of the cells of the glyphs of its characters and of
  /// the elements in it, as the box of a `text` element is, in the user space
  /// of its `text` element. Its stroke adds nothing to the box. It's zero for
  /// one that lays out no characters, such as one with `display: none`.
  ///
  /// It's `nil` for an element that the view doesn't show, because it isn't
  /// in the document's tree or the view no longer shows the document, and for
  /// an element that isn't a graphics element, such as a `mask` or a
  /// `pattern`. The geometry is found off the main actor, as a rendering is,
  /// so it's also `nil` if the task is cancelled.
  ///
  /// - Parameter includingStroke: Whether the box includes the strokes.
  public func boundingBox(includingStroke: Bool = false) async -> CGRect? {
    let geometry = await document.host?.geometry(of: id, includesStroke: includingStroke, includesPath: false)
    return includingStroke ? geometry?.strokeBoundingBox : geometry?.boundingBox
  }

  /// The shape of the element in its user space, or `nil` if it has none.
  ///
  /// The shape is the one that the element is filled with: the path of a
  /// `path` element or of a basic shape, such as a `rect` with its rounded
  /// corners, the outlines of the glyphs of a `text` element, the rectangle
  /// of an `image` element, and the shape of the element that a `use`
  /// element references, moved by its `x` and `y`. A `tspan` or `textPath`
  /// element has the outlines of the glyphs of its characters and of the
  /// elements in it, in the user space of its `text` element. Containers, such
  /// as `g` and `svg` elements, have no shape. It's in the coordinates of
  /// ``boundingBox(includingStroke:)``, and it's `nil` in the same cases.
  public func path() async -> CGPath? {
    await document.host?.geometry(of: id, includesStroke: false, includesPath: true)?.path?.cgPath
  }

  /// The transform from the user space of the element to the coordinates of
  /// the view that shows it, as the DOM's `getScreenCTM()` finds it for the
  /// view, or `nil` if the view doesn't show the element.
  ///
  /// It includes the element's own `transform`, the transforms of its
  /// ancestors, the view boxes of the `svg` elements that it's in, and how
  /// the view places the document with its `contentMode`, so it changes with
  /// the size and the content mode of the view. A `tspan` or `textPath`
  /// element has the transform of its `text` element. It's `nil` in the cases that
  /// ``boundingBox(includingStroke:)`` is.
  public func transformToView() async -> CGAffineTransform? {
    await document.host?.geometry(of: id, includesStroke: false, includesPath: false)?.transformToViewPort
  }

  /// Renders the element and its descendants into an image, as the view
  /// shows them at the time that it displays, and tells where the view
  /// shows the image.
  ///
  /// The image is for a stand-in that an app moves instead of the element,
  /// such as while a finger drags it, since the view shows a change of its
  /// document a frame or more after the app makes it:
  ///
  /// ```swift
  /// if let snapshot = try await shape.takeSnapshot() {
  ///   standIn.contents = snapshot.image
  ///   standIn.frame = snapshot.frame
  ///   svgView.layer.addSublayer(standIn)
  ///   shape.setAttribute("visibility", to: "hidden")
  /// }
  /// ```
  ///
  /// The image has the element's own `transform`, clip path, mask, opacity
  /// and filter, and its descendants. It has the transforms of the
  /// ancestors, the view boxes of the `svg` elements that the element is in,
  /// and how the view places the document with its `contentMode`, but not
  /// the opacities, clip paths, masks and filters of the ancestors, the
  /// clips of the `svg` elements around it, or the other elements, so that
  /// the stand-in is the element alone. The changes that the view hasn't
  /// rendered yet are in the image.
  ///
  /// The image covers what the element paints, out to whole pixels of the
  /// view with a margin for the antialiased edges, also where it's outside
  /// the view, and a filter region only where the view shows it. The image
  /// is transparent where the element doesn't paint.
  ///
  /// It's `nil` for an element that the view doesn't render, because it
  /// isn't in the document's tree, it's in a `defs` element or has
  /// `display: none`, it isn't a graphics element, or the view no longer
  /// shows the document, and for an element that paints nothing, such as one
  /// with `visibility: hidden`.
  ///
  /// - Parameter scale: The number of pixels in a point of the image. Pass
  ///   `nil` to use the scale of the view's screen.
  /// - Returns: The image and where the view shows it, or `nil`.
  /// - Throws: The errors that ``SVGUIView/takeSnapshot(rect:at:scale:)``
  ///   throws.
  public func takeSnapshot(scale: CGFloat? = nil) async throws(SVGRenderingError) -> SVGDocument.ElementSnapshot? {
    guard let host = document.host else { return nil }
    return try await host.snapshot(of: id, scale: scale)
  }
}

extension SVGDocument {
  /// An image of an element and its descendants, and where the view shows
  /// it, which ``Element/takeSnapshot(scale:)`` renders.
  public struct ElementSnapshot: Sendable {
    /// The image, whose width and height in pixels are those of the frame
    /// times the scale that it's rendered at.
    public let image: CGImage
    /// The rectangle in the coordinates of the view that the image covers,
    /// whose edges lie on the pixels of the view at the scale.
    public let frame: CGRect
  }
}

extension SVGDocument {
  /// The classes of an element, which its `class` attribute lists.
  ///
  /// Changing the classes writes the `class` attribute again with each class
  /// once, in order, separated by spaces. A name that is empty or contains
  /// whitespace is never a class, so ``contains(_:)`` returns `false` for it,
  /// and the methods that change the classes ignore it.
  public struct ClassList: Sendable {
    let element: Element
  }
}

@MainActor
extension SVGDocument.ClassList {
  /// The classes in order, each once.
  public var names: [String] {
    var seen = Set<String>()
    return (element.attribute("class") ?? "").split(whereSeparator: Self.isWhitespace).map(String.init).filter {
      seen.insert($0).inserted
    }
  }

  /// Whether the element has a class.
  public func contains(_ name: String) -> Bool {
    Self.isValid(name) && names.contains(name)
  }

  /// Adds classes that the element doesn't have, at the end.
  public func add(_ names: String...) {
    update(self.names + names.filter(Self.isValid))
  }

  /// Removes classes.
  public func remove(_ names: String...) {
    let removed = Set(names)
    update(self.names.filter { !removed.contains($0) })
  }

  /// Adds a class if the element doesn't have it, and removes it otherwise.
  ///
  /// - Parameters:
  ///   - name: The name of the class.
  ///   - force: `true` to only add the class, `false` to only remove it, or
  ///     `nil` to add or remove it.
  /// - Returns: Whether the element has the class afterwards.
  @discardableResult
  public func toggle(_ name: String, force: Bool? = nil) -> Bool {
    guard Self.isValid(name) else { return false }
    let adds = force ?? !contains(name)
    if adds {
      add(name)
    } else {
      remove(name)
    }
    return adds
  }

  /// Writes the `class` attribute with the classes, each once, as the DOM does, except for an element without the
  /// attribute and without classes.
  private func update(_ names: [String]) {
    var seen = Set<String>()
    let text = names.filter { seen.insert($0).inserted }.joined(separator: " ")
    let current = element.attribute("class")
    guard current != text, current != nil || !text.isEmpty else { return }
    element.setAttribute("class", to: text)
  }

  private static func isValid(_ name: String) -> Bool {
    !name.isEmpty && !name.contains(where: isWhitespace)
  }

  /// Whether a character is ASCII whitespace, which separates the names of classes.
  private static func isWhitespace(_ character: Character) -> Bool {
    " \t\n\r\u{0C}".contains(character)
  }
}

extension SVGDocument {
  /// The declarations of an element's `style` attribute.
  ///
  /// A declaration has the name of a property and its value as text. Changing
  /// a declaration writes the `style` attribute again, and keeps the other
  /// declarations as they're written. Values aren't checked: a value that
  /// SVGUIView can't parse is ignored when the document is rendered, as it is
  /// when the document is written with it.
  public struct Style: Sendable {
    let element: Element

    /// Whether a declaration is important, which makes it win over style
    /// sheets and animations.
    public enum Priority: Sendable {
      case normal
      case important
    }
  }
}

@MainActor
extension SVGDocument.Style {
  /// The value of a property as written, or `nil` if the attribute doesn't
  /// declare it.
  ///
  /// - Parameter name: The name of the property, such as `fill`.
  public func property(_ name: String) -> String? {
    declarations.declaration(named: name)?.value
  }

  /// The priority of the declaration of a property, or `nil` if the attribute
  /// doesn't declare it.
  public func priority(_ name: String) -> Priority? {
    declarations.declaration(named: name).map { $0.isImportant ? .important : .normal }
  }

  /// Declares the value of a property, in the place of its declaration if it
  /// has one.
  ///
  /// - Parameters:
  ///   - name: The name of the property, such as `fill`.
  ///   - value: The value, such as `red`, without `!important`.
  ///   - priority: Whether the declaration is important.
  public func setProperty(_ name: String, to value: String, priority: Priority = .normal) {
    var declarations = declarations
    declarations.set(name, to: value, isImportant: priority == .important)
    element.setAttribute("style", to: declarations.text)
  }

  /// Removes the declaration of a property.
  public func removeProperty(_ name: String) {
    var declarations = declarations
    guard declarations.declaration(named: name) != nil else { return }
    declarations.remove(name)
    element.setAttribute("style", to: declarations.text)
  }

  private var declarations: StyleDeclarations {
    StyleDeclarations(element.attribute("style") ?? "")
  }
}

extension SVGDocument {
  /// A CSS animation that an element runs, in the terms of Web Animations.
  ///
  /// An animation plays on the timeline of the view, from the time that the
  /// element starts running it: the time that the document was loaded, or the
  /// time of the change that makes the element run it. Pausing, playing,
  /// moving and changing the rate of an animation change how it plays from the
  /// time that the view displays. A view whose
  /// ``SVGUIViewConfiguration/animation`` is
  /// ``SVGUIViewConfiguration/AnimationMode/none`` displays time zero, so an
  /// animation doesn't advance there, but moving it shows it at another time.
  ///
  /// An animation that the element no longer runs, such as after its class is
  /// removed, does nothing.
  public struct Animation: Hashable, Sendable {
    /// The element that runs the animation.
    public let element: Element
    let id: CSSAnimationID

    /// The name of the animation, which `animation-name` gives.
    public var animationName: String {
      id.name
    }
  }
}

@MainActor
extension SVGDocument.Animation {
  /// The time of the animation, or `nil` if the element no longer runs it.
  ///
  /// The time is zero when the animation starts, before its delay. Setting
  /// it moves the animation to the time.
  public var currentTime: Duration? {
    get {
      host?.playback(of: id).map { .seconds($0.playback.localTime(at: $0.time)) }
    }
    nonmutating set {
      guard let newValue else { return }
      host?.changePlayback(of: id) { $0.seek(to: newValue.seconds, at: $1) }
    }
  }

  /// How fast the animation plays, which is 1 by default and negative to
  /// play backward.
  public var playbackRate: Double {
    get {
      host?.playback(of: id)?.playback.rate ?? 1
    }
    nonmutating set {
      host?.changePlayback(of: id) { $0.setRate(newValue, at: $1) }
    }
  }

  /// Whether the animation is paused, by ``pause()`` or by
  /// `animation-play-state`.
  public var isPaused: Bool {
    host?.playback(of: id)?.playback.isPaused ?? false
  }

  /// Plays the animation from the time that it's paused at.
  public func play() {
    host?.changePlayback(of: id) { $0.play(at: $1) }
  }

  /// Holds the animation at its current time.
  public func pause() {
    host?.changePlayback(of: id) { $0.pause(at: $1) }
  }

  /// Waits until the animation finishes: until it reaches its end, or its
  /// start when it plays backward.
  ///
  /// This also returns when the element no longer runs the animation, the
  /// view no longer shows the document, or the task that waits is cancelled.
  /// It returns at once for an animation that has finished, or in a task that
  /// is cancelled.
  public func finished() async {
    await host?.waitUntilFinished(id)
  }

  private var host: (any DocumentHost)? {
    element.document.host
  }
}
