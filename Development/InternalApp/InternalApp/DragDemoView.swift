import SVGUIView
import SwiftUI
import UIKit.UIGestureRecognizerSubclass

/// The demonstration of dragging a shape of a document of many elements, as an app that edits shapes does.
struct DragDemo: Hashable {}

/// Moves a circle on top of a document of many shapes while a finger drags anywhere on the view, by changing the
/// `transform` attribute of the circle through the document API at every movement of the finger.
///
/// A view shows a change of its document a frame after a layer that the app moves itself, since the rendering
/// returns to the main thread before it's shown. So while the finger drags, the demonstration hides the circle of
/// the document and moves a stand-in layer instead, where the touches predict the finger to be, as apps that edit
/// shapes do. Turning the stand-in off shows how the view follows the changes by itself.
struct DragDemoView: View {
  /// The numbers of shapes to choose from.
  private static let counts = [500, 2000, 5000]
  @State private var count = 2000
  @State private var usesStandIn = true
  @State private var changes = 0

  var body: some View {
    VStack(spacing: 12) {
      Picker("Shapes", selection: $count) {
        ForEach(Self.counts, id: \.self) { Text("\($0) shapes") }
      }
      .pickerStyle(.segmented)
      .padding(.horizontal)

      Toggle("Move a stand-in layer while dragging", isOn: $usesStandIn)
        .padding(.horizontal)

      DraggableSVGView(count: count, usesStandIn: usesStandIn) { changes += 1 }
        .id(count)
        .modifier(Pane(title: "SVGUIView", size: 1, isVisible: true))
        .padding(.horizontal)

      Text("Drag anywhere on the view to move the red circle. Changes: \(changes)")
        .font(.footnote)
        .foregroundStyle(.secondary)
        .padding(.horizontal)
    }
    .padding(.vertical)
    .navigationTitle("Drag a Shape")
    .navigationBarTitleDisplayMode(.inline)
    .onChange(of: count) { changes = 0 }
  }
}

/// A view that shows a document of `count` shapes and a circle, and moves the circle while a finger drags.
private struct DraggableSVGView: UIViewRepresentable {
  let count: Int
  let usesStandIn: Bool
  /// Called at every change of the document.
  let onChange: () -> Void

  /// The columns of the shapes, each 20 units wide.
  private static let columns = 50

  /// The height of the document in its user units, which is 1000 wide.
  private var height: Int { (count + Self.columns - 1) / Self.columns * 20 }

  func makeUIView(context _: Context) -> DragCanvas {
    let canvas = DragCanvas(
      data: document(), documentSize: CGSize(width: 1000, height: height),
      circle: DragCanvas.Circle(center: CGPoint(x: 500, y: height / 2), radius: 60))
    canvas.usesStandIn = usesStandIn
    canvas.onChange = onChange
    return canvas
  }

  func updateUIView(_ canvas: DragCanvas, context _: Context) {
    canvas.usesStandIn = usesStandIn
    canvas.onChange = onChange
  }

  /// The size that SwiftUI proposes, as SVGView takes, instead of the size of the document.
  func sizeThatFits(_ proposal: ProposedViewSize, uiView: DragCanvas, context _: Context) -> CGSize? {
    proposal.replacingUnspecifiedDimensions(by: uiView.intrinsicContentSize)
  }

  /// A document of rectangles and curves in turn, in groups of 50, with a circle on top of them.
  private func document() -> Data {
    var text = #"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1000 \#(height)">"#
    text += "<style>.a{stroke:#333;stroke-width:1}.b{fill:none;stroke:#c33}g>path{stroke-linecap:round}</style>"
    for index in 0..<count {
      if index % 50 == 0 { text += "<g>" }
      let x = index % Self.columns * 20 + 4
      let y = index / Self.columns * 20 + 2
      if index.isMultiple(of: 2) {
        text += #"<rect class="a" x="\#(x)" y="\#(y)" width="12" height="12" fill="teal"/>"#
      } else {
        text += #"<path class="b" d="M\#(x) \#(y + 8)C\#(x + 2) \#(y - 4) \#(x + 6) \#(y + 20) \#(x + 8) \#(y + 8)"/>"#
      }
      if index % 50 == 49 || index == count - 1 { text += "</g>" }
    }
    text += #"<circle id="handle" cx="500" cy="\#(height / 2)" r="60" fill="red" fill-opacity="0.8"/>"#
    text += "</svg>"
    return Data(text.utf8)
  }
}

/// An SVGUIView with a stand-in layer of the circle over it, which moves the circle by the movement of the finger
/// since it touched.
private final class DragCanvas: UIView {
  /// The circle of the document, in the user units of the document.
  struct Circle {
    let center: CGPoint
    let radius: CGFloat
  }

  private let svgView: SVGUIView
  private let documentSize: CGSize
  private let circle: Circle
  var usesStandIn = true
  var onChange: () -> Void = {}

  /// The layer that the finger moves instead of the circle, drawn as the document draws the circle.
  private let standIn = CAShapeLayer()
  /// Where the circle is, from its place in the document, in the user units of the document.
  private var offset = CGPoint.zero
  /// Where the circle was when the drag began.
  private var start = CGPoint.zero
  /// Where the finger touched the view when the drag began.
  private var touch = CGPoint.zero
  /// Hides the stand-in after the view shows the circle where the drag ended.
  private var hiding: Task<Void, Never>?

  init(data: Data, documentSize: CGSize, circle: Circle) {
    svgView = SVGUIView(frame: .zero, data: data)
    self.documentSize = documentSize
    self.circle = circle
    super.init(frame: .zero)
    svgView.contentMode = .scaleAspectFit
    addSubview(svgView)
    // A pan begins only after the finger has moved about 10 points, and counts the movement from there, so the
    // circle would lag behind the finger, and the swipe back of the navigation takes a drag to the right. A press
    // without a minimum duration begins when the finger touches, and keeps the touches.
    let drag = DragGesture(target: self, action: #selector(drag(_:)))
    drag.minimumPressDuration = 0
    drag.allowableMovement = .greatestFiniteMagnitude
    addGestureRecognizer(drag)
    standIn.fillColor = UIColor.red.withAlphaComponent(0.8).cgColor
    standIn.isHidden = true
    layer.addSublayer(standIn)
    // The stand-in shows only the part of the circle that the view shows.
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

  private var handle: SVGDocument.Element? { svgView.document.element(id: "handle") }

  /// The scale and the origin of the document in the view, which fits the document in its bounds.
  private var fit: (scale: CGFloat, origin: CGPoint) {
    let scale = min(bounds.width / documentSize.width, bounds.height / documentSize.height)
    let origin = CGPoint(
      x: (bounds.width - documentSize.width * scale) / 2, y: (bounds.height - documentSize.height * scale) / 2)
    return (scale, origin)
  }

  /// The offset of the circle when the finger is at a point of the view.
  private func offset(at location: CGPoint) -> CGPoint? {
    let scale = fit.scale
    guard scale > 0 else { return nil }
    return CGPoint(x: start.x + (location.x - touch.x) / scale, y: start.y + (location.y - touch.y) / scale)
  }

  /// Moves the stand-in to the circle at an offset, without the implicit animation of the layer.
  private func moveStandIn(to offset: CGPoint) {
    let (scale, origin) = fit
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    let radius = circle.radius * scale
    standIn.path = CGPath(ellipseIn: CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2), transform: nil)
    standIn.position = CGPoint(
      x: origin.x + (circle.center.x + offset.x) * scale, y: origin.y + (circle.center.y + offset.y) * scale)
    standIn.isHidden = false
    CATransaction.commit()
  }

  /// Moves the circle of the document.
  private func moveCircle(to offset: CGPoint) {
    self.offset = offset
    handle?.setAttribute("transform", to: "translate(\(offset.x) \(offset.y))")
    onChange()
  }

  /// Follows the finger that drags the circle.
  @objc private func drag(_ gesture: DragGesture) {
    let location = gesture.location(in: self)
    switch gesture.state {
    case .began:
      start = offset
      touch = location
      hiding?.cancel()
      if usesStandIn {
        // The circle of the document lags behind the stand-in, so it's hidden while the finger drags.
        handle?.setAttribute("visibility", to: "hidden")
        onChange()
        moveStandIn(to: offset)
      } else {
        standIn.isHidden = true
      }
    case .changed:
      guard let moved = offset(at: location) else { return }
      moveCircle(to: moved)
      if usesStandIn {
        // The stand-in goes where the touches predict the finger to be when the screen shows it.
        moveStandIn(to: gesture.predictedLocation(in: self).flatMap(offset(at:)) ?? moved)
      }
    case .ended, .cancelled, .failed:
      endDrag(at: location)
    default:
      break
    }
  }

  private func endDrag(at location: CGPoint) {
    if let moved = offset(at: location) { moveCircle(to: moved) }
    guard !standIn.isHidden else { return }
    handle?.removeAttribute("visibility")
    onChange()
    moveStandIn(to: offset)
    // The view doesn't tell when it shows a rendering, so the stand-in stays over the circle for a while, until the
    // view has shown the circle where the drag ended.
    hiding = Task { [weak self] in
      try? await Task.sleep(for: .milliseconds(200))
      guard !Task.isCancelled else { return }
      self?.standIn.isHidden = true
    }
  }
}

/// A press that also tells where the touches predict the finger to be.
private final class DragGesture: UILongPressGestureRecognizer {
  /// The last predicted touch of the finger, if the last movement predicted it.
  private var predicted: UITouch?

  /// Where the touches predict the finger to be when the screen shows its last movement.
  func predictedLocation(in view: UIView) -> CGPoint? { predicted?.location(in: view) }

  override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
    predicted = touches.first.flatMap { event.predictedTouches(for: $0)?.last }
    super.touchesMoved(touches, with: event)
  }

  override func reset() {
    predicted = nil
    super.reset()
  }
}
