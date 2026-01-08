public struct PrefixStaticSet: StaticAtomSet {
  private static let map: [String: Int] = [
    "*": 0,
    "html": 1,
    "mathml": 2,
    "svg": 3,
    "xlink": 4,
    "xml": 5,
    "xmlns": 6,
  ]
  public static func get() -> [String: Int]? { map }
}
