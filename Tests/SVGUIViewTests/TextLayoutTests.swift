import CoreGraphics
import Foundation
import Testing
import UIKit

@testable import SVGUIView

/// Tests that an app reads where the characters of text are, as the SVG DOM's `getStartPositionOfChar()`,
/// `getEndPositionOfChar()`, `getExtentOfChar()`, `getRotationOfChar()` and `getCharNumAtPosition()` find them.
@MainActor
@Suite("Text layout", .timeLimit(.minutes(2)))
struct TextLayoutTests {
  private func view(_ content: String) -> SVGUIView {
    let view = SVGUIView(
      frame: CGRect(x: 0, y: 0, width: 400, height: 300),
      data: Data(
        (##"<svg xmlns="http://www.w3.org/2000/svg" width="400" height="300" font-family="Helvetica" font-size="40">"##
          + content + "</svg>").utf8))
    view.configuration = SVGUIViewConfiguration(timeoutDuration: patience, animation: .none)
    return view
  }

  private func layout(_ id: String, in view: SVGUIView) async throws -> SVGDocument.TextLayout {
    let element = try #require(view.document.element(id: id))
    return try #require(await element.textLayout())
  }

  private func isClose(_ a: CGPoint, _ b: CGPoint, tolerance: CGFloat = 1e-6) -> Bool {
    abs(a.x - b.x) <= tolerance && abs(a.y - b.y) <= tolerance
  }

  @Test("the characters of horizontal text go along the baseline, one after another, from their positions")
  func horizontal() async throws {
    let view = view(##"<text id="t" x="10" y="50">abc<tspan dx="5">d</tspan></text>"##)
    let layout = try await layout("t", in: view)
    #expect(layout.text == "abcd")
    #expect(layout.characters.count == 4)
    let characters = layout.characters
    #expect(isClose(characters[0].start, CGPoint(x: 10, y: 50)))
    for index in 0..<2 {
      #expect(isClose(characters[index].end, characters[index + 1].start, tolerance: 0.01))
    }
    // `dx` moves the character after the end of the one before it.
    #expect(abs(characters[3].start.x - characters[2].end.x - 5) < 0.01)
    for character in characters {
      #expect(character.start.y == 50 && character.end.y == 50)
      #expect(character.angle == 0)
      #expect(character.isRendered)
      // The cell is the advance by the ascent and the descent of the font.
      #expect(abs(character.extent.width - (character.end.x - character.start.x)) < 0.01)
      #expect(character.extent.minY < 50 && character.extent.maxY > 50)
    }
  }

  @Test("a point finds the character whose cell has it, and the position between characters closest to it")
  func points() async throws {
    let view = view(##"<text id="t" x="10" y="50">abc</text>"##)
    let layout = try await layout("t", in: view)
    let b = layout.characters[1]
    let middle = (b.start.x + b.end.x) / 2
    #expect(layout.characterIndex(at: CGPoint(x: middle, y: 45)) == 1)
    #expect(layout.characterIndex(at: CGPoint(x: 5, y: 45)) == nil)
    #expect(layout.characterIndex(at: CGPoint(x: middle, y: 200)) == nil)
    #expect(layout.insertionIndex(closestTo: CGPoint(x: middle - 1, y: 45)) == 1)
    #expect(layout.insertionIndex(closestTo: CGPoint(x: middle + 1, y: 45)) == 2)
    #expect(layout.insertionIndex(closestTo: CGPoint(x: 0, y: 45)) == 0)
    #expect(layout.insertionIndex(closestTo: CGPoint(x: 300, y: 100)) == 3)
    let caret = try #require(layout.caretPath(at: 1)).boundingBoxOfPath
    #expect(abs(caret.minX - b.start.x) < 0.01 && caret.width < 0.01)
    #expect(abs(caret.minY - b.extent.minY) < 0.01 && abs(caret.maxY - b.extent.maxY) < 0.01)
    let end = try #require(layout.caretPath(at: 3)).boundingBoxOfPath
    #expect(abs(end.minX - layout.characters[2].end.x) < 0.01)
  }

  @Test("a span has its own characters and the ones of the spans in it, where the text has them")
  func spans() async throws {
    let view = view(
      ##"<text id="t" x="10" y="50">a<tspan id="s">b<tspan>c</tspan></tspan><tspan id="n" style="display: none">x</tspan>d</text>"##
    )
    let text = try await layout("t", in: view)
    let span = try await layout("s", in: view)
    let hidden = try await layout("n", in: view)
    #expect(text.text == "abcd")
    #expect(span.text == "bc")
    #expect(span.characters == Array(text.characters[1...2]))
    #expect(hidden.text.isEmpty && hidden.characters.isEmpty)
  }

  @Test("an emoji and a letter with a combining mark are one character each, and collapsed spaces aren't characters")
  func characters() async throws {
    let view = view(##"<text id="t" x="10" y="50">  a   😀e&#x301;  </text>"##)
    let layout = try await layout("t", in: view)
    #expect(layout.text == "a 😀e\u{301}")
    #expect(layout.characters.count == 4)
  }

  @Test("right-to-left characters start at their right ends")
  func rightToLeft() async throws {
    let view = view(##"<text id="t" x="300" y="50" direction="rtl">אבג</text>"##)
    let layout = try await layout("t", in: view)
    #expect(isClose(layout.characters[0].start, CGPoint(x: 300, y: 50), tolerance: 0.01))
    for character in layout.characters {
      #expect(character.end.x < character.start.x)
      #expect(character.angle == 0)
    }
    #expect(layout.characters[1].start.x < layout.characters[0].start.x)
  }

  @Test("vertical characters go down, upright ones unturned and the others turned a quarter")
  func vertical() async throws {
    let view = view(##"<text id="t" x="350" y="20" style="writing-mode: vertical-rl">あb</text>"##)
    let layout = try await layout("t", in: view)
    let upright = layout.characters[0]
    let turned = layout.characters[1]
    #expect(abs(upright.start.x - 350) < 0.01 && upright.end.y > upright.start.y)
    #expect(abs(upright.angle) < 1e-6)
    #expect(abs(turned.angle - .pi / 2) < 1e-6)
    #expect(turned.start.y >= upright.end.y - 0.01)
  }

  @Test("rotate and a path turn the characters, and the ones off the path aren't rendered")
  func turned() async throws {
    let view = view(
      ##"<text id="r" x="10" y="50" rotate="90">a</text><path id="p" d="M 10 200 V 300"/>"##
        + ##"<text id="t"><textPath href="#p">abcdefghij</textPath></text>"##)
    let rotated = try await layout("r", in: view)
    #expect(abs(rotated.characters[0].angle - .pi / 2) < 1e-6)
    let onPath = try await layout("t", in: view)
    #expect(abs(onPath.characters[0].angle - .pi / 2) < 1e-6)
    #expect(isClose(onPath.characters[0].start, CGPoint(x: 10, y: 200), tolerance: 0.01))
    let last = try #require(onPath.characters.last)
    #expect(!last.isRendered)
    #expect(last.extent.size == .zero)
    let rendered = try #require(onPath.characters.last { $0.isRendered })
    #expect(last.start == rendered.end)
  }

  @Test("the characters of a ligature have the geometry of the ligature, and a caret can go between them")
  func ligature() async throws {
    // The fonts that draw "fi" as a ligature differ between systems, so the text is laid out in the first family of
    // the ones that draw it here.
    var found: SVGDocument.TextLayout?
    for family in ["Hoefler Text", "Baskerville", "Palatino", "Didot", "Helvetica Neue"] {
      let view = view(##"<text id="t" x="10" y="50" font-family="\##(family)">fia</text>"##)
      let layout = try await layout("t", in: view)
      if layout.characters[0] == layout.characters[1] {
        found = layout
        break
      }
    }
    guard let layout = found else {
      // No font of the system draws the ligature.
      return
    }
    let f = layout.characters[0]
    let i = layout.characters[1]
    #expect(f == i)
    #expect(layout.characters[2] != i)
    // The first character of the ligature has the cell, also where the second character is.
    #expect(layout.characterIndex(at: CGPoint(x: f.start.x + (f.end.x - f.start.x) * 0.75, y: 45)) == 0)
    // The caret goes between the characters of the ligature, in the middle of it.
    let caret = try #require(layout.caretPath(at: 1)).boundingBoxOfPath
    #expect(abs(caret.minX - (f.start.x + f.end.x) / 2) < 0.01)
    #expect(layout.insertionIndex(closestTo: CGPoint(x: (f.start.x + f.end.x) / 2 + 0.5, y: 45)) == 1)
  }

  @Test("the layout has the changes of the text")
  func changes() async throws {
    let view = view(##"<text id="t" x="10" y="50">ab</text>"##)
    let text = try #require(view.document.element(id: "t"))
    text.textContent = "abc"
    let layout = try await layout("t", in: view)
    #expect(layout.text == "abc")
  }

  @Test("elements that aren't text, that aren't in the tree, or that no view shows have no layout")
  func none() async throws {
    let view = view(##"<rect id="r" width="10" height="10"/><text id="t">a</text>"##)
    #expect(await view.document.element(id: "r")?.textLayout() == nil)
    let created = view.document.createElement("text")
    #expect(await created.textLayout() == nil)
    let document = SVGUIView(data: Data(##"<svg xmlns="http://www.w3.org/2000/svg"><text id="t">a</text></svg>"##.utf8))
      .document
    #expect(await document.element(id: "t")?.textLayout() == nil)
  }
}
