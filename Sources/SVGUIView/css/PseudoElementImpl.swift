import _CSSParser
import _SelectorParser

public enum PseudoElementImpl: Int, Equatable {
  // Eager pseudos.
  case after = 0
  case before
  case selection
  // Non-eager pseudos.
  case backdrop
  case marker
  // Implemented pseudos.
  case colorSwatch
  case placeholder

  public static let count = Self.placeholder.rawValue + 1
  public static let eagerCount = 3
}

extension PseudoElementImpl: ToCSS {
  public func toCSS(to dest: inout some TextOutputStream) {
    let string =
      switch self {
      case .after: "::after"
      case .before: "::before"
      case .selection: "::selection"
      case .backdrop: "::backdrop"
      case .marker: "::marker"
      case .colorSwatch: "::color-swatch"
      case .placeholder: "::placeholder"
      }
    dest.write(string)
  }
}

extension PseudoElementImpl: PseudoElement {
  public typealias Impl = SelectorImpl
}
