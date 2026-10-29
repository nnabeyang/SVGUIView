import Metal
import SVGTestSuite
import Testing
import UIKit

@testable import SVGUIView

/// The SVG files of the test suite with filters.
private let filterFiles =
  SVGFile.all(in: "basic", "filters") + SVGFile.all(in: "1.1F2").filter { $0.name.hasPrefix("filters-") }

/// Whether the device has a GPU, without which the filters run on the CPU.
private let hasGPU = MTLCreateSystemDefaultDevice() != nil

/// Checks that the filters that playing views run on the GPU show what they show on the CPU.
///
/// The snapshot tests render still images, whose filters always run on the CPU, so these tests render the layers of
/// a view that plays the animations. Every element with a filter is painted into a layer of its own, as one whose
/// filter changes is, so that each filter that the GPU can run runs there.
@MainActor
@Suite("Running the filters of layers on the GPU", .enabled(if: hasGPU))
struct GPUFilterTests {
  /// The pixels of the layers of a view that shows a file at the time 0, and how many of them ran their filters on
  /// the GPU.
  private func layers(of file: SVGFile, onGPU: Bool) async throws -> (pixels: [UInt8], filteredOnGPU: Int) {
    let size = CGSize(width: 100, height: 100)
    let view = try #require(SVGUIView(contentsOf: file.url), "Couldn't read \(file.url.lastPathComponent)")
    view.frame = CGRect(origin: .zero, size: size)
    view.contentMode = .scaleAspectFit
    view.runsFiltersOnGPU = onGPU
    view.paintsFiltersIntoOwnLayers = true
    view.configuration = SVGUIViewConfiguration(timeoutDuration: .seconds(60), animation: .paused)
    view.layoutIfNeeded()
    view.layer.displayIfNeeded()
    while let task = view.renderingTask {
      await task.value
      if view.renderingTask == task { break }
    }
    let scale = UIScreen.main.scale
    let width = Int(size.width * scale)
    let height = Int(size.height * scale)
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    pixels.withUnsafeMutableBytes { buffer in
      guard
        let context = CGContext(
          data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
      else { return }
      context.concatenate(CGAffineTransform(scale, 0, 0, -scale, 0, size.height * scale))
      view.layer.render(in: context)
    }
    return (pixels, view.layersFilteredOnGPU)
  }

  @Test("the layers show with the filters on the GPU what they show with the filters on the CPU", arguments: filterFiles)
  func sameLayers(_ file: SVGFile) async throws {
    let gpu = try await layers(of: file, onGPU: true)
    let cpu = try await layers(of: file, onGPU: false)
    #expect(cpu.filteredOnGPU == 0)
    // The boxes of `MPSImageBox` round a few components one more than vImage.
    let largest = zip(gpu.pixels, cpu.pixels).map { abs(Int($0) - Int($1)) }.max() ?? 0
    #expect(largest <= 3, "The layers of \(file.name) differ by \(largest)")
  }

  @Test("a filter that the GPU can run runs on the GPU")
  func runsOnGPU() async throws {
    let file = SVGFile(
      url: TestSuite.bundle.bundleURL.appending(path: "w3c/basic/filters/feGaussianBlur/e-feGaussianBlur-001.svg"))
    #expect(try await layers(of: file, onGPU: true).filteredOnGPU == 1)
  }
}
