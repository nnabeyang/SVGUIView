import CoreGraphics
import Foundation

extension CGPath {
  /// The path with each subpath without length, which Core Graphics caps with a square turned by 45 degrees, made
  /// a short line along the x-axis, whose square caps are the square along the x-axis that SVG 2 specifies.
  package var squareCapped: CGPath {
    let path = self
    // The subpaths, with their start, whether they have a line or a curve, and whether a point of them isn't the
    // start. A subpath of a moveto alone has no caps.
    var subpaths = [(elements: [(CGPathElementType, [CGPoint])], start: CGPoint, hasSegment: Bool, hasLength: Bool)]()
    var hasEmptySubpath = false
    path.applyWithBlock { pointer in
      let element = pointer.pointee
      let count =
        switch element.type {
        case .moveToPoint, .addLineToPoint: 1
        case .addQuadCurveToPoint: 2
        case .addCurveToPoint: 3
        case .closeSubpath: 0
        @unknown default: 0
        }
      let points = (0..<count).map { element.points[$0] }
      if element.type == .moveToPoint || subpaths.isEmpty {
        if let last = subpaths.last, last.hasSegment, !last.hasLength { hasEmptySubpath = true }
        subpaths.append(([], points.first ?? .zero, false, false))
      }
      subpaths[subpaths.count - 1].elements.append((element.type, points))
      if element.type != .moveToPoint, element.type != .closeSubpath {
        subpaths[subpaths.count - 1].hasSegment = true
      }
      if points.contains(where: { $0 != subpaths[subpaths.count - 1].start }) {
        subpaths[subpaths.count - 1].hasLength = true
      }
    }
    if let last = subpaths.last, last.hasSegment, !last.hasLength { hasEmptySubpath = true }
    guard hasEmptySubpath else { return path }
    let result = CGMutablePath()
    // A line too short to show, which only gives the caps their direction.
    let half: CGFloat = 1e-4
    for subpath in subpaths {
      guard subpath.hasLength || !subpath.hasSegment else {
        result.move(to: CGPoint(x: subpath.start.x - half, y: subpath.start.y))
        result.addLine(to: CGPoint(x: subpath.start.x + half, y: subpath.start.y))
        continue
      }
      for (type, points) in subpath.elements {
        switch type {
        case .moveToPoint: result.move(to: points[0])
        case .addLineToPoint: result.addLine(to: points[0])
        case .addQuadCurveToPoint: result.addQuadCurve(to: points[1], control: points[0])
        case .addCurveToPoint: result.addCurve(to: points[2], control1: points[0], control2: points[1])
        case .closeSubpath: result.closeSubpath()
        @unknown default: break
        }
      }
    }
    return result
  }
}
