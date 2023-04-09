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
}
