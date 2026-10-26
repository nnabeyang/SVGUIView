import Foundation

/// A SMIL animation element of a document, with its attributes read.
///
/// The values of `from`, `to`, `by` and `values` stay as written, since how they're read depends on the attribute
/// that the animation changes.
struct SMILAnimation: Sendable {
  enum Kind: Sendable, Equatable {
    case animate
    case set
    case animateTransform
    case animateMotion
  }

  /// The values that an animation goes through, as written.
  enum Values: Sendable, Equatable {
    /// A list of values, which `values` gives.
    case list([String])
    /// A to-animation, from the underlying value or from `from` to `to`.
    case to(from: String?, to: String)
    /// A by-animation, which adds `by` to the underlying value or to `from`.
    case by(from: String?, by: String)
    /// No values, which only `<animateMotion>` can have, with a path instead.
    case none

    /// How many values the animation goes through, which `keyTimes` must match.
    var count: Int {
      switch self {
      case .list(let values): values.count
      case .to, .by: 2
      case .none: 0
      }
    }
  }

  enum CalcMode: String, Sendable, Equatable {
    case discrete
    case linear
    case paced
    case spline
  }

  enum Fill: String, Sendable, Equatable {
    case remove
    case freeze
  }

  enum Restart: String, Sendable, Equatable {
    case always
    case whenNotActive
    case never
  }

  /// The animation element.
  let elementID: ElementID
  /// The ID of the animation element, which syncbase values of other animations reference.
  let id: String?
  let kind: Kind
  /// The element that the animation changes.
  let target: ElementID
  /// The name of the target element.
  let targetName: SVGElementName
  /// The attribute or property that the animation changes, or `nil` for `<animateMotion>`.
  let attributeName: String?
  let values: Values
  let calcMode: CalcMode
  /// The times of the values, from 0 to 1, or `nil` to space them evenly.
  let keyTimes: [Double]?
  /// The easing of each interval between values for `calcMode="spline"`.
  let keySplines: [EasingFunction]?
  /// Whether the animation adds to the value underneath it.
  let isAdditive: Bool
  /// Whether each repeat builds on the value at the end of the previous one.
  let isAccumulative: Bool
  let begin: [SMILTimeValue]
  /// The `end` list, or `nil` if the animation doesn't have one.
  let end: [SMILTimeValue]?
  /// The simple duration in seconds, or `nil` if it's indefinite.
  let duration: Double?
  /// The `repeatCount`, or `nil` if the animation doesn't have one.
  let repeatCount: AnimationIterationCount?
  /// The `repeatDur` in seconds, which is infinite for `indefinite`, or `nil` if the animation doesn't have one.
  let repeatDuration: Double?
  /// The shortest active duration in seconds.
  let minimum: Double
  /// The longest active duration in seconds, which is infinite without a limit.
  let maximum: Double
  let restart: Restart
  let fill: Fill
  /// The attributes of the animation element, for the attributes of one kind, such as `type`, `path` and `rotate`.
  let attributes: [String: String]
  /// The ID that the `<mpath>` child of an `<animateMotion>` references.
  let motionPath: String?
}

extension SMILAnimation {
  /// The animation of an animation element, or `nil` if the element isn't one or is in error, which SVG ignores.
  ///
  /// - Parameter target: The element that the animation changes, which is the element that `href` references or
  ///   the parent.
  init?(element: DocumentElement, target: DocumentElement) {
    let kind: Kind
    switch element.name {
    case .animate: kind = .animate
    case .set: kind = .set
    case .animateTransform: kind = .animateTransform
    case .animateMotion: kind = .animateMotion
    default: return nil
    }
    let attributes = element.attributes
    elementID = element.id
    id = attributes["id"]?.trimmingCharacters(in: .whitespaces)
    self.kind = kind
    self.target = target.id
    targetName = target.name
    self.attributes = attributes

    if kind == .animateMotion {
      attributeName = nil
    } else {
      // An attribute in the XLink namespace is written with its prefix, as the parser keeps `href`.
      guard var name = attributes["attributeName"]?.trimmingCharacters(in: .whitespaces), !name.isEmpty else {
        return nil
      }
      if name == "xlink:href" { name = "href" }
      attributeName = name
    }

    let to = attributes["to"]
    let from = kind == .set ? nil : attributes["from"]
    let by = kind == .set ? nil : attributes["by"]
    if kind != .set, let list = attributes["values"].map(Self.values), !list.isEmpty {
      values = .list(list)
    } else if let to {
      values = .to(from: from, to: to)
    } else if let by {
      values = .by(from: from, by: by)
    } else if kind == .animateMotion {
      values = .none
    } else {
      return nil
    }

    switch kind {
    case .set:
      calcMode = .discrete
    case .animateMotion:
      calcMode = attributes["calcMode"].flatMap(CalcMode.init(rawValue:)) ?? .paced
    case .animate, .animateTransform:
      calcMode = attributes["calcMode"].flatMap(CalcMode.init(rawValue:)) ?? .linear
    }

    // A list of times or splines that doesn't fit the values is an error. Paced animations ignore both.
    if kind != .set, calcMode != .paced, let text = attributes["keyTimes"] {
      guard let times = Self.numbers(text, separator: ";") else { return nil }
      if kind != .animateMotion || values != .none {
        guard times.count == values.count else { return nil }
      }
      guard times.first == 0, zip(times, times.dropFirst()).allSatisfy({ $0 <= $1 }),
        times.allSatisfy({ (0...1).contains($0) }), calcMode == .discrete || times.last == 1
      else { return nil }
      keyTimes = times
    } else {
      keyTimes = nil
    }
    if calcMode == .spline {
      guard let splines = attributes["keySplines"].flatMap(Self.splines) else { return nil }
      let intervals = (keyTimes?.count ?? values.count) - 1
      guard values == .none || splines.count == intervals else { return nil }
      keySplines = splines
    } else {
      keySplines = nil
    }

    isAdditive = kind != .set && attributes["additive"] == "sum"
    isAccumulative = kind != .set && attributes["accumulate"] == "sum"

    begin = attributes["begin"].flatMap(SMILTimeValue.list) ?? [.offset(0)]
    end = attributes["end"].flatMap(SMILTimeValue.list)
    duration = attributes["dur"].flatMap { Self.duration($0) }
    repeatCount = attributes["repeatCount"].flatMap { text -> AnimationIterationCount? in
      let text = text.trimmingCharacters(in: .whitespaces)
      if text == "indefinite" { return .infinite }
      guard let count = Double(text), count > 0, count.isFinite else { return nil }
      return .count(count)
    }
    repeatDuration = attributes["repeatDur"].flatMap { text -> Double? in
      if text.trimmingCharacters(in: .whitespaces) == "indefinite" { return .infinity }
      return SMILClock.seconds(text[...])
    }
    // A `min` or `max` that is invalid, or a `min` larger than `max`, is ignored.
    let minimum = attributes["min"].flatMap { SMILClock.seconds($0[...]) } ?? 0
    let maximum = attributes["max"].flatMap { SMILClock.seconds($0[...]) } ?? .infinity
    if minimum <= maximum {
      self.minimum = minimum
      self.maximum = maximum
    } else {
      self.minimum = 0
      self.maximum = .infinity
    }
    restart = attributes["restart"].flatMap(Restart.init(rawValue:)) ?? .always
    fill = attributes["fill"].flatMap(Fill.init(rawValue:)) ?? .remove
    motionPath =
      kind == .animateMotion
      ? element.children.first { $0.name == .mpath }.flatMap { $0.attributes["href"].flatMap(Self.fragment) } : nil
  }

  /// The values of a `values` list, separated by semicolons, without the empty ones.
  private static func values(_ text: String) -> [String] {
    text.split(separator: ";").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
  }

  /// The numbers of a list, or `nil` if any of them isn't a number.
  private static func numbers(_ text: String, separator: Character) -> [Double]? {
    let items = text.split(separator: separator).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
    let numbers = items.compactMap(Double.init)
    return numbers.count == items.count && !numbers.isEmpty ? numbers : nil
  }

  /// The splines of a `keySplines` list, each with four numbers from 0 to 1, or `nil` if any of them is invalid.
  private static func splines(_ text: String) -> [EasingFunction]? {
    var splines = [EasingFunction]()
    for item in text.split(separator: ";") {
      let item = item.trimmingCharacters(in: .whitespacesAndNewlines)
      if item.isEmpty { continue }
      let numbers = item.split { $0 == "," || $0.isWhitespace }.compactMap { Double($0) }
      guard numbers.count == 4, numbers.allSatisfy({ (0...1).contains($0) }) else { return nil }
      splines.append(.cubicBezier(x1: numbers[0], y1: numbers[1], x2: numbers[2], y2: numbers[3]))
    }
    return splines.isEmpty ? nil : splines
  }

  /// A simple duration that is a clock value larger than zero, or `nil` for `indefinite`, `media` or an invalid
  /// value, which all make it indefinite.
  private static func duration(_ text: String) -> Double? {
    guard let seconds = SMILClock.seconds(text[...]), seconds > 0 else { return nil }
    return seconds
  }

  /// The ID that a local reference such as `#a` names.
  fileprivate static func fragment(_ text: String) -> String? {
    let text = text.trimmingCharacters(in: .whitespaces)
    guard text.hasPrefix("#"), text.count > 1 else { return nil }
    return String(text.dropFirst())
  }
}

extension SMILAnimation {
  /// The animations of a document in document order. An animation changes the element that its `href` references,
  /// or its parent.
  static func animations(of document: SVGDocument) -> [SMILAnimation] {
    guard let root = document.root else { return [] }
    // Of elements with the same ID, the first one in the document is the one that `href` finds.
    var elements = [String: DocumentElement]()
    func index(_ element: DocumentElement) {
      if let id = element.attributes["id"]?.trimmingCharacters(in: .whitespaces), elements[id] == nil {
        elements[id] = element
      }
      element.children.forEach(index)
    }
    index(root)
    var animations = [SMILAnimation]()
    func collect(_ element: DocumentElement) {
      for child in element.children {
        if child.name.isAnimation {
          let target: DocumentElement?
          if let href = child.attributes["href"] {
            target = fragment(href).flatMap { elements[$0] }
          } else {
            target = element
          }
          if let target, let animation = SMILAnimation(element: child, target: target) {
            animations.append(animation)
          }
        } else {
          collect(child)
        }
      }
    }
    collect(root)
    return animations
  }
}
