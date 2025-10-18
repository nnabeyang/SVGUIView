enum CSSRule: Equatable {
  case qualified(QualifiedCSSRule)

  func matches(element: any SVGDrawableElement) -> Bool {
    switch self {
    case .qualified(let rule):
      return rule.matches(element: element)
    }
  }

  var declarations: [CSSValueType: CSSDeclaration] {
    switch self {
    case .qualified(let rule):
      return rule.declarations
    }
  }
}

enum CSSRuleType: String {
  case qualified
}

extension CSSRule: Encodable {
  func encode(to encoder: any Encoder) throws {
    var container = encoder.unkeyedContainer()
    switch self {
    case .qualified(let rule):
      try container.encode(CSSRuleType.qualified.rawValue)
      try container.encode(rule.selectors)
      let declarations = rule.declarations.values.sorted(by: {
        $0.type.rawValue < $1.type.rawValue
      })
      try container.encode(declarations)
    }
  }
}

extension CSSRule: Decodable {
  init(from decoder: any Decoder) throws {
    var container = try decoder.unkeyedContainer()
    guard let type = try CSSRuleType(rawValue: container.decode(String.self)) else {
      throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: ""))
    }
    switch type {
    case .qualified:
      let selectors = try container.decode([CSSSelector].self)
      let declarations = try container.decode([CSSValueType: CSSDeclaration].self)
      self = .qualified(QualifiedCSSRule(selectors: selectors, declarations: declarations))
    }
  }
}

struct QualifiedCSSRule: Equatable {
  let selectors: [CSSSelector]
  let declarations: [CSSValueType: CSSDeclaration]

  func matches(element: any SVGDrawableElement) -> Bool {
    selectors.contains(where: { $0.matches(element: element) })
  }

  subscript(key: CSSValueType) -> CSSValue? {
    declarations[key]?.value
  }
}

struct CSSStyle: Equatable {
  let rules: [CSSRule]
}
