import CoreGraphics
import Foundation
import Testing
import UIKit

@testable import SVGUIView

@Suite("Render tree")
struct RenderTreeBuilderTests {
  /// The render tree of a document rendered into a rectangle of 20 by 20 at a scale of 1.
  private func renderTree(_ content: String) async throws -> RenderTree {
    let svg = #"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20">"# + content + "</svg>"
    let base = SVGParser.parse(data: Data(svg.utf8))
    let builder = RenderTreeBuilder(base: base, viewPort: CGRect(x: 0, y: 0, width: 20, height: 20), scale: 1)
    return try #require(await builder.build(fit: ContentFit(.scaleAspectFit)))
  }

  /// The children of the root `<svg>` element.
  private func children(of tree: RenderTree) throws -> [RenderNode] {
    guard case .viewport(let viewport) = tree.root else {
      Issue.record("The root isn't a viewport")
      return []
    }
    return try #require(viewport.content).children
  }

  private func use(_ node: RenderNode) throws -> UseNode {
    guard case .use(let use) = node else { throw NodeError.unexpected(node) }
    return use
  }

  private func shape(_ node: RenderNode?) throws -> ShapeNode {
    guard case .shape(let shape) = node else { throw NodeError.unexpected(node) }
    return shape
  }

  private enum NodeError: Error {
    case unexpected(RenderNode?)
  }

  @Test("each use element makes its own copy of the content, which keeps the identity of the element")
  func useInstances() async throws {
    let tree = try await renderTree(
      ##"<defs><rect id="r" width="10" height="10"/></defs><use href="#r"/><use href="#r" x="10"/>"##)
    let nodes = try children(of: tree)
    #expect(nodes.count == 3)
    let first = try use(nodes[1])
    let second = try use(nodes[2])
    let firstShape = try shape(try #require(first.instance).content)
    let secondShape = try shape(try #require(second.instance).content)
    #expect(firstShape.id.element == secondShape.id.element)
    #expect(firstShape.id.instance == [first.id.element])
    #expect(secondShape.id.instance == [second.id.element])
    #expect(firstShape.id != secondShape.id)
    #expect(try #require(second.instance).translation == CGAffineTransform(translationX: 10, y: 0))
  }

  @Test("a use element that references an element that contains it shows nothing")
  func useCycle() async throws {
    let tree = try await renderTree(##"<g id="g"><use href="#g"/></g>"##)
    guard case .group(let group) = try children(of: tree).first else {
      Issue.record("The first child isn't a group")
      return
    }
    #expect(try use(try #require(group.children.first)).instance == nil)
  }

  @Test("a gradient takes the stops of the gradient that it references")
  func gradientReference() async throws {
    let tree = try await renderTree(
      ##"""
      <linearGradient id="a"><stop offset="0" stop-color="lime"/><stop offset="1" stop-color="blue"/></linearGradient>
      <linearGradient id="b" href="#a" x2="0" y2="1"/>
      <rect width="20" height="20" fill="url(#b)"/>
      """##)
    let rect = try shape(try children(of: tree).last)
    guard case .vector(.gradient(.linear(let gradient)), _, _) = rect.content else {
      Issue.record("The rectangle isn't filled with a linear gradient")
      return
    }
    #expect(gradient.colors.count == 2)
    #expect(gradient.locations == [0, 1])
    #expect(gradient.x2 == 0)
    #expect(gradient.y2 == 1)
  }

  @Test("lengths in percentages and text scale with the viewBox of a nested svg element")
  func nestedViewBox() async throws {
    let tree = try await renderTree(
      #"<svg width="20" height="20" viewBox="0 0 10 10"><rect width="50%" height="50%"/></svg>"#)
    guard case .viewport(let nested) = try children(of: tree).first else {
      Issue.record("The first child isn't a viewport")
      return
    }
    let rect = try shape(try #require(nested.content).children.first)
    #expect(try #require(rect.geometry).frame == CGRect(x: 0, y: 0, width: 5, height: 5))
  }

  @Test("a group with a clip path finds its bounds without the shapes of patterns and masks")
  func clippedGroupWithPattern() async throws {
    let tree = try await renderTree(
      #"""
      <clipPath id="c"><rect width="10" height="10"/></clipPath>
      <g clip-path="url(#c)">
        <g><pattern id="p" width="2" height="2"/><mask id="m"/></g>
        <rect x="5" y="5" width="10" height="10"/>
      </g>
      """#)
    guard case .group(let group) = try children(of: tree).last else {
      Issue.record("The last child isn't a group")
      return
    }
    #expect(try #require(group.clip).frame == CGRect(x: 0, y: 0, width: 15, height: 15))
  }
}
