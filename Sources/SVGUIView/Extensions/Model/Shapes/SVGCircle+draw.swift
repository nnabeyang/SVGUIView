import SVGView
import UIKit

extension SVGCircle: SVGDrawer {
    func draw(_ trans: CGAffineTransform) {
        let circle = UIBezierPath(arcCenter: CGPoint(x: cx, y: cy), radius: r, startAngle: 0, endAngle: CGFloat(Double.pi) * 2, clockwise: true)
        let combined = transform.concatenating(trans)
        circle.apply(combined)
        applySVGFill(paint: fill, path: circle, transform: combined, frame: frame())
        applySVGStroke(stroke: stroke, path: circle, scaled: sqrt(combined.a * combined.a + combined.b * combined.b))
    }
}
