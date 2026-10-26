import Foundation

/// A value of the `begin` or `end` list of a SMIL animation.
enum SMILTimeValue: Sendable, Equatable {
  /// A time in seconds after the document begins, which can be negative.
  case offset(Double)
  /// A time in seconds after the begin or the end of an interval of another animation, such as `a.end+1s`.
  case syncbase(id: String, event: SMILSyncbaseEvent, offset: Double)
  /// A time that never comes without the document API, such as `indefinite`.
  case indefinite
  /// A time that depends on what SVGUIView doesn't have: user events such as `click`, access keys, repeats of other
  /// animations and wall-clock times. It doesn't come, as `indefinite` doesn't.
  case unresolved

  /// The values of a `begin` or `end` list, separated by semicolons, or `nil` if any of them is invalid, which makes
  /// the whole attribute invalid.
  static func list(_ text: String) -> [SMILTimeValue]? {
    var values = [SMILTimeValue]()
    for item in text.split(separator: ";", omittingEmptySubsequences: false) {
      let item = item.trimmingCharacters(in: .whitespacesAndNewlines)
      if item.isEmpty { continue }
      guard let value = SMILTimeValue(item[...]) else { return nil }
      values.append(value)
    }
    return values.isEmpty ? nil : values
  }

  /// One value of a `begin` or `end` list, or `nil` if it's invalid.
  init?(_ text: Substring) {
    if text == "indefinite" {
      self = .indefinite
      return
    }
    if text.hasPrefix("wallclock(") || text.hasPrefix("accessKey(") {
      guard text.contains(")") else { return nil }
      self = .unresolved
      return
    }
    if let first = text.first, first.isASCIIDigit || first == "+" || first == "-" || first == "." {
      guard let offset = Self.offset(text) else { return nil }
      self = .offset(offset)
      return
    }
    // The last period that a name follows separates the ID from the event, so that an ID can have periods and an
    // offset can have a fraction, as in `a.b.end+1.5s`.
    var start = text.startIndex
    var id: Substring?
    var index = text.endIndex
    while index > text.startIndex {
      index = text.index(before: index)
      let next = text.index(after: index)
      if text[index] == ".", next < text.endIndex, text[next].isASCIILetter {
        id = text[..<index]
        start = next
        break
      }
    }
    // Event names have letters only, so that a sign after them starts an offset.
    var nameEnd = start
    while nameEnd < text.endIndex, text[nameEnd].isASCIILetter {
      nameEnd = text.index(after: nameEnd)
    }
    let name = text[start..<nameEnd]
    var rest = text[nameEnd...]
    // `repeat(2)` counts the repeats of the other animation.
    if rest.hasPrefix("(") {
      guard let close = rest.firstIndex(of: ")") else { return nil }
      rest = rest[rest.index(after: close)...]
    }
    let trimmed = rest.drop { $0.isWhitespace }
    let offset: Double
    if trimmed.isEmpty {
      offset = 0
    } else {
      guard let value = Self.offset(trimmed) else { return nil }
      offset = value
    }
    guard !name.isEmpty, id.map({ !$0.isEmpty }) ?? true else { return nil }
    switch (id, name) {
    case (let id?, "begin"):
      self = .syncbase(id: String(id), event: .begin, offset: offset)
    case (let id?, "end"):
      self = .syncbase(id: String(id), event: .end, offset: offset)
    default:
      self = .unresolved
    }
  }

  /// An offset, which is a clock value with an optional sign, in seconds.
  static func offset(_ text: Substring) -> Double? {
    var text = text
    var sign = 1.0
    if let first = text.first, first == "+" || first == "-" {
      sign = first == "-" ? -1 : 1
      text = text.dropFirst().drop { $0.isWhitespace }
    }
    return SMILClock.seconds(text).map { sign * $0 }
  }
}

/// The event of another animation that a syncbase value follows.
enum SMILSyncbaseEvent: Sendable, Equatable {
  case begin
  case end
}

/// Clock values, which SMIL animation uses for times and durations.
enum SMILClock {
  /// The seconds of a clock value, such as `02:30`, `1.5s`, `500ms`, `2min` or `1h`, or `nil` if it isn't one.
  static func seconds(_ text: Substring) -> Double? {
    let text = text.trimmingCharacters(in: .whitespacesAndNewlines)[...]
    if text.contains(":") {
      let parts = text.split(separator: ":", omittingEmptySubsequences: false)
      // A full clock value has hours, and a partial one doesn't. Minutes and seconds have two digits each.
      guard parts.count == 2 || parts.count == 3 else { return nil }
      let hours: Double
      if parts.count == 3 {
        guard !parts[0].isEmpty, parts[0].allSatisfy(\.isASCIIDigit), let value = Double(parts[0]) else {
          return nil
        }
        hours = value
      } else {
        hours = 0
      }
      let minutesText = parts[parts.count - 2]
      let secondsText = parts[parts.count - 1]
      guard minutesText.count == 2, minutesText.allSatisfy(\.isASCIIDigit), let minutes = Double(minutesText),
        minutes < 60, let seconds = number(secondsText), secondsText.prefix(while: \.isASCIIDigit).count == 2,
        seconds < 60
      else { return nil }
      return hours * 3600 + minutes * 60 + seconds
    }
    let metrics: [(String, Double)] = [("ms", 0.001), ("min", 60), ("h", 3600), ("s", 1)]
    for (metric, scale) in metrics where text.hasSuffix(metric) {
      return number(text.dropLast(metric.count)).map { $0 * scale }
    }
    return number(text)
  }

  /// A number with digits and an optional fraction, without a sign or an exponent.
  private static func number(_ text: Substring) -> Double? {
    let parts = text.split(separator: ".", omittingEmptySubsequences: false)
    guard parts.count <= 2, !parts[0].isEmpty, parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isASCIIDigit) })
    else { return nil }
    return Double(text)
  }
}

extension Character {
  fileprivate var isASCIIDigit: Bool { isASCII && isNumber }
  fileprivate var isASCIILetter: Bool { isASCII && isLetter }
}
