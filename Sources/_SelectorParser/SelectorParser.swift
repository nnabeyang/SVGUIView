import _CSSParser

public typealias CSSParser = _CSSParser.Parser
public typealias SelectorParseError = ParseError<SelectorParseErrorKind>

public enum SelectorParseErrorKind: Error, Equatable, Into {
  case noQualifiedNameInAttributeSelector(Token)
  case emptySelector
  case danglingCombinator
  case nonCompoundSelector
  case nonPseudoElementAfterSlotted
  case invalidPseudoElementAfterSlotted
  case invalidPseudoElementInsideWhere
  case invalidState
  case unexpectedTokenInAttributeSelector(Token)
  case pseudoElementExpectedColon(Token)
  case pseudoElementExpectedIdent(Token)
  case noIdentForPseudo(Token)
  case unsupportedPseudoClassOrElement(String)
  case unexpectedIdent(String)
  case expectedNamespace(String)
  case expectedBarInAttr(Token)
  case badValueInAttr(Token)
  case invalidQualNameInAttr(Token)
  case explicitNamespaceUnexpectedToken(Token)
  case classNeedsIdent(Token)
}

extension SelectorParseErrorKind: From {
  public static func from(_ other: SelectorParseErrorKind) -> SelectorParseErrorKind {
    other
  }

  public typealias From = Self
}

enum ForgivingParsing {
  case no
  case yes
}

public enum ParseRelative {
  case forHas
  case forNesting
  case forScope
  case no
}

func toAsciiLowercase(string: String) -> String {
  var string = string
  if let firstUppercase = string.firstIndex(where: { $0.isUppercase }) {
    let range = firstUppercase...
    string.replaceSubrange(range, with: string[range].toAsciiLowercase())
  }
  return string
}

struct SelectorParsingState: OptionSet, Sendable {
  public let rawValue: UInt16
  public init(rawValue: UInt16) {
    self.rawValue = rawValue
  }

  static let empty = Self([])
  static let skipDefaultNamespace = Self(rawValue: 1 << 0)
  static let afterSlotted = Self(rawValue: 1 << 1)
  static let afterPartLike = Self(rawValue: 1 << 2)
  static let afterNonElementBackedPseudo = Self(rawValue: 1 << 3)
  static let afterNonStatefulPseudoElement = Self(rawValue: 1 << 4)
  static let afterBeforeOrAfterPseudo = Self(rawValue: 1 << 5)
  static let disallowCombinators = Self(rawValue: 1 << 6)
  static let disallowPseudos = Self(rawValue: 1 << 7)
  static let disallowRelativeSelector = Self(rawValue: 1 << 8)
  static let inPseudoElementTree = Self(rawValue: 1 << 9)

  static let afterPseudo: Self = [.afterPartLike, .afterSlotted, .afterNonElementBackedPseudo, .afterBeforeOrAfterPseudo]

  var allowsSlotted: Bool {
    intersection([.afterSlotted, .disallowPseudos]) == .empty
  }

  var allowsPart: Bool {
    intersection([.afterPseudo, .disallowPseudos]) == .empty
  }

  var allowsNonFunctionalPseudoClasses: Bool {
    intersection([.afterSlotted, .afterNonStatefulPseudoElement]) == .empty
  }

  var allowsTreeStructuralPseudoClasses: Bool {
    intersection(.afterPseudo) == .empty || contains(.inPseudoElementTree)
  }

  var allowsCombinators: Bool {
    !contains(.disallowCombinators)
  }

  var allowsOnlyChildPseudoClassOnly: Bool {
    contains(.inPseudoElementTree)
  }
}

extension SelectorParseError: From {
  public typealias From = SelectorParseErrorKind
  public static func from(_ other: SelectorParseErrorKind) -> ParseError<SelectorParseErrorKind> {
    return SelectorParseError.init(kind: .custom(other), location: .init(line: 0, column: 0))
  }
}

public protocol SelectorImpl {
  associatedtype AttrValue: ExpressibleByStringLiteral & Equatable & From & ToCSS where AttrValue.From == String
  associatedtype Identifier: ExpressibleByStringLiteral & From & ToCSS & Hashable where Identifier.From == String
  associatedtype LocalName: ExpressibleByStringLiteral & Equatable & From & ToCSS & Hashable where LocalName.From == String
  associatedtype NamespaceUrl: Default & From & ToCSS & Equatable where NamespaceUrl.From == String
  associatedtype NamespacePrefix: ExpressibleByStringLiteral & Equatable & From & ToCSS & Default where NamespacePrefix.From == String
  associatedtype NonTSPseudoClass: Equatable & _SelectorParser.NonTSPseudoClass where NonTSPseudoClass.Impl == Self
  associatedtype PseudoElement: Equatable & _SelectorParser.PseudoElement where PseudoElement.Impl == Self

  func shouldCollectAttrHash(_ name: LocalName) -> Bool
}

extension SelectorImpl {
  public func shouldCollectAttrHash(_: LocalName) -> Bool {
    false
  }
}

public protocol NonTSPseudoClass: ToCSS {
  associatedtype Impl: SelectorImpl

  func isActiveOrHover() -> Bool
  func isUserActionState() -> Bool
  func visit<V: SelectorVisitor>(_ visitor: inout V) -> Bool where V.Impl == Impl
}

extension NonTSPseudoClass {
  public func isActiveOrHover() -> Bool {
    false
  }

  public func isUserActionState() -> Bool {
    false
  }

  public func visit<V: SelectorVisitor>(_: inout V) -> Bool where V.Impl == Impl {
    true
  }
}

public protocol PseudoElement: ToCSS {
  associatedtype Impl: SelectorImpl

  func acceptsStatePseudoClasses() -> Bool
  func validAfterSlotted() -> Bool
  func validAfterBeforeOrAfter() -> Bool
  func isElementBacked() -> Bool
  func isBeforeOrAfter() -> Bool
  func specificityCount() -> UInt32
  func isInPseudoElementTree() -> Bool
}

extension PseudoElement {
  public func acceptsStatePseudoClasses() -> Bool {
    false
  }

  public func validAfterSlotted() -> Bool {
    false
  }

  public func validAfterBeforeOrAfter() -> Bool {
    false
  }

  public func isElementBacked() -> Bool {
    false
  }

  public func isBeforeOrAfter() -> Bool {
    false
  }

  public func specificityCount() -> UInt32 {
    1
  }

  public func isInPseudoElementTree() -> Bool {
    false
  }
}

public struct SelectorList<Impl: SelectorImpl>: Equatable {
  public let slice: [Selector<Impl>]

  public init(slice: [Selector<Impl>]) {
    self.slice = slice
  }

  public init(selector: Selector<Impl>) {
    self.slice = [selector]
  }

  public var count: Int {
    slice.count
  }

  public func makeIterator() -> [Selector<Impl>].Iterator {
    slice.makeIterator()
  }

  public func scope() -> Self {
    Self(selector: .scope())
  }

  public static func implicitScope() -> Self {
    Self(selector: .implicitScope())
  }

  public static func parse<P: Parser>(parser: P, input: inout CSSParser, parseRelative: ParseRelative)
    -> Result<Self, ParseError<P.Failure>> where P.Impl == Impl
  {
    parseWithState(parser: parser, input: &input, state: .empty, recovery: .no, parseRelative: parseRelative)
  }

  public static func parseDisallowPseudo<P: Parser>(parser: P, input: inout CSSParser, parseRelative: ParseRelative)
    -> Result<Self, ParseError<P.Failure>> where P.Impl == Impl
  {
    parseWithState(parser: parser, input: &input, state: .disallowPseudos, recovery: .no, parseRelative: parseRelative)
  }

  public static func parseForgiving<P: Parser>(parser: P, input: inout CSSParser, parseRelative: ParseRelative)
    -> Result<Self, ParseError<P.Failure>> where P.Impl == Impl
  {
    parseWithState(parser: parser, input: &input, state: .empty, recovery: .yes, parseRelative: parseRelative)
  }

  static func parseWithState<P: Parser>(
    parser: P,
    input: inout CSSParser,
    state: SelectorParsingState,
    recovery: ForgivingParsing,
    parseRelative: ParseRelative
  ) -> Result<Self, ParseError<P.Failure>> where P.Impl == Impl {
    var slice = [Selector<Impl>]()
    let forgiving = recovery == .yes && parser.allowForgivingSelectors()
    loop: while true {
      let result: Result<Selector<Impl>, ParseError<P.Failure>> = input.parseUntilBefore(
        delimiters: [.comma],
        parse: { input in
          let start = input.position
          var selector = parseSelector(parser: parser, input: &input, state: state, parseRelative: parseRelative)
          if forgiving && (selector.isFailure || input.expectExhausted().isFailure) {
            if case .failure(let error) = input.expectNoErrorToken() {
              return .failure(error.into())
            }
            selector = .success(.createInvalid(input: input.slice(from: start)))
          }
          return selector
        })
      switch result {
      case .success(let selector):
        slice.append(selector)
        switch input.next() {
        case .success(.comma): break
        case .success: fatalError("unreachable")
        case .failure: break loop
        }
      case .failure(let error):
        return .failure(error)
      }
    }
    return .success(.init(slice: slice))
  }

  public func replaceParentSelector(_ parent: SelectorList<Impl>) -> Self {
    .init(slice: self.slice.map({ $0.replaceParentSelector(parent: parent) }))
  }
}

extension SelectorList: ToCSS {
  public func toCSS(to dest: inout some TextOutputStream) {
    var iter = makeIterator()
    serializeSelectorList(iter: &iter, to: &dest)
  }
}

func serializeSelectorList<I, Impl: SelectorImpl>(iter: inout I, to dest: inout some TextOutputStream) where I: IteratorProtocol<Selector<Impl>> {
  var first = true
  while let selector = iter.next() {
    if !first {
      dest.write(", ")
    }
    first = false
    selector.toCSS(to: &dest)
  }
}

func parseInnerCompoundSelector<P: Parser, Impl: SelectorImpl>(
  parser: P,
  input: inout CSSParser,
  state: SelectorParsingState
) -> Result<Selector<Impl>, ParseError<P.Failure>> where P.Impl == Impl {
  parseSelector(parser: parser, input: &input, state: [state, .disallowPseudos, .disallowCombinators], parseRelative: .no)
}

public protocol Default {
  static func `default`() -> Self
}

public protocol Parser {
  associatedtype Impl: SelectorImpl
  associatedtype Failure: Swift.Error & Equatable & Sendable & From where Failure.From == SelectorParseErrorKind

  func parseSlotted() -> Bool
  func parsePart() -> Bool
  func parseNthChildOf() -> Bool
  func parseIsAndWhere() -> Bool
  func parseHas() -> Bool
  func parseParentSelector() -> Bool
  func isIsAlias(name: String) -> Bool
  func parseHost() -> Bool
  func allowForgivingSelectors() -> Bool

  func parseNonTSPseudoClass(location: SourceLocation, name: String, ) -> Result<Impl.NonTSPseudoClass, ParseError<Failure>>
  func parseNonTSFunctionalPseudoClass(name: String, parser: inout CSSParser, afterPart: Bool) -> Result<Impl.NonTSPseudoClass, ParseError<Failure>>
  func parsePseudoElement(location: SourceLocation, name: String) -> Result<Impl.PseudoElement, ParseError<Failure>>
  func parseFunctionalPseudoElement(name: String, arguments: inout CSSParser) -> Result<Impl.PseudoElement, ParseError<Failure>>

  func defaultNamespace() -> Impl.NamespaceUrl?
  func namespaceForPrefix(prefix: Impl.NamespacePrefix) -> Impl.NamespaceUrl?
}

extension Parser {
  public func parseSlotted() -> Bool {
    false
  }

  public func parsePart() -> Bool {
    false
  }

  public func parseNthChildOf() -> Bool {
    false
  }

  public func parseIsAndWhere() -> Bool {
    false
  }

  public func parseHas() -> Bool {
    false
  }

  public func parseParentSelector() -> Bool {
    false
  }

  public func isIsAlias(name: String) -> Bool {
    false
  }

  public func parseHost() -> Bool {
    false
  }

  public func allowForgivingSelectors() -> Bool {
    true
  }

  public func parseNonTSPseudoClass(location: SourceLocation, name: String, ) -> Result<Impl.NonTSPseudoClass, ParseError<Failure>> {
    .failure(location.newCustomError(error: SelectorParseErrorKind.unsupportedPseudoClassOrElement(name)))
  }

  public func parseNonTSFunctionalPseudoClass(name: String, parser: inout CSSParser, afterPart: Bool) -> Result<Impl.NonTSPseudoClass, ParseError<Failure>> {
    .failure(parser.newCustomError(error: SelectorParseErrorKind.unsupportedPseudoClassOrElement(name)))
  }

  public func parsePseudoElement(location: SourceLocation, name: String) -> Result<Impl.PseudoElement, ParseError<Failure>> {
    .failure(location.newCustomError(error: SelectorParseErrorKind.unsupportedPseudoClassOrElement(name)))
  }

  public func parseFunctionalPseudoElement(name: String, arguments: inout CSSParser) -> Result<Impl.PseudoElement, ParseError<Failure>> {
    .failure(arguments.newCustomError(error: SelectorParseErrorKind.unsupportedPseudoClassOrElement(name)))
  }

  public func defaultNamespace() -> Impl.NamespaceUrl? {
    nil
  }

  public func namespaceForPrefix(prefix: Impl.NamespacePrefix) -> Impl.NamespaceUrl? {
    nil
  }
}

func parseSelector<P: Parser, Impl: SelectorImpl>(
  parser: P,
  input: inout CSSParser,
  state: SelectorParsingState,
  parseRelative: ParseRelative,
) -> Result<Selector<Impl>, ParseError<P.Failure>> where P.Impl == Impl {
  var state = state
  var builder = SelectorBuilder<Impl>.default()

  input.skipWhitespace()

  if parseRelative != .no {
    let combinator = tryParseCombinator(input: &input)
    switch parseRelative {
    case .forHas:
      builder.pushSimpleSelector(.relativeSelectorAnchor)
      builder.pushCombinator(combinator ?? .descendant)
    case .forNesting, .forScope:
      if let combinator {
        let selector: Component<Impl> =
          switch parseRelative {
          case .forHas, .no:
            fatalError("unreachable")
          case .forNesting:
            .parentSelector
          case .forScope:
            .implicitScope
          }
        builder.pushSimpleSelector(selector)
        builder.pushCombinator(combinator)
      }
      break
    case .no:
      fatalError("unreachable")
    }
  }

  while true {
    switch parseCompoundSelector(parser: parser, state: &state, input: &input, builder: &builder) {
    case .success(let empty):
      if empty {
        let error: SelectorParseErrorKind = builder.hasCombinators ? .danglingCombinator : .emptySelector
        return .failure(input.newCustomError(error: error))
      }
    case .failure(let error):
      return .failure(error)
    }

    if state.intersection(.afterPseudo) != .empty {
      assert(state.intersection([.afterNonElementBackedPseudo, .afterBeforeOrAfterPseudo, .afterSlotted, .afterPartLike]) != .empty)
      break
    }
    guard let combinator = tryParseCombinator(input: &input) else {
      break
    }
    if !state.allowsCombinators {
      return .failure(input.newCustomError(error: .invalidState))
    }
    builder.pushCombinator(combinator)
  }
  return .success(.init(builder.build(parseRelative: parseRelative)))
}

func tryParseCombinator(input: inout CSSParser) -> Combinator? {
  var anyWhitespace = false
  while true {
    let beforeThisToken = input.state
    switch input.nextIncludingWhitespace() {
    case .failure: return nil
    case .success(.whitespace): anyWhitespace = true
    case .success(.delim(">")): return .child
    case .success(.delim("+")): return .nextSibling
    case .success(.delim("~")): return .laterSibling
    default:
      input.reset(state: beforeThisToken)
      if anyWhitespace {
        return .descendant
      } else {
        return nil
      }
    }
  }
}

extension Swift.Result {
  var isFailure: Bool {
    switch self {
    case .success: false
    case .failure: true
    }
  }
}

func parseAttributeSelector<P: Parser, Impl: SelectorImpl>(
  parser: P,
  input: inout CSSParser,
) -> Result<Component<Impl>, ParseError<P.Failure>> where P.Impl == Impl {
  input.skipWhitespace()
  let namespace: NamespaceConstraint<NamespacePair<Impl.NamespacePrefix, Impl.NamespaceUrl>>?
  let localName: String
  do throws(ParseError<P.Failure>) {
    switch try parseQualifiedName(parser: parser, input: &input, inAttrSelector: true).get() {
    case .none(let token):
      return .failure(input.newCustomError(error: SelectorParseErrorKind.noQualifiedNameInAttributeSelector(token)))
    case .some(_, .none):
      fatalError("unreachable")
    case .some(let ns, .some(let ln)):
      localName = ln
      namespace =
        switch ns {
        case .implicitNoNamespace, .explicitNoNamespace: nil
        case .explicitNamespace(let prefix, let url): .specific(.init(prefix: prefix, url: url))
        case .explicitAnyNamespace: .any
        case .implicitAnyNamespace, .implicitDefaultNamespace: fatalError("unreachable")
        }
    }
  } catch {
    return .failure(error)
  }
  let location = input.currentSourceLocation
  let attrOperator: AttrSelectorOperator
  switch input.next() {
  // [foo]
  case .failure:
    let localNameLower: Impl.LocalName = .from(toAsciiLowercase(string: localName))
    let localName: Impl.LocalName = .from(localName)
    if let namespace {
      return .success(
        .attributeOther(
          .init(
            namespace: namespace,
            localName: localName,
            localNameLower: localNameLower,
            operation: .exists)))
    } else {
      return .success(.attributeInNoNamespaceExists(localName: localName, localNameLower: localNameLower))
    }
  case .success(let token):
    switch token {
    // [foo=bar]
    case .delim("="): attrOperator = .equal
    // [foo~=bar]
    case .includeMatch: attrOperator = .includes
    // [foo|=bar]
    case .dashMatch: attrOperator = .dashMatch
    // [foo^=bar]
    case .prefixMatch: attrOperator = .prefix
    // [foo*=bar]
    case .substringMatch: attrOperator = .substring
    // [foo$=bar]
    case .suffixMatch: attrOperator = .suffix
    default:
      return .failure(location.newCustomError(error: .unexpectedTokenInAttributeSelector(token)))
    }
  }
  let value: String
  switch input.expectIdentOrString() {
  case .success(let string): value = string
  case .failure(let error):
    if case .unexpectedToken(let token) = error.kind {
      return .failure(input.newCustomError(error: .badValueInAttr(token)))
    } else {
      return .failure(error.into())
    }
  }
  switch parseAttributeFlags(input: &input) {
  case .failure(let error):
    return .failure(error.into())
  case .success(let attributeFlags):
    let value: Impl.AttrValue = .from(value)
    let localNameLowerCOW = toAsciiLowercase(string: localName)
    let localNameIsAsciiLowercase = localName == localNameLowerCOW
    let caseSensitivity = attributeFlags.toCaseSensitivity(localNameLower: localNameLowerCOW, haveNamespace: namespace != nil)
    let localNameLower: Impl.LocalName = .from(localNameLowerCOW)
    let localName: Impl.LocalName = .from(localName)
    if namespace != nil || !localNameIsAsciiLowercase {
      return .success(
        .attributeOther(
          .init(
            namespace: namespace,
            localName: localName,
            localNameLower: localNameLower,
            operation: .withValue(
              operator: attrOperator,
              caseSensitivity: caseSensitivity,
              value: value)
          )))
    } else {
      return .success(
        .attributeInNoNamespace(
          localName: localName,
          operator: attrOperator,
          value: value,
          caseSensitivity: caseSensitivity
        ))
    }
  }
}

enum HTMLCaseInsensitiveAttributes {
  static let set: Set<String> = [
    "dir", "link", "language", "clear", "checked", "scope", "noresize",
    "align", "http-equiv", "nowrap", "direction", "lang", "alink",
    "face", "rel", "target", "selected", "multiple", "rev", "vlink",
    "type", "codetype", "shape", "valuetype", "method", "disabled",
    "color", "accept-charset", "valign", "declare", "readonly",
    "enctype", "noshade", "compact", "defer", "media", "hreflang",
    "rules", "scrolling", "accept", "text", "axis", "charset",
    "bgcolor", "frame", "nohref",
  ]
}

enum AttributeFlags {
  case caseSensitive
  case asciiCaseInsensitive
  case caseSensitivityDependsOnName

  func toCaseSensitivity(localNameLower: String, haveNamespace: Bool) -> ParsedCaseSensitivity {
    switch self {
    case .caseSensitive:
      return .explicitCaseSensitive
    case .asciiCaseInsensitive:
      return .asciiCaseInsensitive
    case .caseSensitivityDependsOnName:
      if !haveNamespace && HTMLCaseInsensitiveAttributes.set.contains(localNameLower) {
        return .asciiCaseInsensitiveIfInHtmlElementInHtmlDocument
      }
      return .caseSensitive
    }
  }
}

func parseAttributeFlags(input: inout CSSParser) -> Result<AttributeFlags, BasicParseError> {
  let location = input.currentSourceLocation
  let token: Token
  switch input.next() {
  case .success(let t):
    token = t
  case .failure:
    return .success(.caseSensitivityDependsOnName)
  }
  let ident: String
  switch token {
  case .ident(let string):
    ident = string
  default:
    return .failure(location.newBasicUnexpectedTokenError(token: token))
  }
  switch ident.lowercased() {
  case "i": return .success(.asciiCaseInsensitive)
  case "s": return .success(.caseSensitive)
  default: return .failure(location.newBasicUnexpectedTokenError(token: token))
  }
}

func parseNegation<P: Parser, Impl>(
  parser: P,
  input: inout CSSParser,
  state: SelectorParsingState,
) -> Result<Component<Impl>, ParseError<P.Failure>> where P.Impl == Impl {
  switch SelectorList.parseWithState(
    parser: parser, input: &input,
    state: [state, .skipDefaultNamespace, .disallowPseudos],
    recovery: .no,
    parseRelative: .no)
  {
  case .failure(let error):
    return .failure(error)
  case .success(let list):
    return .success(.negation(list))
  }
}

func parseCompoundSelector<P: Parser, Impl: SelectorImpl>(
  parser: P,
  state: inout SelectorParsingState,
  input: inout CSSParser,
  builder: inout SelectorBuilder<Impl>,
) -> Result<Bool, ParseError<P.Failure>> where P.Impl == Impl {
  input.skipWhitespace()

  var empty = true
  switch parseTypeSelector(parser: parser, input: &input, state: state, sink: &builder) {
  case .success(let value):
    empty = !value
  case .failure(let error):
    return .failure(error)
  }
  loop: while true {
    do throws(ParseError<P.Failure>) {
      guard let result = try parseOneSimpleSelector(parser: parser, input: &input, state: state).get() else {
        break loop
      }
      if empty, let url = parser.defaultNamespace() {
        let ignoreDefaultNS =
          switch result {
          case .simpleSelector(.host):
            true
          default:
            state.contains(.skipDefaultNamespace)
          }
        if !ignoreDefaultNS {
          builder.pushSimpleSelector(.defaultNamespace(url: url))
        }
      }
      empty = false
      switch result {
      case .simpleSelector(let s):
        builder.pushSimpleSelector(s)
      case .partPseudo(let partNames):
        state.insert(.afterPartLike)
        builder.pushCombinator(.part)
        builder.pushSimpleSelector(.part(partNames))
      case .slottedPseudo(let selector):
        state.insert(.afterSlotted)
        builder.pushCombinator(.slotAssignment)
        builder.pushSimpleSelector(.slotted(selector))
      case .pseudoElement(let p):
        if p.isElementBacked() {
          state.insert(.afterPartLike)
        } else {
          state.insert(.afterNonElementBackedPseudo)
          if p.isBeforeOrAfter() {
            state.insert(.afterBeforeOrAfterPseudo)
          }
        }
        if !p.acceptsStatePseudoClasses() {
          state.insert(.afterNonStatefulPseudoElement)
        }
        if p.isInPseudoElementTree() {
          state.insert(.inPseudoElementTree)
        }
        builder.pushCombinator(.pseudoElement)
        builder.pushSimpleSelector(.pseudoElement(p))
      }
    } catch {
      return .failure(error)
    }
  }
  return .success(empty)
}

func parseIsWhere<P: Parser, Impl: SelectorImpl>(
  parser: P,
  input: inout CSSParser,
  state: SelectorParsingState,
  component: @escaping (SelectorList<Impl>) -> Component<Impl>
) -> Result<Component<Impl>, ParseError<P.Failure>>
where P.Impl == Impl {
  assert(parser.parseIsAndWhere())
  switch SelectorList.parseWithState(
    parser: parser,
    input: &input,
    state: [.skipDefaultNamespace, .disallowPseudos],
    recovery: .yes,
    parseRelative: .no)
  {
  case .failure(let error):
    return .failure(error)
  case .success(let inner):
    return .success(component(inner))
  }
}

func parseHas<P: Parser, Impl: SelectorImpl>(
  parser: P,
  input: inout CSSParser,
  state: SelectorParsingState
) -> Result<Component<Impl>, ParseError<P.Failure>> where P.Impl == Impl {
  assert(parser.parseHas())
  if state.intersection([.disallowRelativeSelector, .afterPseudo]) != .empty {
    return .failure(input.newCustomError(error: .invalidState))
  }
  switch SelectorList.parseWithState(
    parser: parser,
    input: &input,
    state: state,
    recovery: .no,
    parseRelative: .forHas)
  {
  case .failure(let error):
    return .failure(error)
  case .success(let inner):
    return .success(.has(RelativeSelector.fromSelectorList(inner)))
  }
}

func parseFunctionalPseudoClass<P: Parser, Impl: SelectorImpl>(
  parser: P,
  input: inout CSSParser,
  name: String,
  state: SelectorParsingState
) -> Result<Component<Impl>, ParseError<P.Failure>> where P.Impl == Impl {
  switch name.lowercased() {
  case "nth-child": return parseNthPseudoClass(parser: parser, input: &input, state: state, ty: .child)
  case "nth-of-type": return parseNthPseudoClass(parser: parser, input: &input, state: state, ty: .ofType)
  case "nth-last-child": return parseNthPseudoClass(parser: parser, input: &input, state: state, ty: .lastChild)
  case "nth-last-of-type": return parseNthPseudoClass(parser: parser, input: &input, state: state, ty: .lastOfType)
  case "is" where parser.parseIsAndWhere(): return parseIsWhere(parser: parser, input: &input, state: state, component: Component<Impl>.is)
  case "where" where parser.parseIsAndWhere(): return parseIsWhere(parser: parser, input: &input, state: state, component: Component<Impl>.where)
  case "has" where parser.parseHas(): return parseHas(parser: parser, input: &input, state: state)
  case "host":
    if !state.allowsTreeStructuralPseudoClasses {
      return .failure(input.newCustomError(error: .invalidState))
    }
    switch parseInnerCompoundSelector(parser: parser, input: &input, state: state) {
    case .failure(let error): return .failure(error)
    case .success(let inner): return .success(.host(inner))
    }
  case "not": return parseNegation(parser: parser, input: &input, state: state)
  default:
    break
  }
  if parser.parseIsAndWhere() && parser.isIsAlias(name: name) {
    return parseIsWhere(parser: parser, input: &input, state: state, component: Component<Impl>.is)
  }

  if state.intersection([.afterNonElementBackedPseudo, .afterSlotted]) != .empty {
    return .failure(input.newCustomError(error: .invalidState))
  }
  let afterPart = state.contains(.afterPartLike)
  return parser.parseNonTSFunctionalPseudoClass(name: name, parser: &input, afterPart: afterPart).map({ Component<Impl>.nonTSPseudoClass($0) })
}

func parseNthPseudoClass<P: Parser, Impl: SelectorImpl>(
  parser: P,
  input: inout CSSParser,
  state: SelectorParsingState,
  ty: NthType
) -> Result<Component<Impl>, ParseError<P.Failure>> where P.Impl == Impl {
  guard state.allowsTreeStructuralPseudoClasses else {
    return .failure(input.newCustomError(error: .invalidState))
  }

  let nthData: NthSelectorData
  switch parseNth(input: &input) {
  case .failure(let error):
    return .failure(error.into())
  case .success(let value):
    nthData = NthSelectorData(ty: ty, isFunction: true, anPlusB: AnPlusB(a: value.0, b: value.1))
  }

  if !parser.parseNthChildOf() || ty.isOfType {
    return .success(.nth(nthData))
  }

  if case .failure = input.tryParse({ $0.expectIdentMatching(expectedValue: "of") }) {
    return .success(.nth(nthData))
  }

  switch SelectorList.parseWithState(parser: parser, input: &input, state: [state, .skipDefaultNamespace, .disallowPseudos], recovery: .no, parseRelative: .no) {
  case .failure(let error):
    return .failure(error)
  case .success(let selectors):
    return .success(.nthOf(.init(nthData: nthData, selectors: selectors.slice)))
  }
}

public func isCSS2PseudoElement(name: String) -> Bool {
  switch name {
  case "before", "after", "first-line", "first-letter":
    true
  default:
    false
  }
}

func parseOneSimpleSelector<P: Parser, Impl: SelectorImpl>(
  parser: P,
  input: inout CSSParser,
  state: SelectorParsingState
) -> Result<SimpleSelectorParseResult<Impl>?, ParseError<P.Failure>> where P.Impl == Impl {
  let start = input.state
  let token: Token
  switch input.nextIncludingWhitespace() {
  case .success(let t):
    token = t
  case .failure:
    input.reset(state: start)
    return .success(nil)
  }

  switch token {
  case .idHash(let id):
    if state.intersection(.afterPseudo) != .empty {
      return .failure(input.newCustomError(error: .invalidState))
    } else {
      let id = Component<Impl>.id(.from(id))
      return .success(.simpleSelector(id))
    }
  case .delim(let delim) where delim == "." || (delim == "&" && parser.parseParentSelector()):
    if state.intersection(.afterPseudo) != .empty {
      return .failure(input.newCustomError(error: .invalidState))
    }
    let location = input.currentSourceLocation
    if delim == "&" {
      return .success(.simpleSelector(.parentSelector))
    } else {
      let result = input.nextIncludingWhitespace()
      switch result {
      case .success(.ident(let `class`)):
        return .success(.simpleSelector(.class(.from(`class`))))
      case .success(let token):
        return .failure(location.newCustomError(error: .classNeedsIdent(token)))
      case .failure(let error):
        return .failure(.init(basic: error))
      }
    }
  case .squareBracketBlock:
    if state.intersection(.afterPseudo) != .empty {
      return .failure(input.newCustomError(error: .invalidState))
    }
    let attr: Result<Component<Impl>, ParseError<P.Failure>> = input.parseNestedBlock { input in
      parseAttributeSelector(parser: parser, input: &input)
    }
    switch attr {
    case .success(let component):
      return .success(.simpleSelector(component))
    case .failure(let error):
      return .failure(error)
    }
  case .colon:
    let location = input.currentSourceLocation
    let isSingleColon: Bool
    let nextToken: Token
    switch input.nextIncludingWhitespace() {
    case .success(.colon):
      switch input.nextIncludingWhitespace() {
      case .success(let token):
        isSingleColon = false
        nextToken = token
      case .failure(let error):
        return .failure(.init(basic: error))
      }
    case .success(let token):
      isSingleColon = true
      nextToken = token
    case .failure(let error):
      return .failure(.init(basic: error))
    }

    let name: String
    let isFunctional: Bool
    switch nextToken {
    case .ident(let n):
      name = n
      isFunctional = false
    case .function(let n):
      name = n
      isFunctional = true
    default:
      let e = SelectorParseErrorKind.pseudoElementExpectedIdent(nextToken)
      return .failure(input.newCustomError(error: e))
    }

    let isPseudoElement = !isSingleColon || isCSS2PseudoElement(name: name)
    if isPseudoElement {
      if state.intersection([.disallowPseudos, .afterNonElementBackedPseudo]) != .empty
        && !state.contains(.afterBeforeOrAfterPseudo)
      {
        return .failure(input.newCustomError(error: .invalidState))
      }
      let pseudoElement: Impl.PseudoElement
      if isFunctional {
        if parser.parsePart() && name.lowercased() == "part" {
          if !state.allowsPart {
            return .failure(input.newCustomError(error: .invalidState))
          }
          let result: Result<[Impl.Identifier], ParseError<P.Failure>> = input.parseNestedBlock { input in
            var result = [Impl.Identifier]()
            switch input.expectIdent() {
            case .failure(let error):
              return .failure(error.into())
            case .success(let ident):
              result.append(.from(ident))
            }
            while !input.isExhausted() {
              switch input.expectIdent() {
              case .failure(let error):
                return .failure(error.into())
              case .success(let ident):
                result.append(.from(ident))
              }
            }
            return .success(result)
          }
          switch result {
          case .failure(let error):
            return .failure(error)
          case .success(let names):
            return .success(.partPseudo(names))
          }
        }
        if parser.parseSlotted() && name.lowercased() == "slotted" {
          if !state.allowsSlotted {
            return .failure(input.newCustomError(error: .invalidState))
          }
          let result = input.parseNestedBlock { input in
            parseInnerCompoundSelector(parser: parser, input: &input, state: state)
          }
          switch result {
          case .failure(let error):
            return .failure(error)
          case .success(let selector):
            return .success(.slottedPseudo(selector))
          }
        }
        let result: Result<Impl.PseudoElement, ParseError<P.Failure>> = input.parseNestedBlock { input in
          return parser.parseFunctionalPseudoElement(name: name, arguments: &input)
        }
        switch result {
        case .failure(let error):
          return .failure(error)
        case .success(let element):
          pseudoElement = element
        }
      } else {
        switch parser.parsePseudoElement(location: location, name: name) {
        case .failure(let error):
          return .failure(error)
        case .success(let element):
          pseudoElement = element
        }
      }
      if state.contains(.afterBeforeOrAfterPseudo) && !pseudoElement.validAfterBeforeOrAfter() {
        return .failure(input.newCustomError(error: .invalidState))
      }
      if state.contains(.afterSlotted) && !pseudoElement.validAfterSlotted() {
        return .failure(input.newCustomError(error: .invalidState))
      }
      return .success(.pseudoElement(pseudoElement))
    } else {
      let pseudoClass: Component<Impl>
      if isFunctional {
        let result = input.parseNestedBlock { input in
          parseFunctionalPseudoClass(parser: parser, input: &input, name: name, state: state)
        }
        switch result {
        case .success(let component):
          pseudoClass = component
        case .failure(let error):
          return .failure(error)
        }
      } else {
        switch parseSimplePseudoClass(parser: parser, location: location, name: name, state: state) {
        case .success(let component):
          pseudoClass = component
        case .failure(let error):
          return .failure(error)
        }
      }
      return .success(.simpleSelector(pseudoClass))
    }
  default:
    input.reset(state: start)
    return .success(nil)
  }
}

func parseSimplePseudoClass<P: Parser, Impl: SelectorImpl>(
  parser: P,
  location: SourceLocation,
  name: String,
  state: SelectorParsingState,
) -> Result<Component<Impl>, ParseError<P.Failure>> where P.Impl == Impl {
  if !state.allowsNonFunctionalPseudoClasses {
    return .failure(location.newCustomError(error: .invalidState))
  }

  if state.allowsTreeStructuralPseudoClasses {
    if state.allowsOnlyChildPseudoClassOnly {
      if name.caseInsensitiveCompare("only-child") == .orderedSame {
        return .success(.nth(.only(ofType: false)))
      }
      return .failure(location.newCustomError(error: .invalidState))
    }

    switch name.lowercased() {
    case "first-child":
      return .success(.nth(.first(ofType: false)))
    case "last-child":
      return .success(.nth(.last(ofType: false)))
    case "only-child":
      return .success(.nth(.only(ofType: false)))
    case "root":
      return .success(.root)
    case "empty":
      return .success(.empty)
    case "scope":
      return .success(.scope)
    case "host":
      return .success(.host(.none))
    case "first-of-type":
      return .success(.nth(.first(ofType: true)))
    case "last-of-type":
      return .success(.nth(.last(ofType: true)))
    case "only-of-type":
      return .success(.nth(.only(ofType: true)))
    default:
      break
    }
  }

  switch parser.parseNonTSPseudoClass(location: location, name: name) {
  case .failure(let error):
    return .failure(error)
  case .success(let pseudoClass):
    if state.contains(.afterNonElementBackedPseudo) && !pseudoClass.isUserActionState() {
      return .failure(location.newCustomError(error: .invalidState))
    }
    return .success(.nonTSPseudoClass(pseudoClass))
  }
}

func parseTypeSelector<P: Parser, Impl, S: Push>(
  parser: P,
  input: inout CSSParser,
  state: SelectorParsingState,
  sink: inout S
) -> Result<Bool, ParseError<P.Failure>> where P.Impl == Impl, S.Element == Component<Impl> {
  switch parseQualifiedName(parser: parser, input: &input, inAttrSelector: false) {
  case .failure(let error) where error.kind == .basic(.endOfInput):
    fallthrough
  case .success(.none):
    return .success(false)
  case .success(.some(let namespace, let localName)):
    if state.contains(.afterSlotted) {
      return .failure(input.newCustomError(error: .invalidState))
    }
    switch namespace {
    case .implicitAnyNamespace:
      break
    case .implicitDefaultNamespace(let url):
      sink.push(.defaultNamespace(url: url))
    case .explicitNamespace(let prefix, let url):
      let component: Component<Impl> =
        switch parser.defaultNamespace() {
        case .some(let defaultUrl) where url == defaultUrl:
          .defaultNamespace(url: url)
        default:
          .namespace(prefix: prefix, url: url)
        }
      sink.push(component)
    case .explicitNoNamespace:
      sink.push(.explicitNoNamespace)
    case .explicitAnyNamespace:
      if parser.defaultNamespace() != nil {
        sink.push(.explicitAnyNamespace)
      }
    case .implicitNoNamespace:
      fatalError("unreachable")
    }
    switch localName {
    case .some(let name):
      sink.push(.localName(.init(name: .from(name), lowerName: .from(toAsciiLowercase(string: name)))))
    case .none:
      sink.push(.explicitUniversalType)
    }
    return .success(true)
  case .failure(let error):
    return .failure(error)
  }
}

enum SimpleSelectorParseResult<Impl: SelectorImpl> {
  case simpleSelector(Component<Impl>)
  case pseudoElement(Impl.PseudoElement)
  case slottedPseudo(Selector<Impl>)
  case partPseudo([Impl.Identifier])
}

enum QNamePrefix<Impl: SelectorImpl> {
  case implicitNoNamespace
  case implicitAnyNamespace
  case implicitDefaultNamespace(Impl.NamespaceUrl)
  case explicitNoNamespace
  case explicitAnyNamespace
  case explicitNamespace(Impl.NamespacePrefix, Impl.NamespaceUrl)
}

enum OptionalQName<Impl: SelectorImpl> {
  case some(QNamePrefix<Impl>, String?)
  case none(Token)
}

func parseQualifiedName<P: Parser, Impl: SelectorImpl>(
  parser: P,
  input: inout CSSParser,
  inAttrSelector: Bool,
) -> Result<OptionalQName<Impl>, ParseError<P.Failure>> where P.Impl == Impl {

  let defaultNamespace = { (localName: String?) -> Result<OptionalQName<Impl>, ParseError<P.Failure>> in
    let namespace: QNamePrefix<Impl> =
      switch parser.defaultNamespace() {
      case .some(let url): .implicitDefaultNamespace(url)
      case .none: .implicitAnyNamespace
      }
    return .success(OptionalQName.some(namespace, localName))
  }

  let explicitNamespace: (inout CSSParser, QNamePrefix<Impl>) -> Result<OptionalQName<Impl>, ParseError<P.Failure>> = { input, prefix in
    let location = input.currentSourceLocation
    switch input.nextIncludingWhitespace() {
    case .success(let token):
      switch token {
      case .delim("*") where !inAttrSelector: return .success(.some(prefix, nil))
      case .ident(let localName): return .success(.some(prefix, localName))
      case let t where inAttrSelector:
        let e = SelectorParseErrorKind.invalidQualNameInAttr(t)
        return .failure(location.newCustomError(error: e))
      case let t:
        return .failure(location.newCustomError(error: SelectorParseErrorKind.explicitNamespaceUnexpectedToken(t)))
      }
    case .failure(let error):
      return .failure(.init(basic: error))
    }
  }
  let start = input.state
  switch input.nextIncludingWhitespace() {
  case .success(let token):
    switch token {
    case .ident(let value):
      let afterIdent = input.state
      if case .success(.delim("|")) = input.nextIncludingWhitespace() {
        let prefix = Impl.NamespacePrefix.from(value)
        if let url = parser.namespaceForPrefix(prefix: prefix) {
          return explicitNamespace(&input, .explicitNamespace(prefix, url))
        } else {
          return .failure(afterIdent.sourceLocation.newCustomError(error: SelectorParseErrorKind.expectedNamespace(value)))
        }
      } else {
        input.reset(state: afterIdent)
        if inAttrSelector {
          return .success(.some(.implicitNoNamespace, value))
        } else {
          return defaultNamespace(value)
        }
      }
    case .delim("*"):
      let afterStar = input.state
      switch input.nextIncludingWhitespace() {
      case .success(.delim("|")):
        return explicitNamespace(&input, .explicitAnyNamespace)
      case _ where !inAttrSelector:
        input.reset(state: afterStar)
        return defaultNamespace(nil)
      case .failure(let error):
        return .failure(.init(basic: error))
      case .success(let token):
        return .failure(afterStar.sourceLocation.newCustomError(error: SelectorParseErrorKind.expectedBarInAttr(token)))
      }
    case .delim("|"):
      return explicitNamespace(&input, .explicitNoNamespace)
    case let token:
      input.reset(state: start)
      return .success(.none(token))
    }
  case .failure(let error):
    return .failure(.init(basic: error))
  }
}
