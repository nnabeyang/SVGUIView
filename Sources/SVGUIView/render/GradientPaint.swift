import CoreGraphics
import Foundation

/// A gradient with its lengths resolved, which paints the inside of a path.
enum GradientPaint: Sendable {
  case linear(LinearGradientPaint)
  case radial(RadialGradientPaint)
}

struct LinearGradientPaint: Sendable {
  let units: SVGUnitType
  let x1: CGFloat
  let y1: CGFloat
  let x2: CGFloat
  let y2: CGFloat
  let spreadMethod: SpreadMethod
  /// The colors of the stops that have one, and the offsets of all the stops.
  let colors: [CGColor]
  let locations: [CGFloat]
}

struct RadialGradientPaint: Sendable {
  let units: SVGUnitType
  let cx: CGFloat
  let cy: CGFloat
  let r: CGFloat
  /// The colors of the stops that have one, and the offsets of all the stops.
  let colors: [CGColor]
  let locations: [CGFloat]
}
