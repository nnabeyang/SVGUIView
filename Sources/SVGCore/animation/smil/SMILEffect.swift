import Foundation

/// A SMIL animation at a time of the document, when it has an effect.
struct SMILEffect: Sendable {
  let animation: SMILAnimation
  let state: SMILState
  /// The position of the animation in the document, which orders animations whose intervals begin together.
  let order: Int

  /// The effects of animations at a time by the elements that they change, each in the order that they apply in:
  /// the animation whose interval began first is at the bottom, and of animations whose intervals began together,
  /// the one that comes first in the document, as the sandwich model of SMIL says.
  ///
  /// - Parameter time: The time in seconds since the document began.
  static func effects(of animations: [SMILAnimation], at time: Double) -> [ElementID: [SMILEffect]] {
    guard !animations.isEmpty else { return [:] }
    let schedule = SMILSchedule(animations: animations, until: time)
    var effects = [ElementID: [SMILEffect]]()
    for (index, animation) in animations.enumerated() {
      guard let state = schedule.state(of: index, at: time) else { continue }
      effects[animation.target, default: []].append(SMILEffect(animation: animation, state: state, order: index))
    }
    return effects.mapValues { effects in
      effects.sorted { ($0.state.intervalBegin, $0.order) < ($1.state.intervalBegin, $1.order) }
    }
  }

  /// The property that the animation changes, or `nil` if it changes an attribute of its target that isn't a
  /// property.
  ///
  /// `<animate>` doesn't change `transform`, which `<animateTransform>` animates instead.
  var property: PropertyID? {
    guard let name = animation.attributeName, let id = PropertyID(rawValue: name), !id.isAnimation else { return nil }
    switch animation.kind {
    case .animateTransform:
      return id == .transform ? id : nil
    case .animate, .set:
      guard id != .transform else { return nil }
      var visitor = AttributeAcceptance(name: animation.targetName)
      return id.visit(&visitor) ? id : nil
    case .animateMotion:
      return nil
    }
  }

  /// The value of the property that the animation gives at its time, or `nil` if a value of the animation is
  /// invalid for the property, which makes the animation have no effect.
  ///
  /// - Parameter underlying: The value under the animation, which a to-animation starts from, and which additive
  ///   animations add to.
  func value<P: StyleProperty>(of _: P.Type, over underlying: P.Computed, in resolver: StyleResolver) -> P.Computed? {
    // `<animateTransform>` changes the transform list of `transform` with the values of its type.
    if animation.kind == .animateTransform {
      guard let list = underlying as? TransformList else { return nil }
      return transformed(list) as? P.Computed
    }
    return value(of: PropertyValues<P>(resolver: resolver), over: underlying)
  }

  /// The value that the animation gives at its time, or `nil` if a value of the animation is invalid for what it
  /// changes, which makes the animation have no effect.
  ///
  /// - Parameter underlying: The value under the animation, which a to-animation starts from, and which additive
  ///   animations add to.
  func value<T: SMILValueType>(of type: T, over underlying: T.Value) -> T.Value? {
    let values: [T.Value]
    // The value that each repeat adds to with `accumulate="sum"`, or `nil` if the animation doesn't accumulate.
    var accumulated: T.Value?
    switch animation.values {
    case .to(let from, let to):
      guard let to = type.value(to) else { return nil }
      if animation.kind == .set { return to }
      guard let from else {
        // A to-animation goes from the value under it, and neither adds to it nor accumulates.
        return interpolated([underlying, to], of: type)
      }
      guard let from = type.value(from) else { return nil }
      values = [from, to]
      accumulated = to
    case .by(let from, let by):
      guard let by = type.value(by) else { return nil }
      guard let from else {
        // A by-animation adds to the value under it.
        guard let end = type.added(by, to: underlying) else { return nil }
        var value = interpolated([underlying, end], of: type)
        if animation.isAccumulative {
          value = Self.accumulating(by, to: value, times: state.iteration, of: type)
        }
        return value
      }
      guard let from = type.value(from), let end = type.added(by, to: from) else { return nil }
      values = [from, end]
      accumulated = end
    case .list(let texts):
      var list = [T.Value]()
      for text in texts {
        guard let value = type.value(text) else { return nil }
        list.append(value)
      }
      values = list
      accumulated = list.last
    case .none:
      return nil
    }
    var value = interpolated(values, of: type)
    if animation.isAccumulative, let accumulated {
      value = Self.accumulating(accumulated, to: value, times: state.iteration, of: type)
    }
    if animation.isAdditive, let sum = type.added(value, to: underlying) {
      value = sum
    }
    return value
  }

  /// The value with another value added to it once for each repeat before the current one.
  private static func accumulating<T: SMILValueType>(
    _ addend: T.Value, to value: T.Value, times: Double, of type: T
  ) -> T.Value {
    var value = value
    // A very large count stops, as a value that big can't be drawn anyway.
    for _ in 0..<Int(min(times, 1000)) {
      guard let sum = type.added(addend, to: value) else { break }
      value = sum
    }
    return value
  }

  /// The value at the progress of the animation through the values, as its `calcMode`, `keyTimes` and `keySplines`
  /// say. Values that can't be interpolated change discretely.
  private func interpolated<T: SMILValueType>(_ values: [T.Value], of type: T) -> T.Value {
    let count = values.count
    guard count > 1 else { return values[0] }
    let progress = min(max(state.progress, 0), 1)
    let calcMode = type.isInterpolable ? animation.calcMode : .discrete
    if calcMode == .discrete {
      // Each value lasts from its time to the next one, and the end of the simple duration has the last value.
      if progress >= 1 { return values[count - 1] }
      let times = animation.keyTimes ?? (0..<count).map { Double($0) / Double(count) }
      return values[times.lastIndex { $0 <= progress } ?? 0]
    }
    var times = animation.keyTimes ?? (0..<count).map { Double($0) / Double(count - 1) }
    // A paced animation spaces the values by their distances, and is linear if they have none.
    if calcMode == .paced {
      let distances = zip(values, values.dropFirst()).map { type.distance($0, $1) }
      let total = distances.reduce(0) { $0 + ($1 ?? .nan) }
      if total.isFinite, total > 0 {
        var sum = 0.0
        times =
          [0]
          + distances.map { distance in
            sum += distance ?? 0
            return sum / total
          }
      }
    }
    var index = 0
    while index + 2 < count, times[index + 1] <= progress {
      index += 1
    }
    let length = times[index + 1] - times[index]
    var intervalProgress = length == 0 ? 1 : (progress - times[index]) / length
    if calcMode == .spline, let splines = animation.keySplines, index < splines.count {
      intervalProgress = splines[index](intervalProgress)
    }
    return type.interpolated(values[index], values[index + 1], progress: intervalProgress)
  }
}

/// The values of what a SMIL animation changes: how its texts are read, and how values are found between them,
/// added and measured.
protocol SMILValueType {
  associatedtype Value
  /// Whether values between two values exist, so that animations interpolate them instead of changing them
  /// discretely.
  var isInterpolable: Bool { get }
  /// The value of a text of an animation, or `nil` if it's invalid.
  func value(_ text: String) -> Value?
  func interpolated(_ from: Value, _ to: Value, progress: Double) -> Value
  /// The sum of a value and the value under it, or `nil` if the values can't be added.
  func added(_ value: Value, to underlying: Value) -> Value?
  /// The distance between two values, or `nil` if it isn't defined.
  func distance(_ from: Value, _ to: Value) -> Double?
}

/// The computed values of a property of an element, which the texts of animations are read as presentation
/// attributes into.
struct PropertyValues<P: StyleProperty>: SMILValueType {
  let resolver: StyleResolver

  var isInterpolable: Bool { P.isInterpolable }

  func value(_ text: String) -> P.Computed? {
    P.declared(attribute: text).map { resolver.computed($0, of: P.self) }
  }

  func interpolated(_ from: P.Computed, _ to: P.Computed, progress: Double) -> P.Computed {
    P.interpolated(from, to, progress: progress, in: resolver)
  }

  func added(_ value: P.Computed, to underlying: P.Computed) -> P.Computed? {
    P.added(value, to: underlying, in: resolver)
  }

  func distance(_ from: P.Computed, _ to: P.Computed) -> Double? {
    P.distance(from, to, in: resolver)
  }
}

/// Whether a property is a presentation attribute of an element.
private struct AttributeAcceptance: StylePropertyVisitor {
  let name: SVGElementName

  func visit<P: StyleProperty>(_: P.Type) -> Bool {
    P.accepts(attributeOn: name)
  }
}
