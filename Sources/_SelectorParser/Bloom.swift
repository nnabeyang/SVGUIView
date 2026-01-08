let KEY_SIZE = 12
let ARRAY_SIZE: Int = 1 << KEY_SIZE
let KEY_MASK: UInt32 = (1 << KEY_SIZE) - 1

public struct CountingBloomFilter<S: BloomStorage> {
  public var storage: S

  public init(storage: S) {
    self.storage = storage
  }
}

public typealias BloomFilter = CountingBloomFilter<BloomStorageU8>

public protocol BloomStorage: Default {
  mutating func adjustSlot(_ index: Int, increment: Bool)
  func slotIsEmpty(_ index: Int) -> Bool
  var isZeroed: Bool { get }
  func firstSlotIndex(hash: UInt32) -> Bool
  func secondSlotIsEmpty(hash: UInt32) -> Bool
  mutating func adjustFirstSlot(hash: UInt32, increment: Bool)
  mutating func adjustSecondSlot(hash: UInt32, increment: Bool)
  static func firstSlotIndex(hash: UInt32) -> Int
  static func secondSlotIndex(hash: UInt32) -> Int
}

extension BloomStorage {
  public func firstSlotIndex(hash: UInt32) -> Bool {
    slotIsEmpty(Self.firstSlotIndex(hash: hash))
  }

  public func secondSlotIsEmpty(hash: UInt32) -> Bool {
    slotIsEmpty(Self.secondSlotIndex(hash: hash))
  }

  public mutating func adjustFirstSlot(hash: UInt32, increment: Bool) {
    adjustSlot(Self.firstSlotIndex(hash: hash), increment: increment)
  }

  public mutating func adjustSecondSlot(hash: UInt32, increment: Bool) {
    adjustSlot(Self.secondSlotIndex(hash: hash), increment: increment)
  }

  public static func firstSlotIndex(hash: UInt32) -> Int {
    Int(hash1(hash))
  }

  public static func secondSlotIndex(hash: UInt32) -> Int {
    Int(hash2(hash))
  }
}

public struct BloomStorageU8 {
  var counters: [UInt8]
}

extension BloomStorageU8: BloomStorage {
  public mutating func adjustSlot(_ index: Int, increment: Bool) {
    guard counters[index] != 0xff else { return }
    if increment {
      counters[index] += 1
    } else {
      counters[index] -= 1
    }
  }

  public func slotIsEmpty(_ index: Int) -> Bool {
    counters[index] == 0
  }

  public var isZeroed: Bool {
    counters.allSatisfy({ $0 == 0 })
  }
}

extension BloomStorageU8: Default {
  public static func `default`() -> Self {
    BloomStorageU8(counters: [UInt8](repeating: 0, count: ARRAY_SIZE))
  }
}

func hash1(_ hash: UInt32) -> UInt32 {
  hash & KEY_MASK
}

func hash2(_ hash: UInt32) -> UInt32 {
  (hash >> KEY_SIZE) & KEY_MASK
}
