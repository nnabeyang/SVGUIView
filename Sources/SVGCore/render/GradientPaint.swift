import CoreGraphics
import Foundation

/// A gradient with its lengths resolved, which paints the inside of a path.
package enum GradientPaint: Sendable {
  case linear(LinearGradientPaint)
  case radial(RadialGradientPaint)

  /// The units of the coordinates of the gradient.
  package var units: SVGUnitType {
    switch self {
    case .linear(let gradient): gradient.units
    case .radial(let gradient): gradient.units
    }
  }
}

package struct LinearGradientPaint: Sendable {
  package let units: SVGUnitType
  /// The transform from the coordinates of the gradient to the coordinates of its units.
  package let transform: CGAffineTransform
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
  /// The transform from the coordinates of the gradient to the coordinates of its units.
  package let transform: CGAffineTransform
  package let cx: CGFloat
  package let cy: CGFloat
  package let r: CGFloat
  /// The center of the focal circle, where the gradient starts.
  package let fx: CGFloat
  package let fy: CGFloat
  /// The radius of the focal circle.
  package let fr: CGFloat
  package let spreadMethod: SpreadMethod
  /// The colors of the stops that have one, and the offsets of all the stops.
  package let colors: [CGColor]
  package let locations: [CGFloat]
}
