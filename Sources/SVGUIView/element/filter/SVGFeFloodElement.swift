import Accelerate
import UIKit

struct SVGFeFloodElement: SVGElement, SVGFilterApplier {
    private static let maxKernelSize: UInt32 = 100
    var type: SVGElementName {
        .feFlood
    }

    let x: SVGLength?
    let y: SVGLength?
    let width: SVGLength?
    let height: SVGLength?

    let floodColor: SVGUIColor?
    let floodOpacity: Double?

    func draw(_: SVGContext, index _: Int, depth _: Int, mode _: DrawMode) {
        fatalError()
    }

    func style(with _: CSSStyle, at _: Int) -> any SVGElement {
        self
    }

    init(attributes: [String: String]) {
        x = SVGLength(attributes["x"])
        y = SVGLength(attributes["y"])
        width = SVGLength(attributes["width"])
        height = SVGLength(attributes["height"])
        floodColor = Self.parseColor(description: attributes["flood-color", default: ""])
        floodOpacity = Double(attributes["flood-opacity", default: ""])
    }

    private static func parseColor(description: String) -> (any SVGUIColor)? {
        var data = description
        return data.withUTF8 {
            let bytes = BufferView(unsafeBufferPointer: $0)!
            var scanner = SVGAttributeScanner(bytes: bytes)
            return scanner.scanColor()
        }
    }

    func apply(srcBuffer _: inout vImage_Buffer, destBuffer: inout vImage_Buffer, context _: SVGContext) {
        let floodColor = floodColor ?? SVGColorName(name: "black")
        let floodOpacity = floodOpacity ?? 1.0
        let (red: r, green: g, blue: b, alpha: a) = floodColor.rgba

        let y = (r * 0.2125 + g * 0.7154 + b * 0.0721) * floodOpacity
        let u = (r * -0.115 + g * -0.386 + b * 0.5) * floodOpacity
        let v = (r * 0.5 + g * -0.454 + b * -0.046) * floodOpacity
        var color = [
            UInt8(round(y + u * 1.8558)),
            UInt8(round(y + u * -0.187 + v * -0.4678)),
            UInt8(round(y + v * 1.575)),
            UInt8((a * floodOpacity).rounded(.toNearestOrAwayFromZero)),
        ]
        vImageBufferFill_ARGB8888(&destBuffer,
                                  &color,
                                  vImage_Flags(kvImageNoFlags))
    }
}

extension SVGFeFloodElement: Encodable {
    func encode(to _: Encoder) throws {
        fatalError()
    }
}
