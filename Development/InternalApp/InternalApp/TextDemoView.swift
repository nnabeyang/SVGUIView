import SVGUIView
import SwiftUI

/// The demonstration of typing text onto a picture, as Markup of the Photos app adds text to photos.
struct TextDemo: Hashable {}

/// Shows a picture where a tap adds a text and types into it. As in Markup:
///
/// - A tap on a text selects it with a frame, and a tap on the selected text, or a double tap on a text, edits it with
///   the caret at its end.
/// - One finger moves the selected text, and two fingers turn it about its center.
/// - A tap outside the text ends the editing, and a text left empty is removed.
///
/// The controls change the fill, the size, the alignment and the outline of the selected text. While a text is
/// edited, the picture keeps its size, and moves up only where the keyboard would cover the text.
struct TextDemoView: View {
  @State private var model = TextDemoModel()

  var body: some View {
    VStack(spacing: 12) {
      HStack {
        ColorPicker("Fill", selection: $model.fill, supportsOpacity: false)
          .labelsHidden()
        Stepper("\(model.fontSize)", value: $model.fontSize, in: 8...120, step: 4)
          .fixedSize()
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

      // While a text is edited, these change the selection, and otherwise the selected text.
      HStack {
        Button("Bold", systemImage: "bold") { model.toggle("font-weight", value: "bold") }
        Button("Italic", systemImage: "italic") { model.toggle("font-style", value: "italic") }
        Button("Underline", systemImage: "underline") { model.toggle("text-decoration", value: "underline") }
        Spacer()
        Button("Undo", systemImage: "arrow.uturn.backward") { model.undo() }
          .disabled(!model.canUndo)
      }
      .labelStyle(.iconOnly)
      .buttonStyle(.bordered)
      .padding(.horizontal)

      TextCanvasView(model: model)
        .modifier(Pane(title: "SVGUIView", size: 1, isVisible: true))
        .padding(.horizontal)

      Text(model.status)
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    .padding(.vertical)
    // The picture keeps its size when the keyboard shows, and the canvas moves it up instead where it has to.
    .ignoresSafeArea(.keyboard)
    .navigationTitle("Type Text")
    .navigationBarTitleDisplayMode(.inline)
    .onChange(of: model.fill) { model.applyFill() }
    .onChange(of: model.fontSize) { model.applyStyle() }
    .onChange(of: model.anchor) { model.applyStyle() }
    .onChange(of: model.outlined) { model.applyStyle() }
  }
}

/// The text that the controls change, and what the demonstration tells.
@MainActor
@Observable
final class TextDemoModel {
  var fill = Color.white
  var fontSize = 36
  var anchor = "start"
  var outlined = true
  var status = "Tap the picture to add text."
  /// The selected text, which the controls change.
  var element: SVGDocument.Element?
  /// Called after the style of the selected text changed, which moves its frame.
  @ObservationIgnored var styleDidChange: (() -> Void)?
  /// The view that edits the text, while a text is edited.
  @ObservationIgnored weak var editor: SVGUIView?
  /// The changes of the texts, the latest last, which undo puts back: each text with its styled text before.
  @ObservationIgnored private var undoStack = [(SVGDocument.Element, SVGStyledText)]()
  var canUndo = false

  /// Remembers a change of a text, which undo puts back.
  func registerUndo(of element: SVGDocument.Element, from oldText: SVGStyledText) {
    undoStack.append((element, oldText))
    canUndo = true
  }

  /// Puts the latest change of a text back.
  func undo() {
    guard let (element, oldText) = undoStack.popLast() else { return }
    element.setStyledText(oldText)
    canUndo = !undoStack.isEmpty
    styleDidChange?()
  }

  /// The fill of the controls as an SVG color.
  private var fillValue: String {
    let color = UIColor(fill).resolvedColor(with: .current)
    var red: CGFloat = 0
    var green: CGFloat = 0
    var blue: CGFloat = 0
    color.getRed(&red, green: &green, blue: &blue, alpha: nil)
    return "rgb(\(Int(red * 255)), \(Int(green * 255)), \(Int(blue * 255)))"
  }

  /// Sets the fill of the selection while a text is edited, or of the selected text otherwise.
  func applyFill() {
    if let editor, editor.editedTextElement != nil {
      editor.setTextAttribute("fill", to: fillValue)
    } else {
      applyStyle()
    }
  }

  /// Sets an attribute of the selection while a text is edited, or of the selected text otherwise, or removes it
  /// where all of it has the attribute.
  func toggle(_ name: String, value: String) {
    if let editor, editor.editedTextElement != nil {
      // The view toggles the selection as it looks, also where the text inherits the attribute.
      switch name {
      case "font-weight": editor.toggleBoldface(nil)
      case "font-style": editor.toggleItalics(nil)
      default: editor.toggleUnderline(nil)
      }
    } else if let element {
      if element.attribute(name) == value {
        element.removeAttribute(name)
      } else {
        element.setAttribute(name, to: value)
      }
      styleDidChange?()
    }
  }

  /// Sets the style of the controls on the selected text.
  func applyStyle() {
    guard let element else { return }
    element.setAttribute("fill", to: fillValue)
    element.setAttribute("font-size", to: "\(fontSize)")
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
    styleDidChange?()
  }

  /// Shows the style of a text in the controls.
  func read(_ element: SVGDocument.Element) {
    fontSize = Int(element.attribute("font-size") ?? "") ?? fontSize
    anchor = element.attribute("text-anchor") ?? anchor
  }
}

/// The view of the picture, which adds, selects, moves, turns and edits texts where fingers touch it.
private struct TextCanvasView: UIViewRepresentable {
  let model: TextDemoModel

  func makeUIView(context _: Context) -> TextCanvas {
    TextCanvas(model: model)
  }

  func updateUIView(_: TextCanvas, context _: Context) {}
}

/// Where a text is moved and how far it's turned, which its `transform` attribute has.
private struct Placement {
  var offset = CGPoint.zero
  /// The angle in degrees, about the center of the text.
  var angle: CGFloat = 0
  /// The center of the text in its user space, without the transform, which it turns about.
  var center = CGPoint.zero

  var attribute: String {
    "translate(\(offset.x) \(offset.y)) rotate(\(angle) \(center.x) \(center.y))"
  }
}

private final class TextCanvas: UIView, SVGUIViewTextEditingDelegate, UIGestureRecognizerDelegate {
  private let model: TextDemoModel
  private let svgView: SVGUIView
  /// The frame of the selected text.
  private let frameLayer = CAShapeLayer()
  /// The placement of each text, which the gestures change.
  private var placements = [SVGDocument.Element: Placement]()
  /// The frame of the selected text in the coordinates of the canvas, which the gestures hit-test.
  private var selectedFrame: CGPath?
  /// The placement when a gesture began.
  private var startPlacement = Placement()
  /// Where the finger that moves the text touched the view, from which the text follows it, so that it doesn't lag
  /// by the distance that the gesture waits for before it begins.
  private var touchDown = CGPoint.zero
  /// The top of the keyboard in the window, or `nil` while it's hidden.
  private var keyboardTop: CGFloat?
  /// The gesture that moves the selected text, which the gesture of the navigation that goes back waits for.
  private var pan: UIPanGestureRecognizer?

  /// A picture in place of a photo: a sky, a sun and hills.
  private static let picture = #"""
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 360 480" font-family="Helvetica" font-weight="bold">
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
    clipsToBounds = true
    svgView.contentMode = .scaleAspectFit
    svgView.textEditingDelegate = self
    // A person also toggles bold, italic and underline with the edit menu and the keyboard.
    svgView.allowsEditingTextAttributes = true
    model.editor = svgView
    svgView.translatesAutoresizingMaskIntoConstraints = false
    addSubview(svgView)
    NSLayoutConstraint.activate([
      svgView.leadingAnchor.constraint(equalTo: leadingAnchor),
      svgView.trailingAnchor.constraint(equalTo: trailingAnchor),
      svgView.topAnchor.constraint(equalTo: topAnchor),
      svgView.bottomAnchor.constraint(equalTo: bottomAnchor),
    ])
    frameLayer.fillColor = nil
    frameLayer.strokeColor = UIColor.systemBlue.cgColor
    frameLayer.lineWidth = 1.5
    layer.addSublayer(frameLayer)

    let doubleTap = UITapGestureRecognizer(target: self, action: #selector(doubleTap(_:)))
    doubleTap.numberOfTapsRequired = 2
    let tap = UITapGestureRecognizer(target: self, action: #selector(tap(_:)))
    tap.require(toFail: doubleTap)
    let pan = UIPanGestureRecognizer(target: self, action: #selector(pan(_:)))
    pan.maximumNumberOfTouches = 1
    self.pan = pan
    let rotation = UIRotationGestureRecognizer(target: self, action: #selector(rotate(_:)))
    for gesture in [doubleTap, tap, pan, rotation] {
      gesture.delegate = self
      svgView.addGestureRecognizer(gesture)
    }
    model.styleDidChange = { [weak self] in self?.updateFrame() }
    NotificationCenter.default.addObserver(
      self, selector: #selector(keyboardWillChange(_:)), name: UIResponder.keyboardWillChangeFrameNotification,
      object: nil)
    NotificationCenter.default.addObserver(
      self, selector: #selector(keyboardWillChange(_:)), name: UIResponder.keyboardWillHideNotification, object: nil)
  }

  /// A swipe anywhere goes back in the navigation, so it waits until the finger isn't moving the selected text.
  override func didMoveToWindow() {
    super.didMoveToWindow()
    guard let pan else { return }
    var responder: UIResponder? = self
    while let next = responder?.next {
      if let navigation = next as? UINavigationController {
        if #available(iOS 26.0, *) {
          navigation.interactiveContentPopGestureRecognizer?.require(toFail: pan)
        }
        navigation.interactivePopGestureRecognizer?.require(toFail: pan)
        break
      }
      responder = next
    }
  }

  required init?(coder _: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  // MARK: - Gestures

  /// The view handles the touches of the text that is edited, and the gestures move and turn only the selected text.
  func gestureRecognizer(_ gesture: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
    guard svgView.editedTextElement == nil else { return false }
    switch gesture {
    case is UIPanGestureRecognizer:
      guard let selectedFrame, selectedFrame.contains(touch.location(in: self)) else { return false }
      touchDown = touch.location(in: svgView)
      return true
    case is UIRotationGestureRecognizer:
      return model.element != nil
    default:
      return true
    }
  }

  /// Lets two fingers turn the text while one of them moves it.
  func gestureRecognizer(
    _: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
  ) -> Bool {
    other is UIRotationGestureRecognizer || other is UIPanGestureRecognizer
  }

  /// The text at a point of the view: a `text` element, or the one of a line that a `tspan` element is.
  private func text(at point: CGPoint) async -> SVGDocument.Element? {
    guard let hit = await svgView.document.element(at: point, tolerance: 8) else { return nil }
    if hit.localName == "text" { return hit }
    return hit.parent.flatMap { $0.localName == "text" ? $0 : nil }
  }

  @objc private func tap(_ gesture: UITapGestureRecognizer) {
    let point = gesture.location(in: svgView)
    Task {
      if let text = await text(at: point) {
        // A tap on the selected text edits it, and one on another text selects that.
        if text == model.element {
          await svgView.beginTextEditing(of: text)
        } else {
          select(text)
        }
        return
      }
      if model.element != nil {
        // A tap outside the selected text deselects it.
        select(nil)
        return
      }
      await addText(at: point)
    }
  }

  @objc private func doubleTap(_ gesture: UITapGestureRecognizer) {
    let point = gesture.location(in: svgView)
    Task {
      guard let text = await text(at: point) else { return }
      select(text)
      // As in Markup, the caret is at the end of the text.
      await svgView.beginTextEditing(of: text)
    }
  }

  @objc private func pan(_ gesture: UIPanGestureRecognizer) {
    guard let element = model.element else { return }
    switch gesture.state {
    case .began:
      startPlacement = placements[element] ?? Placement()
    case .changed:
      // The finger moves in the view, which shows the document at another scale.
      let location = gesture.location(in: svgView)
      let translation = CGPoint(x: location.x - touchDown.x, y: location.y - touchDown.y)
      let scale = documentScale()
      var placement = placements[element] ?? startPlacement
      placement.offset = CGPoint(
        x: startPlacement.offset.x + translation.x / scale, y: startPlacement.offset.y + translation.y / scale)
      place(element, placement)
    default:
      break
    }
  }

  @objc private func rotate(_ gesture: UIRotationGestureRecognizer) {
    guard let element = model.element else { return }
    switch gesture.state {
    case .changed:
      var placement = placements[element] ?? Placement()
      placement.angle += gesture.rotation * 180 / .pi
      gesture.rotation = 0
      place(element, placement)
    default:
      break
    }
  }

  // MARK: - Texts

  /// The scale from the user space of the document to the view, for the moves of the fingers.
  private func documentScale() -> CGFloat {
    // The picture is 360 by 480, which `scaleAspectFit` fits in the view.
    min(svgView.bounds.width / 360, svgView.bounds.height / 480)
  }

  /// Sets the placement of a text with its `transform` attribute. The document is small, so the text is moved as the
  /// fingers move; a large document moves a stand-in instead, as the drag demonstration does.
  private func place(_ element: SVGDocument.Element, _ placement: Placement) {
    placements[element] = placement
    element.setAttribute("transform", to: placement.attribute)
    updateFrame()
  }

  private func addText(at point: CGPoint) async {
    let document = svgView.document
    guard let root = document.rootElement, let transform = await root.transformToView() else { return }
    let location = point.applying(transform.inverted())
    let text = document.createElement("text")
    text.setAttribute("x", to: "\(Int(location.x))")
    text.setAttribute("y", to: "\(Int(location.y))")
    try? root.append(text)
    select(text)
    model.applyStyle()
    await svgView.beginTextEditing(of: text)
  }

  private func select(_ element: SVGDocument.Element?) {
    model.element = element
    if let element {
      model.read(element)
      model.status = "Drag the text, or turn it with two fingers. Tap it again to type."
    } else {
      model.status = "Tap the picture to add text, or a text to select it."
    }
    updateFrame()
  }

  /// Draws the frame of the selected text: its bounding box with its transform, in the coordinates of the canvas.
  private func updateFrame() {
    guard let element = model.element, svgView.editedTextElement == nil else {
      frameLayer.path = nil
      selectedFrame = nil
      return
    }
    Task {
      guard let box = await element.boundingBox(), let transform = await element.transformToView(),
        model.element == element, svgView.editedTextElement == nil
      else { return }
      // A text turns about its center, which is found once, before it's moved or turned.
      if placements[element] == nil {
        placements[element] = Placement(center: CGPoint(x: box.midX, y: box.midY))
      }
      let margin: CGFloat = 6
      let frame = box.insetBy(dx: -margin, dy: -margin)
      let corners = [
        CGPoint(x: frame.minX, y: frame.minY), CGPoint(x: frame.maxX, y: frame.minY),
        CGPoint(x: frame.maxX, y: frame.maxY), CGPoint(x: frame.minX, y: frame.maxY),
      ].map { svgView.convert($0.applying(transform), to: self) }
      let path = CGMutablePath()
      path.addLines(between: corners)
      path.closeSubpath()
      frameLayer.path = path
      // A finger also hits the frame a little outside it.
      selectedFrame = path.copy(strokingWithWidth: 24, lineCap: .round, lineJoin: .round, miterLimit: 1).union(path)
    }
  }

  // MARK: - Keyboard

  @objc private func keyboardWillChange(_ notification: Notification) {
    let frame = (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect) ?? .null
    keyboardTop = notification.name == UIResponder.keyboardWillHideNotification || frame.isNull ? nil : frame.minY
    avoidKeyboard()
  }

  /// Moves the picture up as far as the keyboard would cover the edited text, with a margin, and back when it
  /// wouldn't.
  private func avoidKeyboard() {
    var shift: CGFloat = 0
    if let keyboardTop, svgView.editedTextElement != nil,
      let range = svgView.textRange(from: svgView.beginningOfDocument, to: svgView.endOfDocument)
    {
      // The bottom of the edited text in the window, without the move. The caret and the lines of a turned text are
      // rectangles in a frame that their transforms turn into the coordinates of the view.
      let end = svgView.endOfDocument
      var text = svgView.caretRect(for: end).applying(svgView.caretTransform(for: end))
      for rect in svgView.selectionRects(for: range) { text = text.union(rect.rect.applying(rect.transform)) }
      let bottom = svgView.convert(text, to: nil).maxY - svgView.transform.ty
      shift = min(0, keyboardTop - 16 - bottom)
    }
    guard svgView.transform.ty != shift else { return }
    UIView.animate(withDuration: 0.25) {
      self.svgView.transform = CGAffineTransform(translationX: 0, y: shift)
    }
  }

  // MARK: - Editing

  func svgViewDidBeginTextEditing(_: SVGUIView, element: SVGDocument.Element) {
    model.element = element
    model.read(element)
    frameLayer.path = nil
    selectedFrame = nil
    model.status = "Type. Tap outside the text to finish."
    avoidKeyboard()
  }

  func svgView(
    _ view: SVGUIView, didChangeTextOf element: SVGDocument.Element, fromStyledText oldText: SVGStyledText
  ) {
    model.registerUndo(of: element, from: oldText)
    let text = view.editedText ?? ""
    let lines = text.split(separator: "\n", omittingEmptySubsequences: false).count
    model.status =
      "\(text.count) \(text.count == 1 ? "character" : "characters"), \(lines) \(lines == 1 ? "line" : "lines")"
    // A new line can go under the keyboard.
    avoidKeyboard()
  }

  func svgViewDidEndTextEditing(_: SVGUIView, element: SVGDocument.Element) {
    // A text left empty is removed, and one with text stays selected.
    if element.textContent.isEmpty {
      element.remove()
      placements[element] = nil
      select(nil)
    } else {
      select(element)
    }
    avoidKeyboard()
  }
}
