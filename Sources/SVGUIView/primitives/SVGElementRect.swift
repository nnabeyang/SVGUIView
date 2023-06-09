import Foundation

struct SVGElementRect: Encodable {
    let x: CGFloat
    let y: CGFloat
    let width: Double
    let height: Double
    func toCGRect() -> CGRect {
        CGRect(origin: CGPoint(x: x, y: y), size: CGSize(width: width, height: height))
    }
}
