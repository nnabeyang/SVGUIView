import CoreGraphics
import Foundation
import Testing
import UIKit

@testable import SVGUIView

/// Tests that the text that a person types into has runs with attributes, such as a range in bold, which are written
/// as `tspan` elements, typed on, read and undone.
@MainActor
@Suite("Text formatting", .serialized, .timeLimit(.minutes(2)))
struct TextFormattingTests {
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

  /// A view that edits the text `t` of the content.
  private func editing(_ content: String) async throws -> SVGUIView {
    let view = view(content)
    let text = try #require(view.document.element(id: "t"))
    #expect(await view.beginTextEditing(of: text))
    return view
  }

  private func written(_ view: SVGUIView) -> String {
    String(decoding: view.document.svgData(), as: UTF8.self)
  }

  private func select(_ range: Range<Int>, in view: SVGUIView) {
    view.selectedTextRange = TextEditingRange(range)
  }

  /// Records the styled text that each change changes from, and the text that the method of the characters hears.
  private final class Recorder: SVGUIViewTextEditingDelegate {
    var styled = [SVGStyledText]()

    func svgView(_: SVGUIView, didChangeTextOf _: SVGDocument.Element, fromStyledText oldText: SVGStyledText) {
      styled.append(oldText)
    }
  }

  /// Records the text that each change changes from, as an app that adopts only the method of the characters does.
  private final class CharacterRecorder: SVGUIViewTextEditingDelegate {
    var texts = [String]()

    func svgView(_: SVGUIView, didChangeTextOf _: SVGDocument.Element, from oldText: String) {
      texts.append(oldText)
    }
  }

  @Test("an attribute of a range is a tspan of the run, and text without attributes is written as before")
  func range() async throws {
    let view = try await editing(##"<text id="t" x="10" y="50">abc</text>"##)
    #expect(!written(view).contains("<tspan"))
    view.setTextAttribute("font-weight", to: "bold", in: TextEditingRange(1..<2))
    #expect(written(view).contains(##">a<tspan font-weight="bold">b</tspan>c</text>"##))
    #expect(
      view.editedStyledText
        == SVGStyledText(runs: [.init("a"), .init("b", attributes: ["font-weight": "bold"]), .init("c")]))
    // Removing the attribute makes the text one run again.
    view.setTextAttribute("font-weight", to: nil, in: TextEditingRange(0..<3))
    #expect(written(view).contains(##">abc</text>"##))
    // The attributes that place characters aren't set.
    view.setTextAttribute("dx", to: "5", in: TextEditingRange(0..<3))
    #expect(!written(view).contains("dx"))
  }

  @Test("typed characters take the attributes of the character before them, or after them at the start of a line")
  func typing() async throws {
    let view = try await editing(##"<text id="t" x="10" y="50">abc</text>"##)
    view.setTextAttribute("font-weight", to: "bold", in: TextEditingRange(1..<2))
    select(2..<2, in: view)
    view.insertText("x")
    #expect(written(view).contains(##">a<tspan font-weight="bold">bx</tspan>c</text>"##))
    view.setTextAttribute("fill", to: "red", in: TextEditingRange(0..<1))
    select(0..<0, in: view)
    view.insertText("z")
    #expect(written(view).contains(##"><tspan fill="red">za</tspan><tspan font-weight="bold">bx</tspan>c</text>"##))
    // A replaced selection gives the attributes of its first character.
    select(2..<4, in: view)
    view.insertText("y")
    #expect(written(view).contains(##"<tspan font-weight="bold">y</tspan>c</text>"##))
  }

  @Test("an attribute without a selection is for the characters typed next, until the selection moves")
  func typingAttributes() async throws {
    let view = try await editing(##"<text id="t" x="10" y="50">abc</text>"##)
    view.setTextAttribute("fill", to: "red")
    #expect(view.textAttributes() == ["fill": "red"])
    #expect(!written(view).contains("<tspan"))
    view.insertText("d")
    view.insertText("e")
    #expect(written(view).contains(##">abc<tspan fill="red">de</tspan></text>"##))
    view.setTextAttribute("font-weight", to: "bold")
    select(0..<0, in: view)
    select(5..<5, in: view)
    view.insertText("f")
    #expect(written(view).contains(##"<tspan fill="red">def</tspan></text>"##))
  }

  @Test("runs go across lines, and keep their attributes as lines are added and joined")
  func lines() async throws {
    let view = try await editing(##"<text id="t" x="10" y="50">ab</text>"##)
    view.insertText("\n")
    view.insertText("cd")
    view.setTextAttribute("font-weight", to: "bold", in: TextEditingRange(1..<4))
    let text = written(view)
    #expect(text.contains(##"<tspan dy="0" x="10">a<tspan font-weight="bold">b</tspan></tspan>"##), "\(text)")
    #expect(text.contains(##"<tspan dy="1.2em" x="10"><tspan font-weight="bold">c</tspan>d</tspan>"##), "\(text)")
    select(3..<3, in: view)
    view.deleteBackward()
    #expect(written(view).contains(##">a<tspan font-weight="bold">bc</tspan>d</text>"##))
  }

  @Test("text with runs is read and edited, and written as it was read")
  func reading() async throws {
    let content =
      ##"<text id="t" x="10" y="50"><tspan x="10" dy="0">a<tspan fill="red">b</tspan></tspan><tspan x="10" dy="1.2em"><tspan font-style="italic">c</tspan></tspan></text>"##
    let view = view(content)
    let text = try #require(view.document.element(id: "t"))
    let expected = SVGStyledText(runs: [
      .init("a"), .init("b", attributes: ["fill": "red"]), .init("\n"), .init("c", attributes: ["font-style": "italic"]),
    ])
    #expect(text.styledText == expected)
    let before = written(view)
    #expect(await view.beginTextEditing(of: text))
    #expect(view.editedStyledText == expected)
    // The editing only keeps the spaces.
    #expect(written(view).replacingOccurrences(of: ##" xml:space="preserve""##, with: "") == before)
    #expect(text.styledText == expected)
    // A run in a run, and a run that places its characters, aren't read.
    let nested = self.view(##"<text id="n">a<tspan fill="red">b<tspan>c</tspan></tspan></text>"##)
    #expect(try #require(nested.document.element(id: "n")).styledText == nil)
  }

  @Test("the delegate hears the styled text before each change, which undoes it, and hears the characters by default")
  func undo() async throws {
    let view = try await editing(##"<text id="t" x="10" y="50">abc</text>"##)
    let text = try #require(view.document.element(id: "t"))
    let before = written(view)
    let recorder = Recorder()
    view.textEditingDelegate = recorder
    view.setTextAttribute("font-weight", to: "bold", in: TextEditingRange(0..<2))
    view.insertText("d")
    #expect(recorder.styled.count == 2)
    #expect(recorder.styled.first == SVGStyledText("abc"))
    // Undoing in the order of the changes, the latest first, writes the text that was there.
    text.setStyledText(recorder.styled[1])
    #expect(view.editedText == "abc")
    text.setStyledText(recorder.styled[0])
    #expect(written(view) == before)
    #expect(view.editedStyledText == SVGStyledText("abc"))
    // An app that adopts only the method of the characters hears the changes of the attributes too.
    let characters = CharacterRecorder()
    view.textEditingDelegate = characters
    view.setTextAttribute("fill", to: "red", in: TextEditingRange(0..<1))
    #expect(characters.texts == ["abc"])
  }

  @Test("the edit menu and the keyboard toggle bold, italic and underline only where the view allows it")
  func toggles() async throws {
    let view = try await editing(##"<text id="t" x="10" y="50">abc</text>"##)
    let bold = #selector(UIResponderStandardEditActions.toggleBoldface(_:))
    #expect(!view.canPerformAction(bold, withSender: nil))
    select(0..<2, in: view)
    view.toggleBoldface(nil)
    #expect(!written(view).contains("bold"))
    view.allowsEditingTextAttributes = true
    #expect(view.canPerformAction(bold, withSender: nil))
    view.toggleBoldface(nil)
    view.toggleItalics(nil)
    view.toggleUnderline(nil)
    #expect(
      view.textAttributes() == ["font-weight": "bold", "font-style": "italic", "text-decoration": "underline"])
    // A range that is bold in part becomes bold, and one that is bold becomes normal.
    select(1..<3, in: view)
    view.toggleBoldface(nil)
    #expect(view.textAttributes(in: TextEditingRange(0..<3))["font-weight"] == "bold")
    select(0..<3, in: view)
    view.toggleBoldface(nil)
    #expect(view.textAttributes(in: TextEditingRange(0..<3))["font-weight"] == nil)
  }

  @Test("toggling bold where the text is bold turns it off, as the text looks")
  func toggleInherited() async throws {
    let view = try await editing(##"<g font-weight="bold"><text id="t" x="10" y="50">abc</text></g>"##)
    view.allowsEditingTextAttributes = true
    select(0..<1, in: view)
    view.toggleBoldface(nil)
    #expect(written(view).contains(##"><tspan font-weight="normal">a</tspan>bc</text>"##))
    view.toggleBoldface(nil)
    #expect(written(view).contains(##">abc</text>"##))
  }

  @Test("the attributes of a range are the ones that every character of it has with the same value")
  func attributesOfRange() async throws {
    let view = try await editing(##"<text id="t" x="10" y="50">abc</text>"##)
    view.setTextAttribute("font-weight", to: "bold", in: TextEditingRange(0..<3))
    view.setTextAttribute("fill", to: "red", in: TextEditingRange(1..<2))
    #expect(view.textAttributes(in: TextEditingRange(0..<3)) == ["font-weight": "bold"])
    #expect(view.textAttributes(in: TextEditingRange(1..<2)) == ["font-weight": "bold", "fill": "red"])
    // The caret has the attributes of the character before it.
    select(2..<2, in: view)
    #expect(view.textAttributes() == ["font-weight": "bold", "fill": "red"])
  }

  @Test("typed text with attributes renders as the same text written in the document")
  func rendering() async throws {
    let typed = try await editing(##"<text id="t" x="10" y="50"></text>"##)
    for character in "Hi there\nyou" {
      typed.insertText(String(character))
    }
    typed.setTextAttribute("font-weight", to: "bold", in: TextEditingRange(3..<8))
    typed.setTextAttribute("fill", to: "blue", in: TextEditingRange(9..<12))
    typed.endTextEditing()
    let written = view(
      ##"<text x="10" y="50" xml:space="preserve"><tspan x="10" dy="0">Hi <tspan font-weight="bold">there</tspan></tspan>"##
        + ##"<tspan x="10" dy="1.2em"><tspan fill="blue">you</tspan></tspan></text>"##)
    let expected = try #require(try await written.takeSnapshot(scale: 1).cgImage)
    let found = try #require(try await typed.takeSnapshot(scale: 1).cgImage)
    #expect(try pixels(of: found) == pixels(of: expected))
  }
}
