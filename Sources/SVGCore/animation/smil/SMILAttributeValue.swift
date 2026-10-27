import Foundation

/// The values of an attribute that isn't a property, which SMIL animations change before the cascade: lengths, lists
/// of numbers, or other values, which change discretely.
struct SMILAttributeValues: SMILValueType {
  enum Kind: Equatable {
    case length
    case numbers
    case other
  }

  enum Value: Equatable {
    case length(SVGLength)
    case numbers([Double])
    case text(String)

    /// The value as the text of an attribute.
    var text: String {
      switch self {
      case .length(let length): length.description
      case .numbers(let numbers): numbers.map { "\($0)" }.joined(separator: " ")
      case .text(let text): text
      }
    }
  }

  let kind: Kind

  /// The attributes whose values are lengths.
  private static let lengths: Set<String> = [
    "x", "y", "width", "height", "cx", "cy", "r", "rx", "ry", "x1", "y1", "x2", "y2", "fx", "fy", "fr", "dx", "dy",
    "refX", "refY", "markerWidth", "markerHeight", "startOffset", "textLength", "offset",
  ]
  /// The attributes whose values are lists of numbers.
  private static let numbers: Set<String> = [
    "points", "viewBox", "stdDeviation", "kernelMatrix", "values", "tableValues", "k1", "k2", "k3", "k4", "scale",
    "baseFrequency", "radius", "surfaceScale", "diffuseConstant", "specularConstant", "specularExponent",
    "limitingConeAngle", "azimuth", "elevation", "z", "pointsAtX", "pointsAtY", "pointsAtZ", "amplitude", "exponent",
    "intercept", "slope", "seed", "numOctaves", "pathLength",
  ]

  /// The values of an attribute.
  init(attribute name: String) {
    kind = Self.lengths.contains(name) ? .length : Self.numbers.contains(name) ? .numbers : .other
  }

  /// The value of an attribute that the document doesn't have, or that is invalid, under the animations.
  var initial: Value {
    switch kind {
    case .length: .length(.number(0))
    case .numbers: .numbers([])
    case .other: .text("")
    }
  }

  var isInterpolable: Bool { kind != .other }

  func value(_ text: String) -> Value? {
    switch kind {
    case .length:
      return SVGLength(text).map(Value.length)
    case .numbers:
      let items = text.split { $0 == "," || $0.isWhitespace }
      let numbers = items.compactMap { Double($0) }
      return numbers.count == items.count && !numbers.isEmpty ? .numbers(numbers) : nil
    case .other:
      return .text(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }
  }

  func interpolated(_ from: Value, _ to: Value, progress: Double) -> Value {
    switch (from, to) {
    case (.length(let from), .length(let to)):
      return .length(from.animated(to: to, progress: progress))
    case (.numbers(let from), .numbers(let to)) where from.count == to.count:
      return .numbers(zip(from, to).map { $0.interpolated(to: $1, progress: progress) ?? $0 })
    default:
      return discrete(from, to, progress: progress)
    }
  }

  func added(_ value: Value, to underlying: Value) -> Value? {
    switch (underlying, value) {
    case (.length(let underlying), .length(let value)):
      return underlying.adding(value).map(Value.length)
    case (.numbers(let underlying), .numbers(let value)) where underlying.count == value.count:
      return .numbers(zip(underlying, value).map(+))
    default:
      return nil
    }
  }

  func distance(_ from: Value, _ to: Value) -> Double? {
    switch (from, to) {
    case (.length(let from), .length(let to)):
      return from.pacedDistance(to: to)
    case (.numbers(let from), .numbers(let to)) where from.count == to.count:
      return sqrt(zip(from, to).reduce(0) { $0 + ($1.1 - $1.0) * ($1.1 - $1.0) })
    default:
      return nil
    }
  }
}

extension SMILEffect {
  /// Whether the animation changes an attribute of its target that isn't a property.
  var changesAttribute: Bool {
    switch animation.kind {
    case .animate, .set:
      animation.attributeName != nil && animation.attributeName != "transform" && property == nil
    case .animateTransform:
      animatesTransform("gradientTransform") || animatesTransform("patternTransform")
    case .animateMotion:
      false
    }
  }

  /// The attributes that SMIL animations change at their time, by the elements that they change, with the values
  /// after all the animations of each attribute, as text.
  ///
  /// - Parameter effects: The effects of the animations by the elements that they change, in the order that they
  ///   apply in.
  static func attributes(
    of effects: [ElementID: [SMILEffect]], in document: SVGDocument
  ) -> [ElementID: [String: String]] {
    let targets = effects.filter { $0.value.contains(where: \.changesAttribute) }
    guard !targets.isEmpty, let root = document.root else { return [:] }
    var elements = [ElementID: DocumentElement]()
    func find(_ element: DocumentElement) {
      if targets[element.id] != nil { elements[element.id] = element }
      element.children.forEach(find)
    }
    find(root)
    var attributes = [ElementID: [String: String]]()
    for (id, effects) in targets {
      guard let element = elements[id] else { continue }
      var values = [String: SMILAttributeValues.Value]()
      // The transform lists of `<animateTransform>`, which have values of their own.
      var transforms = [String: TransformList]()
      for effect in effects where effect.changesAttribute {
        guard let name = effect.animation.attributeName else { continue }
        if effect.animation.kind == .animateTransform {
          let underlying = transforms[name] ?? element.attributes[name].flatMap(TransformList.init(attribute:)) ?? .none
          if let list = effect.transformed(underlying) {
            transforms[name] = list
          }
          continue
        }
        let type = SMILAttributeValues(attribute: name)
        let underlying = values[name] ?? element.attributes[name].flatMap(type.value) ?? type.initial
        if let value = effect.value(of: type, over: underlying) {
          values[name] = value
        }
      }
      let texts = values.mapValues(\.text).merging(transforms.mapValues(\.attributeText)) { $1 }
      if !texts.isEmpty {
        attributes[id] = texts
      }
    }
    return attributes
  }
}
