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
    func draw(_: SVGContext, index _: Int, depth _: Int, mode _: DrawMode) {
        fatalError()
    }

    func drawWithoutFilter(_: SVGContext, index _: Int, depth _: Int, mode _: DrawMode) {
        fatalError()
    }

    func frame(filter: SVGFilterElement, frame: CGRect, context: SVGContext) -> CGRect {
        let primitiveUnits = (filter.primitiveUnits ?? .userSpaceOnUse) == .userSpaceOnUse
        let userSpace = filter.userSpace ?? false
        let x = x?.calculatedLength(frame: frame, context: context, mode: .width, userSpace: primitiveUnits, isPosition: true) ??
            filter.x?.calculatedLength(frame: frame, context: context, mode: .width, userSpace: userSpace, isPosition: true) ??
            (frame.minX - 0.1 * frame.width)
        let y = y?.calculatedLength(frame: frame, context: context, mode: .height, userSpace: primitiveUnits, isPosition: true) ??
            filter.y?.calculatedLength(frame: frame, context: context, mode: .height, userSpace: userSpace, isPosition: true) ??
            (frame.minY - 0.1 * frame.height)
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
