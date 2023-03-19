import SVGView
import UIKit

extension SVGColor {
    var toUIColor: UIColor {
        UIColor(red: CGFloat(r) / 255.0,
                green: CGFloat(g) / 255.0,
                blue: CGFloat(b) / 255.0,
                alpha: opacity)
    }
}
