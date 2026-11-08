import Foundation
import _CSSParser
import os

/// An expression of the math functions of CSS Values 4 that SVGUIView reads: `calc()`, `min()`, `max()` and
/// `clamp()`, with numbers, percentages, lengths and angles, and the names of the components of the origin of a
/// relative color, which are numbers.
indirect enum CalcNode: Sendable, Equatable {
  case number(Double)
  case percentage(Double)
  /// A length in one unit.
  case length(SVGLength)
  /// An angle in degrees.
  case angle(Double)
  /// A component of the origin of a relative color, by its name, which is a number.
  case channel(String)
  case sum([CalcNode])
  case product([CalcNode])
  /// One divided by the value, which is a number.
  case inverse(CalcNode)
  case min([CalcNode])
  case max([CalcNode])
  case clamp(CalcNode, CalcNode, CalcNode)

  /// The names of the math functions that the expression can be written with.
  static let functionNames: Set<String> = ["calc", "min", "max", "clamp"]

  /// Whether a value starts with a math function, which is how the readers of values that aren't tokens find the
  /// values that they read with ``CalcParser``.
  static func startsWithFunction(_ text: some StringProtocol) -> Bool {
    guard let parenthesis = text.firstIndex(of: "(") else { return false }
    let name = text[..<parenthesis].trimmingCharacters(in: .whitespaces).lowercased()
    return functionNames.contains(name)
  }
}

/// The type of an expression, as CSS Values 4 types them, with percentages as the type that they're resolved
/// against where they're used.
enum CalcType: Equatable {
  case number
  case percentage
  case length
  /// A length with a percentage of a length in it, such as `10px + 5%`.
  case lengthPercentage
  case angle
}

/// What a percentage is in the value that an expression is read for.
enum CalcPercentages {
  /// A percentage isn't allowed.
  case none
  /// A percentage of a length, which adds to lengths.
  case length
  /// A percentage on its own, such as a component of a color or an opacity, which doesn't add to numbers.
  case alone
}

extension CalcNode {
  /// The type of the expression, or `nil` if its terms can't be added or multiplied, such as a length and a number.
  func type(percentages: CalcPercentages) -> CalcType? {
    switch self {
    case .number, .channel: return .number
    case .percentage: return percentages == .none ? nil : .percentage
    case .length: return .length
    case .angle: return .angle
    case .sum(let nodes), .min(let nodes), .max(let nodes):
      return Self.sumType(of: nodes, percentages: percentages)
    case .clamp(let low, let value, let high):
      return Self.sumType(of: [low, value, high], percentages: percentages)
    case .inverse(let node):
      return node.type(percentages: percentages) == .number ? .number : nil
    case .product(let nodes):
      // At most one of the factors isn't a number.
      var result = CalcType.number
      for node in nodes {
        guard let type = node.type(percentages: percentages) else { return nil }
        if type == .number { continue }
        guard result == .number else { return nil }
        result = type
      }
      return result
    }
  }

  /// The type of terms that are added, or compared, which is their type if they have the same one, or a length with a
  /// percentage of a length for lengths and percentages where percentages are of lengths.
  private static func sumType(of nodes: [CalcNode], percentages: CalcPercentages) -> CalcType? {
    var result: CalcType?
    for node in nodes {
      guard let type = node.type(percentages: percentages) else { return nil }
      guard let current = result, current != type else {
        result = type
        continue
      }
      let lengths: Set<CalcType> = [.length, .percentage, .lengthPercentage]
      guard percentages == .length, lengths.contains(current), lengths.contains(type) else { return nil }
      result = .lengthPercentage
    }
    return result
  }

  /// The value of the expression, with lengths, percentages and components given by functions. An angle is in
  /// degrees.
  func value(
    length: (SVGLength) -> Double, percentage: (Double) -> Double, channel: (String) -> Double = { _ in 0 }
  ) -> Double {
    func evaluate(_ node: CalcNode) -> Double {
      switch node {
      case .number(let value): value
      case .percentage(let value): percentage(value)
      case .length(let value): length(value)
      case .angle(let value): value
      case .channel(let name): channel(name)
      case .sum(let nodes): nodes.reduce(0) { $0 + evaluate($1) }
      case .product(let nodes): nodes.reduce(1) { $0 * evaluate($1) }
      case .inverse(let node): 1 / evaluate(node)
      case .min(let nodes): nodes.map(evaluate).min() ?? 0
      case .max(let nodes): nodes.map(evaluate).max() ?? 0
      case .clamp(let low, let value, let high):
        // The lower bound wins over the upper one, as CSS Values 4 specifies.
        Swift.max(evaluate(low), Swift.min(evaluate(value), evaluate(high)))
      }
    }
    return evaluate(self)
  }

  /// The value of an expression without lengths and components, with a percentage as the given number for 100%.
  func constant(percentage hundred: Double = 100) -> Double {
    value(length: { _ in 0 }, percentage: { $0 * hundred / 100 })
  }

  /// Whether a component of a relative color is part of the expression.
  var hasChannels: Bool {
    !channelNames.isEmpty
  }

  /// The names of the components of a relative color that the expression uses.
  var channelNames: Set<String> {
    switch self {
    case .channel(let name): [name]
    case .number, .percentage, .length, .angle: []
    case .sum(let nodes), .product(let nodes), .min(let nodes), .max(let nodes):
      nodes.reduce(into: []) { $0.formUnion($1.channelNames) }
    case .inverse(let node): node.channelNames
    case .clamp(let a, let b, let c): a.channelNames.union(b.channelNames).union(c.channelNames)
    }
  }

  /// Whether a percentage is part of the expression.
  var hasPercent: Bool {
    switch self {
    case .percentage: true
    case .length(let length): length.hasPercent
    case .number, .angle, .channel: false
    case .sum(let nodes), .product(let nodes), .min(let nodes), .max(let nodes): nodes.contains(where: \.hasPercent)
    case .inverse(let node): node.hasPercent
    case .clamp(let a, let b, let c): a.hasPercent || b.hasPercent || c.hasPercent
    }
  }

  /// The expression with its lengths changed.
  func mappingLengths(_ transform: (SVGLength) -> SVGLength) -> CalcNode {
    switch self {
    case .length(let length): .length(transform(length))
    case .number, .percentage, .angle, .channel: self
    case .sum(let nodes): .sum(nodes.map { $0.mappingLengths(transform) })
    case .product(let nodes): .product(nodes.map { $0.mappingLengths(transform) })
    case .min(let nodes): .min(nodes.map { $0.mappingLengths(transform) })
    case .max(let nodes): .max(nodes.map { $0.mappingLengths(transform) })
    case .inverse(let node): .inverse(node.mappingLengths(transform))
    case .clamp(let a, let b, let c):
      .clamp(a.mappingLengths(transform), b.mappingLengths(transform), c.mappingLengths(transform))
    }
  }

  /// The terms of the expression as a sum of lengths in units, absolute lengths in pixels, or `nil` if it isn't a
  /// sum, such as `min()` of lengths in different units, or a product of a length by a component.
  var linearTerms: [SVGLength]? {
    guard let terms = linear else { return nil }
    return terms.sorted { $0.key.rawValue < $1.key.rawValue }.compactMap { unit, magnitude in
      unit == .percentage ? .percent(magnitude) : SVGLength(value: magnitude, type: unit)
    }
  }

  /// The magnitudes of the terms of a linear expression by their units, absolute lengths in pixels and numbers as
  /// `number`.
  private var linear: [SVGLengthType: Double]? {
    switch self {
    case .number(let value): return [.number: value]
    case .percentage(let value): return [.percentage: value]
    case .angle: return nil
    case .channel: return nil
    case .length(let length):
      if let pixels = length.absolutePixelValue { return [.pixels: pixels] }
      guard case .some(let (unit, magnitude)) = length.unitAndMagnitude else { return nil }
      return [unit: magnitude]
    case .sum(let nodes):
      var result = [SVGLengthType: Double]()
      for node in nodes {
        guard let terms = node.linear else { return nil }
        result.merge(terms, uniquingKeysWith: +)
      }
      return result
    case .product(let nodes):
      var factor = 1.0
      var terms: [SVGLengthType: Double]?
      for node in nodes {
        if !node.hasChannels, node.type(percentages: .length) == .number {
          factor *= node.constant()
        } else {
          guard terms == nil, let linear = node.linear else { return nil }
          terms = linear
        }
      }
      return (terms ?? [.number: 1]).mapValues { $0 * factor }
    case .inverse(let node):
      guard !node.hasChannels, node.type(percentages: .length) == .number else { return nil }
      return [.number: 1 / node.constant()]
    case .min, .max, .clamp:
      // The functions compare terms only when every one is in the same single unit, which compares as numbers.
      let nodes: [CalcNode]
      switch self {
      case .min(let n), .max(let n): nodes = n
      case .clamp(let a, let b, let c): nodes = [a, b, c]
      default: nodes = []
      }
      var unit: SVGLengthType?
      var values = [Double]()
      for node in nodes {
        guard let terms = node.linear?.filter({ $0.value != 0 }), terms.count <= 1 else { return nil }
        guard let term = terms.first else {
          values.append(0)
          continue
        }
        if let unit, unit != term.key { return nil }
        unit = term.key
        values.append(term.value)
      }
      let value: Double
      switch self {
      case .min: value = values.min() ?? 0
      case .max: value = values.max() ?? 0
      default: value = Swift.max(values[0], Swift.min(values[1], values[2]))
      }
      return [unit ?? .number: value]
    }
  }
}

extension SVGLength {
  /// The length in pixels for an absolute length, which is the same wherever it's used.
  fileprivate var absolutePixelValue: Double? {
    switch self {
    case .pixel(let value): value
    case .centimeters(let value): value * Self.pixelsPerInch / 2.54
    case .millimeters(let value): value * Self.pixelsPerInch / 25.4
    case .inches(let value): value * Self.pixelsPerInch
    case .points(let value): value * Self.pixelsPerInch / 72
    case .picas(let value): value * Self.pixelsPerInch / 6
    case .q(let value): value * Self.pixelsPerInch / (25.4 * 4)
    default: nil
    }
  }

}

/// Reads the math functions of CSS Values 4 from tokens.
struct CalcParser {
  /// What a percentage is in the value.
  let percentages: CalcPercentages
  /// The names of the components of the origin of a relative color, which the expression can use as numbers.
  let channels: Set<String>

  init(percentages: CalcPercentages, channels: Set<String> = []) {
    self.percentages = percentages
    self.channels = channels
  }

  /// Reads a math function after its function token, for a value of one of the given types, or returns `nil` if it's
  /// invalid.
  func parseFunction(named name: String, _ input: inout Parser, types: Set<CalcType>) -> CalcNode? {
    guard let node = function(named: name, &input), let type = node.type(percentages: percentages),
      types.contains(type)
    else { return nil }
    return node
  }

  /// Reads a whole value that's one math function, or returns `nil` if it isn't one, or there's more after it.
  func parse(_ text: String, types: Set<CalcType>) -> CalcNode? {
    var input = Parser(input: ParserInput(input: text))
    guard case .success(.function(let name)) = input.next(),
      let node = parseFunction(named: name, &input, types: types), input.isExhausted()
    else { return nil }
    return node
  }

  /// Reads a math function after its function token, of any type, or returns `nil` if it's invalid or isn't one.
  func function(named name: String, _ input: inout Parser) -> CalcNode? {
    let name = name.lowercased()
    guard CalcNode.functionNames.contains(name) else { return nil }
    let result: Result<CalcNode, CSSParseError> = input.parseNestedBlock { input in
      let node: CalcNode?
      switch name {
      case "calc":
        node = sum(&input)
      case "min", "max":
        var nodes = [CalcNode]()
        repeat {
          guard let node = sum(&input) else { return .failure(input.newCustomError(error: .invalid)) }
          nodes.append(node)
        } while input.tryParse({ $0.expectComma() }).isSuccess
        node = name == "min" ? .min(nodes) : .max(nodes)
      default:
        guard let low = sum(&input), input.tryParse({ $0.expectComma() }).isSuccess,
          let value = sum(&input), input.tryParse({ $0.expectComma() }).isSuccess,
          let high = sum(&input)
        else { return .failure(input.newCustomError(error: .invalid)) }
        node = .clamp(low, value, high)
      }
      guard let node, input.isExhausted() else { return .failure(input.newCustomError(error: .invalid)) }
      return .success(node)
    }
    return try? result.get()
  }

  /// A sum of products, whose `+` and `-` have whitespace on both sides.
  private func sum(_ input: inout Parser) -> CalcNode? {
    guard let first = product(&input) else { return nil }
    var terms = [first]
    while true {
      let state = input.state
      guard case .success(.whitespace) = input.nextIncludingWhitespace() else {
        input.reset(state: state)
        break
      }
      let sign: Double
      switch input.nextIncludingWhitespace() {
      case .success(.delim("+")): sign = 1
      case .success(.delim("-")): sign = -1
      default:
        input.reset(state: state)
        return terms.count == 1 ? first : .sum(terms)
      }
      guard case .success(.whitespace) = input.nextIncludingWhitespace(), let term = product(&input) else {
        return nil
      }
      terms.append(sign < 0 ? .product([.number(-1), term]) : term)
    }
    return terms.count == 1 ? first : .sum(terms)
  }

  /// A product of values, which are multiplied with `*` and divided with `/`.
  private func product(_ input: inout Parser) -> CalcNode? {
    guard let first = value(&input) else { return nil }
    var factors = [first]
    while true {
      let state = input.state
      switch input.next() {
      case .success(.delim("*")):
        guard let factor = value(&input) else { return nil }
        factors.append(factor)
      case .success(.delim("/")):
        guard let divisor = value(&input) else { return nil }
        factors.append(.inverse(divisor))
      default:
        input.reset(state: state)
        return factors.count == 1 ? first : .product(factors)
      }
    }
  }

  /// A number, a dimension, a percentage, a component, or an expression in parentheses or in a math function.
  private func value(_ input: inout Parser) -> CalcNode? {
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
      let value = Double(text.dropLast(dimension.unit.count)) ?? Double(dimension.value)
      if let degrees = Self.degrees(value, unit: dimension.unit) { return .angle(degrees) }
      return SVGLength(value: value, cssUnit: dimension.unit).map { .length($0) }
    case .ident(let name):
      let name = name.lowercased()
      return channels.contains(name) ? .channel(name) : nil
    case .parenthesisBlock:
      let result: Result<CalcNode, CSSParseError> = input.parseNestedBlock { input in
        guard let node = sum(&input), input.isExhausted() else { return .failure(input.newCustomError(error: .invalid)) }
        return .success(node)
      }
      return try? result.get()
    case .function(let name):
      return function(named: name, &input)
    default:
      return nil
    }
  }

  /// An angle in degrees, or `nil` for a unit that isn't one of an angle.
  static func degrees(_ value: Double, unit: String) -> Double? {
    switch unit.lowercased() {
    case "deg": value
    case "rad": value * 180 / .pi
    case "grad": value * 0.9
    case "turn": value * 360
    default: nil
    }
  }
}

/// An expression in a table of the expressions that documents have, which a value keeps by its index, so that the value
/// stays trivial to copy, as lengths and colors are copied a lot when styles are computed and render trees are built.
/// The table keeps each expression once, so it grows only with the expressions that documents write.
struct CalcExpression: Sendable, Equatable {
  private let index: Int

  private static let expressions = OSAllocatedUnfairLock(initialState: [CalcNode]())

  init(_ node: CalcNode) {
    index = Self.expressions.withLock { expressions in
      if let index = expressions.firstIndex(of: node) { return index }
      expressions.append(node)
      return expressions.count - 1
    }
  }

  var node: CalcNode {
    Self.expressions.withLock { $0[index] }
  }
}

/// A length that's an expression that can't be written as a sum of lengths in units, such as `min()` of lengths in
/// different units, which is resolved where it's used.
struct SVGLengthExpression: Sendable, Equatable, CustomStringConvertible {
  private let expression: CalcExpression

  init(_ node: CalcNode) {
    expression = CalcExpression(node)
  }

  var node: CalcNode { expression.node }

  /// The length, where a percentage is of the given length.
  func value(total: CGFloat, context: any SVGLengthContext) -> CGFloat {
    node.value(length: { $0.value(total: total, context: context) }, percentage: { total * $0 / 100 })
  }

  var description: String { "calc(…)" }
}

extension SVGLength {
  /// A length that's a math function, such as `calc(100% - 10px)`, or `nil` if the text isn't one or is invalid.
  ///
  /// - Parameter isNonNegative: Whether the value can't be negative, which the expression is clamped to where it's
  ///   used, as CSS Values 4 clamps a math function to the range of the property.
  init?(mathFunction text: String, percentages: Bool = true, isNonNegative: Bool = false) {
    guard CalcNode.startsWithFunction(text) else { return nil }
    let parser = CalcParser(percentages: percentages ? .length : .none)
    guard let node = parser.parse(text, types: [.length, .lengthPercentage, .percentage]) else { return nil }
    self.init(calc: node, isNonNegative: isNonNegative)
  }

  /// A length that's the value of an expression of lengths and percentages.
  init(calc node: CalcNode, isNonNegative: Bool = false) {
    if let terms = node.linearTerms {
      let terms = terms.filter { $0.unitAndMagnitude?.1 != 0 }
      if terms.count <= 1 {
        let length = terms.first ?? .pixel(0)
        self = isNonNegative ? length.nonNegative : length
        return
      }
      if !isNonNegative, let sum = SVGLength.sum(of: terms) {
        self = sum
        return
      }
    }
    self = .calc(SVGLengthExpression(isNonNegative ? .max([node, .length(.pixel(0))]) : node))
  }

  /// The length as read from a property's value: a length, or a math function.
  init?(property text: String, isNonNegative: Bool = false) {
    if let length = SVGLength(text) {
      self = length
    } else if let length = SVGLength(mathFunction: text, isNonNegative: isNonNegative) {
      self = length
    } else {
      return nil
    }
  }
}

/// Reads a number that can be a math function, such as `calc(1 / 2)`, or `nil` if it's invalid.
///
/// - Parameter percentages: The number that 100% is, for a value that takes a percentage too, such as an opacity.
func mathFunctionNumber(_ text: String, percentage hundred: Double? = nil) -> Double? {
  guard CalcNode.startsWithFunction(text) else { return nil }
  let parser = CalcParser(percentages: hundred == nil ? .none : .alone)
  guard let node = parser.parse(text, types: [.number, .percentage]) else { return nil }
  let value = node.constant(percentage: hundred ?? 100)
  return value.isFinite ? value : nil
}

extension SVGLength {
  /// Whether a viewport unit is part of the length, which is known only when drawing.
  var hasViewportUnits: Bool {
    switch self {
    case .vw, .vh, .vi, .vb, .vmin, .vmax: true
    case .sum: terms.contains(where: \.hasViewportUnits)
    case .calc(let expression): expression.node.hasViewportUnits
    default: false
    }
  }
}

extension CalcNode {
  /// Whether a viewport unit is part of the expression.
  fileprivate var hasViewportUnits: Bool {
    var result = false
    _ = mappingLengths {
      if $0.hasViewportUnits { result = true }
      return $0
    }
    return result
  }
}
