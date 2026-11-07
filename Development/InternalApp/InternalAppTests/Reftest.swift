import Foundation
import SVGTestSuite
import SVGUIView
import Testing
import UIKit

/// A reftest of web-platform-tests: an SVG file with `<link rel="match">` or `<link rel="mismatch">` to SVG files
/// that it must render as, or not as, within the fuzziness of its `<meta name="fuzzy">`.
struct Reftest: Sendable, CustomTestStringConvertible {
  /// A range of a difference, inclusive.
  struct Range: Sendable, Equatable {
    let lowerBound: Int
    let upperBound: Int
  }

  /// How much a rendering may differ from a reference: the largest difference of a color component, and the number
  /// of pixels that differ.
  struct Fuzziness: Sendable, Equatable {
    let maxDifference: Range
    let totalPixels: Range
  }

  let url: URL
  /// The path from the top of the test suite's `wpt` folder, such as `svg/styling/name.svg`.
  let path: String
  let matches: [URL]
  let mismatches: [URL]
  /// The fuzziness for every reference without its own.
  let fuzziness: Fuzziness?
  /// The fuzziness of each reference that has its own, by its URL.
  let referenceFuzziness: [URL: Fuzziness]

  var testDescription: String { path }

  /// The fuzziness for a reference.
  func fuzziness(for reference: URL) -> Fuzziness? {
    referenceFuzziness[reference] ?? fuzziness
  }

  /// The reftests under `wpt/<components>` of the test suite, sorted by path. The references, which have no links,
  /// aren't reftests.
  static func all(in components: String...) -> [Reftest] {
    let top = TestSuite.bundle.bundleURL.appending(component: "wpt")
    let root = top.appending(path: components.joined(separator: "/"), directoryHint: .isDirectory)
    guard
      let enumerator = FileManager.default.enumerator(
        at: root, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
    else { return [] }
    return enumerator.compactMap { $0 as? URL }
      .filter { $0.pathExtension == "svg" }
      .sorted { $0.path < $1.path }
      .compactMap { url in
        let path = String(url.standardizedFileURL.path.dropFirst(top.standardizedFileURL.path.count + 1))
        return Reftest(url: url, path: path)
      }
  }

  /// The reftest of a file, or `nil` if the file has no `match` or `mismatch` link.
  init?(url: URL, path: String) {
    guard let parser = XMLParser(contentsOf: url) else { return nil }
    let reader = HeadReader()
    parser.delegate = reader
    parser.parse()
    let directory = url.deletingLastPathComponent()
    let top = TestSuite.bundle.bundleURL.appending(component: "wpt")
    // A path that starts with a slash is from the top of WPT.
    let resolve = { (href: String) in
      href.hasPrefix("/")
        ? top.appending(path: String(href.dropFirst())).standardizedFileURL
        : URL(filePath: href, relativeTo: directory).standardizedFileURL
    }
    matches = reader.links.filter { $0.rel == "match" }.map { resolve($0.href) }
    mismatches = reader.links.filter { $0.rel == "mismatch" }.map { resolve($0.href) }
    guard !matches.isEmpty || !mismatches.isEmpty else { return nil }
    var fuzziness: Fuzziness?
    var referenceFuzziness = [URL: Fuzziness]()
    for content in reader.fuzzy {
      guard let (reference, value) = Self.parseFuzzy(content) else { continue }
      if let reference {
        referenceFuzziness[resolve(reference)] = value
      } else {
        fuzziness = value
      }
    }
    self.url = url
    self.path = path
    self.fuzziness = fuzziness
    self.referenceFuzziness = referenceFuzziness
  }

  /// The reference and the fuzziness of the content of `<meta name="fuzzy">`, such as `0-1;0-11`,
  /// `maxDifference=0-127; totalPixels=0-1220` or `name-ref.svg:0-1;0-11`, whose reference is `nil` when it applies
  /// to every reference without its own. A single number is the range of only that number.
  static func parseFuzzy(_ content: String) -> (reference: String?, Fuzziness)? {
    var content = Substring(content)
    var reference: String?
    // The values have no colon, so a colon ends the URL of a reference.
    if let colon = content.firstIndex(of: ":") {
      reference = content[..<colon].trimmingCharacters(in: .whitespaces)
      content = content[content.index(after: colon)...]
    }
    var ranges = [String: Range]()
    var unnamed = [Range]()
    for part in content.split(separator: ";") {
      let pieces = part.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
      guard let text = pieces.last, let range = parseRange(text) else { return nil }
      if pieces.count == 2 {
        ranges[pieces[0]] = range
      } else {
        unnamed.append(range)
      }
    }
    guard ranges.count + unnamed.count == 2, let maxDifference = ranges["maxDifference"] ?? unnamed.first,
      let totalPixels = ranges["totalPixels"] ?? unnamed.last
    else { return nil }
    return (reference, Fuzziness(maxDifference: maxDifference, totalPixels: totalPixels))
  }

  private static func parseRange(_ text: String) -> Range? {
    let bounds = text.split(separator: "-", omittingEmptySubsequences: false).map { Int($0.trimmingCharacters(in: .whitespaces)) }
    switch bounds.count {
    case 1: return bounds[0].map { Range(lowerBound: $0, upperBound: $0) }
    case 2:
      guard let lower = bounds[0], let upper = bounds[1] else { return nil }
      return Range(lowerBound: lower, upperBound: upper)
    default: return nil
    }
  }
}

/// Reads the `link` and `meta` elements of a document, in any namespace.
private final class HeadReader: NSObject, XMLParserDelegate {
  var links = [(rel: String, href: String)]()
  var fuzzy = [String]()

  func parser(
    _: XMLParser, didStartElement elementName: String, namespaceURI _: String?, qualifiedName _: String?,
    attributes: [String: String] = [:]
  ) {
    let name = elementName.split(separator: ":").last.map(String.init) ?? elementName
    if name == "link", let rel = attributes["rel"], let href = attributes["href"] {
      links.append((rel.trimmingCharacters(in: .whitespaces), href.trimmingCharacters(in: .whitespaces)))
    } else if name == "meta", attributes["name"] == "fuzzy", let content = attributes["content"] {
      fuzzy.append(content)
    }
  }
}

/// The differences between two images of the same size: the largest difference of a red, green or blue component,
/// and the number of pixels that differ, as web-platform-tests counts them.
struct ImageDifference: Equatable {
  let maxDifference: Int
  let totalPixels: Int

  /// Whether the images are the same within the fuzziness, as wptrunner decides it: images without a difference
  /// are the same, and with a fuzziness, the differences must be in its ranges unless a range starts at 0 and that
  /// difference is 0.
  func isWithin(_ fuzziness: Reftest.Fuzziness?) -> Bool {
    guard let fuzziness,
      fuzziness
        != Reftest.Fuzziness(
          maxDifference: .init(lowerBound: 0, upperBound: 0), totalPixels: .init(lowerBound: 0, upperBound: 0))
    else { return maxDifference == 0 && totalPixels == 0 }
    let allowed = fuzziness
    return (totalPixels == 0 && allowed.totalPixels.lowerBound == 0)
      || (maxDifference == 0 && allowed.maxDifference.lowerBound == 0)
      || ((allowed.maxDifference.lowerBound...allowed.maxDifference.upperBound).contains(maxDifference)
        && (allowed.totalPixels.lowerBound...allowed.totalPixels.upperBound).contains(totalPixels))
  }
}

/// The pixels of an image over white, as a page shows it, in sRGB with 8 bits for each component.
struct Screenshot {
  static let width = 800
  static let height = 600

  /// The red, green, blue and alpha components of each pixel, row by row.
  let pixels: [UInt8]

  init(_ image: CGImage) {
    var pixels = [UInt8](repeating: 0, count: Self.width * Self.height * 4)
    pixels.withUnsafeMutableBytes { buffer in
      let context = CGContext(
        data: buffer.baseAddress, width: Self.width, height: Self.height, bitsPerComponent: 8,
        bytesPerRow: Self.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
      context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
      context.fill(CGRect(x: 0, y: 0, width: Self.width, height: Self.height))
      context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    }
    self.pixels = pixels
  }

  func difference(from other: Screenshot) -> ImageDifference {
    var maxDifference = 0
    var totalPixels = 0
    for offset in stride(from: 0, to: pixels.count, by: 4) {
      var largest = 0
      for component in 0..<3 {
        largest = max(largest, abs(Int(pixels[offset + component]) - Int(other.pixels[offset + component])))
      }
      if largest > 0 {
        totalPixels += 1
        maxDifference = max(maxDifference, largest)
      }
    }
    return ImageDifference(maxDifference: maxDifference, totalPixels: totalPixels)
  }

  /// An image of the pixels that differ from another screenshot, in red over a faint copy of this one.
  func differenceImage(from other: Screenshot) -> UIImage {
    var pixels = pixels
    for offset in stride(from: 0, to: pixels.count, by: 4) {
      let differs = (0..<3).contains { self.pixels[offset + $0] != other.pixels[offset + $0] }
      for component in 0..<3 {
        pixels[offset + component] = differs ? (component == 0 ? 255 : 0) : 255 - (255 - self.pixels[offset + component]) / 4
      }
      pixels[offset + 3] = 255
    }
    return Self.image(of: pixels)
  }

  var image: UIImage { Self.image(of: pixels) }

  private static func image(of pixels: [UInt8]) -> UIImage {
    let provider = CGDataProvider(data: Data(pixels) as CFData)!
    let image = CGImage(
      width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
      provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    return UIImage(cgImage: image)
  }
}

/// Renders a reftest and its references as a page of 800 × 600 CSS pixels shows them, and checks that it matches
/// one of its `match` references, if it has any, and none of its `mismatch` references, as web-platform-tests
/// decides it. When it fails, the renderings and their differences are attached to the test result.
@MainActor
func assertSVGReftest(_ test: Reftest, sourceLocation: SourceLocation = #_sourceLocation) async throws {
  try SnapshotEnvironment.requireExpected(sourceLocation: sourceLocation)
  guard let rendering = await screenshot(of: test.url, sourceLocation: sourceLocation) else { return }
  var failures = [String]()
  var compared = [(name: String, screenshot: Screenshot)]()
  if !test.matches.isEmpty {
    var matched = false
    for reference in test.matches {
      guard let expected = await screenshot(of: reference, sourceLocation: sourceLocation) else { return }
      let difference = rendering.difference(from: expected)
      if difference.isWithin(test.fuzziness(for: reference)) {
        matched = true
        break
      }
      failures.append(
        "\(reference.lastPathComponent) differs in \(difference.totalPixels) pixels by up to \(difference.maxDifference)"
          + (test.fuzziness(for: reference).map { ", beyond \(description(of: $0))" } ?? ""))
      compared.append((reference.lastPathComponent, expected))
    }
    if matched {
      failures.removeAll()
      compared.removeAll()
    }
  }
  for reference in test.mismatches {
    guard let unexpected = await screenshot(of: reference, sourceLocation: sourceLocation) else { return }
    if rendering.difference(from: unexpected).isWithin(test.fuzziness(for: reference)) {
      failures.append("\(reference.lastPathComponent) is a mismatch reference, but renders the same")
      compared.append((reference.lastPathComponent, unexpected))
    }
  }
  guard !failures.isEmpty else { return }
  Attachment.record(rendering.image, named: "test.png", sourceLocation: sourceLocation)
  for (name, screenshot) in compared {
    Attachment.record(screenshot.image, named: name + ".png", sourceLocation: sourceLocation)
    Attachment.record(rendering.differenceImage(from: screenshot), named: name + ".difference.png", sourceLocation: sourceLocation)
  }
  Issue.record(Comment(rawValue: "\(test.path): " + failures.joined(separator: "; ")), sourceLocation: sourceLocation)
}

private func description(of fuzziness: Reftest.Fuzziness) -> String {
  "maxDifference=\(fuzziness.maxDifference.lowerBound)-\(fuzziness.maxDifference.upperBound);"
    + "totalPixels=\(fuzziness.totalPixels.lowerBound)-\(fuzziness.totalPixels.upperBound)"
}

/// The rendering of a file in a view of 800 × 600 points at a scale of 1, which shows the document at its size as
/// a page does, or `nil` after recording why it couldn't be rendered.
@MainActor
private func screenshot(of url: URL, sourceLocation: SourceLocation) async -> Screenshot? {
  guard let view = SVGUIView(contentsOf: url) else {
    Issue.record("Couldn't read \(url.lastPathComponent)", sourceLocation: sourceLocation)
    return nil
  }
  // The document is placed at the top left at its size, as a page places it, instead of being scaled to the view.
  view.contentMode = .topLeft
  view.configuration = SVGUIViewConfiguration(timeoutDuration: .seconds(60))
  view.frame = CGRect(x: 0, y: 0, width: Screenshot.width, height: Screenshot.height)
  view.layoutIfNeeded()
  do {
    guard let image = try await view.takeSnapshot(scale: 1).cgImage else {
      Issue.record("Rendering \(url.lastPathComponent) gave no image", sourceLocation: sourceLocation)
      return nil
    }
    return Screenshot(image)
  } catch .missingRootElement {
    // A document without a root `svg` element draws nothing.
    return Screenshot(UIGraphicsImageRenderer(size: view.bounds.size).image { _ in }.cgImage!)
  } catch {
    Issue.record("Rendering \(url.lastPathComponent) failed: \(error)", sourceLocation: sourceLocation)
    return nil
  }
}
