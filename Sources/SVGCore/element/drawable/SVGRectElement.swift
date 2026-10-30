import CoreGraphics
import Foundation

final class SVGRectElement: ShapeGeometry {
  static var type: SVGElementName {
    .rect
  }

  var type: SVGElementName {
    .rect
  }

  let base: SVGBaseElement
  let x: SVGLength?
  let y: SVGLength?
  let rx: SVGLength?
  let ry: SVGLength?
  let width: SVGLength?
  let height: SVGLength?

  init(base: SVGBaseElement, text _: String, attributes: [String: String]) {
    self.base = base
    x = base.style.x
    y = base.style.y
    rx = .init(attributes["rx"])
    ry = .init(attributes["ry"])
    width = base.style.width
    height = base.style.height
  }

  /// The rectangle and the radii of its corners, or `nil` if it has no area.
  private func geometry(in context: any GeometryContext) -> (rect: CGRect, corner: CGSize)? {
    let x = x?.value(context: context, mode: .width) ?? 0
    let y = y?.value(context: context, mode: .height) ?? 0
    let _rx = (rx?.value(context: context, mode: .width)).flatMap { $0 < 0 ? nil : $0 }
    let _ry = (ry?.value(context: context, mode: .height)).flatMap { $0 < 0 ? nil : $0 }
    let rx: CGFloat = _rx ?? _ry ?? 0
    let ry: CGFloat = _ry ?? _rx ?? 0
    let width = width?.value(context: context, mode: .width) ?? 0
    let height = height?.value(context: context, mode: .height) ?? 0
    guard width > 0, height > 0 else {
      return nil
    }
    return (CGRect(x: x, y: y, width: width, height: height), CGSize(width: min(width / 2.0, rx), height: min(height / 2.0, ry)))
  }

  func path(in context: any GeometryContext) -> CGPath? {
    guard let (rect, corner) = geometry(in: context) else { return nil }
    let path = CGMutablePath()
    path.addRoundedRect(rect, cornerSize: corner)
    return path
  }

  /// The path of SVG 2 for a rectangle, which starts at the end of the arc of the top left corner and goes
  /// clockwise, with an arc at each rounded corner.
  func markerPath(in context: any GeometryContext) -> PathData? {
    guard let (r, c) = geometry(in: context) else { return nil }
    guard c.width > 0, c.height > 0 else {
      return PathData(commands: [
        PathCommand(type: .M, values: [r.minX, r.minY]), PathCommand(type: .H, values: [r.maxX]),
        PathCommand(type: .V, values: [r.maxY]), PathCommand(type: .H, values: [r.minX]),
        PathCommand(type: .Z, values: []),
      ])
    }
    func arc(to x: CGFloat, _ y: CGFloat) -> PathCommand {
      PathCommand(type: .A, values: [c.width, c.height, 0, 0, 1, x, y])
    }
    return PathData(commands: [
      PathCommand(type: .M, values: [r.minX + c.width, r.minY]), PathCommand(type: .H, values: [r.maxX - c.width]),
      arc(to: r.maxX, r.minY + c.height), PathCommand(type: .V, values: [r.maxY - c.height]),
      arc(to: r.maxX - c.width, r.maxY), PathCommand(type: .H, values: [r.minX + c.width]),
      arc(to: r.minX, r.maxY - c.height), PathCommand(type: .V, values: [r.minY + c.height]),
      arc(to: r.minX + c.width, r.minY), PathCommand(type: .Z, values: []),
    ])
  }
}

extension SVGRectElement: Encodable {
  private enum CodingKeys: String, CodingKey {
    case x
    case y
    case width
    case height
  }

  func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: Self.CodingKeys.self)
    try container.encode(x, forKey: .x)
    try container.encode(y, forKey: .y)
    try container.encode(width, forKey: .width)
    try container.encode(height, forKey: .height)
  }
}
