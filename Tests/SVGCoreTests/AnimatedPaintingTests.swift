import Foundation
import Testing

@testable import SVGCore

/// The IDs of the elements of a document with the content whose painting is animated.
private func animated(_ content: String) -> Set<String> {
  let svg = #"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">"# + content + "</svg>"
  let base = SVGParser.parse(data: Data(svg.utf8))
  let elements = base.elementsWithAnimatedPainting()
  return Set((base.root?.elements ?? []).filter { elements.contains($0.base.elementID) }.compactMap(\.base.id))
}

@Suite("Elements whose painting is animated")
struct AnimatedPaintingTests {
  /// Documents, and the IDs of the elements whose painting can change.
  private static let documents: [(String, Set<String>)] = [
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
    // An animation inside a gradient, a clip path, a mask, a pattern or a filter changes the elements that use it,
    // and not the elements that use other resources.
    (
      #"<linearGradient id="l"><stop id="t" offset="0" stop-color="red"><animate attributeName="stop-color" to="lime" dur="1s"/></stop></linearGradient>"#
        + ##"<rect id="r" width="10" height="10" fill="url(#l)"/><rect id="s" width="10" height="10" fill="red"/>"##,
      ["t", "r"]
    ),
    (
      #"<linearGradient id="l"><animateTransform attributeName="gradientTransform" type="rotate" to="90" dur="1s"/>"#
        + #"<stop offset="0" stop-color="red"/></linearGradient>"#,
      ["l"]
    ),
    (
      #"<clipPath id="c"><rect id="s" width="5" height="5"><animate attributeName="width" to="10" dur="1s"/></rect></clipPath>"#
        + ##"<rect id="r" width="10" height="10" clip-path="url(#c)"/>"##,
      ["s", "r"]
    ),
    (
      #"<style>@keyframes a { to { transform: rotate(90deg) } }</style>"#
        + #"<mask id="m"><rect id="s" width="5" height="5" fill="white" style="animation: a 1s"/></mask>"#
        + ##"<rect id="r" width="10" height="10" mask="url(#m)"/>"##,
      ["r"]
    ),
    (
      #"<pattern id="p" width="10" height="10"><rect id="s" width="5" height="5"><animate attributeName="fill" to="lime" dur="1s"/></rect></pattern>"#
        + ##"<rect id="r" width="10" height="10" fill="url(#p)"/>"##,
      ["s", "r"]
    ),
    (
      #"<filter id="f"><feGaussianBlur id="b" stdDeviation="1"><animate attributeName="stdDeviation" to="8" dur="1s"/></feGaussianBlur></filter>"#
        + #"<filter id="g"><feGaussianBlur stdDeviation="4"/></filter>"#
        + ##"<rect id="r" width="10" height="10" filter="url(#f)"/><g id="h"><rect id="s" width="10" height="10" filter="url(#g)"/></g>"##,
      ["b", "r"]
    ),
    // A gradient that inherits the stops of another one, and a mask whose content uses a filter, change with them.
    (
      #"<linearGradient id="l"><stop id="t" offset="0" stop-color="red"><animate attributeName="stop-color" to="lime" dur="1s"/></stop></linearGradient>"#
        + ##"<linearGradient id="k" href="#l" x2="0.5"/><rect id="r" width="10" height="10" fill="url(#k)"/>"##,
      ["t", "k", "r"]
    ),
    (
      #"<radialGradient id="l"><stop id="t" offset="0" stop-color="red"><animate attributeName="stop-color" to="lime" dur="1s"/></stop></radialGradient>"#
        + ##"<radialGradient id="k" href="#l" r="0.2"/><rect id="r" width="10" height="10" fill="url(#k)"/>"##,
      ["t", "k", "r"]
    ),
    (
      #"<filter id="f"><feGaussianBlur id="b" stdDeviation="1"><animate attributeName="stdDeviation" to="8" dur="1s"/></feGaussianBlur></filter>"#
        + ##"<mask id="m"><rect id="s" width="5" height="5" fill="white" filter="url(#f)"/></mask>"##
        + ##"<rect id="r" width="10" height="10" mask="url(#m)"/>"##,
      ["b", "s", "r"]
    ),
  ]

  @Test("the elements whose painting an animation changes", arguments: documents)
  func elements(content: String, expected: Set<String>) {
    #expect(animated(content) == expected)
  }
}
