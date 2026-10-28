import SVGCore

/// The document that a view displays, which an app reads and changes from Swift.
///
/// The API follows the DOM where it fits Swift. Find elements with
/// ``element(id:)``, ``querySelector(_:)`` and ``querySelectorAll(_:)``, and
/// change their attributes, their classes and the declarations of their
/// `style` attributes. A change is visible at once to the methods that read the
/// document, and the view shows it at its next rendering. The changes made in
/// one turn of the run loop are rendered together.
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
/// CSS animations that a change starts, such as ones that a new class sets,
/// play on the timeline of the document, so they run as if they started when
/// the document was loaded.
@MainActor
public final class SVGDocument {
  /// The tree of the document with every change, which reading the document sees.
  private var tree: DocumentTree
  /// The changes that the view hasn't rendered yet, by the elements and the names of the attributes, with `nil` for an
  /// attribute that is removed.
  private var changes = [ElementID: [String: String?]]()
  /// Tells the view that shows the document that it has changed.
  var onChange: (() -> Void)?

  init(tree: DocumentTree) {
    self.tree = tree
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
  /// A selector with a pseudo-class that depends on user actions or on the
  /// language, such as `:hover` or `:lang()`, matches no element.
  ///
  /// - Parameter selectors: CSS selectors, separated by commas.
  /// - Throws: ``SelectorError`` if the selectors can't be parsed.
  public func querySelectorAll(_ selectors: String) throws(SelectorError) -> [Element] {
    try elements(matching: selectors, in: nil)
  }

  /// Takes the changes that the view hasn't rendered yet.
  func takeChanges() -> [ElementID: [String: String?]] {
    defer { changes = [:] }
    return changes
  }

  fileprivate func elements(matching selectors: String, in scope: ElementID?) throws(SelectorError) -> [Element] {
    do {
      return try tree.elements(matching: selectors, in: scope).map { Element(document: self, id: $0) }
    } catch {
      throw SelectorError(selectors: error.selectors)
    }
  }

  fileprivate func localName(of id: ElementID) -> String {
    tree.localName(of: id) ?? ""
  }

  fileprivate func attribute(_ name: String, of id: ElementID) -> String? {
    tree.attributes(of: id)?[Self.attributeName(name)]
  }

  /// Sets or removes an attribute, unless it already has the value.
  fileprivate func setAttribute(_ name: String, to value: String?, of id: ElementID) {
    let name = Self.attributeName(name)
    guard let attributes = tree.attributes(of: id), attributes[name] != value else { return }
    tree = tree.changingAttributes([id: [name: value]])
    changes[id, default: [:]][name] = .some(value)
    onChange?()
  }

  /// The name of an attribute as the document keeps it, which keeps `href` of the XLink namespace as `href`.
  private static func attributeName(_ name: String) -> String {
    name == "xlink:href" ? "href" : name
  }
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
  ///   `href` of the XLink namespace can also be named `xlink:href`.
  public func attribute(_ name: String) -> String? {
    document.attribute(name, of: id)
  }

  /// Sets the value of an attribute.
  ///
  /// - Parameters:
  ///   - name: The name of the attribute, without a namespace. The `href` of
  ///     the XLink namespace can also be named `xlink:href`.
  ///   - value: The value, as it would be written in the document.
  public func setAttribute(_ name: String, to value: String) {
    document.setAttribute(name, to: value, of: id)
  }

  /// Removes an attribute.
  ///
  /// - Parameter name: The name of the attribute, without a namespace. The
  ///   `href` of the XLink namespace can also be named `xlink:href`.
  public func removeAttribute(_ name: String) {
    document.setAttribute(name, to: nil, of: id)
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

  /// The classes of the element, in its `class` attribute.
  public var classList: SVGDocument.ClassList {
    SVGDocument.ClassList(element: self)
  }

  /// The declarations of the element's `style` attribute.
  public var style: SVGDocument.Style {
    SVGDocument.Style(element: self)
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
