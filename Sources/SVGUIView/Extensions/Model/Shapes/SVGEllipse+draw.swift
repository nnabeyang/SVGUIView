import SVGView
import UIKit

extension SVGEllipse: SVGDrawer {
    func draw(_ trans: CGAffineTransform) {
        if rx == 0 || ry == 0 {
            return
        }
        let oval = UIBezierPath(ovalIn: frame())
        let combined = transform.concatenating(trans)
        oval.apply(combined)
        applySVGFill(paint: fill, path: oval, transform: combined, frame: frame())
        applySVGStroke(stroke: stroke, path: oval, scaled: sqrt(combined.a * combined.a + combined.b * combined.b))
    }
}
