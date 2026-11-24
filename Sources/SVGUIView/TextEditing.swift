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
  /// The editing of the element ended, and the view hid the keyboard. An app can remove an element that has no text
  /// left.
  func svgViewDidEndTextEditing(_ view: SVGUIView, element: SVGDocument.Element)
  /// Whether a tap at a point of the view, outside the text that is edited, ends the editing.
  func svgView(_ view: SVGUIView, shouldEndTextEditingAt point: CGPoint) -> Bool
}

extension SVGUIViewTextEditingDelegate {
  public func svgViewDidBeginTextEditing(_: SVGUIView, element _: SVGDocument.Element) {}
  public func svgView(_: SVGUIView, didChangeTextOf _: SVGDocument.Element, from _: String) {}
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

/// A rectangle in a frame that a rotation turns into the coordinates of the view, as `UITextInput` tells the caret and
/// the selection of a turned text: the rotation is about the origin of the view, not about the rectangle.
struct TurnedRect {
  /// The rectangle in the turned frame.
  var rect: CGRect
  /// The rotation from the turned frame to the coordinates of the view.
  var transform: CGAffineTransform

  /// The upright rectangle around points of the view, in the frame that an angle turns, and the rotation.
  init(around points: [CGPoint], angle: CGFloat) {
    let rotation = angle == 0 ? CGAffineTransform.identity : CGAffineTransform(rotationAngle: angle)
    let path = CGMutablePath()
    path.addLines(between: angle == 0 ? points : points.map { $0.applying(rotation.inverted()) })
    rect = path.boundingBoxOfPath
    transform = rotation
  }

  init(rect: CGRect, transform: CGAffineTransform) {
    self.rect = rect
    self.transform = transform
  }

  /// The bounds of the rectangle in the coordinates of the view.
  var bounds: CGRect { rect.applying(transform) }

  /// The square of the distance from a point of the view to the rectangle.
  func squaredDistance(to point: CGPoint) -> CGFloat {
    let local = point.applying(transform.inverted())
    let dx = max(rect.minX - local.x, 0, local.x - rect.maxX)
    let dy = max(rect.minY - local.y, 0, local.y - rect.maxY)
    return dx * dx + dy * dy
  }
}

/// The `text` element that a person types into, its text, and the selection.
@MainActor
final class TextEditingSession: NSObject, UITextInteractionDelegate, UITextSelectionDisplayInteractionDelegate {
  let element: SVGDocument.Element
  weak var view: SVGUIView?
  /// The characters of the text, with a line feed between the lines.
  var text: [Character]
  var selection: Range<Int>
  /// The characters that the keyboard marks while they're composed, or `nil`.
  var marked: Range<Int>?
  /// The text before the marked characters began, which the change that commits them changes from.
  var textBeforeMarking: String?
  var markedTextStyle: [NSAttributedString.Key: Any]?
  weak var inputDelegate: (any UITextInputDelegate)?
  /// The transform from the user space of the text to the coordinates of the view.
  var transform: CGAffineTransform = .identity
  /// Whether the lines are vertical, which `writing-mode` decides.
  let isVertical: Bool
  /// The interaction that shows the caret, the selection, the loupe and the edit menu.
  let interaction = UITextInteraction(for: .editable)
  /// The interaction that draws the caret and the selection, which the text interaction has, or one of the session.
  var display: UITextSelectionDisplayInteraction?
  /// Whether the session added the display interaction, which it removes at the end.
  var addsDisplay = false
  /// The line under the marked characters.
  let markLayer = CAShapeLayer()
  /// Where the characters are, which the changes of the text find again.
  private var cachedLayout: (text: [Character], characters: [CharacterGeometry?])??

  init(element: SVGDocument.Element, view: SVGUIView, text: [Character], isVertical: Bool) {
    self.element = element
    self.view = view
    self.text = text
    self.isVertical = isVertical
    selection = text.count..<text.count
    super.init()
    markLayer.fillColor = nil
    markLayer.strokeColor = UIColor.tintColor.cgColor
    markLayer.lineWidth = 2
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
    // A tap outside the text ends the editing, unless the delegate keeps it.
    let bounds = view.editedTextBounds(of: self).insetBy(dx: -20, dy: -20)
    guard !bounds.contains(point) else { return true }
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
  /// The element is a `text` element of the document that the view shows, in a window, with character data and no
  /// children, or with `tspan` elements that are lines: each with an `x` attribute, or a `y` attribute in vertical
  /// text, and with character data only. The editing sets `xml:space="preserve"`, so that spaces are kept, and writes
  /// a text of more than one line as lines of that form, the next one `1.2em` after the one before it.
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
    let writingMode = element.computedStyle.property("writing-mode") ?? "horizontal-tb"
    let isVertical = writingMode.hasPrefix("vertical") || writingMode.hasPrefix("sideways")
    let lineAttribute = isVertical ? "y" : "x"
    let children = element.children
    guard
      children.allSatisfy({
        $0.localName == "tspan" && $0.attribute(lineAttribute) != nil && $0.children.isEmpty
      })
    else { return false }
    endTextEditing()
    let lines = children.isEmpty ? [element.textContent] : children.map(\.textContent)
    let session = TextEditingSession(
      element: element, view: self, text: Array(lines.joined(separator: "\n")), isVertical: isVertical)
    element.setAttribute("xml:space", to: "preserve")
    // Character data between the lines would be rendered with the spaces kept, so the lines are written again.
    if !children.isEmpty, element.textContent != lines.joined() {
      writeLines(lines, of: session)
    }
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
    if session.addsDisplay, let display = session.display {
      removeInteraction(display)
    }
    removeInteraction(session.interaction)
    session.markLayer.removeFromSuperlayer()
    resignFirstResponder()
    textEditingDelegate?.svgViewDidEndTextEditing(self, element: session.element)
  }

  /// The bounds of the text that is edited, in the coordinates of the view.
  func editedTextBounds(of session: TextEditingSession) -> CGRect {
    var bounds = caret(at: session.selection.lowerBound, in: session).bounds
    for rect in selectionRects(for: TextEditingRange(0..<session.text.count)) {
      bounds = bounds.union(TurnedRect(rect: rect.rect, transform: rect.transform).bounds)
    }
    return bounds
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
    let old = String(session.text)
    if session.marked == nil, marked != nil {
      session.textBeforeMarking = old
    }
    session.text.replaceSubrange(range, with: characters)
    session.selection = selection.clamped(to: 0..<session.text.count)
    session.marked = marked?.clamped(to: 0..<session.text.count)
    let lines = String(session.text).split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    writeLines(lines, of: session)
    session.invalidateLayout()
    updateMarkLayer(of: session)
    if movesSelection { session.inputDelegate?.selectionDidChange(self) }
    session.display?.setNeedsSelectionUpdate()
    if notifies { session.inputDelegate?.textDidChange(self) }
    // The marked characters change the text once, when they're committed.
    if session.marked == nil, String(session.text) != (session.textBeforeMarking ?? old) {
      textEditingDelegate?.svgView(
        self, didChangeTextOf: session.element, from: session.textBeforeMarking ?? old)
    }
    if session.marked == nil {
      session.textBeforeMarking = nil
    }
  }

  /// Writes the lines into the element: one line as its character data, and more as `tspan` elements.
  private func writeLines(_ lines: [String], of session: TextEditingSession) {
    let element = session.element
    guard lines.count > 1 else {
      if !element.children.isEmpty || element.textContent != lines.first ?? "" {
        element.textContent = lines.first ?? ""
      }
      return
    }
    let lineAttribute = session.isVertical ? "y" : "x"
    let children = element.children
    if children.count == lines.count {
      for (child, line) in zip(children, lines) where child.textContent != line {
        child.textContent = line
      }
      return
    }
    // The lines start where the text does, and each one is 1.2em after the one before it.
    let start =
      element.attribute(lineAttribute)?.split(whereSeparator: { $0 == " " || $0 == "," }).first
      .map(String.init) ?? "0"
    let isRightToLeft = (element.computedStyle.property("writing-mode") ?? "") == "vertical-rl"
    let advance =
      session.isVertical ? (isRightToLeft ? ("dx", "-1.2em") : ("dx", "1.2em")) : ("dy", "1.2em")
    element.textContent = ""
    for (index, line) in lines.enumerated() {
      let tspan = document.createElement("tspan")
      tspan.setAttribute(lineAttribute, to: start)
      tspan.setAttribute(advance.0, to: index == 0 ? "0" : advance.1)
      tspan.textContent = line
      try? element.append(tspan)
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

  /// The angle that the text that is edited is turned by in the view, which turns its caret and its selection. The
  /// baseline of a horizontal line, or the x-axis of the text, goes along it.
  private func angle(of session: TextEditingSession) -> CGFloat {
    let transform = session.transform
    return transform.b == 0 && transform.a >= 0 ? 0 : atan2(transform.b, transform.a)
  }

  /// The caret at an offset of the text: a thin bar across the line, which the angle of the text turns.
  private func caret(at offset: Int, in session: TextEditingSession) -> TurnedRect {
    let (point, ascent, descent) = caretGeometry(at: offset, in: session)
    let top = CGPoint(x: point.x + ascent.x, y: point.y + ascent.y).applying(session.transform)
    let bottom = CGPoint(x: point.x + descent.x, y: point.y + descent.y).applying(session.transform)
    let line = TurnedRect(around: [top, bottom], angle: angle(of: session))
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

  public func caretTransform(for position: UITextPosition) -> CGAffineTransform {
    guard let session = textEditing, let position = position as? TextEditingPosition else { return .identity }
    return caret(at: position.offset, in: session).transform
  }

  public func selectionRects(for range: UITextRange) -> [UITextSelectionRect] {
    guard let session = textEditing, let range = range as? TextEditingRange,
      let characters = session.layout?.characters
    else { return [] }
    let text = session.text
    let angle = angle(of: session)
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
