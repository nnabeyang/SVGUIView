import _CSSParser

public enum KleeneValue {
  case `false`
  case `true`
  case unknown

  public func toBool(unknown: Bool) -> Bool {
    switch self {
    case .true:
      return true
    case .false:
      return false
    case .unknown:
      return unknown
    }
  }
}

extension KleeneValue: From {
  public static func from(_ other: Bool) -> Self {
    switch other {
    case true:
      return .true
    case false:
      return .false
    }
  }
}

extension KleeneValue {
  public static func any<T>(iter: inout some IteratorProtocol<T>, f: @escaping (T) -> Self) -> Self {
    anyValue(iter: &iter, value: .true, onEmpty: .false, op: { (a, b) in a | b }, f: f)
  }

  public static func anyFalse<T>(iter: inout some IteratorProtocol<T>, f: @escaping (T) -> Self) -> Self {
    anyValue(iter: &iter, value: .false, onEmpty: .true, op: { (a, b) in a & b }, f: f)
  }

  static func anyValue<T>(
    iter: inout some IteratorProtocol<T>, value: Self, onEmpty: Self,
    op: @escaping (Self, Self) -> Self, f: @escaping (T) -> Self
  ) -> Self {
    var result: Self? = nil
    while let item = iter.next() {
      let r = f(item)
      if r == value {
        return r
      }
      if let v = result {
        result = op(v, r)
      } else {
        result = r
      }
    }
    return result ?? onEmpty
  }

  static prefix func ! (value: Self) -> Self {
    switch value {
    case .true: return .false
    case .false: return .true
    case .unknown: return .unknown
    }
  }

  static func & (lhs: Self, rhs: Self) -> Self {
    switch (lhs, rhs) {
    case (.false, _), (_, .false): return .false
    case (.unknown, _), (_, .unknown): return .unknown
    default: return .true
    }
  }

  static func | (lhs: KleeneValue, rhs: KleeneValue) -> KleeneValue {
    switch (lhs, rhs) {
    case (.true, _), (_, .true): return .true
    case (.unknown, _), (_, .unknown): return .unknown
    default: return .false
    }
  }

  static func |= (lhs: inout KleeneValue, rhs: KleeneValue) {
    lhs = lhs | rhs
  }

  static func &= (lhs: inout KleeneValue, rhs: KleeneValue) {
    lhs = lhs & rhs
  }
}
