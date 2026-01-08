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

public typealias AtomIdent = SelectorImpl.Identifier
public typealias LocalName = SelectorImpl.LocalName
public typealias Namespace = SelectorImpl.NamespaceUrl
public typealias Prefix = SelectorImpl.NamespacePrefix

public enum SelectorImpl: _SelectorParser.SelectorImpl {
  public typealias AttrValue = AtomString
  public typealias Identifier = GenericAtomIdent<IdentStaticSet>
  public typealias LocalName = GenericAtomIdent<LocalNameStaticSet>
  public typealias NamespaceUrl = GenericAtomIdent<NamespaceStaticSet>
  public typealias NamespacePrefix = GenericAtomIdent<PrefixStaticSet>
  public typealias NonTSPseudoClass = NonTSPseudoClassImpl
  public typealias PseudoElement = PseudoElementImpl
}
