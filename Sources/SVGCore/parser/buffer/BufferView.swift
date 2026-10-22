struct BufferView<Element> {
  typealias Index = BufferViewIndex<Element>

  let start: Index
  let count: Int

  init(start: Index, count: Int) {
    self.start = start
    self.count = count
  }

  init(baseAddress: UnsafeRawPointer, count: Int) {
    self.init(start: BufferViewIndex(rawValue: baseAddress), count: count)
  }

  init?(unsafeBufferPointer buffer: UnsafeBufferPointer<Element>) {
    guard let baseAddress = UnsafeRawPointer(buffer.baseAddress) else { return nil }
    self.init(baseAddress: baseAddress, count: buffer.count)
  }

  private var baseAddress: UnsafeRawPointer { start.rawValue }
}

extension BufferView: Collection {
  typealias Element = Element
  typealias SubSeqence = Self

  var startIndex: Index {
    start
  }

  var endIndex: Index {
    start.advanced(by: count)
  }

  func distance(from start: BufferViewIndex<Element>, to end: BufferViewIndex<Element>) -> Int {
    start.distance(to: end)
  }

  subscript(position: Index) -> Element {
    self[unchecked: position]
  }

  subscript(unchecked position: Index) -> Element {
    position.rawValue.load(as: Element.self)
  }

  subscript(bounds: Range<Index>) -> Self {
    self[unchecked: bounds]
  }

  subscript(unchecked bounds: Range<Index>) -> Self {
    BufferView(start: bounds.lowerBound, count: bounds.count)
  }

  func index(after i: Index) -> Index {
    i.advanced(by: +1)
  }
}

extension BufferView: BidirectionalCollection {
  func index(before i: Index) -> Index {
    i.advanced(by: -1)
  }
}

extension BufferView: RandomAccessCollection {
  func formIndex(after i: inout Index) {
    i = index(after: i)
  }

  func formIndex(before i: inout Index) {
    i = index(before: i)
  }

  func index(_ i: Index, offsetBy distance: Int) -> Index {
    i.advanced(by: distance)
  }

  func formIndex(_ i: inout Index, offsetBy distance: Int) {
    i = i.advanced(by: distance)
  }
}

extension BufferView {
  func withUnsafePointer<R>(
    _ body:
      @escaping (
        _ pointer: UnsafePointer<Element>,
        _ capacity: Int
      ) throws -> R
  ) rethrows -> R {
    try baseAddress.withMemoryRebound(to: Element.self, capacity: count) {
      try body($0, count)
    }
  }
}
