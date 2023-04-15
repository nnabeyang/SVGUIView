import SVGView
import UIKit

extension SVGEllipse: SVGDrawer {
    var path: UIBezierPath? {
        if rx == 0 || ry == 0 {
            return nil
        }
        return UIBezierPath(ovalIn: frame())
    }
}
