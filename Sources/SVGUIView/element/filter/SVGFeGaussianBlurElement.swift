import Accelerate
import UIKit

enum StdDeviation: Equatable {
    case iso(SVGLength)
    case hetero(x: SVGLength, y: SVGLength)
    init?(description: String) {
        var data = description
        let stdDeviation = data.withUTF8 {
            let bytes = BufferView(unsafeBufferPointer: $0)!
            var scanner = SVGAttributeScanner(bytes: bytes)
            return scanner.scanStdDeviation()
        }
        guard let stdDeviation = stdDeviation else {
            return nil
        }
        self = stdDeviation
    }
}

extension StdDeviation: Encodable {
    private enum CodingKeys: String, CodingKey {
        case x
        case y
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Self.CodingKeys.self)
        switch self {
        case let .iso(x):
            try container.encode(x, forKey: .x)
        case let .hetero(x, y):
            try container.encode(x, forKey: .x)
            try container.encode(y, forKey: .y)
        }
    }
}

extension StdDeviation {
    static let zero: StdDeviation = .hetero(x: SVGLength(value: 0, unit: .number), y: SVGLength(value: 0, unit: .number))
}

enum SVGFilterInput {
    case sourceGraphic
    case sourceAlpha
    case other(String)

    init?(rawValue: String) {
        guard !rawValue.isEmpty else { return nil }
        switch rawValue {
        case "SourceGraphic":
            self = .sourceGraphic
        case "SourceAlpha":
            self = .sourceAlpha
        default:
            self = .other(rawValue)
        }
    }
}

struct SVGFeGaussianBlurElement: SVGElement, SVGFilterApplier {
    private static let maxKernelSize: UInt32 = 100
    var type: SVGElementName {
        .feGaussianBlur
    }

    let x: SVGLength?
    let y: SVGLength?
    let width: SVGLength?
    let height: SVGLength?

    let result: String?

    let input: SVGFilterInput?

    let colorInterpolationFilters: SVGColorInterpolation?

    func draw(_: SVGContext, index _: Int, depth _: Int, mode _: DrawMode) {
        fatalError()
    }

    func style(with _: CSSStyle, at _: Int) -> any SVGElement {
        self
    }

    let stdDeviation: StdDeviation?
    init(attributes: [String: String]) {
        x = SVGLength(attributes["x"])
        y = SVGLength(attributes["y"])
        width = SVGLength(attributes["width"])
        height = SVGLength(attributes["height"])

        result = attributes["result"]

        stdDeviation = StdDeviation(description: attributes["stdDeviation", default: ""])
        input = SVGFilterInput(rawValue: attributes["in", default: ""])

        colorInterpolationFilters = SVGColorInterpolation(rawValue: attributes["color-interpolation-filters", default: ""])
    }

    static func clampedToKernelSize(value: CGFloat) -> UInt32 {
        min(Self.maxKernelSize, UInt32(max(floor(value * 3.0 * sqrt(2 * .pi) as CGFloat / 4 + 0.5) as CGFloat, 2 * UIScreen.main.scale)))
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

    private func colorSpace(colorInterpolation: SVGColorInterpolation) -> CGColorSpace {
        switch colorInterpolation {
        case .sRGB:
            return CGColorSpace(name: CGColorSpace.sRGB)!
        case .linearRGB:
            return CGColorSpace(name: CGColorSpace.linearSRGB)!
        }
    }

    func apply(srcImage: CGImage, inImage: CGImage, clipRect: inout CGRect,
               filter: SVGFilterElement, frame: CGRect, effectRect: CGRect, opacity: CGFloat, cgContext: CGContext, context: SVGContext, results: [String: CGImage], isFirst: Bool) -> CGImage?
    {
        let colorSpace: CGColorSpace
        switch input {
        case .none:
            if isFirst {
                colorSpace = self.colorSpace(colorInterpolation: colorInterpolationFilters ?? filter.colorInterpolationFilters ?? .sRGB)
            } else {
                colorSpace = (colorInterpolationFilters ?? filter.colorInterpolationFilters).map { self.colorSpace(colorInterpolation: $0) } ?? inImage.colorSpace!
            }
        case .sourceAlpha, .sourceGraphic:
            colorSpace = colorInterpolationFilters.map { self.colorSpace(colorInterpolation: $0) } ?? srcImage.colorSpace!
        case let .other(srcName):
            if let image = results[srcName] {
                colorSpace = image.colorSpace!
            } else {
                colorSpace = colorInterpolationFilters.map { self.colorSpace(colorInterpolation: $0) } ?? (isFirst ? srcImage.colorSpace! : inImage.colorSpace!)
            }
        }
        guard var format = vImage_CGImageFormat(bitsPerComponent: srcImage.bitsPerComponent,
                                                bitsPerPixel: srcImage.bitsPerPixel,
                                                colorSpace: colorSpace,
                                                bitmapInfo: srcImage.bitmapInfo) else { return nil }
        guard var srcBuffer = try? vImage_Buffer(cgImage: srcImage.copy(colorSpace: colorSpace)!, format: format) else { return nil }
        guard var inputBuffer = try? vImage_Buffer(cgImage: inImage.copy(colorSpace: colorSpace)!, format: format) else { return nil }

        let data = malloc(inputBuffer.rowBytes * Int(inputBuffer.height))
        var destBuffer = vImage_Buffer(data: data, height: inputBuffer.height, width: inputBuffer.width, rowBytes: inputBuffer.rowBytes)
        defer {
            free(data)
        }
        let stdDeviation = stdDeviation ?? .zero
        let unitType = filter.primitiveUnits ?? .userSpaceOnUse
        var buffer = vImage_Buffer(data: data, height: inputBuffer.height, width: inputBuffer.width, rowBytes: inputBuffer.rowBytes)
        inputImageBuffer(input: input, format: &format, results: results, srcBuffer: &srcBuffer, inputBuffer: &inputBuffer, destBuffer: &buffer)
        switch stdDeviation {
        case let .hetero(x, y):
            let x = x.calculatedLength(frame: frame, context: context, mode: .width, unitType: unitType)
            let y = y.calculatedLength(frame: frame, context: context, mode: .height, unitType: unitType)
            guard x >= 0, y >= 0 else {
                swap(&inputBuffer, &destBuffer)
                break
            }
            if x != y {
                let kernelSizeX = Self.clampedToKernelSize(value: x * UIScreen.main.scale)
                let kernelSizeY = Self.clampedToKernelSize(value: y * UIScreen.main.scale)
                applyUnaccelerated(srcBuffer: &buffer, destBuffer: &destBuffer,
                                   kernelSizeX: kernelSizeX, kernelSizeY: kernelSizeY, context: context)
            } else {
                let kernelSize = Self.clampedToKernelSize(value: x * UIScreen.main.scale) | 1
                applyAccelerated(srcBuffer: &buffer, destBuffer: &destBuffer, kernelSize: kernelSize)
            }
        case let .iso(x):
            let x = x.calculatedLength(frame: frame, context: context, mode: .other, unitType: unitType)
            guard x >= 0 else {
                swap(&buffer, &destBuffer)
                break
            }
            let kernelSize = Self.clampedToKernelSize(value: x * UIScreen.main.scale) | 1
            applyAccelerated(srcBuffer: &buffer, destBuffer: &destBuffer, kernelSize: kernelSize)
        }
        guard let image = vImageCreateCGImageFromBuffer(&destBuffer,
                                                        &format,
                                                        { _, _ in },
                                                        nil,
                                                        vImage_Flags(kvImageNoAllocate),
                                                        nil)?.takeRetainedValue()
        else {
            return nil
        }
        let rect = self.frame(filter: filter, frame: frame, context: context)
        clipRect = rect
        cgContext.clip(to: rect)
        let transform = transform(filter: filter, frame: frame)
        cgContext.concatenate(transform)
        cgContext.setAlpha(opacity)
        cgContext.draw(image, in: effectRect)
        return cgContext.makeImage()
    }

    func applyAccelerated(srcBuffer: inout vImage_Buffer, destBuffer: inout vImage_Buffer, kernelSize: UInt32) {
        let tmpBufferSize = vImageBoxConvolve_ARGB8888(&srcBuffer,
                                                       &destBuffer,
                                                       nil,
                                                       0,
                                                       0,
                                                       kernelSize,
                                                       kernelSize,
                                                       nil,
                                                       vImage_Flags(kvImageEdgeExtend | kvImageGetTempBufferSize))
        let tmpBuffer = malloc(tmpBufferSize)
        vImageBoxConvolve_ARGB8888(&srcBuffer,
                                   &destBuffer,
                                   tmpBuffer,
                                   0,
                                   0,
                                   kernelSize,
                                   kernelSize,
                                   nil,
                                   vImage_Flags(kvImageEdgeExtend))
        vImageBoxConvolve_ARGB8888(&destBuffer,
                                   &srcBuffer,
                                   tmpBuffer,
                                   0,
                                   0,
                                   kernelSize,
                                   kernelSize,
                                   nil,
                                   vImage_Flags(kvImageEdgeExtend))
        vImageBoxConvolve_ARGB8888(&srcBuffer,
                                   &destBuffer,
                                   tmpBuffer,
                                   0,
                                   0,
                                   kernelSize,
                                   kernelSize,
                                   nil,
                                   vImage_Flags(kvImageEdgeExtend))
        free(tmpBuffer)
    }

    func applyUnaccelerated(srcBuffer: inout vImage_Buffer, destBuffer: inout vImage_Buffer, kernelSizeX: UInt32, kernelSizeY: UInt32, context _: SVGContext) {
        var dxLeft = 0
        var dxRight = 0
        var dyLeft = 0
        var dyRight = 0
        var kernelSizeX = UInt(kernelSizeX)
        var kernelSizeY = UInt(kernelSizeY)
        let width = Int(srcBuffer.width)
        let height = Int(srcBuffer.height)
        let stride = srcBuffer.rowBytes
        var i = 0
        while i < 3 {
            if kernelSizeX > 0 {
                kernelPosition(blurIteration: i, radius: &kernelSizeX, deltaLeft: &dxLeft, deltaRight: &dxRight)
                boxBlur(srcBuffer: &srcBuffer, destBuffer: &destBuffer, dx: Int(kernelSizeX),
                        dxLeft: dxLeft, dxRight: dxRight, stride: 4, strideLine: stride,
                        width: width, height: height)
                swap(&srcBuffer, &destBuffer)
            }

            if kernelSizeY > 0 {
                kernelPosition(blurIteration: i, radius: &kernelSizeY, deltaLeft: &dyLeft, deltaRight: &dyRight)
                boxBlur(srcBuffer: &srcBuffer, destBuffer: &destBuffer, dx: Int(kernelSizeY),
                        dxLeft: dyLeft, dxRight: dyRight, stride: stride, strideLine: 4,
                        width: height, height: width)
                swap(&srcBuffer, &destBuffer)
            }
            i += 1
        }
    }

    private func boxBlur(srcBuffer: inout vImage_Buffer, destBuffer: inout vImage_Buffer, dx: Int, dxLeft: Int, dxRight: Int,
                         stride: Int, strideLine: Int, width: Int, height: Int)
    {
        let maxKernelSize = min(dxRight, Int(width))
        let srcData = srcBuffer.data.assumingMemoryBound(to: Pixel_8.self)
        let destData = destBuffer.data.assumingMemoryBound(to: Pixel_8.self)
        var y = 0
        while y < height {
            let line = y * strideLine
            var (sumR, sumG, sumB, sumA) = (Int(0), Int(0), Int(0), Int(0))
            var i = 0
            while i < maxKernelSize {
                let offset = line + i * stride
                sumR += Int(srcData[offset + 0])
                sumG += Int(srcData[offset + 1])
                sumB += Int(srcData[offset + 2])
                sumA += Int(srcData[offset + 3])
                i += 1
            }
            var x = 0
            while x < width {
                let offset = line + x * stride
                let destPtr = destData.advanced(by: offset)
                destPtr[0] = Pixel_8(max(sumR / dx, 0))
                destPtr[1] = Pixel_8(max(sumG / dx, 0))
                destPtr[2] = Pixel_8(max(sumB / dx, 0))
                destPtr[3] = Pixel_8(max(sumA / dx, 0))

                if x >= dxLeft {
                    let leftOffset = offset - dxLeft * stride
                    let srcPtr = srcData.advanced(by: leftOffset)
                    sumR -= Int(srcPtr[0])
                    sumG -= Int(srcPtr[1])
                    sumB -= Int(srcPtr[2])
                    sumA -= Int(srcPtr[3])
                }

                if x + dxRight < width {
                    let rightOffset = offset + dxRight * stride
                    let srcPtr = srcData.advanced(by: rightOffset)
                    sumR += Int(srcPtr[0])
                    sumG += Int(srcPtr[1])
                    sumB += Int(srcPtr[2])
                    sumA += Int(srcPtr[3])
                }
                x += 1
            }
            y += 1
        }
    }

    @inline(__always)
    private func kernelPosition(blurIteration: Int, radius: inout UInt, deltaLeft: inout Int, deltaRight: inout Int) {
        switch blurIteration {
        case 0:
            if radius % 2 == 1 {
                deltaLeft = Int(radius) / 2 - 1
                deltaRight = Int(radius) - deltaLeft
            } else {
                deltaLeft = Int(radius) / 2
                deltaRight = Int(radius) - deltaLeft
            }
        case 1:
            if radius % 2 == 1 {
                deltaLeft += 1
                deltaRight -= 1
            }
        case 2:
            if radius % 2 == 1 {
                deltaRight += 1
                radius += 1
            }
        default:
            fatalError()
        }
    }
}

extension SVGFeGaussianBlurElement: Encodable {
    private enum CodingKeys: String, CodingKey {
        case stdDeviation
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Self.CodingKeys.self)
        try container.encodeIfPresent(stdDeviation, forKey: .stdDeviation)
    }
}
