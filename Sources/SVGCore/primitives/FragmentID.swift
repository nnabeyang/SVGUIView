import Foundation

/// The ID that a local reference such as `#a` in an `href` names, or `nil` if the `href` isn't one.
///
/// The reference is a URL, whose fragment has its percent-encoded characters decoded, so that `#a%20b` names the
/// element with the ID `a b`, as browsers find it. A fragment that can't be decoded, such as `#100%`, names the ID as
/// it's written.
func fragmentID(of href: String?) -> String? {
  guard let text = href?.trimmingCharacters(in: .whitespaces), text.hasPrefix("#"), text.count > 1 else { return nil }
  let fragment = String(text.dropFirst())
  return fragment.removingPercentEncoding ?? fragment
}
