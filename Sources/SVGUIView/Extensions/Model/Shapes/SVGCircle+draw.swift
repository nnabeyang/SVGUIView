import SVGView
import UIKit

extension SVGCircle: SVGDrawer {
    func draw(_ trans: CGAffineTransform) {
        let circle = UIBezierPath(arcCenter: CGPoint(x: cx, y: cy), radius: r, startAngle: 0, endAngle: CGFloat(Double.pi) * 2, clockwise: true)
        let combined = transform.concatenating(trans)
        circle.apply(combined)
        applySVGFill(paint: fill, path: circle, transform: combined, frame: frame())
        applySVGStroke(stroke: stroke, path: circle)
    }

    private func applySVGStroke(stroke: SVGStroke?, path: UIBezierPath) {
        guard let stroke = stroke else { return }
        if let color = stroke.fill as? SVGColor {
            color.toUIColor.setStroke()
        }
        path.lineWidth = stroke.width
        path.lineCapStyle = stroke.cap
        path.lineJoinStyle = stroke.join
        path.stroke()
    }
}
