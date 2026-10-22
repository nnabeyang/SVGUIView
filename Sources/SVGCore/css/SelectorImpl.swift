import Foundation
import _CSSParser
import _SelectorParser

struct CustomState: Equatable {
  let ident: AtomIdent
}

extension CustomState: ToCSS {
  func toCSS(to dest: inout some TextOutputStream) {
    ident.toCSS(to: &dest)
  }
}

typealias AtomIdent = SVGSelectorImpl.Identifier
typealias LocalName = SVGSelectorImpl.LocalName
typealias Namespace = SVGSelectorImpl.NamespaceUrl
typealias Prefix = SVGSelectorImpl.NamespacePrefix

enum SVGSelectorImpl: _SelectorParser.SelectorImpl {
  typealias AttrValue = AtomString
  typealias Identifier = GenericAtomIdent<IdentStaticSet>
  typealias LocalName = GenericAtomIdent<LocalNameStaticSet>
  typealias NamespaceUrl = GenericAtomIdent<NamespaceStaticSet>
  typealias NamespacePrefix = GenericAtomIdent<PrefixStaticSet>
  typealias NonTSPseudoClass = NonTSPseudoClassImpl
  typealias PseudoElement = PseudoElementImpl
}
