import CoreGraphics
import Foundation
import Testing
import UIKit

@testable import SVGUIView

/// Tests that an app finds and changes the elements of a view's document, and that the view shows the changes.
@MainActor
@Suite("Document API", .serialized)
struct DocumentAPITests {
  /// A document whose square is red, which has no green.
  private static let square = #"""
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" id="root">
      <style>.lime { fill: rgb(0, 255, 0) } @keyframes a { to { opacity: 1 } } .on { animation: a 1s }</style>
      <g id="g" class="a">
        <rect id="square" width="20" height="20" fill="red"/>
        <circle id="c1" r="1" fill="none"/>
      </g>
      <circle id="c2" r="1" fill="none" class="a"/>
    </svg>
    """#

  /// The window of the views, which the suite keeps for the test, since a view only plays in a window.
  private let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 20, height: 20))

  /// A view in a window that has rendered its first image.
  private func makeView(
    _ svg: String = square, animation: SVGUIViewConfiguration.AnimationMode = .none
  ) async throws -> (SVGUIView, ManualClock) {
    let view = SVGUIView(frame: CGRect(x: 0, y: 0, width: 20, height: 20), data: Data(svg.utf8))
    let clock = ManualClock()
    view.clock = clock
    view.isReduceMotionEnabled = { false }
    view.configuration = SVGUIViewConfiguration(timeoutDuration: patience, animation: animation)
    window.addSubview(view)
    view.layoutIfNeeded()
    view.layer.displayIfNeeded()
    try await waitForGreen(in: view) { _ in true }
    return (view, clock)
  }

  /// Lets the run loop display the layer of the view, and waits until the view has shown its renderings.
  ///
  /// The tests don't display the layer themselves: UIKit displays it again at the next commit then.
  private func settle(_ view: SVGUIView) async throws {
    let deadline = ContinuousClock.now + patience
    repeat {
      try await Task.sleep(for: .milliseconds(50))
    } while view.isRendering && ContinuousClock.now < deadline
  }

  private func document(_ svg: String = square) -> SVGDocument {
    SVGUIView(data: Data(svg.utf8)).document
  }

  // MARK: - Finding elements

  @Test("an app finds the root element, elements by their IDs and elements by selectors")
  func findsElements() throws {
    let document = document()
    #expect(document.rootElement?.localName == "svg")
    #expect(document.rootElement == document.element(id: "root"))
    #expect(document.element(id: "square")?.localName == "rect")
    #expect(document.element(id: "none") == nil)
    #expect(try document.querySelectorAll(".a, circle").map { $0.attribute("id") } == ["g", "c1", "c2"])
    #expect(try document.querySelector("circle")?.attribute("id") == "c1")
    #expect(try document.querySelector("line") == nil)
    let g = try #require(document.element(id: "g"))
    #expect(try g.querySelectorAll("circle").map { $0.attribute("id") } == ["c1"])
    #expect(try g.querySelector(".a") == nil)
    #expect(throws: SVGDocument.SelectorError(selectors: "rect >")) {
      try document.querySelectorAll("rect >")
    }
    #expect(throws: SVGDocument.SelectorError(selectors: "")) {
      try g.querySelector("")
    }
  }

  // MARK: - Changing elements

  @Test("an app reads the attributes that it sets and removes at once")
  func attributes() throws {
    let document = document(
      ##"<svg xmlns="http://www.w3.org/2000/svg"><rect id="r"/><use id="u" href="#r"/></svg>"##)
    let rect = try #require(document.element(id: "r"))
    #expect(rect.attribute("fill") == nil)
    rect.setAttribute("fill", to: "lime")
    #expect(rect.attribute("fill") == "lime")
    #expect(document.element(id: "r")?.attribute("fill") == "lime")
    rect.removeAttribute("fill")
    #expect(rect.attribute("fill") == nil)
    // The `href` of the XLink namespace is `href`.
    let use = try #require(document.element(id: "u"))
    #expect(use.attribute("xlink:href") == "#r")
    use.setAttribute("xlink:href", to: "#s")
    #expect(use.attribute("href") == "#s")
    // A new ID finds the element.
    rect.setAttribute("id", to: "s")
    #expect(document.element(id: "s") == rect)
    #expect(document.element(id: "r") == nil)
  }

  @Test("the class list writes each class once, in order, and ignores names that can't be classes")
  func classList() throws {
    let document = document(
      #"<svg xmlns="http://www.w3.org/2000/svg"><rect id="r" class=" b  a b"/><rect id="s"/></svg>"#)
    let classes = try #require(document.element(id: "r")).classList
    #expect(classes.names == ["b", "a"])
    #expect(classes.contains("a"))
    #expect(!classes.contains("") && !classes.contains("a b"))
    classes.add("c", "a", "", "d e")
    #expect(document.element(id: "r")?.attribute("class") == "b a c")
    classes.remove("b", "x")
    #expect(document.element(id: "r")?.attribute("class") == "a c")
    #expect(!classes.toggle("a"))
    #expect(classes.toggle("d"))
    #expect(classes.toggle("d", force: true))
    #expect(!classes.toggle("x", force: false))
    #expect(!classes.toggle(" "))
    #expect(document.element(id: "r")?.attribute("class") == "c d")
    // Removing a class from an element without classes doesn't add the attribute.
    let other = try #require(document.element(id: "s"))
    other.classList.remove("x")
    #expect(other.attribute("class") == nil)
  }

  @Test("the style declares properties in the style attribute and keeps the other declarations")
  func style() throws {
    let document = document(
      #"<svg xmlns="http://www.w3.org/2000/svg"><rect id="r" style="fill: red; opacity:0.5"/></svg>"#)
    let rect = try #require(document.element(id: "r"))
    let style = rect.style
    #expect(style.property("fill") == "red")
    #expect(style.priority("fill") == .normal)
    #expect(style.property("stroke") == nil && style.priority("stroke") == nil)
    style.setProperty("fill", to: "lime", priority: .important)
    #expect(rect.attribute("style") == "fill: lime !important; opacity: 0.5")
    #expect(style.priority("fill") == .important)
    style.setProperty("stroke", to: "blue")
    style.removeProperty("opacity")
    style.removeProperty("missing")
    #expect(rect.attribute("style") == "fill: lime !important; stroke: blue")
  }

  // MARK: - Rendering

  @Test("the view shows the changes of the document at its next rendering")
  func rendersChanges() async throws {
    let (view, _) = try await makeView()
    try await waitForGreen(in: view) { $0 == 0 }
    try #require(view.document.element(id: "square")).classList.add("lime")
    try await waitForGreen(in: view) { $0 == 255 }
  }

  @Test("the changes made in one turn of the run loop are rendered together")
  func rendersChangesTogether() async throws {
    let (view, _) = try await makeView()
    try await settle(view)
    let generation = view.renderingGeneration
    let square = try #require(view.document.element(id: "square"))
    square.setAttribute("fill", to: "rgb(0, 128, 0)")
    square.style.setProperty("fill", to: "rgb(0, 255, 0)")
    try await settle(view)
    #expect(green(in: view) == 255)
    #expect(view.renderingGeneration == generation + 1)
  }

  @Test("a snapshot shows the changes that the view hasn't rendered yet")
  func snapshotShowsChanges() async throws {
    let (view, _) = try await makeView()
    try #require(view.document.element(id: "square")).setAttribute("fill", to: "rgb(0, 255, 0)")
    let image = try #require(try await view.takeSnapshot().cgImage)
    var components = [UInt8](repeating: 0, count: 4)
    let context = try #require(
      CGContext(
        data: &components, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.draw(image, in: CGRect(x: -CGFloat(image.width) / 2, y: -CGFloat(image.height) / 2, width: CGFloat(image.width), height: CGFloat(image.height)))
    #expect(components[1] == 255)
  }

  @Test("new data replaces the document, and the view doesn't show the document that it replaces")
  func newData() async throws {
    let (view, _) = try await makeView()
    let old = view.document
    view.data = Data(Self.square.replacingOccurrences(of: #"fill="red""#, with: #"fill="blue""#).utf8)
    #expect(view.document !== old)
    #expect(view.document.element(id: "square")?.attribute("fill") == "blue")
    try await settle(view)
    let generation = view.renderingGeneration
    try #require(old.element(id: "square")).classList.add("lime")
    #expect(old.element(id: "square")?.attribute("class") == "lime")
    try await settle(view)
    #expect(view.renderingGeneration == generation)
    #expect(green(in: view) == 0)
  }

  @Test("a change that starts an animation starts the clock that stopped at the end of the animations")
  func startsClock() async throws {
    let (view, clock) = try await makeView(animation: .play)
    #expect(!clock.isRunning)
    try #require(view.document.element(id: "square")).classList.add("on")
    try await settle(view)
    #expect(clock.isRunning)
  }
}
