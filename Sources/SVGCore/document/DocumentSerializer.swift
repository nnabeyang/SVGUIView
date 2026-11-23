import Foundation

extension DocumentTree {
  /// The document as SVG: its elements with their attributes as written, and the character data that the tree keeps,
  /// as UTF-8 XML.
  ///
  /// The attributes are the ones as written, without the values of SMIL animations, in the order of their names, so
  /// that the same document is always written the same way. The root declares the SVG namespace, and an element of
  /// another namespace declares its namespace where it differs from its parent's. An attribute of the XLink namespace,
  /// such as `xlink:href`, is written as it is, and the root declares the XLink namespace if the document has one.
  /// Nothing is added between the elements, so that the character data, and the white space that `xml:space` keeps,
  /// are written as they are.
  package func xmlData() -> Data {
    var xml = #"<?xml version="1.0" encoding="UTF-8"?>"# + "\n"
    if let root {
      Self.write(root, parentNamespace: nil, isRoot: true, declaresXLink: Self.hasXLinkAttribute(root), into: &xml)
    }
    return Data(xml.utf8)
  }

  /// An element and its descendants as an SVG document that renders them alone, as UTF-8 XML, or `nil` if the document
  /// has no such element.
  ///
  /// The root of the written document is an `svg` element with the `width`, `height`, `viewBox` and
  /// `preserveAspectRatio` of the root of this document, if it's an `svg` element. Its children are a `<defs>` element
  /// with the elements that the element and its descendants reference, if they reference any, and then the element.
  /// The references are the fragment identifiers of `url()` in the attributes, such as a `fill` or a `style`, and of
  /// `href` and `xlink:href`, found again in the referenced elements. A referenced element is written with its
  /// descendants, unless it's the element, one of its descendants or ancestors, or in another referenced element, and
  /// the referenced elements are in document order. The root element of the document is written as ``xmlData()``
  /// writes it, when it's an `svg` element. The attributes are written as ``xmlData()`` writes them.
  package func xmlData(of id: ElementID) -> Data? {
    guard let root, let element = cursor(at: id)?.element else { return nil }
    if element === root, root.name == .svg {
      return xmlData()
    }
    // The first element of each identifier in document order, which a reference finds.
    var identified = [String: DocumentElement]()
    func identify(_ element: DocumentElement) {
      if let value = element.writtenAttributes["id"], identified[value] == nil {
        identified[value] = element
      }
      element.children.forEach(identify)
    }
    identify(root)
    var referenced = Set<ElementID>()
    var pending = [element]
    while let next = pending.popLast() {
      for target in Self.references(in: next) {
        guard let found = identified[target], !referenced.contains(found.id),
          !isElement(found.id, inSubtreeOf: id), !isElement(id, inSubtreeOf: found.id)
        else { continue }
        referenced.insert(found.id)
        pending.append(found)
      }
    }
    // The outermost referenced elements, in document order.
    var definitions = [DocumentElement]()
    func collect(_ element: DocumentElement) {
      if referenced.contains(element.id) {
        definitions.append(element)
        return
      }
      element.children.forEach(collect)
    }
    collect(root)
    var xml = #"<?xml version="1.0" encoding="UTF-8"?>"# + "\n"
    xml += #"<svg xmlns=""# + Self.svgNamespace + #"""#
    if Self.hasXLinkAttribute(element) || definitions.contains(where: Self.hasXLinkAttribute) {
      xml += #" xmlns:xlink="http://www.w3.org/1999/xlink""#
    }
    if root.name == .svg {
      for name in ["height", "preserveAspectRatio", "viewBox", "width"] {
        guard let value = root.writtenAttributes[name] else { continue }
        xml += " " + name + #"=""# + Self.escapedAttribute(value) + #"""#
      }
    }
    xml += ">"
    if !definitions.isEmpty {
      xml += "<defs>"
      for definition in definitions {
        Self.write(definition, parentNamespace: Self.svgNamespace, isRoot: false, into: &xml)
      }
      xml += "</defs>"
    }
    Self.write(element, parentNamespace: Self.svgNamespace, isRoot: false, into: &xml)
    xml += "</svg>"
    return Data(xml.utf8)
  }

  /// The fragment identifiers that an element and its descendants reference with `url()` in their attributes and
  /// with `href` and `xlink:href`.
  private static func references(in element: DocumentElement) -> [String] {
    var found = [String]()
    func visit(_ element: DocumentElement) {
      for (name, value) in element.writtenAttributes {
        if name == "href" || name == "xlink:href" {
          let trimmed = value.trimmingCharacters(in: .whitespaces)
          if trimmed.hasPrefix("#"), trimmed.count > 1 {
            found.append(String(trimmed.dropFirst()))
          }
        }
        found += urlFragments(in: value)
      }
      element.children.forEach(visit)
    }
    visit(element)
    return found
  }

  /// The fragment identifiers of the `url()` in a value, quoted or not.
  private static func urlFragments(in value: String) -> [String] {
    var found = [String]()
    var rest = value[...]
    while let start = rest.range(of: "url(", options: .caseInsensitive) {
      rest = rest[start.upperBound...].drop { $0.isWhitespace }
      if let quote = rest.first, quote == "\"" || quote == "'" {
        rest = rest.dropFirst()
      }
      guard rest.first == "#" else { continue }
      let identifier = rest.dropFirst().prefix { !"\"')".contains($0) && !$0.isWhitespace }
      if !identifier.isEmpty {
        found.append(String(identifier))
      }
      rest = rest.dropFirst(identifier.count + 1)
    }
    return found
  }

  private static let svgNamespace = "http://www.w3.org/2000/svg"

  /// Whether the element or one of its descendants has an attribute of the XLink namespace, which the root then
  /// declares.
  private static func hasXLinkAttribute(_ element: DocumentElement) -> Bool {
    element.writtenAttributes.keys.contains { $0.hasPrefix("xlink:") } || element.children.contains(where: hasXLinkAttribute)
  }

  private static func write(
    _ element: DocumentElement, parentNamespace: String?, isRoot: Bool, declaresXLink: Bool = false,
    into xml: inout String
  ) {
    let namespace = element.namespace ?? svgNamespace
    xml += "<" + element.localName
    if isRoot || namespace != (parentNamespace ?? svgNamespace) {
      xml += #" xmlns=""# + escapedAttribute(namespace) + #"""#
    }
    if declaresXLink {
      xml += #" xmlns:xlink="http://www.w3.org/1999/xlink""#
    }
    for (name, value) in element.writtenAttributes.sorted(by: { $0.key < $1.key }) {
      xml += " " + name + #"=""# + escapedAttribute(value) + #"""#
    }
    guard !element.children.isEmpty || element.texts.contains(where: { !$0.isEmpty }) else {
      xml += "/>"
      return
    }
    xml += ">"
    for (index, child) in element.children.enumerated() {
      xml += escapedText(element.texts[index])
      write(child, parentNamespace: namespace, isRoot: false, into: &xml)
    }
    xml += escapedText(element.texts[element.children.count])
    xml += "</" + element.localName + ">"
  }

  /// The value of an attribute, with the characters that would end it or that XML normalizes escaped.
  private static func escapedAttribute(_ value: String) -> String {
    var escaped = ""
    escaped.reserveCapacity(value.utf8.count)
    for character in value.unicodeScalars {
      switch character {
      case "&": escaped += "&amp;"
      case "<": escaped += "&lt;"
      case ">": escaped += "&gt;"
      case "\"": escaped += "&quot;"
      case "\t": escaped += "&#9;"
      case "\n": escaped += "&#10;"
      case "\r": escaped += "&#13;"
      default: escaped.unicodeScalars.append(character)
      }
    }
    return escaped
  }

  /// Character data, with the characters that would start markup escaped, and a carriage return kept as it is.
  private static func escapedText(_ text: String) -> String {
    guard text.unicodeScalars.contains(where: { $0 == "&" || $0 == "<" || $0 == ">" || $0 == "\r" }) else {
      return text
    }
    var escaped = ""
    escaped.reserveCapacity(text.utf8.count)
    for character in text.unicodeScalars {
      switch character {
      case "&": escaped += "&amp;"
      case "<": escaped += "&lt;"
      case ">": escaped += "&gt;"
      case "\r": escaped += "&#13;"
      default: escaped.unicodeScalars.append(character)
      }
    }
    return escaped
  }
}
