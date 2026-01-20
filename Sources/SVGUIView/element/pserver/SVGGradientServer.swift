import CoreGraphics
import UIKit

enum SpreadMethod: String {
  case pad
  case `repeat`
  case reflect
}

protocol SVGGradientServer: SVGElement {
  var parentId: String? { get }
  var parentIds: [String] { get }
  var id: String? { get }
  var display: CSSDisplay? { get }
  var children: [any SVGElement] { get }
  func merged(other: any SVGGradientServer) -> (any SVGGradientServer)?
  func draw(path: UIBezierPath, context: SVGContext, opacity: Double)
  func stops(context: SVGContext) -> [SVGStopElement]
  init?(lhs: Self, rhs: SVGLinearGradientServer)
  init?(lhs: Self, rhs: SVGRadialGradientServer)
}

extension SVGGradientServer {
  func merged(other: any SVGGradientServer) -> (any SVGGradientServer)? {
    switch other {
    case let other as SVGLinearGradientServer:
      return Self(lhs: self, rhs: other)
    case let other as SVGRadialGradientServer:
      return Self(lhs: self, rhs: other)
    default:
      fatalError("not implemented")
    }
  }

  func stops(context: SVGContext) -> [SVGStopElement] {
    children.compactMap { $0 as? SVGStopElement }
  }

  func style(with _: Stylesheet) -> any SVGElement {
    self
  }
}

final class SVGLinearGradientServer: SVGGradientServer {
  static var type: SVGElementName {
    .linearGradient
  }

  var type: SVGElementName {
    .linearGradient
  }

  let base: SVGBaseElement
  let display: CSSDisplay?
  let color: SVGColor?
  let children: [any SVGElement]
  let id: String?
  let parentId: String?
  let gradientUnits: SVGUnitType?
  let spreadMethod: SpreadMethod?
  let x1: SVGLength?
  let y1: SVGLength?
  let x2: SVGLength?
  let y2: SVGLength?

  let parentIds: [String]

  private enum CodingKeys: String, CodingKey {
    case stops
  }

  init(base: SVGBaseElement, contents children: [any SVGElement]) {
    self.base = base
    self.children = children
    let attributes = base.attributes
    id = attributes["id"]?.trimmingCharacters(in: .whitespaces)
    display = CSSDisplay(rawValue: attributes["display", default: ""])

    x1 = SVGLength(attributes["x1"])
    y1 = SVGLength(attributes["y1"])
    x2 = SVGLength(attributes["x2"])
    y2 = SVGLength(attributes["y2"])
    color = SVGAttributeScanner.parseColor(description: attributes["color", default: ""])

    parentId = Self.parseLink(description: attributes["href"])
    gradientUnits = SVGUnitType(rawValue: attributes["gradientUnits", default: ""])
    spreadMethod = Self.parseSpreadMethod(attributes["spreadMethod", default: ""])

    if let parentId = parentId {
      parentIds = [parentId]
    } else {
      parentIds = []
    }
  }

  init?(lhs: SVGLinearGradientServer, rhs: SVGLinearGradientServer) {
    if let id = lhs.id {
      guard !rhs.parentIds.contains(id) else { return nil }
      parentIds = lhs.parentIds + rhs.parentIds
    } else {
      parentIds = lhs.parentIds
    }
    id = lhs.id
    self.base = lhs.base
    display = lhs.display ?? rhs.display
    x1 = lhs.x1 ?? rhs.x1
    y1 = lhs.y1 ?? rhs.y1
    x2 = lhs.x2 ?? rhs.x2
    y2 = lhs.y2 ?? rhs.y2
    color = lhs.color ?? rhs.color
    children = lhs.children.isEmpty ? rhs.children : lhs.children
    parentId = rhs.parentId
    gradientUnits = lhs.gradientUnits ?? rhs.gradientUnits
    spreadMethod = lhs.spreadMethod ?? rhs.spreadMethod
  }

  init?(lhs: SVGLinearGradientServer, rhs: SVGRadialGradientServer) {
    if let id = lhs.id {
      guard !lhs.parentIds.contains(id) else { return nil }
      parentIds = lhs.parentIds + rhs.parentIds
    } else {
      parentIds = lhs.parentIds
    }
    id = lhs.id
    base = lhs.base
    display = lhs.display ?? rhs.display
    x1 = lhs.x1
    y1 = lhs.y1
    x2 = lhs.x2
    y2 = lhs.y2
    color = lhs.color ?? rhs.color
    children = lhs.children.isEmpty ? rhs.children : lhs.children
    parentId = rhs.parentId
    gradientUnits = lhs.gradientUnits ?? rhs.gradientUnits
    spreadMethod = lhs.spreadMethod ?? rhs.spreadMethod
  }

  private static func parseLink(description: String?) -> String? {
    guard let description = description else { return nil }
    let hashId = description.trimmingCharacters(in: .whitespaces)
    if hashId.hasPrefix("#") {
      return String(hashId.dropFirst())
    }
    return nil
  }

  private static func parseSpreadMethod(_ src: String) -> SpreadMethod? {
    SpreadMethod(rawValue: src.trimmingCharacters(in: .whitespaces))
  }

  func draw(path: UIBezierPath, context: SVGContext, opacity: Double) {
    let stops = stops(context: context)
    let gradientUnits = gradientUnits ?? .objectBoundingBox
    let x1 = (x1 ?? .percent(0)).value(context: context, mode: .width, unitType: gradientUnits)
    let y1 = (y1 ?? .percent(0)).value(context: context, mode: .height, unitType: gradientUnits)
    let x2 = (x2 ?? .percent(100)).value(context: context, mode: .width, unitType: gradientUnits)
    let y2 = (y2 ?? .percent(0)).value(context: context, mode: .height, unitType: gradientUnits)
    let spreadMethod = spreadMethod ?? .pad

    let colors = stops.compactMap {
      switch $0.color {
      case .current:
        return color?.toUIColor(opacity: $0.opacity * opacity)?.cgColor
      case .color(let color, let colorOpacity):
        let colorOpacity = colorOpacity?.value ?? 1.0
        return color?.toUIColor(opacity: $0.opacity * opacity * colorOpacity)?.cgColor
      case .inherit, .none:
        // TODO: implement inherit, url(...), auto case
        return nil
      case .image:
        fatalError("Images not supported in gradient")
      }
    }
    guard !colors.isEmpty else { return }
    let space = CGColorSpaceCreateDeviceRGB()
    let locations: [CGFloat] = stops.map(\.offset.value)
    guard let gradient = CGGradient(colorsSpace: space, colors: colors as CFArray, locations: locations) else {
      return
    }
    let gContext = context.graphics
    gContext.saveGState()
    gContext.addPath(path.cgPath)
    gContext.clip()
    let frame = path.cgPath.boundingBoxOfPath
    let (sx, sy): (CGFloat, CGFloat) = {
      switch gradientUnits {
      case .userSpaceOnUse:
        return (1.0, 1.0)
      case .objectBoundingBox:
        if x1 == x2 || y1 == y2 {
          return (frame.width, frame.height)
        }
        let s = min(frame.width, frame.height)
        return (s, s)
      }
    }()
    let rect = CGRect(x: x1 * sx, y: y1 * sy, width: (x2 - x1) * sx, height: (y2 - y1) * sy)
    let rx: CGFloat
    let ry: CGFloat
    let x: CGFloat
    let y: CGFloat
    switch gradientUnits {
    case .userSpaceOnUse:
      rx = 1.0
      ry = 1.0
      x = 0
      y = 0
    case .objectBoundingBox:
      rx = sx / frame.width
      ry = sy / frame.height
      x = frame.minX * rx
      y = frame.minY * ry
    }
    let _x1 = rect.minX
    let _y1 = rect.minY
    let _x2 = rect.maxX
    let _y2 = rect.maxY

    if sx == sy {
      gContext.scaleBy(x: 1.0 / rx, y: 1.0 / ry)
    }

    switch spreadMethod {
    case .pad:
      let start = CGPoint(x: x + _x1, y: y + _y1)
      let end = CGPoint(x: x + _x2, y: y + _y2)
      let options: CGGradientDrawingOptions = [.drawsBeforeStartLocation, .drawsAfterEndLocation]
      gContext.drawLinearGradient(gradient, start: start, end: end, options: options)
    case .repeat:
      let dx = _x2 - _x1
      let dy = _y2 - _y1
      let n = min(ceil((x + _x1 - frame.minX) / dx), ceil((y + _y1 - frame.minY) / dy))
      let base = CGPoint(x: x + _x1 - dx * n, y: y + _y1 - dy * n)
      let m = min(ceil((frame.maxX - base.x) / dx), ceil((frame.maxY - base.y) / dy))
      for i in stride(from: 0, to: m, by: 1) {
        let start = CGPoint(x: base.x + i * dx, y: base.y + i * dy)
        let end = CGPoint(x: base.x + (i + 1) * dx, y: base.y + (i + 1) * dy)
        gContext.drawLinearGradient(gradient, start: start, end: end, options: [])
      }
    case .reflect:
      let reflected = CGGradient(colorsSpace: space, colors: colors as CFArray, locations: locations.reversed())!
      let dx = _x2 - _x1
      let dy = _y2 - _y1
      let n = min(ceil((x + _x1 - frame.minX) / dx), ceil((y + _y1 - frame.minY) / dy))
      let base = CGPoint(x: x + _x1 - dx * n, y: y + _y1 - dy * n)
      let m = min(ceil((frame.maxX - base.x) / dx), ceil((frame.maxY - base.y) / dy))
      for i in stride(from: 0, to: m, by: 1) {
        let start = CGPoint(x: base.x + i * dx, y: base.y + i * dy)
        let end = CGPoint(x: base.x + (i + 1) * dx, y: base.y + (i + 1) * dy)
        if Int(i - n) % 2 == 0 {
          gContext.drawLinearGradient(gradient, start: start, end: end, options: [])
        } else {
          gContext.drawLinearGradient(reflected, start: start, end: end, options: [])
        }
      }
    }
    gContext.restoreGState()
  }
}

extension SVGLinearGradientServer {
  func encode(to encoder: any Encoder) throws {
    fatalError()
  }
}

final class SVGRadialGradientServer: SVGGradientServer {
  static var type: SVGElementName {
    .radialGradient
  }

  var type: SVGElementName {
    .radialGradient
  }

  let base: SVGBaseElement
  let display: CSSDisplay?
  let color: SVGColor?
  let children: [any SVGElement]
  let spreadMethod: SpreadMethod?
  let gradientUnits: SVGUnitType?

  let id: String?
  let parentId: String?
  let parentIds: [String]

  let cx: SVGLength?
  let cy: SVGLength?
  let fx: SVGLength?
  let fy: SVGLength?
  let r: SVGLength?

  private enum CodingKeys: String, CodingKey {
    case stops
  }

  init(base: SVGBaseElement, contents children: [any SVGElement]) {
    self.base = base
    self.children = children
    let attributes = base.attributes
    id = attributes["id"]?.trimmingCharacters(in: .whitespaces)
    display = CSSDisplay(rawValue: attributes["display", default: ""])
    color = SVGAttributeScanner.parseColor(description: attributes["color", default: ""])
    cx = SVGLength(attributes["cx"])
    cy = SVGLength(attributes["cy"])
    fx = SVGLength(attributes["fx"])
    fy = SVGLength(attributes["fy"])
    r = SVGLength(attributes["r"])
    spreadMethod = Self.parseSpreadMethod(attributes["spreadMethod", default: ""])
    parentId = Self.parseLink(description: attributes["href"])
    gradientUnits = SVGUnitType(rawValue: attributes["gradientUnits", default: ""])

    parentIds = []
  }

  init?(lhs: SVGRadialGradientServer, rhs: SVGRadialGradientServer) {
    if let id = rhs.id {
      guard !lhs.parentIds.contains(id) else { return nil }
      parentIds = lhs.parentIds + [id]
    } else {
      parentIds = lhs.parentIds
    }
    id = lhs.id
    base = lhs.base
    display = lhs.display ?? rhs.display
    color = lhs.color ?? rhs.color
    cx = lhs.cx ?? rhs.cx
    cy = lhs.cy ?? rhs.cy
    fx = lhs.fx ?? rhs.fx
    fy = lhs.fy ?? rhs.fy
    r = lhs.r ?? rhs.r
    children = lhs.children.isEmpty ? rhs.children : lhs.children
    spreadMethod = lhs.spreadMethod ?? rhs.spreadMethod
    parentId = rhs.parentId
    gradientUnits = lhs.gradientUnits ?? rhs.gradientUnits
  }

  init?(lhs: SVGRadialGradientServer, rhs: SVGLinearGradientServer) {
    if let id = rhs.id {
      guard !lhs.parentIds.contains(id) else { return nil }
      parentIds = lhs.parentIds + [id]
    } else {
      parentIds = lhs.parentIds
    }
    id = lhs.id
    base = lhs.base
    display = lhs.display ?? rhs.display
    color = lhs.color ?? rhs.color
    cx = lhs.cx
    cy = lhs.cy
    fx = lhs.fx
    fy = lhs.fy
    r = lhs.r
    children = lhs.children.isEmpty ? rhs.children : lhs.children
    spreadMethod = lhs.spreadMethod ?? rhs.spreadMethod
    parentId = rhs.parentId
    gradientUnits = lhs.gradientUnits ?? rhs.gradientUnits
  }

  private static func parseLink(description: String?) -> String? {
    guard let description = description else { return nil }
    let hashId = description.trimmingCharacters(in: .whitespaces)
    if hashId.hasPrefix("#") {
      return String(hashId.dropFirst())
    }
    return nil
  }

  private static func parseSpreadMethod(_ src: String) -> SpreadMethod? {
    SpreadMethod(rawValue: src.trimmingCharacters(in: .whitespaces))
  }

  func draw(path: UIBezierPath, context: SVGContext, opacity: Double) {
    let stops = stops(context: context)
    let gradientUnits = gradientUnits ?? .objectBoundingBox
    let cx = (cx ?? .percent(50)).value(context: context, mode: .width, unitType: gradientUnits)
    let cy = (cy ?? .percent(50)).value(context: context, mode: .width, unitType: gradientUnits)
    let r = (r ?? .percent(50)).value(context: context, mode: .height, unitType: gradientUnits)
    let colors = stops.compactMap {
      switch $0.color {
      case .current:
        return color?.toUIColor(opacity: opacity)?.cgColor
      case .color(let color, let colorOpacity):
        let colorOpacity = colorOpacity?.value ?? 1.0
        return color?.toUIColor(opacity: $0.opacity * opacity * colorOpacity)?.cgColor
      case .inherit, .none:
        // TODO: implement inherit, url(...), auto case
        return nil
      case .image:
        fatalError("Images not supported in gradient")
      }
    }
    guard !colors.isEmpty else { return }
    let space = CGColorSpaceCreateDeviceRGB()
    let locations: [CGFloat] = stops.map(\.offset.value)

    let gradient = CGGradient(colorsSpace: space, colors: colors as CFArray, locations: locations)!

    let gContext = context.graphics
    gContext.saveGState()
    gContext.addPath(path.cgPath)
    gContext.clip()
    let frame = path.cgPath.boundingBoxOfPath
    let pp = CGPoint(x: cx, y: cy)

    let s: CGFloat
    let rx: CGFloat
    let ry: CGFloat
    let _cx: CGFloat
    let _cy: CGFloat
    switch gradientUnits {
    case .userSpaceOnUse:
      s = 1.0
      rx = 1.0
      ry = 1.0
      _cx = pp.x * s
      _cy = pp.y * s
    case .objectBoundingBox:
      s = min(frame.width, frame.height)
      rx = s / frame.width
      ry = s / frame.height
      _cx = pp.x * s + frame.minX * rx
      _cy = pp.y * s + frame.minY * ry
    }
    let _r = r * s

    if case .objectBoundingBox = gradientUnits, frame.width != frame.height {
      gContext.scaleBy(x: 1.0 / rx, y: 1.0 / ry)
    }
    gContext.drawRadialGradient(
      gradient,
      startCenter: .init(x: _cx, y: _cy),
      startRadius: 0,
      endCenter: .init(x: _cx, y: _cy),
      endRadius: _r,
      options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    context.restoreGState()
  }
}

extension SVGRadialGradientServer {
  func encode(to encoder: any Encoder) throws {
    fatalError()
  }
}
