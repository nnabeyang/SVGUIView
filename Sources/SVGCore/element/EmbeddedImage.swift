import CoreGraphics
import Foundation
import ImageIO

/// The data of an image that an `href` holds, of `<image>` and `<feImage>`.
enum EmbeddedImage {
  /// The data of a data URL, or `nil` if the `href` isn't a data URL.
  ///
  /// The data after the first comma is base64 if the media type ends with `;base64`, and percent-encoded text
  /// otherwise, as the Fetch standard reads data URLs. A fragment after `#` isn't part of the data.
  static func data(ofHref href: String) -> Data? {
    let href = href.trimmingCharacters(in: .whitespacesAndNewlines)
    guard href.lowercased().hasPrefix("data:"), let comma = href.firstIndex(of: ",") else { return nil }
    let mediaType = href[href.index(href.startIndex, offsetBy: 5)..<comma]
    var body = href[href.index(after: comma)...]
    if let hash = body.firstIndex(of: "#") {
      body = body[..<hash]
    }
    let text = String(body).removingPercentEncoding ?? String(body)
    if mediaType.trimmingCharacters(in: .whitespaces).lowercased().hasSuffix(";base64") {
      return Data(base64Encoded: text, options: .ignoreUnknownCharacters)
    }
    return Data(text.utf8)
  }

  /// The fragment of a URL after `#`, which names an element of an SVG image, or `nil` if it has none.
  static func fragment(ofHref href: String) -> String? {
    let href = href.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let hash = href.firstIndex(of: "#") else { return nil }
    let fragment = String(href[href.index(after: hash)...])
    return fragment.isEmpty ? nil : fragment.removingPercentEncoding ?? fragment
  }

  /// The image of the data, or `nil` if the data isn't an image.
  static func decodedImage(of data: Data) -> CGImage? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil)
    else { return nil }
    return CGImageSourceCreateImageAtIndex(source, 0, nil)
  }

  /// The data of the SVG image that the data is, gzipped or not, or `nil` if it doesn't start like an XML document.
  static func svgData(of data: Data) -> Data? {
    var data = data
    if data.starts(with: [0x1F, 0x8B]) {
      guard let unzipped = Self.gunzipped(data) else { return nil }
      data = unzipped
    }
    // An XML document starts with a tag, after a byte order mark and spaces.
    let start = data.starts(with: [0xEF, 0xBB, 0xBF]) ? data.index(data.startIndex, offsetBy: 3) : data.startIndex
    let first = data[start...].first { ![0x20, 0x09, 0x0A, 0x0D].contains($0) }
    return first == UInt8(ascii: "<") ? data : nil
  }

  /// The data that gzipped data holds, or `nil` if it isn't gzipped data that can be unzipped.
  private static func gunzipped(_ data: Data) -> Data? {
    let bytes = [UInt8](data)
    // The header has 10 bytes, with optional fields after them that its flags tell, and a trailer of 8 bytes follows
    // the compressed data.
    guard bytes.count >= 18, bytes[2] == 8 else { return nil }
    let flags = bytes[3]
    var index = 10
    if flags & 0x04 != 0 {
      guard index + 2 <= bytes.count else { return nil }
      index += 2 + Int(bytes[index]) + Int(bytes[index + 1]) << 8
    }
    for flag: UInt8 in [0x08, 0x10] where flags & flag != 0 {
      // A file name or a comment, terminated by zero.
      guard let end = bytes[min(index, bytes.count)...].firstIndex(of: 0) else { return nil }
      index = end + 1
    }
    if flags & 0x02 != 0 {
      index += 2
    }
    guard index <= bytes.count - 8 else { return nil }
    return try? (Data(bytes[index..<(bytes.count - 8)]) as NSData).decompressed(using: .zlib) as Data
  }
}
