public protocol Into {
  func into<T: From>() -> T where T.From == Self
}

extension Into {
  public func into<T: From>() -> T where T.From == Self {
    T.from(self)
  }
}

public protocol From {
  associatedtype From
  static func from(_ other: From) -> Self
}
