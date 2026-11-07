import CoreGraphics
import Foundation

final class SVGEllipseElement: ShapeGeometry {
  static var type: SVGElementName {
    .ellipse
  }

  var type: SVGElementName {
    .ellipse
  }

  let base: SVGBaseElement
  let cx: SVGLength?
  let cy: SVGLength?
  let rx: SVGLength?
  let ry: SVGLength?

  init(base: SVGBaseElement, text _: String, attributes _: [String: String]) {
    self.base = base
    cx = base.style.cx
    cy = base.style.cy
    rx = base.style.rx
    ry = base.style.ry
  }

  /// The center and the radii, or `nil` without an area.
  private func geometry(in context: any GeometryContext) -> (center: CGPoint, radii: CGSize)? {
    let cx = cx?.value(context: context, mode: .width) ?? 0
    let cy = cy?.value(context: context, mode: .height) ?? 0
    let _rx = (rx?.value(context: context, mode: .width)).flatMap { $0 < 0 ? nil : $0 }
    let _ry = (ry?.value(context: context, mode: .height)).flatMap { $0 < 0 ? nil : $0 }
    let rx: CGFloat = _rx ?? _ry ?? 0
    let ry: CGFloat = _ry ?? _rx ?? 0
    guard rx > 0, ry > 0 else { return nil }
    return (CGPoint(x: cx, y: cy), CGSize(width: rx, height: ry))
  }

  func path(in context: any GeometryContext) -> CGPath? {
    guard let (center, radii) = geometry(in: context) else { return nil }
    let path = CGPath(
      ellipseIn: CGRect(
        origin: CGPoint(x: center.x - radii.width, y: center.y - radii.height),
        size: CGSize(width: 2 * radii.width, height: 2 * radii.height)), transform: nil)
    return path
  }

  func markerPath(in context: any GeometryContext) -> PathData? {
    geometry(in: context).map { PathData.ellipse(center: $0.center, radii: $0.radii) }
  }
}
