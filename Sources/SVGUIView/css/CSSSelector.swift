enum CSSSelector: Equatable {
  case type(tag: SVGElementName)
  case `class`(name: String)
  case id(String)

  func matches(element: any SVGDrawableElement) -> Bool {
    switch self {
    case .type(let tag):
      return tag == element.type
    case .class(let name):
      guard let className = element.className else { return false }
      return name == className
    case .id(let name):
      guard let idName = element.id else { return false }
      return name == idName
    }
  }
}

enum CSSSelectorType: String {
  case tag
  case `class`
  case id
}

extension CSSSelector: Encodable {
  func encode(to encoder: any Encoder) throws {
    var container = encoder.unkeyedContainer()
    switch self {
    case .type(tag: let name):
      try container.encode(CSSSelectorType.tag.rawValue)
      try container.encode(name.rawValue)
    case .class(let name):
      try container.encode(CSSSelectorType.class.rawValue)
      try container.encode(name)
    case .id(let name):
      try container.encode(CSSSelectorType.id.rawValue)
      try container.encode(name)
    }
  }
}

extension CSSSelector: Decodable {
  init(from decoder: any Decoder) throws {
    var container = try decoder.unkeyedContainer()
    guard let type = try CSSSelectorType(rawValue: container.decode(String.self)) else {
      throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: ""))
    }
    switch type {
    case .tag:
      guard let element = try SVGElementName(rawValue: container.decode(String.self)) else {
        throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: ""))
      }
      self = .type(tag: element)
    case .class:
      let name = try container.decode(String.self)
      self = .class(name: name)
    case .id:
      let name = try container.decode(String.self)
      self = .id(name)
    }
  }
}
