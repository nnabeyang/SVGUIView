import Foundation
import _CSSParser
import _SelectorParser

public struct CustomState: Equatable {
  public let ident: AtomIdent
}

extension CustomState: ToCSS {
  public func toCSS(to dest: inout some TextOutputStream) {
    ident.toCSS(to: &dest)
  }
}

public typealias AtomIdent = SVGSelectorImpl.Identifier
public typealias LocalName = SVGSelectorImpl.LocalName
public typealias Namespace = SVGSelectorImpl.NamespaceUrl
public typealias Prefix = SVGSelectorImpl.NamespacePrefix

public enum SVGSelectorImpl: _SelectorParser.SelectorImpl {
  public typealias AttrValue = AtomString
  public typealias Identifier = GenericAtomIdent<IdentStaticSet>
  public typealias LocalName = GenericAtomIdent<LocalNameStaticSet>
  public typealias NamespaceUrl = GenericAtomIdent<NamespaceStaticSet>
  public typealias NamespacePrefix = GenericAtomIdent<PrefixStaticSet>
  public typealias NonTSPseudoClass = NonTSPseudoClassImpl
  public typealias PseudoElement = PseudoElementImpl
}
