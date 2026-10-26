import Foundation

/// The values of an `<animateTransform>`: the numbers of a transform function of the type that its `type` gives,
/// which are interpolated, added and measured number by number.
struct SMILTransformValues: SMILValueType {
  enum Kind: String {
    case translate
    case scale
    case rotate
    case skewX
    case skewY
  }

  let kind: Kind

  /// The values of a `type`, which is `translate` without one, or `nil` for a type that isn't valid, which makes the
  /// animation have no effect.
  init?(type: String?) {
    guard let kind = Kind(rawValue: (type ?? "translate").trimmingCharacters(in: .whitespaces)) else { return nil }
    self.kind = kind
  }

  /// The numbers that a value has after the ones that it leaves out are filled in.
  private var count: Int {
    switch kind {
    case .translate, .scale: 2
    case .rotate: 3
    case .skewX, .skewY: 1
    }
  }

  /// The value with all its numbers zero, which by-animations start from, as SMIL says, and which additive animations
  /// don't change: they add their transforms to the transform list under them instead.
  var zero: [Double] { [Double](repeating: 0, count: count) }

  var isInterpolable: Bool { true }

  /// The numbers of a value, with the ones that it leaves out filled in: `ty` is 0, `sy` is `sx`, and the center of
  /// a rotation is the origin.
  func value(_ text: String) -> [Double]? {
    let items = text.split { $0 == "," || $0.isWhitespace }
    let numbers = items.compactMap { Double($0) }
    guard numbers.count == items.count else { return nil }
    switch (kind, numbers.count) {
    case (.translate, 1): return [numbers[0], 0]
    case (.scale, 1): return [numbers[0], numbers[0]]
    case (.rotate, 1): return [numbers[0], 0, 0]
    case (.translate, 2), (.scale, 2), (.rotate, 3), (.skewX, 1), (.skewY, 1): return numbers
    default: return nil
    }
  }

  func interpolated(_ from: [Double], _ to: [Double], progress: Double) -> [Double] {
    zip(from, to).map { $0 + ($1 - $0) * progress }
  }

  func added(_ value: [Double], to underlying: [Double]) -> [Double]? {
    zip(underlying, value).map(+)
  }

  /// The distance between two values, which is the distance between the points for translations and scales, and the
  /// difference of the angles for rotations and skews.
  func distance(_ from: [Double], _ to: [Double]) -> Double? {
    switch kind {
    case .translate, .scale: hypot(to[0] - from[0], to[1] - from[1])
    case .rotate, .skewX, .skewY: abs(to[0] - from[0])
    }
  }

  /// The transform functions of a value. A rotation about a center is a translation to the center, the rotation,
  /// and a translation back.
  func functions(_ value: [Double]) -> [TransformFunction] {
    switch kind {
    case .translate:
      return [.translate(.number(value[0]), .number(value[1]))]
    case .scale:
      return [.scale(value[0], value[1])]
    case .rotate:
      guard value[1] != 0 || value[2] != 0 else { return [.rotate(value[0])] }
      return [
        .translate(.number(value[1]), .number(value[2])), .rotate(value[0]),
        .translate(.number(-value[1]), .number(-value[2])),
      ]
    case .skewX:
      return [.skew(value[0], 0)]
    case .skewY:
      return [.skew(0, value[0])]
    }
  }
}

extension SMILEffect {
  /// Whether the animation is an `<animateTransform>` of the attribute.
  func animatesTransform(_ name: String) -> Bool {
    animation.kind == .animateTransform && animation.attributeName == name
  }

  /// The transform list that an `<animateTransform>` gives at its time over the list under it, or `nil` if a value
  /// of the animation is invalid, which makes the animation have no effect.
  ///
  /// An additive animation, and a by-animation, which SMIL makes additive, add their transform after the list under
  /// them. Other animations replace the list.
  func transformed(_ underlying: TransformList) -> TransformList? {
    guard animation.kind == .animateTransform, let type = SMILTransformValues(type: animation.attributes["type"]),
      let value = value(of: type, over: type.zero)
    else { return nil }
    let functions = type.functions(value)
    var isAdditive = animation.isAdditive
    if case .by(from: nil, by: _) = animation.values { isAdditive = true }
    return TransformList(functions: isAdditive ? underlying.functions + functions : functions)
  }
}
