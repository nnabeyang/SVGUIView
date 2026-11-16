import CoreGraphics
import Foundation
import Testing
import UIKit

@testable import SVGUIView

/// A change that the tests make at every step of continuous changes.
struct ContinuousChange: CustomTestStringConvertible, Sendable {
  let testDescription: String
  /// The document of the view.
  let document: String
  /// The changes of the steps, one after another.
  let steps: [@MainActor @Sendable (SVGDocument) throws -> Void]
}

@MainActor
@Suite("Continuous changes of a document")
struct ContinuousChangesTests {
  /// The scale of the screen, which the view renders at and the snapshots are taken at.
  private let scale = UIScreen.main.scale

  /// A view of 20 by 20 that shows a document in the user space of 20 by 20, whose changes stay continuous for the
  /// tests, and has shown its first rendering.
  private func makeView(_ content: String) async throws -> SVGUIView {
    let view = SVGUIView(frame: CGRect(x: 0, y: 0, width: 20, height: 20), data: Data(document(content).utf8))
    view.configuration = SVGUIViewConfiguration(timeoutDuration: patience)
    view.continuousChangeInterval = .seconds(600)
    view.layer.displayIfNeeded()
    try await waitForRendering(of: view)
    return view
  }

  /// The pixels that the view shows, in its image or in its layers.
  private func shownPixels(of view: SVGUIView) throws -> [UInt8] {
    let width = Int((view.bounds.width * scale).rounded(.up))
    let height = Int((view.bounds.height * scale).rounded(.up))
    var components = [UInt8](repeating: 0, count: width * height * 4)
    let context = try #require(
      CGContext(
        data: &components, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.translateBy(x: 0, y: CGFloat(height))
    context.scaleBy(x: scale, y: -scale)
    view.layer.render(in: context)
    return components
  }

  /// The largest difference between the components of the pixels that the view shows and of its snapshot.
  private func differenceFromSnapshot(of view: SVGUIView) async throws -> Int {
    let shown = try shownPixels(of: view)
    let snapshot = try pixels(of: try #require(try await view.takeSnapshot(scale: scale).cgImage))
    try #require(shown.count == snapshot.count)
    return zip(shown, snapshot).map { abs(Int($0) - Int($1)) }.max() ?? 0
  }

  /// Makes a change, and waits until the view shows it.
  private func apply(_ change: (SVGDocument) throws -> Void, to view: SVGUIView) async throws {
    try change(view.document)
    view.layer.displayIfNeeded()
    try await waitForRendering(of: view)
  }

  private static func element(_ id: String, in document: SVGDocument) throws -> SVGDocument.Element {
    try #require(document.element(id: id))
  }

  /// Rectangles on the pixels of the view, so that the layers show the pixels of one image.
  nonisolated private static let shapes =
    #"<rect id="back" width="20" height="20" fill="silver"/>"#
    + #"<g id="group" fill="teal"><rect id="a" x="2" y="2" width="6" height="6"/>"#
    + #"<rect id="b" x="10" y="2" width="6" height="6"/></g>"#
    + #"<rect id="moving" x="4" y="10" width="6" height="6" fill="orange"/>"#

  nonisolated static let changes: [ContinuousChange] = [
    ContinuousChange(
      testDescription: "moving a shape over others", document: shapes,
      steps: [4, 6, 8, 2].map { x in
        { try element("moving", in: $0).setAttribute("transform", to: "translate(\(x) -\(x / 2))") }
      }),
    ContinuousChange(
      testDescription: "the fill of a group, which its children inherit", document: shapes,
      steps: ["navy", "purple", "teal"].map { color in
        { try element("group", in: $0).setAttribute("fill", to: color) }
      }),
    ContinuousChange(
      testDescription: "moving a shape, and then changing its fill", document: shapes,
      steps: [
        { try element("moving", in: $0).setAttribute("transform", to: "translate(2 0)") },
        { try element("moving", in: $0).setAttribute("fill", to: "green") },
        { try element("moving", in: $0).setAttribute("transform", to: "translate(4 0)") },
      ]),
    ContinuousChange(
      testDescription: "a stop of a gradient that a shape is painted with",
      document: #"<linearGradient id="g"><stop id="s" offset="0" stop-color="red"/></linearGradient>"#
        + #"<rect x="4" y="4" width="12" height="12" fill="url(#g)"/>"#,
      steps: ["blue", "lime", "black"].map { color in
        { try element("s", in: $0).setAttribute("stop-color", to: color) }
      }),
    ContinuousChange(
      testDescription: "an element that a use element shows",
      document: #"<defs><rect id="r" width="6" height="6" fill="red"/></defs>"#
        + ##"<use href="#r" x="2" y="2"/><use href="#r" x="12" y="12"/>"##,
      steps: [
        { try element("r", in: $0).setAttribute("fill", to: "blue") },
        { try element("r", in: $0).setAttribute("width", to: "4") },
        { try element("r", in: $0).setAttribute("transform", to: "translate(1 1)") },
      ]),
    ContinuousChange(
      testDescription: "removing, inserting and renaming the element that a reference names",
      document: #"<defs id="defs"><linearGradient id="g"><stop offset="0" stop-color="blue"/></linearGradient></defs>"#
        + #"<rect id="other-shape" width="2" height="2" fill="gray"/>"#
        + #"<rect id="target" x="4" y="4" width="12" height="12" fill="url(#g) lime"/>"#,
      // Moving another shape first makes the changes continuous, so that the layers of the shape that references the
      // gradient are reused unless the references make it paint again.
      steps: [
        { try element("other-shape", in: $0).setAttribute("transform", to: "translate(1 0)") },
        { try element("other-shape", in: $0).setAttribute("transform", to: "translate(2 0)") },
        { try element("g", in: $0).setAttribute("id", to: "other") },
        { try element("other", in: $0).setAttribute("id", to: "g") },
        { try element("g", in: $0).remove() },
        { document in
          let gradient = document.createElement("linearGradient")
          gradient.setAttribute("id", to: "g")
          let stop = document.createElement("stop")
          stop.setAttribute("stop-color", to: "purple")
          try gradient.append(stop)
          try element("defs", in: document).append(gradient)
        },
      ]),
    ContinuousChange(
      testDescription: "reordering, inserting and removing shapes", document: shapes,
      steps: [
        { try #require($0.rootElement).insert(try element("moving", in: $0), before: try element("group", in: $0)) },
        { try #require($0.rootElement).append(try element("moving", in: $0)) },
        { try element("a", in: $0).remove() },
        { document in
          let shape = document.createElement("rect")
          shape.setAttribute("x", to: "6")
          shape.setAttribute("y", to: "6")
          shape.setAttribute("width", to: "8")
          shape.setAttribute("height", to: "8")
          shape.setAttribute("fill", to: "black")
          try element("group", in: document).append(shape)
        },
      ]),
    ContinuousChange(
      testDescription: "the width of the stroke of a moving shape, which paints past where it painted",
      document: shapes,
      steps: ["1", "3", "5", "2"].map { width in
        {
          let shape = try element("moving", in: $0)
          shape.setAttribute("stroke", to: "black")
          shape.setAttribute("stroke-width", to: width)
          shape.setAttribute("transform", to: "translate(\(width) 0)")
        }
      }),
    ContinuousChange(
      testDescription: "the character data of a text",
      document: shapes + #"<text id="label" x="1" y="19" font-size="4" fill="black">0</text>"#,
      steps: ["1", "22", "333", ""].map { text in
        { try element("label", in: $0).textContent = text }
      }),
  ]

  @Test("the layers of continuous changes show what a snapshot of the document shows", arguments: changes)
  func layersShowChanges(_ change: ContinuousChange) async throws {
    let view = try await makeView(change.document)
    for (index, step) in change.steps.enumerated() {
      try await apply(step, to: view)
      // The first change is shown in one image, and the next ones in layers.
      #expect(view.isChangingContinuously == (index > 0))
      #expect((view.layer.contents == nil) == (index > 0))
      let difference = try await differenceFromSnapshot(of: view)
      #expect(difference <= 1, "step \(index)")
    }
  }

  /// The contents of the layers that the view shows, by their identities.
  private func layerContents(of view: SVGUIView) -> Set<ObjectIdentifier> {
    func contents(of layer: CALayer) -> [ObjectIdentifier] {
      (layer.contents.map { [ObjectIdentifier($0 as AnyObject)] } ?? [])
        + (layer.sublayers ?? []).flatMap(contents(of:))
    }
    return Set(contents(of: view.layer))
  }

  @Test("moving a shape continuously moves its layer, and paints no layer again")
  func movingReusesLayers() async throws {
    let view = try await makeView(Self.shapes)
    let moving = try Self.element("moving", in: view.document)
    try await apply({ _ in moving.setAttribute("transform", to: "translate(1 0)") }, to: view)
    try await apply({ _ in moving.setAttribute("transform", to: "translate(2 0)") }, to: view)
    let contents = layerContents(of: view)
    #expect(contents.count > 1)
    for x in 3...5 {
      try await apply({ _ in moving.setAttribute("transform", to: "translate(\(x) 0)") }, to: view)
      #expect(layerContents(of: view) == contents)
      #expect(try await differenceFromSnapshot(of: view) <= 1)
    }
  }

  @Test("the first frame of continuous changes keeps the nodes that the next frame reuses")
  func firstFrameKeepsNodes() async throws {
    let view = try await makeView(Self.shapes)
    let moving = try Self.element("moving", in: view.document)
    // The first change is shown in one image, and the second one in the first frame of layers.
    try await apply({ _ in moving.setAttribute("transform", to: "translate(1 0)") }, to: view)
    try await apply({ _ in moving.setAttribute("transform", to: "translate(2 0)") }, to: view)
    #expect(view.isChangingContinuously)
    #expect(!view.shownNodes.isEmpty)
  }

  @Test("changing the fill of a shape continuously paints only its layer again")
  func fillPaintsOneLayer() async throws {
    let view = try await makeView(Self.shapes)
    let moving = try Self.element("moving", in: view.document)
    try await apply({ _ in moving.setAttribute("fill", to: "red") }, to: view)
    try await apply({ _ in moving.setAttribute("fill", to: "green") }, to: view)
    let contents = layerContents(of: view)
    try await apply({ _ in moving.setAttribute("fill", to: "blue") }, to: view)
    // The layer of the shape has new contents, and every other layer keeps its contents.
    #expect(layerContents(of: view).subtracting(contents).count == 1)
    #expect(contents.subtracting(layerContents(of: view)).count == 1)
    #expect(try await differenceFromSnapshot(of: view) <= 1)
  }

  /// A shape like the ones of `shapes`, which the tests insert.
  private static func insertedShape(in document: SVGDocument, x: Int = 6) -> SVGDocument.Element {
    let shape = document.createElement("rect")
    shape.setAttribute("x", to: "\(x)")
    shape.setAttribute("y", to: "12")
    shape.setAttribute("width", to: "2")
    shape.setAttribute("height", to: "2")
    shape.setAttribute("fill", to: "black")
    return shape
  }

  @Test("inserting and removing a shape continuously paints only the layer of the inserted shape again")
  func insertionPaintsOneLayer() async throws {
    let view = try await makeView(Self.shapes)
    let group = try Self.element("group", in: view.document)
    var inserted: SVGDocument.Element?
    func toggle(_ document: SVGDocument) throws {
      if let shape = inserted {
        shape.remove()
        inserted = nil
      } else {
        let shape = Self.insertedShape(in: document)
        try group.append(shape)
        inserted = shape
      }
    }
    for _ in 1...4 {
      try await apply(toggle, to: view)
    }
    var shown = layerContents(of: view)
    for step in 5...8 {
      try await apply(toggle, to: view)
      // A new shape is painted into a layer of its own, and the layers around it keep their contents.
      let contents = layerContents(of: view)
      #expect(contents.subtracting(shown).count == (inserted == nil ? 0 : 1), "step \(step)")
      #expect(try await differenceFromSnapshot(of: view) <= 1, "step \(step)")
      shown.formUnion(contents)
    }
  }

  @Test("moving a shape between its siblings continuously paints only its layer again")
  func reorderingPaintsOneLayer() async throws {
    let view = try await makeView(Self.shapes + #"<rect id="front" x="12" y="12" width="6" height="6" fill="navy"/>"#)
    func move(_ document: SVGDocument, step: Int) throws {
      let root = try #require(document.rootElement)
      let moving = try Self.element("moving", in: document)
      try root.insert(moving, before: step.isMultiple(of: 2) ? try Self.element("group", in: document) : nil)
    }
    for step in 1...4 {
      try await apply({ try move($0, step: step) }, to: view)
    }
    var contents = layerContents(of: view)
    for step in 5...8 {
      try await apply({ try move($0, step: step) }, to: view)
      // The moved shape is painted again, as an inserted one is, since it can inherit from another parent, and the
      // layers around it keep their contents wherever it is.
      let shown = layerContents(of: view)
      #expect(shown.subtracting(contents).count == 1, "step \(step)")
      #expect(contents.subtracting(shown).count == 1, "step \(step)")
      #expect(try await differenceFromSnapshot(of: view) <= 1, "step \(step)")
      contents = shown
    }
  }

  @Test("changing the character data of a text continuously paints only its layer again")
  func textPaintsOneLayer() async throws {
    let view = try await makeView(
      Self.shapes + #"<text id="label" x="1" y="19" font-size="4" fill="black">0</text>"#)
    let label = try Self.element("label", in: view.document)
    for value in 1...3 {
      try await apply({ _ in label.textContent = "\(value)" }, to: view)
    }
    var contents = layerContents(of: view)
    for value in 4...6 {
      try await apply({ _ in label.textContent = "\(value)" }, to: view)
      let shown = layerContents(of: view)
      // The text has a layer of its own, apart from the shapes.
      #expect(shown.count > 1, "value \(value)")
      #expect(shown.subtracting(contents).count == 1, "value \(value)")
      #expect(contents.subtracting(shown).count == 1, "value \(value)")
      #expect(try await differenceFromSnapshot(of: view) <= 1, "value \(value)")
      contents = shown
    }
  }

  @Test("inserting shapes continuously gives layers of their own to a limited number of them")
  func insertedLayersAreLimited() async throws {
    let view = try await makeView(Self.shapes)
    let group = try Self.element("group", in: view.document)
    let count = SVGUIView.maximumRestructuringElements + 10
    for index in 0..<count {
      try await apply({ try group.append(Self.insertedShape(in: $0, x: index % 18)) }, to: view)
    }
    // The shapes after the limit are painted together into one layer.
    #expect(layerContents(of: view).count <= SVGUIView.maximumRestructuringElements + 4)
    #expect(try await differenceFromSnapshot(of: view) <= 1)
  }

  @Test("the view shows one image again when the changes stop")
  func endOfChanges() async throws {
    let view = try await makeView(Self.shapes)
    let moving = try Self.element("moving", in: view.document)
    for x in 1...3 {
      try await apply({ _ in moving.setAttribute("transform", to: "translate(\(x) 0)") }, to: view)
    }
    #expect(view.isChangingContinuously)
    #expect(view.layer.contents == nil)
    // The last change ends the changes soon after it.
    view.continuousChangeInterval = .milliseconds(100)
    try await apply({ _ in moving.setAttribute("transform", to: "translate(4 0)") }, to: view)
    #expect(view.isChangingContinuously)
    try await waitUntil("The changes are still continuous") { !view.isChangingContinuously }
    try await waitForRendering(of: view)
    #expect(view.layer.contents != nil)
    #expect(try await differenceFromSnapshot(of: view) == 0)
  }

  @Test("a change long after another one is shown in one image")
  func separateChanges() async throws {
    let view = try await makeView(Self.shapes)
    view.continuousChangeInterval = .milliseconds(1)
    let moving = try Self.element("moving", in: view.document)
    for x in 1...3 {
      try await apply({ _ in moving.setAttribute("transform", to: "translate(\(x) 0)") }, to: view)
      try await Task.sleep(for: .milliseconds(20))
      #expect(!view.isChangingContinuously)
      #expect(view.layer.contents != nil)
    }
  }
}
