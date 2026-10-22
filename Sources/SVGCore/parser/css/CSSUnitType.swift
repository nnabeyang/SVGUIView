enum CSSUnitType: UInt8 {
  case unknown = 0
  case number = 1
  case percentage = 2
  case ems = 3
  case exs = 4
  case px = 5
  case cm = 6
  case mm = 7
  case `in` = 8
  case pt = 9
  case pc = 10
  case deg = 11
  case rad = 12
  case grad = 13
  case ms = 14
  case s = 15
  case hz = 16
  case khz = 17
  case dimension = 18
  case string = 19
  case uri = 20
  case indent = 21
  case attr = 22
  case counter = 23
  case rect = 24
  case rgbcolor = 25
  case chs = 26
  case ic = 27
  case rems = 28
  case lhs = 29
  case rlhs = 30

  init(_ string: String) {
    switch string {
    case "hz":
      self = .hz
    case "cm":
      self = .cm
    case "px":
      self = .px
    case "em":
      self = .ems
    case "ex":
      self = .exs
    case "mm":
      self = .mm
    case "ch":
      self = .chs
    case "ic":
      self = .ic
    case "rem":
      self = .rems
    case "lh":
      self = .lhs
    case "rlh":
      self = .rlhs
    default:
      self = .px
    }
  }
}
