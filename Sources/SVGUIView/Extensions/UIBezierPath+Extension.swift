import UIKit

extension UIBezierPath {
    convenience init(roundedRect rect: CGRect, cornerSize: CGSize) {
        self.init()

        let rx = cornerSize.width
        let ry = cornerSize.height

        let x1 = rect.minX + rx
        let y1 = rect.minY + ry
        let x2 = rect.maxX - rx
        let y2 = rect.maxY - ry

        move(to: CGPoint(x: x1, y: y1 - ry))
        addLine(to: CGPoint(x: x2, y: y1 - ry))
        addEllipticalArc(withCenter: .init(x: x2, y: y1), radii: .init(width: rx * 2, height: ry * 2), startAngle: -CGFloat.pi / 2.0, endAngle: 0)
        addLine(to: CGPoint(x: x2 + rx, y: rect.maxY - ry))
        addEllipticalArc(withCenter: .init(x: x2, y: y2), radii: .init(width: rx * 2, height: ry * 2), startAngle: 0, endAngle: CGFloat.pi / 2.0)
        addLine(to: CGPoint(x: x1, y: y2 + ry))
        addEllipticalArc(withCenter: .init(x: x1, y: y2), radii: .init(width: rx * 2, height: ry * 2), startAngle: CGFloat.pi / 2.0, endAngle: CGFloat.pi)
        addLine(to: CGPoint(x: x1 - rx, y: y1))
        addEllipticalArc(withCenter: .init(x: x1, y: y1), radii: .init(width: rx * 2, height: ry * 2), startAngle: CGFloat.pi, endAngle: CGFloat.pi * 3.0 / 2.0)
        close()
    }

    private static let maxArcAngle = CGFloat.pi / 3.0

    public func addEllipticalArc(withCenter center: CGPoint, radii: CGSize, startAngle: CGFloat, endAngle: CGFloat, rotation: CGFloat = 0) {
        if radii.width == radii.height, rotation == 0 {
            addArc(withCenter: center, radius: CGFloat(radii.width / 2), startAngle: startAngle, endAngle: endAngle, clockwise: endAngle >= startAngle)
            return
        }
        let clockwise = endAngle > startAngle
        let lastAngle = clockwise ? min(startAngle + 2 * CGFloat.pi, endAngle) : max(startAngle - 2 * CGFloat.pi, endAngle)
        let n = Int(abs(lastAngle - startAngle) / Self.maxArcAngle) + 1
        let angles = (0 ... n).map {
            clockwise ? min(lastAngle, startAngle + Self.maxArcAngle * CGFloat($0)) : max(lastAngle, startAngle - Self.maxArcAngle * CGFloat($0))
        }

        for i in 0 ..< n {
            _addEllipticalArc(withCenter: center, radii: radii, startAngle: angles[i], endAngle: angles[i + 1], rotation: rotation)
        }
    }

    private func _addEllipticalArc(withCenter center: CGPoint, radii: CGSize, startAngle: CGFloat, endAngle: CGFloat, rotation: CGFloat) {
        func e(cx: CGFloat, cy: CGFloat, rx: CGFloat, ry: CGFloat, angle: CGFloat, rotation: CGFloat) -> CGPoint {
            CGPoint(
                x: cx + rx * cos(rotation) * cos(angle) - ry * sin(rotation) * sin(angle),
                y: cy + rx * sin(rotation) * cos(angle) + ry * cos(rotation) * sin(angle)
            )
        }

        func d(cx _: CGFloat, cy _: CGFloat, rx: CGFloat, ry: CGFloat, angle: CGFloat, rotation: CGFloat) -> CGPoint {
            CGPoint(
                x: -rx * cos(rotation) * sin(angle) - ry * sin(rotation) * cos(angle),
                y: -rx * sin(rotation) * sin(angle) + ry * cos(rotation) * cos(angle)
            )
        }

        let (cx, cy) = (center.x, center.y)
        let (rx, ry) = (radii.width / 2.0, radii.height / 2.0)
        let a = sin(endAngle - startAngle) * (sqrt(4 + 3 * tan((endAngle - startAngle) / 2.0) * tan((endAngle - startAngle) / 2.0)) - 1) / 3.0

        let p1 = e(cx: cx, cy: cy, rx: rx, ry: ry, angle: startAngle, rotation: rotation)
        let p2 = e(cx: cx, cy: cy, rx: rx, ry: ry, angle: endAngle, rotation: rotation)

        let q1 = d(cx: cx, cy: cy, rx: rx, ry: ry, angle: startAngle, rotation: rotation)
        let q2 = d(cx: cx, cy: cy, rx: rx, ry: ry, angle: endAngle, rotation: rotation)

        addCurve(to: p2,
                 controlPoint1: CGPoint(x: p1.x + a * q1.x, y: p1.y + a * q1.y),
                 controlPoint2: CGPoint(x: p2.x - a * q2.x, y: p2.y - a * q2.y))
    }
}
