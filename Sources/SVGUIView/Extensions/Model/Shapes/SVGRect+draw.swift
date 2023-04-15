import SVGView
import UIKit

extension SVGRect: SVGDrawer {
    var path: UIBezierPath? {
        if width == 0 || height == 0 {
            return nil
        }
        let cornerSize = CGSize(width: min(width / 2.0, rx), height: min(height / 2.0, ry))
        return UIBezierPath(roundedRect: .init(x: x, y: y, width: width, height: height), cornerSize: cornerSize)
    }
}
