import SVGView
import UIKit

extension SVGLine: SVG1DDrawer {
    func draw(_ trans: CGAffineTransform) {
        let line = UIBezierPath()
        line.move(to: CGPoint(x: x1, y: y1))
        line.addLine(to: CGPoint(x: x2, y: y2))
        let combined = trans.concatenating(transform)
        line.apply(combined)
        applySVGStroke(stroke: stroke, path: line, scaled: sqrt(combined.a * combined.a + combined.b * combined.b))
    }
}
