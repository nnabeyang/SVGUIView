import Foundation
import Testing

@testable import SVGCore

/// The IDs of the elements of a document with the content whose compositing is animated.
private func animated(_ content: String) -> Set<String> {
  let svg = #"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">"# + content + "</svg>"
  let base = SVGParser.parse(data: Data(svg.utf8))
  let elements = base.elementsWithAnimatedCompositing()
  return Set((base.root?.elements ?? []).filter { elements.contains($0.base.elementID) }.compactMap(\.base.id))
}

/// A rectangle `r` that runs a CSS animation of the keyframes, and a rectangle `s` that doesn't.
private func css(_ keyframes: String) -> String {
  "<style>@keyframes a { " + keyframes + #" }</style><rect id="r" width="10" height="10" style="animation: a 1s"/>"#
    + #"<rect id="s" width="10" height="10"/>"#
}

/// A rectangle `r` with the SMIL animations, and a rectangle `s` without.
private func smil(_ animations: String) -> String {
  #"<rect id="r" width="10" height="10">"# + animations + #"</rect><rect id="s" width="10" height="10"/>"#
}

@Suite("Elements whose compositing is animated")
struct AnimatedCompositingTests {
  /// Documents, and the IDs of the elements whose transform or opacity can change.
  private static let documents: [(String, Set<String>)] = [
    (#"<rect id="r" width="10" height="10"/>"#, []),
    // CSS animations whose keyframes set the transform or the opacity.
    (css("to { transform: rotate(90deg) }"), ["r"]),
    (css("from { opacity: 0 }"), ["r"]),
    (css("to { transform-origin: center }"), ["r"]),
    (css("from { fill: lime } to { opacity: 0.5 }"), ["r"]),
    (css("to { fill: lime }"), []),
    // SMIL animations of the transform, the motion and the opacity.
    (smil(#"<animateTransform attributeName="transform" type="rotate" to="90" dur="1s"/>"#), ["r"]),
    (smil(#"<animateMotion path="M0 0 L10 0" dur="1s"/>"#), ["r"]),
    (smil(#"<animate attributeName="opacity" to="0" dur="1s"/>"#), ["r"]),
    (smil(#"<set attributeName="opacity" to="0" dur="1s"/>"#), ["r"]),
    (smil(#"<animate attributeName="fill" to="lime" dur="1s"/>"#), []),
    // An animation changes the element that it references.
    (smil(##"<animate href="#s" attributeName="opacity" to="0" dur="1s"/>"##), ["s"]),
    (
      #"<linearGradient id="g"><animateTransform attributeName="gradientTransform" type="rotate" to="90" dur="1s"/></linearGradient>"#
        + ##"<rect id="r" width="10" height="10" fill="url(#g)"/>"##, []
    ),
  ]

  @Test("the elements whose transform or opacity an animation changes", arguments: documents)
  func elements(content: String, expected: Set<String>) {
    #expect(animated(content) == expected)
  }
}
