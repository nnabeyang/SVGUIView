import CoreGraphics
import Foundation
import _CSSParser

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
    self = Self.scan(text).data
  }

  /// The path data of a text in the grammar of SVG, or `nil` if the text has an error, as CSS specifies for
  /// `path()`.
  init?(validating text: String) {
    let (data, isValid) = Self.scan(text)
    guard isValid else { return nil }
    self = data
  }

  private static func scan(_ text: String) -> (data: PathData, isValid: Bool) {
    var text = text
    return text.withUTF8 {
      guard let bytes = BufferView(unsafeBufferPointer: $0) else { return (PathData.none, true) }
      var scanner = SVGAttributeScanner(bytes: bytes)
      let (commands, isValid) = scanner.scanPathCommands()
      return (PathData(commands: commands), isValid)
    }
  }

  /// The value of `d` in CSS: `none`, or `path()` with path data that has no error. `path()` of `d` takes no fill
  /// rule.
  static func parse(_ input: inout _CSSParser.Parser) -> PathData? {
    let value: PathData?
    switch input.next() {
    case .success(.ident(let name)) where name.lowercased() == "none":
      value = PathData.none
    case .success(.function(let name)) where name.lowercased() == "path":
      let result: Result<PathData, CSSParseError> = input.parseNestedBlock { input in
        guard case .success(let text) = input.expectString(), input.isExhausted(),
          let data = PathData(validating: text)
        else { return .failure(input.newCustomError(error: .invalid)) }
        return .success(data)
      }
      value = try? result.get()
    default:
      value = nil
    }
    return input.isExhausted() ? value : nil
  }
}

extension PathData {
  /// The path of SVG 2 for an ellipse, which starts at the point on the right and goes clockwise with four arcs.
  static func ellipse(center c: CGPoint, radii r: CGSize) -> PathData {
    func arc(to x: CGFloat, _ y: CGFloat) -> PathCommand {
      PathCommand(type: .A, values: [r.width, r.height, 0, 0, 1, x, y])
    }
    return PathData(commands: [
      PathCommand(type: .M, values: [c.x + r.width, c.y]), arc(to: c.x, c.y + r.height),
      arc(to: c.x - r.width, c.y), arc(to: c.x, c.y - r.height), arc(to: c.x + r.width, c.y),
      PathCommand(type: .Z, values: []),
    ])
  }

  /// The path data with every command in its absolute form, which draws the same path. Commands before the first
  /// moveto draw nothing, and stay as they are.
  func absolute() -> PathData {
    var current = CGPoint.zero
    var start = CGPoint.zero
    var hasStarted = false
    return PathData(
      commands: commands.map { command in
        guard hasStarted || command.type == .M || command.type == .m else { return command }
        hasStarted = true
        let origin = command.type.isAbsolute ? CGPoint.zero : current
        var values = command.values
        // The indices of the pairs of coordinates of the command, and of the single coordinate of H and V.
        let pairs: [Int]
        switch command.type {
        case .M, .m, .L, .l, .T, .t: pairs = [0]
        case .C, .c: pairs = [0, 2, 4]
        case .S, .s, .Q, .q: pairs = [0, 2]
        case .A, .a: pairs = [5]
        case .H, .h:
          values[0] += origin.x
          current.x = values[0]
          pairs = []
        case .V, .v:
          values[0] += origin.y
          current.y = values[0]
          pairs = []
        case .Z, .z:
          current = start
          pairs = []
        }
        for index in pairs {
          values[index] += origin.x
          values[index + 1] += origin.y
        }
        if let last = pairs.last {
          current = CGPoint(x: values[last], y: values[last + 1])
        }
        if command.type == .M || command.type == .m { start = current }
        return PathCommand(type: command.type.absolute, values: values)
      })
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

  /// The command in its absolute form, which is in uppercase.
  var absolute: PathSegmentType {
    isAbsolute ? self : PathSegmentType(rawValue: rawValue - 32)!
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
  ///
  /// - Returns: The commands, and whether the data has no error: it starts with a moveto, every group is complete,
  ///   and nothing follows the last command.
  mutating func scanPathCommands() -> (commands: [PathCommand], isValid: Bool) {
    var commands = [PathCommand]()
    var isValid = true
    while true {
      guard let type = readSegmentType() else {
        if reader.consumeWhitespace() != nil { isValid = false }
        break
      }
      guard let segment = scanPathSegment(of: type, isValid: &isValid) else {
        isValid = false
        break
      }
      commands += segment
    }
    if let first = commands.first, first.type != .M, first.type != .m { isValid = false }
    return (commands, isValid)
  }

  mutating func readSegmentType() -> PathSegmentType? {
    guard let ch = reader.consumeWhitespace(),
      let type = PathSegmentType(rawValue: ch)
    else { return nil }
    reader.advance()
    return type
  }

  /// The commands of one command letter and its groups of numbers, or `nil` if it has no complete group.
  private mutating func scanPathSegment(of type: PathSegmentType, isValid: inout Bool) -> [PathCommand]? {
    if type == .Z || type == .z {
      return [PathCommand(type: type, values: [])]
    }
    var commands = [PathCommand]()
    while !reader.isEOF, let values = scanPathValues(of: type, isValid: &isValid) {
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

  /// One group of the numbers of a command, or `nil` if the group isn't complete. A group that has some of its
  /// numbers is an error.
  private mutating func scanPathValues(of type: PathSegmentType, isValid: inout Bool) -> [Double]? {
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
      guard let value = isFlag ? scanBool().map({ $0 ? 1 : 0 }) : scanNumber() else {
        if !values.isEmpty || isFlag { isValid = false }
        return nil
      }
      values.append(value)
    }
    return values
  }
}
