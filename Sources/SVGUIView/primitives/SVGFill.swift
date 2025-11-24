import CoreGraphics
import Foundation

enum SVGFill {
  case inherit
  case current
  case color(color: SVGColor?, opacity: SVGOpacity?)
  case image(data: Data?)

  init?(style: SVGUIStyle) {
    let opacity: SVGOpacity? = {
      switch style[.fillOpacity] {
      case .number(let value):
        return .number(value)
      default:
        return nil
      }
    }()
    if case .fill(let value) = style[.fill] {
      switch value {
      case .inherit:
        self = .inherit
      case .current:
        self = .current
      case .color(let color):
        self = .color(color: color, opacity: opacity)
      }
      return
    }
    guard let opacity = opacity else {
      return nil
    }
    self = .color(color: nil, opacity: opacity)
  }

  init?(style: SVGUIStyle, attributes: [String: String]) {
    let opacity: SVGOpacity? = {
      switch style[.fillOpacity] {
      case .number(let value):
        return .number(value)
      default:
        return SVGOpacity(attributes["fill-opacity"])
      }
    }()
    if case .fill(let value) = style[.fill] {
      switch value {
      case .inherit:
        self = .inherit
      case .current:
        self = .current
      case .color(let color):
        self = .color(color: color, opacity: opacity)
      }
      return
    }

    var data = attributes["fill", default: ""]
    let fill = data.withUTF8 {
      let bytes = BufferView(unsafeBufferPointer: $0)!
      var scanner = SVGAttributeScanner(bytes: bytes)
      return scanner.scanFill(opacity: opacity)
    }
    guard let fill = fill else {
      guard let opacity = opacity else {
        return nil
      }
      self = .color(color: nil, opacity: opacity)
      return
    }
    self = fill
  }

  init?(description: String) {
    var data = description
    let fill = data.withUTF8 {
      let bytes = BufferView(unsafeBufferPointer: $0)!
      var scanner = SVGAttributeScanner(bytes: bytes)
      return scanner.scanFill()
    }
    guard let fill = fill else {
      return nil
    }
    self = fill
  }

  init?(attributes: [String: String]) {
    let opacity = SVGOpacity(attributes["fill-opacity"])
    var data = attributes["fill", default: ""]
    let fill = data.withUTF8 {
      let bytes = BufferView(unsafeBufferPointer: $0)!
      var scanner = SVGAttributeScanner(bytes: bytes)
      return scanner.scanFill(opacity: opacity)
    }
    guard let fill = fill else {
      return nil
    }
    self = fill
  }

  init?(lhs: SVGFill?, rhs: SVGFill?) {
    guard let rhs = rhs else {
      guard let lhs = lhs else { return nil }
      self = lhs
      return
    }
    guard let lhs = lhs else {
      self = rhs
      return
    }
    switch (lhs, rhs) {
    case (.color(let lc, let lo), .color(let rc, let ro)):
      self = .color(color: lc ?? rc, opacity: lo ?? ro)
    default:
      self = lhs
    }
  }
}

extension SVGFill: Equatable {
  static func == (lhs: SVGFill, rhs: SVGFill) -> Bool {
    switch (lhs, rhs) {
    case (.color(let l, let lo), .color(let r, let ro)):
      return l?.description == r?.description && lo == ro
    case (.image(let l), .image(let r)):
      return l == r
    default:
      return false
    }
  }
}

extension SVGFill: Encodable {
  func encode(to encoder: any Encoder) throws {
    switch self {
    case .inherit:
      try "inherit".encode(to: encoder)
    case .current:
      try "currentColor".encode(to: encoder)
    case .color(let color, let opacity):
      var container = encoder.unkeyedContainer()
      if let color = color {
        try container.encode(color)
      }
      if let opacity = opacity {
        try container.encode(opacity)
      }
    case .image(let data):
      try data?.encode(to: encoder)
    }
  }
}
