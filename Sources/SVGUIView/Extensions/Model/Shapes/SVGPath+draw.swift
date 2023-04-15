import SVGView
import UIKit

extension SVGPath: SVGDrawer {
    func draw(_ trans: CGAffineTransform) {
        let path = toBezierPath()
        let combined = transform.concatenating(trans)
        path.apply(combined)
        applySVGFill(paint: fill, path: path, transform: combined, frame: frame())
        applySVGStroke(stroke: stroke, path: path, scaled: sqrt(combined.a * combined.a + combined.b * combined.b))
    }
}
