import CoreGraphics

enum SVGMaskType: String {
  case none
  case url
}

enum SVGMask {
  case url(url: String)
  case none

  init?(description: String) {
    var data = description
    let clipPath = data.withUTF8 {
      let bytes = BufferView(unsafeBufferPointer: $0)!
      var scanner = SVGAttributeScanner(bytes: bytes)
      return scanner.scanMask()
    }
    guard let clipPath = clipPath else {
      return nil
    }
    self = clipPath
  }

}
