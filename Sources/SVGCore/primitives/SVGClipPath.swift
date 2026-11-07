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
enum SVGMarkerReference: Equatable {
  case url(String)
  case none

  init?(description: String) {
    guard let reference = SVGClipPath(description: description) else { return nil }
    if case .url(let id) = reference {
      self = .url(id)
    } else {
      self = .none
    }
  }

  /// The id of the marker, or `nil` for `none`.
  var id: String? {
    if case .url(let id) = self { id } else { nil }
  }
}
