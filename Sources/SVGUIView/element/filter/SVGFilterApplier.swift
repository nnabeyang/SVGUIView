import Accelerate

protocol SVGFilterApplier {
    var x: SVGLength? { get }
    var y: SVGLength? { get }
    var width: SVGLength? { get }
    var height: SVGLength? { get }
    func apply(srcBuffer: inout vImage_Buffer, destBuffer: inout vImage_Buffer, context: SVGContext)
    func frame(filter: SVGFilterElement, frame: CGRect, context: SVGContext) -> CGRect
    func transform(filter: SVGFilterElement, frame: CGRect) -> CGAffineTransform
}

extension SVGFilterApplier {
    func frame(filter: SVGFilterElement, frame: CGRect, context: SVGContext) -> CGRect {
        let x: CGFloat, y: CGFloat
        let primitiveUnits = (filter.primitiveUnits ?? .userSpaceOnUse) == .userSpaceOnUse
        let userSpace = filter.userSpace ?? false
        if let dx = self.x?.calculatedLength(frame: frame, context: context, mode: .width, userSpace: primitiveUnits) {
            x = primitiveUnits ? dx : frame.minX + dx
        } else {
            let dx = filter.x?.calculatedLength(frame: frame, context: context, mode: .width, userSpace: userSpace) ?? -0.1 * frame.width
            x = userSpace ? dx : frame.minX + dx
        }
        if let dy = self.y?.calculatedLength(frame: frame, context: context, mode: .height, userSpace: primitiveUnits) {
            y = primitiveUnits ? dy : frame.minX + dy
        } else {
            let dy = filter.y?.calculatedLength(frame: frame, context: context, mode: .height, userSpace: userSpace) ?? -0.1 * frame.height
            y = userSpace ? dy : frame.minY + dy
        }
        let width = width?.calculatedLength(frame: frame, context: context, mode: .width, userSpace: primitiveUnits) ??
            filter.width?.calculatedLength(frame: frame, context: context, mode: .width, userSpace: filter.userSpace ?? false) ??
            1.2 * frame.width
        let height = height?.calculatedLength(frame: frame, context: context, mode: .height, userSpace: primitiveUnits) ??
            filter.height?.calculatedLength(frame: frame, context: context, mode: .height, userSpace: userSpace) ??
            1.2 * frame.height
        return CGRect(origin: CGPoint(x: x, y: y), size: CGSize(width: width, height: height))
    }

    func transform(filter _: SVGFilterElement, frame _: CGRect) -> CGAffineTransform {
        .identity
    }
}
