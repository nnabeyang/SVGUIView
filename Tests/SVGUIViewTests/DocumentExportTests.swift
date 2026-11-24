import Foundation
import Testing
import UIKit

@testable import SVGUIView

@MainActor
@Suite("Writing documents as SVG")
struct DocumentExportTests {
  private static let declaration = #"<?xml version="1.0" encoding="UTF-8"?>"# + "\n"

  /// A view that shows the SVG.
  private func view(_ svg: String) -> SVGUIView {
    let view = SVGUIView(frame: CGRect(x: 0, y: 0, width: 100, height: 100), data: Data(svg.utf8))
    view.configuration = SVGUIViewConfiguration(timeoutDuration: patience, animation: .none)
    return view
  }

  /// The SVG that the document of a view writes, without the XML declaration.
  private func written(_ view: SVGUIView) throws -> String {
    let xml = try #require(String(data: view.document.svgData(), encoding: .utf8))
    #expect(xml.hasPrefix(Self.declaration))
    return String(xml.dropFirst(Self.declaration.count))
  }

  @Test("a document is written with its attributes in the order of their names, and its character data")
  func document() throws {
    let view = view(
      #"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10" width="10"><style>rect { fill: red }</style>"#
        + #"<g id="g"><rect y="2" x="1"/></g><text x="1">A <tspan>b</tspan> c</text><title>T</title></svg>"#)
    #expect(
      try written(view)
        == #"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10" width="10"><style>rect { fill: red }</style>"#
        + #"<g id="g"><rect x="1" y="2"/></g><text x="1">A <tspan>b</tspan> c</text><title>T</title></svg>"#)
  }

  @Test("the characters that would end an attribute or start markup are escaped, and parsed back as they were")
  func escaping() throws {
    let view = view(#"<svg xmlns="http://www.w3.org/2000/svg"><text id="t">a</text></svg>"#)
    let text = try #require(view.document.element(id: "t"))
    text.setAttribute("data-x", to: "1 & 2 < 3 > \"4\"\tline\nnext")
    text.textContent = "x < y & z > w"
    let xml = try written(view)
    #expect(xml.contains(#"data-x="1 &amp; 2 &lt; 3 &gt; &quot;4&quot;&#9;line&#10;next""#))
    #expect(xml.contains("x &lt; y &amp; z &gt; w"))
    let parsed = self.view(String(decoding: view.document.svgData(), as: UTF8.self))
    let again = try #require(parsed.document.element(id: "t"))
    #expect(again.attribute("data-x") == "1 & 2 < 3 > \"4\"\tline\nnext")
    #expect(again.textContent == "x < y & z > w")
  }

  @Test("the changes made through the document are written, and the elements outside the tree aren't")
  func changes() throws {
    let view = view(
      #"<svg xmlns="http://www.w3.org/2000/svg"><rect id="a" width="1"/><rect id="b" width="2"/></svg>"#)
    let document = view.document
    let root = try #require(document.rootElement)
    try #require(document.element(id: "a")).setAttribute("width", to: "5")
    try #require(document.element(id: "b")).remove()
    let circle = document.createElement("circle")
    circle.setAttribute("r", to: "3")
    try root.append(circle)
    _ = document.createElement("ellipse")
    #expect(
      try written(view)
        == #"<svg xmlns="http://www.w3.org/2000/svg"><rect id="a" width="5"/><circle r="3"/></svg>"#)
  }

  @Test("the attributes are written as written, without the values that SMIL animations give them")
  func animations() throws {
    let view = view(
      #"<svg xmlns="http://www.w3.org/2000/svg"><rect width="1" height="1">"#
        + #"<set attributeName="width" to="9"/></rect></svg>"#)
    view.seek(to: .seconds(1))
    #expect(
      try written(view)
        == #"<svg xmlns="http://www.w3.org/2000/svg"><rect height="1" width="1">"#
        + #"<set attributeName="width" to="9"/></rect></svg>"#)
  }

  @Test("an element of another namespace is written in its namespace, and xlink:href as it is")
  func namespaces() throws {
    let view = view(
      #"<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" "#
        + #"xmlns:inkscape="http://www.inkscape.org/namespaces/inkscape" xml:lang="en">"#
        + ##"<use xlink:href="#r" inkscape:label="x"/><foreignObject><div xmlns="http://www.w3.org/1999/xhtml">"##
        + #"<svg xmlns="http://www.w3.org/2000/svg"/></div></foreignObject><other xmlns=""/></svg>"#)
    #expect(
      try written(view)
        == #"<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" xml:lang="en">"#
        + ##"<use xlink:href="#r"/><foreignObject>"##
        + #"<div xmlns="http://www.w3.org/1999/xhtml"><svg xmlns="http://www.w3.org/2000/svg"/></div>"#
        + #"</foreignObject><other xmlns=""/></svg>"#)
  }

  @Test("href and xlink:href are written as separate attributes, and parsed back as they were")
  func hrefAndXLinkHref() throws {
    let view = view(
      #"<svg xmlns="http://www.w3.org/2000/svg" xmlns:l="http://www.w3.org/1999/xlink">"#
        + ##"<rect id="a"/><use id="u" href="#a" l:href="#b"/></svg>"##)
    let written = try written(view)
    #expect(
      written
        == #"<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink">"#
        + ##"<rect id="a"/><use href="#a" id="u" xlink:href="#b"/></svg>"##)
    let parsed = self.view(written)
    #expect(try self.written(parsed) == written)
    // A document without an attribute of the XLink namespace doesn't declare it.
    try #require(parsed.document.element(id: "u")).removeAttribute("xlink:href")
    #expect(try !self.written(parsed).contains("xmlns:xlink"))
  }

  @Test("an attribute of a name that the document can't write isn't set, and the document is parsed back")
  func unwritableNames() throws {
    let view = view(#"<svg xmlns="http://www.w3.org/2000/svg"><rect id="r"/></svg>"#)
    let rect = try #require(view.document.element(id: "r"))
    let unwritable = [
      "foo:bar", "xmlns", "xmlns:foo", "xml:", ":x", "a:b:c", "", "has space", "1x", "-x", "a<b", "a=b", "a\"b",
    ]
    for name in unwritable {
      rect.setAttribute(name, to: "1")
      #expect(rect.attribute(name) == nil, "\(name)")
    }
    let writable = ["data-x", "xml:lang", "xml:space", "xlink:href", "x.1", "_x", "名前", "é"]
    for name in writable {
      rect.setAttribute(name, to: "v")
      #expect(rect.attribute(name) == "v", "\(name)")
    }
    let xml = view.document.svgData()
    let parser = XMLParser(data: xml)
    parser.shouldProcessNamespaces = true
    #expect(parser.parse(), "\(String(decoding: xml, as: UTF8.self))")
    let parsed = self.view(String(decoding: xml, as: UTF8.self))
    let again = try #require(parsed.document.element(id: "r"))
    for name in ["data-x", "xml:lang", "xml:space", "xlink:href", "x.1", "_x", "名前", "é"] {
      #expect(again.attribute(name) == "v", "\(name)")
    }
    // The document sets the attributes that it writes for its own changes.
    let text = view.document.createElement("text")
    text.textContent = "a"
    text.style.setProperty("fill", to: "red")
    text.classList.add("c")
    #expect(text.attribute("style") != nil)
    #expect(text.attribute("class") == "c")
  }

  @Test("the white space that xml:space keeps is written as it is")
  func whiteSpace() throws {
    let view = view(
      #"<svg xmlns="http://www.w3.org/2000/svg"><text xml:space="preserve">  a  <tspan> b </tspan>  </text></svg>"#)
    #expect(
      try written(view)
        == #"<svg xmlns="http://www.w3.org/2000/svg"><text xml:space="preserve">  a  <tspan> b </tspan>  </text></svg>"#)
  }
}
