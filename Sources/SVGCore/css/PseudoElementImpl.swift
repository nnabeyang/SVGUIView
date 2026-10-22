import _CSSParser
import _SelectorParser

enum PseudoElementImpl: Int, Equatable {
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

  static let count = Self.placeholder.rawValue + 1
  static let eagerCount = 3
}

extension PseudoElementImpl: ToCSS {
  func toCSS(to dest: inout some TextOutputStream) {
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
  typealias Impl = SVGSelectorImpl
}
