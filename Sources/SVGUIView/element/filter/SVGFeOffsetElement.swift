import Accelerate
import UIKit

struct SVGFeOffsetElement: SVGElement, SVGFilterApplier {
    var type: SVGElementName {
        .feOffset
    }

    let x: SVGLength?
    let y: SVGLength?
    let width: SVGLength?
    let height: SVGLength?

    let dx: Double?
    let dy: Double?

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

        dx = Double(attributes["dx", default: ""])
        dy = Double(attributes["dy", default: ""])
    }

    private static func parseColor(description: String) -> (any SVGUIColor)? {
        var data = description
        return data.withUTF8 {
            let bytes = BufferView(unsafeBufferPointer: $0)!
            var scanner = SVGAttributeScanner(bytes: bytes)
            return scanner.scanColor()
        }
    }

    func apply(srcBuffer _: inout vImage_Buffer, destBuffer _: inout vImage_Buffer, context _: SVGContext) {}
    func transform(filter: SVGFilterElement, frame: CGRect) -> CGAffineTransform {
        let primitiveUnits = (filter.primitiveUnits ?? .userSpaceOnUse) == .userSpaceOnUse
        let dx = dx ?? 0
        let dy = dy ?? 0
        return CGAffineTransform(translationX: primitiveUnits ? dx : dx * frame.width, y: primitiveUnits ? dy : dy * frame.height)
    }
}

extension SVGFeOffsetElement: Encodable {
    func encode(to _: Encoder) throws {
        fatalError()
    }
}
