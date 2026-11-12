import CoreGraphics
import Foundation
import ImageIO

/// The data of an image that an `href` holds, of `<image>` and `<feImage>`.
enum EmbeddedImage {
  /// The `href` without its leading and trailing whitespace, as a part of it and not a copy, since an `href` can be a
  /// data URL of megabytes.
  static func trimmed(_ href: some StringProtocol) -> Substring {
    let scalars = href.unicodeScalars
    let isWhitespace = { CharacterSet.whitespacesAndNewlines.contains($0) }
    guard let first = scalars.firstIndex(where: { !isWhitespace($0) }),
      let last = scalars.lastIndex(where: { !isWhitespace($0) })
    else { return Substring() }
    return Substring(href[first...last])
  }

  /// Whether an `href` is a data URL: whether it starts with `data:` in any case after whitespace. It reads only the
  /// start of the `href`.
  static func isDataURL(_ href: some StringProtocol) -> Bool {
    let scheme = trimmed(href.prefix(64 + 5)).utf8.prefix(5)
    return scheme.count == 5
      && zip(scheme, "data:".utf8).allSatisfy { byte, expected in
        byte == expected || (expected >= UInt8(ascii: "a") && byte == expected - 0x20)
      }
  }

  /// The data of a data URL, or `nil` if the `href` isn't a data URL.
  ///
  /// The data after the first comma is base64 if the media type ends with `;base64`, and percent-encoded text
  /// otherwise, as the Fetch standard reads data URLs. A fragment after `#` isn't part of the data.
  static func data(ofHref href: some StringProtocol) -> Data? {
    dataURL(ofHref: href)?.data
  }

  /// The data and the fragment of a data URL, or `nil` if the `href` isn't a data URL or its data can't be read.
  ///
  /// It reads the `href` once and copies only the data, since a data URL can be megabytes long.
  static func dataURL(ofHref href: some StringProtocol) -> (data: Data, fragment: String?)? {
    let href = trimmed(href)
    guard isDataURL(href), let comma = href.utf8.firstIndex(of: UInt8(ascii: ",")) else { return nil }
    let mediaType = href[href.utf8.index(href.startIndex, offsetBy: 5)..<comma]
    var body = href[href.utf8.index(after: comma)...]
    var fragment: String?
    if let hash = body.utf8.firstIndex(of: UInt8(ascii: "#")) {
      fragment = decodedFragment(body[body.utf8.index(after: hash)...])
      body = body[..<hash]
    }
    // Most data URLs, such as the base64 of images, have no percent-encoded characters, and are copied only once.
    var text = String(body)
    if body.utf8.contains(UInt8(ascii: "%")) {
      text = text.removingPercentEncoding ?? text
    }
    if mediaType.trimmingCharacters(in: .whitespaces).lowercased().hasSuffix(";base64") {
      return Data(base64Encoded: text, options: .ignoreUnknownCharacters).map { ($0, fragment) }
    }
    return (Data(text.utf8), fragment)
  }

  /// The fragment of a URL after `#`, which names an element of an SVG image, or `nil` if it has none.
  static func fragment(ofHref href: some StringProtocol) -> String? {
    let href = trimmed(href)
    guard let hash = href.utf8.firstIndex(of: UInt8(ascii: "#")) else { return nil }
    return decodedFragment(href[href.utf8.index(after: hash)...])
  }

  /// The fragment without its percent-encoding, or `nil` if it's empty.
  private static func decodedFragment(_ fragment: Substring) -> String? {
    let fragment = String(fragment)
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
