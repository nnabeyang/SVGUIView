import CoreGraphics
import Foundation
import Testing
import UIKit

@testable import SVGUIView

/// Tests that a person types into a `text` element of the document that a view shows, as into a text field.
@MainActor
@Suite("Text editing", .serialized, .timeLimit(.minutes(2)))
struct TextEditingTests {
  private let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 300))

  private func view(_ content: String) -> SVGUIView {
    let view = SVGUIView(
      frame: CGRect(x: 0, y: 0, width: 400, height: 300),
      data: Data(
        (##"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 400 300" font-family="Helvetica" font-size="40">"##
          + content + "</svg>").utf8))
    view.configuration = SVGUIViewConfiguration(timeoutDuration: patience, animation: .none)
    window.addSubview(view)
    return view
  }

  private func element(_ id: String, in view: SVGUIView) throws -> SVGDocument.Element {
    try #require(view.document.element(id: id))
  }

  private func written(_ view: SVGUIView) -> String {
    String(decoding: view.document.svgData(), as: UTF8.self)
  }

  /// Records what the delegate hears.
  private final class Recorder: SVGUIViewTextEditingDelegate {
    var events = [String]()
    var endsAtTaps = true

    func svgViewDidBeginTextEditing(_: SVGUIView, element: SVGDocument.Element) {
      events.append("begin \(element.attribute("id") ?? "")")
    }

    func svgView(_: SVGUIView, didChangeTextOf _: SVGDocument.Element, from oldText: String) {
      events.append("change from \(oldText)")
    }

    func svgViewDidEndTextEditing(_: SVGUIView, element: SVGDocument.Element) {
      events.append("end \(element.attribute("id") ?? "")")
    }

    func svgView(_: SVGUIView, shouldEndTextEditingAt _: CGPoint) -> Bool {
      endsAtTaps
    }
  }

  @Test("editing begins on a text element of character data and runs or of lines of them, and on nothing else")
  func begin() async throws {
    let view = view(
      ##"<text id="a" x="10" y="50">ab</text><text id="l" x="10" y="100"><tspan x="10">c</tspan><tspan x="10" dy="1.2em">d</tspan></text>"##
        + ##"<text id="s" x="10" y="200">e<tspan font-weight="bold">f</tspan></text>"##
        + ##"<text id="p" x="10" y="250">e<tspan dx="5">f</tspan></text><rect id="r" width="1" height="1"/>"##)
    #expect(await view.beginTextEditing(of: try element("a", in: view)))
    #expect(view.editedText == "ab")
    #expect(try element("a", in: view).attribute("xml:space") == "preserve")
    #expect((view.selectedTextRange as? TextEditingRange)?.range == 2..<2)
    #expect(await view.beginTextEditing(of: try element("l", in: view)))
    #expect(view.editedText == "c\nd")
    #expect(await view.beginTextEditing(of: try element("s", in: view)))
    #expect(view.editedText == "ef")
    #expect(await view.beginTextEditing(of: try element("p", in: view)) == false)
    #expect(await view.beginTextEditing(of: try element("r", in: view)) == false)
    let detached = SVGUIView(data: Data(##"<svg xmlns="http://www.w3.org/2000/svg"><text id="t">a</text></svg>"##.utf8))
    #expect(await detached.beginTextEditing(of: try element("t", in: detached)) == false)
  }

  @Test("typing changes the text, a line feed makes lines of tspan elements, and deleting it makes one line again")
  func typing() async throws {
    let view = view(##"<text id="t" x="10" y="50">ab</text>"##)
    let text = try element("t", in: view)
    #expect(await view.beginTextEditing(of: text))
    view.insertText("c")
    #expect(text.textContent == "abc")
    view.deleteBackward()
    #expect(text.textContent == "ab")
    view.insertText("\n")
    view.insertText("d")
    #expect(view.editedText == "ab\nd")
    #expect(text.children.map(\.localName) == ["tspan", "tspan"])
    #expect(text.children.map { $0.attribute("x") } == ["10", "10"])
    #expect(text.children.map { $0.attribute("dy") } == ["0", "1.2em"])
    #expect(written(view).contains(##"<tspan dy="1.2em" x="10">d</tspan>"##))
    view.deleteBackward()
    view.deleteBackward()
    #expect(text.children.isEmpty)
    #expect(text.textContent == "ab")
    // A selection is replaced by what is typed.
    view.selectedTextRange = view.textRange(from: view.beginningOfDocument, to: view.endOfDocument)
    view.insertText("x")
    #expect(view.editedText == "x")
  }

  @Test("marked text is in the text until it's committed, which changes the text once")
  func markedText() async throws {
    let view = view(##"<text id="t" x="10" y="50">a</text>"##)
    let recorder = Recorder()
    view.textEditingDelegate = recorder
    let text = try element("t", in: view)
    #expect(await view.beginTextEditing(of: text))
    view.setMarkedText("か", selectedRange: NSRange(location: 1, length: 0))
    #expect(text.textContent == "aか")
    #expect(view.markedTextRange != nil)
    view.setMarkedText("漢字", selectedRange: NSRange(location: 2, length: 0))
    #expect(text.textContent == "a漢字")
    view.unmarkText()
    #expect(view.markedTextRange == nil)
    #expect(text.textContent == "a漢字")
    #expect(recorder.events == ["begin t", "change from a"])
    let caret = try #require(view.selectedTextRange as? TextEditingRange)
    #expect(caret.range == 3..<3)
  }

  @Test("the caret and the closest position are where the characters are, also on an empty line")
  func geometry() async throws {
    let view = view(##"<text id="t" x="10" y="50">ab</text>"##)
    let text = try element("t", in: view)
    #expect(await view.beginTextEditing(of: text))
    let layout = try #require(await text.textLayout())
    let b = layout.characters[1]
    let caret = view.caretRect(for: TextEditingPosition(1))
    #expect(abs(caret.midX - b.start.x) < 0.01)
    #expect(abs(caret.minY - b.extent.minY) < 0.01 && abs(caret.maxY - b.extent.maxY) < 0.01)
    let point = CGPoint(x: (b.start.x + b.end.x) / 2 + 1, y: 40)
    #expect((view.closestPosition(to: point) as? TextEditingPosition)?.offset == layout.insertionIndex(closestTo: point))
    // An empty line has a caret a line under the line before it.
    view.insertText("\n")
    let empty = view.caretRect(for: TextEditingPosition(3))
    let first = view.caretRect(for: TextEditingPosition(0))
    #expect(abs(empty.minX - first.minX) < 0.01)
    #expect(abs(empty.minY - first.minY - 48) < 0.01)
    let rects = view.selectionRects(for: TextEditingRange(0..<2))
    #expect(rects.count == 1)
    #expect(abs(rects[0].rect.minX - layout.characters[0].extent.minX) < 0.01)
  }

  @Test("the caret and the selection of a turned text turn with it, and a point finds the caret it's on")
  func turnedText() async throws {
    let view = view(##"<text id="t" x="100" y="150" transform="rotate(30 100 150)">abc</text>"##)
    let text = try element("t", in: view)
    #expect(await view.beginTextEditing(of: text))
    let angle = CGFloat.pi / 6
    // The caret is an upright rectangle where the turned caret is, without a transform, so that the loupe, which reads
    // the rectangle alone, is at the caret, and the view that draws it turns its bar.
    #expect(view.caretTransform(for: TextEditingPosition(1)) == .identity)
    let display = try #require(view.interactions.lazy.compactMap { $0 as? UITextSelectionDisplayInteraction }.first)
    let cursor = try #require(display.cursorView as? TextCursorView)
    view.addSubview(cursor)
    cursor.layoutIfNeeded()
    let bar = CATransform3DGetAffineTransform(cursor.layer.sublayerTransform)
    #expect(abs(atan2(bar.b, bar.a) - angle) < 0.001)
    // The caret stands across the line, as tall as the line, where the character starts.
    let layout = try #require(await text.textLayout())
    let b = layout.characters[1]
    let rect = view.caretRect(for: TextEditingPosition(1))
    let center = CGPoint(x: rect.midX, y: rect.midY)
    #expect(abs(rect.width - 2) < 0.01)
    let start = b.start.applying(CGAffineTransform(translationX: 100, y: 150).rotated(by: angle).translatedBy(x: -100, y: -150))
    let line = CGPoint(x: b.ascent.x - b.descent.x, y: b.ascent.y - b.descent.y)
    #expect(abs(rect.height - (line.x * line.x + line.y * line.y).squareRoot()) < 0.01)
    let across = CGPoint(x: center.x - start.x, y: center.y - start.y)
    // The center of the caret is on the line through the start of the character across the baseline.
    #expect(abs(across.x * cos(angle) + across.y * sin(angle)) < 0.01)
    let rects = view.selectionRects(for: TextEditingRange(0..<3))
    #expect(rects.count == 1)
    #expect(abs(atan2(rects[0].transform.b, rects[0].transform.a) - angle) < 0.001)
    // The selection is as long as the line, not as the box around the turned line.
    let first = layout.characters[0]
    let last = layout.characters[2]
    #expect(abs(rects[0].rect.width - (last.end.x - first.start.x)) < 0.5)
    // The selection is on the characters, also without its transform.
    let selection = rects[0].rect.applying(rects[0].transform)
    let middle = b.start.applying(CGAffineTransform(translationX: 100, y: 150).rotated(by: angle).translatedBy(x: -100, y: -150))
    #expect(selection.contains(middle))
    #expect(selection.contains(CGPoint(x: rects[0].rect.midX, y: rects[0].rect.midY)))
    #expect(view.firstRect(for: TextEditingRange(0..<3)).contains(middle))
    #expect((view.closestPosition(to: center) as? TextEditingPosition)?.offset == 1)
  }

  @Test("the caret and the selection of a text that isn't turned have no transform")
  func uprightText() async throws {
    let view = view(##"<text id="t" x="100" y="150">abc</text>"##)
    #expect(await view.beginTextEditing(of: try element("t", in: view)))
    let display = try #require(view.interactions.lazy.compactMap { $0 as? UITextSelectionDisplayInteraction }.first)
    let cursor = try #require(display.cursorView as? TextCursorView)
    view.addSubview(cursor)
    cursor.layoutIfNeeded()
    #expect(CATransform3DIsIdentity(cursor.layer.sublayerTransform))
    #expect(view.caretTransform(for: TextEditingPosition(1)) == .identity)
    #expect(view.selectionRects(for: TextEditingRange(0..<3)).map(\.transform) == [.identity])
    view.endTextEditing()
    // The display interaction draws its caret with the view that it had before the editing.
    #expect(!(display.cursorView is TextCursorView))
  }

  @Test("a transform found for an older size doesn't replace the one of a later finding, whichever ends last")
  func latestTransform() async throws {
    let view = view(##"<text id="t" x="10" y="50">ab</text>"##)
    let session = try #require(await view.beginTextEditing(of: try element("t", in: view)) ? view.textEditing : nil)
    let old = session.beginTransformRequest()
    let new = session.beginTransformRequest()
    let half = CGAffineTransform(scaleX: 0.5, y: 0.5)
    #expect(session.takeTransform(half, of: new))
    #expect(!session.takeTransform(.identity, of: old))
    #expect(session.transform == half)
  }

  @Test("the caret moves with the document when the view changes its size, as the keyboard makes it smaller")
  func resizing() async throws {
    let view = view(##"<text id="t" x="10" y="50">ab</text>"##)
    view.contentMode = .scaleAspectFit
    #expect(await view.beginTextEditing(of: try element("t", in: view)))
    let before = view.caretRect(for: TextEditingPosition(0))
    // A view of half the width shows the document at half its size.
    view.frame = CGRect(x: 0, y: 0, width: 200, height: 300)
    view.layoutIfNeeded()
    try await waitUntil("The caret stays at \(view.caretRect(for: TextEditingPosition(0)))") {
      abs(view.caretRect(for: TextEditingPosition(0)).height - before.height / 2) < 0.01
    }
  }

  @Test("a tap outside the text ends the editing, unless the delegate keeps it, and new data ends it")
  func ending() async throws {
    let view = view(##"<text id="t" x="10" y="50">ab</text>"##)
    let recorder = Recorder()
    view.textEditingDelegate = recorder
    let session = try #require(await view.beginTextEditing(of: try element("t", in: view)) ? view.textEditing : nil)
    recorder.endsAtTaps = false
    #expect(session.interactionShouldBegin(session.interaction, at: CGPoint(x: 300, y: 250)))
    #expect(view.editedTextElement != nil)
    #expect(session.interactionShouldBegin(session.interaction, at: CGPoint(x: 20, y: 40)))
    recorder.endsAtTaps = true
    #expect(!session.interactionShouldBegin(session.interaction, at: CGPoint(x: 300, y: 250)))
    #expect(view.editedTextElement == nil)
    #expect(recorder.events == ["begin t", "end t"])
    #expect(await view.beginTextEditing(of: try element("t", in: view)))
    view.data = Data(##"<svg xmlns="http://www.w3.org/2000/svg"/>"##.utf8)
    #expect(view.editedTextElement == nil)
  }

  @Test("a tap just outside a turned text ends the editing, also where it's inside the bounds of the turned text")
  func endingAwayFromTurnedText() async throws {
    let view = view(##"<text id="t" x="60" y="60" transform="rotate(45 60 60)">abcdefgh</text>"##)
    let text = try element("t", in: view)
    let session = try #require(await view.beginTextEditing(of: text) ? view.textEditing : nil)
    let line = try #require(view.selectionRects(for: TextEditingRange(0..<8)).first)
    let center = CGPoint(x: line.rect.midX, y: line.rect.midY)
    let angle = CGFloat.pi / 4
    // Along the line, and across it.
    func point(along: CGFloat, across: CGFloat) -> CGPoint {
      CGPoint(
        x: center.x + along * cos(angle) - across * sin(angle), y: center.y + along * sin(angle) + across * cos(angle))
    }
    let width = line.rect.width
    let height = line.rect.height
    // In the line, near its edges, the editing goes on.
    #expect(session.interactionShouldBegin(session.interaction, at: point(along: 0, across: height / 2 - 5)))
    #expect(session.interactionShouldBegin(session.interaction, at: point(along: width / 2 - 5, across: 0)))
    #expect(view.editedTextElement != nil)
    // Just across the line is in the bounds of the turned line, but outside the text, so the editing ends.
    let across = point(along: 0, across: height / 2 + 5)
    let bounds = CGMutablePath()
    bounds.addLines(between: TurnedRect(rect: line.rect, transform: line.transform).corners)
    #expect(bounds.boundingBoxOfPath.contains(across))
    #expect(!session.interactionShouldBegin(session.interaction, at: across))
    #expect(view.editedTextElement == nil)
    // Just past the end of the line ends it too.
    let again = try #require(await view.beginTextEditing(of: text) ? view.textEditing : nil)
    #expect(!again.interactionShouldBegin(again.interaction, at: point(along: width / 2 + 5, across: 0)))
    #expect(view.editedTextElement == nil)
  }

  @Test("a tap beside a short line of a text that isn't turned, within the longer line, goes on editing")
  func tapBesideShortLine() async throws {
    let view = view(##"<text id="t" x="10" y="50">abcdefgh</text>"##)
    let session = try #require(await view.beginTextEditing(of: try element("t", in: view)) ? view.textEditing : nil)
    view.selectedTextRange = TextEditingRange(8..<8)
    view.insertText("\n")
    view.insertText("a")
    let lines = view.selectionRects(for: TextEditingRange(0..<10))
    try #require(lines.count == 2)
    let beside = CGPoint(x: lines[0].rect.maxX - 5, y: lines[1].rect.midY)
    #expect(lines[1].rect.maxX < beside.x - 20)
    #expect(session.interactionShouldBegin(session.interaction, at: beside))
    #expect(view.editedTextElement != nil)
  }

  @Test("a tap on a handle of the selection, which sticks out of the line, doesn't end the editing")
  func handleTap() async throws {
    let view = view(##"<text id="t" x="60" y="60">abcdef</text>"##)
    let session = try #require(
      await view.beginTextEditing(of: try element("t", in: view), selecting: 0..<6) ? view.textEditing : nil)
    let start = view.caret(at: 0, in: session).rect
    // The knob of the start handle is above the line.
    let knob = CGPoint(x: start.midX, y: start.minY - 10)
    #expect(view.selectionHandle(at: knob) == .start)
    #expect(session.interactionShouldBegin(session.interaction, at: knob))
    #expect(view.editedTextElement != nil)
    // A tap away from the handles ends it.
    #expect(view.selectionHandle(at: CGPoint(x: start.midX, y: start.minY - 40)) == nil)
    #expect(!session.interactionShouldBegin(session.interaction, at: CGPoint(x: start.midX, y: start.minY - 40)))
    #expect(view.editedTextElement == nil)
  }

  @Test("a handle of a turned text is found where it's drawn, and dragging it moves its end along the text")
  func turnedHandles() async throws {
    let view = view(##"<text id="t" x="60" y="60" transform="rotate(45 60 60)">abcdefgh</text>"##)
    let session = try #require(
      await view.beginTextEditing(of: try element("t", in: view), selecting: 0..<8) ? view.textEditing : nil)
    func center(_ offset: Int) -> CGPoint {
      let caret = view.caret(at: offset, in: session).rect
      return CGPoint(x: caret.midX, y: caret.midY)
    }
    #expect(view.selectionHandle(at: center(0)) == .start)
    #expect(view.selectionHandle(at: center(8)) == .end)
    #expect(view.selectionHandle(at: center(4)) == nil)
    // The end moves from the start, which stays.
    #expect(view.moveSelection(from: 0, to: center(3)) == .end)
    #expect((view.selectedTextRange as? TextEditingRange)?.range == 0..<3)
    #expect(view.moveSelection(from: 3, to: center(2)) == .start)
    #expect((view.selectedTextRange as? TextEditingRange)?.range == 2..<3)
    // The dragged end passes the other one, and they swap, as on a text that isn't turned.
    #expect(view.moveSelection(from: 3, to: center(6)) == .end)
    #expect((view.selectedTextRange as? TextEditingRange)?.range == 3..<6)
    // Where they meet, the selection stays.
    #expect(view.moveSelection(from: 3, to: center(3)) == .end)
    #expect((view.selectedTextRange as? TextEditingRange)?.range == 3..<6)
  }

  @Test("the view drags the handles of a turned text, and the other gestures of the view don't begin on them")
  func handleGestures() async throws {
    let view = view(##"<text id="t" x="60" y="60" transform="rotate(45 60 60)">abcdefgh</text>"##)
    let session = try #require(
      await view.beginTextEditing(of: try element("t", in: view), selecting: 0..<8) ? view.textEditing : nil)
    let end = view.caret(at: 8, in: session).rect
    #expect(session.handleDragged(from: CGPoint(x: end.midX, y: end.midY)) == .end)
    let tap = UITapGestureRecognizer()
    view.addGestureRecognizer(tap)
    session.touchedHandle = .end
    #expect(!view.gestureRecognizerShouldBegin(tap))
    session.touchedHandle = nil
    #expect(view.gestureRecognizerShouldBegin(tap))
    // On a text that isn't turned, the text interaction drags the handles from the lines.
    let flat = self.view(##"<text id="f" x="60" y="60">abcdefgh</text>"##)
    let flatSession = try #require(
      await flat.beginTextEditing(of: try element("f", in: flat), selecting: 0..<8) ? flat.textEditing : nil)
    let start = flat.caret(at: 0, in: flatSession).rect
    #expect(flatSession.handleDragged(from: CGPoint(x: start.midX, y: start.midY)) == nil)
    #expect(flatSession.handleDragged(from: CGPoint(x: start.midX, y: start.minY - 10)) == .start)
  }

  @Test("the edit menu offers Cut and Copy with a selection, and Select with a caret, as a text view does")
  func editMenu() async throws {
    let view = view(##"<text id="t" x="10" y="50">ab cd</text>"##)
    #expect(await view.beginTextEditing(of: try element("t", in: view), selecting: 4..<4))
    let cut = #selector(UIResponderStandardEditActions.cut(_:))
    let copy = #selector(UIResponderStandardEditActions.copy(_:))
    let select = #selector(UIResponderStandardEditActions.select(_:))
    let selectAll = #selector(UIResponderStandardEditActions.selectAll(_:))
    #expect(!view.canPerformAction(cut, withSender: nil))
    #expect(!view.canPerformAction(copy, withSender: nil))
    #expect(view.canPerformAction(select, withSender: nil))
    #expect(view.canPerformAction(selectAll, withSender: nil))
    // Select selects the word at the caret.
    view.select(nil)
    #expect((view.selectedTextRange as? TextEditingRange)?.range == 3..<5)
    #expect(view.canPerformAction(cut, withSender: nil))
    #expect(view.canPerformAction(copy, withSender: nil))
    #expect(!view.canPerformAction(select, withSender: nil))
    view.selectAll(nil)
    #expect(!view.canPerformAction(selectAll, withSender: nil))
    // A caret after a word, before a space, selects that word.
    view.selectedTextRange = TextEditingRange(2..<2)
    view.select(nil)
    #expect((view.selectedTextRange as? TextEditingRange)?.range == 0..<2)
  }

  @Test("the typed text renders as the same text written in the document")
  func rendering() async throws {
    let typed = view(##"<text id="t" x="10" y="50"></text>"##)
    #expect(await typed.beginTextEditing(of: try element("t", in: typed)))
    for character in "Hi  there\nyou" {
      typed.insertText(String(character))
    }
    typed.endTextEditing()
    let written = view(
      ##"<text x="10" y="50" xml:space="preserve"><tspan x="10" dy="0">Hi  there</tspan><tspan x="10" dy="1.2em">you</tspan></text>"##
    )
    let expected = try #require(try await written.takeSnapshot(scale: 1).cgImage)
    let found = try #require(try await typed.takeSnapshot(scale: 1).cgImage)
    #expect(try pixels(of: found) == pixels(of: expected))
  }
}
