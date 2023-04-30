import SVGView
import UIKit

public extension SVGDataImage {
    func draw() {
        let context = UIGraphicsGetCurrentContext()!
        context.saveGState()

        if let image = UIImage(data: data),
           let cgImage = image.cgImage
        {
            let s = scale(imageSize: image.size)
            let width = image.size.width * s
            let height = image.size.height * s
            context.scaleBy(x: 1, y: -1)
            context.draw(cgImage, in: CGRect(x: x, y: -height - y, width: width, height: height))
        }
        context.restoreGState()
    }

    private func scale(imageSize size: CGSize) -> CGFloat {
        let sx = width / size.width
        let sy = height / size.height
        if width == 0 { return sy }
        if height == 0 { return sx }
        return width > height ? sy : sx
    }
}
