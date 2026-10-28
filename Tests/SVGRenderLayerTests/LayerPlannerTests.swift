import CoreGraphics
import Foundation
import Testing

@testable import SVGCore
@testable import SVGRenderLayer

/// The layers of a document with the content, rendered into a rectangle of 100 by 100 at the scale.
private func plan(
  _ content: String, viewBox: String = "0 0 100 100", scale: CGFloat = 1
) async throws -> (ContainerLayer, SVGBaseContext) {
  let svg = #"<svg xmlns="http://www.w3.org/2000/svg" viewBox=""# + viewBox + #"">"# + content + "</svg>"
  let base = SVGParser.parse(data: Data(svg.utf8))
  let rect = CGRect(x: 0, y: 0, width: 100, height: 100)
  let fit = ContentFit(
    preserveAspectRatio: PreserveAspectRatio(xAlign: .mid, yAlign: .mid, option: .meet), stretches: false, scales: true)
  let tree = try #require(await RenderTreeBuilder(base: base.at(time: 0), viewPort: rect, scale: scale).build(fit: fit))
  let planner = LayerPlanner(
    promoted: base.elementsWithAnimatedCompositing(), painting: base.elementsWithAnimatedPainting(), scale: scale)
  return (planner.plan(tree, in: rect), base)
}

/// The layers as text: a container is the ID or the name of its element, or `clip`, with its opacity if it isn't 1
/// and its layers in parentheses, and a painted layer is the IDs or the names of its nodes in brackets, followed by
/// `*` if it changes and `marksChanges` is `true`.
private func describe(_ layer: PlannedLayer, in base: SVGBaseContext, marksChanges: Bool = false) -> String {
  let elements = base.root?.elements ?? []
  func name(_ id: ElementID) -> String {
    guard let element = elements.first(where: { $0.base.elementID == id }) else { return "?" }
    return element.base.id ?? element.base.name.rawValue
  }
  switch layer {
  case .container(let container):
    let label = container.id.map { name($0.element) } ?? (container.clip == nil ? "-" : "clip")
    let opacity = container.opacity == 1 ? "" : "@\(container.opacity)"
    let children = container.children.map { describe($0, in: base, marksChanges: marksChanges) }
    return label + opacity + "(" + children.joined(separator: " ") + ")"
  case .painted(let painted):
    let mark = marksChanges && painted.changes ? "*" : ""
    return "[" + painted.nodes.map { name($0.id.element) }.joined(separator: " ") + "]" + mark
  }
}

/// A style sheet with keyframes `s` that rotate an element.
private let spin = "<style>@keyframes s { to { transform: rotate(90deg) } }</style>"
/// A rectangle with the ID whose rotation is animated.
private func spinning(_ id: String, _ attributes: String = "") -> String {
  #"<rect id=""# + id + #"" width="10" height="10" style="animation: s 1s" "# + attributes + "/>"
}

/// A filter `p` whose blur is animated.
private let pulse =
  #"<filter id="p"><feGaussianBlur stdDeviation="1"><animate attributeName="stdDeviation" to="4" dur="1s"/>"#
  + "</feGaussianBlur></filter>"

/// The painted layers in a layer and the layers in it, in order.
private func paintedLayers(of layer: PlannedLayer) -> [PaintedLayer] {
  switch layer {
  case .container(let container): container.children.flatMap(paintedLayers)
  case .painted(let painted): [painted]
  }
}

@Suite("Planning layers")
struct LayerPlannerTests {
  /// Documents, and their layers as text.
  private static let documents: [(String, String)] = [
    // Without animations, everything is painted together.
    (#"<rect id="a" width="10" height="10"/><rect id="b" width="10" height="10"/>"#, "clip(-([svg]))"),
    // An element whose transform is animated gets a layer between the ones painted before and after it.
    (
      spin + #"<rect id="a" width="10" height="10"/>"# + spinning("r") + #"<rect id="b" width="10" height="10"/>"#,
      "clip(-(svg([a] r([r]) [b])))"
    ),
    // A group around it becomes a container with its opacity.
    (
      spin + #"<g id="g" opacity="0.5"><rect id="a" width="10" height="10"/>"# + spinning("r") + "</g>",
      "clip(-(svg(g@0.5([a] r([r])))))"
    ),
    // Inside a clip path, a mask or a filter, it's painted with the element that composites it.
    (
      spin + ##"<clipPath id="c"><rect width="5" height="5"/></clipPath><g id="g" clip-path="url(#c)">"##
        + spinning("r") + "</g>",
      "clip(-([svg]))"
    ),
    (
      spin + ##"<mask id="m"><rect width="5" height="5" fill="white"/></mask><g id="g" mask="url(#m)">"##
        + spinning("r") + "</g>",
      "clip(-([svg]))"
    ),
    // The element with the filter is painted into a layer of its own, since what it filters moves.
    (
      spin + ##"<filter id="f"><feGaussianBlur stdDeviation="1"/></filter><g id="g" filter="url(#f)">"##
        + spinning("r") + "</g>",
      "clip(-(svg([g])))"
    ),
    // An animated element with a clip path is painted in its layer with it.
    (
      spin + #"<clipPath id="c"><rect width="5" height="5"/></clipPath>"# + spinning("r", ##"clip-path="url(#c)""##),
      "clip(-(svg(r([r]))))"
    ),
    // The content of a nested viewport is clipped to it.
    (
      spin + #"<svg id="v" x="10" y="10" width="50" height="50" viewBox="0 0 10 10">"# + spinning("r") + "</svg>",
      "clip(-(svg(v(clip(r([r]))))))"
    ),
    // The content of a `<use>` is in a container with its translation and opacity.
    (
      spin + "<defs>" + spinning("d") + ##"</defs><use id="u" href="#d" x="5" opacity="0.5"/>"##,
      "clip(-(svg(u@0.5(d([d])))))"
    ),
  ]

  @Test("the layers of a document", arguments: documents)
  func layers(content: String, expected: String) async throws {
    let (layer, base) = try await plan(content)
    #expect(describe(.container(layer), in: base) == expected)
  }

  @Test("the layers keep the transforms and the opacities of the nodes")
  func compositing() async throws {
    let (layer, _) = try await plan(
      spin + #"<g transform="translate(10 0)">"# + spinning("r", #"transform="translate(0 5)" opacity="0.25""#)
        + "</g>")
    guard case .container(let fit) = layer.children.first, case .container(let svg) = fit.children.first,
      case .container(let group) = svg.children.first, case .container(let rect) = group.children.first,
      case .painted(let painted) = rect.children.first, case .shape(let shape) = painted.nodes.first
    else {
      Issue.record("The layers aren't nested as expected")
      return
    }
    #expect(group.transform == CGAffineTransform(translationX: 10, y: 0))
    #expect(rect.transform == CGAffineTransform(translationX: 0, y: 5))
    #expect(rect.opacity == 0.25)
    // The node paints without them, in the coordinates of its layer.
    #expect(shape.transform == .identity)
    #expect(shape.opacity == 1)
  }

  @Test("the contents are as sharp as a rendering into one bitmap")
  func rasterScale() async throws {
    let (layer, _) = try await plan(spin + spinning("r"), viewBox: "0 0 10 10", scale: 2)
    #expect(paintedLayers(of: .container(layer)).map(\.rasterScale) == [CGSize(width: 20, height: 20)])
    // A transform that scales the axes differently scales the pixels of each axis, which lie on the pixels of the
    // screen.
    let (scaled, _) = try await plan(
      spin + #"<g transform="scale(2, 3)"><rect x="0.3" y="0.3" width="2" height="2"/>"# + spinning("r") + "</g>",
      viewBox: "0 0 10 10", scale: 2)
    let painted = try #require(paintedLayers(of: .container(scaled)).first)
    #expect(painted.rasterScale == CGSize(width: 40, height: 60))
    let pixels = painted.bounds.applying(CGAffineTransform(scaleX: 40, y: 60))
    #expect(pixels == pixels.integral)
  }

  @Test("a painted layer that doesn't move covers only what shows in the view, and one that moves covers everything")
  func bounds() async throws {
    let (layer, _) = try await plan(
      spin + #"<rect x="-50" y="-50" width="200" height="200"/>"#
        + #"<rect id="r" x="-50" width="200" height="10" style="animation: s 1s"/>"#)
    let bounds = paintedLayers(of: .container(layer)).map(\.bounds)
    // The margin is two pixels for the antialiased edges.
    #expect(bounds == [CGRect(x: -2, y: -2, width: 104, height: 104), CGRect(x: -52, y: -2, width: 204, height: 14)])
  }

  /// Documents, and their layers as text with the painted layers that change marked.
  private static let changes: [(String, String)] = [
    // The layers around a moving element, and the element in its layer, don't change.
    (
      spin + #"<rect id="a" width="10" height="10"/>"# + spinning("r") + #"<rect id="b" width="10" height="10"/>"#,
      "clip(-(svg([a] r([r]) [b])))"
    ),
    // A layer with an element whose fill changes does.
    (
      spin + "<style>@keyframes c { to { fill: lime } }</style>"
        + #"<rect id="a" width="10" height="10" style="animation: c 1s"/>"# + spinning("r"),
      "clip(-(svg([a]* r([r]))))"
    ),
    (
      spin + "<style>@keyframes c { to { fill: lime } }</style>"
        + #"<rect id="r" width="10" height="10" style="animation: s 1s, c 1s"/>"#,
      "clip(-(svg(r([r]*))))"
    ),
    // The fill of a group changes the elements in it.
    (
      spin + "<style>@keyframes c { to { fill: lime } }</style>"
        + #"<g id="g" style="animation: c 1s"><rect id="a" width="10" height="10"/>"# + spinning("r") + "</g>",
      "clip(-(svg(g([a]* r([r]*)))))"
    ),
    // A moving element that doesn't get a layer of its own changes the layer that it's painted in.
    (
      spin + ##"<clipPath id="c"><rect width="5" height="5"/></clipPath><g id="g" clip-path="url(#c)">"##
        + spinning("r") + "</g>",
      "clip(-([svg]*))"
    ),
    // An animation in a gradient changes only the layers of the elements that use it.
    (
      spin + #"<linearGradient id="l"><stop offset="0" stop-color="red">"#
        + #"<animate attributeName="stop-color" to="lime" dur="1s"/></stop></linearGradient>"#
        + ##"<rect id="a" width="10" height="10" fill="url(#l)"/>"## + spinning("r")
        + #"<rect id="b" width="10" height="10"/>"#,
      "clip(-(svg([a]* r([r]) [b])))"
    ),
    // A moving element with a filter keeps its contents, unless the filter changes.
    (
      spin + #"<filter id="f"><feGaussianBlur stdDeviation="1"/></filter>"#
        + ##"<rect id="r" width="10" height="10" filter="url(#f)" style="animation: s 1s"/>"##,
      "clip(-(svg(r([r]))))"
    ),
    (
      spin + #"<filter id="f"><feGaussianBlur stdDeviation="1"><animate attributeName="stdDeviation" to="4" dur="1s"/>"#
        + "</feGaussianBlur></filter>"
        + ##"<rect id="r" width="10" height="10" filter="url(#f)" style="animation: s 1s"/>"##,
      "clip(-(svg(r([r]*))))"
    ),
    // An element whose filter changes is painted into a layer of its own, between the layers of the elements around
    // it, which don't change.
    (
      pulse + #"<rect id="a" width="10" height="10"/>"#
        + ##"<rect id="f" width="10" height="10" filter="url(#p)"/><rect id="b" width="10" height="10"/>"##,
      "clip(-(svg([p a] [f]* [b])))"
    ),
    // One whose filter doesn't change is painted with them.
    (
      pulse + #"<filter id="still"><feGaussianBlur stdDeviation="1"/></filter><rect id="a" width="10" height="10"/>"#
        + ##"<rect id="f" width="10" height="10" filter="url(#still)"/><rect id="b" width="10" height="10"/>"##,
      "clip(-([svg]))"
    ),
    // A group around it becomes a container.
    (
      pulse + #"<g id="g" opacity="0.5"><rect id="a" width="10" height="10"/>"#
        + ##"<rect id="f" width="10" height="10" filter="url(#p)"/></g><rect id="b" width="10" height="10"/>"##,
      "clip(-(svg(g@0.5([a] [f]*) [b])))"
    ),
    // Inside a clip path, it's painted with the element that composites it.
    (
      pulse + ##"<clipPath id="c"><rect width="5" height="5"/></clipPath><g id="g" clip-path="url(#c)">"##
        + ##"<rect id="a" width="10" height="10"/><rect id="f" width="10" height="10" filter="url(#p)"/></g>"##,
      "clip(-([svg]*))"
    ),
    // A filter whose content changes changes too, and so does one whose content moves.
    (
      "<style>@keyframes c { to { fill: lime } }</style>"
        + #"<filter id="still"><feGaussianBlur stdDeviation="1"/></filter><rect id="a" width="10" height="10"/>"#
        + ##"<g id="f" filter="url(#still)"><rect id="c" width="10" height="10" style="animation: c 1s"/></g>"##,
      "clip(-(svg([still a] [f]*)))"
    ),
    (
      spin + #"<filter id="still"><feGaussianBlur stdDeviation="1"/></filter><rect id="a" width="10" height="10"/>"#
        + ##"<g id="f" filter="url(#still)">"## + spinning("r") + "</g>",
      "clip(-(svg([still a] [f]*)))"
    ),
  ]

  @Test("the painted layers that change", arguments: changes)
  func changingLayers(content: String, expected: String) async throws {
    let (layer, base) = try await plan(content)
    #expect(describe(.container(layer), in: base, marksChanges: true) == expected)
  }
}
