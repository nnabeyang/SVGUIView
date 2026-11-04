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

/// A `fePointLight`, which is a light source that the lighting primitives don't draw yet.
final class SVGFePointLightElement: SVGLightSourceElement {
  static var type: SVGElementName {
    .fePointLight
  }

  var type: SVGElementName {
    .fePointLight
  }

  let base: SVGBaseElement

  init(base: SVGBaseElement, contents _: [any SVGElement]) {
    self.base = base
  }
}

extension SVGFePointLightElement: Encodable {
  func encode(to _: any Encoder) throws {
    fatalError()
  }
}

/// A `feSpotLight`, which is a light source that the lighting primitives don't draw yet.
final class SVGFeSpotLightElement: SVGLightSourceElement {
  static var type: SVGElementName {
    .feSpotLight
  }

  var type: SVGElementName {
    .feSpotLight
  }

  let base: SVGBaseElement

  init(base: SVGBaseElement, contents _: [any SVGElement]) {
    self.base = base
  }
}

extension SVGFeSpotLightElement: Encodable {
  func encode(to _: any Encoder) throws {
    fatalError()
  }
}
