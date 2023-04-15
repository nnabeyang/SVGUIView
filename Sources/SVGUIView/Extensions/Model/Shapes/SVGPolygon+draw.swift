import SVGView
import UIKit

extension SVGPolygon: SVGDrawer {
    var path: UIBezierPath? {
        guard let first = points.first else { return nil }
        let path = MBezierPath()
        path.move(to: CGPoint(x: first.x, y: first.y))
        for i in 1 ..< points.count {
            let point = points[i]
            path.addLine(to: CGPoint(x: point.x, y: point.y))
        }
        path.close()
        return path
    }
}
