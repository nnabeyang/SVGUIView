struct ElementState: OptionSet, Sendable {
  let rawValue: UInt64

  init(rawValue: UInt64) {
    self.rawValue = rawValue
  }

  static let empty: Self = []

  static let active = Self(rawValue: 1 << 0)
  static let focus = Self(rawValue: 1 << 1)
  static let hover = Self(rawValue: 1 << 2)
  static let enabled = Self(rawValue: 1 << 3)
  static let disabled = Self(rawValue: 1 << 4)
  static let checked = Self(rawValue: 1 << 5)
  static let indeterminate = Self(rawValue: 1 << 6)
  static let placeholderShown = Self(rawValue: 1 << 7)
  static let urlTarget = Self(rawValue: 1 << 8)
  static let fullscreen = Self(rawValue: 1 << 9)
  static let valid = Self(rawValue: 1 << 10)
  static let invalid = Self(rawValue: 1 << 11)
  static let userValid = Self(rawValue: 1 << 12)
  static let userInvalid = Self(rawValue: 1 << 13)
  static let broken = Self(rawValue: 1 << 14)
  static let required = Self(rawValue: 1 << 15)
  static let optional = Self(rawValue: 1 << 16)
  static let defined = Self(rawValue: 1 << 17)
  static let visited = Self(rawValue: 1 << 18)
  static let unvisited = Self(rawValue: 1 << 19)
  static let dragover = Self(rawValue: 1 << 20)
  static let inRange = Self(rawValue: 1 << 21)
  static let outOfRange = Self(rawValue: 1 << 22)
  static let readOnly = Self(rawValue: 1 << 23)
  static let readWrite = Self(rawValue: 1 << 24)
  static let `default` = Self(rawValue: 1 << 25)
  static let optimum = Self(rawValue: 1 << 26)
  static let subOptimum = Self(rawValue: 1 << 27)
  static let subSubOptimum = Self(rawValue: 1 << 28)
  static let incrementScriptLevel = Self(rawValue: 1 << 29)
  static let focusRing = Self(rawValue: 1 << 30)
  static let focusWithin = Self(rawValue: 1 << 31)
  static let ltr = Self(rawValue: 1 << 32)
  static let rtl = Self(rawValue: 1 << 33)
  static let hasDirAttr = Self(rawValue: 1 << 34)
  static let hasDirAttrLtr = Self(rawValue: 1 << 35)
  static let hasDirAttrRtl = Self(rawValue: 1 << 36)
  static let hasDirAttrLikeAuto = Self(rawValue: 1 << 37)
  static let autofill = Self(rawValue: 1 << 38)
  static let autofillPreview = Self(rawValue: 1 << 39)
  static let modal = Self(rawValue: 1 << 40)
  static let inert = Self(rawValue: 1 << 41)
  static let topmostModal = Self(rawValue: 1 << 42)
  static let devtoolsHighlighted = Self(rawValue: 1 << 43)
  static let styleeditorTransitioning = Self(rawValue: 1 << 44)
  static let valueEmpty = Self(rawValue: 1 << 45)
  static let revealed = Self(rawValue: 1 << 46)
  static let popoverOpen = Self(rawValue: 1 << 47)
  static let hasSlotted = Self(rawValue: 1 << 48)
  static let open = Self(rawValue: 1 << 49)
  static let activeViewTransition = Self(rawValue: 1 << 50)
  static let suppressForPrintSelection = Self(rawValue: 1 << 51)

  static let visitedOrUnvisited: Self = [visited, unvisited]
  static let validityStates: Self = [.valid, .invalid, .userValid, .userInvalid]
  static let meterOptimumStates: Self = [.optimum, .subOptimum, .subSubOptimum]
  static let meterOptinumStates: Self = [.optimum, .subOptimum, .subSubOptimum]

  static let dirStates: Self = [ltr, .rtl]
  static let dirAttrStates: Self = [.hasDirAttr, .hasDirAttrLtr, .hasDirAttrRtl, .hasDirAttrLikeAuto]
  static let disabledStates: Self = [.disabled, .enabled]
  static let requiredStates: Self = [.required, .optional]
}
