import CoreGraphics
import Foundation

/// A command of path data with one group of its numbers. A command that repeats its numbers is one command for each
/// group, and the groups after the first of a moveto are linetos.
struct PathCommand: Sendable, Equatable {
  let type: PathSegmentType
  /// The numbers of the command, in the order of the path data. The flags of an arc are 0 or 1.
  var values: [Double]
}

/// The path data of `d`: the commands of the shape, which is `none` when there's none.
struct PathData: Sendable, Equatable {
  static let none = PathData(commands: [])

  var commands: [PathCommand]
}

extension PathData {
  /// The path data of a text in the grammar of SVG, up to the first error, as SVG specifies for the `d` attribute.
  init(_ text: String) {
    var text = text
    self = text.withUTF8 {
      guard let bytes = BufferView(unsafeBufferPointer: $0) else { return PathData.none }
      var scanner = SVGAttributeScanner(bytes: bytes)
      return PathData(commands: scanner.scanPathCommands())
    }
  }
}

enum PathSegmentType: UInt8, Equatable, Sendable {
  case A = 65
  case C = 67
  case H = 72
  case L = 76
  case M = 77
  case Q = 81
  case S = 83
  case T = 84
  case V = 86
  case Z = 90
  case a = 97
  case c = 99
  case h = 104
  case l = 108
  case m = 109
  case q = 113
  case s = 115
  case t = 116
  case v = 118
  case z = 122

  var name: String {
    String(decoding: [rawValue], as: UTF8.self)
  }

  var isAbsolute: Bool {
    rawValue >= UInt8(ascii: "A") && rawValue <= UInt8(ascii: "Z")
  }
}

extension PathSegmentType: Encodable {
  func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(name)
  }
}

extension PathCommand: Encodable {
  private enum CodingKeys: String, CodingKey {
    case type
    case args
  }

  func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: Self.CodingKeys.self)
    try container.encode(type, forKey: .type)
    try container.encode(values, forKey: .args)
  }
}

// for d attribute of path tag
extension SVGAttributeScanner {
  /// The commands of path data, up to the first command without a complete group of numbers. A group that isn't
  /// complete is dropped, and the data goes on at the next command.
  mutating func scanPathCommands() -> [PathCommand] {
    var commands = [PathCommand]()
    while let segment = scanPathSegment() {
      commands += segment
    }
    return commands
  }

  mutating func readSegmentType() -> PathSegmentType? {
    guard let ch = reader.consumeWhitespace(),
      let type = PathSegmentType(rawValue: ch)
    else { return nil }
    reader.advance()
    return type
  }

  /// The commands of one command letter and its groups of numbers, or `nil` if it has no complete group.
  private mutating func scanPathSegment() -> [PathCommand]? {
    guard let type = readSegmentType() else { return nil }
    if type == .Z || type == .z {
      return [PathCommand(type: type, values: [])]
    }
    var commands = [PathCommand]()
    while !reader.isEOF, let values = scanPathValues(of: type) {
      // The groups after the first of a moveto are linetos.
      let groupType: PathSegmentType =
        switch type {
        case .M where !commands.isEmpty: .L
        case .m where !commands.isEmpty: .l
        default: type
        }
      commands.append(PathCommand(type: groupType, values: values))
    }
    return commands.isEmpty ? nil : commands
  }

  /// One group of the numbers of a command, or `nil` if the group isn't complete.
  private mutating func scanPathValues(of type: PathSegmentType) -> [Double]? {
    let count: Int
    switch type {
    case .H, .h, .V, .v: count = 1
    case .M, .m, .L, .l, .T, .t: count = 2
    case .Q, .q, .S, .s: count = 4
    case .C, .c: count = 6
    case .A, .a: count = 7
    case .Z, .z: count = 0
    }
    var values = [Double]()
    for index in 0..<count {
      consumeWhitespaceIfNext(UInt8(ascii: ","))
      // The flags of an arc are a single digit.
      let isFlag = (type == .A || type == .a) && (index == 3 || index == 4)
      guard let value = isFlag ? scanBool().map({ $0 ? 1 : 0 }) : scanNumber() else { return nil }
      values.append(value)
    }
    return values
  }
}
