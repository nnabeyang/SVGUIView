import _CSSParser

@testable import _SelectorParser

struct DummyAtom {
  let value: String
}

extension DummyAtom: From {
  typealias From = String
  static func from(_ string: String) -> Self {
    Self(value: string)
  }
}

extension DummyAtom: ExpressibleByStringLiteral {
  init(stringLiteral value: String) {
    self.value = value
  }
}

extension DummyAtom: ToCSS {
  func toCSS(to dest: inout some TextOutputStream) {
    serializeIdentifier(value, dest: &dest)
  }
}

extension DummyAtom: Default {
  static func `default`() -> Self {
    Self(value: "")
  }
}

extension DummyAtom: Hashable {}

struct DummyAttrValue: Equatable {
  let value: String
}

extension DummyAttrValue: ExpressibleByStringLiteral {
  init(stringLiteral value: String) {
    self.value = value
  }
}

extension DummyAttrValue: ToCSS {
  func toCSS(to dest: inout some TextOutputStream) {
    dest.write("\"")
    var writer = CssStringWriter(&dest)
    writer.write(value)
    dest.write("\"")
  }
}

extension DummyAttrValue: From {
  typealias From = String
  static func from(_ string: String) -> Self {
    Self(value: string)
  }
}

extension DummyAttrValue: Default {
  static func `default`() -> Self {
    Self(value: "")
  }
}

enum PseudoClass: Equatable {
  case hover
  case active
  case lang(String)
}

extension PseudoClass: _SelectorParser.NonTSPseudoClass {
  typealias Impl = DummySelectorImpl

  func isActiveOrHover() -> Bool {
    switch self {
    case .active, .hover: true
    case .lang: false
    }
  }

  func isUserActionState() -> Bool {
    isActiveOrHover()
  }

  func toCSS(to dest: inout some TextOutputStream) {
    switch self {
    case .hover:
      dest.write(":hover")
    case .active:
      dest.write(":active")
    case .lang(let lang):
      dest.write(":lang(")
      serializeIdentifier(lang, dest: &dest)
      dest.write(")")
    }
  }
}

enum PseudoElement: Equatable {
  case before
  case after
  case marker
  case detailsContent
  case highlight(String)
}

extension PseudoElement: _SelectorParser.PseudoElement {
  typealias Impl = DummySelectorImpl

  func toCSS(to dest: inout some TextOutputStream) {
    switch self {
    case .before: dest.write("::before")
    case .after: dest.write("::after")
    case .marker: dest.write("::marker")
    case .detailsContent: dest.write("::details-content")
    case .highlight(let name):
      dest.write("::highlight(")
      serializeIdentifier(name, dest: &dest)
      dest.write(")")
    }
  }

  func acceptsStatePseudoClasses() -> Bool {
    true
  }

  func validAfterSlotted() -> Bool {
    true
  }

  func validAfterBeforeOrAfter() -> Bool {
    if case .marker = self { true } else { false }
  }

  func isBeforeOrAfter() -> Bool {
    switch self {
    case .before, .after: true
    default: false
    }
  }

  func isElementBacked() -> Bool {
    if case .detailsContent = self { true } else { false }
  }
}

struct DummySelectorImpl: SelectorImpl {
  typealias AttrValue = DummyAttrValue
  typealias Identifier = DummyAtom
  typealias LocalName = DummyAtom
  typealias NamespaceUrl = DummyAtom
  typealias NamespacePrefix = DummyAtom
  typealias NonTSPseudoClass = _SelectorParserTests.PseudoClass
  typealias PseudoElement = _SelectorParserTests.PseudoElement
}

struct DummyParser {
  var defaultNS: DummyAtom?
  var nsPrefixes: [DummyAtom: DummyAtom]

  static func defaultWithNamespace(defaultNS: DummyAtom) -> DummyParser {
    Self(defaultNS: defaultNS, nsPrefixes: [:])
  }
}

extension DummyParser: Default {
  static func `default`() -> Self {
    Self(defaultNS: nil, nsPrefixes: [:])
  }
}

extension DummyParser: _SelectorParser.Parser {
  typealias Impl = DummySelectorImpl
  typealias Failure = SelectorParseErrorKind

  public func parseSlotted() -> Bool {
    true
  }

  public func parseNthChildOf() -> Bool {
    true
  }

  public func parsePart() -> Bool {
    true
  }

  public func parseIsAndWhere() -> Bool {
    true
  }

  public func parseHas() -> Bool {
    true
  }

  public func parseParentSelector() -> Bool {
    true
  }

  public func parseHost() -> Bool {
    true
  }

  public func parseNonTSPseudoClass(location: SourceLocation, name: String) -> Result<Impl.NonTSPseudoClass, ParseError<Failure>> {
    switch name.lowercased() {
    case "hover": .success(.hover)
    case "active": .success(.active)
    default: .failure(.init(kind: .custom(.unsupportedPseudoClassOrElement(name)), location: location))
    }
  }

  public func parseNonTSFunctionalPseudoClass(name: String, parser: inout CSSParser, afterPart: Bool) -> Result<Impl.NonTSPseudoClass, ParseError<Failure>> {
    switch name.lowercased() {
    case "lang" where !afterPart:
      switch parser.expectIdentOrString() {
      case .success(let lang):
        .success(.lang(lang))
      case .failure(let error):
        .failure(error.into())
      }
    default:
      .failure(.init(kind: .custom(.unsupportedPseudoClassOrElement(name)), location: parser.currentSourceLocation))
    }
  }

  public func parsePseudoElement(location: SourceLocation, name: String) -> Result<Impl.PseudoElement, ParseError<Failure>> {
    switch name.lowercased() {
    case "before": .success(.before)
    case "after": .success(.after)
    case "marker": .success(.marker)
    case "details-content": .success(.detailsContent)
    default: .failure(.init(kind: .custom(.unsupportedPseudoClassOrElement(name)), location: location))
    }
  }

  public func parseFunctionalPseudoElement(name: String, arguments: inout CSSParser) -> Result<Impl.PseudoElement, ParseError<Failure>> {
    switch name.lowercased() {
    case "highlight":
      switch arguments.expectIdent() {
      case .success(let ident):
        return .success(.highlight(ident))
      case .failure(let error):
        return .failure(error.into())
      }
    default:
      return .failure(.init(kind: .custom(.unsupportedPseudoClassOrElement(name)), location: arguments.currentSourceLocation))
    }
  }

  public func defaultNamespace() -> DummyAtom? {
    defaultNS
  }

  public func namespaceForPrefix(prefix: Impl.NamespacePrefix) -> Impl.NamespaceUrl? {
    nsPrefixes[prefix]
  }

}
