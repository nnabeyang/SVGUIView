import _CSSParser

/// The declarations of a `style` attribute as text, which the document API reads and changes.
///
/// A declaration keeps its value as written, so that changing one declaration leaves the others as they are. The
/// values aren't checked: the cascade ignores the ones that it can't parse, as it does for the `style` attribute as
/// written.
package struct StyleDeclarations: Equatable, Sendable {
  /// A declaration with the name of its property in lowercase, and its value as written without `!important`.
  package struct Declaration: Equatable, Sendable {
    package let name: String
    package let value: String
    package let isImportant: Bool
  }

  /// The declarations in order. Of declarations with the same name, only the last one is kept, which is the one that
  /// the cascade uses.
  package private(set) var declarations: [Declaration]

  /// The declarations of the text of a `style` attribute. A declaration that isn't a name, a colon and a value is
  /// left out.
  package init(_ text: String) {
    declarations = []
    var input = Parser(input: ParserInput(input: text))
    while !input.isExhausted() {
      let result: Result<Declaration, ParseError<Never>> = input.parseUntilAfter(delimiters: .semicolon) { input in
        let name: String
        switch input.expectIdent() {
        case .success(let ident): name = ident
        case .failure(let error): return .failure(error.into())
        }
        if case .failure(let error) = input.expectColon() { return .failure(error.into()) }
        let start = input.position
        _ = input.parseUntilBefore(delimiters: .bang) { input -> Result<Void, ParseError<Never>> in
          while case .success = input.next() {}
          return .success(())
        }
        let value = input.slice(from: start).trimmingCharacters(in: .whitespacesAndNewlines)
        var isImportant = false
        if case .success = input.expectDelim(expectedValue: "!") {
          guard case .success = input.expectIdentMatching(expectedValue: "important") else {
            return .failure(input.newError(kind: .endOfInput))
          }
          isImportant = true
        }
        guard !value.isEmpty, case .success = input.expectExhausted() else {
          return .failure(input.newError(kind: .endOfInput))
        }
        return .success(Declaration(name: Self.normalized(name), value: value, isImportant: isImportant))
      }
      if case .success(let declaration) = result {
        declarations.removeAll { $0.name == declaration.name }
        declarations.append(declaration)
      }
    }
  }

  /// The text of a `style` attribute with the declarations, separated by semicolons.
  package var text: String {
    declarations.map { "\($0.name): \($0.value)\($0.isImportant ? " !important" : "")" }.joined(separator: "; ")
  }

  /// The declaration of a property, or `nil` if there is none.
  package func declaration(named name: String) -> Declaration? {
    let name = Self.normalized(name)
    return declarations.last { $0.name == name }
  }

  /// Sets the value of a property, in the place of its declaration if it has one, and at the end otherwise.
  package mutating func set(_ name: String, to value: String, isImportant: Bool) {
    let declaration = Declaration(
      name: Self.normalized(name), value: value.trimmingCharacters(in: .whitespacesAndNewlines),
      isImportant: isImportant)
    if let index = declarations.firstIndex(where: { $0.name == declaration.name }) {
      declarations[index] = declaration
    } else {
      declarations.append(declaration)
    }
  }

  /// Removes the declaration of a property.
  package mutating func remove(_ name: String) {
    let name = Self.normalized(name)
    declarations.removeAll { $0.name == name }
  }

  /// The name of a property in lowercase, which is how properties are named, except custom properties.
  private static func normalized(_ name: String) -> String {
    name.hasPrefix("--") ? name : name.lowercased()
  }
}
