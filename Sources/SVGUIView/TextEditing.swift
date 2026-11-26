import SVGCore
import UIKit

/// The methods that a view calls while a person types into a `text` element of its document, which an app adopts to
/// know when the editing begins and ends, and to undo the changes of the text.
///
/// Each method does nothing by default, and the view ends the editing at a tap outside the text.
@MainActor
public protocol SVGUIViewTextEditingDelegate: AnyObject {
  /// The editing of a `text` element began, and the view shows the keyboard.
  func svgViewDidBeginTextEditing(_ view: SVGUIView, element: SVGDocument.Element)
  /// The text of the element changed, from the text before it, which an app can register to undo.
  ///
  /// The text is the one that ``SVGUIView/editedText`` gives, with a line feed between the lines. Characters that the
  /// keyboard marks while they're composed, such as Japanese before it's converted, change the text once when
  /// they're committed.
  func svgView(_ view: SVGUIView, didChangeTextOf element: SVGDocument.Element, from oldText: String)
  /// The text of the element or the attributes of its runs changed, from the styled text before it, which an app can
  /// register to undo with ``SVGDocument/Element/setStyledText(_:)``.
  ///
  /// The view calls this method for every change, also of the attributes alone, such as
  /// ``SVGUIView/setTextAttribute(_:to:in:)`` makes. By default, it calls
  /// ``svgView(_:didChangeTextOf:from:)`` with the characters of the text, so that an app that adopts only that
  /// method hears about the changes.
  func svgView(_ view: SVGUIView, didChangeTextOf element: SVGDocument.Element, fromStyledText oldText: SVGStyledText)
  /// The editing of the element ended, and the view hid the keyboard. An app can remove an element that has no text
  /// left.
  func svgViewDidEndTextEditing(_ view: SVGUIView, element: SVGDocument.Element)
  /// Whether a tap at a point of the view, outside the text that is edited, ends the editing.
  func svgView(_ view: SVGUIView, shouldEndTextEditingAt point: CGPoint) -> Bool
}

extension SVGUIViewTextEditingDelegate {
  public func svgViewDidBeginTextEditing(_: SVGUIView, element _: SVGDocument.Element) {}
  public func svgView(_: SVGUIView, didChangeTextOf _: SVGDocument.Element, from _: String) {}
  public func svgView(
    _ view: SVGUIView, didChangeTextOf element: SVGDocument.Element, fromStyledText oldText: SVGStyledText
  ) {
    svgView(view, didChangeTextOf: element, from: oldText.string)
  }
  public func svgViewDidEndTextEditing(_: SVGUIView, element _: SVGDocument.Element) {}
  public func svgView(_: SVGUIView, shouldEndTextEditingAt _: CGPoint) -> Bool { true }
}

/// A position in the text that is edited, as the number of characters before it.
final class TextEditingPosition: UITextPosition {
  let offset: Int

  init(_ offset: Int) {
    self.offset = offset
  }

  override var description: String { "\(offset)" }
}

/// A range of the text that is edited.
final class TextEditingRange: UITextRange {
  let range: Range<Int>

  init(_ range: Range<Int>) {
    self.range = range
  }

  override var start: UITextPosition { TextEditingPosition(range.lowerBound) }
  override var end: UITextPosition { TextEditingPosition(range.upperBound) }
  override var isEmpty: Bool { range.isEmpty }
}

/// The rectangle of a line of the selection.
final class TextEditingSelectionRect: UITextSelectionRect {
  private let storedRect: CGRect
  private let storedContainsStart: Bool
  private let storedContainsEnd: Bool
  private let storedIsVertical: Bool
  private let storedTransform: CGAffineTransform

  init(rect: CGRect, containsStart: Bool, containsEnd: Bool, isVertical: Bool, transform: CGAffineTransform) {
    storedRect = rect
    storedContainsStart = containsStart
    storedContainsEnd = containsEnd
    storedIsVertical = isVertical
    storedTransform = transform
  }

  override var rect: CGRect { storedRect }
  override var writingDirection: NSWritingDirection { .natural }
  override var containsStart: Bool { storedContainsStart }
  override var containsEnd: Bool { storedContainsEnd }
  override var isVertical: Bool { storedIsVertical }
  override var transform: CGAffineTransform { storedTransform }
}

/// A rectangle that a transform turns in the coordinates of the view, as `UITextInput` tells the caret and the
/// selection of a turned text. UIKit draws the caret with its transform about the origin of the view, while the
/// loupe is placed by the rectangle alone, so the rectangle is where the turned one is, and the transform turns it
/// about its center, with the translation that this takes.
struct TurnedRect {
  /// The rectangle before it's turned, at the center of the turned one.
  var rect: CGRect
  /// The transform that turns the rectangle into the coordinates of the view.
  var transform: CGAffineTransform

  /// The rectangle around points of the view along an angle: the upright rectangle at the center of the points, of
  /// the size of the rectangle along the angle, and the rotation by the angle about its center.
  ///
  /// The rectangle is where the turned one is, so that what reads it without its transform finds the right place, as
  /// the loupe of the text interaction does with the caret. With its transform, it's the turned one, whether the
  /// transform is applied about the origin of the view or about the center of the rectangle.
  init(around points: [CGPoint], angle: CGFloat) {
    let path = CGMutablePath()
    guard angle != 0 else {
      path.addLines(between: points)
      rect = path.boundingBoxOfPath
      transform = .identity
      return
    }
    let rotation = CGAffineTransform(rotationAngle: angle)
    path.addLines(between: points.map { $0.applying(rotation.inverted()) })
    let turned = path.boundingBoxOfPath
    let center = CGPoint(x: turned.midX, y: turned.midY).applying(rotation)
    rect = CGRect(
      x: center.x - turned.width / 2, y: center.y - turned.height / 2, width: turned.width, height: turned.height)
    transform = CGAffineTransform(translationX: -center.x, y: -center.y)
      .concatenating(rotation)
      .concatenating(CGAffineTransform(translationX: center.x, y: center.y))
  }

  init(rect: CGRect, transform: CGAffineTransform) {
    self.rect = rect
    self.transform = transform
  }

  /// The corners of the turned rectangle in the coordinates of the view.
  var corners: [CGPoint] {
    [
      CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
      CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY),
    ].map { $0.applying(transform) }
  }

  /// Whether a point of the view is in the turned rectangle.
  func contains(_ point: CGPoint) -> Bool {
    rect.contains(point.applying(transform.inverted()))
  }

  /// The square of the distance from a point of the view to the rectangle.
  func squaredDistance(to point: CGPoint) -> CGFloat {
    let local = point.applying(transform.inverted())
    let dx = max(rect.minX - local.x, 0, local.x - rect.maxX)
    let dy = max(rect.minY - local.y, 0, local.y - rect.maxY)
    return dx * dx + dy * dy
  }
}

/// The view that draws the caret of the text that is edited, which turns its bar by the angle of the text.
///
/// The caret of a turned text is an upright rectangle at its center, without a transform. UIKit places this view
/// there, and also places a copy of it, of the same class, while a person drags the caret with the loupe, so both turn
/// the bar about their centers. The view finds the angle in the `SVGUIView` that it's in.
final class TextCursorView: UIStandardTextCursorView {
  override func didMoveToSuperview() {
    super.didMoveToSuperview()
    setNeedsLayout()
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    var ancestor = superview
    while let view = ancestor, !(view is SVGUIView) {
      ancestor = view.superview
    }
    let angle = (ancestor as? SVGUIView)?.textEditing?.angle ?? 0
    layer.sublayerTransform =
      angle == 0 ? CATransform3DIdentity : CATransform3DMakeAffineTransform(CGAffineTransform(rotationAngle: angle))
  }
}

/// The `text` element that a person types into, its text, and the selection.
@MainActor
final class TextEditingSession: NSObject, UITextInteractionDelegate, UITextSelectionDisplayInteractionDelegate {
  let element: SVGDocument.Element
  weak var view: SVGUIView?
  /// The characters of the text, with a line feed between the lines.
  var text: [Character]
  /// The attributes of the run of each character, which are none for a line feed.
  var attributes: [[String: String]]
  /// The attributes of the characters that are typed next, which an attribute that is set without a selection gives,
  /// or `nil` for the attributes of the characters around the caret. Moving the selection removes them.
  var typingAttributes: [String: String]?
  var selection: Range<Int>
  /// The characters that the keyboard marks while they're composed, or `nil`.
  var marked: Range<Int>?
  /// The text before the marked characters began, which the change that commits them changes from.
  var textBeforeMarking: SVGStyledText?
  var markedTextStyle: [NSAttributedString.Key: Any]?
  weak var inputDelegate: (any UITextInputDelegate)?
  /// The transform from the user space of the text to the coordinates of the view.
  var transform: CGAffineTransform = .identity {
    didSet {
      // The caret turns its bar by the angle of the text.
      display?.cursorView.setNeedsLayout()
    }
  }

  /// The angle that the text is turned by in the view, which turns its caret and its selection. The baseline of a
  /// horizontal line, or the x-axis of the text, goes along it.
  var angle: CGFloat {
    transform.b == 0 && transform.a >= 0 ? 0 : atan2(transform.b, transform.a)
  }
  /// Whether the lines are vertical, which `writing-mode` decides.
  let isVertical: Bool
  /// The interaction that shows the caret, the selection, the loupe and the edit menu.
  let interaction = UITextInteraction(for: .editable)
  /// The interaction that draws the caret and the selection, which the text interaction has, or one of the session.
  var display: UITextSelectionDisplayInteraction?
  /// Whether the session added the display interaction, which it removes at the end.
  var addsDisplay = false
  /// The view that drew the caret of the display interaction before the session, which it draws with again at the end.
  var replacedCursorView: (any UIView & UITextCursorView)?
  /// The line under the marked characters.
  let markLayer = CAShapeLayer()
  /// Where the characters are, which the changes of the text find again.
  private var cachedLayout: (text: [Character], characters: [CharacterGeometry?])??

  init(element: SVGDocument.Element, view: SVGUIView, text: SVGStyledText, isVertical: Bool) {
    self.element = element
    self.view = view
    self.text = Array(text.string)
    attributes = Self.lineFeedsWithoutAttributes(Array(text.string), text.characterAttributes)
    self.isVertical = isVertical
    selection = self.text.count..<self.text.count
    super.init()
    markLayer.fillColor = nil
    markLayer.strokeColor = UIColor.tintColor.cgColor
    markLayer.lineWidth = 2
  }

  /// The text with the attributes of its runs.
  var styledText: SVGStyledText {
    SVGStyledText(characters: text, attributes: attributes)
  }

  /// The attributes of characters, with none for the line feeds, which aren't in a run.
  static func lineFeedsWithoutAttributes(_ text: [Character], _ attributes: [[String: String]]) -> [[String: String]] {
    zip(text, attributes).map { $0 == "\n" ? [:] : $1 }
  }

  /// The attributes that a character typed in place of a range takes: the typing attributes, or the ones of the
  /// character before it in its line, or else of the character after it in its line.
  func inheritedAttributes(at range: Range<Int>) -> [String: String] {
    if let typingAttributes { return typingAttributes }
    // A selection that is replaced gives the attributes of its first character.
    if !range.isEmpty, text[range.lowerBound] != "\n" {
      return attributes[range.lowerBound]
    }
    if range.lowerBound > 0, text[range.lowerBound - 1] != "\n" {
      return attributes[range.lowerBound - 1]
    }
    if range.upperBound < text.count, text[range.upperBound] != "\n" {
      return attributes[range.upperBound]
    }
    return [:]
  }

  /// Reads the text of the element again, after an app changed it, and keeps the selection in it.
  func reload() -> Bool {
    guard let styled = element.styledText else { return false }
    text = Array(styled.string)
    attributes = Self.lineFeedsWithoutAttributes(text, styled.characterAttributes)
    selection = selection.clamped(to: 0..<text.count)
    marked = nil
    textBeforeMarking = nil
    typingAttributes = nil
    invalidateLayout()
    return true
  }

  /// The rendered characters and where they are, in the user space of the text.
  var layout: (text: [Character], characters: [CharacterGeometry?])? {
    if let cachedLayout { return cachedLayout }
    let found = view?.editedCharacterGeometry(of: element.id)
    cachedLayout = .some(found)
    return found
  }

  func invalidateLayout() {
    cachedLayout = nil
  }

  func interactionShouldBegin(_ interaction: UITextInteraction, at point: CGPoint) -> Bool {
    guard let view else { return true }
    // A tap outside the text ends the editing, unless the delegate keeps it, as a tap outside a text view does. The
    // text is the rectangle along its angle around its caret and lines, so that a tap away from a turned text ends it
    // too, and a tap just outside the lines ends it at any scale of the view.
    guard !view.editedTextArea(of: self).contains(point) else { return true }
    if view.textEditingDelegate?.svgView(view, shouldEndTextEditingAt: point) ?? true {
      view.endTextEditing()
      return false
    }
    return true
  }
}

// MARK: - Beginning and ending

extension SVGUIView {
  /// The text element that a person types into, or `nil` if the view doesn't edit text.
  public var editedTextElement: SVGDocument.Element? {
    textEditing?.element
  }

  /// The text that a person types into, with a line feed between the lines, or `nil` if the view doesn't edit text.
  public var editedText: String? {
    textEditing.map { String($0.text) }
  }

  /// Begins the editing of a `text` element, where a person types and selects text as in a text field, and returns
  /// whether it began.
  ///
  /// The view becomes the first responder, shows the keyboard, and shows the caret, the selection, the loupe and the
  /// edit menu over the text. Japanese and other text that the keyboard composes is shown in the text, underlined,
  /// until it's committed. A tap outside the text, ``endTextEditing()`` and new data end the editing, and the
  /// ``textEditingDelegate`` hears about the changes.
  ///
  /// The element is a `text` element of the document that the view shows, in a window, whose content is a line of
  /// character data and `tspan` elements of runs, or `tspan` elements that are lines of them: each line with an `x`
  /// attribute, or a `y` attribute in vertical text. The `tspan` of a run has no position attributes and no child
  /// elements, and ``SVGDocument/Element/styledText`` reads its attributes. The editing sets
  /// `xml:space="preserve"`, so that spaces are kept, and writes a text of more than one line as lines of that form,
  /// the next one `1.2em` after the one before it.
  ///
  /// - Parameters:
  ///   - element: The `text` element to edit.
  ///   - range: The characters to select, counted in `Character`s of the text with a line feed between the lines, or
  ///     `nil` to put the caret at the end.
  /// - Returns: `false` if the element isn't such a `text` element, or the view isn't in a window.
  @discardableResult
  public func beginTextEditing(of element: SVGDocument.Element, selecting range: Range<Int>? = nil) async -> Bool {
    guard element.document === document, element.isConnected, element.localName == "text", window != nil else {
      return false
    }
    guard let styled = element.styledText else { return false }
    endTextEditing()
    let session = TextEditingSession(
      element: element, view: self, text: styled, isVertical: StyledTextContent.isVertical(element))
    element.setAttribute("xml:space", to: "preserve")
    // Character data between the lines would be rendered with the spaces kept, so the text is written again in the
    // form that the editing writes, which keeps what's already in that form.
    StyledTextContent.write(styled, into: element)
    if let range {
      session.selection = range.clamped(to: 0..<session.text.count)
    }
    textEditing = session
    session.transform = await element.transformToView() ?? .identity
    // The editing can have ended while the transform was found.
    guard textEditing === session else { return false }
    session.interaction.textInput = self
    session.interaction.delegate = session
    addInteraction(session.interaction)
    // The caret and the selection are drawn by the display interaction, which a custom text view activates when it
    // becomes the first responder, as Apple's "Adopting system selection UI in custom text views" describes.
    if let display = interactions.lazy.compactMap({ $0 as? UITextSelectionDisplayInteraction }).first {
      session.display = display
    } else {
      let display = UITextSelectionDisplayInteraction(textInput: self, delegate: session)
      addInteraction(display)
      session.display = display
      session.addsDisplay = true
    }
    layer.addSublayer(session.markLayer)
    if let display = session.display {
      session.replacedCursorView = display.cursorView
      display.cursorView = TextCursorView(frame: .zero)
    }
    becomeFirstResponder()
    session.display?.isActivated = true
    session.display?.setNeedsSelectionUpdate()
    // The interaction shows the caret where the selection is, once the keyboard is connected to the view, which
    // gives the view its input delegate after it becomes the first responder.
    Task { @MainActor [weak self] in
      await Task.yield()
      guard let self, textEditing === session else { return }
      session.inputDelegate?.selectionWillChange(self)
      session.inputDelegate?.selectionDidChange(self)
    }
    textEditingDelegate?.svgViewDidBeginTextEditing(self, element: element)
    return true
  }

  /// Finds the transform of the text that is edited again, after the view or how it places the document changed, and
  /// shows the caret and the selection there.
  func refreshTextEditingTransform() {
    guard let session = textEditing else { return }
    Task {
      guard let transform = await session.element.transformToView(), textEditing === session else { return }
      session.inputDelegate?.selectionWillChange(self)
      session.transform = transform
      updateMarkLayer(of: session)
      session.inputDelegate?.selectionDidChange(self)
      session.display?.setNeedsSelectionUpdate()
    }
  }

  /// Ends the editing of text, commits the characters that the keyboard composes, and hides the keyboard. It does
  /// nothing if the view doesn't edit text.
  public func endTextEditing() {
    guard let session = textEditing else { return }
    if session.marked != nil {
      unmarkText()
    }
    textEditing = nil
    session.display?.isActivated = false
    if let display = session.display, let cursorView = session.replacedCursorView {
      display.cursorView = cursorView
    }
    if session.addsDisplay, let display = session.display {
      removeInteraction(display)
    }
    removeInteraction(session.interaction)
    session.markLayer.removeFromSuperlayer()
    resignFirstResponder()
    textEditingDelegate?.svgViewDidEndTextEditing(self, element: session.element)
  }

  /// The rectangle along the angle of the text that is edited around its caret and its lines, in the coordinates of
  /// the view. It's the bounds of the caret and the lines for a text that isn't turned.
  func editedTextArea(of session: TextEditingSession) -> TurnedRect {
    var corners = caret(at: session.selection.lowerBound, in: session).corners
    for rect in selectionRects(for: TextEditingRange(0..<session.text.count)) {
      corners += TurnedRect(rect: rect.rect, transform: rect.transform).corners
    }
    return TurnedRect(around: corners, angle: session.angle)
  }

  // MARK: - Changing the text

  /// Replaces characters of the text, and puts the selection and the marked characters where they're given.
  private func replace(
    _ range: Range<Int>, with characters: [Character], selection: Range<Int>, marked: Range<Int>?,
    notifies: Bool = false
  ) {
    guard let session = textEditing else { return }
    let range = range.clamped(to: 0..<session.text.count)
    if notifies { session.inputDelegate?.textWillChange(self) }
    // The interaction moves the caret with the selection. The selection doesn't change while the keyboard composes
    // characters, which it marks.
    let movesSelection = session.marked == nil && marked == nil
    if movesSelection { session.inputDelegate?.selectionWillChange(self) }
    let old = session.styledText
    if session.marked == nil, marked != nil {
      session.textBeforeMarking = old
    }
    // The characters take the attributes of the typing or of the characters around them.
    let inherited = session.inheritedAttributes(at: range)
    session.text.replaceSubrange(range, with: characters)
    session.attributes.replaceSubrange(range, with: characters.map { $0 == "\n" ? [:] : inherited })
    session.selection = selection.clamped(to: 0..<session.text.count)
    session.marked = marked?.clamped(to: 0..<session.text.count)
    StyledTextContent.write(session.styledText, into: session.element)
    session.invalidateLayout()
    updateMarkLayer(of: session)
    if movesSelection { session.inputDelegate?.selectionDidChange(self) }
    session.display?.setNeedsSelectionUpdate()
    if notifies { session.inputDelegate?.textDidChange(self) }
    // The marked characters change the text once, when they're committed.
    if session.marked == nil, session.styledText != (session.textBeforeMarking ?? old) {
      textEditingDelegate?.svgView(
        self, didChangeTextOf: session.element, fromStyledText: session.textBeforeMarking ?? old)
    }
    if session.marked == nil {
      session.textBeforeMarking = nil
    }
  }

  func updateMarkLayer(of session: TextEditingSession) {
    guard let marked = session.marked, !marked.isEmpty else {
      session.markLayer.path = nil
      return
    }
    let path = CGMutablePath()
    for rect in selectionRects(for: TextEditingRange(marked)) {
      let line = rect.rect
      if session.isVertical {
        path.move(to: CGPoint(x: line.minX, y: line.minY), transform: rect.transform)
        path.addLine(to: CGPoint(x: line.minX, y: line.maxY), transform: rect.transform)
      } else {
        path.move(to: CGPoint(x: line.minX, y: line.maxY), transform: rect.transform)
        path.addLine(to: CGPoint(x: line.maxX, y: line.maxY), transform: rect.transform)
      }
    }
    session.markLayer.path = path
  }

  // MARK: - Geometry

  /// The point on the baseline where a caret at an offset of the text stands, and the vectors from it to the top and
  /// the bottom of the line, in the user space of the text.
  private func caretGeometry(at offset: Int, in session: TextEditingSession) -> (
    point: CGPoint, ascent: CGPoint, descent: CGPoint
  ) {
    let text = session.text
    let offset = min(max(offset, 0), text.count)
    let characters = session.layout?.characters ?? []
    // The index of each character among the rendered characters, which leave out the line feeds.
    func rendered(_ offset: Int) -> Int { offset - text[..<offset].count(where: { $0 == "\n" }) }
    let fontSize = Self.pixels(element: session.element, property: "font-size") ?? 16
    let defaultAscent = session.isVertical ? CGPoint(x: fontSize / 2, y: 0) : CGPoint(x: 0, y: -0.8 * fontSize)
    let defaultDescent = session.isVertical ? CGPoint(x: -fontSize / 2, y: 0) : CGPoint(x: 0, y: 0.2 * fontSize)
    if offset < text.count, text[offset] != "\n", characters.indices.contains(rendered(offset)),
      let character = characters[rendered(offset)]
    {
      return (character.start, character.ascent, character.descent)
    }
    if offset > 0, text[offset - 1] != "\n", characters.indices.contains(rendered(offset) - 1),
      let character = characters[rendered(offset) - 1]
    {
      return (character.end, character.ascent, character.descent)
    }
    // An empty line is a line after the nearest line with a character, or the position of the text.
    let line = text[..<offset].count(where: { $0 == "\n" })
    let lineHeight = 1.2 * fontSize
    var lineStarts = [Int]()
    var start = 0
    for (index, character) in text.enumerated() where character == "\n" {
      lineStarts.append(start)
      start = index + 1
    }
    lineStarts.append(start)
    for (other, lineStart) in lineStarts.enumerated() where lineStart < text.count && text[lineStart] != "\n" {
      guard characters.indices.contains(rendered(lineStart)), let character = characters[rendered(lineStart)] else {
        continue
      }
      let lines = CGFloat(line - other)
      let isLeft = (session.element.computedStyle.property("writing-mode") ?? "") == "vertical-rl"
      let shift =
        session.isVertical ? CGPoint(x: (isLeft ? -1 : 1) * lines * lineHeight, y: 0) : CGPoint(x: 0, y: lines * lineHeight)
      return (
        CGPoint(x: character.start.x + shift.x, y: character.start.y + shift.y), character.ascent, character.descent
      )
    }
    let x = Self.number(session.element.attribute("x")) ?? 0
    let y = Self.number(session.element.attribute("y")) ?? 0
    let shift = session.isVertical ? CGPoint(x: -CGFloat(line) * lineHeight, y: 0) : CGPoint(x: 0, y: CGFloat(line) * lineHeight)
    return (CGPoint(x: x + shift.x, y: y + shift.y), defaultAscent, defaultDescent)
  }

  /// The first number of a list of numbers or lengths in pixels, such as an `x` attribute.
  private static func number(_ text: String?) -> CGFloat? {
    guard let first = text?.split(whereSeparator: { $0 == " " || $0 == "," }).first else { return nil }
    return Double(first.hasSuffix("px") ? first.dropLast(2) : first).map { CGFloat($0) }
  }

  /// A computed value of an element in pixels.
  private static func pixels(element: SVGDocument.Element, property: String) -> CGFloat? {
    number(element.computedStyle.property(property))
  }
}

// MARK: - UITextInput

extension SVGUIView: UITextInput {
  public var hasText: Bool {
    !(textEditing?.text.isEmpty ?? true)
  }

  public func insertText(_ text: String) {
    guard let session = textEditing else { return }
    let range = session.marked ?? session.selection
    let characters = Array(text)
    let caret = range.lowerBound + characters.count
    replace(range, with: characters, selection: caret..<caret, marked: nil)
  }

  public func deleteBackward() {
    guard let session = textEditing else { return }
    var range = session.marked ?? session.selection
    if range.isEmpty {
      guard range.lowerBound > 0 else { return }
      range = (range.lowerBound - 1)..<range.lowerBound
    }
    replace(range, with: [], selection: range.lowerBound..<range.lowerBound, marked: nil)
  }

  public func text(in range: UITextRange) -> String? {
    guard let session = textEditing, let range = range as? TextEditingRange else { return nil }
    return String(session.text[range.range.clamped(to: 0..<session.text.count)])
  }

  public func replace(_ range: UITextRange, withText text: String) {
    guard let range = range as? TextEditingRange else { return }
    let characters = Array(text)
    let caret = range.range.lowerBound + characters.count
    replace(range.range, with: characters, selection: caret..<caret, marked: nil)
  }

  public var selectedTextRange: UITextRange? {
    get { textEditing.map { TextEditingRange($0.selection) } }
    set {
      guard let session = textEditing, let range = newValue as? TextEditingRange else { return }
      session.selection = range.range.clamped(to: 0..<session.text.count)
      session.typingAttributes = nil
      session.display?.setNeedsSelectionUpdate()
    }
  }

  public var markedTextRange: UITextRange? {
    textEditing?.marked.map { TextEditingRange($0) }
  }

  public var markedTextStyle: [NSAttributedString.Key: Any]? {
    get { textEditing?.markedTextStyle }
    set { textEditing?.markedTextStyle = newValue }
  }

  public func setMarkedText(_ markedText: String?, selectedRange: NSRange) {
    guard let session = textEditing else { return }
    let range = session.marked ?? session.selection
    let marked = markedText ?? ""
    let characters = Array(marked)
    // The selected range is in UTF-16 code units of the marked text.
    func characterOffset(_ utf16Offset: Int) -> Int {
      let index = String.Index(utf16Offset: min(max(utf16Offset, 0), marked.utf16.count), in: marked)
      return marked.distance(from: marked.startIndex, to: index)
    }
    let start = range.lowerBound
    let selectionStart = start + characterOffset(selectedRange.location)
    let selectionEnd = start + characterOffset(selectedRange.location + selectedRange.length)
    let newMarked: Range<Int>? = characters.isEmpty ? nil : start..<(start + characters.count)
    replace(range, with: characters, selection: selectionStart..<selectionEnd, marked: newMarked)
  }

  public func unmarkText() {
    guard let session = textEditing, let marked = session.marked else { return }
    let characters = Array(session.text[marked])
    replace(marked, with: characters, selection: session.selection, marked: nil)
  }

  public var beginningOfDocument: UITextPosition {
    TextEditingPosition(0)
  }

  public var endOfDocument: UITextPosition {
    TextEditingPosition(textEditing?.text.count ?? 0)
  }

  public func textRange(from fromPosition: UITextPosition, to toPosition: UITextPosition) -> UITextRange? {
    guard let from = fromPosition as? TextEditingPosition, let to = toPosition as? TextEditingPosition else {
      return nil
    }
    return TextEditingRange(min(from.offset, to.offset)..<max(from.offset, to.offset))
  }

  public func position(from position: UITextPosition, offset: Int) -> UITextPosition? {
    guard let position = position as? TextEditingPosition, let count = textEditing?.text.count else { return nil }
    let moved = position.offset + offset
    return (0...count).contains(moved) ? TextEditingPosition(moved) : nil
  }

  public func position(
    from position: UITextPosition, in direction: UITextLayoutDirection, offset: Int
  ) -> UITextPosition? {
    guard let session = textEditing, let position = position as? TextEditingPosition else { return nil }
    switch direction {
    case .left: return self.position(from: position, offset: -offset)
    case .right: return self.position(from: position, offset: offset)
    case .up, .down:
      // The position in the line before or after, at the same column, or at the end of a shorter line.
      let text = session.text
      var lineStarts = [0]
      for (index, character) in text.enumerated() where character == "\n" { lineStarts.append(index + 1) }
      guard let line = lineStarts.lastIndex(where: { $0 <= position.offset }) else { return nil }
      let column = position.offset - lineStarts[line]
      let target = line + (direction == .down ? offset : -offset)
      guard lineStarts.indices.contains(target) else { return nil }
      let end = target + 1 < lineStarts.count ? lineStarts[target + 1] - 1 : text.count
      return TextEditingPosition(min(lineStarts[target] + column, end))
    @unknown default:
      return nil
    }
  }

  public func compare(_ position: UITextPosition, to other: UITextPosition) -> ComparisonResult {
    guard let position = position as? TextEditingPosition, let other = other as? TextEditingPosition else {
      return .orderedSame
    }
    return position.offset < other.offset
      ? .orderedAscending : position.offset > other.offset ? .orderedDescending : .orderedSame
  }

  public func offset(from: UITextPosition, to toPosition: UITextPosition) -> Int {
    guard let from = from as? TextEditingPosition, let to = toPosition as? TextEditingPosition else { return 0 }
    return to.offset - from.offset
  }

  public var inputDelegate: (any UITextInputDelegate)? {
    get { textEditing?.inputDelegate }
    set { textEditing?.inputDelegate = newValue }
  }

  public var tokenizer: any UITextInputTokenizer {
    UITextInputStringTokenizer(textInput: self)
  }

  public func position(within range: UITextRange, farthestIn direction: UITextLayoutDirection) -> UITextPosition? {
    guard let range = range as? TextEditingRange else { return nil }
    switch direction {
    case .left, .up: return TextEditingPosition(range.range.lowerBound)
    default: return TextEditingPosition(range.range.upperBound)
    }
  }

  public func characterRange(
    byExtending position: UITextPosition, in direction: UITextLayoutDirection
  ) -> UITextRange? {
    guard let position = position as? TextEditingPosition, let count = textEditing?.text.count else { return nil }
    switch direction {
    case .left, .up: return TextEditingRange(max(position.offset - 1, 0)..<position.offset)
    default: return TextEditingRange(position.offset..<min(position.offset + 1, count))
    }
  }

  public func baseWritingDirection(
    for _: UITextPosition, in _: UITextStorageDirection
  ) -> NSWritingDirection {
    .natural
  }

  public func setBaseWritingDirection(_: NSWritingDirection, for _: UITextRange) {}

  public func firstRect(for range: UITextRange) -> CGRect {
    guard let range = range as? TextEditingRange else { return .null }
    return selectionRects(for: range).first?.rect ?? caretRect(for: range.start)
  }

  /// The caret at an offset of the text: a thin bar across the line, which the angle of the text turns.
  private func caret(at offset: Int, in session: TextEditingSession) -> TurnedRect {
    let (point, ascent, descent) = caretGeometry(at: offset, in: session)
    let top = CGPoint(x: point.x + ascent.x, y: point.y + ascent.y).applying(session.transform)
    let bottom = CGPoint(x: point.x + descent.x, y: point.y + descent.y).applying(session.transform)
    let line = TurnedRect(around: [top, bottom], angle: session.angle)
    let rect = line.rect
    return TurnedRect(
      rect: session.isVertical
        ? CGRect(x: rect.minX, y: rect.midY - 1, width: rect.width, height: 2)
        : CGRect(x: rect.midX - 1, y: rect.minY, width: 2, height: rect.height),
      transform: line.transform)
  }

  public func caretRect(for position: UITextPosition) -> CGRect {
    guard let session = textEditing, let position = position as? TextEditingPosition else { return .null }
    return caret(at: position.offset, in: session).rect
  }

  /// The transform of the caret, which is always the identity: the caret of a turned text is an upright rectangle at
  /// its center, as ``caretRect(for:)`` gives it, and the view that draws the caret turns its bar by the angle of the
  /// text. UIKit draws the caret that a person drags, with the loupe, with a copy of that view that doesn't get the
  /// transform of the caret, so the view turns the bar instead, as it does for both.
  public func caretTransform(for position: UITextPosition) -> CGAffineTransform {
    .identity
  }

  public func selectionRects(for range: UITextRange) -> [UITextSelectionRect] {
    guard let session = textEditing, let range = range as? TextEditingRange,
      let characters = session.layout?.characters
    else { return [] }
    let text = session.text
    let angle = session.angle
    var rects = [TurnedRect]()
    var rendered = 0
    var line: [CGPoint]?
    for (offset, character) in text.enumerated() {
      if character == "\n" {
        if let current = line { rects.append(TurnedRect(around: current, angle: angle)) }
        line = nil
        continue
      }
      defer { rendered += 1 }
      guard range.range.contains(offset), characters.indices.contains(rendered),
        let geometry = characters[rendered]
      else { continue }
      line = (line ?? []) + geometry.corners.map { $0.applying(session.transform) }
    }
    if let current = line { rects.append(TurnedRect(around: current, angle: angle)) }
    return rects.enumerated().map { index, rect in
      TextEditingSelectionRect(
        rect: rect.rect, containsStart: index == 0, containsEnd: index == rects.count - 1,
        isVertical: session.isVertical, transform: rect.transform)
    }
  }

  public func closestPosition(to point: CGPoint) -> UITextPosition? {
    guard let session = textEditing else { return nil }
    return closestPosition(to: point, in: 0..<(session.text.count + 1))
  }

  public func closestPosition(to point: CGPoint, within range: UITextRange) -> UITextPosition? {
    guard let range = range as? TextEditingRange else { return nil }
    return closestPosition(to: point, in: range.range.lowerBound..<(range.range.upperBound + 1))
  }

  /// The offset whose caret is the closest to a point, among the offsets.
  private func closestPosition(to point: CGPoint, in offsets: Range<Int>) -> UITextPosition? {
    guard let session = textEditing else { return nil }
    var closest: (offset: Int, distance: CGFloat)?
    for offset in offsets {
      let distance = caret(at: offset, in: session).squaredDistance(to: point)
      if closest.map({ distance < $0.distance }) ?? true {
        closest = (offset, distance)
      }
    }
    return closest.map { TextEditingPosition($0.offset) }
  }

  public func characterRange(at point: CGPoint) -> UITextRange? {
    guard let session = textEditing, let position = closestPosition(to: point) as? TextEditingPosition else {
      return nil
    }
    let start = min(position.offset, max(session.text.count - 1, 0))
    return TextEditingRange(start..<min(start + 1, session.text.count))
  }

  // MARK: - Attributes of runs

  /// The text that a person types into, with the attributes of its runs, or `nil` if the view doesn't edit text.
  public var editedStyledText: SVGStyledText? {
    textEditing?.styledText
  }

  /// Sets an attribute of the characters of a range of the text that is edited, or removes it if the value is `nil`,
  /// such as `font-weight` to `bold` or `fill` to `red`. The characters are written as a `tspan` element of a run
  /// with the attribute.
  ///
  /// Without characters in the range, the attribute is set for the characters that are typed next at the caret,
  /// until the selection moves. The attributes that place characters, such as `x` and `dy`, aren't set.
  ///
  /// ```swift
  /// svgView.setTextAttribute("font-weight", to: "bold")
  /// ```
  ///
  /// - Parameters:
  ///   - name: The name of the attribute, which is a presentation attribute of `tspan` elements, such as `fill`.
  ///   - value: The value of the attribute, or `nil` to remove it.
  ///   - range: The characters, or `nil` for the selection.
  public func setTextAttribute(_ name: String, to value: String?, in range: UITextRange? = nil) {
    guard let session = textEditing, !StyledTextContent.positionAttributes.contains(name), session.marked == nil
    else { return }
    let range =
      ((range as? TextEditingRange)?.range ?? session.selection).clamped(to: 0..<session.text.count)
    guard !range.isEmpty else {
      var typing = session.inheritedAttributes(at: range)
      typing[name] = value
      session.typingAttributes = typing
      return
    }
    let old = session.styledText
    for index in range where session.text[index] != "\n" {
      session.attributes[index][name] = value
    }
    guard session.styledText != old else { return }
    session.inputDelegate?.selectionWillChange(self)
    StyledTextContent.write(session.styledText, into: session.element)
    session.invalidateLayout()
    updateMarkLayer(of: session)
    session.inputDelegate?.selectionDidChange(self)
    session.display?.setNeedsSelectionUpdate()
    textEditingDelegate?.svgView(self, didChangeTextOf: session.element, fromStyledText: old)
  }

  /// The attributes that every character of a range of the text that is edited has with the same value, or the
  /// attributes of the characters that are typed next at the caret without characters in the range, which an app
  /// shows in its controls, such as whether bold is on.
  ///
  /// - Parameter range: The characters, or `nil` for the selection.
  public func textAttributes(in range: UITextRange? = nil) -> [String: String] {
    guard let session = textEditing else { return [:] }
    let range =
      ((range as? TextEditingRange)?.range ?? session.selection).clamped(to: 0..<session.text.count)
    let characters = range.filter { session.text[$0] != "\n" }
    guard let first = characters.first else { return session.inheritedAttributes(at: range) }
    return session.attributes[first].filter { name, value in
      characters.allSatisfy { session.attributes[$0][name] == value }
    }
  }

  /// Reads the text that the view edits again, after an app wrote its content, or ends the editing if the content
  /// isn't text that the view edits.
  func textDidChange(of element: SVGDocument.Element) {
    guard let session = textEditing, session.element == element else { return }
    session.inputDelegate?.textWillChange(self)
    session.inputDelegate?.selectionWillChange(self)
    let reloaded = session.reload()
    updateMarkLayer(of: session)
    session.inputDelegate?.selectionDidChange(self)
    session.inputDelegate?.textDidChange(self)
    session.display?.setNeedsSelectionUpdate()
    if !reloaded {
      endTextEditing()
    }
  }

  /// Sets an attribute of the selection to a value, or removes it if every character of the selection has it, as
  /// the edit menu and the keyboard toggle bold, italic and underline.
  ///
  /// The characters are on where their runs or the text that they inherit from have a value that is on, such as a
  /// `font-weight` of 700 for bold, as the text looks. Where the text is on, the characters are turned off with the
  /// value that is off, such as `normal`, and on by removing the attribute of their runs, and elsewhere the other way
  /// around.
  private func toggleTextAttribute(_ name: String, on: String, off: String, isOn valueIsOn: (String) -> Bool) {
    guard let session = textEditing else { return }
    let inherited = session.element.computedStyle.property(name).map(valueIsOn) ?? false
    func isOn(_ attributes: [String: String]) -> Bool {
      attributes[name].map(valueIsOn) ?? inherited
    }
    let range = session.selection
    let characters = range.filter { session.text[$0] != "\n" }
    let allOn =
      characters.isEmpty
      ? isOn(session.inheritedAttributes(at: range)) : characters.allSatisfy { isOn(session.attributes[$0]) }
    // The characters take the value that they inherit where it's the one that they get.
    setTextAttribute(name, to: allOn ? (inherited ? off : nil) : (inherited ? nil : on))
  }

  override public func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
    if action == #selector(toggleBoldface(_:)) || action == #selector(toggleItalics(_:))
      || action == #selector(toggleUnderline(_:))
    {
      return textEditing != nil && allowsEditingTextAttributes
    }
    return super.canPerformAction(action, withSender: sender)
  }

  override public func toggleBoldface(_: Any?) {
    guard allowsEditingTextAttributes else { return }
    toggleTextAttribute("font-weight", on: "bold", off: "normal") {
      $0 == "bold" || $0 == "bolder" || (Double($0) ?? 0) >= 600
    }
  }

  override public func toggleItalics(_: Any?) {
    guard allowsEditingTextAttributes else { return }
    toggleTextAttribute("font-style", on: "italic", off: "normal") {
      $0.hasPrefix("italic") || $0.hasPrefix("oblique")
    }
  }

  override public func toggleUnderline(_: Any?) {
    guard allowsEditingTextAttributes else { return }
    toggleTextAttribute("text-decoration", on: "underline", off: "none") {
      $0.split(separator: " ").contains("underline")
    }
  }

  // MARK: - Editing actions

  override public func copy(_: Any?) {
    guard let session = textEditing, !session.selection.isEmpty else { return }
    UIPasteboard.general.string = String(session.text[session.selection])
  }

  override public func cut(_ sender: Any?) {
    guard let session = textEditing, !session.selection.isEmpty else { return }
    copy(sender)
    let start = session.selection.lowerBound
    replace(session.selection, with: [], selection: start..<start, marked: nil, notifies: true)
  }

  override public func paste(_: Any?) {
    guard let session = textEditing, let string = UIPasteboard.general.string else { return }
    let characters = Array(string)
    let caret = session.selection.lowerBound + characters.count
    replace(session.selection, with: characters, selection: caret..<caret, marked: nil, notifies: true)
  }

  override public func selectAll(_: Any?) {
    guard let session = textEditing else { return }
    session.inputDelegate?.selectionWillChange(self)
    session.selection = 0..<session.text.count
    session.inputDelegate?.selectionDidChange(self)
    session.display?.setNeedsSelectionUpdate()
  }
}
