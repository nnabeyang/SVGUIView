import CoreGraphics
import Foundation
import Metal
import SVGRenderCG
import Testing

@testable import SVGCore
@testable import SVGRenderLayer

private let renderer = MetalFilterRenderer()

/// The filtered nodes of a document with the content, rendered into a rectangle of 100 by 100 at the scale.
private func filteredNodes(_ content: String, scale: CGFloat) async throws -> [FilteredNode] {
  let svg = #"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">"# + content + "</svg>"
  let base = SVGParser.parse(data: Data(svg.utf8))
  let rect = CGRect(x: 0, y: 0, width: 100, height: 100)
  let fit = ContentFit(
    preserveAspectRatio: PreserveAspectRatio(xAlign: .mid, yAlign: .mid, option: .meet), stretches: false, scales: true)
  let tree = try #require(await RenderTreeBuilder(base: base, viewPort: rect, scale: scale).build(fit: fit))
  let nodes = tree.root.map { [$0] + $0.descendants } ?? []
  return nodes.compactMap { node in
    guard case .filtered(let filtered) = node else { return nil }
    return filtered
  }
}

/// The bytes of an image, a row after another from the top, without padding.
private func bytes(of image: CGImage) throws -> [UInt8] {
  let data = try #require(image.dataProvider?.data as Data?)
  var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
  for row in 0..<image.height {
    bytes.replaceSubrange(
      (row * image.width * 4)..<((row + 1) * image.width * 4),
      with: data[(row * image.bytesPerRow)..<(row * image.bytesPerRow + image.width * 4)])
  }
  return bytes
}

/// A texture with the pixels of an image.
private func texture(of image: CGImage, on device: MTLDevice) throws -> MTLTexture {
  let descriptor = MTLTextureDescriptor.texture2DDescriptor(
    pixelFormat: .bgra8Unorm, width: image.width, height: image.height, mipmapped: false)
  descriptor.usage = [.shaderRead, .shaderWrite]
  descriptor.storageMode = .private
  let texture = try #require(device.makeTexture(descriptor: descriptor))
  let pixels = try bytes(of: image)
  let buffer = try #require(device.makeBuffer(bytes: pixels, length: pixels.count))
  let commands = try #require(device.makeCommandQueue()?.makeCommandBuffer())
  let blit = try #require(commands.makeBlitCommandEncoder())
  blit.copy(
    from: buffer, sourceOffset: 0, sourceBytesPerRow: image.width * 4, sourceBytesPerImage: pixels.count,
    sourceSize: MTLSize(width: image.width, height: image.height, depth: 1), to: texture, destinationSlice: 0,
    destinationLevel: 0, destinationOrigin: MTLOrigin())
  blit.endEncoding()
  commands.commit()
  commands.waitUntilCompleted()
  return texture
}

/// The bytes of a texture, a row after another from the top.
private func bytes(of texture: MTLTexture, on device: MTLDevice) throws -> [UInt8] {
  let length = texture.width * texture.height * 4
  let buffer = try #require(device.makeBuffer(length: length, options: .storageModeShared))
  let commands = try #require(device.makeCommandQueue()?.makeCommandBuffer())
  let blit = try #require(commands.makeBlitCommandEncoder())
  blit.copy(
    from: texture, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(),
    sourceSize: MTLSize(width: texture.width, height: texture.height, depth: 1), to: buffer, destinationOffset: 0,
    destinationBytesPerRow: texture.width * 4, destinationBytesPerImage: length)
  blit.endEncoding()
  commands.commit()
  commands.waitUntilCompleted()
  return [UInt8](UnsafeBufferPointer(start: buffer.contents().assumingMemoryBound(to: UInt8.self), count: length))
}

/// The largest difference of a component between the results of the filters of a document on the GPU and on the
/// CPU, or `nil` if the GPU doesn't run one of them.
private func largestDifference(_ content: String, scale: CGFloat) async throws -> Int? {
  let renderer = try #require(renderer)
  let painter = CGPainter(scale: scale)
  let nodes = try await filteredNodes(content, scale: scale)
  try #require(!nodes.isEmpty)
  var largest = 0
  for filtered in nodes {
    let source = try #require(await painter.sourceImage(of: filtered))
    let expected = try bytes(of: try #require(await painter.filterResult(of: filtered, source: source)))
    guard
      let result = await renderer.render(
        filtered, source: try texture(of: source, on: renderer.device), scale: scale)
    else { return nil }
    let actual = try bytes(of: result, on: renderer.device)
    try #require(actual.count == expected.count)
    largest = max(largest, zip(actual, expected).map { abs(Int($0) - Int($1)) }.max() ?? 0)
  }
  return largest
}

/// The style of a filter region of the square from 10 to 90, which is on the pixels at any whole scale.
private let region = #"filterUnits="userSpaceOnUse" x="10" y="10" width="80" height="80""#
/// Shapes to filter: a translucent green square and an opaque circle.
private let shapes =
  #"<rect x="20" y="20" width="40" height="30" fill="green" fill-opacity="0.6"/>"#
  + ##"<circle cx="60" cy="60" r="18" fill="#c06030"/>"##

/// A group of the shapes with a filter of the primitives, in a color space, and with the opacity.
private func filter(_ primitives: String, space: String = "linearRGB", opacity: String = "1") -> String {
  #"<filter id="f" "# + region + #" color-interpolation-filters=""# + space + #"">"# + primitives + "</filter>"
    + ##"<g filter="url(#f)" opacity=""## + opacity + #"">"# + shapes + "</g>"
}

@Suite("Running filters on the GPU", .enabled(if: renderer != nil))
struct MetalFilterRendererTests {
  /// Filters that the GPU runs with the same results as the CPU.
  private static let documents: [String] = [
    // Blurs with Gaussian kernels, three boxes, and in one direction.
    filter(#"<feGaussianBlur stdDeviation="1"/>"#),
    filter(#"<feGaussianBlur stdDeviation="2"/>"#, space: "sRGB"),
    filter(#"<feGaussianBlur stdDeviation="5"/>"#),
    filter(#"<feGaussianBlur stdDeviation="1 2"/>"#),
    filter(#"<feGaussianBlur stdDeviation="2 0"/>"#),
    filter(#"<feGaussianBlur stdDeviation="0"/>"#),
    filter(#"<feGaussianBlur stdDeviation="-1"/>"#),
    filter(#"<feGaussianBlur in="SourceAlpha" stdDeviation="1"/>"#),
    // A blur of part of the region, and the opacity of the element.
    filter(#"<feGaussianBlur stdDeviation="1" x="20" y="30" width="50" height="40"/>"#, opacity: "0.5"),
    // Offsets, also clipped by the region of the primitive before.
    filter(#"<feOffset dx="5" dy="-8"/>"#),
    filter(#"<feFlood flood-color="blue" x="0" y="0" width="60" height="60"/><feOffset dx="10" dy="10"/>"#),
    // Floods.
    filter(#"<feFlood flood-color="orange" flood-opacity="0.7" x="20" y="20" width="40" height="50"/>"#),
    filter(#"<feFlood flood-color="orange"/>"#, space: "sRGB", opacity: "0.3"),
    // Merges of the results, the source and its alpha.
    filter(
      #"<feGaussianBlur in="SourceAlpha" stdDeviation="2" result="b"/><feOffset dx="3" dy="3" result="o"/>"#
        + #"<feMerge><feMergeNode in="o"/><feMergeNode in="SourceGraphic"/></feMerge>"#),
    filter(
      #"<feFlood flood-color="gold" result="f"/>"#
        + #"<feMerge color-interpolation-filters="sRGB"><feMergeNode in="f"/><feMergeNode/></feMerge>"#),
    // Blends.
    filter(##"<feFlood flood-color="#3080ff" result="f"/><feBlend in="SourceGraphic" in2="f" mode="multiply"/>"##),
    filter(##"<feFlood flood-color="#3080ff" result="f"/><feBlend in="SourceGraphic" in2="f" mode="screen"/>"##),
    filter(##"<feFlood flood-color="#3080ff" result="f"/><feBlend in="f" in2="SourceGraphic" mode="darken"/>"##),
    filter(#"<feGaussianBlur stdDeviation="3" result="b"/><feBlend in="SourceGraphic" in2="b"/>"#, opacity: "0.6"),
  ]

  @Test("the GPU runs a filter as the CPU does", arguments: documents, [1.0, 3.0])
  func sameResults(content: String, scale: Double) async throws {
    let difference = try #require(await largestDifference(content, scale: scale))
    #expect(difference <= 2)
  }

  /// Filters that the GPU doesn't run.
  private static let unsupported: [String] = [
    // A blur that blurs a direction with three boxes, by a standard deviation different from the other.
    filter(#"<feGaussianBlur stdDeviation="1 10"/>"#),
    // A merge of part of the region, which the CPU scales its inputs into.
    filter(#"<feMerge x="20" y="20" width="40" height="40"><feMergeNode/></feMerge>"#),
    // A blend mode that Core Graphics computes differently from the specification.
    filter(##"<feFlood flood-color="#3080ff" result="f"/><feBlend in="SourceGraphic" in2="f" mode="color-dodge"/>"##),
    // An offset off the pixels.
    filter(#"<feOffset dx="0.25" dy="0"/>"#),
  ]

  @Test("the GPU doesn't run a filter whose results it can't make the same", arguments: unsupported)
  func unsupportedFilters(content: String) async throws {
    #expect(try await largestDifference(content, scale: 1) == nil)
  }
}
