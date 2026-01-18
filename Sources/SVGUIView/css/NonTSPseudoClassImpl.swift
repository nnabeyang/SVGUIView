import _CSSParser
import _SelectorParser

public enum NonTSPseudoClassImpl: Equatable {
  case active
  case anyLink
  case autofill
  case checked
  /// The :state` pseudo-class.
  case customState(CustomState)
  case `default`
  case defined
  case disabled
  case enabled
  case focus
  case focusWithin
  case focusVisible
  case fullscreen
  case hover
  case inRange
  case indeterminate
  case invalid
  case lang(String)
  case link
  case modal
  case mozMeterOptimum
  case mozMeterSubOptimum
  case mozMeterSubSubOptimum
  case optional
  case outOfRange
  case placeholderShown
  case popoverOpen
  case readOnly
  case readWrite
  case required
  case target
  case userInvalid
  case userValid
  case valid
  case visited
}

extension NonTSPseudoClassImpl: NonTSPseudoClass {
  public typealias Impl = SVGSelectorImpl

  public func isActiveOrHover() -> Bool {
    switch self {
    case .active, .hover: true
    default: false
    }
  }

  public func isUserActionState() -> Bool {
    switch self {
    case .active, .hover, .focus: true
    default: false
    }
  }

  public func visit<V: SelectorVisitor>(_ visitor: inout V) -> Bool where V.Impl == Impl {
    true
  }
}

extension NonTSPseudoClassImpl: ToCSS {
  public func toCSS(to dest: inout some TextOutputStream) {
    if case .lang(let lang) = self {
      dest.write(":lang(")
      serializeIdentifier(lang, dest: &dest)
      dest.write(")")
      return
    }
    if case .customState(let state) = self {
      dest.write(":state(")
      state.toCSS(to: &dest)
      dest.write(")")
      return
    }
    let string =
      switch self {
      case .active: ":active"
      case .anyLink: ":any-link"
      case .autofill: ":autofill"
      case .checked: ":checked"
      case .default: ":default"
      case .defined: ":defined"
      case .disabled: ":disabled"
      case .enabled: ":enabled"
      case .focus: ":focus"
      case .focusVisible: ":focus-visible"
      case .focusWithin: ":focus-within"
      case .fullscreen: ":fullscreen"
      case .hover: ":hover"
      case .inRange: ":in-range"
      case .indeterminate: ":indeterminate"
      case .invalid: ":invalid"
      case .link: ":link"
      case .modal: ":modal"
      case .mozMeterOptimum: ":-moz-meter-optimum"
      case .mozMeterSubOptimum: ":-moz-meter-sub-optimum"
      case .mozMeterSubSubOptimum: ":-moz-meter-sub-sub-optimum"
      case .optional: ":optional"
      case .outOfRange: ":out-of-range"
      case .placeholderShown: ":placeholder-shown"
      case .popoverOpen: ":popover-open"
      case .readOnly: ":read-only"
      case .readWrite: ":read-write"
      case .required: ":required"
      case .target: ":target"
      case .userInvalid: ":user-invalid"
      case .userValid: ":user-valid"
      case .valid: ":valid"
      case .visited: ":visited"
      case .lang, .customState: fatalError("unreachable")
      }
    dest.write(string)
  }
}

extension NonTSPseudoClassImpl {
  public var stateFlag: ElementState {
    switch self {
    case .active: .active
    case .anyLink: .visitedOrUnvisited
    case .autofill: .autofill
    case .checked: .checked
    case .default: .default
    case .defined: .defined
    case .disabled: .disabled
    case .enabled: .enabled
    case .focus: .focus
    case .focusVisible: .focusRing
    case .focusWithin: .focusWithin
    case .fullscreen: .fullscreen
    case .hover: .hover
    case .inRange: .inRange
    case .indeterminate: .indeterminate
    case .invalid: .invalid
    case .link: .unvisited
    case .modal: .modal
    case .mozMeterOptimum: .optimum
    case .mozMeterSubOptimum: .subOptimum
    case .mozMeterSubSubOptimum: .subSubOptimum
    case .optional: .optional
    case .outOfRange: .outOfRange
    case .placeholderShown: .placeholderShown
    case .popoverOpen: .popoverOpen
    case .readOnly: .readOnly
    case .readWrite: .readWrite
    case .required: .required
    case .target: .urlTarget
    case .userInvalid: .userInvalid
    case .userValid: .userValid
    case .valid: .valid
    case .visited: .visited
    case .customState, .lang: .empty
    }
  }

  public var documentStateFlag: DocumentState {
    .empty
  }

  public var needsCacheRevalidation: Bool {
    self.stateFlag.isEmpty
  }
}
