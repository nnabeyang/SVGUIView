import Foundation

enum JSONValue: Codable {
  case null
  case bool(Bool)
  case number(Number)
  case string(String)
  case array([JSONValue])
  case object([String: JSONValue])

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if container.decodeNil() {
      self = .null
      return
    }

    if let bool = try? container.decode(Bool.self) {
      self = .bool(bool)
      return
    }
    if let int = try? container.decode(Int.self) {
      self = .number(.init(n: .init(int)))
      return
    }
    if let uint = try? container.decode(UInt.self) {
      self = .number(.init(n: .posInt(UInt64(uint))))
      return
    }
    if let string = try? container.decode(String.self) {
      self = .string(string)
      return
    }
    if let float = try? container.decode(Double.self) {
      self = .number(.init(n: .float(float)))
      return
    }
    if let dictionary = try? container.decode([String: JSONValue].self) {
      self = .object(dictionary)
      return
    }
    if let array = try? container.decode([JSONValue].self) {
      self = .array(array)
      return
    }
    throw DecodingError.dataCorruptedError(in: container, debugDescription: "AnyCodable value cannot be decoded")
  }

  func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .null:
      try container.encodeNil()
    case .bool(let b):
      try container.encode(b)
    case .number(let n):
      try container.encode(n.n)
    case .string(let s):
      try container.encode(s)
    case .array(let a):
      try container.encode(a)
    case .object(let o):
      try container.encode(o)
    }
  }
}

extension JSONValue: CustomDebugStringConvertible {
  var debugDescription: String {
    switch self {
    case .null:
      return "null"
    case .bool(let b):
      return b.description
    case .number(let n):
      return n.debugDescription
    case .string(let s):
      return s.debugDescription
    case .array(let a):
      return "[\(a.map(\.debugDescription).joined(separator: ", "))]"
    case .object(let o):
      return "[\(o.map({ "\($0.key): \($0.value.debugDescription)"}).joined(separator: ", "))]"
    }
  }
}

extension JSONValue: ExpressibleByIntegerLiteral {
  init(integerLiteral value: Int) {
    self = .number(.init(n: .init(value)))
  }
}

extension JSONValue: ExpressibleByStringLiteral {
  init(stringLiteral value: String) {
    self = .string(value)
  }
}

extension JSONValue: ExpressibleByArrayLiteral {
  init(arrayLiteral elements: JSONValue...) {
    self = .array(elements)
  }
}

struct Number: Codable {
  let n: N
}

extension Float64 {
  init(_ number: Number) {
    switch number.n {
    case .posInt(let value):
      self = .init(value)
    case .negInt(let value):
      self = .init(value)
    case .float(let value):
      self = value
    }
  }
}

extension Number: CustomDebugStringConvertible {
  var debugDescription: String {
    switch n {
    case .posInt(let value):
      return "Number(\(value.description))"
    case .negInt(let value):
      return "Number(\(value.description))"
    case .float(let value):
      return "Number(\(String(format: "%.3g", value)))"
    }
  }
}

enum N: Codable {
  case posInt(UInt64)
  case negInt(Int64)
  case float(Float64)

  init(_ value: Int) {
    if value >= 0 {
      self = .posInt(UInt64(value))
    } else {
      self = .negInt(Int64(value))
    }
  }
}
