/// The names of attributes that a document can have and write as XML that is read again.
package enum AttributeName {
  /// Whether a document can have an attribute of a name: a name without a prefix, other than `xmlns`, or one with the
  /// `xml` or the `xlink` prefix, where the part after the prefix and the name without a prefix are names of XML
  /// Namespaces (`NCName`).
  ///
  /// A name with another prefix, which would be written without a declaration of its namespace, `xmlns` and the names
  /// with its prefix, which would declare namespaces, and a name that isn't a name of XML, aren't. A parsed document
  /// doesn't have them either.
  package static func isWritable(_ name: String) -> Bool {
    let parts = name.utf8.split(separator: UInt8(ascii: ":"), maxSplits: 2, omittingEmptySubsequences: false)
    switch parts.count {
    case 1:
      return name != "xmlns" && isNCName(Substring(parts[0]))
    case 2:
      let prefix = Substring(parts[0])
      return (prefix == "xml" || prefix == "xlink") && isNCName(Substring(parts[1]))
    default:
      return false
    }
  }

  /// Whether a string is a name of XML without a colon: a `NameStartChar` followed by `NameChar`s of XML 1.0, without
  /// the colon. The names of the elements that a document writes are such names too.
  package static func isNCName(_ name: Substring) -> Bool {
    var scalars = name.unicodeScalars.makeIterator()
    guard let first = scalars.next(), isNameStart(first) else { return false }
    while let next = scalars.next() {
      guard isNameStart(next) || isNameCharacter(next) else { return false }
    }
    return true
  }

  private static func isNameStart(_ scalar: Unicode.Scalar) -> Bool {
    switch scalar.value {
    case 0x41...0x5A, 0x5F, 0x61...0x7A, 0xC0...0xD6, 0xD8...0xF6, 0xF8...0x2FF, 0x370...0x37D, 0x37F...0x1FFF,
      0x200C...0x200D, 0x2070...0x218F, 0x2C00...0x2FEF, 0x3001...0xD7FF, 0xF900...0xFDCF, 0xFDF0...0xFFFD,
      0x10000...0xEFFFF:
      return true
    default:
      return false
    }
  }

  /// A `NameChar` that isn't a `NameStartChar`.
  private static func isNameCharacter(_ scalar: Unicode.Scalar) -> Bool {
    switch scalar.value {
    case 0x2D, 0x2E, 0x30...0x39, 0xB7, 0x300...0x36F, 0x203F...0x2040:
      return true
    default:
      return false
    }
  }
}
