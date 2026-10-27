import Foundation
import Testing

@testable import SVGCore

/// The IDs of the elements of a document with the content whose painting is animated, or `nil` if they can't be
/// told.
private func animated(_ content: String) -> Set<String>? {
  let svg = #"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">"# + content + "</svg>"
  let base = SVGParser.parse(data: Data(svg.utf8))
  guard let elements = base.elementsWithAnimatedPainting() else { return nil }
  return Set((base.root?.elements ?? []).filter { elements.contains($0.base.elementID) }.compactMap(\.base.id))
}

@Suite("Elements whose painting is animated")
struct AnimatedPaintingTests {
  /// Documents, and the IDs of the elements whose painting can change, or `nil` if they can't be told.
  private static let documents: [(String, Set<String>?)] = [
    (#"<rect id="r" width="10" height="10"/>"#, []),
    // An animation of a property that isn't the transform or the opacity changes the element and its descendants.
    (
      #"<style>@keyframes a { to { fill: lime } }</style><g id="g" style="animation: a 1s">"#
        + #"<rect id="r" width="10" height="10"/></g><rect id="s" width="10" height="10"/>"#,
      ["g", "r"]
    ),
    (
      #"<style>@keyframes a { to { transform: rotate(90deg); opacity: 0 } }</style>"#
        + #"<rect id="r" width="10" height="10" style="animation: a 1s"/>"#,
      []
    ),
    (#"<rect id="r" width="10" height="10"><animate attributeName="x" to="5" dur="1s"/></rect>"#, ["r"]),
    (
      #"<rect id="r" width="10" height="10"><animateTransform attributeName="transform" type="rotate" to="90" dur="1s"/></rect>"#,
      []
    ),
    // An animation inside a gradient, a clip path or a mask changes the elements that reference it.
    (
      #"<linearGradient id="l"><stop id="t" offset="0" stop-color="red"><animate attributeName="stop-color" to="lime" dur="1s"/></stop></linearGradient>"#
        + ##"<rect id="r" width="10" height="10" fill="url(#l)"/>"##,
      nil
    ),
    (
      #"<linearGradient id="l"><animateTransform attributeName="gradientTransform" type="rotate" to="90" dur="1s"/>"#
        + #"<stop offset="0" stop-color="red"/></linearGradient>"#,
      nil
    ),
    (
      #"<clipPath id="c"><rect id="s" width="5" height="5"><animate attributeName="width" to="10" dur="1s"/></rect></clipPath>"#
        + ##"<rect id="r" width="10" height="10" clip-path="url(#c)"/>"##,
      nil
    ),
    (
      #"<style>@keyframes a { to { transform: rotate(90deg) } }</style>"#
        + #"<mask id="m"><rect id="s" width="5" height="5" fill="white" style="animation: a 1s"/></mask>"#,
      nil
    ),
  ]

  @Test("the elements whose painting an animation changes", arguments: documents)
  func elements(content: String, expected: Set<String>?) {
    #expect(animated(content) == expected)
  }
}
