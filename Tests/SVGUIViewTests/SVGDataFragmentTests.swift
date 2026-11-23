import CoreGraphics
import Foundation
import Testing
import UIKit

@testable import SVGUIView

/// Tests that an app copies an element as SVG data, with the elements that it references, and pastes SVG data into
/// a document.
@MainActor
@Suite("Copying and pasting SVG data", .timeLimit(.minutes(2)))
struct SVGDataFragmentTests {
  private static let header = ##"<?xml version="1.0" encoding="UTF-8"?>"## + "\n"

  private func document(_ content: String, root: String = "") -> SVGDocument {
    let svg = ##"<svg xmlns="http://www.w3.org/2000/svg"\##(root)>"## + content + "</svg>"
    return SVGUIView(data: Data(svg.utf8)).document
  }

  private func text(_ data: Data) -> String {
    String(decoding: data, as: UTF8.self)
  }

  @Test("an element without references is written alone in an svg element with the size of the root")
  func elementAlone() throws {
    let document = document(
      ##"<g><rect id="r" x="1" fill="red"/></g>"##,
      root: ##" width="20" height="10" viewBox="0 0 40 20" preserveAspectRatio="none" class="c""##)
    let rect = try #require(document.element(id: "r"))
    #expect(
      text(rect.svgData())
        == Self.header
        + ##"<svg xmlns="http://www.w3.org/2000/svg" height="10" preserveAspectRatio="none" viewBox="0 0 40 20" width="20">"##
        + ##"<rect fill="red" id="r" x="1"/></svg>"##)
  }

  @Test("the root element is written as the document is")
  func root() throws {
    let document = document(##"<rect id="r"/>"##, root: ##" width="20""##)
    #expect(try #require(document.rootElement).svgData() == document.svgData())
  }

  @Test("the referenced elements are written in a defs element in document order, once each")
  func references() throws {
    let document = document(
      ##"<defs><linearGradient id="base"><stop offset="0"/></linearGradient>"##
        + ##"<linearGradient id="g" href="#base"/><clipPath id="c"><rect width="5" height="5"/></clipPath>"##
        + ##"<rect id="unused"/></defs><symbol id="s"><circle r="1" fill="url('#g')"/></symbol>"##
        + ##"<g id="copied" style="clip-path: url(#c)"><rect id="r" fill="url(#g) red" stroke="url(&quot;#g&quot;)"/>"##
        + ##"<use href="#s"/><use href="#r"/><use href="#copied"/></g>"##)
    let group = try #require(document.element(id: "copied"))
    #expect(
      text(group.svgData())
        == Self.header + ##"<svg xmlns="http://www.w3.org/2000/svg"><defs>"##
        + ##"<linearGradient id="base"><stop offset="0"/></linearGradient>"##
        + ##"<linearGradient href="#base" id="g"/><clipPath id="c"><rect height="5" width="5"/></clipPath>"##
        + ##"<symbol id="s"><circle fill="url('#g')" r="1"/></symbol></defs>"##
        + ##"<g id="copied" style="clip-path: url(#c)"><rect fill="url(#g) red" id="r" stroke="url(&quot;#g&quot;)"/>"##
        + ##"<use href="#s"/><use href="#r"/><use href="#copied"/></g></svg>"##)
  }

  @Test("a referenced element in another referenced element is written with that element only")
  func nestedReferences() throws {
    let document = document(
      ##"<defs id="d"><linearGradient id="a"/><linearGradient id="b" href="#a"/></defs>"##
        + ##"<rect id="r" fill="url(#b)" stroke="url(#d)"/>"##)
    let rect = try #require(document.element(id: "r"))
    #expect(
      text(rect.svgData())
        == Self.header + ##"<svg xmlns="http://www.w3.org/2000/svg"><defs>"##
        + ##"<defs id="d"><linearGradient id="a"/><linearGradient href="#a" id="b"/></defs></defs>"##
        + ##"<rect fill="url(#b)" id="r" stroke="url(#d)"/></svg>"##)
  }

  @Test("an xlink:href is written with the declaration of the XLink namespace")
  func xlink() throws {
    let document = document(
      ##"<rect id="target"/><use id="u" xlink:href="#target"/>"##,
      root: ##" xmlns:xlink="http://www.w3.org/1999/xlink""##)
    let use = try #require(document.element(id: "u"))
    #expect(
      text(use.svgData())
        == Self.header
        + ##"<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink">"##
        + ##"<defs><rect id="target"/></defs><use id="u" xlink:href="#target"/></svg>"##)
  }

  @Test("the written data, inserted into another document, adds the referenced elements and the same element")
  func roundTrip() throws {
    let source = document(
      ##"<linearGradient id="g"><stop offset="0" stop-color="red"/></linearGradient>"##
        + ##"<rect id="r" width="10" height="10" fill="url(#g)"><title>A &amp; B</title></rect>"##)
    let target = document(##"<circle id="c"/>"##)
    let root = try #require(target.rootElement)
    let inserted = try root.append(svgData: try #require(source.element(id: "r")).svgData())
    #expect(inserted.map(\.localName) == ["defs", "rect"])
    #expect(inserted.allSatisfy { $0.isConnected })
    let rect = try #require(target.element(id: "r"))
    #expect(rect == inserted[1])
    let copied = try #require(source.element(id: "r"))
    #expect(rect.svgData() == copied.svgData())
    #expect(rect.textContent == "A & B")
    #expect(target.element(id: "g")?.parent == inserted[0])
  }

  @Test("inserting the data twice keeps the identifiers that the document has")
  func sameIdentifiers() throws {
    let document = document(##"<rect id="r" fill="red"/>"##)
    let root = try #require(document.rootElement)
    let data = try #require(document.element(id: "r")).svgData()
    let first = try root.append(svgData: data)
    let second = try root.append(svgData: data)
    #expect(try root.querySelectorAll("#r").count == 3)
    // The elements are different elements of the document.
    #expect(Set(first + second).count == 2)
    let created = document.createElement("g")
    #expect(!(first + second).contains(created))
  }

  @Test("elements without namespace declarations are inserted before a child")
  func elements() throws {
    let document = document(##"<rect id="a"/><rect id="b"/>"##)
    let root = try #require(document.rootElement)
    let inserted = try root.insert(
      svgData: Data(##"<circle id="c" r="1"/> <use xlink:href="#a"/>"##.utf8), before: document.element(id: "b"))
    #expect(inserted.map(\.localName) == ["circle", "use"])
    #expect(inserted[1].attribute("xlink:href") == "#a")
    #expect(root.children.map(\.localName) == ["rect", "circle", "use", "rect"])
  }

  @Test("data that isn't well-formed, or a reference that isn't a child, throws and changes nothing")
  func errors() throws {
    let document = document(##"<g id="g"><rect id="a"/></g><rect id="b"/>"##)
    let root = try #require(document.rootElement)
    let before = document.svgData()
    #expect(throws: SVGDocument.SVGDataError(reason: .notWellFormed)) {
      try root.append(svgData: Data("<rect><circle></rect>".utf8))
    }
    #expect(throws: SVGDocument.SVGDataError(reason: .referenceNotChild)) {
      try root.insert(svgData: Data("<rect/>".utf8), before: document.element(id: "a"))
    }
    #expect(document.svgData() == before)
  }

  @Test("a style element in the data applies its rules to the document")
  func styleSheet() throws {
    let view = SVGUIView(data: Data(##"<svg xmlns="http://www.w3.org/2000/svg"><rect id="r"/></svg>"##.utf8))
    let root = try #require(view.document.rootElement)
    try root.append(svgData: Data("<style>rect { fill: green }</style>".utf8))
    #expect(try #require(view.document.element(id: "r")).computedStyle.property("fill") == "rgb(0, 128, 0)")
  }

  @Test("the inserted element renders as the copied one does")
  func rendering() async throws {
    let content =
      ##"<linearGradient id="g"><stop offset="0" stop-color="red"/><stop offset="1" stop-color="blue"/></linearGradient>"##
      + ##"<clipPath id="c"><circle cx="10" cy="10" r="8"/></clipPath>"##
      + ##"<rect id="r" width="20" height="20" fill="url(#g)" clip-path="url(#c)"/>"##
    func view(_ content: String) -> SVGUIView {
      let view = SVGUIView(
        frame: CGRect(x: 0, y: 0, width: 20, height: 20),
        data: Data(##"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20">\##(content)</svg>"##.utf8))
      view.configuration = SVGUIViewConfiguration(timeoutDuration: patience, animation: .none)
      return view
    }
    let source = view(content)
    let target = view("")
    try #require(target.document.rootElement).append(
      svgData: try #require(source.document.element(id: "r")).svgData())
    let expected = try #require(try await source.takeSnapshot(scale: 1).cgImage)
    let found = try #require(try await target.takeSnapshot(scale: 1).cgImage)
    #expect(try pixels(of: found) == pixels(of: expected))
  }
}
