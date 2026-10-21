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
  private var values: [PropertyID: any Sendable] = [:]

  init() {}

  /// Cascaded values with the given declarations applied in order, so that a later declaration wins.
  init(_ declarations: [PropertyDeclaration]) {
    for declaration in declarations {
      values[declaration.id] = declaration.value
    }
  }

  subscript<P: StyleProperty>(_: P.Type) -> Declared<P.Specified>? {
    values[P.id] as? Declared<P.Specified>
  }

  var isEmpty: Bool {
    values.isEmpty
  }

  /// The declarations of the presentation attributes of an element.
  static func presentationAttributes(
    of name: SVGElementName, attributes: [String: String]
  ) -> [PropertyDeclaration] {
    PropertyID.allCases.compactMap { id in
      guard let text = attributes[id.rawValue] else { return nil }
      return declaration(id.property, name: name, attribute: text)
    }
  }

  private static func declaration<P: StyleProperty>(
    _: P.Type, name: SVGElementName, attribute text: String
  ) -> PropertyDeclaration? {
    guard P.accepts(attributeOn: name), let value = P.declared(attribute: text) else { return nil }
    return PropertyDeclaration(P.self, value)
  }
}
