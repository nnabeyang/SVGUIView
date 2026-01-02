struct LazySplitSequence<Base: Collection> {

  private let storage: [[Base.Element]]

  init(base: Base, isSeparator: (Base.Element) -> Bool) {
    var result: [[Base.Element]] = []
    var current: [Base.Element] = []

    for e in base {
      if isSeparator(e) {
        if !current.isEmpty {
          result.append(current)
          current = []
        }
      } else {
        current.append(e)
      }
    }
    if !current.isEmpty {
      result.append(current)
    }

    self.storage = result
  }
}

extension LazySplitSequence: RandomAccessCollection {

  typealias Element = [Base.Element]
  typealias Index = Int

  var startIndex: Int { storage.startIndex }
  var endIndex: Int { storage.endIndex }

  subscript(position: Int) -> Element {
    storage[position]
  }

  func index(after i: Int) -> Int { i + 1 }
  func index(before i: Int) -> Int { i - 1 }
}

extension Collection {
  func lazySplit(
    whereSeparator isSeparator: (Element) -> Bool
  ) -> LazySplitSequence<Self> {
    LazySplitSequence(base: self, isSeparator: isSeparator)
  }
}
