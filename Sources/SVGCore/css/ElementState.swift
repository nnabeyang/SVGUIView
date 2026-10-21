public struct ElementState: OptionSet, Sendable {
  public let rawValue: UInt64

  public init(rawValue: UInt64) {
    self.rawValue = rawValue
  }

  public static let empty: Self = []

  public static let active = Self(rawValue: 1 << 0)
  public static let focus = Self(rawValue: 1 << 1)
  public static let hover = Self(rawValue: 1 << 2)
  public static let enabled = Self(rawValue: 1 << 3)
  public static let disabled = Self(rawValue: 1 << 4)
  public static let checked = Self(rawValue: 1 << 5)
  public static let indeterminate = Self(rawValue: 1 << 6)
  public static let placeholderShown = Self(rawValue: 1 << 7)
  public static let urlTarget = Self(rawValue: 1 << 8)
  public static let fullscreen = Self(rawValue: 1 << 9)
  public static let valid = Self(rawValue: 1 << 10)
  public static let invalid = Self(rawValue: 1 << 11)
  public static let userValid = Self(rawValue: 1 << 12)
  public static let userInvalid = Self(rawValue: 1 << 13)
  public static let broken = Self(rawValue: 1 << 14)
  public static let required = Self(rawValue: 1 << 15)
  public static let optional = Self(rawValue: 1 << 16)
  public static let defined = Self(rawValue: 1 << 17)
  public static let visited = Self(rawValue: 1 << 18)
  public static let unvisited = Self(rawValue: 1 << 19)
  public static let dragover = Self(rawValue: 1 << 20)
  public static let inRange = Self(rawValue: 1 << 21)
  public static let outOfRange = Self(rawValue: 1 << 22)
  public static let readOnly = Self(rawValue: 1 << 23)
  public static let readWrite = Self(rawValue: 1 << 24)
  public static let `default` = Self(rawValue: 1 << 25)
  public static let optimum = Self(rawValue: 1 << 26)
  public static let subOptimum = Self(rawValue: 1 << 27)
  public static let subSubOptimum = Self(rawValue: 1 << 28)
  public static let incrementScriptLevel = Self(rawValue: 1 << 29)
  public static let focusRing = Self(rawValue: 1 << 30)
  public static let focusWithin = Self(rawValue: 1 << 31)
  public static let ltr = Self(rawValue: 1 << 32)
  public static let rtl = Self(rawValue: 1 << 33)
  public static let hasDirAttr = Self(rawValue: 1 << 34)
  public static let hasDirAttrLtr = Self(rawValue: 1 << 35)
  public static let hasDirAttrRtl = Self(rawValue: 1 << 36)
  public static let hasDirAttrLikeAuto = Self(rawValue: 1 << 37)
  public static let autofill = Self(rawValue: 1 << 38)
  public static let autofillPreview = Self(rawValue: 1 << 39)
  public static let modal = Self(rawValue: 1 << 40)
  public static let inert = Self(rawValue: 1 << 41)
  public static let topmostModal = Self(rawValue: 1 << 42)
  public static let devtoolsHighlighted = Self(rawValue: 1 << 43)
  public static let styleeditorTransitioning = Self(rawValue: 1 << 44)
  public static let valueEmpty = Self(rawValue: 1 << 45)
  public static let revealed = Self(rawValue: 1 << 46)
  public static let popoverOpen = Self(rawValue: 1 << 47)
  public static let hasSlotted = Self(rawValue: 1 << 48)
  public static let open = Self(rawValue: 1 << 49)
  public static let activeViewTransition = Self(rawValue: 1 << 50)
  public static let suppressForPrintSelection = Self(rawValue: 1 << 51)

  public static let visitedOrUnvisited: Self = [visited, unvisited]
  public static let validityStates: Self = [.valid, .invalid, .userValid, .userInvalid]
  public static let meterOptimumStates: Self = [.optimum, .subOptimum, .subSubOptimum]
  public static let meterOptinumStates: Self = [.optimum, .subOptimum, .subSubOptimum]

  public static let dirStates: Self = [ltr, .rtl]
  public static let dirAttrStates: Self = [.hasDirAttr, .hasDirAttrLtr, .hasDirAttrRtl, .hasDirAttrLikeAuto]
  public static let disabledStates: Self = [.disabled, .enabled]
  public static let requiredStates: Self = [.required, .optional]
}
