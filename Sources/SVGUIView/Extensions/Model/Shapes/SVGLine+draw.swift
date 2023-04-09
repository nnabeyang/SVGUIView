import SVGView
import UIKit

extension SVGLine {
    func draw(_ trans: CGAffineTransform) {
        let line = UIBezierPath()
        line.move(to: CGPoint(x: x1, y: y1))
        line.addLine(to: CGPoint(x: x2, y: y2))
        line.apply(trans.concatenating(transform))
        applySVGStroke(stroke: stroke, path: line)
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
