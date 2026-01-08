public struct NamespaceStaticSet: StaticAtomSet {
  private static let map: [String: Int] = [
    "http://www.w3.org/1999/xhtml": 0,
    "http://www.w3.org/1999/xlink": 1,
    "http://www.w3.org/2000/xmlns/": 2,
    "http://www.w3.org/1998/Math/MathML": 3,
    "": 4,
    "http://www.w3.org/2000/svg": 5,
  ]
  public static func get() -> [String: Int]? { map }
}
