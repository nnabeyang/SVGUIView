import SVGView
import UIKit

extension SVGPath: SVGDrawer {
    var path: UIBezierPath? {
        toBezierPath()
    }

    var eoFill: Bool? {
        fillRule == .evenOdd
    }
}
