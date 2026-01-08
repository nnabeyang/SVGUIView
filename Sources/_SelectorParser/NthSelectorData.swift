import _CSSParser

public struct AnPlusB: Equatable {
  public let a: Int32
  public let b: Int32

  public func matchesIndex(i: Int32) -> Bool {
    if let an = i.checkedSub(b) {
      if let n = an.checkedDiv(a) {
        n >= 0 && a * n == an
      } else {
        an == 0
      }
    } else {
      false
    }
  }
}

extension AnPlusB: ToCSS {
  public func toCSS(to dest: inout some TextOutputStream) {
    let css =
      switch (a, b) {
      case (0, 0): "0"
      case (1, 0): "n"
      case (-1, 0): "-n"
      case (let n, 0): "\(n)n"
      case (0, let n): "\(n)"
      case (1, let n): "n\(String(format: "%+d", n))"
      case (-1, let n): "-n\(String(format: "%+d", n))"
      case (let a, let b): "\(a)n\(String(format: "%+d", b))"
      }
    dest.write(css)
  }
}

public struct NthSelectorData: Equatable {
  public let ty: NthType
  public let isFunction: Bool
  public let anPlusB: AnPlusB

  public static func only(ofType: Bool) -> Self {
    Self(
      ty: ofType ? .onlyOfType : .onlyChild,
      isFunction: false,
      anPlusB: .init(a: 0, b: 1)
    )
  }

  public static func first(ofType: Bool) -> Self {
    Self(
      ty: ofType ? .ofType : .child,
      isFunction: false,
      anPlusB: .init(a: 0, b: 1)
    )
  }

  public static func last(ofType: Bool) -> Self {
    Self(
      ty: ofType ? .lastOfType : .lastChild,
      isFunction: false,
      anPlusB: .init(a: 0, b: 1)
    )
  }

  public var isSimpleEdge: Bool {
    anPlusB.a == 0
      && anPlusB.b == 1
      && !ty.isOfType
      && !ty.isOnly
  }

  func writeStart(dest: inout some TextOutputStream) {
    let css =
      switch ty {
      case .child: isFunction ? ":nth-child(" : ":first-child"
      case .lastChild: isFunction ? ":nth-last-child(" : ":last-child"
      case .ofType: isFunction ? ":nth-of-type(" : ":first-of-type"
      case .lastOfType: isFunction ? ":nth-last-of-type(" : ":last-of-type"
      case .onlyChild: ":only-child"
      case .onlyOfType: ":only-of-type"
      }
    dest.write(css)
  }

  func writeAffine(dest: inout some TextOutputStream) {
    anPlusB.toCSS(to: &dest)
  }
}

public enum NthType {
  case child
  case lastChild
  case onlyChild
  case ofType
  case lastOfType
  case onlyOfType

  public var isOnly: Bool {
    switch self {
    case .onlyChild, .onlyOfType:
      return true
    default:
      return false
    }
  }

  public var isOfType: Bool {
    switch self {
    case .ofType, .lastOfType, .onlyOfType:
      return true
    default:
      return false
    }
  }

  public var isFromEnd: Bool {
    switch self {
    case .lastChild, .lastOfType:
      return true
    default:
      return false
    }
  }

  public var isChild: Bool {
    switch self {
    case .child:
      return true
    default:
      return false
    }
  }
}

public struct NthOfSelectorData<Impl: SelectorImpl>: Equatable {
  public let nthData: NthSelectorData
  public let selectors: [Selector<Impl>]
}
