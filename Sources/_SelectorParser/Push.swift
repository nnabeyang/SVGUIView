public protocol Push {
  associatedtype Element
  mutating func push(_ value: Element)
}

extension Array: Push {
  public mutating func push(_ value: Element) {
    append(value)
  }
}
