import CoreGraphics
import Foundation
import ImageIO

final class SVGImageElement: ShapeGeometry {
  static var type: SVGElementName {
    .circle
  }

  var type: SVGElementName {
    .circle
  }

  let base: SVGBaseElement
  let data: Data?
  let x: SVGLength?
  let y: SVGLength?
  let width: SVGLength?
  let height: SVGLength?
  /// How the image is placed in the rectangle of `x`, `y`, `width` and `height`.
  let preserveAspectRatio: PreserveAspectRatio

  init(base: SVGBaseElement, text _: String, attributes: [String: String]) {
    self.base = base
    let src = attributes["href", default: ""].split(separator: ",").map { String($0) }
    data = src.last.flatMap { Data(base64Encoded: $0, options: .ignoreUnknownCharacters) }
    x = SVGLength(attributes["x"]) ?? .pixel(0)
    y = SVGLength(attributes["y"]) ?? .pixel(0)
    width = SVGLength(attributes["width"])
    height = SVGLength(attributes["height"])
    preserveAspectRatio =
      PreserveAspectRatio(description: attributes["preserveAspectRatio", default: ""]) ?? PreserveAspectRatio()
  }

  func path(in context: any GeometryContext) -> CGPath? {
    let x = x?.value(context: context, mode: .width) ?? 0
    let y = y?.value(context: context, mode: .width) ?? 0
    let width = width?.value(context: context, mode: .width) ?? 0
    let height = height?.value(context: context, mode: .height) ?? 0

    guard width > 0, height > 0 else {
      return nil
    }
    let path = CGPath(rect: .init(x: x, y: y, width: width, height: height), transform: nil)
    return path
  }

  /// The image of the data, or `nil` if the data isn't an image.
  func decodedImage() -> CGImage? {
    guard let data = data,
      let source = CGImageSourceCreateWithData(data as CFData, nil)
    else { return nil }
    return CGImageSourceCreateImageAtIndex(source, 0, nil)
  }

  /// The data of the SVG image that the data is, gzipped or not, or `nil` if it doesn't start like an XML document.
  func svgData() -> Data? {
    guard var data else { return nil }
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

extension SVGImageElement: Encodable {
  private enum CodingKeys: String, CodingKey {
    case x
    case y
    case width
    case height
  }

  func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: Self.CodingKeys.self)
    try container.encode(x, forKey: .x)
    try container.encode(y, forKey: .y)
    try container.encode(width, forKey: .width)
    try container.encode(height, forKey: .height)
  }
}
