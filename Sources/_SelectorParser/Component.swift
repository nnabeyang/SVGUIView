import _CSSParser

public enum Component<Impl: SelectorImpl>: Equatable {
  case localName(LocalName<Impl>)
  case id(Impl.Identifier)
  case `class`(Impl.Identifier)
  case attributeInNoNamespaceExists(localName: Impl.LocalName, localNameLower: Impl.LocalName)
  case attributeInNoNamespace(
    localName: Impl.LocalName,
    operator: AttrSelectorOperator,
    value: Impl.AttrValue,
    caseSensitivity: ParsedCaseSensitivity
  )
  case attributeOther(AttrSelectorWithOptionalNamespace<Impl>)
  case explicitUniversalType
  case explicitAnyNamespace
  case explicitNoNamespace
  case defaultNamespace(url: Impl.NamespaceUrl)
  case namespace(prefix: Impl.NamespacePrefix, url: Impl.NamespaceUrl)
  case negation(SelectorList<Impl>)
  case root
  case empty
  case scope
  case implicitScope
  case parentSelector
  case nth(NthSelectorData)
  case nthOf(NthOfSelectorData<Impl>)
  case nonTSPseudoClass(Impl.NonTSPseudoClass)
  case slotted(Selector<Impl>)
  case part([Impl.Identifier])
  case host(Selector<Impl>?)
  case `where`(SelectorList<Impl>)
  case `is`(SelectorList<Impl>)
  case has([RelativeSelector<Impl>])
  case invalid(String)
  case pseudoElement(Impl.PseudoElement)
  case combinator(Combinator)
  case relativeSelectorAnchor

  public var isCombinator: Bool {
    switch self {
    case .combinator: true
    default: false
    }
  }

  public var isHost: Bool {
    switch self {
    case .host: true
    default: false
    }
  }

  public func asCombinator() -> Combinator? {
    switch self {
    case .combinator(let combinator): combinator
    default: nil
    }
  }

  public func visit<V: SelectorVisitor>(visitor: inout V) -> Bool where V.Impl == Impl {
    guard visitor.visitSimpleSelector(self) else { return false }
    switch self {
    case .slotted(let selector):
      guard selector.visit(&visitor) else {
        return false
      }
    case .host(.some(let selector)):
      guard selector.visit(&visitor) else {
        return false
      }
    case .attributeInNoNamespaceExists(let localName, let localNameLower):
      guard visitor.visitAttributeSelector(namespace: .specific(Impl.NamespaceUrl.default()), localName: localName, localNameLower: localNameLower) else {
        return false
      }
    case .attributeInNoNamespace(let localName, _, _, _):
      guard visitor.visitAttributeSelector(namespace: .specific(Impl.NamespaceUrl.default()), localName: localName, localNameLower: localName) else {
        return false
      }
    case .attributeOther(let attrSelector):
      let namespace: NamespaceConstraint<Impl.NamespaceUrl> =
        switch attrSelector.getNamespace() {
        case .some(let ns): ns
        case .none: .specific(Impl.NamespaceUrl.default())
        }
      guard visitor.visitAttributeSelector(namespace: namespace, localName: attrSelector.localName, localNameLower: attrSelector.localNameLower) else {
        return false
      }
    case .nonTSPseudoClass(let pseudoClass):
      guard pseudoClass.visit(&visitor) else {
        return false
      }
    case .negation(let list), .is(let list), .where(let list):
      let listKind = SelectorListKind(from: self)
      assert(!listKind.isEmpty)
      guard visitor.visitSelectorList(listKind: listKind, list: list.slice) else {
        return false
      }
    case .nthOf(let nthOfData):
      guard visitor.visitSelectorList(listKind: .nthOf, list: nthOfData.selectors) else {
        return false
      }
    case .has(let list):
      guard visitor.visitRelativeSelectorList(list: list) else {
        return false
      }
    default:
      break
    }
    return true
  }

  public func hasIndexedSelectorInSubject() -> Bool {
    switch self {
    case .nthOf, .nth: return true
    case .is(let selectors), .where(let selectors), .negation(let selectors):
      for selector in selectors.slice {
        var iter = selector.makeIterator()
        while let c = iter.next() {
          if c.hasIndexedSelectorInSubject() {
            return true
          }
        }
      }
    default:
      break
    }
    return false
  }

  func matchesForStatelessPseudoElement() -> Bool {
    switch self {
    case .negation(let selectors):
      !selectors.slice.allSatisfy({ selector in
        selector.iterRawMatchOrder().allSatisfy({ c in
          c.matchesForStatelessPseudoElement()
        })
      })
    case .is(let selectors), .where(let selectors):
      selectors.slice.contains(where: { selector in
        selector.iterRawMatchOrder().allSatisfy({ c in
          c.matchesForStatelessPseudoElement()
        })
      })
    default:
      false
    }
  }
}

extension Component: ToCSS {
  public func toCSS(to dest: inout some TextOutputStream) {
    switch self {
    case .combinator(let c):
      c.toCSS(to: &dest)
    case .slotted(let selector):
      dest.write("::slotted(")
      selector.toCSS(to: &dest)
      dest.write(")")
    case .part(let partNames):
      dest.write("::part(")
      for (i, name) in partNames.enumerated() {
        if i != 0 {
          dest.write(" ")
        }
        name.toCSS(to: &dest)
      }
      dest.write(")")
    case .pseudoElement(let p):
      p.toCSS(to: &dest)
    case .id(let s):
      dest.write("#")
      s.toCSS(to: &dest)
    case .class(let s):
      dest.write(".")
      s.toCSS(to: &dest)
    case .localName(let s):
      s.toCSS(to: &dest)
    case .explicitUniversalType:
      dest.write("*")
    case .defaultNamespace:
      break
    case .explicitNoNamespace:
      dest.write("|")
    case .explicitAnyNamespace:
      dest.write("*|")
    case .namespace(let prefix, _):
      prefix.toCSS(to: &dest)
      dest.write("|")
    case .attributeInNoNamespaceExists(let localName, _):
      dest.write("[")
      localName.toCSS(to: &dest)
      dest.write("]")
    case .attributeInNoNamespace(let localName, let op, let value, let caseSensitivity):
      dest.write("[")
      localName.toCSS(to: &dest)
      op.toCSS(to: &dest)
      value.toCSS(to: &dest)
      switch caseSensitivity {
      case .caseSensitive, .asciiCaseInsensitiveIfInHtmlElementInHtmlDocument:
        break
      case .asciiCaseInsensitive:
        dest.write(" i")
      case .explicitCaseSensitive:
        dest.write(" s")
      }
      dest.write("]")
    case .attributeOther(let attrSelector):
      attrSelector.toCSS(to: &dest)
    case .root:
      dest.write(":root")
    case .empty:
      dest.write(":empty")
    case .scope:
      dest.write(":scope")
    case .parentSelector:
      dest.write("&")
    case .host(let selector):
      dest.write(":host")
      guard let selector else { return }
      dest.write("(")
      selector.toCSS(to: &dest)
      dest.write(")")
    case .nth(let nthData):
      nthData.writeStart(dest: &dest)
      guard nthData.isFunction else { return }
      nthData.writeAffine(dest: &dest)
      dest.write(")")
    case .nthOf(let nthOfData):
      let nthData = nthOfData.nthData
      nthData.writeStart(dest: &dest)
      assert(nthData.isFunction, "A selector must be a function to hold An+B notation")
      nthData.writeAffine(dest: &dest)
      assert(nthData.ty.isChild, "Only :nth-child or :nth-last-child can be of a selector list")
      assert(!nthOfData.selectors.isEmpty, "The selector list should not be empty")
      dest.write(" of ")
      var iter = nthOfData.selectors.makeIterator()
      serializeSelectorList(iter: &iter, dest: &dest)
      dest.write(")")
    case .is(let list):
      dest.write(":is(")
      var iter = list.makeIterator()
      serializeSelectorList(iter: &iter, dest: &dest)
      dest.write(")")
    case .where(let list):
      dest.write(":where(")
      var iter = list.makeIterator()
      serializeSelectorList(iter: &iter, dest: &dest)
      dest.write(")")
    case .negation(let list):
      dest.write(":not(")
      var iter = list.makeIterator()
      serializeSelectorList(iter: &iter, dest: &dest)
      dest.write(")")
    case .has(let list):
      dest.write(":has(")
      var first = true
      var iter = list.makeIterator()
      while let relativeSelector = iter.next() {
        if !first {
          dest.write(", ")
        }
        first = false
        relativeSelector.selector.toCSS(to: &dest)
      }
      dest.write(")")
    case .nonTSPseudoClass(let pseudo):
      pseudo.toCSS(to: &dest)
    case .invalid(let css):
      dest.write(css)
    case .relativeSelectorAnchor, .implicitScope:
      break
    }
  }
}

public struct LocalName<Impl: SelectorImpl>: Equatable {
  public let name: Impl.LocalName
  public let lowerName: Impl.LocalName

  public init(name: Impl.LocalName, lowerName: Impl.LocalName) {
    self.name = name
    self.lowerName = lowerName
  }
}

extension LocalName: ToCSS {
  public func toCSS(to dest: inout some TextOutputStream) {
    name.toCSS(to: &dest)
  }
}

func serializeSelectorList<Impl: SelectorImpl, I: IteratorProtocol, W: TextOutputStream>(iter: inout I, dest: inout W) where I.Element == Selector<Impl> {
  var first = true
  while let selector = iter.next() {
    if !first {
      dest.write(", ")
    }
    first = false
    selector.toCSS(to: &dest)
  }
}
