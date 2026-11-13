import SVGUIView
import SwiftUI

/// The demonstration of dragging a shape of a document of many elements, as an app that edits shapes does.
struct DragDemo: Hashable {}

/// Moves a circle on top of a document of many shapes while a finger drags anywhere on the view, by changing the
/// `transform` attribute of the circle through the document API at every change of the drag.
///
/// It shows how a view follows a document that changes at every frame when rendering the document takes longer
/// than a frame.
struct DragDemoView: View {
  /// The numbers of shapes to choose from.
  private static let counts = [500, 2000, 5000]
  @State private var count = 2000
  @State private var changes = 0

  var body: some View {
    VStack(spacing: 12) {
      Picker("Shapes", selection: $count) {
        ForEach(Self.counts, id: \.self) { Text("\($0) shapes") }
      }
      .pickerStyle(.segmented)
      .padding(.horizontal)

      DraggableSVGView(count: count) { changes += 1 }
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
  /// Called at every change of the document.
  let onChange: () -> Void

  /// The columns of the shapes, each 20 units wide.
  private static let columns = 50

  /// The height of the document in its user units, which is 1000 wide.
  private var height: Int { (count + Self.columns - 1) / Self.columns * 20 }

  func makeCoordinator() -> Coordinator {
    Coordinator(documentSize: CGSize(width: 1000, height: height), onChange: onChange)
  }

  func makeUIView(context: Context) -> SVGUIView {
    let view = SVGUIView(frame: .zero, data: document())
    view.contentMode = .scaleAspectFit
    // A pan begins only after the finger has moved about 10 points, and counts the movement from there, so the
    // circle would lag behind the finger. A press without a minimum duration begins when the finger touches.
    let drag = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.drag(_:)))
    drag.minimumPressDuration = 0
    drag.allowableMovement = .greatestFiniteMagnitude
    view.addGestureRecognizer(drag)
    return view
  }

  func updateUIView(_: SVGUIView, context: Context) {
    context.coordinator.onChange = onChange
  }

  /// The size that SwiftUI proposes, as SVGView takes, instead of the size of the document.
  func sizeThatFits(_ proposal: ProposedViewSize, uiView: SVGUIView, context _: Context) -> CGSize? {
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

  /// Moves the circle by the movement of the finger since it touched, in the user units of the document.
  @MainActor
  final class Coordinator: NSObject {
    private let documentSize: CGSize
    var onChange: () -> Void
    /// Where the circle is, from its place in the document.
    private var offset = CGPoint.zero
    /// Where the circle was when the drag began.
    private var start = CGPoint.zero
    /// Where the finger touched the view when the drag began.
    private var touch = CGPoint.zero

    init(documentSize: CGSize, onChange: @escaping () -> Void) {
      self.documentSize = documentSize
      self.onChange = onChange
    }

    @objc func drag(_ gesture: UILongPressGestureRecognizer) {
      guard let view = gesture.view as? SVGUIView else { return }
      let location = gesture.location(in: view)
      switch gesture.state {
      case .began:
        start = offset
        touch = location
      case .changed, .ended:
        // The view fits the document in its bounds, so a point of the view is this many units of the document.
        let scale = min(view.bounds.width / documentSize.width, view.bounds.height / documentSize.height)
        guard scale > 0 else { return }
        offset = CGPoint(x: start.x + (location.x - touch.x) / scale, y: start.y + (location.y - touch.y) / scale)
        view.document.element(id: "handle")?
          .setAttribute("transform", to: "translate(\(offset.x) \(offset.y))")
        onChange()
      default:
        break
      }
    }
  }
}
