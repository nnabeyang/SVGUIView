import CoreGraphics
import Foundation

enum PreserveAspectRatio {
    case normal(x: Align, y: Align, option: Option)
    case simple(x: Align, y: Align)
    case none

    enum Align: String {
        case min
        case mid
        case max

        func align(outer: CGFloat, inner: CGFloat) -> CGFloat {
            switch self {
            case .mid:
                return (outer - inner) / 2
            case .max:
                return outer - inner
            default:
                return 0
            }
        }
    }

    enum AlignType: String {
        case xMinYMin
        case xMidYMin
        case xMaxYMin
        case xMinYMid
        case xMidYMid
        case xMaxYMid
        case xMinYMax
        case xMidYMax
        case xMaxYMax
        case none
    }

    enum Option: String {
        case meet
        case slice

        public func fit(size: CGSize, into sizeToFitIn: CGSize) -> CGSize {
            let widthRatio = sizeToFitIn.width / size.width
            let heightRatio = sizeToFitIn.height / size.height
            switch (self, heightRatio < widthRatio) {
            case (.meet, true), (.slice, false):
                return CGSize(width: size.width * heightRatio, height: sizeToFitIn.height)
            case (.meet, false), (.slice, true):
                return CGSize(width: sizeToFitIn.width, height: size.height * widthRatio)
            }
        }
    }

    init() {
        self = .normal(x: .mid, y: .mid, option: .meet)
    }

    init(xAlign: Align, yAlign: Align, option: Option) {
        self = .normal(x: xAlign, y: yAlign, option: option)
    }

    init(xAlign: Align, yAlign: Align) {
        self = .simple(x: xAlign, y: yAlign)
    }

    init?(description: String) {
        var data = description
        let value = data.withUTF8 {
            let bytes = BufferView(unsafeBufferPointer: $0)!
            var scanner = SVGAttributeScanner(bytes: bytes)
            return scanner.scanPreserveAspectRatio()
        }
        guard let value = value else {
            return nil
        }
        self = value
    }

    func getTransform(viewBox: CGRect, size: CGSize) -> CGAffineTransform {
        let (sx, sy): (CGFloat, CGFloat)
        let (dx, dy): (CGFloat, CGFloat)
        switch self {
        case .none:
            sx = size.width / viewBox.width
            sy = size.height / viewBox.height
            dx = 0
            dy = 0
        case let .simple(xAlign, yAlign):
            sx = 1.0
            sy = 1.0
            dx = xAlign.align(outer: size.width, inner: viewBox.width)
            dy = yAlign.align(outer: size.height, inner: viewBox.height)
        case let .normal(xAlign, yAlign, option):
            let newSize = option.fit(size: viewBox.size, into: size)
            sx = newSize.width / viewBox.width
            sy = newSize.height / viewBox.height
            dx = xAlign.align(outer: size.width, inner: newSize.width) / sx
            dy = yAlign.align(outer: size.height, inner: newSize.height) / sy
        }
        return CGAffineTransform(scaleX: sx, y: sy).translatedBy(x: dx - viewBox.minX, y: dy - viewBox.minY)
    }
}
