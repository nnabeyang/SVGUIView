import CoreGraphics
import Foundation
import Testing

@testable import SVGCore

/// A document with the given content at the time.
private func document(_ content: String, at time: Double) -> SVGBaseContext {
  let svg = #"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">"# + content + "</svg>"
  return SVGParser.parse(data: Data(svg.utf8)).at(time: time)
}

/// The element with the ID `e` at the time.
private func element<T>(_ content: String, at time: Double, as _: T.Type) throws -> T {
  try #require(document(content, at: time)["e"] as? T)
}

@Suite("SMIL animations of attributes")
struct SMILAttributeTests {
  /// Circles with animations of their radius, times, and the radius then.
  private static let radii: [(String, Double, SVGLength?)] = [
    (#"<circle id="e" r="10"><animate attributeName="r" from="10" to="30" dur="2s"/></circle>"#, 1, .number(20)),
    // A to-animation starts from the attribute, and from 0 without one.
    (#"<circle id="e" r="10"><animate attributeName="r" to="30" dur="2s"/></circle>"#, 1, .number(20)),
    (#"<circle id="e"><animate attributeName="r" to="30" dur="2s"/></circle>"#, 1, .number(15)),
    (#"<circle id="e" r="10"><animate attributeName="r" by="10" dur="2s" fill="freeze"/></circle>"#, 3, .number(20)),
    (
      #"<circle id="e" r="10"><animate attributeName="r" from="0" to="10" dur="2s" additive="sum"/></circle>"#, 1,
      .number(15)
    ),
    (#"<circle id="e" r="10"><set attributeName="r" to="5px" begin="1s"/></circle>"#, 2, .pixel(5)),
    // Without an effect, the attribute is the one in the document.
    (#"<circle id="e" r="10"><animate attributeName="r" from="0" to="30" dur="1s"/></circle>"#, 2, .number(10)),
    (#"<circle id="e" r="10"><animate attributeName="r" from="0" to="x" dur="1s"/></circle>"#, 0.5, .number(10)),
  ]

  @Test("SMIL animations change lengths that aren't properties", arguments: radii)
  func lengths(content: String, time: Double, radius: SVGLength?) throws {
    #expect(try element(content, at: time, as: SVGCircleElement.self).r == radius)
  }

  @Test("lengths of other elements change too")
  func otherLengths() throws {
    let line = try element(
      #"<line id="e" x1="0" x2="10"><animate attributeName="x1" to="20" dur="2s"/></line>"#, at: 1,
      as: SVGLineElement.self)
    #expect(line.x1 == .number(10))
    let text = try element(
      #"<text id="e" x="0">A<animate attributeName="x" values="0;40" dur="2s"/></text>"#, at: 0.5,
      as: SVGTextElement.self)
    #expect(text.x == .number(10))
    #expect(text.text == "A")
    let image = try element(
      #"<image id="e" width="10"><animate attributeName="width" to="50" dur="2s"/></image>"#, at: 1,
      as: SVGImageElement.self)
    #expect(image.width == .number(30))
  }

  @Test("lists of numbers are interpolated when they have the same lengths")
  func numbers() throws {
    let polygon = try element(
      #"<polygon id="e" points="0,0 10,0 10,10"><animate attributeName="points" to="0,0 20,0 20,20" dur="2s"/></polygon>"#,
      at: 1, as: SVGPolygonElement.self)
    #expect(polygon.points.points == [CGPoint(x: 0, y: 0), CGPoint(x: 15, y: 0), CGPoint(x: 15, y: 15)])
    let viewport = try element(
      #"<svg id="e" width="10" height="10" viewBox="0 0 10 10"><animate attributeName="viewBox" to="0 0 20 40" dur="2s"/></svg>"#,
      at: 1, as: SVGSVGElement.self)
    #expect(viewport.viewBox?.toCGRect() == CGRect(x: 0, y: 0, width: 15, height: 25))
    // Lists of different lengths change discretely.
    let discrete = try element(
      #"<polygon id="e" points="0,0 10,0 10,10"><animate attributeName="points" to="0,0 20,0" dur="2s"/></polygon>"#,
      at: 1.5, as: SVGPolygonElement.self)
    #expect(discrete.points.points == [CGPoint(x: 0, y: 0), CGPoint(x: 20, y: 0)])
  }

  @Test("other attributes change discretely, and classes change the rules that match")
  func discreteAttributes() throws {
    let use = try element(
      ##"""
      <defs><rect id="a" width="10" height="10"/><circle id="b" r="5"/></defs>
      <use id="e" href="#a"><animate attributeName="href" values="#a;#b" dur="2s"/></use>
      """##, at: 1.5, as: SVGUseElement.self)
    #expect(use.parentId == "b")
    let rect = try element(
      #"""
      <style>.on { fill: green }</style>
      <rect id="e" width="10" height="10" fill="red"><set attributeName="class" to="on" begin="1s"/></rect>
      """#, at: 2, as: SVGRectElement.self)
    guard case .color(let fill) = rect.style.fill else {
      Issue.record("The fill isn't a color")
      return
    }
    #expect(fill.components?.green ?? 0 > 0.4)
  }

  @Test("attributes and properties change together, and the document stays the same")
  func attributesAndProperties() throws {
    let content =
      #"<circle id="e" r="10"><animate attributeName="r" to="30" dur="2s"/><animate attributeName="opacity" to="0" dur="2s"/></circle>"#
    let base = SVGParser.parse(
      data: Data((#"<svg xmlns="http://www.w3.org/2000/svg">"# + content + "</svg>").utf8))
    let circle = try #require(base.at(time: 1)["e"] as? SVGCircleElement)
    #expect(circle.r == .number(20))
    #expect(abs(circle.style.opacity - 0.5) < 1e-9)
    #expect(try #require(base.at(time: 0.5)["e"] as? SVGCircleElement).r == .number(15))
    #expect(base.document.root?.children.first?.attributes["r"] == "10")
  }

  @Test("the copies of an element in use elements have its animated attributes")
  func useInstances() async throws {
    let base = document(
      ##"<defs><circle id="c" r="10"><animate attributeName="r" to="30" dur="2s"/></circle></defs><use id="e" href="#c"/>"##,
      at: 1)
    #expect((base["c"] as? SVGCircleElement)?.r == .number(20))
  }
}
