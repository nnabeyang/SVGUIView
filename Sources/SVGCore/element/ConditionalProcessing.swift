import Foundation

/// The conditional processing attributes of an element, which decide whether the element is rendered, and which
/// child of a `<switch>` is.
///
/// The conditions don't stop references: a gradient, a clip path or an element that a `<use>` shows works whatever
/// the conditions of its ancestors are.
enum ConditionalProcessing {
  /// Whether all the conditional processing attributes of an element evaluate to true.
  ///
  /// - `requiredExtensions` is false with any value, even an empty one, since SVGUIView supports no extensions.
  /// - `requiredFeatures` is ignored, as SVG 2 removed it.
  /// - `systemLanguage` is true if one of its comma-separated languages matches one of the user's. An empty value is
  ///   false.
  ///
  /// - Parameters:
  ///   - attributes: The attributes of the element.
  ///   - languages: The languages of the user, in the order of preference.
  static func passes(attributes: [String: String], languages: [String]) -> Bool {
    if attributes["requiredExtensions"] != nil { return false }
    if let systemLanguage = attributes["systemLanguage"] {
      let tags = systemLanguage.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
      return tags.contains { tag in !tag.isEmpty && languages.contains { matches(tag, $0) } }
    }
    return true
  }

  /// Whether a language of `systemLanguage` matches a language of the user. They match if their primary language
  /// subtags are the same, as browsers match them: `en` and `en-GB` match a user of `en-US`.
  private static func matches(_ tag: String, _ language: String) -> Bool {
    func primary(_ tag: String) -> Substring {
      tag.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)[0]
    }
    return primary(tag).caseInsensitiveCompare(primary(language)) == .orderedSame
  }
}
