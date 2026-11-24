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

  @Test("editing begins on a text element of character data or of lines, and on nothing else")
  func begin() async throws {
    let view = view(
      ##"<text id="a" x="10" y="50">ab</text><text id="l" x="10" y="100"><tspan x="10">c</tspan><tspan x="10" dy="1.2em">d</tspan></text>"##
        + ##"<text id="s" x="10" y="200">e<tspan font-weight="bold">f</tspan></text><rect id="r" width="1" height="1"/>"##)
    #expect(await view.beginTextEditing(of: try element("a", in: view)))
    #expect(view.editedText == "ab")
    #expect(try element("a", in: view).attribute("xml:space") == "preserve")
    #expect((view.selectedTextRange as? TextEditingRange)?.range == 2..<2)
    #expect(await view.beginTextEditing(of: try element("l", in: view)))
    #expect(view.editedText == "c\nd")
    #expect(await view.beginTextEditing(of: try element("s", in: view)) == false)
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
