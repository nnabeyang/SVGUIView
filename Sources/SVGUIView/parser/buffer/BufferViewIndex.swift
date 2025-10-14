struct BufferViewIndex<Element> {
  let rawValue: UnsafeRawPointer
  init(rawValue: UnsafeRawPointer) {
    self.rawValue = rawValue
  }
}

extension BufferViewIndex: Equatable {}

extension BufferViewIndex: Hashable {}

extension BufferViewIndex: Strideable {
  typealias Stride = Int
  func distance(to other: Self) -> Int {
    rawValue.distance(to: other.rawValue) / MemoryLayout<Element>.stride
  }

  func advanced(by n: Int) -> Self {
    BufferViewIndex(rawValue: rawValue.advanced(by: n &* MemoryLayout<Element>.stride))
  }
}

extension BufferViewIndex: Comparable {
  static func < (lhs: BufferViewIndex, rhs: BufferViewIndex) -> Bool {
    lhs.rawValue < rhs.rawValue
  }
}
