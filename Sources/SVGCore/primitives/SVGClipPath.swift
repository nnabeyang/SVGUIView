import CoreGraphics

enum SVGClipPathType: String {
  case none
  case url
}

/// The value of `clip-path`: a `<clipPath>` element, a basic shape with its reference box, a reference box alone, or
/// `none`.
enum SVGClipPath: Equatable, Sendable {
  case url(url: String)
  /// A basic shape in its reference box, or the reference box itself if the shape is `nil`. The shape is kept out of
  /// line, so that the value stays as small as a `url()` in every computed style.
  indirect case shape(BasicShape?, box: ClipBox)
  case none

  /// A `url()` or `none`, or `nil` if it's neither.
  init?(description: String) {
    var data = description
    let clipPath = data.withUTF8 {
      let bytes = BufferView(unsafeBufferPointer: $0)!
      var scanner = SVGAttributeScanner(bytes: bytes)
      return scanner.scanClipPath()
    }
    guard let clipPath = clipPath else {
      return nil
    }
    self = clipPath
  }

}

/// A value of `marker-start`, `marker-mid` or `marker-end`: the `<marker>` to draw at vertices of a shape.
///
/// The marker is an element of the document, named by its ID, or an element of the SVG document of a data URL, named
/// by the URL with its fragment, such as `data:image/svg+xml;base64,…#m`. An ID never has a `#`, which tells them
/// apart, so that the value stays as small as one string in every computed style.
enum SVGMarkerReference: Equatable {
  case url(String)
  case none

  init?(description: String) {
    if let reference = SVGClipPath(description: description) {
      if case .url(let id) = reference {
        self = .url(id)
      } else {
        self = .none
      }
      return
    }
    guard let url = Self.documentURL(in: description) else { return nil }
    self = .url(url)
  }

  /// The URL with a fragment that a `url()` names, in quotes or not, if it names an element of another document.
  private static func documentURL(in text: String) -> String? {
    let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard text.utf8.count > 5, text.prefix(4).lowercased() == "url(", text.hasSuffix(")") else { return nil }
    guard let url = urlReference(arguments: text.dropFirst(4).dropLast()), !url.hasPrefix("#"),
      Self.isDocumentReference(url)
    else { return nil }
    return url
  }

  /// Whether a reference names an element of another document: a URL with a fragment, rather than an ID.
  static func isDocumentReference(_ reference: some StringProtocol) -> Bool {
    guard let hash = reference.firstIndex(of: "#") else { return false }
    return reference.index(after: hash) != reference.endIndex
  }

  /// The id of the marker, or `nil` for `none`. For a marker of another document, it's its URL with the fragment.
  var id: String? {
    if case .url(let id) = self { id } else { nil }
  }
}
