import _CSSParser

public enum Combinator {
  case child  // >
  case descendant  // space
  case nextSibling  // +
  case laterSibling  // ~
  case pseudoElement
  case slotAssignment
  case part

  public var isAncestor: Bool {
    switch self {
    case .child, .descendant, .pseudoElement, .slotAssignment:
      true
    default:
      false
    }
  }

  public var isPseudoElement: Bool {
    switch self {
    case .pseudoElement:
      true
    default:
      false
    }
  }

  public var isSibling: Bool {
    switch self {
    case .nextSibling, .laterSibling:
      true
    default:
      false
    }
  }
}

extension Combinator: ToCSS {
  public func toCSS(to dest: inout some TextOutputStream) {
    toCSSInternal(to: &dest, prefixSpace: true)
  }

  func toCSSInternal(to dest: inout some TextOutputStream, prefixSpace: Bool) {
    switch self {
    case .pseudoElement, .part, .slotAssignment:
      return
    default:
      break
    }
    if prefixSpace {
      dest.write(" ")
    }
    switch self {
    case .child: dest.write("> ")
    case .descendant: break
    case .nextSibling: dest.write("+ ")
    case .laterSibling: dest.write("~ ")
    case .pseudoElement, .part, .slotAssignment:
      fatalError("Already handled")
    }
  }

  func toCSSRelative(to dest: inout some TextOutputStream) {
    self.toCSSInternal(to: &dest, prefixSpace: false)
  }
}
