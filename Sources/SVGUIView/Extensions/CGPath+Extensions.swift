
import UIKit

public extension CGPath {
    func xnormalized(using rule: CGPathFillRule = .winding) -> CGPath {
        if #available(iOS 16.0, *) {
            return normalized(using: rule)
        } else {
            return self
        }
    }

    func xintersection(_ other: CGPath, using rule: CGPathFillRule = .winding) -> CGPath {
        if #available(iOS 16.0, *) {
            return intersection(other, using: rule)
        } else {
            return self
        }
    }

    func xunion(_ other: CGPath, using rule: CGPathFillRule = .winding) -> CGPath {
        if #available(iOS 16.0, *) {
            return union(other, using: rule)
        } else {
            return self
        }
    }
}
