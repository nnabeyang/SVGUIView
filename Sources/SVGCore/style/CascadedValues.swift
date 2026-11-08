import Foundation

/// A declaration of a property, from a presentation attribute, a style sheet or the `style` attribute.
struct PropertyDeclaration: Sendable {
  /// The property that the declaration sets.
  enum Name: Hashable, Sendable {
    case property(PropertyID)
    /// A custom property, by its name with the leading `--`, which is case-sensitive.
    case custom(String)
  }

  /// The property that the declaration sets, or `nil` for a custom property. It's kept apart from the name of a
  /// custom property, since the cascade compares the properties of every element.
  let id: PropertyID?
  /// The name of the custom property that the declaration sets, or `nil` for another property.
  let customName: String?
  /// The declared value: a ``Declared`` of the property's specified value, an ``UnparsedValue`` of a value with
  /// `var()`, or a ``Declared`` of the text of a custom property.
  let value: any Sendable
  /// Whether the value is an ``UnparsedValue``.
  let isUnparsed: Bool
  /// Whether the declaration of a custom property is important, which animations don't override. The cascade keeps
  /// the importance of the other properties apart.
  var isImportant = false

  var name: Name {
    if let id { .property(id) } else { .custom(customName ?? "") }
  }

  init<P: StyleProperty>(_: P.Type, _ value: Declared<P.Specified>) {
    id = P.id
    customName = nil
    self.value = value
    isUnparsed = false
  }

  /// The declaration of a value with `var()`, which is parsed when the value is computed.
  init(_ id: PropertyID, unparsed value: UnparsedValue) {
    self.id = id
    customName = nil
    self.value = value
    isUnparsed = true
  }

  /// The declaration of a custom property.
  init(custom name: String, _ value: Declared<String>) {
    id = nil
    customName = name
    self.value = value
    isUnparsed = false
  }

  /// Whether two declarations set the same property.
  func setsSameProperty(as other: PropertyDeclaration) -> Bool {
    id == other.id && customName == other.customName
  }
}

/// The value of a declaration that has `var()`, which CSS Variables 1 parses only when the element's custom
/// properties are known, after it substitutes them.
struct UnparsedValue: Sendable, Equatable {
  /// The text of the value.
  let text: String
  /// The shorthand that the declaration sets, whose value the text is, or `nil` for a longhand.
  let shorthand: String?
}

/// The value that wins the cascade for each property that an element declares.
struct CascadedValues: Sendable {
  /// The declarations that win, one for each property. An element declares few properties, so searching them is
  /// faster than hashing the names of the properties.
  private var values: [PropertyDeclaration] = []
  /// The properties whose declarations that win are important, which animations don't override.
  let important: Set<PropertyID>
  /// Whether a declaration that wins has `var()`, or sets a custom property.
  private(set) var hasVariables = false

  init() {
    important = []
  }

  /// Cascaded values with the given declarations applied in order, so that a later declaration wins.
  ///
  /// - Parameter important: The properties whose declarations that win are important.
  init(_ declarations: [PropertyDeclaration], important: Set<PropertyID> = []) {
    self.important = important
    for declaration in declarations {
      if let index = values.firstIndex(where: { $0.setsSameProperty(as: declaration) }) {
        values[index] = declaration
      } else {
        values.append(declaration)
      }
    }
    hasVariables = values.contains { $0.id == nil || $0.isUnparsed }
  }

  /// The properties that have declarations, without the custom properties.
  var properties: [PropertyID] {
    values.compactMap(\.id)
  }

  /// The declared values of the custom properties, in the order of their declarations.
  var customProperties: [(name: String, value: Declared<String>)] {
    guard hasVariables else { return [] }
    return values.compactMap { declaration in
      guard let name = declaration.customName, let value = declaration.value as? Declared<String> else { return nil }
      return (name, value)
    }
  }

  /// Whether the declaration of the custom property that wins is important.
  func isImportant(customProperty name: String) -> Bool {
    hasVariables && values.contains { $0.customName == name && $0.isImportant }
  }

  subscript<P: StyleProperty>(_: P.Type) -> Declared<P.Specified>? {
    values.first { if case P.id? = $0.id { true } else { false } }?.value as? Declared<P.Specified>
  }

  /// The value with `var()` that the element declares for the property, or `nil` if it declares none.
  func unparsed(_ id: PropertyID) -> UnparsedValue? {
    guard hasVariables else { return nil }
    return values.first { if case id? = $0.id { true } else { false } }?.value as? UnparsedValue
  }

  /// The value that the element declares for the property, or `nil` if it declares none or a keyword.
  func declared<P: StyleProperty>(_: P.Type) -> P.Specified? {
    if case .value(let value) = self[P.self] { value } else { nil }
  }

  /// The cascaded values with declarations of the user agent's style sheet under them: each one applies only if no
  /// declaration of its property wins already.
  func addingUserAgentDeclarations(_ declarations: [PropertyDeclaration]) -> CascadedValues {
    var cascaded = self
    for declaration in declarations where !cascaded.values.contains(where: { $0.setsSameProperty(as: declaration) }) {
      cascaded.values.append(declaration)
    }
    return cascaded
  }

  /// The declarations of the user agent's style sheet for an `<svg>` element that a `<use>` element shows, at the top
  /// of the tree that it shows. SVG 2 sets `transform-origin: 0 0` only for the `<svg>` elements that have parents,
  /// and the one at the top of the tree of a `<use>` element has none, so its transform origin is the center of its
  /// box, as it is for the root element.
  static var userAgentDeclarationsOfInstanceRoot: [PropertyDeclaration] {
    [PropertyDeclaration(TransformOriginProperty.self, .value(TransformOrigin(x: .percent(50), y: .percent(50))))]
  }

  /// The declarations of the user agent's style sheet for an element, which every other declaration overrides.
  ///
  /// SVG 2 hides the overflow of the elements that establish viewports, except the root element. The root element is
  /// a box of CSS layout, whose transform origin is its center, as SVG 2 sets `transform-origin: 0 0` only for the
  /// other `<svg>` elements.
  static func userAgentDeclarations(of name: SVGElementName, isRoot: Bool) -> [PropertyDeclaration] {
    switch name {
    case .svg where isRoot:
      [PropertyDeclaration(TransformOriginProperty.self, .value(TransformOrigin(x: .percent(50), y: .percent(50))))]
    case .svg, .symbol, .image, .marker, .pattern:
      [PropertyDeclaration(OverflowProperty.self, .value(.hidden))]
    default: []
    }
  }

  /// The declarations of the presentation attributes of an element.
  static func presentationAttributes(
    of name: SVGElementName, attributes: [String: String]
  ) -> [PropertyDeclaration] {
    // Each property has one attribute, so the order of the attributes doesn't change the cascaded values.
    let declarations = attributes.compactMap { attribute, text -> PropertyDeclaration? in
      guard let id = PropertyID(rawValue: attribute) else { return nil }
      var declarator = AttributeDeclarator(name: name, text: text)
      return id.visit(&declarator)
    }
    // SVG 2 maps `xml:space` to `white-space` in the user agent's style sheet, so that the `white-space` attribute
    // and style sheets override it.
    let whiteSpace: CSSWhiteSpace? =
      switch attributes["xml:space"] {
      case "preserve": .pre
      case "default": .normal
      default: nil
      }
    return whiteSpace.map { [PropertyDeclaration(WhiteSpaceProperty.self, .value($0))] + declarations } ?? declarations
  }
}

/// Makes the declaration of a presentation attribute.
private struct AttributeDeclarator: StylePropertyVisitor {
  let name: SVGElementName
  let text: String

  func visit<P: StyleProperty>(_: P.Type) -> PropertyDeclaration? {
    guard P.accepts(attributeOn: name) else { return nil }
    // A value with `var()` is read as CSS once the custom properties are substituted, as browsers read it.
    if containsVariable(text) { return PropertyDeclaration(P.id, unparsed: UnparsedValue(text: text, shorthand: nil)) }
    guard let value = P.declared(attribute: text) else { return nil }
    return PropertyDeclaration(P.self, value)
  }
}
