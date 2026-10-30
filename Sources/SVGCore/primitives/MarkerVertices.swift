import CoreGraphics
import Foundation

/// A vertex of a path where a marker is drawn, with the direction of the path there.
struct MarkerVertex: Equatable {
  let point: CGPoint
  /// The direction of the path at the vertex, in degrees clockwise from the x-axis, which `orient="auto"` rotates
  /// a marker by.
  let angle: Double
}

/// The vertices of path data, where markers are drawn, and the directions of the path there, as SVG 2 specifies.
///
/// A vertex is the start of each subpath and the end of each segment. `marker-start` is drawn at the first vertex,
/// `marker-end` at the last and `marker-mid` at the others, including the starts and ends of subpaths. The direction
/// at the start of an open subpath is the one out of it, at its end the one into it, and at the other vertices, and
/// at both ends of a closed subpath, the bisector of the directions into and out of the vertex.
enum MarkerVertices {
  /// A segment of a subpath, with the directions at its start and its end as vectors, which are `nil` for a segment
  /// of zero length until they're taken from the segments around it.
  private struct Segment {
    let end: CGPoint
    var start: CGVector?
    var finish: CGVector?
  }

  private struct Subpath {
    let start: CGPoint
    var segments = [Segment]()
    var isClosed = false
    /// Whether the subpath starts after a closepath without a moveto, at the point where the subpath before it
    /// ends, so that the vertex is already there.
    var continues = false
  }

  /// The vertices of path data, with the points and the directions transformed.
  static func vertices(of data: PathData, transform: CGAffineTransform = .identity) -> [MarkerVertex] {
    let subpaths = subpaths(of: data.absolute())
    var vertices = [MarkerVertex]()
    for subpath in subpaths {
      let segments = subpath.segments
      // The directions into and out of the start of a closed subpath come from its closing segment and its first one.
      let closingAngle: Double? =
        if subpath.isClosed, let last = segments.last, let first = segments.first {
          bisector(last.finish, first.start)
        } else {
          nil
        }
      if !subpath.continues {
        vertices.append(
          MarkerVertex(point: subpath.start, angle: closingAngle ?? angle(of: segments.first?.start)))
      }
      for (index, segment) in segments.enumerated() {
        let angle: Double =
          if index + 1 < segments.count {
            bisector(segment.finish, segments[index + 1].start)
          } else {
            closingAngle ?? Self.angle(of: segment.finish)
          }
        vertices.append(MarkerVertex(point: segment.end, angle: angle))
      }
    }
    guard transform != .identity else { return vertices }
    return vertices.map { vertex in
      let radians = vertex.angle * .pi / 180
      let direction = CGPoint(x: cos(radians), y: sin(radians)).applying(
        CGAffineTransform(a: transform.a, b: transform.b, c: transform.c, d: transform.d, tx: 0, ty: 0))
      return MarkerVertex(
        point: vertex.point.applying(transform), angle: atan2(direction.y, direction.x) * 180 / .pi)
    }
  }

  /// The subpaths of absolute path data, with the directions of their segments of zero length taken from the
  /// segments around them.
  private static func subpaths(of data: PathData) -> [Subpath] {
    var subpaths = [Subpath]()
    var current = CGPoint.zero
    // The second control point of the curve before, which a smooth curve reflects.
    var cubicControl: CGPoint?
    var quadraticControl: CGPoint?
    var closed = false
    for command in data.commands {
      let v = command.values
      if command.type == .M {
        current = CGPoint(x: v[0], y: v[1])
        subpaths.append(Subpath(start: current))
        cubicControl = nil
        quadraticControl = nil
        closed = false
        continue
      }
      guard !subpaths.isEmpty else { continue }
      // A closepath right after another closes nothing more.
      if closed, command.type == .Z { continue }
      if closed {
        // A command after a closepath starts a subpath at the same point.
        subpaths.append(Subpath(start: current, continues: true))
        closed = false
      }
      let from = current
      var segment: Segment
      switch command.type {
      case .L, .H, .V:
        let to =
          switch command.type {
          case .H: CGPoint(x: v[0], y: from.y)
          case .V: CGPoint(x: from.x, y: v[0])
          default: CGPoint(x: v[0], y: v[1])
          }
        segment = line(from: from, to: to)
      case .C, .S:
        let control1 =
          command.type == .C
          ? CGPoint(x: v[0], y: v[1])
          : cubicControl.map { CGPoint(x: 2 * from.x - $0.x, y: 2 * from.y - $0.y) } ?? from
        let rest = command.type == .C ? Array(v[2...]) : v
        let control2 = CGPoint(x: rest[0], y: rest[1])
        let to = CGPoint(x: rest[2], y: rest[3])
        segment = curve(from: from, controls: [control1, control2], to: to)
        cubicControl = control2
      case .Q, .T:
        let control =
          command.type == .Q
          ? CGPoint(x: v[0], y: v[1])
          : quadraticControl.map { CGPoint(x: 2 * from.x - $0.x, y: 2 * from.y - $0.y) } ?? from
        let to = command.type == .Q ? CGPoint(x: v[2], y: v[3]) : CGPoint(x: v[0], y: v[1])
        segment = curve(from: from, controls: [control], to: to)
        quadraticControl = control
      case .A:
        segment = arc(
          from: from, radii: CGSize(width: v[0], height: v[1]), rotation: v[2], largeArc: v[3] != 0,
          sweep: v[4] != 0, to: CGPoint(x: v[5], y: v[6]))
      case .Z:
        segment = line(from: from, to: subpaths[subpaths.count - 1].start)
        subpaths[subpaths.count - 1].isClosed = true
        closed = true
      default:
        continue
      }
      switch command.type {
      case .C, .S: quadraticControl = nil
      case .Q, .T: cubicControl = nil
      default:
        cubicControl = nil
        quadraticControl = nil
      }
      subpaths[subpaths.count - 1].segments.append(segment)
      current = segment.end
    }
    return subpaths.map(fillingDirections)
  }

  /// The subpath with each segment of zero length taking the direction at the end of the segment before it, or,
  /// at the start of the subpath, the direction at the start of the first segment after it that has one.
  private static func fillingDirections(_ subpath: Subpath) -> Subpath {
    var subpath = subpath
    var previous: CGVector?
    for index in subpath.segments.indices {
      if subpath.segments[index].start == nil, let previous {
        subpath.segments[index].start = previous
        subpath.segments[index].finish = previous
      }
      previous = subpath.segments[index].finish ?? previous
    }
    if let first = subpath.segments.lazy.compactMap(\.start).first {
      for index in subpath.segments.indices where subpath.segments[index].start == nil {
        subpath.segments[index].start = first
        subpath.segments[index].finish = first
      }
    }
    return subpath
  }

  private static func vector(from: CGPoint, to: CGPoint) -> CGVector? {
    from == to ? nil : CGVector(dx: to.x - from.x, dy: to.y - from.y)
  }

  private static func line(from: CGPoint, to: CGPoint) -> Segment {
    let direction = vector(from: from, to: to)
    return Segment(end: to, start: direction, finish: direction)
  }

  /// A Bézier curve, whose directions at its ends point to and from the nearest of its points that differ from
  /// the ends.
  private static func curve(from: CGPoint, controls: [CGPoint], to: CGPoint) -> Segment {
    let points = [from] + controls + [to]
    let start = points.dropFirst().lazy.compactMap { vector(from: from, to: $0) }.first
    let finish = points.dropLast().reversed().lazy.compactMap { vector(from: $0, to: to) }.first
    return Segment(end: to, start: start, finish: finish)
  }

  /// An elliptical arc, with its directions from the parameterization by its center, as the implementation notes
  /// of SVG describe. An arc with a radius of zero is a line.
  private static func arc(
    from: CGPoint, radii: CGSize, rotation: Double, largeArc: Bool, sweep: Bool, to: CGPoint
  ) -> Segment {
    var rx = abs(radii.width)
    var ry = abs(radii.height)
    guard rx > 0, ry > 0, from != to else { return line(from: from, to: to) }
    let phi = rotation * .pi / 180
    let dx = (from.x - to.x) / 2
    let dy = (from.y - to.y) / 2
    let x1 = cos(phi) * dx + sin(phi) * dy
    let y1 = -sin(phi) * dx + cos(phi) * dy
    let lambda = (x1 * x1) / (rx * rx) + (y1 * y1) / (ry * ry)
    if lambda > 1 {
      rx *= sqrt(lambda)
      ry *= sqrt(lambda)
    }
    let numerator = rx * rx * ry * ry - rx * rx * y1 * y1 - ry * ry * x1 * x1
    let denominator = rx * rx * y1 * y1 + ry * ry * x1 * x1
    var coefficient = sqrt(max(0, numerator / denominator))
    if largeArc == sweep { coefficient = -coefficient }
    let cx1 = coefficient * rx * y1 / ry
    let cy1 = -coefficient * ry * x1 / rx
    let startAngle = atan2((y1 - cy1) / ry, (x1 - cx1) / rx)
    var delta = atan2((-y1 - cy1) / ry, (-x1 - cx1) / rx) - startAngle
    if sweep, delta < 0 { delta += 2 * .pi }
    if !sweep, delta > 0 { delta -= 2 * .pi }
    let sign: CGFloat = delta >= 0 ? 1 : -1
    func tangent(at angle: Double) -> CGVector {
      let x = -rx * sin(angle) * sign
      let y = ry * cos(angle) * sign
      return CGVector(dx: cos(phi) * x - sin(phi) * y, dy: sin(phi) * x + cos(phi) * y)
    }
    return Segment(end: to, start: tangent(at: startAngle), finish: tangent(at: startAngle + delta))
  }

  /// The angle of a direction in degrees, or 0 without one.
  private static func angle(of vector: CGVector?) -> Double {
    guard let vector else { return 0 }
    return atan2(vector.dy, vector.dx) * 180 / .pi
  }

  /// The angle halfway between the directions into and out of a vertex.
  private static func bisector(_ incoming: CGVector?, _ outgoing: CGVector?) -> Double {
    guard let incoming else { return angle(of: outgoing) }
    guard let outgoing else { return angle(of: incoming) }
    let a = angle(of: incoming)
    var b = angle(of: outgoing)
    if b - a > 180 { b -= 360 }
    if a - b > 180 { b += 360 }
    return (a + b) / 2
  }
}
