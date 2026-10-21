import CoreGraphics
import Foundation

final class SVGLineElement: ShapeGeometry {
  static var type: SVGElementName {
    .line
  }

  var type: SVGElementName {
    .line
  }

  let base: SVGBaseElement
  let x1: SVGLength?
  let y1: SVGLength?
  let x2: SVGLength?
  let y2: SVGLength?

  init(base: SVGBaseElement, text _: String, attributes: [String: String]) {
    self.base = base
    x1 = .init(attributes["x1"])
    y1 = .init(attributes["y1"])
    x2 = .init(attributes["x2"])
    y2 = .init(attributes["y2"])
  }

  func toPath(context: SVGContext) -> CGPath? {
    path(in: context)
  }

  func path(in context: any GeometryContext) -> CGPath? {
    let x1 = x1?.value(context: context, mode: .width) ?? 0
    let y1 = y1?.value(context: context, mode: .height) ?? 0
    let x2 = x2?.value(context: context, mode: .width) ?? 0
    let y2 = y2?.value(context: context, mode: .height) ?? 0
    let start = CGPoint(x: x1, y: y1)
    let end = CGPoint(x: x2, y: y2)
    guard start != end else { return nil }
    let path = CGMutablePath()
    path.move(to: start)
    path.addLine(to: end)
    return path
  }

  func frame(context: SVGContext, path: CGPath?) -> CGRect {
    frame(in: context, path: path)
  }

  /// The bounding box of the path, or of the stroke for a horizontal or vertical line, whose path has no area.
  func frame(in context: any GeometryContext, path: CGPath?) -> CGRect {
    guard let path = path else { return .zero }
    let r = path.boundingBoxOfPath
    if r.width > 0, r.height > 0 {
      return r
    }

    let x1 = x1?.value(context: context, mode: .width) ?? 0
    let y1 = y1?.value(context: context, mode: .height) ?? 0
    let x2 = x2?.value(context: context, mode: .width) ?? 0
    let y2 = y2?.value(context: context, mode: .height) ?? 0
    let length = sqrt(pow(x2 - x1, 2) + pow(y2 - y1, 2))
    let lineWidth = style.strokeWidth.value(context: context, mode: .other)
    let xmin = min(x1, x2)
    let ymin = min(y1, y2)
    if r.width > 0 {
      let origin = CGPoint(x: xmin, y: ymin - lineWidth / 2.0)
      return CGRect(origin: origin, size: CGSize(width: length, height: lineWidth))
    }
    if r.height > 0 {
      let origin = CGPoint(x: xmin - lineWidth / 2.0, y: ymin)
      return CGRect(origin: origin, size: CGSize(width: lineWidth, height: length))
    }
    return .zero
  }
}

extension SVGLineElement: Encodable {
  private enum CodingKeys: String, CodingKey {
    case x1
    case y1
    case x2
    case y2
  }

  func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: Self.CodingKeys.self)
    try container.encode(x1, forKey: .x1)
    try container.encode(y1, forKey: .y1)
    try container.encode(x1, forKey: .x2)
    try container.encode(y1, forKey: .y2)
  }
}
