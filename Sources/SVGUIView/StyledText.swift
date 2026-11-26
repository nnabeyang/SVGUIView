import Foundation

/// The text of a `text` element with the attributes of its runs, such as a
/// range in bold or in another color, which
/// ``SVGDocument/Element/styledText`` reads and
/// ``SVGDocument/Element/setStyledText(_:)`` writes.
///
/// A run is characters with the same attributes, which are the attributes of
/// the `tspan` element that the run is written as, such as `font-weight` or
/// `fill`. Characters without attributes are written as the character data of
/// the line. A line feed separates the lines, which are written as `tspan`
/// elements, as the characters that a person types are.
///
/// ```swift
/// let text = SVGStyledText(runs: [
///   .init("Hello, "),
///   .init("world", attributes: ["font-weight": "bold"]),
/// ])
/// element.setStyledText(text)
/// // <text x="10" y="50">Hello, <tspan font-weight="bold">world</tspan></text>
/// ```
public struct SVGStyledText: Equatable, Sendable {
  /// Characters with the same attributes.
  public struct Run: Equatable, Sendable {
    /// The characters of the run.
    public var text: String
    /// The attributes of the `tspan` element of the run, by their names, or
    /// none for characters that aren't in a `tspan` element.
    public var attributes: [String: String]

    /// Characters with attributes.
    public init(_ text: String, attributes: [String: String] = [:]) {
      self.text = text
      self.attributes = attributes
    }
  }

  /// The runs, without empty runs, and with the runs of the same attributes
  /// next to each other joined.
  public let runs: [Run]

  /// Text of runs, which are joined where they're next to each other and
  /// have the same attributes.
  public init(runs: [Run]) {
    var joined = [Run]()
    for run in runs where !run.text.isEmpty {
      if let last = joined.last, last.attributes == run.attributes {
        joined[joined.count - 1].text += run.text
      } else {
        joined.append(run)
      }
    }
    self.runs = joined
  }

  /// Text without attributes.
  public init(_ string: String) {
    self.init(runs: [Run(string)])
  }

  /// The characters of the text, without the attributes.
  public var string: String {
    runs.map(\.text).joined()
  }

  /// Text of characters with the attributes of each character.
  init(characters: [Character], attributes: [[String: String]]) {
    var runs = [Run]()
    for (character, attributes) in zip(characters, attributes) {
      if let last = runs.last, last.attributes == attributes {
        runs[runs.count - 1].text.append(character)
      } else {
        runs.append(Run(String(character), attributes: attributes))
      }
    }
    self.init(runs: runs)
  }

  /// The attributes of each character.
  var characterAttributes: [[String: String]] {
    runs.flatMap { run in Array(repeating: run.attributes, count: run.text.count) }
  }

  /// The runs of each line, without the line feeds.
  var lines: [[Run]] {
    var lines: [[Run]] = [[]]
    for run in runs {
      let parts = run.text.split(separator: "\n", omittingEmptySubsequences: false)
      for (index, part) in parts.enumerated() {
        if index > 0 { lines.append([]) }
        if !part.isEmpty { lines[lines.count - 1].append(Run(String(part), attributes: run.attributes)) }
      }
    }
    return lines
  }
}

/// How the runs of a `text` element are written as its content: the lines as `tspan` elements with the attribute of
/// the line position, and the runs with attributes as `tspan` elements in the lines.
@MainActor
enum StyledTextContent {
  /// The attributes that place characters, which a `tspan` of a run doesn't have, so that the lines stay where the
  /// line `tspan` elements put them in any renderer.
  static let positionAttributes: Set<String> = ["x", "y", "dx", "dy", "rotate", "textLength", "lengthAdjust"]

  /// The attribute that starts each line: `x` for horizontal lines, and `y` for vertical ones.
  static func lineAttribute(of text: SVGDocument.Element) -> String {
    isVertical(text) ? "y" : "x"
  }

  /// Whether the lines of a text are vertical, which `writing-mode` decides.
  static func isVertical(_ text: SVGDocument.Element) -> Bool {
    let writingMode = text.computedStyle.property("writing-mode") ?? "horizontal-tb"
    return writingMode.hasPrefix("vertical") || writingMode.hasPrefix("sideways")
  }

  /// Whether an element is the `tspan` of a run: one without position attributes or child elements.
  private static func isRun(_ element: SVGDocument.Element) -> Bool {
    element.localName == "tspan" && element.children.isEmpty
      && element.attributes.keys.allSatisfy { !positionAttributes.contains($0) }
  }

  /// Whether an element is the `tspan` of a line: one with the line attribute, whose children are runs.
  private static func isLine(_ element: SVGDocument.Element, lineAttribute: String) -> Bool {
    element.localName == "tspan" && element.attribute(lineAttribute) != nil && element.children.allSatisfy(isRun)
  }

  /// The runs of the character data and the run `tspan` elements of a line or of a text of one line.
  private static func runs(of container: SVGDocument.Element) -> [SVGStyledText.Run] {
    let texts = container.characterData
    var runs = [SVGStyledText.Run(texts.first ?? "")]
    for (child, text) in zip(container.children, texts.dropFirst()) {
      runs.append(SVGStyledText.Run(child.textContent, attributes: child.attributes))
      runs.append(SVGStyledText.Run(text))
    }
    return runs
  }

  /// The styled text of a `text` element, or `nil` if it isn't one line of character data and run `tspan` elements,
  /// or lines of them.
  static func read(_ text: SVGDocument.Element) -> SVGStyledText? {
    guard text.localName == "text" else { return nil }
    let children = text.children
    let lineAttribute = lineAttribute(of: text)
    if !children.isEmpty, children.allSatisfy({ isLine($0, lineAttribute: lineAttribute) }) {
      // The character data between the lines isn't part of the text.
      var runs = [SVGStyledText.Run]()
      for (index, line) in children.enumerated() {
        if index > 0 { runs.append(SVGStyledText.Run("\n")) }
        runs += Self.runs(of: line)
      }
      return SVGStyledText(runs: runs)
    }
    guard children.allSatisfy(isRun) else { return nil }
    return SVGStyledText(runs: runs(of: text))
  }

  /// Writes styled text into a `text` element: one line into the element itself, and more as `tspan` elements, with
  /// the runs that have attributes as `tspan` elements in the line. The elements of the lines and of the runs that
  /// are there are kept where they're written the same, so that typing changes only the character data.
  static func write(_ styled: SVGStyledText, into text: SVGDocument.Element) {
    let lines = styled.lines
    let lineAttribute = lineAttribute(of: text)
    guard lines.count > 1 else {
      write(lines.first ?? [], into: text)
      return
    }
    var children = text.children
    if children.count != lines.count || !children.allSatisfy({ isLine($0, lineAttribute: lineAttribute) }) {
      // The lines start where the text does, and each one is 1.2em after the one before it.
      let start =
        text.attribute(lineAttribute)?.split(whereSeparator: { $0 == " " || $0 == "," }).first
        .map(String.init) ?? "0"
      let isRightToLeft = (text.computedStyle.property("writing-mode") ?? "") == "vertical-rl"
      let advance =
        isVertical(text) ? (isRightToLeft ? ("dx", "-1.2em") : ("dx", "1.2em")) : ("dy", "1.2em")
      text.textContent = ""
      children = []
      for index in lines.indices {
        let tspan = text.document.createElement("tspan")
        tspan.setAttribute(lineAttribute, to: start)
        tspan.setAttribute(advance.0, to: index == 0 ? "0" : advance.1)
        try? text.append(tspan)
        children.append(tspan)
      }
    } else if text.characterData.contains(where: { !$0.isEmpty }) {
      // Character data between the lines would be rendered with the spaces kept.
      text.characterData = Array(repeating: "", count: children.count + 1)
    }
    for (line, runs) in zip(children, lines) {
      write(runs, into: line)
    }
  }

  /// Writes the runs of a line into a line `tspan` or a text: the runs without attributes as character data, and the
  /// others as `tspan` elements.
  private static func write(_ runs: [SVGStyledText.Run], into container: SVGDocument.Element) {
    var texts = [""]
    var styled = [SVGStyledText.Run]()
    for run in runs {
      if run.attributes.isEmpty {
        texts[texts.count - 1] += run.text
      } else {
        styled.append(run)
        texts.append("")
      }
    }
    let children = container.children
    if children.count == styled.count,
      zip(children, styled).allSatisfy({ isRun($0) && $0.attributes == $1.attributes })
    {
      for (child, run) in zip(children, styled) where child.textContent != run.text {
        child.textContent = run.text
      }
      container.characterData = texts
      return
    }
    if styled.isEmpty {
      container.textContent = texts[0]
      return
    }
    container.textContent = ""
    for run in styled {
      let tspan = container.document.createElement("tspan")
      for (name, value) in run.attributes.sorted(by: { $0.key < $1.key }) {
        tspan.setAttribute(name, to: value)
      }
      tspan.textContent = run.text
      try? container.append(tspan)
    }
    container.characterData = texts
  }
}

@MainActor
extension SVGDocument.Element {
  /// The text of a `text` element with the attributes of its runs, or `nil`
  /// if the element isn't a `text` element whose content is a line of
  /// character data and `tspan` elements without positions and child
  /// elements, or lines of them, as ``SVGUIView/SVGUIView/beginTextEditing(of:selecting:)``
  /// writes them.
  public var styledText: SVGStyledText? {
    StyledTextContent.read(self)
  }

  /// Replaces the content of a `text` element with styled text: one line as
  /// its character data and the `tspan` elements of its runs with attributes,
  /// and more lines as `tspan` elements 1.2em apart. It does nothing for
  /// another element.
  ///
  public func setStyledText(_ text: SVGStyledText) {
    guard localName == "text" else { return }
    StyledTextContent.write(text, into: self)
  }
}
