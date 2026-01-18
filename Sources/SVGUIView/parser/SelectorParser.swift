import Foundation
import _CSSParser
import _SelectorParser

public typealias AttrValue = SVGSelectorImpl.AttrValue

public struct SelectorParser {
  public let stylesheetOrigin: Origin
  public let namespaces: Namespaces
  public let urlData: URLExtraData
  public let forSupportsRule: Bool

  public func parseAuthorOriginNoNamespace(input: String, urlData: URLExtraData) -> Result<SelectorList<SVGSelectorImpl>, ParseError<Failure>> {
    let namespaces = Namespaces.default()
    let parser = SelectorParser(stylesheetOrigin: .author, namespaces: namespaces, urlData: urlData, forSupportsRule: false)
    let input = ParserInput(input: input)
    var cssParser = _SelectorParser.CSSParser(input: input)
    return SelectorList.parse(parser: parser, input: &cssParser, parseRelative: .no)
  }

  public var inUserAgentStylesheet: Bool {
    switch stylesheetOrigin {
    case .userAgent: true
    default: false
    }
  }

  public var chromeRulesEnabled: Bool {
    urlData.chromeRulesEnabled || stylesheetOrigin == .userAgent
  }
}

extension SelectorParser: _SelectorParser.Parser {
  public typealias Impl = SVGSelectorImpl
  public typealias Failure = StyleParseErrorKind

  public func parseSlotted() -> Bool {
    true
  }

  public func parsePart() -> Bool {
    true
  }

  public func parseNthChildOf() -> Bool {
    false
  }

  public func parseIsAndWhere() -> Bool {
    true
  }

  public func parseHas() -> Bool {
    false
  }

  public func parseParentSelector() -> Bool {
    true
  }

  public func parseHost() -> Bool {
    true
  }
  public func allowForgivingSelectors() -> Bool {
    !forSupportsRule
  }

  public func parseNonTSPseudoClass(location: SourceLocation, name: String)
    -> Result<Impl.NonTSPseudoClass, ParseError<Failure>>
  {
    let pseudoClass: SVGSelectorImpl.NonTSPseudoClass
    switch name.lowercased() {
    case "active": pseudoClass = .active
    case "any-link": pseudoClass = .anyLink
    case "autofill": pseudoClass = .autofill
    case "checked": pseudoClass = .checked
    case "default": pseudoClass = .default
    case "defined": pseudoClass = .defined
    case "disabled": pseudoClass = .disabled
    case "enabled": pseudoClass = .enabled
    case "focus": pseudoClass = .focus
    case "focus-visible": pseudoClass = .focusVisible
    case "focus-within": pseudoClass = .focusWithin
    case "fullscreen": pseudoClass = .fullscreen
    case "hover": pseudoClass = .hover
    case "indeterminate": pseudoClass = .indeterminate
    case "invalid": pseudoClass = .invalid
    case "link": pseudoClass = .link
    case "optional": pseudoClass = .optional
    case "out-of-range": pseudoClass = .outOfRange
    case "placeholder-shown": pseudoClass = .placeholderShown
    case "popover-open": pseudoClass = .popoverOpen
    case "read-only": pseudoClass = .readOnly
    case "read-write": pseudoClass = .readWrite
    case "required": pseudoClass = .required
    case "target": pseudoClass = .target
    case "user-invalid": pseudoClass = .userInvalid
    case "user-valid": pseudoClass = .userValid
    case "valid": pseudoClass = .valid
    case "visited": pseudoClass = .visited
    case "-moz-meter-optimum": pseudoClass = .mozMeterOptimum
    case "-moz-meter-sub-optimum": pseudoClass = .mozMeterSubOptimum
    case "-moz-meter-sub-sub-optimum": pseudoClass = .mozMeterSubSubOptimum
    default:
      return .failure(location.newCustomError(error: .unexpectedIdent(name)))
    }
    return .success(pseudoClass)
  }

  public func parseNonTSFunctionalPseudoClass(name: String, parser: inout _SelectorParser.CSSParser, afterPart: Bool) -> Result<Impl.NonTSPseudoClass, ParseError<Failure>> {
    let pseudoClass: Impl.NonTSPseudoClass
    switch name.lowercased() {
    case "lang":
      switch parser.expectIdentOrString() {
      case .failure(let error):
        return .failure(error.into())
      case .success(let string):
        pseudoClass = .lang(string)
      }
    case "state":
      switch parser.expectIdent() {
      case .failure(let error):
        return .failure(error.into())
      case .success(let ident):
        pseudoClass = .customState(CustomState(ident: .from(ident)))
      }
    default:
      return .failure(parser.newCustomError(error: .unexpectedIdent(name)))
    }
    return .success(pseudoClass)
  }

  public func parsePseudoElement(location: SourceLocation, name: String)
    -> Result<Impl.PseudoElement, ParseError<Failure>>
  {
    let pseudoElement: Impl.PseudoElement
    switch name.lowercased() {
    case "before":
      pseudoElement = .before
    case "after":
      pseudoElement = .after
    case "backdrop":
      pseudoElement = .backdrop
    case "selection":
      pseudoElement = .selection
    case "marker":
      pseudoElement = .marker
    case "color-swatch":
      pseudoElement = .colorSwatch
    case "placeholder":
      guard inUserAgentStylesheet else {
        return .failure(location.newCustomError(error: .unexpectedIdent(name)))
      }
      pseudoElement = .placeholder
    default:
      return .failure(location.newCustomError(error: .unexpectedIdent(name)))
    }
    return .success(pseudoElement)
  }

  public func defaultNamespace() -> Impl.NamespaceUrl? {
    namespaces.default
  }

  public func namespaceForPrefix(prefix: Impl.NamespacePrefix) -> Impl.NamespaceUrl? {
    namespaces.prefixes[prefix]
  }
}
