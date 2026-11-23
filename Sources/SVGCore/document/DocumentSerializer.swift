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
