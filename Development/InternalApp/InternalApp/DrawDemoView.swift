import SVGUIView
import SwiftUI
import UniformTypeIdentifiers

/// The demonstration of drawing on a document through the document API, and sharing the drawing as an SVG file, as
/// an app that edits shapes saves its work.
struct DrawDemo: Hashable {}

/// Draws a line where a finger drags, and puts a circle where it taps, by adding `path` and `circle` elements to a
/// document of 400 by 400 units. The share button writes the document as SVG with `svgData()`, which the Files app
/// saves, and which the viewer opens again with its file picker.
struct DrawDemoView: View {
  @State private var drawing = Drawing()

  var body: some View {
    VStack(spacing: 12) {
      Picker("Color", selection: $drawing.color) {
        ForEach(Drawing.colors, id: \.self) { color in
          Text(color.capitalized).tag(color)
        }
      }
      .pickerStyle(.segmented)
      .padding(.horizontal)

      // The view is square, as the document is, so that the white of the document fills it.
      DrawingSVGView(drawing: drawing)
        .modifier(Pane(title: "SVGUIView", size: 1, isVisible: true))
        .aspectRatio(1, contentMode: .fit)
        .padding(.horizontal)

      Text("Drag to draw a line, and tap to put a circle. Elements: \(drawing.elementCount)")
        .font(.footnote)
        .foregroundStyle(.secondary)

      Spacer(minLength: 0)
    }
    .padding(.vertical)
    .navigationTitle("Draw and Share")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItemGroup(placement: .topBarTrailing) {
        Button("Undo", systemImage: "arrow.uturn.backward") { drawing.undo() }
          .disabled(drawing.elementCount == 0)
        Button("Clear", systemImage: "trash") { drawing.clear() }
          .disabled(drawing.elementCount == 0)
        ShareLink(
          item: DrawingFile(data: drawing.svgData()), preview: SharePreview("Drawing.svg", image: Image(systemName: "scribble")))
      }
    }
  }
}

/// The document that the demonstration draws on, and the elements that it added, which undo removes.
@MainActor
@Observable
final class Drawing {
  /// The colors to draw with, as SVG color keywords.
  static let colors = ["black", "crimson", "royalblue"]

  /// The document of 400 by 400 units on white.
  static let document = #"""
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 400 400">
      <title>Drawing</title>
      <rect width="400" height="400" fill="white"/>
    </svg>
    """#

  var color = colors[0]
  /// The view that shows the document, which the canvas sets.
  @ObservationIgnored weak var view: SVGUIView?
  /// The elements that the drawing added, in the order that they were added.
  @ObservationIgnored private var elements = [SVGDocument.Element]()
  /// How many elements the drawing has, which changes the views that read it, as a change of a line does too.
  private(set) var elementCount = 0
  /// Changes with every change of the document, so that the share button writes the latest one.
  private(set) var version = 0

  /// Adds an element of the document, with the attributes, and returns it, or `nil` without a document.
  func add(_ name: String, attributes: [(String, String)]) -> SVGDocument.Element? {
    guard let document = view?.document, let root = document.rootElement else { return nil }
    let element = document.createElement(name)
    for (name, value) in attributes {
      element.setAttribute(name, to: value)
    }
    try? root.append(element)
    elements.append(element)
    elementCount = elements.count
    version += 1
    return element
  }

  /// Notes a change of an element that the drawing added, such as a line that grows.
  func changed() {
    version += 1
  }

  func undo() {
    elements.popLast()?.remove()
    elementCount = elements.count
    version += 1
  }

  func clear() {
    for element in elements {
      element.remove()
    }
    elements.removeAll()
    elementCount = 0
    version += 1
  }

  /// The document as SVG, which reads ``version`` so that a view that shows it updates with the drawing.
  func svgData() -> Data {
    _ = version
    return view?.document.svgData() ?? Data(Self.document.utf8)
  }
}

/// An SVG file of a drawing, which the share sheet saves.
private struct DrawingFile: Transferable {
  let data: Data

  static var transferRepresentation: some TransferRepresentation {
    DataRepresentation(exportedContentType: .svg) { $0.data }
      .suggestedFileName("Drawing.svg")
  }
}

/// A view of the document of a drawing, which draws where a finger drags and taps.
private struct DrawingSVGView: UIViewRepresentable {
  let drawing: Drawing

  func makeUIView(context _: Context) -> DrawingCanvas {
    DrawingCanvas(drawing: drawing)
  }

  func updateUIView(_: DrawingCanvas, context _: Context) {}

  /// The size that SwiftUI proposes, as SVGView takes, instead of the size of the document.
  func sizeThatFits(_ proposal: ProposedViewSize, uiView: DrawingCanvas, context _: Context) -> CGSize? {
    proposal.replacingUnspecifiedDimensions(by: uiView.intrinsicContentSize)
  }
}

/// An SVGUIView that adds a `path` element where a finger drags, and a `circle` element where it taps.
private final class DrawingCanvas: UIView {
  private let svgView: SVGUIView
  private let drawing: Drawing
  /// The line that the finger draws, and its path data.
  private var line: (element: SVGDocument.Element, data: String)?
  /// Where the finger last went down, where a line starts. The pan gesture begins after the finger has moved a
  /// little, and measures its translation from there.
  private var touchDown: CGPoint?

  init(drawing: Drawing) {
    self.drawing = drawing
    svgView = SVGUIView(frame: .zero, data: Data(Drawing.document.utf8))
    super.init(frame: .zero)
    svgView.contentMode = .scaleAspectFit
    addSubview(svgView)
    drawing.view = svgView
    addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(pan(_:))))
    addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tap(_:))))
    clipsToBounds = true
  }

  @available(*, unavailable)
  required init?(coder _: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override var intrinsicContentSize: CGSize { svgView.intrinsicContentSize }

  override func layoutSubviews() {
    super.layoutSubviews()
    svgView.frame = bounds
  }

  /// A point of the view in the coordinates of the document, which the view fits in its bounds.
  private func documentPoint(_ point: CGPoint) -> CGPoint {
    let scale = min(bounds.width, bounds.height) / 400
    guard scale > 0 else { return .zero }
    let origin = CGPoint(x: (bounds.width - 400 * scale) / 2, y: (bounds.height - 400 * scale) / 2)
    return CGPoint(x: (point.x - origin.x) / scale, y: (point.y - origin.y) / scale)
  }

  /// A number of the path data, rounded to a tenth.
  private static func number(_ value: CGFloat) -> String {
    let rounded = (value * 10).rounded() / 10
    return rounded == rounded.rounded() ? String(Int(rounded)) : String(format: "%.1f", rounded)
  }

  override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
    touchDown = touches.first?.location(in: self)
    super.touchesBegan(touches, with: event)
  }

  @objc private func pan(_ gesture: UIPanGestureRecognizer) {
    let location = gesture.location(in: self)
    let point = documentPoint(location)
    let coordinates = Self.number(point.x) + " " + Self.number(point.y)
    switch gesture.state {
    case .began:
      // The gesture begins after the finger has moved a little, so the line starts where the finger went down.
      let start = documentPoint(touchDown ?? location)
      let data = "M" + Self.number(start.x) + " " + Self.number(start.y) + "L" + coordinates
      guard
        let element = drawing.add(
          "path",
          attributes: [
            ("d", data), ("fill", "none"), ("stroke", drawing.color), ("stroke-width", "4"),
            ("stroke-linecap", "round"), ("stroke-linejoin", "round"),
          ])
      else { return }
      line = (element, data)
    case .changed:
      guard var line else { return }
      line.data += "L" + coordinates
      line.element.setAttribute("d", to: line.data)
      self.line = line
      drawing.changed()
    default:
      line = nil
    }
  }

  @objc private func tap(_ gesture: UITapGestureRecognizer) {
    let point = documentPoint(gesture.location(in: self))
    _ = drawing.add(
      "circle",
      attributes: [("cx", Self.number(point.x)), ("cy", Self.number(point.y)), ("r", "12"), ("fill", drawing.color)])
  }
}
