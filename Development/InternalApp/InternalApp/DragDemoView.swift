import SVGUIView
import SwiftUI
import UIKit.UIGestureRecognizerSubclass

/// The demonstration of dragging a shape of a document of many elements, as an app that edits shapes does.
struct DragDemo: Hashable {}

/// Moves a handle on top of a document of many shapes while a finger drags it, by changing the `transform` attribute
/// of the handle through the document API at every movement of the finger. A drag begins when the hit test of the
/// view, `element(at:tolerance:)`, finds the handle or an element in it where the finger touched.
///
/// A view shows a change of its document a frame after a layer that the app moves itself, since the rendering
/// returns to the main thread before it's shown. So while the finger drags, the demonstration hides the handle of
/// the document and moves a stand-in layer instead, where the touches predict the finger to be, as apps that edit
/// shapes do. The stand-in shows the image of the handle that `takeSnapshot(scale:)` renders, with its gradient and
/// its stroke, and goes when `waitUntilDisplayed()` tells that the view shows the handle where the drag ended.
/// Turning the stand-in off shows how the view follows the changes by itself.
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

      Text("Drag the red handle to move it. Changes: \(changes)")
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

/// A view that shows a document of `count` shapes and a handle, and moves the handle while a finger drags.
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
      data: document(), documentSize: CGSize(width: 1000, height: height))
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

  /// A document of rectangles and curves in turn, in groups of 50, with a handle of a circle and a cross on top of
  /// them.
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
    let y = height / 2
    text += ##"<radialGradient id="glow"><stop offset="0" stop-color="#ffd0d0"/><stop offset="1" stop-color="red"/>"##
    text += "</radialGradient>"
    text += #"<g id="handle" opacity="0.85"><circle cx="500" cy="\#(y)" r="57" fill="url(#glow)" stroke="darkred" "#
    text += #"stroke-width="6"/><path d="M475 \#(y)H525M500 \#(y - 25)V\#(y + 25)" stroke="white" stroke-width="8" "#
    text += #"stroke-linecap="round"/></g>"#
    text += "</svg>"
    return Data(text.utf8)
  }
}

/// An SVGUIView with a stand-in layer of the handle over it, which moves the handle by the movement of the finger
/// since it touched.
private final class DragCanvas: UIView {
  private let svgView: SVGUIView
  private let documentSize: CGSize
  var usesStandIn = true
  var onChange: () -> Void = {}

  /// The layer that the finger moves instead of the handle, which shows the image of the handle that the view renders.
  private let standIn = CALayer()
  /// Where the image of the stand-in is in the view, and the offset of the handle that it shows there, or `nil`
  /// before the image is rendered.
  private var standInPlace: (frame: CGRect, offset: CGPoint)?
  /// Where the stand-in goes, which it goes to when its image is rendered.
  private var standInOffset = CGPoint.zero
  /// Renders the image of the stand-in when a drag begins.
  private var preparing: Task<Void, Never>?
  /// Where the handle is, from its place in the document, in the user units of the document.
  private var offset = CGPoint.zero
  /// Where the handle was when the drag began.
  private var start = CGPoint.zero
  /// Where the finger touched the view when the drag began.
  private var touch = CGPoint.zero
  /// Hides the stand-in after the view shows the handle where the drag ended.
  private var hiding: Task<Void, Never>?
  /// Whether the finger touched the handle, which the hit test of the view tells after the touch, or `nil` until it
  /// tells.
  private var grabs: Bool?
  /// Finds whether the finger touched the handle.
  private var grabbing: Task<Void, Never>?
  /// Where the finger was last, and where the touches predicted it to be, which a drag that the hit test begins
  /// after the finger moved catches up with.
  private var lastLocation = CGPoint.zero
  private var lastPredicted: CGPoint?

  init(data: Data, documentSize: CGSize) {
    svgView = SVGUIView(frame: .zero, data: data)
    self.documentSize = documentSize
    super.init(frame: .zero)
    svgView.contentMode = .scaleAspectFit
    addSubview(svgView)
    // A pan begins only after the finger has moved about 10 points, and counts the movement from there, so the
    // handle would lag behind the finger, and the swipe back of the navigation takes a drag to the right. A press
    // without a minimum duration begins when the finger touches, and keeps the touches.
    let drag = DragGesture(target: self, action: #selector(drag(_:)))
    drag.minimumPressDuration = 0
    drag.allowableMovement = .greatestFiniteMagnitude
    addGestureRecognizer(drag)
    standIn.isHidden = true
    layer.addSublayer(standIn)
    // The stand-in shows only the part of the handle that the view shows.
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

  /// The offset of the handle when the finger is at a point of the view.
  private func offset(at location: CGPoint) -> CGPoint? {
    let scale = fit.scale
    guard scale > 0 else { return nil }
    return CGPoint(x: start.x + (location.x - touch.x) / scale, y: start.y + (location.y - touch.y) / scale)
  }

  /// Moves the stand-in to the handle at an offset, without the implicit animation of the layer, once its image is
  /// rendered.
  private func moveStandIn(to offset: CGPoint) {
    standInOffset = offset
    guard let (frame, imageOffset) = standInPlace else { return }
    let scale = fit.scale
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    standIn.frame = frame.offsetBy(dx: (offset.x - imageOffset.x) * scale, dy: (offset.y - imageOffset.y) * scale)
    standIn.isHidden = false
    CATransaction.commit()
  }

  /// Renders the image of the handle into the stand-in, and hides the handle of the document, which lags behind the
  /// stand-in, while the finger drags.
  private func prepareStandIn() async {
    guard let handle else { return }
    // The image shows the handle with the changes until now.
    let offset = offset
    guard let snapshot = try? await handle.takeSnapshot(), !Task.isCancelled else { return }
    standIn.contents = snapshot.image
    standInPlace = (snapshot.frame, offset)
    handle.setAttribute("visibility", to: "hidden")
    onChange()
    moveStandIn(to: standInOffset)
  }

  /// Moves the handle of the document.
  private func moveHandle(to offset: CGPoint) {
    self.offset = offset
    handle?.setAttribute("transform", to: "translate(\(offset.x) \(offset.y))")
    onChange()
  }

  /// Follows the finger that drags the handle, once the hit test tells that it touched the handle.
  @objc private func drag(_ gesture: DragGesture) {
    let location = gesture.location(in: self)
    lastLocation = location
    lastPredicted = gesture.predictedLocation(in: self)
    switch gesture.state {
    case .began:
      start = offset
      touch = location
      grabs = nil
      // The view finds the element at the point off the main thread, while the finger may move on. A finger on a
      // thin edge of the handle picks it within the tolerance.
      grabbing = Task { [weak self] in
        guard let self, let handle else { return }
        let hit = await svgView.document.element(at: location, tolerance: 8)
        guard !Task.isCancelled else { return }
        grabs = hit.map { self.isInHandle($0, handle) } ?? false
        if grabs == true { beginDrag() }
      }
    case .changed:
      guard grabs == true else { return }
      follow()
    case .ended, .cancelled, .failed:
      grabbing?.cancel()
      if grabs == true { endDrag(at: location) }
      grabs = nil
    default:
      break
    }
  }

  /// Whether an element is the handle or in it.
  private func isInHandle(_ element: SVGDocument.Element, _ handle: SVGDocument.Element) -> Bool {
    var element: SVGDocument.Element? = element
    while let current = element {
      if current == handle { return true }
      element = current.parent
    }
    return false
  }

  /// Begins to drag the handle, after the hit test tells that the finger touched it.
  private func beginDrag() {
    hiding?.cancel()
    standInOffset = offset
    if usesStandIn, standInPlace != nil {
      // The stand-in of the drag before is still shown, which this drag moves on.
      handle?.setAttribute("visibility", to: "hidden")
      onChange()
    } else if usesStandIn {
      // Until the image is rendered, the handle of the document follows the finger by itself.
      preparing = Task { [weak self] in await self?.prepareStandIn() }
    } else {
      hideStandIn()
    }
    // The finger may have moved while the hit test ran.
    follow()
  }

  /// Moves the handle to where the finger is.
  private func follow() {
    guard let moved = offset(at: lastLocation) else { return }
    moveHandle(to: moved)
    if usesStandIn {
      // The stand-in goes where the touches predict the finger to be when the screen shows it.
      moveStandIn(to: lastPredicted.flatMap(offset(at:)) ?? moved)
    }
  }

  private func endDrag(at location: CGPoint) {
    if let moved = offset(at: location) { moveHandle(to: moved) }
    preparing?.cancel()
    guard standInPlace != nil else { return }
    handle?.removeAttribute("visibility")
    onChange()
    moveStandIn(to: offset)
    // The stand-in goes in the same transaction as the view shows the handle where the drag ended.
    hiding = Task { [weak self] in
      guard let svgView = self?.svgView else { return }
      await svgView.waitUntilDisplayed()
      guard !Task.isCancelled else { return }
      self?.hideStandIn()
    }
  }

  private func hideStandIn() {
    standIn.isHidden = true
    standIn.contents = nil
    standInPlace = nil
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
