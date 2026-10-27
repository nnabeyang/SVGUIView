import CoreGraphics
import Foundation

/// Path data flattened into lines, which finds the points along the path by their distances from its start, as
/// `<animateMotion>` moves an element along a path.
///
/// A moveto in the middle of the path jumps to its point without adding to the distance.
struct PathMeasure: Sendable {
  /// A line of the flattened path.
  private struct Segment: Sendable {
    let start: CGPoint
    let end: CGPoint
    /// The distance along the path at the end of the line.
    let distance: Double
  }

  private var segments = [Segment]()
  /// The point that the path starts at, or `nil` for path data without a moveto.
  private(set) var start: CGPoint?
  /// The distances along the path at the ends of its commands, which are the vertices that the linear and discrete
  /// calculation modes of `<animateMotion>` go through. The first is 0, at the first moveto.
  private(set) var vertexDistances = [Double]()

  /// The length of the path.
  var length: Double { segments.last?.distance ?? 0 }

  /// The number of lines that each curve is divided into.
  private static let curveSteps = 64

  init(_ data: PathData) {
    let context = SVGPathContext()
    var count = 0
    var current = CGPoint.zero
    var subpathStart = CGPoint.zero
    for command in data.commands {
      context.apply(command)
      // Commands before the first moveto draw nothing, and have no vertex.
      guard let path = context.path else { continue }
      // The elements that the command added, after the ones of the commands before it.
      var elements = [(type: CGPathElementType, points: [CGPoint])]()
      var index = 0
      path.applyWithBlock { element in
        defer { index += 1 }
        guard index >= count else { return }
        let element = element.pointee
        let pointCount =
          switch element.type {
          case .moveToPoint, .addLineToPoint: 1
          case .addQuadCurveToPoint: 2
          case .addCurveToPoint: 3
          default: 0
          }
        elements.append((element.type, (0..<pointCount).map { element.points[$0] }))
      }
      for (type, points) in elements {
        switch type {
        case .moveToPoint:
          current = points[0]
          subpathStart = current
          if start == nil { start = current }
        case .addLineToPoint:
          add(from: current, to: points[0])
          current = points[0]
        case .addQuadCurveToPoint:
          let (from, control, end) = (current, points[0], points[1])
          addCurve(from: current) { t in
            let u = 1 - t
            return CGPoint(
              x: u * u * from.x + 2 * u * t * control.x + t * t * end.x,
              y: u * u * from.y + 2 * u * t * control.y + t * t * end.y)
          }
          current = end
        case .addCurveToPoint:
          let (from, control1, control2, end) = (current, points[0], points[1], points[2])
          addCurve(from: current) { t in
            let u = 1 - t
            let a = u * u * u
            let b = 3 * u * u * t
            let c = 3 * u * t * t
            let d = t * t * t
            return CGPoint(
              x: a * from.x + b * control1.x + c * control2.x + d * end.x,
              y: a * from.y + b * control1.y + c * control2.y + d * end.y)
          }
          current = end
        case .closeSubpath:
          add(from: current, to: subpathStart)
          current = subpathStart
        @unknown default:
          break
        }
      }
      count = index
      vertexDistances.append(length)
    }
  }

  private mutating func add(from start: CGPoint, to end: CGPoint) {
    let distance = length + hypot(end.x - start.x, end.y - start.y)
    segments.append(Segment(start: start, end: end, distance: distance))
  }

  private mutating func addCurve(from start: CGPoint, point: (Double) -> CGPoint) {
    var previous = start
    for step in 1...Self.curveSteps {
      let next = point(Double(step) / Double(Self.curveSteps))
      add(from: previous, to: next)
      previous = next
    }
  }

  /// The point at a distance along the path, which is clamped to the path, and the angle in degrees of the
  /// direction that the path goes in there, or `nil` for path data without a moveto.
  func point(atDistance distance: Double) -> (point: CGPoint, angle: Double)? {
    guard let start else { return nil }
    let distance = min(max(distance, 0), length)
    var previous = 0.0
    for segment in segments {
      defer { previous = segment.distance }
      let length = segment.distance - previous
      guard length > 0, segment.distance >= distance else { continue }
      let progress = (distance - previous) / length
      let point = CGPoint(
        x: segment.start.x + (segment.end.x - segment.start.x) * progress,
        y: segment.start.y + (segment.end.y - segment.start.y) * progress)
      let angle = atan2(segment.end.y - segment.start.y, segment.end.x - segment.start.x) * 180 / .pi
      return (point, angle)
    }
    return (start, 0)
  }
}
