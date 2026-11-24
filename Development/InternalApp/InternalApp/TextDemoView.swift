import SVGUIView
import SwiftUI

/// The demonstration of typing text onto a picture, as an app that adds text to photos does.
struct TextDemo: Hashable {}

/// Shows a picture where a tap adds a text and types into it, and a tap on a text edits it again. A tap outside the
/// text ends the editing, and a text left empty is removed. The controls change the fill, the alignment and the
/// outline of the text that is edited, or of the last one.
struct TextDemoView: View {
  @State private var model = TextDemoModel()

  var body: some View {
    VStack(spacing: 12) {
      HStack {
        ColorPicker("Fill", selection: $model.fill, supportsOpacity: false)
          .labelsHidden()
        Picker("Alignment", selection: $model.anchor) {
          Image(systemName: "text.alignleft").tag("start")
          Image(systemName: "text.aligncenter").tag("middle")
          Image(systemName: "text.alignright").tag("end")
        }
        .pickerStyle(.segmented)
        Toggle("Outline", isOn: $model.outlined)
          .toggleStyle(.button)
      }
      .padding(.horizontal)

      TextCanvasView(model: model)
        .modifier(Pane(title: "SVGUIView", size: 1, isVisible: true))
        .padding(.horizontal)

      Text(model.status)
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    .padding(.vertical)
    .navigationTitle("Type Text")
    .navigationBarTitleDisplayMode(.inline)
    .onChange(of: model.fill) { model.applyStyle() }
    .onChange(of: model.anchor) { model.applyStyle() }
    .onChange(of: model.outlined) { model.applyStyle() }
  }
}

/// The text that the controls change, and what the demonstration tells.
@MainActor
@Observable
final class TextDemoModel {
  var fill = Color.white
  var anchor = "start"
  var outlined = true
  var status = "Tap the picture to add text."
  /// The text that the controls change: the one that is edited, or the last one.
  var element: SVGDocument.Element?

  /// Sets the style of the controls on the text.
  func applyStyle() {
    guard let element else { return }
    let color = UIColor(fill).resolvedColor(with: .current)
    var red: CGFloat = 0
    var green: CGFloat = 0
    var blue: CGFloat = 0
    color.getRed(&red, green: &green, blue: &blue, alpha: nil)
    element.setAttribute("fill", to: "rgb(\(Int(red * 255)), \(Int(green * 255)), \(Int(blue * 255)))")
    element.setAttribute("text-anchor", to: anchor)
    if outlined {
      element.style.setProperty("stroke", to: "black")
      element.style.setProperty("stroke-width", to: "4")
      element.style.setProperty("stroke-linejoin", to: "round")
      element.style.setProperty("paint-order", to: "stroke")
    } else {
      for name in ["stroke", "stroke-width", "stroke-linejoin", "paint-order"] {
        element.style.removeProperty(name)
      }
    }
  }
}

/// The view of the picture, which adds and edits texts where a finger taps.
private struct TextCanvasView: UIViewRepresentable {
  let model: TextDemoModel

  func makeUIView(context _: Context) -> TextCanvas {
    TextCanvas(model: model)
  }

  func updateUIView(_: TextCanvas, context _: Context) {}
}

private final class TextCanvas: UIView, SVGUIViewTextEditingDelegate, UIGestureRecognizerDelegate {
  private let model: TextDemoModel
  private let svgView: SVGUIView

  /// A picture in place of a photo: a sky, a sun and hills.
  private static let picture = #"""
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 360 480" font-family="Helvetica" font-size="36" font-weight="bold">
    <defs><linearGradient id="sky" x2="0" y2="1"><stop offset="0" stop-color="#4a90d9"/><stop offset="1" stop-color="#f5c27a"/></linearGradient></defs>
    <rect width="360" height="480" fill="url(#sky)"/>
    <circle cx="260" cy="150" r="50" fill="#ffd54a"/>
    <path d="M0 360 Q90 280 180 350 T360 330 V480 H0 Z" fill="#3f7d4a"/>
    </svg>
    """#

  init(model: TextDemoModel) {
    self.model = model
    svgView = SVGUIView(data: Data(Self.picture.utf8))
    super.init(frame: .zero)
    svgView.contentMode = .scaleAspectFit
    svgView.textEditingDelegate = self
    svgView.translatesAutoresizingMaskIntoConstraints = false
    addSubview(svgView)
    NSLayoutConstraint.activate([
      svgView.leadingAnchor.constraint(equalTo: leadingAnchor),
      svgView.trailingAnchor.constraint(equalTo: trailingAnchor),
      svgView.topAnchor.constraint(equalTo: topAnchor),
      svgView.bottomAnchor.constraint(equalTo: bottomAnchor),
    ])
    let tap = UITapGestureRecognizer(target: self, action: #selector(tap(_:)))
    tap.delegate = self
    svgView.addGestureRecognizer(tap)
  }

  required init?(coder _: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  /// The view handles the taps while it edits text: a tap in the text moves the caret, and one outside ends it.
  func gestureRecognizer(_: UIGestureRecognizer, shouldReceive _: UITouch) -> Bool {
    svgView.editedTextElement == nil
  }

  @objc private func tap(_ gesture: UITapGestureRecognizer) {
    let point = gesture.location(in: svgView)
    Task {
      let document = svgView.document
      // A tap on a text edits it, and a tap elsewhere adds one there.
      // A tap on a line of a text hits its tspan, which is in the text.
      if let hit = await document.element(at: point, tolerance: 8),
        let text = hit.localName == "text" ? hit : hit.parent.flatMap({ $0.localName == "text" ? $0 : nil })
      {
        model.element = text
        // The caret goes between the characters closest to the tap.
        var caret: Range<Int>?
        if let layout = await text.textLayout(), let transform = await text.transformToView() {
          let rendered = layout.insertionIndex(closestTo: point.applying(transform.inverted()))
          // The text of the editing has a line feed after each line but the last, which the layout doesn't have.
          var offset = rendered
          var end = 0
          for length in svgViewLines(of: text).dropLast() {
            end += length
            guard rendered > end else { break }
            offset += 1
          }
          caret = offset..<offset
        }
        await svgView.beginTextEditing(of: text, selecting: caret)
        return
      }
      guard let root = document.rootElement, let transform = await root.transformToView() else { return }
      let location = point.applying(transform.inverted())
      let text = document.createElement("text")
      text.setAttribute("x", to: "\(Int(location.x))")
      text.setAttribute("y", to: "\(Int(location.y))")
      try? root.append(text)
      model.element = text
      model.applyStyle()
      await svgView.beginTextEditing(of: text)
    }
  }

  /// The number of characters of each line of a text: its tspan elements, or its character data.
  private func svgViewLines(of text: SVGDocument.Element) -> [Int] {
    let children = text.children
    return children.isEmpty ? [text.textContent.count] : children.map(\.textContent.count)
  }

  func svgViewDidBeginTextEditing(_: SVGUIView, element: SVGDocument.Element) {
    model.element = element
    model.status = "Type. Tap outside the text to finish."
  }

  func svgView(_ view: SVGUIView, didChangeTextOf _: SVGDocument.Element, from _: String) {
    let text = view.editedText ?? ""
    let lines = text.split(separator: "\n", omittingEmptySubsequences: false).count
    model.status = "\(text.count) \(text.count == 1 ? "character" : "characters"), \(lines) \(lines == 1 ? "line" : "lines")"
  }

  func svgViewDidEndTextEditing(_: SVGUIView, element: SVGDocument.Element) {
    // A text left empty is removed.
    if element.textContent.isEmpty {
      element.remove()
      model.element = nil
    }
    model.status = "Tap the picture to add text, or a text to edit it."
  }
}
