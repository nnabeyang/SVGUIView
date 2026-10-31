import Foundation

/// The value of `fill` or `stroke`.
indirect enum Paint: Sendable, Equatable {
  case none
  case color(SVGColor)
  /// The value of `color`, which stays a keyword in computed values and is resolved where it's used.
  case currentColor
  /// A paint server, such as a gradient or a pattern, by its ID, and the paint used instead where the server can't
  /// paint: `none`, a color or `currentColor`.
  case url(String, fallback: Paint?)

  init?(_ text: String) {
    var data = text
    let paint = data.withUTF8 {
      let bytes = BufferView(unsafeBufferPointer: $0)!
      var scanner = SVGAttributeScanner(bytes: bytes)
      return scanner.scanPaint()
    }
    // A name that isn't a color, or a function that isn't supported, such as `lab()`, is invalid.
    switch paint {
    case .color(let color), .url(_, .color(let color)?):
      if color.toCGColor(opacity: 1) == nil { return nil }
    default:
      break
    }
    guard let paint else { return nil }
    self = paint
  }
}

/// The value of `color`, `stop-color` or `flood-color`.
enum ColorValue: Sendable, Equatable {
  case color(SVGColor)
  case currentColor

  init?(_ text: String) {
    if keyword(text) == "currentcolor" {
      self = .currentColor
      return
    }
    // A name that isn't a color, or a function that isn't supported, such as `lab()`, is invalid.
    guard let color = SVGAttributeScanner.parseColor(description: text), color.toCGColor(opacity: 1) != nil else {
      return nil
    }
    self = .color(color)
  }
}

/// The value of `fill-rule` or `clip-rule`.
enum FillRule: String, CaseIterable, Sendable {
  case nonzero
  case evenodd
}

/// What a shape is rendered for, which trades the precision of its edges for speed or crispness.
enum ShapeRendering: String, CaseIterable, Sendable {
  case auto
  case optimizeSpeed
  case crispEdges
  case geometricPrecision

  /// Whether the edges of a shape rendered for it are antialiased.
  var antialiases: Bool {
    switch self {
    case .auto, .geometricPrecision: true
    case .optimizeSpeed, .crispEdges: false
    }
  }
}

/// The order in which a shape or text paints its fill, its stroke and its markers.
struct PaintOrder: Equatable, Sendable {
  enum Layer: Sendable {
    case fill, stroke, markers
  }

  /// The fill, the stroke and the markers in the order that they're painted.
  let layers: [Layer]

  static let normal = PaintOrder(first: [])

  /// The order that paints the given layers first, and the others after them in their normal order.
  init(first: [Layer]) {
    layers = first + [Layer.fill, .stroke, .markers].filter { !first.contains($0) }
  }

  /// Whether the stroke is painted before the fill.
  var strokesFirst: Bool {
    (layers.firstIndex(of: .stroke) ?? 0) < (layers.firstIndex(of: .fill) ?? 0)
  }
}
