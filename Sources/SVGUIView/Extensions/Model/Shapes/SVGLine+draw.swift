import SVGView
import UIKit

extension SVGLine: SVG1DDrawer {
    var path: UIBezierPath? {
        let line = UIBezierPath()
        line.move(to: CGPoint(x: x1, y: y1))
        line.addLine(to: CGPoint(x: x2, y: y2))
        return line
    }
}
