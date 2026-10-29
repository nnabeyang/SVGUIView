import CoreGraphics
import Foundation
import Metal
import MetalPerformanceShaders
import SVGCore
import SVGRenderCG
import Synchronization
import os

/// The signposts of rendering, as `SVGUIView` marks them.
private let signposter = OSSignposter(subsystem: "com.github.nnabeyang.SVGUIView", category: "Rendering")

/// Runs the primitives of filters on the GPU, with the same results as the filters on the CPU up to the rounding.
///
/// It takes the image of the element without its filter from `CGPainter.sourceImage(of:)`, and returns what
/// `CGPainter.filterResult(of:source:)` does, as textures of premultiplied BGRA pixels of the filter region. It does
/// the same steps as the CPU: each primitive draws into a cleared bitmap of the color space of
/// `color-interpolation-filters`, clipped to its subregion, with the opacity of the element, converting the color
/// spaces where the CPU does. The color conversions and the opacity are looked up in tables that Core Graphics and
/// vImage make, so that they round in the same way.
///
/// It doesn't run a filter region larger than the textures that every GPU can make, nor filters whose results it can't
/// make the same, for which it returns `nil`:
/// - A filter region or a subregion whose edges, or an offset whose distance, aren't on the pixels, which the CPU
///   resamples.
/// - A `feBlend` or a `feMerge` whose subregion isn't the filter region, which the CPU scales its inputs into.
/// - A blend mode other than the ones that Core Graphics computes as the specification does.
/// - A blur whose standard deviations differ, and that blurs a direction with three boxes.
package final class MetalFilterRenderer: Sendable {
  let device: MTLDevice
  private let queue: MTLCommandQueue
  private let drawImage: MTLComputePipelineState
  private let convertImage: MTLComputePipelineState
  private let dropColor: MTLComputePipelineState
  private let fillArea: MTLComputePipelineState
  private let blendImage: MTLComputePipelineState
  private let gaussianPass: MTLComputePipelineState
  /// The tables of the color operations made so far.
  private let tables = Mutex([ColorOperation: [UInt8]]())

  /// Makes the pipelines of the filters, or returns `nil` if there's no GPU or they can't be made.
  package init?(device: MTLDevice? = MTLCreateSystemDefaultDevice()) {
    guard let device, let queue = device.makeCommandQueue(),
      let library = try? device.makeLibrary(source: filterKernelSource, options: nil)
    else { return nil }
    func pipeline(_ name: String) -> MTLComputePipelineState? {
      library.makeFunction(name: name).flatMap { try? device.makeComputePipelineState(function: $0) }
    }
    guard let drawImage = pipeline("drawImage"), let convertImage = pipeline("convertImage"),
      let dropColor = pipeline("dropColor"), let fillArea = pipeline("fillArea"),
      let blendImage = pipeline("blendImage"), let gaussianPass = pipeline("gaussianPass")
    else { return nil }
    self.device = device
    self.queue = queue
    self.drawImage = drawImage
    self.convertImage = convertImage
    self.dropColor = dropColor
    self.fillArea = fillArea
    self.blendImage = blendImage
    self.gaussianPass = gaussianPass
  }

  /// The renderer of the process, made when it's first used, or `nil` if there's no GPU.
  ///
  /// Making it compiles the kernels, which the first frame that runs a filter on the GPU waits for.
  package static let shared: MetalFilterRenderer? = {
    let interval = signposter.beginInterval("Prepare GPU filters")
    defer { signposter.endInterval("Prepare GPU filters", interval) }
    return MetalFilterRenderer()
  }()

  /// Whether the GPU runs a filter at a scale with the same results as the CPU.
  package static func supports(_ filtered: FilteredNode, scale: CGFloat) -> Bool {
    FilterGeometry(filtered: filtered, scale: scale).isSupported
  }

  /// The result of the primitives of a filter on the image of the element, as a texture of the filter region in the
  /// color space of `color-interpolation-filters`, or `nil` if the filter can't be run on the GPU.
  ///
  /// - Parameters:
  ///   - source: The image of the element without its filter, in the color space of `color-interpolation`, of the
  ///     size of the filter region at the scale.
  ///   - scale: The scale of the screen.
  package func render(_ filtered: FilteredNode, source: MTLTexture, scale: CGFloat) async -> MTLTexture? {
    guard let buffer = queue.makeCommandBuffer() else { return nil }
    var run = FilterRun(renderer: self, filtered: filtered, scale: scale, buffer: buffer)
    guard let result = run.encode(source: source), await Self.run(buffer) else { return nil }
    return result
  }

  /// The result of a filter as `CGPainter.filterResult(of:source:)` makes it, with the element painted by the painter
  /// and the primitives run on the GPU, or `nil` if the filter can't be run on the GPU or the task is cancelled.
  ///
  /// The element is painted into memory that the GPU reads, and the result is read from memory that the GPU writes,
  /// so the pixels aren't copied on the CPU.
  package func filterImage(of filtered: FilteredNode, painter: CGPainter) async -> CGImage? {
    let scale = painter.scale
    let geometry = FilterGeometry(filtered: filtered, scale: scale)
    guard geometry.isSupported else { return nil }
    let width = geometry.width
    let height = geometry.height
    let interval = signposter.beginInterval("Filter on GPU", id: signposter.makeSignpostID(), "\(width) × \(height)")
    defer { signposter.endInterval("Filter on GPU", interval) }
    let bytesPerRow = width * 4
    let length = bytesPerRow * height
    let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
    guard let sourceBuffer = device.makeBuffer(length: length, options: .storageModeShared),
      let resultBuffer = device.makeBuffer(length: length, options: .storageModeShared),
      let graphics = CGContext(
        data: sourceBuffer.contents(), width: width, height: height, bitsPerComponent: 8, bytesPerRow: bytesPerRow,
        space: filtered.colorInterpolation.colorSpace, bitmapInfo: bitmapInfo)
    else { return nil }
    graphics.clear(CGRect(x: 0, y: 0, width: width, height: height))
    guard await painter.paintSource(of: filtered, into: graphics), !Task.isCancelled else { return nil }
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
    descriptor.usage = [.shaderRead, .shaderWrite]
    descriptor.storageMode = .private
    let size = MTLSize(width: width, height: height, depth: 1)
    guard let buffer = queue.makeCommandBuffer(), let source = device.makeTexture(descriptor: descriptor),
      let upload = buffer.makeBlitCommandEncoder()
    else { return nil }
    upload.copy(
      from: sourceBuffer, sourceOffset: 0, sourceBytesPerRow: bytesPerRow, sourceBytesPerImage: length,
      sourceSize: size, to: source, destinationSlice: 0, destinationLevel: 0, destinationOrigin: MTLOrigin())
    upload.endEncoding()
    var run = FilterRun(renderer: self, filtered: filtered, scale: scale, buffer: buffer)
    guard let result = run.encode(source: source), let download = buffer.makeBlitCommandEncoder() else { return nil }
    download.copy(
      from: result, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(), sourceSize: size, to: resultBuffer,
      destinationOffset: 0, destinationBytesPerRow: bytesPerRow, destinationBytesPerImage: length)
    download.endEncoding()
    guard await Self.run(buffer) else { return nil }
    // The image reads the memory of the buffer, which it keeps until it's released.
    let retained = Unmanaged.passRetained(resultBuffer as AnyObject).toOpaque()
    guard
      let provider = CGDataProvider(
        dataInfo: retained, data: resultBuffer.contents(), size: length,
        releaseData: { info, _, _ in info.map { Unmanaged<AnyObject>.fromOpaque($0).release() } })
    else {
      Unmanaged<AnyObject>.fromOpaque(retained).release()
      return nil
    }
    return CGImage(
      width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: bytesPerRow,
      space: filtered.colorInterpolationFilters.colorSpace, bitmapInfo: CGBitmapInfo(rawValue: bitmapInfo),
      provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
  }

  /// Commits a command buffer, and returns whether it completed, which it doesn't while the app is in the background.
  private static func run(_ buffer: MTLCommandBuffer) async -> Bool {
    await withCheckedContinuation { continuation in
      buffer.addCompletedHandler { _ in continuation.resume() }
      buffer.commit()
    }
    return buffer.status == .completed
  }

  /// The table of a color operation, made once.
  fileprivate func table(_ operation: ColorOperation) -> [UInt8]? {
    if let table = tables.withLock({ $0[operation] }) { return table }
    guard let table = operation.table else { return nil }
    tables.withLock { $0[operation] = table }
    return table
  }

  fileprivate func pipeline(_ kernel: FilterKernel) -> MTLComputePipelineState {
    switch kernel {
    case .drawImage: drawImage
    case .convertImage: convertImage
    case .dropColor: dropColor
    case .fillArea: fillArea
    case .blendImage: blendImage
    case .gaussianPass: gaussianPass
    }
  }
}

private enum FilterKernel {
  case drawImage, convertImage, dropColor, fillArea, blendImage, gaussianPass
}

/// The blend modes that the GPU computes, in the order of `BlendMode` in the kernels: the ones that Core Graphics
/// computes as the specification does.
private let blendModes: [CGBlendMode] = [
  .normal, .multiply, .screen, .overlay, .darken, .lighten, .hardLight, .difference, .exclusion,
]

/// The area that a kernel draws into, as `DrawArea` in the kernels.
private struct DrawArea {
  var origin: SIMD2<Int32>
  var end: SIMD2<Int32>
  var offset: SIMD2<Int32> = .zero
}

/// The weights of a Gaussian kernel along an axis, as `GaussianPass` in the kernels.
private struct GaussianPass {
  var radius: Int32
  var step: SIMD2<Int32>
  var extendsEdges: UInt32
}

/// An image of a filter on the GPU, and the color space that its pixels are in.
private struct FilterImage {
  let texture: MTLTexture
  let space: SVGColorInterpolation
}

/// Where the pixels of a filter are, and whether the GPU runs it.
private struct FilterGeometry {
  /// The largest width and height of the textures, which every GPU and the simulator can make.
  static let maximumSize = 8192

  let filtered: FilteredNode
  let scale: CGFloat

  /// The pixels of the filter bitmap of the CPU, whose width and height are rounded up to whole pixels.
  var width: Int { CGContext.bitmapLayout(size: filtered.effectRect.size, scale: scale)?.width ?? 0 }
  var height: Int { CGContext.bitmapLayout(size: filtered.effectRect.size, scale: scale)?.height ?? 0 }

  func isOnPixels(_ value: CGFloat) -> Bool {
    abs(value - value.rounded()) < 1e-6
  }

  /// The pixels of a rectangle of the filter region, from the top left, or `nil` if its edges aren't on the pixels.
  func area(of rect: CGRect) -> DrawArea? {
    let effectRect = filtered.effectRect
    let left = (rect.minX - effectRect.minX) * scale
    let right = (rect.maxX - effectRect.minX) * scale
    // The bitmaps of the CPU have their origin at the bottom left.
    let bottom = (rect.minY - effectRect.minY) * scale
    let top = (rect.maxY - effectRect.minY) * scale
    guard [left, right, bottom, top].allSatisfy(isOnPixels) else { return nil }
    func clamped(_ value: CGFloat) -> Int32 {
      Int32(max(-1, min(CGFloat(Int32.max / 2), value.rounded())))
    }
    return DrawArea(
      origin: SIMD2(clamped(left), clamped(CGFloat(height) - top)),
      end: SIMD2(clamped(right), clamped(CGFloat(height) - bottom)))
  }

  var fullArea: DrawArea {
    DrawArea(origin: .zero, end: SIMD2(Int32(width), Int32(height)))
  }

  /// Whether the GPU runs the filter with the same results as the CPU, as `FilterRun` checks while it encodes it.
  var isSupported: Bool {
    let effectRect = filtered.effectRect
    guard !filtered.primitives.isEmpty, (1...Self.maximumSize).contains(width),
      (1...Self.maximumSize).contains(height)
    else { return false }
    var clipRect = effectRect
    for step in filtered.primitives {
      let subregion = step.subregion
      switch step.primitive {
      case .blend(let mode, _, _):
        guard blendModes.contains(mode), area(of: subregion) != nil else { return false }
        clipRect = subregion
      case .flood(let color):
        guard area(of: subregion) != nil, color.count == 4 else { return false }
        clipRect = subregion
      case .gaussianBlur(let blur):
        guard area(of: subregion) != nil else { return false }
        if case .hetero(let x, let y) = blur.standardDeviation, x >= 0, y >= 0, x != y {
          guard GaussianBlurPrimitive.isGaussian(x * scale), GaussianBlurPrimitive.isGaussian(y * scale) else {
            return false
          }
        }
        clipRect = subregion
      case .merge:
        guard area(of: subregion) != nil else { return false }
        clipRect = subregion
      case .offset(let translation):
        clipRect = clipRect.intersection(subregion)
        guard isOnPixels(translation.tx * scale), isOnPixels(translation.ty * scale),
          clipRect.isNull || area(of: clipRect) != nil
        else { return false }
      }
    }
    return true
  }
}

/// The buffers of the tables of the color operations of a run of a filter.
private final class TableBuffers {
  var buffers = [ColorOperation: MTLBuffer]()
}

/// The encoding of the primitives of a filter into a command buffer.
private struct FilterRun {
  let renderer: MetalFilterRenderer
  let filtered: FilteredNode
  let scale: CGFloat
  let buffer: MTLCommandBuffer
  /// The results of the primitives with names.
  var results = [String: FilterImage]()
  /// The rectangle that the last primitive clipped to, which `feOffset` clips to as well.
  var clipRect: CGRect
  /// The tables of the color operations that the run uses, in buffers that the kernels read, which are too large to
  /// pass as bytes.
  let tableBuffers = TableBuffers()

  init(renderer: MetalFilterRenderer, filtered: FilteredNode, scale: CGFloat, buffer: MTLCommandBuffer) {
    self.renderer = renderer
    self.filtered = filtered
    self.scale = scale
    self.buffer = buffer
    clipRect = filtered.effectRect
  }

  private var geometry: FilterGeometry { FilterGeometry(filtered: filtered, scale: scale) }
  var width: Int { geometry.width }
  var height: Int { geometry.height }
  /// The color space of the bitmap that the primitives draw into.
  var space: SVGColorInterpolation { filtered.colorInterpolationFilters }

  /// Encodes the primitives on the source, and returns the texture of the result, or `nil` if the filter can't be run
  /// on the GPU.
  mutating func encode(source: MTLTexture) -> MTLTexture? {
    guard geometry.isSupported, source.width == width, source.height == height else { return nil }
    let sourceImage = FilterImage(texture: source, space: filtered.colorInterpolation)
    var input = sourceImage
    for step in filtered.primitives {
      guard let result = apply(step, source: sourceImage, input: input) else { return nil }
      if let name = step.result {
        results[name] = result
      }
      input = result
    }
    return input.texture
  }

  private func isOnPixels(_ value: CGFloat) -> Bool { geometry.isOnPixels(value) }
  private func area(of rect: CGRect) -> DrawArea? { geometry.area(of: rect) }
  private var fullArea: DrawArea { geometry.fullArea }

  private mutating func apply(_ step: FilterStep, source: FilterImage, input: FilterImage) -> FilterImage? {
    let subregion = step.subregion
    switch step.primitive {
    case .blend(let mode, let input1, let input2):
      guard let modeIndex = blendModes.firstIndex(of: mode), let area = area(of: subregion) else { return nil }
      clipRect = subregion
      // The inputs are in the color space of the source.
      var source = source
      guard let converted = convert(input, to: source.space),
        let image1 = self.input(input1, source: &source, input: converted, space: source.space),
        let image2 = self.input(input2, source: &source, input: converted, space: source.space),
        let backdrop = draw(image2, in: fullArea),
        let blended = blend(image1, over: backdrop, mode: UInt32(modeIndex))
      else { return nil }
      return clipped(blended, to: area)
    case .flood(let color):
      guard let area = area(of: subregion), color.count == 4,
        let table = renderer.table(.draw(from: source.space, to: space, alpha: filtered.opacity))
      else { return nil }
      clipRect = subregion
      // The color is in the order of the pixels of the bitmap, and the kernels read the components as RGBA.
      func lookUp(_ component: UInt8) -> UInt32 {
        UInt32(table[(Int(color[3]) * 256 + Int(component)) * 2])
      }
      let alpha = UInt32(table[(Int(color[3]) * 256 + Int(color[3])) * 2 + 1])
      return fill(SIMD4(lookUp(color[2]), lookUp(color[1]), lookUp(color[0]), alpha), in: area)
    case .gaussianBlur(let blur):
      guard let area = area(of: subregion), let blurred = gaussianBlur(blur, step: step, source: source, input: input)
      else { return nil }
      clipRect = subregion
      return draw(blurred, in: area)
    case .merge(let inputs, let colorInterpolationFilters):
      guard let area = area(of: subregion) else { return nil }
      clipRect = subregion
      let mergeSpace = colorInterpolationFilters ?? (step.isFirst ? source.space : input.space)
      guard var source = convert(source, to: mergeSpace), let converted = convert(input, to: mergeSpace) else {
        return nil
      }
      var result: FilterImage?
      for mergeInput in inputs {
        guard let image = self.input(mergeInput, source: &source, input: converted, space: mergeSpace) else {
          return nil
        }
        if let under = result {
          guard let blended = blend(image, over: under, mode: 0) else { return nil }
          result = blended
        } else {
          guard let drawn = draw(image, in: fullArea) else { return nil }
          result = drawn
        }
      }
      guard let result else { return fill(.zero, in: fullArea) }
      return clipped(result, to: area)
    case .offset(let translation):
      let dx = translation.tx * scale
      let dy = translation.ty * scale
      clipRect = clipRect.intersection(subregion)
      // A clip to nothing draws nothing.
      let clip = clipRect.isNull ? DrawArea(origin: .zero, end: .zero) : area(of: clipRect)
      guard isOnPixels(dx), isOnPixels(dy), var area = clip, let converted = convert(input, to: source.space) else {
        return nil
      }
      // The bitmaps of the CPU have their origin at the bottom left, so a positive distance up is a smaller row.
      area.offset = SIMD2(Int32(dx.rounded()), Int32(-dy.rounded()))
      return draw(converted, in: area)
    }
  }

  /// The input of a primitive, in a color space, as `inputImageBuffer` makes it on the CPU.
  ///
  /// As on the CPU, `SourceAlpha` drops the colors of `source`, so a later `SourceGraphic` of the same primitive has
  /// no colors either.
  private func input(
    _ input: SVGFilterInput?, source: inout FilterImage, input converted: FilterImage, space: SVGColorInterpolation
  ) -> FilterImage? {
    switch input {
    case .none:
      return converted
    case .sourceGraphic:
      return source
    case .sourceAlpha:
      guard let alpha = dropColor(source) else { return nil }
      source = alpha
      return alpha
    case .other(let name):
      guard let result = results[name] else { return converted }
      return convert(result, to: space)
    }
  }

  // MARK: Blur

  /// The blurred input of a blur, in the color space that it's blurred in, before it's drawn.
  private func gaussianBlur(
    _ blur: GaussianBlurPrimitive, step: FilterStep, source: FilterImage, input: FilterImage
  ) -> FilterImage? {
    // The color space, as on the CPU, which reinterprets the pixels of the source and the input in it.
    let blurSpace: SVGColorInterpolation
    switch blur.input {
    case .none:
      blurSpace =
        step.isFirst
        ? (blur.colorInterpolationFilters ?? blur.filterColorInterpolationFilters ?? .sRGB)
        : (blur.colorInterpolationFilters ?? blur.filterColorInterpolationFilters ?? input.space)
    case .sourceAlpha, .sourceGraphic:
      blurSpace = blur.colorInterpolationFilters ?? source.space
    case .other(let name):
      blurSpace = results[name]?.space ?? blur.colorInterpolationFilters ?? (step.isFirst ? source.space : input.space)
    }
    var source = FilterImage(texture: source.texture, space: blurSpace)
    let reinterpreted = FilterImage(texture: input.texture, space: blurSpace)
    guard let selected = self.input(blur.input, source: &source, input: reinterpreted, space: blurSpace) else {
      return nil
    }
    switch blur.standardDeviation {
    case .hetero(let x, let y) where x < 0 || y < 0:
      // The CPU leaves the input of the primitive, rather than the one that it takes.
      return reinterpreted
    case .iso(let x) where x < 0:
      return selected
    case .hetero(let x, let y) where x != y:
      let deviationX = x * scale
      let deviationY = y * scale
      guard GaussianBlurPrimitive.isGaussian(deviationX), GaussianBlurPrimitive.isGaussian(deviationY) else {
        return nil
      }
      return gaussian(
        selected, kernelX: GaussianBlurPrimitive.gaussianKernel(deviation: deviationX),
        kernelY: GaussianBlurPrimitive.gaussianKernel(deviation: deviationY), extendsEdges: false)
    case .hetero(let deviation, _), .iso(let deviation):
      let pixels = deviation * scale
      guard GaussianBlurPrimitive.isGaussian(pixels) else {
        let size = Int(GaussianBlurPrimitive.clampedToKernelSize(value: pixels, scale: scale) | 1)
        return boxes(selected, size: size)
      }
      let kernel = GaussianBlurPrimitive.gaussianKernel(deviation: pixels)
      return gaussian(selected, kernelX: kernel, kernelY: kernel, extendsEdges: true)
    }
  }

  private func gaussian(_ image: FilterImage, kernelX: [Float], kernelY: [Float], extendsEdges: Bool) -> FilterImage? {
    guard let floats = makeTexture(format: .rgba32Float), let output = makeTexture() else { return nil }
    func pass(_ kernel: [Float], from: MTLTexture, to: MTLTexture, step: SIMD2<Int32>, rounds: Bool) -> Bool {
      var pass = GaussianPass(radius: Int32(kernel.count / 2), step: step, extendsEdges: extendsEdges ? 1 : 0)
      var rounds: UInt32 = rounds ? 1 : 0
      return dispatch(.gaussianPass, textures: [from, to]) { encoder in
        encoder.setBytes(kernel, length: kernel.count * MemoryLayout<Float>.stride, index: 0)
        encoder.setBytes(&pass, length: MemoryLayout<GaussianPass>.stride, index: 1)
        encoder.setBytes(&rounds, length: MemoryLayout<UInt32>.stride, index: 2)
      }
    }
    guard pass(kernelX, from: image.texture, to: floats, step: SIMD2(1, 0), rounds: false),
      pass(kernelY, from: floats, to: output, step: SIMD2(0, 1), rounds: true)
    else { return nil }
    return FilterImage(texture: output, space: image.space)
  }

  /// Three box blurs of a size in both directions, extending the pixels on the edges, as vImage blurs them.
  private func boxes(_ image: FilterImage, size: Int) -> FilterImage? {
    guard let first = makeTexture(), let second = makeTexture() else { return nil }
    let box = MPSImageBox(device: renderer.device, kernelWidth: size, kernelHeight: size)
    box.edgeMode = .clamp
    box.encode(commandBuffer: buffer, sourceTexture: image.texture, destinationTexture: first)
    box.encode(commandBuffer: buffer, sourceTexture: first, destinationTexture: second)
    box.encode(commandBuffer: buffer, sourceTexture: second, destinationTexture: first)
    return FilterImage(texture: first, space: image.space)
  }

  // MARK: Kernels

  /// The buffer of the table of a color operation, made once for the run.
  private func tableBuffer(_ operation: ColorOperation) -> MTLBuffer? {
    if let buffer = tableBuffers.buffers[operation] { return buffer }
    guard let table = renderer.table(operation),
      let buffer = renderer.device.makeBuffer(bytes: table, length: table.count, options: .storageModeShared)
    else { return nil }
    tableBuffers.buffers[operation] = buffer
    return buffer
  }

  /// An image converted into a color space, as vImage converts it.
  private func convert(_ image: FilterImage, to space: SVGColorInterpolation) -> FilterImage? {
    guard image.space != space else { return image }
    guard let table = tableBuffer(.convert(from: image.space, to: space)), let output = makeTexture(),
      dispatch(.convertImage, textures: [image.texture, output], body: { $0.setBuffer(table, offset: 0, index: 0) })
    else { return nil }
    return FilterImage(texture: output, space: space)
  }

  /// An image drawn with the opacity into the area of a cleared bitmap of the filter.
  private func draw(_ image: FilterImage, in area: DrawArea) -> FilterImage? {
    guard let table = tableBuffer(.draw(from: image.space, to: space, alpha: filtered.opacity)),
      let output = makeTexture()
    else { return nil }
    var area = area
    guard
      dispatch(
        .drawImage, textures: [image.texture, output],
        body: { encoder in
          encoder.setBuffer(table, offset: 0, index: 0)
          encoder.setBytes(&area, length: MemoryLayout<DrawArea>.stride, index: 1)
        })
    else { return nil }
    return FilterImage(texture: output, space: space)
  }

  /// An image with its pixels outside an area cleared and the others kept, as the clip of the CPU leaves them.
  private func clipped(_ image: FilterImage, to area: DrawArea) -> FilterImage? {
    if area.origin == fullArea.origin, area.end == fullArea.end { return image }
    guard let table = tableBuffer(.draw(from: image.space, to: image.space, alpha: 1)),
      let output = makeTexture()
    else { return nil }
    var area = area
    guard
      dispatch(
        .drawImage, textures: [image.texture, output],
        body: { encoder in
          encoder.setBuffer(table, offset: 0, index: 0)
          encoder.setBytes(&area, length: MemoryLayout<DrawArea>.stride, index: 1)
        })
    else { return nil }
    return FilterImage(texture: output, space: image.space)
  }

  /// An image drawn with the opacity and a blend mode over an image of the filter.
  private func blend(_ image: FilterImage, over backdrop: FilterImage, mode: UInt32) -> FilterImage? {
    guard let table = tableBuffer(.draw(from: image.space, to: space, alpha: filtered.opacity)),
      let output = makeTexture()
    else { return nil }
    var mode = mode
    guard
      dispatch(
        .blendImage, textures: [image.texture, backdrop.texture, output],
        body: { encoder in
          encoder.setBuffer(table, offset: 0, index: 0)
          encoder.setBytes(&mode, length: MemoryLayout<UInt32>.stride, index: 1)
        })
    else { return nil }
    return FilterImage(texture: output, space: space)
  }

  private func dropColor(_ image: FilterImage) -> FilterImage? {
    guard let output = makeTexture(), dispatch(.dropColor, textures: [image.texture, output], body: { _ in }) else {
      return nil
    }
    return FilterImage(texture: output, space: image.space)
  }

  /// A cleared bitmap of the filter with a color in an area.
  private func fill(_ color: SIMD4<UInt32>, in area: DrawArea) -> FilterImage? {
    guard let output = makeTexture() else { return nil }
    var color = color
    var area = area
    guard
      dispatch(
        .fillArea, textures: [output],
        body: { encoder in
          encoder.setBytes(&color, length: MemoryLayout<SIMD4<UInt32>>.stride, index: 0)
          encoder.setBytes(&area, length: MemoryLayout<DrawArea>.stride, index: 1)
        })
    else { return nil }
    return FilterImage(texture: output, space: space)
  }

  private func makeTexture(format: MTLPixelFormat = .bgra8Unorm) -> MTLTexture? {
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: format, width: width, height: height, mipmapped: false)
    descriptor.usage = [.shaderRead, .shaderWrite]
    descriptor.storageMode = .private
    return renderer.device.makeTexture(descriptor: descriptor)
  }

  /// Encodes a kernel over the pixels of the filter region, with the textures at their indices.
  private func dispatch(
    _ kernel: FilterKernel, textures: [MTLTexture], body: (MTLComputeCommandEncoder) -> Void
  ) -> Bool {
    guard let encoder = buffer.makeComputeCommandEncoder() else { return false }
    encoder.setComputePipelineState(renderer.pipeline(kernel))
    for (index, texture) in textures.enumerated() {
      encoder.setTexture(texture, index: index)
    }
    body(encoder)
    let threads = MTLSize(width: 16, height: 16, depth: 1)
    encoder.dispatchThreadgroups(
      MTLSize(width: (width + 15) / 16, height: (height + 15) / 16, depth: 1), threadsPerThreadgroup: threads)
    encoder.endEncoding()
    return true
  }
}
