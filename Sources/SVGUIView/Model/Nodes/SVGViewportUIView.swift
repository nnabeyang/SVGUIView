import SVGView
import UIKit

public extension SVGViewport {
    func uiView() -> SVGUIView {
        SVGUIView(model: self)
    }

    func getViewBox(size: CGSize) -> CGRect {
        if let viewBox = viewBox {
            return viewBox
        }
        return CGRect(x: 0,
                      y: 0,
                      width: width.toPixels(total: size.width),
                      height: height.toPixels(total: size.height))
    }

    func getTransform(viewBox: CGRect, size: CGSize) -> CGAffineTransform {
        let transform = preserveAspectRatio.layout(size: viewBox.size, into: size)
        return transform.translatedBy(x: -viewBox.minX, y: -viewBox.minY)
    }
}

extension SVGLength {
    var ideal: CGFloat? {
        switch self {
        case .percent:
            return nil
        case let .pixels(pixels):
            return pixels
        }
    }
}
