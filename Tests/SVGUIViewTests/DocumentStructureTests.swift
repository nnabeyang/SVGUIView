import CoreGraphics
import Foundation
import Testing
import UIKit

@testable import SVGUIView

extension SVGDocument {
  /// A new element with attributes.
  fileprivate func make(_ localName: String, _ attributes: KeyValuePairs<String, String> = [:]) -> Element {
    let element = createElement(localName)
    for (name, value) in attributes {
      element.setAttribute(name, to: value)
    }
    return element
  }

  /// The element with an `id` attribute, which the document must have.
  fileprivate func require(_ id: String, sourceLocation: SourceLocation = #_sourceLocation) throws -> Element {
    try #require(element(id: id), "The document has no element \(id)", sourceLocation: sourceLocation)
  }
}

/// A change of the tree of a document, and the document as it's written with the change.
struct StructureChange: Sendable, CustomTestStringConvertible {
  let testDescription: String
  /// The content of the document before the change.
  let before: String
  /// The content of the document as it's written with the change.
  let after: String
  let change: @MainActor @Sendable (SVGDocument) throws -> Void

  init(
    _ description: String, before: String, after: String,
    change: @escaping @MainActor @Sendable (SVGDocument) throws -> Void
  ) {
    testDescription = description
    self.before = before
    self.after = after
    self.change = change
  }
}

/// Tests that an app inserts, removes and moves the elements of a view's document, and that the view shows the
/// document as it shows the document written with the changes.
@MainActor
@Suite("Document structure API", .serialized, .timeLimit(.minutes(2)))
struct DocumentStructureTests {
  nonisolated private static let content = """
    <g id="a" fill="red"><rect id="a1" width="10" height="10"/><rect id="a2" x="5" width="10" height="10"/></g>\
    <g id="b" fill="blue"><rect id="b1" y="10" width="10" height="10"/></g>
    """

  private func makeView(_ content: String) -> SVGUIView {
    let view = SVGUIView(frame: CGRect(x: 0, y: 0, width: 20, height: 20), data: Data(document(content).utf8))
    view.configuration = SVGUIViewConfiguration(timeoutDuration: patience)
    return view
  }

  // MARK: - The tree

  @Test("an app walks the parents and the children of the elements")
  func walksTree() throws {
    let document = makeView(Self.content).document
    let root = try #require(document.rootElement)
    #expect(root.parent == nil)
    #expect(root.isConnected)
    #expect(root.children.map { $0.attribute("id") } == ["a", "b"])
    let a2 = try document.require("a2")
    #expect(a2.parent == (try document.require("a")))
    #expect(a2.children.isEmpty)
    #expect(a2.isConnected)
  }

  @Test("a created element isn't in the tree until it's inserted, and is read and changed as other elements")
  func createsElements() throws {
    let document = makeView(Self.content).document
    let circle = document.createElement("circle")
    #expect(circle.localName == "circle")
    #expect(!circle.isConnected)
    #expect(circle.parent == nil)
    #expect(circle.children.isEmpty)
    circle.setAttribute("id", to: "c")
    circle.classList.add("on")
    circle.style.setProperty("fill", to: "lime")
    #expect(circle.attribute("class") == "on")
    #expect(circle.style.property("fill") == "lime")
    #expect(document.element(id: "c") == nil)
    #expect(document.createElement("circle") != circle)

    try document.require("a").append(circle)
    #expect(circle.isConnected)
    #expect(circle.parent == (try document.require("a")))
    #expect(document.element(id: "c") == circle)
    #expect(try document.require("a").children.map { $0.attribute("id") } == ["a1", "a2", "c"])
  }

  @Test("an element is inserted before a child, or after the last one")
  func inserts() throws {
    let document = makeView(Self.content).document
    let a = try document.require("a")
    try a.insert(document.make("circle", ["id": "first"]), before: try document.require("a1"))
    try a.insert(document.make("circle", ["id": "middle"]), before: try document.require("a2"))
    try a.insert(document.make("circle", ["id": "last"]), before: nil)
    #expect(a.children.map { $0.attribute("id") } == ["first", "a1", "middle", "a2", "last"])
  }

  @Test("an element that has a parent is moved, also among the children of its parent")
  func moves() throws {
    let document = makeView(Self.content).document
    let a = try document.require("a")
    let b = try document.require("b")
    let a1 = try document.require("a1")
    try b.append(a1)
    #expect(a.children.map { $0.attribute("id") } == ["a2"])
    #expect(b.children.map { $0.attribute("id") } == ["b1", "a1"])
    #expect(a1.parent == b)
    // To the front of its own parent, and back.
    try b.append(try document.require("b1"))
    #expect(b.children.map { $0.attribute("id") } == ["a1", "b1"])
    try b.insert(try document.require("b1"), before: a1)
    #expect(b.children.map { $0.attribute("id") } == ["b1", "a1"])
    // An element that is inserted before itself stays where it is.
    try b.insert(a1, before: a1)
    try b.insert(try document.require("b1"), before: try document.require("b1"))
    #expect(b.children.map { $0.attribute("id") } == ["b1", "a1"])
  }

  @Test("a removed element is kept with its descendants, and is inserted again as the same element")
  func removes() throws {
    let document = makeView(Self.content).document
    let a = try document.require("a")
    let a1 = try document.require("a1")
    a.remove()
    #expect(!a.isConnected)
    #expect(!a1.isConnected)
    #expect(a.parent == nil)
    #expect(a1.parent == a)
    #expect(document.element(id: "a1") == nil)
    #expect(try document.rootElement?.children.map { $0.attribute("id") } == ["b"])
    // The removed elements are read and changed, and found among the descendants of the removed element.
    #expect(a.children.map { $0.attribute("id") } == ["a1", "a2"])
    #expect(try a.querySelectorAll("rect") == a.children)
    a1.setAttribute("fill", to: "lime")
    a1.remove()
    #expect(a.children.map { $0.attribute("id") } == ["a2"])
    #expect(a1.parent == nil)
    try a.append(a1)
    // Removing an element that has no parent does nothing.
    a.remove()
    try document.rootElement?.insert(a, before: try document.require("b"))
    #expect(a1.isConnected)
    #expect(a1.attribute("fill") == "lime")
    #expect(document.element(id: "a1") == a1)
    #expect(try document.rootElement?.children.map { $0.attribute("id") } == ["a", "b"])
  }

  @Test("the root element stays where it is")
  func rootElement() throws {
    let document = makeView(Self.content).document
    let root = try #require(document.rootElement)
    root.remove()
    #expect(document.rootElement == root)
    #expect(root.isConnected)
    #expect(throws: SVGDocument.HierarchyError(reason: .rootElement)) {
      try document.createElement("g").append(root)
    }
  }

  @Test("an element can't be inserted in itself, in a descendant, in another document or before another element's child")
  func hierarchyErrors() throws {
    let document = makeView(Self.content).document
    let a = try document.require("a")
    let a1 = try document.require("a1")
    #expect(throws: SVGDocument.HierarchyError(reason: .containsParent)) { try a.append(a) }
    #expect(throws: SVGDocument.HierarchyError(reason: .containsParent)) { try a1.append(a) }
    let group = document.make("g")
    let child = document.make("g")
    try group.append(child)
    #expect(throws: SVGDocument.HierarchyError(reason: .containsParent)) { try child.append(group) }
    #expect(throws: SVGDocument.HierarchyError(reason: .referenceNotChild)) {
      try a.insert(document.createElement("circle"), before: try document.require("b1"))
    }
    #expect(throws: SVGDocument.HierarchyError(reason: .referenceNotChild)) {
      try a.insert(document.createElement("circle"), before: document.createElement("circle"))
    }
    let other = makeView(Self.content).document
    #expect(throws: SVGDocument.HierarchyError(reason: .differentDocument)) {
      try a.append(other.createElement("circle"))
    }
    #expect(throws: SVGDocument.HierarchyError(reason: .differentDocument)) {
      try a.insert(document.createElement("circle"), before: try other.require("a1"))
    }
    // The document is as it was.
    #expect(a.children.map { $0.attribute("id") } == ["a1", "a2"])
    #expect(a.parent == document.rootElement)
  }

  // MARK: - Rendering

  nonisolated private static let style = "<style>rect + rect { fill: lime } rect:first-child { stroke: black } g:empty + g { opacity: 0.5 }</style>"
  nonisolated private static let siblings = "<style>rect + rect { fill: lime } rect ~ circle { fill: blue }</style>"
  nonisolated private static let keyframes = "<style>@keyframes k { to { fill: lime } } .on { animation: k 1s linear }</style>"

  nonisolated private static let changes: [StructureChange] = [
    StructureChange(
      "an appended shape", before: content,
      after: content + #"<circle cx="15" cy="15" r="4" fill="lime"/>"#
    ) { document in
      try document.rootElement?.append(document.make("circle", ["cx": "15", "cy": "15", "r": "4", "fill": "lime"]))
    },
    StructureChange(
      "a shape inserted before its siblings, which inherits from its parent", before: content,
      after: content.replacingOccurrences(of: #"<rect id="a1""#, with: #"<circle cx="8" cy="5" r="6"/><rect id="a1""#)
    ) { document in
      try document.require("a").insert(
        document.make("circle", ["cx": "8", "cy": "5", "r": "6"]), before: try document.require("a1"))
    },
    StructureChange(
      "a removed shape", before: content,
      after: content.replacingOccurrences(of: #"<rect id="a2" x="5" width="10" height="10"/>"#, with: "")
    ) { document in
      try document.require("a2").remove()
    },
    StructureChange(
      "a shape brought to the front", before: #"<g fill="blue">"# + content + "</g>",
      after: #"<g fill="blue"><g id="b" fill="blue"><rect id="b1" y="10" width="10" height="10"/></g>"#
        + #"<g id="a" fill="red"><rect id="a2" x="5" width="10" height="10"/><rect id="a1" width="10" height="10"/></g></g>"#
    ) { document in
      try document.require("a").append(try document.require("a1"))
      try document.require("a").parent?.append(try document.require("a"))
    },
    StructureChange(
      "a shape moved to another group, which it inherits from", before: content,
      after: #"<g id="a" fill="red"><rect id="a1" width="10" height="10"/></g>"#
        + #"<g id="b" fill="blue"><rect id="a2" x="5" width="10" height="10"/><rect id="b1" y="10" width="10" height="10"/></g>"#
    ) { document in
      try document.require("b").insert(try document.require("a2"), before: try document.require("b1"))
    },
    StructureChange(
      "a group made with its children before it's inserted", before: content,
      after: content + #"<g fill="lime" transform="translate(10 10)"><rect width="5" height="5"/><circle r="3"/></g>"#
    ) { document in
      let group = document.make("g", ["fill": "lime", "transform": "translate(10 10)"])
      try group.append(document.make("circle", ["r": "3"]))
      try group.insert(document.make("rect", ["width": "5", "height": "5"]), before: group.children.first)
      try document.rootElement?.append(group)
    },
    StructureChange(
      "an element changed after it's inserted, and one removed and inserted again", before: content,
      after: content.replacingOccurrences(of: #"<rect id="a2" x="5""#, with: #"<rect id="a2" x="5" fill="lime""#)
        + #"<circle r="5" fill="lime"/>"#
    ) { document in
      let circle = document.createElement("circle")
      try document.rootElement?.append(circle)
      circle.setAttribute("r", to: "5")
      circle.setAttribute("fill", to: "lime")
      let a2 = try document.require("a2")
      a2.remove()
      a2.setAttribute("fill", to: "lime")
      try document.require("a").append(a2)
      // An element that is inserted and removed again leaves nothing.
      let other = document.make("rect", ["width": "20", "height": "20"])
      try document.rootElement?.append(other)
      other.remove()
    },
    StructureChange(
      "a gradient that a shape refers to",
      before: #"<defs id="defs"/><rect width="20" height="20" fill="url(#gradient) red"/>"#,
      after: #"<defs id="defs"><linearGradient id="gradient"><stop stop-color="lime"/><stop offset="1" stop-color="blue"/></linearGradient></defs>"#
        + #"<rect width="20" height="20" fill="url(#gradient) red"/>"#
    ) { document in
      let gradient = document.make("linearGradient", ["id": "gradient"])
      try gradient.append(document.make("stop", ["stop-color": "lime"]))
      try gradient.append(document.make("stop", ["offset": "1", "stop-color": "blue"]))
      try document.require("defs").append(gradient)
    },
    StructureChange(
      "a removed clip path that a shape refers to",
      before: #"<clipPath id="clip"><circle cx="10" cy="10" r="5"/></clipPath><rect width="20" height="20" clip-path="url(#clip)"/>"#,
      after: #"<rect width="20" height="20" clip-path="url(#clip)"/>"#
    ) { document in
      try document.require("clip").remove()
    },
    StructureChange(
      "the element that a use element shows", before: ##"<defs id="defs"/><use href="#shape" x="5" fill="lime"/>"##,
      after: ##"<defs id="defs"><rect id="shape" width="10" height="10"/></defs><use href="#shape" x="5" fill="lime"/>"##
    ) { document in
      try document.require("defs").append(document.make("rect", ["id": "shape", "width": "10", "height": "10"]))
    },
    StructureChange(
      "a SMIL animation", before: #"<rect id="r" width="20" height="20" fill="red"/>"#,
      after: #"<rect id="r" width="20" height="20" fill="red"><animate attributeName="width" from="5" to="20" dur="1s"/></rect>"#
    ) { document in
      try document.require("r").append(
        document.make("animate", ["attributeName": "width", "from": "5", "to": "20", "dur": "1s"]))
    },
    StructureChange(
      "a removed SMIL animation",
      before: #"<rect id="r" width="20" height="20" fill="red"><animate id="animation" attributeName="width" from="5" to="20" dur="1s"/></rect>"#,
      after: #"<rect id="r" width="20" height="20" fill="red"/>"#
    ) { document in
      try document.require("animation").remove()
    },
    StructureChange(
      "an element with a CSS animation", before: keyframes + #"<g id="g"/>"#,
      after: keyframes + #"<g id="g"><rect width="20" height="20" fill="red" class="on"/></g>"#
    ) { document in
      try document.require("g").append(document.make("rect", ["width": "20", "height": "20", "fill": "red", "class": "on"]))
    },
    StructureChange(
      "an element inserted before siblings that sibling combinators and :first-child match", before: style + content,
      after: style
        + content.replacingOccurrences(of: #"<rect id="a1""#, with: #"<rect x="2" y="2" width="6" height="16"/><rect id="a1""#)
    ) { document in
      try document.require("a").insert(
        document.make("rect", ["x": "2", "y": "2", "width": "6", "height": "16"]), before: try document.require("a1"))
    },
    StructureChange(
      "an element removed before siblings that sibling combinators and :first-child match", before: style + content,
      after: style + content.replacingOccurrences(of: #"<rect id="a1" width="10" height="10"/>"#, with: "")
    ) { document in
      try document.require("a1").remove()
    },
    StructureChange(
      "an element inserted before siblings that only sibling combinators match", before: siblings + content,
      after: siblings
        + content.replacingOccurrences(of: #"<rect id="a1""#, with: #"<rect x="2" y="2" width="6" height="16"/><rect id="a1""#)
    ) { document in
      try document.require("a").insert(
        document.make("rect", ["x": "2", "y": "2", "width": "6", "height": "16"]), before: try document.require("a1"))
    },
    StructureChange(
      "an element removed before siblings that only sibling combinators match",
      before: siblings + content.replacingOccurrences(of: "</g><g", with: #"<circle cx="15" cy="15" r="4"/></g><g"#),
      after: siblings
        + content.replacingOccurrences(of: "</g><g", with: #"<circle cx="15" cy="15" r="4"/></g><g"#)
        .replacingOccurrences(of: #"<rect id="a1" width="10" height="10"/>"#, with: "")
    ) { document in
      try document.require("a1").remove()
    },
    StructureChange(
      "the last child removed from an element that :empty matches", before: style + content,
      after: style + #"<g id="a" fill="red"></g><g id="b" fill="blue"><rect id="b1" y="10" width="10" height="10"/></g>"#
    ) { document in
      try document.require("a1").remove()
      try document.require("a2").remove()
    },
    StructureChange(
      "a span removed from text",
      before: #"<text id="t" y="15" font-size="8">a<tspan id="s" fill="lime">b</tspan>c</text>"#,
      after: #"<text id="t" y="15" font-size="8">ac</text>"#
    ) { document in
      try document.require("s").remove()
    },
    StructureChange(
      "a span moved in text",
      before: #"<text id="t" y="15" font-size="8"><tspan id="s" fill="lime">b</tspan><tspan id="e" fill="blue">c</tspan></text>"#,
      after: #"<text id="t" y="15" font-size="8"><tspan id="e" fill="blue">c</tspan><tspan id="s" fill="lime">b</tspan></text>"#
    ) { document in
      try document.require("t").append(try document.require("s"))
    },
  ]

  /// The pixels of the snapshot of a view at a time.
  private func snapshot(of view: SVGUIView, at time: Duration) async throws -> [UInt8] {
    try pixels(of: try await view.takeCGImageSnapshot(at: time, scale: 2))
  }

  @Test("a changed document is shown as the document written with the change", arguments: changes)
  func changedDocument(_ change: StructureChange) async throws {
    let changed = makeView(change.before)
    // The view has a context of the document before the change, which the change makes again.
    _ = try await snapshot(of: changed, at: .zero)
    try change.change(changed.document)
    let written = makeView(change.after)
    for time in [Duration.zero, .milliseconds(500)] {
      let pixels = try await snapshot(of: changed, at: time)
      #expect(pixels == (try await snapshot(of: written, at: time)), "at \(time)")
      #expect(pixels.contains { $0 != 0 }, "Nothing is painted at \(time)")
    }
    #expect(changed.document.animationEnd == written.document.animationEnd)
    #expect(changed.intrinsicContentSize == written.intrinsicContentSize)
  }

  @Test("a document changed before its first rendering is shown as the document written with the change", arguments: changes)
  func changedBeforeRendering(_ change: StructureChange) async throws {
    let changed = makeView(change.before)
    try change.change(changed.document)
    let pixels = try await snapshot(of: changed, at: .zero)
    #expect(pixels == (try await snapshot(of: makeView(change.after), at: .zero)))
  }

  // MARK: - The view

  /// The window of the views, which the suite keeps for the test, since a view only plays in a window.
  private let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 20, height: 20))

  /// A view in a window that has rendered its first image.
  private func showView(
    _ content: String, animation: SVGUIViewConfiguration.AnimationMode = .none
  ) async throws -> (SVGUIView, ManualClock) {
    let view = SVGUIView(frame: CGRect(x: 0, y: 0, width: 20, height: 20), data: Data(document(content).utf8))
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

  @Test("the view shows an inserted element at its next rendering, and not a removed one")
  func rendersStructure() async throws {
    let (view, _) = try await showView(#"<rect width="20" height="20" fill="red"/>"#)
    try await waitForGreen(in: view) { $0 == 0 }
    let square = view.document.make("rect", ["width": "20", "height": "20", "fill": "rgb(0, 255, 0)"])
    try view.document.rootElement?.append(square)
    try await waitForGreen(in: view) { $0 == 255 }
    square.remove()
    try await waitForGreen(in: view) { $0 == 0 }
  }

  @Test("changes of elements that aren't in the tree don't render the view again")
  func detachedChanges() async throws {
    let (view, _) = try await showView(#"<rect width="20" height="20" fill="red"/>"#)
    try await waitForRendering(of: view)
    let generation = view.renderingGeneration
    let group = view.document.make("g", ["fill": "rgb(0, 255, 0)"])
    let square = view.document.make("rect", ["width": "20", "height": "20"])
    try group.append(square)
    square.setAttribute("width", to: "10")
    square.remove()
    try group.append(square)
    try await waitForRendering(of: view)
    #expect(view.renderingGeneration == generation)
    // The changes made in one turn of the run loop are rendered together.
    try view.document.rootElement?.append(group)
    square.setAttribute("width", to: "20")
    try await waitForRendering(of: view)
    #expect(view.renderingGeneration == generation + 1)
    #expect(green(in: view) == 255)
  }

  private static let animated =
    "<style>@keyframes a { from { fill: rgb(0, 0, 0) } to { fill: rgb(0, 255, 0) } } .on { animation: a 1s linear both }"
    + " .slow { transition: fill 1s linear }</style>"

  @Test("the CSS animations of an element that is inserted again start at the time that it's inserted")
  func restartsAnimations() async throws {
    let (view, clock) = try await showView(
      Self.animated + #"<rect id="square" width="20" height="20" class="on"/>"#, animation: .play)
    clock.advance(by: .milliseconds(500))
    let square = try view.document.require("square")
    #expect(try #require(square.animations.first).currentTime == .milliseconds(500))
    square.remove()
    #expect(view.document.animations.isEmpty)
    clock.advance(by: .milliseconds(250))
    try view.document.rootElement?.append(square)
    #expect(try #require(square.animations.first).currentTime == .zero)
    clock.advance(by: .milliseconds(500))
    try await waitForGreen(in: view) { (126...129).contains($0) }
    // An element that is moved is removed and inserted at once, and starts its animations too.
    let group = view.document.createElement("g")
    try view.document.rootElement?.append(group)
    try group.append(square)
    #expect(try #require(square.animations.first).currentTime == .zero)
    try await waitForGreen(in: view) { $0 == 0 }
  }

  @Test("an inserted element starts no transitions, and the transitions of a removed element are cancelled")
  func transitions() async throws {
    let (view, clock) = try await showView(
      Self.animated + #"<g id="g" fill="rgb(0, 255, 0)"/><rect id="square" width="20" height="20" fill="rgb(0, 0, 0)" class="slow"/>"#,
      animation: .play)
    let square = try view.document.require("square")
    // The transition of the square runs, and is cancelled when the square is removed.
    square.setAttribute("fill", to: "rgb(0, 200, 0)")
    try await waitForRendering(of: view)
    clock.advance(by: .milliseconds(500))
    try await waitForGreen(in: view) { (99...101).contains($0) }
    square.remove()
    try view.document.rootElement?.append(square)
    try await waitForGreen(in: view) { $0 == 200 }
    // The square inherits another fill in the group, which starts no transition.
    square.removeAttribute("fill")
    try await waitForRendering(of: view)
    clock.advance(by: .seconds(2))
    try await waitForGreen(in: view) { $0 == 0 }
    try view.document.require("g").append(square)
    try await waitForGreen(in: view) { $0 == 255 }
  }
}
