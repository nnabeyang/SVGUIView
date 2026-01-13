import _SelectorParser

public struct Namespaces {
  public let `default`: Namespace?
  public let prefixes: [Prefix: Namespace]
}

extension Namespaces: Default {
  public static func `default`() -> Namespaces {
    .init(default: nil, prefixes: [:])
  }
}

struct Stylesheet: Equatable {
  let rules: [CSSRule]
}
