import CoreGraphics
import Foundation

/// A `<marker>`: graphics that `marker-start`, `marker-mid` and `marker-end` draw at vertices of shapes. It's
/// rendered only where a shape references it.
final class SVGMarkerElement: SVGElement {
  /// What scales the coordinates of a marker: the stroke width of the shape, or nothing.
  enum Units: String {
    case strokeWidth
    case userSpaceOnUse
  }

  /// How a marker is rotated at a vertex.
  enum Orientation: Equatable {
    /// By the direction of the path.
    case auto
    /// By the direction of the path, and at the start, by the opposite direction.
    case autoStartReverse
    /// By an angle in degrees.
    case angle(Double)

    init?(_ text: String?) {
      guard let text = text?.trimmingCharacters(in: .whitespaces), !text.isEmpty else { return nil }
      switch text {
      case "auto":
        self = .auto
      case "auto-start-reverse":
        self = .autoStartReverse
      default:
        let units: [(String, Double)] = [("deg", 1), ("grad", 0.9), ("rad", 180 / .pi), ("turn", 360)]
        for (unit, degrees) in units where text.hasSuffix(unit) {
          guard let value = Double(text.dropLast(unit.count)) else { return nil }
          self = .angle(value * degrees)
          return
        }
        guard let value = Double(text) else { return nil }
        self = .angle(value)
      }
    }
  }

  static var type: SVGElementName {
    .marker
  }

  var type: SVGElementName {
    .marker
  }

  let base: SVGBaseElement
  let children: [any SVGElement]
  let id: String?
  let units: Units
  let width: SVGLength?
  let height: SVGLength?
  let refX: SVGLength?
  let refY: SVGLength?
  let orientation: Orientation
  let viewBox: SVGElementRect?
  let preserveAspectRatio: PreserveAspectRatio?
  let overflow: SVGOverflow?

  init(base: SVGBaseElement, contents children: [any SVGElement]) {
    self.base = base
    self.children = children
    let attributes = base.attributes
    id = attributes["id"]?.trimmingCharacters(in: .whitespaces)
    units = Units(rawValue: attributes["markerUnits", default: ""].trimmingCharacters(in: .whitespaces)) ?? .strokeWidth
    width = SVGLength(attributes["markerWidth"])
    height = SVGLength(attributes["markerHeight"])
    refX = SVGLength(attributes["refX"])
    refY = SVGLength(attributes["refY"])
    orientation = Orientation(attributes["orient"]) ?? .angle(0)
    viewBox = SVGPatternElement.parseViewBox(attributes["viewBox"])
    preserveAspectRatio = PreserveAspectRatio(description: attributes["preserveAspectRatio", default: ""])
    overflow = base.style.overflow
  }

  /// The angle of the marker in degrees at a vertex of a path.
  func angle(at vertex: MarkerVertex, isStart: Bool) -> Double {
    switch orientation {
    case .auto: vertex.angle
    case .autoStartReverse: isStart ? vertex.angle + 180 : vertex.angle
    case .angle(let angle): angle
    }
  }
}

extension SVGMarkerElement: Encodable {
  func encode(to _: any Encoder) throws {
    fatalError()
  }
}
