import Foundation

/// A declaration of a property, from a presentation attribute, a style sheet or the `style` attribute.
struct PropertyDeclaration: Sendable {
  let id: PropertyID
  /// The declared value, a ``Declared`` of the property's specified value.
  let value: any Sendable

  init<P: StyleProperty>(_: P.Type, _ value: Declared<P.Specified>) {
    id = P.id
    self.value = value
  }
}

/// The value that wins the cascade for each property that an element declares.
struct CascadedValues: Sendable {
  /// The declarations that win, one for each property. An element declares few properties, so searching them is
  /// faster than hashing the names of the properties.
  private var values: [PropertyDeclaration] = []
  /// The properties whose declarations that win are important, which animations don't override.
  let important: Set<PropertyID>

  init() {
    important = []
  }

  /// Cascaded values with the given declarations applied in order, so that a later declaration wins.
  ///
  /// - Parameter important: The properties whose declarations that win are important.
  init(_ declarations: [PropertyDeclaration], important: Set<PropertyID> = []) {
    self.important = important
    for declaration in declarations {
      if let index = values.firstIndex(where: { $0.id == declaration.id }) {
        values[index] = declaration
      } else {
        values.append(declaration)
      }
    }
  }

  /// The properties that have declarations.
  var properties: [PropertyID] {
    values.map(\.id)
  }

  subscript<P: StyleProperty>(_: P.Type) -> Declared<P.Specified>? {
    values.first { $0.id == P.id }?.value as? Declared<P.Specified>
  }

  /// The value that the element declares for the property, or `nil` if it declares none or a keyword.
  func declared<P: StyleProperty>(_: P.Type) -> P.Specified? {
    if case .value(let value) = self[P.self] { value } else { nil }
  }

  /// The declarations of the user agent's style sheet for an element, which every other declaration overrides.
  ///
  /// SVG 2 hides the overflow of the elements that establish viewports, except the root element.
  static func userAgentDeclarations(of name: SVGElementName, isRoot: Bool) -> [PropertyDeclaration] {
    switch name {
    case .svg where !isRoot, .image, .marker, .pattern: [PropertyDeclaration(OverflowProperty.self, .value(.hidden))]
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
    guard P.accepts(attributeOn: name), let value = P.declared(attribute: text) else { return nil }
    return PropertyDeclaration(P.self, value)
  }
}
