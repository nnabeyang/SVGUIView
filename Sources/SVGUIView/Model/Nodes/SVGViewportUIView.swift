import SVGView
import UIKit

public extension SVGViewport {
    func uiView() -> SVGUIView {
        SVGUIView(model: self)
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
