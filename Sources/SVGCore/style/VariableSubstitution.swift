import Foundation
import _CSSParser

/// Whether the text of a value has `var()`, which CSS Variables 1 substitutes when the value is computed.
func containsVariable(_ text: String) -> Bool {
  // The bytes are compared without Foundation, since every presentation attribute is checked.
  var utf8 = text.utf8.makeIterator()
  var matched = 0
  let pattern: [UInt8] = [UInt8(ascii: "v"), UInt8(ascii: "a"), UInt8(ascii: "r"), UInt8(ascii: "(")]
  while let byte = utf8.next() {
    let lowered = byte >= UInt8(ascii: "A") && byte <= UInt8(ascii: "Z") ? byte + 32 : byte
    if lowered == pattern[matched] {
      matched += 1
      if matched == pattern.count { return true }
    } else {
      matched = lowered == pattern[0] ? 1 : 0
    }
  }
  return false
}

/// The substitution of custom properties for `var()` in values, as CSS Variables 1 does it.
enum VariableSubstitution {
  /// The longest text that a substitution makes. A longer one is invalid, which keeps values that refer to each other
  /// from growing exponentially, as CSS Variables 1 allows.
  static let maximumLength = 1 << 16

  /// The text with each `var()` replaced by the value of its custom property, or by its fallback if the element has
  /// no value for it, or `nil` if a `var()` has neither or the text is too long.
  ///
  /// - Parameter value: The value of a custom property by its name, or `nil` if the element has none.
  static func substituted(_ text: String, value: (String) -> String?) -> String? {
    var parser = _CSSParser.Parser(input: ParserInput(input: text))
    var result = ""
    guard substitute(&parser, into: &result, value: value), result.utf8.count <= maximumLength else { return nil }
    return result.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  /// Copies the text of the tokens to the end of the parser's input, or of its block, with each `var()` replaced,
  /// and returns whether every `var()` has a value.
  private static func substitute(
    _ parser: inout _CSSParser.Parser, into result: inout String, value: (String) -> String?
  ) -> Bool {
    var segmentStart = parser.position
    var isValid = true
    while true {
      let before = parser.position
      guard case .success(let token) = parser.nextIncludingWhitespaceAndComments() else { break }
      switch token {
      case .function(let name) where name.lowercased() == "var":
        result += parser.slice(range: segmentStart..<before)
        let reference = parser.parseNestedBlock { input -> Result<String?, ParseError<Never>> in
          .success(Self.variable(&input, value: value))
        }
        guard case .success(let substitution?) = reference else {
          isValid = false
          segmentStart = parser.position
          continue
        }
        append(substitution, to: &result)
        segmentStart = parser.position
        // The text after the value is kept apart from it too.
        if let last = substitution.last, let next = parser.slice(from: segmentStart).first, joins(last, next) {
          result += "/**/"
        }
      case .function, .parenthesisBlock, .squareBracketBlock, .curlyBracketBlock:
        // The block is copied around its contents, which can have `var()` too.
        result += parser.slice(range: segmentStart..<parser.position)
        var end = parser.position
        let contents = parser.parseNestedBlock { input -> Result<Bool, ParseError<Never>> in
          let isValid = Self.substitute(&input, into: &result, value: value)
          end = input.position
          return .success(isValid)
        }
        if case .success(false) = contents { isValid = false }
        // The closing bracket, which an unclosed block at the end of the text doesn't have.
        result += parser.slice(range: end..<parser.position)
        segmentStart = parser.position
      default:
        continue
      }
      if result.utf8.count > maximumLength { return false }
    }
    result += parser.slice(from: segmentStart)
    return isValid
  }

  /// The value that the arguments of a `var()` give: the value of its custom property, or its fallback with its own
  /// `var()` replaced, or `nil` if it has neither or the arguments are invalid.
  private static func variable(_ input: inout _CSSParser.Parser, value: (String) -> String?) -> String? {
    guard case .success(.ident(let name)) = input.next(), name.hasPrefix("--") else { return nil }
    let afterName = input.state
    switch input.next() {
    case .failure:
      return value(name)
    case .success(.comma):
      // The fallback is the rest of the arguments, which can be empty. It's substituted only if it's used, but its
      // references count as references of the value either way, for cycles.
      var fallback = ""
      let isValid = substitute(&input, into: &fallback, value: value)
      if let found = value(name) { return found }
      guard isValid else { return nil }
      return fallback.trimmingCharacters(in: .whitespacesAndNewlines)
    case .success:
      input.reset(state: afterName)
      return nil
    }
  }

  /// Appends a substituted value, with an empty comment between it and the text before it where they would otherwise
  /// run together into other tokens, since a substitution keeps the tokens of the value apart, as browsers serialize
  /// them.
  private static func append(_ value: String, to result: inout String) {
    if let last = result.last, let first = value.first, joins(last, first) { result += "/**/" }
    result += value
  }

  /// Whether two characters next to each other can be in the same token, such as the number and the unit of a
  /// dimension.
  private static func joins(_ a: Character, _ b: Character) -> Bool {
    func isWord(_ c: Character) -> Bool { c.isLetter || c.isNumber || c == "-" || c == "_" || c == "." || c == "%" }
    return isWord(a) && isWord(b)
  }

  /// The computed values of the custom properties of an element: the values that it declares, with their `var()`
  /// replaced, over the values of its parent, which they inherit.
  ///
  /// The custom properties that refer to each other in a cycle, directly or through others, are invalid at
  /// computed-value time, and take the guaranteed-invalid value, which is no value, as CSS Variables 1 says. So does
  /// a value whose `var()` has no value and no fallback, and the keyword `initial`.
  ///
  /// - Parameter animated: The values that animations give to the custom properties, which override the declared
  ///   ones, with `nil` for the guaranteed-invalid value.
  static func computedCustomProperties(
    declared: [(name: String, value: Declared<String>)], parent: [String: String],
    animated: [String: String?] = [:]
  ) -> [String: String] {
    var specified = [String: String?]()
    for (name, value) in declared {
      switch value {
      case .value(let text): specified[name] = .some(text)
      case .initial: specified[name] = .some(nil)
      case .inherit, .unset: specified[name] = .some(parent[name])
      }
    }
    for (name, value) in animated { specified[name] = .some(value) }
    guard !specified.isEmpty else { return parent }
    var computed = parent
    var states = [String: Bool]()  // false while it's being resolved, and true once it's done.
    var stack = [String]()
    var cyclic = Set<String>()
    func resolve(_ name: String) -> String? {
      guard let entry = specified[name] else { return parent[name] }
      if let done = states[name] {
        if done { return computed[name] }
        // A cycle: every property on the stack from this one is in it.
        if let index = stack.lastIndex(of: name) { cyclic.formUnion(stack[index...]) }
        return nil
      }
      guard let text = entry else {
        states[name] = true
        computed[name] = nil
        return nil
      }
      guard containsVariable(text) else {
        states[name] = true
        computed[name] = text
        return text
      }
      states[name] = false
      stack.append(name)
      let value = substituted(text, value: resolve)
      stack.removeLast()
      states[name] = true
      computed[name] = cyclic.contains(name) ? nil : value
      return computed[name]
    }
    for name in specified.keys.sorted() {
      _ = resolve(name)
    }
    return computed
  }
}

extension UnparsedValue {
  /// The declared value of a property that the value sets, with the custom properties substituted, or `unset` if the
  /// value isn't valid after the substitution, which CSS Variables 1 calls invalid at computed-value time.
  func declared<P: StyleProperty>(_: P.Type, customProperties: [String: String]) -> Declared<P.Specified> {
    guard let text = VariableSubstitution.substituted(text, value: { customProperties[$0] }) else { return .unset }
    // A length of a geometry property that `var()` gives needs a unit, as in Chrome and Firefox, also for a
    // presentation attribute, which takes a number without one otherwise.
    if P.self is any GeometryLengthProperty.Type, Self.isNumberWithoutUnit(text) { return .unset }
    var input = _CSSParser.Parser(input: ParserInput(input: text))
    let declarations = input.parseEntirely { input -> Result<[PropertyDeclaration], ParseError<Never>> in
      CSSDeclarationParser.propertyDeclarations(shorthand ?? P.id.rawValue, input: &input).map { .success($0) }
        ?? .failure(input.newError(kind: .endOfInput))
    }
    guard case .success(let declarations) = declarations,
      let value = declarations.first(where: { $0.name == .property(P.id) })?.value as? Declared<P.Specified>
    else { return .unset }
    return value
  }
}

extension CascadedValues {
  /// The declared value of the property, with the custom properties substituted for a value with `var()`.
  func declared<P: StyleProperty>(_: P.Type, customProperties: [String: String]) -> Declared<P.Specified>? {
    if let declared = self[P.self] { return declared }
    return unparsed(P.id)?.declared(P.self, customProperties: customProperties)
  }
}

extension UnparsedValue {
  /// Whether the text is one number other than 0, without a unit.
  fileprivate static func isNumberWithoutUnit(_ text: String) -> Bool {
    var input = _CSSParser.Parser(input: ParserInput(input: text))
    guard case .success(.number(let number)) = input.next(), input.isExhausted() else { return false }
    return number.value != 0
  }
}
