import Accelerate
import CoreGraphics

protocol SVGFilterApplier {
  var x: SVGLength? { get }
  var y: SVGLength? { get }
  var width: SVGLength? { get }
  var height: SVGLength? { get }
  var result: String? { get }
  func apply(
    srcImage: CGImage, inImage: CGImage, clipRect: inout CGRect, filter: SVGFilterElement, frame: CGRect,
    effectRect: CGRect, opacity: CGFloat, cgContext: CGContext, context: SVGContext, results: [String: CGImage], isFirst: Bool
  ) async -> CGImage?
  func frame(filter: SVGFilterElement, frame: CGRect, context: SVGContext) -> CGRect
  func transform(filter: SVGFilterElement, frame: CGRect) -> CGAffineTransform
}

extension SVGFilterApplier {
  func frame(filter: SVGFilterElement, frame: CGRect, context: SVGContext) -> CGRect {
    let primitiveUnits = filter.primitiveUnits ?? .userSpaceOnUse
    let filterUnits = filter.filterUnits ?? .objectBoundingBox
    let x = x?.calculatedLength(frame: frame, context: context, mode: .width, unitType: primitiveUnits, isPosition: true) ?? filter.x?.calculatedLength(frame: frame, context: context, mode: .width, unitType: filterUnits, isPosition: true) ?? (frame.minX - 0.1 * frame.width)
    let y = y?.calculatedLength(frame: frame, context: context, mode: .height, unitType: primitiveUnits, isPosition: true) ?? filter.y?.calculatedLength(frame: frame, context: context, mode: .height, unitType: filterUnits, isPosition: true) ?? (frame.minY - 0.1 * frame.height)
    let width = width?.calculatedLength(frame: frame, context: context, mode: .width, unitType: primitiveUnits) ?? filter.width?.calculatedLength(frame: frame, context: context, mode: .width, unitType: filterUnits) ?? 1.2 * frame.width
    let height = height?.calculatedLength(frame: frame, context: context, mode: .height, unitType: primitiveUnits) ?? filter.height?.calculatedLength(frame: frame, context: context, mode: .height, unitType: filterUnits) ?? 1.2 * frame.height
    return CGRect(origin: CGPoint(x: x, y: y), size: CGSize(width: width, height: height))
  }

  func transform(filter _: SVGFilterElement, frame _: CGRect) -> CGAffineTransform {
    .identity
  }

  /// Points `destBuffer` at the input of the primitive.
  ///
  /// `destBuffer` shares its memory with `srcBuffer` or `inputBuffer`, except for the result of another
  /// primitive, for which the method allocates the memory.
  ///
  /// - Returns: The memory that the method allocates, if any. The caller frees it after it no longer uses
  ///   `destBuffer`, or an image that it makes from `destBuffer` without copying the pixels.
  func inputImageBuffer(
    input: SVGFilterInput?, format: inout vImage_CGImageFormat, results: [String: CGImage],
    srcBuffer: inout vImage_Buffer, inputBuffer: inout vImage_Buffer, destBuffer: inout vImage_Buffer
  ) -> UnsafeMutableRawPointer? {
    switch input {
    case .none:
      destBuffer = inputBuffer
    case .sourceGraphic:
      destBuffer = srcBuffer
    case .sourceAlpha:
      destBuffer = srcBuffer
      dropRGBColor(srcBuffer: &srcBuffer, destBuffer: &destBuffer)
    case .other(let srcName):
      if let image = results[srcName],
        let tbuffer = try? vImage_Buffer(cgImage: image, format: format)
      {
        destBuffer = tbuffer
        return tbuffer.data
      } else {
        destBuffer = inputBuffer
      }
    }
    return nil
  }

  private func dropRGBColor(srcBuffer: inout vImage_Buffer, destBuffer: inout vImage_Buffer) {
    let matrix: [Int16] = [
      0, 0, 0, 0,
      0, 0, 0, 0,
      0, 0, 0, 0,
      0, 0, 0, 1,
    ]

    vImageMatrixMultiply_ARGB8888(
      &srcBuffer,
      &destBuffer,
      matrix,
      1,
      nil,
      nil,
      vImage_Flags(kvImageNoFlags)
    )
    swap(&srcBuffer, &destBuffer)
  }
}
