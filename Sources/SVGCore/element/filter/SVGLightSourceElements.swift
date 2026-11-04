import CoreGraphics
import Foundation

/// A light source of `feDiffuseLighting` or `feSpecularLighting`: `feDistantLight`, `fePointLight` or `feSpotLight`.
protocol SVGLightSourceElement: SVGElement {}

/// The first light source of the children of a lighting primitive, which is the one that it uses. The other
/// children, such as `title` and elements that aren't light sources, are left out.
func firstLightSource(in children: [any SVGElement]) -> (any SVGLightSourceElement)? {
  children.lazy.compactMap { $0 as? any SVGLightSourceElement }.first
}

final class SVGFeDistantLightElement: SVGLightSourceElement {
  static var type: SVGElementName {
    .feDistantLight
  }

  var type: SVGElementName {
    .feDistantLight
  }

  let base: SVGBaseElement
  /// The direction of the light in the plane of the user space, clockwise from the x-axis, in degrees, which is 0
  /// where the attribute is missing or isn't a number.
  let azimuth: Double
  /// The angle of the light above the plane, in degrees, which is 0 where the attribute is missing or isn't a
  /// number.
  let elevation: Double

  init(base: SVGBaseElement, contents _: [any SVGElement]) {
    self.base = base
    let attributes = base.attributes
    func number(_ name: String) -> Double? {
      attributes[name].flatMap { Double($0.trimmingCharacters(in: .whitespaces)) }.flatMap { $0.isFinite ? $0 : nil }
    }
    azimuth = number("azimuth") ?? 0
    elevation = number("elevation") ?? 0
  }
}

extension SVGFeDistantLightElement: Encodable {
  func encode(to _: any Encoder) throws {
    fatalError()
  }
}

/// A `fePointLight`, a light at a position.
final class SVGFePointLightElement: SVGLightSourceElement {
  static var type: SVGElementName {
    .fePointLight
  }

  var type: SVGElementName {
    .fePointLight
  }

  let base: SVGBaseElement
  /// The position of the light in the coordinates of the filter primitives, which are 0 where the attributes are
  /// missing or aren't lengths.
  let x: SVGLength
  let y: SVGLength
  let z: SVGLength

  init(base: SVGBaseElement, contents _: [any SVGElement]) {
    self.base = base
    let attributes = base.attributes
    x = SVGLength(attributes["x"]) ?? .number(0)
    y = SVGLength(attributes["y"]) ?? .number(0)
    z = SVGLength(attributes["z"]) ?? .number(0)
  }
}

extension SVGFePointLightElement: Encodable {
  func encode(to _: any Encoder) throws {
    fatalError()
  }
}

/// A `feSpotLight`, a light at a position that points at another.
final class SVGFeSpotLightElement: SVGLightSourceElement {
  static var type: SVGElementName {
    .feSpotLight
  }

  var type: SVGElementName {
    .feSpotLight
  }

  let base: SVGBaseElement
  /// The position of the light in the coordinates of the filter primitives, which are 0 where the attributes are
  /// missing or aren't lengths.
  let x: SVGLength
  let y: SVGLength
  let z: SVGLength
  /// The position that the light points at, which are 0 where the attributes are missing or aren't lengths.
  let pointsAtX: SVGLength
  let pointsAtY: SVGLength
  let pointsAtZ: SVGLength
  /// The exponent of the focus of the light, which is 1 where the attribute is missing, isn't a number or isn't
  /// positive, as in resvg.
  let specularExponent: Double
  /// The angle between the axis of the light and its cone, in degrees, or `nil` for no cone where the attribute is
  /// missing or isn't a number.
  let limitingConeAngle: Double?

  init(base: SVGBaseElement, contents _: [any SVGElement]) {
    self.base = base
    let attributes = base.attributes
    x = SVGLength(attributes["x"]) ?? .number(0)
    y = SVGLength(attributes["y"]) ?? .number(0)
    z = SVGLength(attributes["z"]) ?? .number(0)
    pointsAtX = SVGLength(attributes["pointsAtX"]) ?? .number(0)
    pointsAtY = SVGLength(attributes["pointsAtY"]) ?? .number(0)
    pointsAtZ = SVGLength(attributes["pointsAtZ"]) ?? .number(0)
    func number(_ name: String) -> Double? {
      attributes[name].flatMap { Double($0.trimmingCharacters(in: .whitespaces)) }.flatMap { $0.isFinite ? $0 : nil }
    }
    specularExponent = number("specularExponent").flatMap { $0 > 0 ? $0 : nil } ?? 1
    limitingConeAngle = number("limitingConeAngle")
  }
}

extension SVGFeSpotLightElement: Encodable {
  func encode(to _: any Encoder) throws {
    fatalError()
  }
}
