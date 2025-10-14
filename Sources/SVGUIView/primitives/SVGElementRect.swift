import Foundation

struct SVGElementRect: Encodable {
  let x: Double
  let y: Double
  let width: Double
  let height: Double
  func toCGRect() -> CGRect {
    CGRect(origin: CGPoint(x: x, y: y), size: CGSize(width: width, height: height))
  }
}
