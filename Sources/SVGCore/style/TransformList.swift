import CoreGraphics
import Foundation
import _CSSParser

/// A transform function, in the form that CSS Transforms 2 interpolates it: `translateX()` is a `translate()`,
/// `scaleY()` a `scale()`, and `skewX()` a `skew()`.
enum TransformFunction: Sendable, Equatable {
  case translate(SVGLength, SVGLength)
  case scale(Double, Double)
  /// An angle in degrees.
  case rotate(Double)
  /// The angles along the x and y axes, in degrees.
  case skew(Double, Double)
  case matrix(CGAffineTransform)
}

/// The value of `transform`: the transform functions in the order that they're written, which is `none` when there's
/// none.
struct TransformList: Sendable, Equatable {
  static let none = TransformList(functions: [])

  var functions: [TransformFunction]
}

extension TransformList {
  /// The transform list of an attribute that isn't a presentation attribute, such as `patternTransform`, or `nil` if
  /// it's invalid.
  init?(attribute text: String) {
    var input = _CSSParser.Parser(input: ParserInput(input: text))
    guard let list = Self.parse(&input, origin: .attribute) else { return nil }
    self = list
  }

  /// A transform list, or `nil` if any of its functions is invalid.
  ///
  /// An attribute also takes numbers without units, which are lengths in user units and angles in degrees, commas
  /// between functions, and `rotate()` with the center of the rotation, as CSS Transforms 1 specifies for SVG. Names
  /// of functions are case-sensitive in an attribute, as in SVG 1.1.
  static func parse(_ input: inout _CSSParser.Parser, origin: DeclarationOrigin) -> TransformList? {
    let state = input.state
    if case .success(.ident(let name)) = input.next(), name.lowercased() == "none" {
      return input.isExhausted() ? TransformList.none : nil
    }
    input.reset(state: state)
    var functions = [TransformFunction]()
    while true {
      if origin == .attribute {
        while case .success = input.tryParse({ $0.expectComma() }) {}
      }
      if input.isExhausted() { break }
      guard let next = transformFunction(&input, origin: origin) else { return nil }
      functions += next
    }
    return functions.isEmpty ? nil : TransformList(functions: functions)
  }

  /// The matrix of the functions, with percentages of the size of the reference box.
  func matrix(box: CGSize, context: any SVGLengthContext) -> CGAffineTransform {
    functions.reduce(.identity) { $1.applied(to: $0, box: box, context: context) }
  }

  /// The list as the text of an attribute that isn't a presentation attribute, such as `gradientTransform`, which
  /// ``init(attribute:)`` reads back as the same list.
  var attributeText: String {
    functions.isEmpty ? "none" : functions.map(\.attributeText).joined(separator: " ")
  }
}

extension TransformFunction {
  /// The function as SVG 1.1 writes it in an attribute. A skew along both axes is a matrix, since `skew()` isn't a
  /// function of SVG 1.1.
  fileprivate var attributeText: String {
    switch self {
    case .translate(let x, let y): "translate(\(x) \(y))"
    case .scale(let x, let y): "scale(\(x) \(y))"
    case .rotate(let angle): "rotate(\(angle))"
    case .skew(let x, let y) where y == 0: "skewX(\(x))"
    case .skew(let x, let y) where x == 0: "skewY(\(y))"
    case .skew(let x, let y):
      TransformFunction.matrix(CGAffineTransform.identity.shear(shx: tan(x * .pi / 180), shy: tan(y * .pi / 180)))
        .attributeText
    case .matrix(let m): "matrix(\(m.a) \(m.b) \(m.c) \(m.d) \(m.tx) \(m.ty))"
    }
  }
}

extension TransformFunction {
  /// The transform with the function applied to points before it.
  func applied(to transform: CGAffineTransform, box: CGSize, context: any SVGLengthContext) -> CGAffineTransform {
    switch self {
    case .translate(let x, let y):
      transform.translatedBy(
        x: x.value(total: box.width, context: context), y: y.value(total: box.height, context: context))
    case .scale(let x, let y):
      transform.scaledBy(x: x, y: y)
    case .rotate(let angle):
      transform.rotated(by: angle * .pi / 180)
    case .skew(let x, let y):
      transform.shear(shx: tan(x * .pi / 180), shy: tan(y * .pi / 180))
    case .matrix(let matrix):
      matrix.concatenating(transform)
    }
  }
}

extension CGAffineTransform {
  func shear(shx: CGFloat = 0, shy: CGFloat = 0) -> CGAffineTransform {
    CGAffineTransform(
      a: a + c * shy, b: b + d * shy,
      c: a * shx + c, d: b * shx + d, tx: tx, ty: ty)
  }
}

// MARK: - Parsing

/// The names of the transform functions, as SVG and CSS write them.
private let functionNames = [
  "translate", "translateX", "translateY", "scale", "scaleX", "scaleY", "rotate", "skew", "skewX", "skewY", "matrix",
]

/// The basic functions of one function of a list, or `nil` if it's invalid. `rotate()` with a center is three.
private func transformFunction(_ input: inout _CSSParser.Parser, origin: DeclarationOrigin) -> [TransformFunction]? {
  let written: String
  switch input.next() {
  case .success(.function(let name)):
    written = name
  case .success(.ident(let name)) where origin == .attribute:
    // An attribute can have spaces between the name and the parenthesis, as in SVG 1.1.
    guard case .success(.parenthesisBlock) = input.next() else { return nil }
    written = name
  default:
    return nil
  }
  guard
    let name = functionNames.first(where: { origin == .css ? $0.lowercased() == written.lowercased() : $0 == written })
  else { return nil }
  let result: Result<[TransformFunction], CSSParseError> = input.parseNestedBlock { input in
    guard let functions = arguments(of: name, &input, origin: origin), input.isExhausted() else {
      return .failure(input.newCustomError(error: .invalid))
    }
    return .success(functions)
  }
  return try? result.get()
}

private func arguments(
  of name: String, _ input: inout _CSSParser.Parser, origin: DeclarationOrigin
) -> [TransformFunction]? {
  switch name {
  case "translate":
    guard let x = length(&input, origin: origin) else { return nil }
    if input.isExhausted() { return [.translate(x, .number(0))] }
    guard separator(&input, origin: origin), let y = length(&input, origin: origin) else { return nil }
    return [.translate(x, y)]
  case "translateX":
    return length(&input, origin: origin).map { [.translate($0, .number(0))] }
  case "translateY":
    return length(&input, origin: origin).map { [.translate(.number(0), $0)] }
  case "scale":
    guard let x = scale(&input) else { return nil }
    if input.isExhausted() { return [.scale(x, x)] }
    guard separator(&input, origin: origin), let y = scale(&input) else { return nil }
    return [.scale(x, y)]
  case "scaleX":
    return scale(&input).map { [.scale($0, 1)] }
  case "scaleY":
    return scale(&input).map { [.scale(1, $0)] }
  case "rotate":
    guard let angle = angle(&input, origin: origin) else { return nil }
    if input.isExhausted() { return [.rotate(angle)] }
    guard origin == .attribute,
      separator(&input, origin: origin), let x = number(&input),
      separator(&input, origin: origin), let y = number(&input)
    else { return nil }
    return [.translate(.number(x), .number(y)), .rotate(angle), .translate(.number(-x), .number(-y))]
  case "skew":
    guard let x = angle(&input, origin: origin) else { return nil }
    if input.isExhausted() { return [.skew(x, 0)] }
    guard separator(&input, origin: origin), let y = angle(&input, origin: origin) else { return nil }
    return [.skew(x, y)]
  case "skewX":
    return angle(&input, origin: origin).map { [.skew($0, 0)] }
  case "skewY":
    return angle(&input, origin: origin).map { [.skew(0, $0)] }
  case "matrix":
    var values = [Double]()
    for index in 0..<6 {
      guard index == 0 || separator(&input, origin: origin), let value = number(&input) else { return nil }
      values.append(value)
    }
    return [.matrix(CGAffineTransform(a: values[0], b: values[1], c: values[2], d: values[3], tx: values[4], ty: values[5]))]
  default:
    return nil
  }
}

/// Reads the separator between two arguments: a comma, which an attribute can leave out.
private func separator(_ input: inout _CSSParser.Parser, origin: DeclarationOrigin) -> Bool {
  if case .success = input.tryParse({ $0.expectComma() }) { return true }
  return origin == .attribute
}

/// A numeric token, with its value read from the text of the token, since the token keeps it only as a `Float32`.
private enum Numeric {
  case number(Double)
  case percentage(Double)
  case dimension(Double, unit: String)
}

private func numeric(_ input: inout _CSSParser.Parser) -> Numeric? {
  input.skipWhitespace()
  let start = input.position
  guard case .success(let token) = input.next() else { return nil }
  let text = input.slice(from: start)
  switch token {
  case .number(let number):
    return .number(Double(text) ?? Double(number.value))
  case .percentage(let percentage):
    return .percentage(Double(text.dropLast()) ?? Double(percentage.unitValue) * 100)
  case .dimention(let dimension):
    return .dimension(Double(text.dropLast(dimension.unit.count)) ?? Double(dimension.value), unit: dimension.unit)
  default:
    return nil
  }
}

private func number(_ input: inout _CSSParser.Parser) -> Double? {
  guard case .number(let value) = numeric(&input) else { return nil }
  return value
}

/// A number or a percentage, which `scale()` takes.
private func scale(_ input: inout _CSSParser.Parser) -> Double? {
  switch numeric(&input) {
  case .number(let value): value
  case .percentage(let value): value / 100
  default: nil
  }
}

/// A length or a percentage. A number is a length in user units in an attribute, and only zero is in CSS.
private func length(_ input: inout _CSSParser.Parser, origin: DeclarationOrigin) -> SVGLength? {
  switch numeric(&input) {
  case .number(let value) where origin == .attribute || value == 0: .number(value)
  case .percentage(let value): .percent(value)
  case .dimension(let value, let unit): SVGLength(value: value, cssUnit: unit)
  default: nil
  }
}

/// An angle in degrees. A number is an angle in degrees in an attribute, and only zero is in CSS.
private func angle(_ input: inout _CSSParser.Parser, origin: DeclarationOrigin) -> Double? {
  switch numeric(&input) {
  case .number(let value) where origin == .attribute || value == 0:
    return value
  case .dimension(let value, let unit):
    switch unit.lowercased() {
    case "deg": return value
    case "rad": return value * 180 / .pi
    case "grad": return value * 0.9
    case "turn": return value * 360
    default: return nil
    }
  default:
    return nil
  }
}

// MARK: - Transform origin

/// The value of `transform-origin`: the point that transforms are applied about, from the top left corner of the
/// reference box. Percentages are of the size of the box.
struct TransformOrigin: Sendable, Equatable {
  /// The origin of SVG elements, which have no box of CSS layout.
  static let zero = TransformOrigin(x: .number(0), y: .number(0))

  var x: SVGLength
  var y: SVGLength
}

extension TransformOrigin {
  /// The transform origin, or `nil` if it's invalid. Keywords are percentages, and a length along the z axis is read
  /// and dropped, since transforms here are 2D. An attribute also takes numbers without units, as lengths in user
  /// units.
  static func parse(_ input: inout _CSSParser.Parser, origin: DeclarationOrigin) -> TransformOrigin? {
    var values = [OriginValue]()
    while values.count < 2, !input.isExhausted() {
      guard let value = originValue(&input, origin: origin) else { return nil }
      values.append(value)
    }
    if values.count == 2, !input.isExhausted() {
      // A length along the z axis can't be a percentage.
      guard let z = length(&input, origin: origin) else { return nil }
      if case .percent = z { return nil }
    }
    guard input.isExhausted() else { return nil }
    switch values.count {
    case 1:
      switch values[0] {
      case .top, .bottom: return TransformOrigin(x: .percent(50), y: values[0].length)
      default: return TransformOrigin(x: values[0].length, y: .percent(50))
      }
    case 2:
      var (x, y) = (values[0], values[1])
      // Two keywords can come in either order.
      if x.isKeyword, y.isKeyword, x.isVertical || y.isHorizontal { swap(&x, &y) }
      guard !x.isVertical, !y.isHorizontal else { return nil }
      return TransformOrigin(x: x.length, y: y.length)
    default:
      return nil
    }
  }
}

/// A value of `transform-origin`, before its axis is known.
private enum OriginValue {
  case left, center, right, top, bottom
  case length(SVGLength)

  var isKeyword: Bool {
    if case .length = self { false } else { true }
  }

  var isHorizontal: Bool {
    switch self {
    case .left, .right: true
    default: false
    }
  }

  var isVertical: Bool {
    switch self {
    case .top, .bottom: true
    default: false
    }
  }

  var length: SVGLength {
    switch self {
    case .left, .top: .percent(0)
    case .center: .percent(50)
    case .right, .bottom: .percent(100)
    case .length(let length): length
    }
  }
}

private func originValue(_ input: inout _CSSParser.Parser, origin: DeclarationOrigin) -> OriginValue? {
  let state = input.state
  if case .success(.ident(let name)) = input.next() {
    switch name.lowercased() {
    case "left": return .left
    case "center": return .center
    case "right": return .right
    case "top": return .top
    case "bottom": return .bottom
    default: return nil
    }
  }
  input.reset(state: state)
  return length(&input, origin: origin).map(OriginValue.length)
}

/// The value of `transform-box`: the box that `transform-origin` and percentages of transform functions are
/// relative to.
enum TransformBox: String, CaseIterable, Sendable {
  case contentBox = "content-box"
  case borderBox = "border-box"
  case fillBox = "fill-box"
  case strokeBox = "stroke-box"
  case viewBox = "view-box"
}
