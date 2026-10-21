import Foundation

/// The value of `fill` or `stroke`.
enum Paint: Sendable {
  case none
  case color(SVGColor)
  /// The value of `color`, which stays a keyword in computed values and is resolved where it's used.
  case currentColor
  /// A paint server, such as a gradient or a pattern, by its ID.
  case url(String)

  init?(_ text: String) {
    var data = text
    let fill = data.withUTF8 {
      let bytes = BufferView(unsafeBufferPointer: $0)!
      var scanner = SVGAttributeScanner(bytes: bytes)
      return scanner.scanFill()
    }
    switch fill {
    case .current:
      self = .currentColor
    case .color(.url(let id), _):
      self = .url(id)
    case .color(.named(let name), _) where name.name.lowercased() == "none":
      self = .none
    // A name that isn't a color, or a function that isn't supported, such as `hsla()`, is invalid.
    case .color(.some(let color), _) where color.toCGColor(opacity: 1) == nil:
      return nil
    case .color(.some(let color), _):
      self = .color(color)
    case .color(.none, _), .inherit, .image, nil:
      return nil
    }
  }
}

/// The value of `color`, `stop-color` or `flood-color`.
enum ColorValue: Sendable {
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
