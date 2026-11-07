import CoreGraphics
import Foundation
import _CSSParser

/// The reference box of a basic shape of `clip-path`, as CSS Masking 1 maps the boxes of CSS layout for SVG
/// elements, which have none: `content-box` and `padding-box` are `fill-box`, and `border-box` and `margin-box` are
/// `stroke-box`.
enum ClipBox: Sendable, Equatable {
  case fillBox
  case strokeBox
  case viewBox

  /// The box of a keyword of `<geometry-box>`, or `nil` if it isn't one.
  init?(keyword: String) {
    switch keyword.lowercased() {
    case "content-box", "padding-box", "fill-box": self = .fillBox
    case "border-box", "margin-box", "stroke-box": self = .strokeBox
    case "view-box": self = .viewBox
    default: return nil
    }
  }
}

/// A basic shape of CSS Shapes 1, which `clip-path` clips an element to. Percentages are of the reference box.
enum BasicShape: Sendable, Equatable {
  case circle(radius: ShapeRadius, center: ShapePosition)
  case ellipse(rx: ShapeRadius, ry: ShapeRadius, center: ShapePosition)
  case inset(InsetShape)
  case polygon(fillRule: FillRule, points: [ShapePosition])
}

/// The radius of a circle or an ellipse.
enum ShapeRadius: Sendable, Equatable {
  /// A length that isn't negative.
  case length(SVGLength)
  /// The distance from the center to the closest side of the reference box, which is the default.
  case closestSide
  /// The distance from the center to the farthest side of the reference box.
  case farthestSide
}

/// A point from the top left corner of the reference box. A position from the right or the bottom edge is a sum
/// with `100%`.
struct ShapePosition: Sendable, Equatable {
  static let center = ShapePosition(x: .percent(50), y: .percent(50))

  var x: SVGLength
  var y: SVGLength
}

/// A rectangle inset from the sides of the reference box, with rounded corners.
struct InsetShape: Sendable, Equatable {
  var top: SVGLength
  var right: SVGLength
  var bottom: SVGLength
  var left: SVGLength
  /// The horizontal and vertical radii of the top left, top right, bottom right and bottom left corners. Each is a
  /// length that isn't negative.
  var radii: [ShapePosition]
}

// MARK: - Parsing

extension SVGClipPath {
  /// A basic shape, a reference box or both, in either order, or `nil` if it's invalid.
  static func parseShape(_ input: inout _CSSParser.Parser, origin: DeclarationOrigin) -> SVGClipPath? {
    var shape: BasicShape?
    var box: ClipBox?
    while !input.isExhausted() {
      let state = input.state
      if box == nil, case .success(.ident(let name)) = input.next(), let keyword = ClipBox(keyword: name) {
        box = keyword
        continue
      }
      input.reset(state: state)
      guard shape == nil, let next = BasicShape.parse(&input, origin: origin) else { return nil }
      shape = next
    }
    guard shape != nil || box != nil else { return nil }
    return .shape(shape, box: box ?? .strokeBox)
  }
}

extension BasicShape {
  /// A basic shape function, or `nil` if it's invalid or isn't one of `circle()`, `ellipse()`, `inset()` and
  /// `polygon()`.
  static func parse(_ input: inout _CSSParser.Parser, origin: DeclarationOrigin) -> BasicShape? {
    guard case .success(.function(let name)) = input.next() else { return nil }
    let result: Result<BasicShape, CSSParseError> = input.parseNestedBlock { input in
      let shape: BasicShape? =
        switch name.lowercased() {
        case "circle": circle(&input, origin: origin)
        case "ellipse": ellipse(&input, origin: origin)
        case "inset": inset(&input, origin: origin)
        case "polygon": polygon(&input, origin: origin)
        default: nil
        }
      guard let shape, input.isExhausted() else { return .failure(input.newCustomError(error: .invalid)) }
      return .success(shape)
    }
    return try? result.get()
  }

  private static func circle(_ input: inout _CSSParser.Parser, origin: DeclarationOrigin) -> BasicShape? {
    let radius = radius(&input, origin: origin)
    guard let center = center(&input, origin: origin) else { return nil }
    return .circle(radius: radius ?? .closestSide, center: center)
  }

  private static func ellipse(_ input: inout _CSSParser.Parser, origin: DeclarationOrigin) -> BasicShape? {
    var (rx, ry) = (ShapeRadius.closestSide, ShapeRadius.closestSide)
    if let x = radius(&input, origin: origin) {
      // The radii come in pairs.
      guard let y = radius(&input, origin: origin) else { return nil }
      (rx, ry) = (x, y)
    }
    guard let center = center(&input, origin: origin) else { return nil }
    return .ellipse(rx: rx, ry: ry, center: center)
  }

  private static func inset(_ input: inout _CSSParser.Parser, origin: DeclarationOrigin) -> BasicShape? {
    guard let sides = lengths(&input, origin: origin, allowsNegative: true) else { return nil }
    var radii = Array(repeating: ShapePosition(x: .number(0), y: .number(0)), count: 4)
    if !input.isExhausted() {
      guard case .success(.ident(let name)) = input.next(), name.lowercased() == "round",
        let horizontal = lengths(&input, origin: origin, allowsNegative: false)
      else { return nil }
      var vertical = horizontal
      if case .success = input.tryParse({ $0.expectDelim(expectedValue: "/") }) {
        guard let values = lengths(&input, origin: origin, allowsNegative: false) else { return nil }
        vertical = values
      }
      radii = zip(horizontal, vertical).map { ShapePosition(x: $0, y: $1) }
    }
    return .inset(InsetShape(top: sides[0], right: sides[1], bottom: sides[2], left: sides[3], radii: radii))
  }

  private static func polygon(_ input: inout _CSSParser.Parser, origin: DeclarationOrigin) -> BasicShape? {
    var fillRule = FillRule.nonzero
    let state = input.state
    if case .success(.ident(let name)) = input.next(), let rule = FillRule(rawValue: name.lowercased()) {
      guard case .success = input.expectComma() else { return nil }
      fillRule = rule
    } else {
      input.reset(state: state)
    }
    var points = [ShapePosition]()
    repeat {
      guard let x = lengthPercentage(&input, origin: origin), let y = lengthPercentage(&input, origin: origin)
      else { return nil }
      points.append(ShapePosition(x: x, y: y))
    } while input.tryParse({ $0.expectComma() }).isSuccess
    return .polygon(fillRule: fillRule, points: points)
  }

  /// A radius, or `nil` if there's none, which leaves the input where it was.
  private static func radius(_ input: inout _CSSParser.Parser, origin: DeclarationOrigin) -> ShapeRadius? {
    let state = input.state
    switch input.next() {
    case .success(.ident(let name)) where name.lowercased() == "closest-side":
      return .closestSide
    case .success(.ident(let name)) where name.lowercased() == "farthest-side":
      return .farthestSide
    default:
      input.reset(state: state)
    }
    guard let length = lengthPercentage(&input, origin: origin), !length.isNegative else {
      input.reset(state: state)
      return nil
    }
    return .length(length)
  }

  /// The center after `at`, the center of the reference box if there's no `at`, or `nil` if it's invalid.
  private static func center(_ input: inout _CSSParser.Parser, origin: DeclarationOrigin) -> ShapePosition? {
    if input.isExhausted() { return .center }
    guard case .success(.ident(let name)) = input.next(), name.lowercased() == "at" else { return nil }
    return ShapePosition.parse(&input, origin: origin)
  }

  /// One to four lengths, which are the top, right, bottom and left values as the margin shorthand gives them.
  private static func lengths(
    _ input: inout _CSSParser.Parser, origin: DeclarationOrigin, allowsNegative: Bool
  ) -> [SVGLength]? {
    var values = [SVGLength]()
    while values.count < 4 {
      let state = input.state
      guard let value = lengthPercentage(&input, origin: origin) else {
        input.reset(state: state)
        break
      }
      guard allowsNegative || !value.isNegative else { return nil }
      values.append(value)
    }
    switch values.count {
    case 1: return [values[0], values[0], values[0], values[0]]
    case 2: return [values[0], values[1], values[0], values[1]]
    case 3: return [values[0], values[1], values[2], values[1]]
    case 4: return values
    default: return nil
    }
  }
}

extension ShapePosition {
  /// A `<position>` of one, two or four values, or `nil` if it's invalid. Keywords are percentages.
  static func parse(_ input: inout _CSSParser.Parser, origin: DeclarationOrigin) -> ShapePosition? {
    var values = [OriginValue]()
    while values.count < 4, !input.isExhausted() {
      guard let value = originValue(&input, origin: origin) else { return nil }
      values.append(value)
    }
    switch values.count {
    case 1:
      switch values[0] {
      case .top, .bottom: return ShapePosition(x: .percent(50), y: values[0].length)
      default: return ShapePosition(x: values[0].length, y: .percent(50))
      }
    case 2:
      var (x, y) = (values[0], values[1])
      // Two keywords can come in either order.
      if x.isKeyword, y.isKeyword, x.isVertical || y.isHorizontal { swap(&x, &y) }
      guard !x.isVertical, !y.isHorizontal else { return nil }
      return ShapePosition(x: x.length, y: y.length)
    case 4:
      // Two pairs of an edge and an offset from it, in either order.
      guard let first = offset(values[0], values[1]), let second = offset(values[2], values[3]),
        first.isHorizontal != second.isHorizontal
      else { return nil }
      return first.isHorizontal
        ? ShapePosition(x: first.length, y: second.length) : ShapePosition(x: second.length, y: first.length)
    default:
      return nil
    }
  }

  /// The length from the top or the left edge of an edge keyword and an offset from it.
  private static func offset(_ edge: OriginValue, _ offset: OriginValue) -> (length: SVGLength, isHorizontal: Bool)? {
    guard case .length(let length) = offset else { return nil }
    switch edge {
    case .left: return (length, true)
    case .top: return (length, false)
    case .right: return (SVGLength.sum(of: [.percent(100), length.negated]) ?? length, true)
    case .bottom: return (SVGLength.sum(of: [.percent(100), length.negated]) ?? length, false)
    default: return nil
    }
  }
}

// MARK: - Geometry

extension SVGClipPath {
  /// The path of a basic shape or a reference box, in the user space of the clipped element, and its fill rule.
  func shapePath(in box: CGRect, context: any SVGLengthContext) -> (path: CGPath, fillRule: FillRule)? {
    guard case .shape(let shape, _) = self else { return nil }
    guard let shape else { return (CGPath(rect: box, transform: nil), .nonzero) }
    return shape.path(in: box, context: context)
  }
}

extension BasicShape {
  /// The path of the shape in a reference box, and its fill rule.
  func path(in box: CGRect, context: any SVGLengthContext) -> (path: CGPath, fillRule: FillRule) {
    let path = CGMutablePath()
    switch self {
    case .circle(let radius, let center):
      let point = center.point(in: box, context: context)
      let (dx, dy) = Self.distances(from: point, to: box)
      let r: CGFloat =
        switch radius {
        case .length(let length):
          length.value(total: sqrt(box.width * box.width + box.height * box.height) / sqrt(2), context: context)
        case .closestSide: min(dx.closest, dy.closest)
        case .farthestSide: max(dx.farthest, dy.farthest)
        }
      if r > 0 { path.addEllipse(in: CGRect(x: point.x - r, y: point.y - r, width: 2 * r, height: 2 * r)) }
      return (path, .nonzero)
    case .ellipse(let rx, let ry, let center):
      let point = center.point(in: box, context: context)
      let (dx, dy) = Self.distances(from: point, to: box)
      func resolved(_ radius: ShapeRadius, size: CGFloat, distances: (closest: CGFloat, farthest: CGFloat)) -> CGFloat {
        switch radius {
        case .length(let length): length.value(total: size, context: context)
        case .closestSide: distances.closest
        case .farthestSide: distances.farthest
        }
      }
      let x = resolved(rx, size: box.width, distances: dx)
      let y = resolved(ry, size: box.height, distances: dy)
      if x > 0, y > 0 { path.addEllipse(in: CGRect(x: point.x - x, y: point.y - y, width: 2 * x, height: 2 * y)) }
      return (path, .nonzero)
    case .inset(let inset):
      inset.add(to: path, in: box, context: context)
      return (path, .nonzero)
    case .polygon(let fillRule, let points):
      path.addLines(between: points.map { $0.point(in: box, context: context) })
      path.closeSubpath()
      return (path, fillRule)
    }
  }

  /// The distances from a point to the closest and the farthest of the vertical and the horizontal sides of a box.
  private static func distances(
    from point: CGPoint, to box: CGRect
  ) -> (x: (closest: CGFloat, farthest: CGFloat), y: (closest: CGFloat, farthest: CGFloat)) {
    let (left, right) = (abs(point.x - box.minX), abs(box.maxX - point.x))
    let (top, bottom) = (abs(point.y - box.minY), abs(box.maxY - point.y))
    return ((min(left, right), max(left, right)), (min(top, bottom), max(top, bottom)))
  }
}

extension ShapePosition {
  /// The point in a reference box.
  func point(in box: CGRect, context: any SVGLengthContext) -> CGPoint {
    CGPoint(
      x: box.minX + x.value(total: box.width, context: context),
      y: box.minY + y.value(total: box.height, context: context))
  }
}

extension InsetShape {
  /// Adds the rounded rectangle to a path, which it leaves empty if the rectangle is.
  fileprivate func add(to path: CGMutablePath, in box: CGRect, context: any SVGLengthContext) {
    var (top, bottom) = (top.value(total: box.height, context: context), bottom.value(total: box.height, context: context))
    var (left, right) = (left.value(total: box.width, context: context), right.value(total: box.width, context: context))
    // Insets that add up to more than the box are reduced in proportion, as CSS Shapes 1 says.
    if left + right > box.width, left + right > 0 {
      let scale = box.width / (left + right)
      (left, right) = (left * scale, right * scale)
    }
    if top + bottom > box.height, top + bottom > 0 {
      let scale = box.height / (top + bottom)
      (top, bottom) = (top * scale, bottom * scale)
    }
    let rect = CGRect(x: box.minX + left, y: box.minY + top, width: box.width - left - right, height: box.height - top - bottom)
    guard rect.width > 0, rect.height > 0 else { return }
    // Percentages of the radii are of the reference box. Radii that overlap are reduced by the same factor, as
    // CSS Backgrounds 3 reduces the radii of a border.
    var corners = radii.map {
      CGSize(width: $0.x.value(total: box.width, context: context), height: $0.y.value(total: box.height, context: context))
    }
    let sums = [
      (corners[0].width + corners[1].width, rect.width), (corners[3].width + corners[2].width, rect.width),
      (corners[0].height + corners[3].height, rect.height), (corners[1].height + corners[2].height, rect.height),
    ]
    let factor = sums.reduce(1) { $1.0 > 0 ? min($0, $1.1 / $1.0) : $0 }
    if factor < 1 { corners = corners.map { CGSize(width: $0.width * factor, height: $0.height * factor) } }
    // A corner with a radius of zero in either direction is square.
    corners = corners.map { $0.width > 0 && $0.height > 0 ? $0 : .zero }
    // The control points of a quarter of an ellipse, as a cubic Bézier curve.
    let k: CGFloat = 0.552_284_749_8
    let (tl, tr, br, bl) = (corners[0], corners[1], corners[2], corners[3])
    path.move(to: CGPoint(x: rect.minX + tl.width, y: rect.minY))
    path.addLine(to: CGPoint(x: rect.maxX - tr.width, y: rect.minY))
    path.addCurve(
      to: CGPoint(x: rect.maxX, y: rect.minY + tr.height),
      control1: CGPoint(x: rect.maxX - tr.width * (1 - k), y: rect.minY),
      control2: CGPoint(x: rect.maxX, y: rect.minY + tr.height * (1 - k)))
    path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - br.height))
    path.addCurve(
      to: CGPoint(x: rect.maxX - br.width, y: rect.maxY),
      control1: CGPoint(x: rect.maxX, y: rect.maxY - br.height * (1 - k)),
      control2: CGPoint(x: rect.maxX - br.width * (1 - k), y: rect.maxY))
    path.addLine(to: CGPoint(x: rect.minX + bl.width, y: rect.maxY))
    path.addCurve(
      to: CGPoint(x: rect.minX, y: rect.maxY - bl.height),
      control1: CGPoint(x: rect.minX + bl.width * (1 - k), y: rect.maxY),
      control2: CGPoint(x: rect.minX, y: rect.maxY - bl.height * (1 - k)))
    path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + tl.height))
    path.addCurve(
      to: CGPoint(x: rect.minX + tl.width, y: rect.minY),
      control1: CGPoint(x: rect.minX, y: rect.minY + tl.height * (1 - k)),
      control2: CGPoint(x: rect.minX + tl.width * (1 - k), y: rect.minY))
    path.closeSubpath()
  }
}

// MARK: - Animation

/// Basic shapes are interpolated when they're the same function with the same reference box, and their lengths
/// can be interpolated, as CSS Shapes 1 says. Radii that are keywords are interpolated only when they're the same
/// keyword. Polygons need the same fill rule and the same number of points. Other values change discretely.
extension SVGClipPath: Animatable {
  func interpolated(to other: SVGClipPath, progress: Double) -> SVGClipPath? {
    guard case .shape(let from?, let box) = self, case .shape(let to?, let otherBox) = other, box == otherBox,
      let shape = from.interpolated(to: to, progress: progress)
    else { return nil }
    return .shape(shape, box: box)
  }

  func adding(_: SVGClipPath) -> SVGClipPath? {
    nil
  }

  func pacedDistance(to _: SVGClipPath) -> Double? {
    nil
  }
}

extension BasicShape {
  fileprivate func interpolated(to other: BasicShape, progress: Double) -> BasicShape? {
    func length(_ a: SVGLength, _ b: SVGLength) -> SVGLength? {
      a.interpolated(to: b, progress: progress)
    }
    func position(_ a: ShapePosition, _ b: ShapePosition) -> ShapePosition? {
      guard let x = length(a.x, b.x), let y = length(a.y, b.y) else { return nil }
      return ShapePosition(x: x, y: y)
    }
    func radius(_ a: ShapeRadius, _ b: ShapeRadius) -> ShapeRadius? {
      switch (a, b) {
      case (.length(let a), .length(let b)): length(a, b).map { .length($0.nonNegative) }
      default: a == b ? a : nil
      }
    }
    switch (self, other) {
    case (.circle(let r1, let c1), .circle(let r2, let c2)):
      guard let r = radius(r1, r2), let c = position(c1, c2) else { return nil }
      return .circle(radius: r, center: c)
    case (.ellipse(let x1, let y1, let c1), .ellipse(let x2, let y2, let c2)):
      guard let x = radius(x1, x2), let y = radius(y1, y2), let c = position(c1, c2) else { return nil }
      return .ellipse(rx: x, ry: y, center: c)
    case (.inset(let a), .inset(let b)):
      guard let top = length(a.top, b.top), let right = length(a.right, b.right),
        let bottom = length(a.bottom, b.bottom), let left = length(a.left, b.left)
      else { return nil }
      var radii = [ShapePosition]()
      for (r1, r2) in zip(a.radii, b.radii) {
        guard let r = position(r1, r2) else { return nil }
        radii.append(ShapePosition(x: r.x.nonNegative, y: r.y.nonNegative))
      }
      return .inset(InsetShape(top: top, right: right, bottom: bottom, left: left, radii: radii))
    case (.polygon(let rule1, let p1), .polygon(let rule2, let p2)):
      guard rule1 == rule2, p1.count == p2.count else { return nil }
      var points = [ShapePosition]()
      for (a, b) in zip(p1, p2) {
        guard let point = position(a, b) else { return nil }
        points.append(point)
      }
      return .polygon(fillRule: rule1, points: points)
    default:
      return nil
    }
  }
}
