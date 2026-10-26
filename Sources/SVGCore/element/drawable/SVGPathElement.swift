import CoreGraphics
import Foundation

final class SVGPathElement: ShapeGeometry {
  static var type: SVGElementName {
    .path
  }

  var type: SVGElementName {
    .path
  }

  let base: SVGBaseElement
  let data: PathData

  init(base: SVGBaseElement, text _: String, attributes: [String: String]) {
    self.base = base
    data = attributes["d"].map(PathData.init) ?? .none
  }

  func path(in context: any GeometryContext) -> CGPath? {
    let pathContext = SVGPathContext()
    for command in data.commands {
      pathContext.apply(command)
    }
    return pathContext.path?.applying(scale(context: context))
  }
}

extension SVGPathElement: Encodable {
  private enum CodingKeys: String, CodingKey {
    case d
  }

  func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: Self.CodingKeys.self)
    try container.encode(data.commands, forKey: .d)
  }
}

final class SVGPathContext {
  var path: CGMutablePath?
  var cubicPoint: CGPoint?
  var quadrPoint: CGPoint?
  init() {}

  private func createPathIfNeeded() -> CGMutablePath {
    guard let path = path else {
      let newPath = CGMutablePath()
      self.path = newPath
      return newPath
    }
    return path
  }

  static func takeMirrorIfNeeded(p1: CGPoint, p2: CGPoint?) -> CGPoint {
    guard let p2 = p2 else { return p1 }
    return CGPoint(x: (2 * p1.x) - p2.x, y: (2 * p1.y) - p2.y)
  }

  /// Adds a command to the path. A command before the first moveto draws nothing.
  func apply(_ command: PathCommand) {
    let isAbsolute = command.type.isAbsolute
    let v = command.values
    if command.type == .M || command.type == .m {
      M(path: path, isMoved: false, x: v[0], y: v[1], isAbsolute: isAbsolute)
    } else {
      guard let path else { return }
      switch command.type {
      case .Z, .z:
        Z(path: path)
      case .L, .l:
        L(path: path, x: v[0], y: v[1], isAbsolute: isAbsolute)
      case .H, .h:
        L(path: path, x: v[0], y: nil, isAbsolute: isAbsolute)
      case .V, .v:
        L(path: path, x: nil, y: v[0], isAbsolute: isAbsolute)
      case .C, .c:
        C(path: path, x1: v[0], y1: v[1], x2: v[2], y2: v[3], x: v[4], y: v[5], isAbsolute: isAbsolute)
      case .S, .s:
        C(path: path, x1: nil, y1: nil, x2: v[0], y2: v[1], x: v[2], y: v[3], isAbsolute: isAbsolute)
      case .Q, .q:
        Q(path: path, x1: v[0], y1: v[1], x: v[2], y: v[3], isAbsolute: isAbsolute)
      case .T, .t:
        Q(path: path, x1: nil, y1: nil, x: v[0], y: v[1], isAbsolute: isAbsolute)
      case .A, .a:
        A(
          path: path, rx: v[0], ry: v[1], angle: v[2], largeArc: v[3] != 0, sweep: v[4] != 0, x: v[5], y: v[6],
          isAbsolute: isAbsolute)
      case .M, .m:
        break
      }
    }
    // The control point that a smooth curve reflects is the one of the curve of its kind just before it.
    switch command.type {
    case .C, .c, .S, .s:
      quadrPoint = nil
    case .Q, .q, .T, .t:
      cubicPoint = nil
    default:
      cubicPoint = nil
      quadrPoint = nil
    }
  }

  // moveto
  @inline(__always)
  private func M(path: CGMutablePath?, isMoved: Bool, x: Double, y: Double, isAbsolute: Bool) {
    guard isMoved else {
      let cur = isAbsolute ? .zero : (path?.currentPoint ?? .zero)
      let path = createPathIfNeeded()
      let endPoint = CGPoint(x: cur.x + x, y: cur.y + y)
      path.move(to: endPoint)
      return
    }
    L(path: path!, x: x, y: y, isAbsolute: isAbsolute)
  }

  // closepath
  @inline(__always)
  private func Z(path: CGMutablePath) {
    path.closeSubpath()
    let cur = path.currentPoint
    M(path: path, isMoved: false, x: cur.x, y: cur.y, isAbsolute: true)
  }

  // lineto
  @inline(__always)
  private func L(path: CGMutablePath, x: Double?, y: Double?, isAbsolute: Bool) {
    let dp = isAbsolute ? path.currentPoint : .zero
    let cur = isAbsolute ? .zero : path.currentPoint
    let x = x ?? dp.x
    let y = y ?? dp.y
    let endPoint = CGPoint(x: cur.x + x, y: cur.y + y)
    path.addLine(to: endPoint)
  }

  // cubic Bézier curve
  @inline(__always)
  private func C(path: CGMutablePath, x1: Double?, y1: Double?, x2: Double, y2: Double, x: Double, y: Double, isAbsolute: Bool) {
    let cur = isAbsolute ? .zero : path.currentPoint
    let endPoint = CGPoint(x: cur.x + x, y: cur.y + y)
    let controlPoint1: CGPoint
    if let x1 = x1, let y1 = y1 {
      controlPoint1 = CGPoint(x: cur.x + x1, y: cur.y + y1)
    } else {
      controlPoint1 = SVGPathContext.takeMirrorIfNeeded(p1: path.currentPoint, p2: cubicPoint)
    }
    let controlPoint2 = CGPoint(x: cur.x + x2, y: cur.y + y2)
    path.addCurve(to: endPoint, control1: controlPoint1, control2: controlPoint2)
    cubicPoint = controlPoint2
  }

  // quadratic Bézier curve
  @inline(__always)
  private func Q(path: CGMutablePath, x1: Double?, y1: Double?, x: Double, y: Double, isAbsolute: Bool) {
    let cur = isAbsolute ? .zero : path.currentPoint
    let endPoint = CGPoint(x: cur.x + x, y: cur.y + y)
    let controlPoint: CGPoint
    if let x1 = x1, let y1 = y1 {
      controlPoint = CGPoint(x: cur.x + x1, y: cur.y + y1)
    } else {
      controlPoint = SVGPathContext.takeMirrorIfNeeded(p1: path.currentPoint, p2: quadrPoint)
    }
    path.addQuadCurve(to: endPoint, control: controlPoint)
    quadrPoint = controlPoint
  }

  // elliptical arc curve
  @inline(__always)
  private func A(path: CGMutablePath, rx _rx: Double, ry _ry: Double, angle: Double, largeArc: Bool, sweep: Bool, x: Double, y: Double, isAbsolute: Bool) {
    if _rx == 0 || _ry == 0 {
      L(path: path, x: x, y: y, isAbsolute: isAbsolute)
      return
    }
    let angle = angle * .pi / 180

    let cur = path.currentPoint
    let x1 = Double(cur.x)
    let y1 = Double(cur.y)

    let dp = isAbsolute ? .zero : path.currentPoint
    let x2 = x + Double(dp.x)
    let y2 = y + Double(dp.y)

    let x1_ = cos(angle) * (x1 - x2) / 2 + sin(angle) * (y1 - y2) / 2
    let y1_ = -sin(angle) * (x1 - x2) / 2 + cos(angle) * (y1 - y2) / 2

    let lambda = (x1_ * x1_) / (_rx * _rx) + (y1_ * y1_) / (_ry * _ry)
    let rx: Double
    let ry: Double
    if lambda > 1 {
      rx = sqrt(lambda) * _rx
      ry = sqrt(lambda) * _ry
    } else {
      rx = _rx
      ry = _ry
    }

    let coef = xsqrt(
      (rx * rx * ry * ry - rx * rx * y1_ * y1_ - ry * ry * x1_ * x1_)
        / (rx * rx * y1_ * y1_ + ry * ry * x1_ * x1_))
    let sign: Double = (sweep != largeArc) ? 1 : -1
    let cx_ = sign * coef * rx * y1_ / ry
    let cy_ = -sign * coef * ry * x1_ / rx
    let cx = cos(angle) * cx_ - sin(angle) * cy_ + (x1 + x2) / 2
    let cy = sin(angle) * cx_ + cos(angle) * cy_ + (y1 + y2) / 2

    let t1 = calcAngle(ux: 1, uy: 0, vx: (x1_ - cx_) / rx, vy: (y1_ - cy_) / ry)
    let dt = calcAngle(ux: (x1_ - cx_) / rx, uy: (y1_ - cy_) / ry, vx: (-x1_ - cx_) / rx, vy: (-y1_ - cy_) / ry, sweep: sweep)

    path.addEllipticalArc(
      center: CGPoint(x: cx, y: cy), radii: .init(width: 2 * rx, height: 2 * ry),
      startAngle: t1, endAngle: t1 + dt, rotation: angle)
  }

  @inline(__always)
  func calcAngle(ux: Double, uy: Double, vx: Double, vy: Double, sweep: Bool? = nil) -> Double {
    let sign = copysign(1, ux * vy - uy * vx)
    let value = (ux * vx + uy * vy) / (sqrt(ux * ux + uy * uy) * sqrt(vx * vx + vy * vy))
    let angle: Double
    if value < -1 {
      angle = sign * .pi
    } else if value > 1 {
      angle = 0
    } else {
      angle = sign * acos(value)
    }
    guard let sweep = sweep else {
      return angle
    }
    let delta: CGFloat
    if angle > 0, !sweep {
      delta = -.pi * 2
    } else if angle < 0, sweep {
      delta = .pi * 2
    } else {
      delta = 0.0
    }
    return angle.truncatingRemainder(dividingBy: .pi * 2) + delta
  }

  @inline(__always)
  func xsqrt(_ x: Double) -> Double {
    x > 0 ? sqrt(x) : 0
  }
}
