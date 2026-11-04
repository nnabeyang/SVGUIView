import CoreGraphics
import Foundation

/// The number of an attribute of a lighting primitive, or `nil` where it's missing or isn't a number.
private func number(_ name: String, of attributes: [String: String]) -> Double? {
  attributes[name].flatMap { Double($0.trimmingCharacters(in: .whitespaces)) }.flatMap { $0.isFinite ? $0 : nil }
}

final class SVGFeDiffuseLightingElement: SVGElement, SVGFilterPrimitiveElement {
  static var type: SVGElementName {
    .feDiffuseLighting
  }

  var type: SVGElementName {
    .feDiffuseLighting
  }

  let base: SVGBaseElement
  let x: SVGLength?
  let y: SVGLength?
  let width: SVGLength?
  let height: SVGLength?

  let result: String?

  let input: SVGFilterInput?
  let children: [any SVGElement]
  /// The height of the surface where the alpha of the input is 1, which is 1 where the attribute is missing or
  /// isn't a number.
  let surfaceScale: Double
  /// The constant of the diffuse reflection, which is 1 where the attribute is missing or isn't a number.
  let diffuseConstant: Double
  let lightingColor: SVGColor
  /// The light source, the first of the children, or `nil` if there's none.
  let lightSource: (any SVGLightSourceElement)?

  init(base: SVGBaseElement, contents children: [any SVGElement]) {
    self.base = base
    self.children = children
    let attributes = base.attributes
    x = SVGLength(attributes["x"])
    y = SVGLength(attributes["y"])
    width = SVGLength(attributes["width"])
    height = SVGLength(attributes["height"])

    result = attributes["result"]

    input = SVGFilterInput(rawValue: attributes["in", default: ""])
    surfaceScale = number("surfaceScale", of: attributes) ?? 1
    diffuseConstant = number("diffuseConstant", of: attributes) ?? 1
    lightingColor = base.style.resolved(base.style.lightingColor)
    lightSource = firstLightSource(in: children)
  }
}

extension SVGFeDiffuseLightingElement: Encodable {
  func encode(to _: any Encoder) throws {
    fatalError()
  }
}

final class SVGFeSpecularLightingElement: SVGElement, SVGFilterPrimitiveElement {
  static var type: SVGElementName {
    .feSpecularLighting
  }

  var type: SVGElementName {
    .feSpecularLighting
  }

  let base: SVGBaseElement
  let x: SVGLength?
  let y: SVGLength?
  let width: SVGLength?
  let height: SVGLength?

  let result: String?

  let input: SVGFilterInput?
  let children: [any SVGElement]
  /// The height of the surface where the alpha of the input is 1, which is 1 where the attribute is missing or
  /// isn't a number.
  let surfaceScale: Double
  /// The constant of the specular reflection, which is 1 where the attribute is missing or isn't a number.
  let specularConstant: Double
  /// The exponent of the specular reflection, which is 1 where the attribute is missing or isn't a number.
  let specularExponent: Double
  let lightingColor: SVGColor
  /// The light source, the first of the children, or `nil` if there's none.
  let lightSource: (any SVGLightSourceElement)?

  init(base: SVGBaseElement, contents children: [any SVGElement]) {
    self.base = base
    self.children = children
    let attributes = base.attributes
    x = SVGLength(attributes["x"])
    y = SVGLength(attributes["y"])
    width = SVGLength(attributes["width"])
    height = SVGLength(attributes["height"])

    result = attributes["result"]

    input = SVGFilterInput(rawValue: attributes["in", default: ""])
    surfaceScale = number("surfaceScale", of: attributes) ?? 1
    specularConstant = number("specularConstant", of: attributes) ?? 1
    specularExponent = number("specularExponent", of: attributes) ?? 1
    lightingColor = base.style.resolved(base.style.lightingColor)
    lightSource = firstLightSource(in: children)
  }
}

extension SVGFeSpecularLightingElement: Encodable {
  func encode(to _: any Encoder) throws {
    fatalError()
  }
}
