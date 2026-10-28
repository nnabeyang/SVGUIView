import Foundation

/// The value of `fill` or `stroke`.
enum Paint: Sendable, Equatable {
  case none
  case color(SVGColor)
  /// The value of `color`, which stays a keyword in computed values and is resolved where it's used.
  case currentColor
  /// A paint server, such as a gradient or a pattern, by its ID.
  case url(String)

  init?(_ text: String) {
    var data = text
    let paint = data.withUTF8 {
      let bytes = BufferView(unsafeBufferPointer: $0)!
      var scanner = SVGAttributeScanner(bytes: bytes)
      return scanner.scanPaint()
    }
    // A name that isn't a color, or a function that isn't supported, such as `hsla()`, is invalid.
    if case .color(let color) = paint, color.toCGColor(opacity: 1) == nil { return nil }
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
    // A name that isn't a color, or a function that isn't supported, such as `hsla()`, is invalid.
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
