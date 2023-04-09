import SVGView
import UIKit

extension SVGRect: SVGDrawer {
    func draw(_ trans: CGAffineTransform) {
        if width == 0 || height == 0 {
            return
        }
        let cornerSize = CGSize(width: min(width / 2.0, rx), height: min(height / 2.0, ry))
        let rect = UIBezierPath(roundedRect: .init(x: x, y: y, width: width, height: height), cornerSize: cornerSize)
        let combined = transform.concatenating(trans)
        rect.apply(combined)
        applySVGFill(paint: fill, path: rect, transform: combined, frame: frame())
        applySVGStroke(stroke: stroke, rect: rect, scaled: sqrt(combined.a * combined.a + combined.b * combined.b))
    }

    private func applySVGStroke(stroke: SVGStroke?, rect: UIBezierPath, scaled: CGFloat) {
        guard let stroke = stroke else { return }
        if let color = stroke.fill as? SVGColor {
            color.toUIColor.setStroke()
        }
        rect.lineWidth = stroke.width * scaled
        rect.lineCapStyle = stroke.cap
        rect.lineJoinStyle = stroke.join
        rect.stroke()
    }
}
