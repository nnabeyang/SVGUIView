import Accelerate
import CoreGraphics
import Foundation
import SVGCore

extension CGPainter {
  /// Moves the pixels of the first input of a `feDisplacementMap` by the components of the second, the map, and
  /// draws the result clipped to the subregion into `cgContext`, or returns `nil` if its bitmaps can't be made or the
  /// task is cancelled.
  ///
  /// The map is in the color space of the primitive, and its components are taken without their alpha
  /// premultiplied. The first input stays in the color space of the filter, as only the map is converted. Each pixel
  /// takes the pixel of the input nearest to it moved by the scale in pixels times the component minus 0.5, as in
  /// resvg, or transparent black outside the input.
  func displacementMap(
    scale: CGSize, x: SVGChannelSelector, y: SVGChannelSelector, input: SVGFilterInput?, input2: SVGFilterInput?,
    colorSpace: SVGColorInterpolation, srcImage: CGImage, inImage: CGImage, subregion: CGRect, bitmapRect: CGRect,
    cgContext: CGContext, results: [String: CGImage]
  ) -> CGImage? {
    let bitmapInfo = CGBitmapInfo(
      rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
    guard let filterSpace = cgContext.colorSpace,
      var imageFormat = vImage_CGImageFormat(
        bitsPerComponent: 8, bitsPerPixel: 32, colorSpace: filterSpace, bitmapInfo: bitmapInfo),
      var mapFormat = vImage_CGImageFormat(
        bitsPerComponent: 8, bitsPerPixel: 32, colorSpace: colorSpace.colorSpace, bitmapInfo: bitmapInfo),
      let image = selectedImage(input, format: &imageFormat, srcImage: srcImage, inImage: inImage, results: results),
      let map = selectedImage(input2, format: &mapFormat, srcImage: srcImage, inImage: inImage, results: results),
      let source = try? vImage_Buffer(cgImage: image, format: imageFormat),
      let mapBuffer = try? vImage_Buffer(cgImage: map, format: mapFormat),
      let destination = try? vImage_Buffer(width: image.width, height: image.height, bitsPerPixel: 32)
    else { return nil }
    defer {
      source.free()
      mapBuffer.free()
      destination.free()
    }
    let width = Int(source.width)
    let height = Int(source.height)
    guard Int(mapBuffer.width) == width, Int(mapBuffer.height) == height else { return nil }
    memset(destination.data, 0, destination.rowBytes * height)
    // The displacements in pixels. The rows of the bitmaps go down from the top, and y in the user space goes up from
    // the bottom of the bitmap, so the rows move against y.
    let scaleX = Double(scale.width * self.scale)
    let scaleY = -Double(scale.height * self.scale)
    // The offsets of the components in the pixels, which are blue, green, red and alpha in memory.
    func offset(_ channel: SVGChannelSelector) -> Int {
      switch channel {
      case .blue: 0
      case .green: 1
      case .red: 2
      case .alpha: 3
      }
    }
    let xOffset = offset(x)
    let yOffset = offset(y)
    for row in 0..<height {
      guard !Task.isCancelled else { return nil }
      let mapRow = mapBuffer.data.advanced(by: row * mapBuffer.rowBytes).assumingMemoryBound(to: UInt8.self)
      let destinationRow = destination.data.advanced(by: row * destination.rowBytes).assumingMemoryBound(
        to: UInt32.self)
      for column in 0..<width {
        let pixel = mapRow.advanced(by: column * 4)
        let alpha = Double(pixel[3])
        // The component without its alpha premultiplied, from 0 to 1, where a transparent pixel has components of 0.
        func component(_ offset: Int) -> Double {
          guard alpha > 0 else { return 0 }
          return offset == 3 ? alpha / 255 : min(Double(pixel[offset]) / alpha, 1)
        }
        let sourceColumn = (Double(column) + scaleX * (component(xOffset) - 0.5)).rounded()
        let sourceRow = (Double(row) + scaleY * (component(yOffset) - 0.5)).rounded()
        guard sourceColumn >= 0, sourceColumn < Double(width), sourceRow >= 0, sourceRow < Double(height) else {
          continue
        }
        destinationRow[column] =
          source.data.advanced(by: Int(sourceRow) * source.rowBytes)
          .assumingMemoryBound(to: UInt32.self)[Int(sourceColumn)]
      }
    }
    guard let displaced = try? destination.createCGImage(format: imageFormat) else { return nil }
    cgContext.clip(to: subregion)
    cgContext.draw(displaced, in: bitmapRect)
    return cgContext.makeImage()
  }
}
