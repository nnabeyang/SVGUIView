import SVGView
import UIKit

extension SVGFont {
    func toUIFont() -> UIFont {
        if let font = UIFont(name: name, size: size) {
            return font
        }

        return UIFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }
}
