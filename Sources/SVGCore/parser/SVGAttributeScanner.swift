import Foundation
import _CShims

struct SVGAttributeScanner {
  var reader: BufferReader

  init(bytes: BufferView<UInt8>) {
    reader = BufferReader(bytes: bytes)
  }

  mutating func consume(ascii: UInt8) -> Bool {
    guard let ch = reader.consumeWhitespace(),
      ch == ascii
    else { return false }
    reader.advance()
    return true
  }

  /// The name at the reader, or `nil` if the next character can't be in a name.
  mutating func scanIdentity() -> String? {
    guard reader.peek().isName else { return nil }
    return consumeName()
  }

  mutating func consumeName() -> String {
    let ch = reader.peek()
    precondition(ch.isName)
    let start = reader.readIndex
    var size = 0
    while true {
      let c = reader.peek(offset: size)
      guard c > 0 else {
        reader.moveReaderIndex(forwardBy: size)
        let end = reader.readIndex
        return String(decoding: reader.bytes[start..<end], as: UTF8.self)
      }
      if c.isName {
        size += 1
        continue
      }
      reader.moveReaderIndex(forwardBy: size)
      let end = reader.readIndex
      return String(decoding: reader.bytes[start..<end], as: UTF8.self)
    }
  }

  /// The string in quotes at the reader. A string without the closing quote ends at the end of the value, as in
  /// CSS.
  mutating func consumeString() -> String {
    let endingCodePoint = reader.peek()
    precondition(endingCodePoint == UInt8(ascii: "'") || endingCodePoint == UInt8(ascii: "\""))
    _ = reader.read()
    let start = reader.readIndex
    var size = 0
    while case let c = reader.peek(offset: size), c > 0, c != endingCodePoint {
      size += 1
    }
    reader.moveReaderIndex(forwardBy: size)
    let end = reader.readIndex
    if !reader.isEOF {
      reader.advance()
    }
    return String(decoding: reader.bytes[start..<end], as: UTF8.self)
  }

  mutating func scanNumber() -> Double? {
    let ch = reader.peek()
    guard ch > 0 else { return nil }
    switch ch {
    case asciiNumbers, UInt8(ascii: "+"), UInt8(ascii: "-"), UInt8(ascii: "."):
      break
    default:
      return nil
    }
    let start = reader.readIndex
    reader.skipNumber()
    let end = reader.readIndex
    return Double(prevalidatedBuffer: reader.bytes[start..<end])
  }

  mutating func scanBool() -> Bool? {
    guard let ascii = reader.read() else { return nil }
    switch ascii {
    case UInt8(ascii: "0"): return false
    case UInt8(ascii: "1"): return true
    default:
      return nil
    }
  }

  @discardableResult
  mutating func consumeWhitespaceIfNext(_ ch: UInt8) -> UInt8? {
    let cc = reader.consumeWhitespace()
    if let cc = cc, cc == ch {
      reader.advance()
      return reader.consumeWhitespace()
    }
    return cc
  }
}

// for points attribute of polyline and polygon tags
extension SVGAttributeScanner {
  mutating func scanPoints() -> [CGPoint] {
    var points = [CGPoint]()
    while !reader.isEOF {
      consumeWhitespaceIfNext(UInt8(ascii: ","))
      guard let x = scanNumber() else { break }
      consumeWhitespaceIfNext(UInt8(ascii: ","))
      guard let y = scanNumber() else { break }
      points.append(CGPoint(x: x, y: y))
    }
    return points
  }
}

// for font attributes
extension SVGAttributeScanner {
  private static let familyNames = [
    "cursive",
    "fantasy",
    "monospace",
    "sans-serif",
    "serif",
    "standard",
  ]

  /// The families of a `font-family` value, or none if a character is neither in a name nor in quotes.
  mutating func scanFontFamilies() -> [String] {
    var families = [String]()
    guard reader.consumeWhitespace() != nil else { return families }
    while !reader.isEOF {
      let family: String
      let ch = reader.peek()
      if ch == UInt8(ascii: "\"") || ch == UInt8(ascii: "'") {
        family = consumeString()
      } else if let name = scanIdentity() {
        family = name
      } else {
        return []
      }
      let prefix = Self.familyNames.contains(family) ? "-webkit-" : ""
      families.append("\(prefix)\(family)")
      consumeWhitespaceIfNext(UInt8(ascii: ","))
    }
    return families
  }
}

// for stroke attribute
extension SVGAttributeScanner {
  mutating func scanHex() -> String? {
    guard consume(ascii: UInt8(ascii: "#")) else { return nil }
    let start = reader.readIndex
    reader.skipHex()
    let end = reader.readIndex
    guard start != end else { return nil }
    return String(decoding: reader.bytes[start..<end], as: UTF8.self)
  }
}

// for fill/color attribute
extension SVGAttributeScanner {
  mutating func scanColorDimension() -> ColorDimension? {
    guard let value = scanNumber() else { return nil }
    if let ch = reader.consumeWhitespace(), ch == UInt8(ascii: "%") {
      reader.advance()
      return .percent(value)
    } else {
      return .absolute(value)
    }
  }

  /// A value of `fill` or `stroke`. A name that isn't a color paints black if anything follows it.
  mutating func scanPaint() -> Paint? {
    guard let ascii = reader.consumeWhitespace() else { return nil }
    if ascii == UInt8(ascii: "#") {
      // Nothing but hexadecimal digits makes the color.
      guard let hex = scanHex(), let color = SVGHexColor(hex: hex), reader.consumeWhitespace() == nil else {
        return nil
      }
      return .color(.hex(color))
    }

    guard let name = scanIdentity() else {
      return nil
    }
    guard let type = SVGFillType(rawValue: name.lowercased()) else {
      _ = reader.consumeWhitespace()
      guard reader.isEOF else { return .color(.named(SVGColorName(name: "black"))) }
      return name.lowercased() == "none" ? Paint.none : .color(.named(SVGColorName(name: name)))
    }
    switch type {
    case .current:
      return .currentColor
    case .inherit:
      return nil
    case .rgb, .rgba, .hsl, .hsla, .hwb, .lab, .lch, .oklab, .oklch, .color, .colorMix:
      return scanColorExpression(type: type).map { expression in
        if case .color(let color) = expression { .color(color) } else { .expression(expression) }
      }
    case .url:
      guard consume(ascii: UInt8(ascii: "(")) else { return nil }
      consumeWhitespaceIfNext(UInt8(ascii: "#"))
      guard let id = scanIdentity() else { return nil }
      guard consume(ascii: UInt8(ascii: ")")) else { return nil }
      // The fallback is the rest of the value: a paint other than a paint server, with nothing after it.
      guard reader.consumeWhitespace() != nil else { return .url(id, fallback: nil) }
      guard let fallback = scanPaint(), reader.isEOF else { return nil }
      if case .url = fallback { return nil }
      return .url(id, fallback: fallback)
    }
  }

  /// A color, or `nil` for a value that isn't one or that `currentcolor` is part of.
  mutating func scanColor() -> SVGColor? {
    guard case .color(let color)? = scanColorExpression() else { return nil }
    return color
  }

  /// A color, or an expression that `currentcolor` is part of, such as `currentcolor` itself or a `color-mix()` of
  /// it, or `nil` for a value that isn't one.
  mutating func scanColorExpression() -> ColorExpression? {
    guard let ascii = reader.consumeWhitespace() else { return nil }
    if ascii == UInt8(ascii: "#") {
      guard let hex = scanHex() else { return nil }
      return SVGHexColor(hex: hex).map { .color(.hex($0)) }
    }

    guard let name = scanIdentity() else {
      return nil
    }
    guard let type = SVGFillType(rawValue: name.lowercased()) else {
      return .color(.named(SVGColorName(name: name)))
    }
    if type == .current { return .currentColor }
    return scanColorExpression(type: type)
  }

  /// A color function after its name, as a color or an expression that `currentcolor` is part of.
  private mutating func scanColorExpression(type: SVGFillType) -> ColorExpression? {
    if type == .colorMix { return scanColorMix() }
    guard var function = ColorFunction(type), consume(ascii: UInt8(ascii: "(")) else { return nil }
    let origin: ColorExpression?
    if consumeFromKeyword() {
      // A relative color, whose components can be the names of the components of its origin.
      guard let color = scanColorExpression() else { return nil }
      if case .color(let value) = color, value.toCGColor(opacity: 1) == nil { return nil }
      origin = color
    } else {
      origin = nil
    }
    if case .color = function {
      guard reader.consumeWhitespace() != nil, let name = scanIdentity(),
        let space = CSSColorSpace(rawValue: name.lowercased())
      else { return nil }
      function = .color(space)
    }
    guard
      let (components, alpha, isLegacy) = scanColorComponents(
        hueAt: function.hueIndex, allowsChannels: origin != nil)
    else { return nil }
    guard let origin else {
      return Self.color(of: function, components: components, alpha: alpha, isLegacy: isLegacy).map { .color($0) }
    }
    // A relative color has only the modern syntax, and the names of the components of its function.
    let names = function.channelNames.union(["alpha"])
    guard !isLegacy,
      (components + [alpha].compactMap { $0 }).allSatisfy({
        if case .channel(let name) = $0 { names.contains(name) } else { true }
      })
    else { return nil }
    return ColorExpression.relative(
      RelativeColor(function: function, origin: origin, components: components, alpha: alpha)
    ).simplified
  }

  /// Whether the next name is `from` and a space follows it, which starts a relative color, and reads it if it is.
  private mutating func consumeFromKeyword() -> Bool {
    guard reader.consumeWhitespace() != nil else { return false }
    let letters = "from".utf8.map { $0 }
    for (offset, letter) in letters.enumerated() {
      let ascii = reader.peek(offset: offset)
      guard ascii == letter || ascii == letter - 32 else { return false }
    }
    let next = reader.peek(offset: letters.count)
    guard
      next == UInt8(ascii: " ") || next == UInt8(ascii: "\t") || next == UInt8(ascii: "\n")
        || next == UInt8(ascii: "\r") || next == 0x0C
    else { return false }
    reader.moveReaderIndex(forwardBy: letters.count)
    return true
  }

  /// `color-mix()` after its name: `in` a color space, and a method of interpolating hues for a space with them,
  /// and two colors, each with a percentage that can be omitted, before or after it.
  private mutating func scanColorMix() -> ColorExpression? {
    guard consume(ascii: UInt8(ascii: "(")), reader.consumeWhitespace() != nil, scanIdentity()?.lowercased() == "in",
      reader.consumeWhitespace() != nil, let spaceName = scanIdentity(),
      let space = ColorMixSpace(rawValue: spaceName.lowercased())
    else { return nil }
    var method = HueInterpolationMethod.shorter
    if reader.consumeWhitespace() != UInt8(ascii: ",") {
      guard space.isPolar, let name = scanIdentity(), let hueMethod = HueInterpolationMethod(rawValue: name.lowercased()),
        reader.consumeWhitespace() != nil, scanIdentity()?.lowercased() == "hue"
      else { return nil }
      method = hueMethod
    }
    guard consume(ascii: UInt8(ascii: ",")), let (color1, percentage1) = scanColorMixOperand(),
      consume(ascii: UInt8(ascii: ",")), let (color2, percentage2) = scanColorMixOperand(),
      consume(ascii: UInt8(ascii: ")")), ColorConversion.mixWeights(percentage1, percentage2) != nil
    else { return nil }
    return ColorExpression.mix(space, method, color1, percentage1, color2, percentage2).simplified
  }

  /// A color of `color-mix()` and its percentage, which comes before or after it and can be omitted.
  private mutating func scanColorMixOperand() -> (ColorExpression, Double?)? {
    var percentage = scanPercentageIfNext()
    // A name that isn't a color makes the mix invalid.
    guard let color = scanColorExpression() else { return nil }
    if case .color(let value) = color, value.toCGColor(opacity: 1) == nil { return nil }
    if percentage == nil {
      percentage = scanPercentageIfNext()
    }
    return (color, percentage)
  }

  /// A percentage if the next characters are a number, which needs a percent sign, or `nil` if they aren't a
  /// number or the number isn't a percentage, which makes `color-mix()` invalid where it's checked.
  private mutating func scanPercentageIfNext() -> Double? {
    guard let next = reader.consumeWhitespace(),
      next == UInt8(ascii: "+") || next == UInt8(ascii: "-") || next == UInt8(ascii: ".")
        || (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(next),
      let value = scanNumber()
    else { return nil }
    guard reader.peek() == UInt8(ascii: "%") else { return .nan }
    reader.advance()
    return value
  }

  /// The color of a function and its components, or `nil` for components that the function doesn't take.
  ///
  /// - Parameters:
  ///   - isLegacy: Whether the components are separated by commas, in the legacy syntax.
  ///   - isRelative: Whether the color is a relative color, whose components aren't clamped to sRGB in the functions
  ///     of sRGB, as CSS Color 5 specifies, so that it keeps an origin outside sRGB.
  static func color(
    of function: ColorFunction, components: [ColorComponent], alpha: ColorComponent?, isLegacy: Bool,
    isRelative: Bool = false
  ) -> SVGColor? {
    switch function {
    case .rgb:
      // The legacy syntax with commas takes numbers or percentages, but not both.
      guard !isLegacy || components.allSatisfy(\.isPercentage) || components.allSatisfy(\.isNumber) else {
        return nil
      }
      if isRelative {
        let (red, green, blue) = (components[0], components[1], components[2])
        return Self.color(
          red: red.value(percentOf: 255) / 255, green: green.value(percentOf: 255) / 255,
          blue: blue.value(percentOf: 255) / 255, alpha: alpha?.alpha ?? 1)
      }
      // Each channel is a number from 0 to 255 or a percentage, which the color keeps.
      let dimensions = components.map { channel -> ColorDimension in
        switch channel {
        case .number(let value): .absolute(min(max(value, 0), 255))
        case .percentage(let value): .percent(min(max(value, 0), 100))
        case .none, .channel: .absolute(0)
        }
      }
      guard let alpha else { return .rgb(SVGRGBColor(r: dimensions[0], g: dimensions[1], b: dimensions[2])) }
      return .rgba(SVGRGBAColor(r: dimensions[0], g: dimensions[1], b: dimensions[2], a: alpha.alpha))
    case .hsl:
      guard !isLegacy || components.dropFirst().allSatisfy(\.isPercentage) else { return nil }
      // A negative saturation is 0%, and the other values outside their ranges make colors outside sRGB, whose
      // channels are clamped, since `hsl()` is a function of sRGB.
      let (red, green, blue) = ColorConversion.sRGB(
        hue: components[0].value, saturation: max(components[1].value, 0), lightness: components[2].value)
      return Self.color(red: red, green: green, blue: blue, alpha: alpha?.alpha ?? 1, clampsToSRGB: !isRelative)
    case .hwb:
      guard !isLegacy else { return nil }
      let (red, green, blue) = ColorConversion.sRGB(
        hue: components[0].value, whiteness: components[1].value, blackness: components[2].value)
      return Self.color(red: red, green: green, blue: blue, alpha: alpha?.alpha ?? 1, clampsToSRGB: !isRelative)
    case .lab, .lch, .oklab, .oklch:
      // These functions have only the modern syntax. The lightness and the chroma have the ranges of CSS Color 4,
      // which their percentages are of, and the other values can make colors outside sRGB.
      guard !isLegacy else { return nil }
      let isPolar = function == .lch || function == .oklch
      let isOK = function == .oklab || function == .oklch
      let lightnessRange: Double = isOK ? 1 : 100
      let lightness = min(max(components[0].value(percentOf: lightnessRange), 0), lightnessRange)
      let a: Double
      let b: Double
      if isPolar {
        let chroma = max(components[1].value(percentOf: isOK ? 0.4 : 150), 0)
        (a, b) = ColorConversion.ab(chroma: chroma, hue: components[2].value)
      } else {
        a = components[1].value(percentOf: isOK ? 0.4 : 125)
        b = components[2].value(percentOf: isOK ? 0.4 : 125)
      }
      let (red, green, blue) =
        isOK
        ? ColorConversion.sRGB(oklabLightness: lightness, a: a, b: b)
        : ColorConversion.sRGB(lightness: lightness, a: a, b: b)
      return Self.color(red: red, green: green, blue: blue, alpha: alpha?.alpha ?? 1)
    case .color(let space):
      // The three components of the color space, where 100% is 1.
      guard !isLegacy else { return nil }
      let (red, green, blue) = ColorConversion.sRGB(
        (components[0].value(percentOf: 1), components[1].value(percentOf: 1), components[2].value(percentOf: 1)),
        in: space)
      return Self.color(red: red, green: green, blue: blue, alpha: alpha?.alpha ?? 1)
    }
  }

  /// A number, a percentage, or `none`, which is 0, in a color function, or the name of a component of the origin of
  /// a relative color, which is replaced by its value.
  enum ColorComponent: Sendable, Equatable {
    case number(Double)
    case percentage(Double)
    case none
    case channel(String)

    var value: Double {
      switch self {
      case .number(let value), .percentage(let value): value
      case .none, .channel: 0
      }
    }

    /// The value, where a percentage is of `range`.
    func value(percentOf range: Double) -> Double {
      switch self {
      case .number(let value): value
      case .percentage(let value): value / 100 * range
      case .none, .channel: 0
      }
    }

    var isPercentage: Bool {
      if case .percentage = self { true } else { false }
    }

    var isNumber: Bool {
      if case .number = self { true } else { false }
    }

    /// The value as an alpha from 0 to 1.
    var alpha: Double {
      switch self {
      case .number(let value): min(max(value, 0), 1)
      case .percentage(let value): min(max(value / 100, 0), 1)
      case .none, .channel: 0
      }
    }
  }

  /// The arguments of a color function after its opening parenthesis, or after the color space of `color()` or the
  /// origin of a relative color, to its closing parenthesis: three components and an alpha, which is optional,
  /// separated by commas in the legacy syntax, or by spaces with a slash before the alpha in the modern one, which
  /// also takes `none`.
  ///
  /// - Parameters:
  ///   - hueIndex: The index of the component that is a hue, such as 0 for `hsl()`, or `nil` for none.
  ///   - allowsChannels: Whether the components can be the names of the components of the origin of a relative
  ///     color.
  private mutating func scanColorComponents(
    hueAt hueIndex: Int?, allowsChannels: Bool = false
  ) -> (components: [ColorComponent], alpha: ColorComponent?, isLegacy: Bool)? {
    var components = [ColorComponent]()
    var isLegacy = false
    for index in 0..<3 {
      if index == 1 {
        isLegacy = reader.consumeWhitespace() == UInt8(ascii: ",")
      }
      if index > 0, isLegacy, !consume(ascii: UInt8(ascii: ",")) { return nil }
      guard
        let component = index == hueIndex
          ? scanHue(allowsChannels: allowsChannels) : scanColorComponent(allowsChannels: allowsChannels)
      else { return nil }
      components.append(component)
    }
    var alpha: ColorComponent?
    if consume(ascii: UInt8(ascii: isLegacy ? "," : "/")) {
      guard let component = scanColorComponent(allowsChannels: allowsChannels) else { return nil }
      alpha = component
    }
    guard consume(ascii: UInt8(ascii: ")")) else { return nil }
    // `none` is a component only in the modern syntax.
    if isLegacy, (components + [alpha].compactMap { $0 }).contains(where: { if case .none = $0 { true } else { false } }) {
      return nil
    }
    return (components, alpha, isLegacy)
  }

  /// A component of a color function: a number, a percentage, or `none`, or the name of a component of the origin
  /// of a relative color where it's allowed.
  private mutating func scanColorComponent(allowsChannels: Bool = false) -> ColorComponent? {
    // A name starts with a letter, unlike a number.
    if reader.consumeWhitespace()?.isNameStart == true {
      return Self.component(named: consumeName(), allowsChannels: allowsChannels)
    }
    guard let value = scanNumber() else { return nil }
    if reader.peek() == UInt8(ascii: "%") {
      reader.advance()
      return .percentage(value)
    }
    return .number(value)
  }

  /// A hue in degrees: a number, an angle, or `none`, or the name of a component of the origin of a relative color
  /// where it's allowed.
  private mutating func scanHue(allowsChannels: Bool = false) -> ColorComponent? {
    // A name starts with a letter, unlike a number.
    if reader.consumeWhitespace()?.isNameStart == true {
      return Self.component(named: consumeName(), allowsChannels: allowsChannels)
    }
    guard let value = scanNumber() else { return nil }
    guard reader.peek().isNameStart else { return .number(value) }
    switch consumeName().lowercased() {
    case "deg": return .number(value)
    case "grad": return .number(value * 0.9)
    case "rad": return .number(value * 180 / .pi)
    case "turn": return .number(value * 360)
    default: return nil
    }
  }

  /// A color of red, green and blue of sRGB, where 0 to 1 is sRGB and the values outside are colors outside it.
  ///
  /// A value that is outside 0 to 1 by less than half a step of 8 bits, such as from the errors of the conversions
  /// of white of Display P3, is in sRGB.
  ///
  /// - Parameter clampsToSRGB: Whether values outside 0 to 1 are clamped to it, for a function of sRGB.
  static func color(
    red: Double, green: Double, blue: Double, alpha: Double, clampsToSRGB: Bool = false
  ) -> SVGColor {
    func channel(_ value: Double) -> ColorDimension {
      let limit = SVGColor.sRGBTolerance
      let isNearSRGB = -limit < value && value < 1 + limit
      return .absolute((clampsToSRGB || isNearSRGB ? min(max(value, 0), 1) : value) * 255)
    }
    return .rgba(SVGRGBAColor(r: channel(red), g: channel(green), b: channel(blue), a: alpha))
  }

  /// `none`, or the name of a component of the origin of a relative color where it's allowed, or `nil`.
  private static func component(named name: String, allowsChannels: Bool) -> ColorComponent? {
    let name = name.lowercased()
    if name == "none" { return ColorComponent.none }
    return allowsChannels ? .channel(name) : nil
  }

  /// A color, or an expression that `currentcolor` is part of, with nothing after it.
  static func parseColorExpression(description: String) -> ColorExpression? {
    var data = description
    return data.withUTF8 {
      let bytes = BufferView(unsafeBufferPointer: $0)!
      var scanner = SVGAttributeScanner(bytes: bytes)
      guard let expression = scanner.scanColorExpression(), scanner.reader.consumeWhitespace() == nil else {
        return nil
      }
      return expression
    }
  }

  static func parseColor(description: String) -> SVGColor? {
    var data = description
    return data.withUTF8 {
      let bytes = BufferView(unsafeBufferPointer: $0)!
      var scanner = SVGAttributeScanner(bytes: bytes)
      return scanner.scanColor()
    }
  }
}

extension SVGAttributeScanner {
  mutating func scanStdDeviation() -> StdDeviation? {
    _ = reader.consumeWhitespace()
    guard let x = scanNumber() else { return nil }
    _ = reader.consumeWhitespace()
    guard let y = scanNumber() else { return .iso(SVGLength(value: x, unit: .number)) }
    _ = reader.consumeWhitespace()
    if reader.isEOF {
      return .hetero(
        x: SVGLength(value: x, unit: .number),
        y: SVGLength(value: y, unit: .number))
    }
    return nil
  }
}

// for preserveAspectRatio attribute
extension SVGAttributeScanner {
  mutating func scanPreserveAspectRatio() -> PreserveAspectRatio? {
    _ = reader.consumeWhitespace()
    if reader.isEOF { return nil }
    guard let alignValue = scanIdentity(),
      let type = PreserveAspectRatio.AlignType(rawValue: alignValue)
    else {
      return nil
    }
    _ = reader.consumeWhitespace()
    let option: PreserveAspectRatio.Option = {
      guard !reader.isEOF,
        let optionValue = scanIdentity()
      else {
        return .meet
      }
      return PreserveAspectRatio.Option(rawValue: optionValue) ?? .meet
    }()
    switch type {
    case .xMinYMin:
      return .normal(x: .min, y: .min, option: option)
    case .xMidYMin:
      return .normal(x: .mid, y: .min, option: option)
    case .xMaxYMin:
      return .normal(x: .max, y: .min, option: option)
    case .xMinYMid:
      return .normal(x: .min, y: .mid, option: option)
    case .xMidYMid:
      return .normal(x: .mid, y: .mid, option: option)
    case .xMaxYMid:
      return .normal(x: .max, y: .mid, option: option)
    case .xMinYMax:
      return .normal(x: .min, y: .max, option: option)
    case .xMidYMax:
      return .normal(x: .mid, y: .max, option: option)
    case .xMaxYMax:
      return .normal(x: .max, y: .max, option: option)
    case .none:
      return PreserveAspectRatio.none
    }
  }
}

extension SVGAttributeScanner {
  mutating func scanClipPath() -> SVGClipPath? {
    guard let name = scanIdentity() else {
      return nil
    }
    guard let type = SVGClipPathType(rawValue: name.lowercased()) else {
      return nil
    }
    switch type {
    case .none:
      return SVGClipPath.none
    case .url:
      guard consume(ascii: UInt8(ascii: "(")) else { return nil }
      consumeWhitespaceIfNext(UInt8(ascii: "#"))
      guard let id = scanIdentity() else { return nil }
      guard consume(ascii: UInt8(ascii: ")")) else { return nil }
      return .url(url: id)
    }
  }
}

extension SVGAttributeScanner {
  mutating func scanMask() -> SVGMask? {
    guard let name = scanIdentity() else {
      return nil
    }
    guard let type = SVGClipPathType(rawValue: name.lowercased()) else {
      return nil
    }
    switch type {
    case .none:
      return SVGMask.none
    case .url:
      guard consume(ascii: UInt8(ascii: "(")) else { return nil }
      consumeWhitespaceIfNext(UInt8(ascii: "#"))
      guard let id = scanIdentity() else { return nil }
      guard consume(ascii: UInt8(ascii: ")")) else { return nil }
      return .url(url: id)
    }
  }
}

// for svg length
extension SVGAttributeScanner {
  mutating func scanLengthType() -> SVGLengthType {
    if reader.isEOF {
      return .number
    }
    guard let first = reader.read() else { return .unknown }
    if reader.isEOF {
      switch first {
      case UInt8(ascii: "%"):
        return .percentage
      case UInt8(ascii: "Q"):
        return .q
      default:
        return .unknown
      }
    }
    guard let second = reader.read() else { return .unknown }
    if reader.isEOF {
      switch (first, second) {
      case (UInt8(ascii: "e"), UInt8(ascii: "m")):
        return .ems
      case (UInt8(ascii: "e"), UInt8(ascii: "x")):
        return .exs
      case (UInt8(ascii: "p"), UInt8(ascii: "x")):
        return .pixels
      case (UInt8(ascii: "c"), UInt8(ascii: "m")):
        return .centimeters
      case (UInt8(ascii: "m"), UInt8(ascii: "m")):
        return .millimeters
      case (UInt8(ascii: "i"), UInt8(ascii: "n")):
        return .inches
      case (UInt8(ascii: "p"), UInt8(ascii: "t")):
        return .points
      case (UInt8(ascii: "p"), UInt8(ascii: "c")):
        return .picas
      case (UInt8(ascii: "c"), UInt8(ascii: "h")):
        return .chs
      case (UInt8(ascii: "i"), UInt8(ascii: "c")):
        return .ic
      case (UInt8(ascii: "l"), UInt8(ascii: "h")):
        return .lhs
      case (UInt8(ascii: "v"), UInt8(ascii: "w")):
        return .vw
      case (UInt8(ascii: "v"), UInt8(ascii: "h")):
        return .vh
      case (UInt8(ascii: "v"), UInt8(ascii: "i")):
        return .vi
      case (UInt8(ascii: "v"), UInt8(ascii: "b")):
        return .vb
      default:
        return .unknown
      }
    }
    guard let third = reader.read() else { return .unknown }
    if reader.isEOF {
      switch (first, second, third) {
      case (UInt8(ascii: "r"), UInt8(ascii: "e"), UInt8(ascii: "m")):
        return .rems
      case (UInt8(ascii: "r"), UInt8(ascii: "l"), UInt8(ascii: "h")):
        return .rlhs
      default:
        return .unknown
      }
    }
    guard let fourth = reader.read() else { return .unknown }
    guard reader.isEOF else { return .unknown }
    switch (first, second, third, fourth) {
    case (UInt8(ascii: "v"), UInt8(ascii: "m"), UInt8(ascii: "a"), UInt8(ascii: "x")):
      return .vmax
    case (UInt8(ascii: "v"), UInt8(ascii: "m"), UInt8(ascii: "i"), UInt8(ascii: "n")):
      return .vmin
    default:
      return .unknown
    }
  }
}

extension Double {
  init?(prevalidatedBuffer buffer: BufferView<UInt8>) {
    let value = buffer.withUnsafePointer { nptr, count -> Double? in
      var endPtr: UnsafeMutablePointer<CChar>?
      let decodedValue = strtod_l(nptr, &endPtr, nil)
      if let endPtr, nptr.advanced(by: count) == endPtr {
        return decodedValue
      } else {
        return nil
      }
    }
    guard let value = value else {
      return nil
    }
    self = value
  }
}

extension UInt64 {
  init?(prevalidatedBuffer buffer: BufferView<UInt8>) {
    let value = buffer.withUnsafePointer { nptr, count -> UInt64? in
      var endPtr: UnsafeMutablePointer<CChar>?

      let decodedValue = strtoull_l(nptr, &endPtr, 16, nil)
      if let endPtr, nptr.advanced(by: count) == endPtr {
        return decodedValue
      } else {
        return nil
      }
    }
    guard let value = value else {
      return nil
    }
    self = value
  }
}

private var asciiNumbers: ClosedRange<UInt8> { UInt8(ascii: "0")...UInt8(ascii: "9") }
