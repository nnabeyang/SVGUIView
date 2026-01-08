public enum Origin: UInt8 {
  case userAgent = 1
  case user = 2
  case author = 4

  static func fromIndex(_ index: Int) -> Self? {
    switch index {
    case 0: .author
    case 1: .user
    case 2: .userAgent
    default: nil
    }
  }
}
