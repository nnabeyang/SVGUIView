import SVGView
import UIKit

extension SVGCircle: SVGDrawer {
    var path: UIBezierPath? {
        UIBezierPath(arcCenter: CGPoint(x: cx, y: cy), radius: r, startAngle: 0, endAngle: CGFloat(Double.pi) * 2, clockwise: true)
    }
}
