import CoreGraphics
import Foundation

/// A gradient with its lengths resolved, which paints the inside of a path.
package enum GradientPaint: Sendable {
  case linear(LinearGradientPaint)
  case radial(RadialGradientPaint)
}

package struct LinearGradientPaint: Sendable {
  package let units: SVGUnitType
  package let x1: CGFloat
  package let y1: CGFloat
  package let x2: CGFloat
  package let y2: CGFloat
  package let spreadMethod: SpreadMethod
  /// The colors of the stops that have one, and the offsets of all the stops.
  package let colors: [CGColor]
  package let locations: [CGFloat]
}

package struct RadialGradientPaint: Sendable {
  package let units: SVGUnitType
  package let cx: CGFloat
  package let cy: CGFloat
  package let r: CGFloat
  /// The colors of the stops that have one, and the offsets of all the stops.
  package let colors: [CGColor]
  package let locations: [CGFloat]
}
