import Accelerate
import UIKit

protocol SVGFilterApplier {
    func apply(srcBuffer: inout vImage_Buffer, destBuffer: inout vImage_Buffer, context: SVGContext)
    func frame(filter: SVGFilterElement, frame: CGRect, context: SVGContext) -> CGRect
}

enum StdDeviation: Equatable {
    case iso(Double)
    case hetero(x: Double, y: Double)
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
        var container = encoder.container(keyedBy: Self.CodingKeys)
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
    static let zero: StdDeviation = .hetero(x: 0, y: 0)
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
        stdDeviation = StdDeviation(description: attributes["stdDeviation", default: ""])
    }

    static func clampedToKernelSize(value: CGFloat) -> UInt32 {
        min(Self.maxKernelSize, UInt32(max(floor(value * 3.0 * sqrt(2 * .pi) as CGFloat / 4 + 0.5) as CGFloat, 2 * UIScreen.main.scale)))
    }

    func frame(filter: SVGFilterElement, frame: CGRect, context: SVGContext) -> CGRect {
        let x: CGFloat, y: CGFloat
        let primitiveUnits = (filter.primitiveUnits ?? .userSpaceOnUse) == .userSpaceOnUse
        let userSpace = filter.userSpace ?? false
        if let dx = self.x?.calculatedLength(frame: frame, context: context, mode: .width, userSpace: primitiveUnits) {
            x = primitiveUnits ? dx : frame.minX + dx
        } else {
            let dx = filter.x?.calculatedLength(frame: frame, context: context, mode: .width, userSpace: userSpace) ?? -0.1 * frame.width
            x = userSpace ? dx : frame.minX + dx
        }
        if let dy = self.y?.calculatedLength(frame: frame, context: context, mode: .height, userSpace: primitiveUnits) {
            y = primitiveUnits ? dy : frame.minX + dy
        } else {
            let dy = filter.y?.calculatedLength(frame: frame, context: context, mode: .height, userSpace: userSpace) ?? -0.1 * frame.height
            y = userSpace ? dy : frame.minY + dy
        }
        let width = width?.calculatedLength(frame: frame, context: context, mode: .width, userSpace: primitiveUnits) ??
            filter.width?.calculatedLength(frame: frame, context: context, mode: .width, userSpace: filter.userSpace ?? false) ??
            1.2 * frame.width
        let height = height?.calculatedLength(frame: frame, context: context, mode: .height, userSpace: primitiveUnits) ??
            filter.height?.calculatedLength(frame: frame, context: context, mode: .height, userSpace: userSpace) ??
            1.2 * frame.height
        return CGRect(origin: CGPoint(x: x, y: y), size: CGSize(width: width, height: height))
    }

    func apply(srcBuffer: inout vImage_Buffer, destBuffer: inout vImage_Buffer, context: SVGContext) {
        let stdDeviation = stdDeviation ?? .zero
        switch stdDeviation {
        case let .hetero(x, y):
            guard x >= 0, y >= 0 else { return }
            if x != y {
                let kernelSizeX = Self.clampedToKernelSize(value: x * UIScreen.main.scale)
                let kernelSizeY = Self.clampedToKernelSize(value: y * UIScreen.main.scale)
                applyUnaccelerated(srcBuffer: &srcBuffer, destBuffer: &destBuffer,
                                   kernelSizeX: kernelSizeX, kernelSizeY: kernelSizeY, context: context)
            } else {
                let kernelSize = Self.clampedToKernelSize(value: x * UIScreen.main.scale) | 1
                applyAccelerated(srcBuffer: &srcBuffer, destBuffer: &destBuffer, kernelSize: kernelSize)
            }
        case let .iso(x):
            guard x >= 0 else { return }
            let kernelSize = Self.clampedToKernelSize(value: x * UIScreen.main.scale) | 1
            applyAccelerated(srcBuffer: &srcBuffer, destBuffer: &destBuffer, kernelSize: kernelSize)
        }
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
        var container = encoder.container(keyedBy: Self.CodingKeys)
        try container.encodeIfPresent(stdDeviation, forKey: .stdDeviation)
    }
}
