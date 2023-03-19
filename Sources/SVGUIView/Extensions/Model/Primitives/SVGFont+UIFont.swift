import SVGView
import UIKit

extension SVGFont {
    func toUIFont() -> UIFont? {
        UIFont(name: name, size: size)
    }
}
