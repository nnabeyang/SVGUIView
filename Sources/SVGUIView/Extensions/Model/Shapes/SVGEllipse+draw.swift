import SVGView
import UIKit

public extension SVGEllipse {
    func draw(_ trans: CGAffineTransform) {
        if rx == 0 || ry == 0 {
            return
        }
        let oval = UIBezierPath(ovalIn: frame())
        oval.apply(trans.concatenating(transform))
        applySVGFill(paint: fill, path: oval)
        applySVGStroke(stroke: stroke, path: oval)
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

    private func applySVGFill(paint: SVGPaint?, path: UIBezierPath) {
        if let p = paint as? SVGColor {
            p.toUIColor.setFill()
            path.fill()
        }
    }
}
