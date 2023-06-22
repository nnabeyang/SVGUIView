import UIKit

struct SVGPathElement: SVGDrawableElement {
    var type: SVGElementName {
        .path
    }

    let base: SVGBaseElement
    let segments: [any PathSegment]

    init(base: SVGBaseElement, text _: String, attributes: [String: String]) {
        self.base = base
        guard var d = attributes["d"] else {
            segments = []
            return
        }
        segments = d.withUTF8 {
            let bytes = BufferView(unsafeBufferPointer: $0)!
            var scanner = SVGAttributeScanner(bytes: bytes)
            return scanner.scanPathSegments()
        }
    }

    init(other: Self, css: SVGUIStyle) {
        base = SVGBaseElement(other: other.base, css: css)
        segments = other.segments
    }

    func toBezierPath(context _: SVGContext) -> UIBezierPath? {
        let pathContext = SVGPathContext()
        for segment in segments {
            segment.apply(context: pathContext)
        }
        return pathContext.path
    }
}

extension SVGPathElement: Encodable {
    private enum CodingKeys: String, CodingKey {
        case d
        case fill
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Self.CodingKeys)
        var dContainer = container.nestedUnkeyedContainer(forKey: .d)
        for segment in segments {
            try dContainer.encode(segment)
        }
        try container.encode(fill, forKey: .fill)
    }
}

final class SVGPathContext {
    var path: UIBezierPath?
    var cubicPoint: CGPoint?
    var quadrPoint: CGPoint?
    init() {}

    private func createPathIfNeeded() -> UIBezierPath {
        guard let path = path else {
            let newPath = UIBezierPath()
            self.path = newPath
            return newPath
        }
        return path
    }

    static func takeMirrorIfNeeded(p1: CGPoint, p2: CGPoint?) -> CGPoint {
        guard let p2 = p2 else { return p1 }
        return CGPoint(x: (2 * p1.x) - p2.x, y: (2 * p1.y) - p2.y)
    }

    func apply(path: UIBezierPath?, arg: MPathArgument, isAbsolute: Bool) {
        M(path: path, isMoved: arg.isMoved, x: arg.x, y: arg.y, isAbsolute: isAbsolute)
    }

    func apply(path: UIBezierPath, arg _: ZPathArgument, isAbsolute _: Bool) {
        Z(path: path)
    }

    func apply(path: UIBezierPath, arg: LPathArgument, isAbsolute: Bool) {
        L(path: path, x: arg.x, y: arg.y, isAbsolute: isAbsolute)
    }

    func apply(path: UIBezierPath, arg: CPathArgument, isAbsolute: Bool) {
        C(path: path, x1: arg.x1, y1: arg.y1, x2: arg.x2, y2: arg.y2, x: arg.x, y: arg.y, isAbsolute: isAbsolute)
    }

    func apply(path: UIBezierPath, arg: QPathArgument, isAbsolute: Bool) {
        Q(path: path, x1: arg.x1, y1: arg.y1, x: arg.x, y: arg.y, isAbsolute: isAbsolute)
    }

    func apply(path: UIBezierPath, arg: APathArgument, isAbsolute: Bool) {
        A(path: path, rx: arg.rx, ry: arg.ry, angle: arg.angle, largeArc: arg.largeArc, sweep: arg.sweep, x: arg.x, y: arg.y, isAbsolute: isAbsolute)
    }

    func apply(path _: UIBezierPath, arg: (isMoved: Bool, x: Double, y: Double), isAbsolute: Bool) {
        M(path: path, isMoved: arg.isMoved, x: arg.x, y: arg.y, isAbsolute: isAbsolute)
    }

    func apply(path: UIBezierPath, arg _: Void, isAbsolute _: Bool) {
        Z(path: path)
    }

    func apply(path: UIBezierPath, arg: (x: Double?, y: Double?), isAbsolute: Bool) {
        L(path: path, x: arg.x, y: arg.y, isAbsolute: isAbsolute)
    }

    func apply(path: UIBezierPath, arg: (x1: Double?, y1: Double?, x2: Double, y2: Double, x: Double, y: Double), isAbsolute: Bool) {
        C(path: path, x1: arg.x1, y1: arg.y1, x2: arg.x2, y2: arg.y2, x: arg.x, y: arg.y, isAbsolute: isAbsolute)
    }

    func apply(path: UIBezierPath, arg: (x1: Double?, y1: Double?, x: Double, y: Double), isAbsolute: Bool) {
        Q(path: path, x1: arg.x1, y1: arg.y1, x: arg.x, y: arg.y, isAbsolute: isAbsolute)
    }

    func apply(path: UIBezierPath, arg: (rx: Double, ry: Double, angle: Double, largeArc: Bool, sweep: Bool, x: Double, y: Double), isAbsolute: Bool) {
        A(path: path, rx: arg.rx, ry: arg.ry, angle: arg.angle, largeArc: arg.largeArc, sweep: arg.sweep, x: arg.x, y: arg.y, isAbsolute: isAbsolute)
    }

    // moveto
    @inline(__always)
    private func M(path: UIBezierPath?, isMoved: Bool, x: Double, y: Double, isAbsolute: Bool) {
        guard isMoved else {
            let cur = isAbsolute ? .zero : (path?.currentPoint ?? .zero)
            let path = createPathIfNeeded()
            let endPoint = CGPoint(x: cur.x + x, y: cur.y + y)
            path.move(to: endPoint)
            return
        }
        L(path: path!, x: x, y: y, isAbsolute: isAbsolute)
    }

    // closepath
    @inline(__always)
    private func Z(path: UIBezierPath) {
        path.close()
        let cur = path.currentPoint
        M(path: path, isMoved: false, x: cur.x, y: cur.y, isAbsolute: true)
    }

    // lineto
    @inline(__always)
    private func L(path: UIBezierPath, x: Double?, y: Double?, isAbsolute: Bool) {
        let dp = isAbsolute ? path.currentPoint : .zero
        let cur = isAbsolute ? .zero : path.currentPoint
        let x = x ?? dp.x
        let y = y ?? dp.y
        let endPoint = CGPoint(x: cur.x + x, y: cur.y + y)
        path.addLine(to: endPoint)
    }

    // cubic Bézier curve
    @inline(__always)
    private func C(path: UIBezierPath, x1: Double?, y1: Double?, x2: Double, y2: Double, x: Double, y: Double, isAbsolute: Bool) {
        let cur = isAbsolute ? .zero : path.currentPoint
        let endPoint = CGPoint(x: cur.x + x, y: cur.y + y)
        let controlPoint1: CGPoint
        if let x1 = x1, let y1 = y1 {
            controlPoint1 = CGPoint(x: cur.x + x1, y: cur.y + y1)
        } else {
            controlPoint1 = SVGPathContext.takeMirrorIfNeeded(p1: path.currentPoint, p2: cubicPoint)
        }
        let controlPoint2 = CGPoint(x: cur.x + x2, y: cur.y + y2)
        path.addCurve(to: endPoint, controlPoint1: controlPoint1, controlPoint2: controlPoint2)
        cubicPoint = controlPoint2
    }

    // quadratic Bézier curve
    @inline(__always)
    private func Q(path: UIBezierPath, x1: Double?, y1: Double?, x: Double, y: Double, isAbsolute: Bool) {
        let cur = isAbsolute ? .zero : path.currentPoint
        let endPoint = CGPoint(x: cur.x + x, y: cur.y + y)
        let controlPoint: CGPoint
        if let x1 = x1, let y1 = y1 {
            controlPoint = CGPoint(x: cur.x + x1, y: cur.y + y1)
        } else {
            controlPoint = SVGPathContext.takeMirrorIfNeeded(p1: path.currentPoint, p2: quadrPoint)
        }
        path.addQuadCurve(to: endPoint, controlPoint: controlPoint)
        quadrPoint = controlPoint
    }

    // elliptical arc curve
    @inline(__always)
    private func A(path: UIBezierPath, rx _rx: Double, ry _ry: Double, angle: Double, largeArc: Bool, sweep: Bool, x: Double, y: Double, isAbsolute: Bool)
    {
        if _rx == 0 || _ry == 0 {
            L(path: path, x: x, y: y, isAbsolute: isAbsolute)
            return
        }
        let angle = angle * .pi / 180

        let cur = path.currentPoint
        let x1 = Double(cur.x)
        let y1 = Double(cur.y)

        let dp = isAbsolute ? .zero : path.currentPoint
        let x2 = x + Double(dp.x)
        let y2 = y + Double(dp.y)

        let x1_ = cos(angle) * (x1 - x2) / 2 + sin(angle) * (y1 - y2) / 2
        let y1_ = -sin(angle) * (x1 - x2) / 2 + cos(angle) * (y1 - y2) / 2

        let lambda = (x1_ * x1_) / (_rx * _rx) + (y1_ * y1_) / (_ry * _ry)
        let rx: Double
        let ry: Double
        if lambda > 1 {
            rx = sqrt(lambda) * _rx
            ry = sqrt(lambda) * _ry
        } else {
            rx = _rx
            ry = _ry
        }

        let coef = xsqrt((rx * rx * ry * ry - rx * rx * y1_ * y1_ - ry * ry * x1_ * x1_)
            / (rx * rx * y1_ * y1_ + ry * ry * x1_ * x1_))
        let sign: Double = (sweep != largeArc) ? 1 : -1
        let cx_ = sign * coef * rx * y1_ / ry
        let cy_ = -sign * coef * ry * x1_ / rx
        let cx = cos(angle) * cx_ - sin(angle) * cy_ + (x1 + x2) / 2
        let cy = sin(angle) * cx_ + cos(angle) * cy_ + (y1 + y2) / 2

        let t1 = calcAngle(ux: 1, uy: 0, vx: (x1_ - cx_) / rx, vy: (y1_ - cy_) / ry)
        let dt = calcAngle(ux: (x1_ - cx_) / rx, uy: (y1_ - cy_) / ry, vx: (-x1_ - cx_) / rx, vy: (-y1_ - cy_) / ry, sweep: sweep)

        path.addEllipticalArc(withCenter: CGPoint(x: cx, y: cy), radii: .init(width: 2 * rx, height: 2 * ry),
                              startAngle: t1, endAngle: t1 + dt, rotation: angle)
    }

    @inline(__always)
    func calcAngle(ux: Double, uy: Double, vx: Double, vy: Double, sweep: Bool? = nil) -> Double {
        let sign = copysign(1, ux * vy - uy * vx)
        let value = (ux * vx + uy * vy) / (sqrt(ux * ux + uy * uy) * sqrt(vx * vx + vy * vy))
        let angle: Double
        if value < -1 {
            angle = sign * .pi
        } else if value > 1 {
            angle = 0
        } else {
            angle = sign * acos(value)
        }
        guard let sweep = sweep else {
            return angle
        }
        let delta: CGFloat
        if angle > 0, !sweep {
            delta = -.pi * 2
        } else if angle < 0, sweep {
            delta = .pi * 2
        } else {
            delta = 0.0
        }
        return angle.truncatingRemainder(dividingBy: .pi * 2) + delta
    }

    @inline(__always)
    func xsqrt(_ x: Double) -> Double {
        x > 0 ? sqrt(x) : 0
    }
}

enum PathSegmentType: UInt8, Equatable {
    case A = 65
    case C = 67
    case H = 72
    case L = 76
    case M = 77
    case Q = 81
    case S = 83
    case T = 84
    case V = 86
    case Z = 90
    case a = 97
    case c = 99
    case h = 104
    case l = 108
    case m = 109
    case q = 113
    case s = 115
    case t = 116
    case v = 118
    case z = 122

    var name: String {
        String(decoding: [rawValue], as: UTF8.self)
    }

    var isAbsolute: Bool {
        rawValue >= UInt8(ascii: "A") && rawValue <= UInt8(ascii: "Z")
    }
}

extension PathSegmentType: Encodable {
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(name)
    }
}

protocol PathSegmentArgument: Equatable, Encodable {
    func apply(path: UIBezierPath?, isAbsolute: Bool, context: SVGPathContext)
}

struct MPathArgument: PathSegmentArgument {
    let isMoved: Bool
    let x: Double
    let y: Double

    func apply(path: UIBezierPath?, isAbsolute: Bool, context: SVGPathContext) {
        context.apply(path: path, arg: self, isAbsolute: isAbsolute)
    }
}

extension MPathArgument: Encodable {
    private enum CondingKeys: String, CodingKey {
        case x
        case y
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Self.CondingKeys)
        try container.encode(x, forKey: .x)
        try container.encode(y, forKey: .y)
    }
}

struct ZPathArgument: PathSegmentArgument {
    func apply(path: UIBezierPath?, isAbsolute: Bool, context: SVGPathContext) {
        context.apply(path: path!, arg: self, isAbsolute: isAbsolute)
    }
}

struct LPathArgument: PathSegmentArgument {
    let x: Double?
    let y: Double?
    func apply(path: UIBezierPath?, isAbsolute: Bool, context: SVGPathContext) {
        context.apply(path: path!, arg: self, isAbsolute: isAbsolute)
    }
}

struct CPathArgument: PathSegmentArgument {
    let x1: Double?
    let y1: Double?
    let x2: Double
    let y2: Double
    let x: Double
    let y: Double
    func apply(path: UIBezierPath?, isAbsolute: Bool, context: SVGPathContext) {
        context.apply(path: path!, arg: self, isAbsolute: isAbsolute)
    }
}

struct QPathArgument: PathSegmentArgument {
    let x1: Double?
    let y1: Double?
    let x: Double
    let y: Double
    func apply(path: UIBezierPath?, isAbsolute: Bool, context: SVGPathContext) {
        context.apply(path: path!, arg: self, isAbsolute: isAbsolute)
    }
}

struct APathArgument: PathSegmentArgument {
    let rx: Double
    let ry: Double
    let angle: Double
    let largeArc: Bool
    let sweep: Bool
    let x: Double
    let y: Double
    func apply(path: UIBezierPath?, isAbsolute: Bool, context: SVGPathContext) {
        context.apply(path: path!, arg: self, isAbsolute: isAbsolute)
    }
}

protocol PathSegment: Equatable, Encodable {
    associatedtype Argument: PathSegmentArgument
    var type: PathSegmentType { get }
    var args: [Argument] { get }
    var isAbsolute: Bool { get }
    init(type: PathSegmentType, args: [Argument])
    func apply(context: SVGPathContext)
    func cleanUp(context: SVGPathContext)
    func isRenderable(context: SVGPathContext) -> Bool
}

extension PathSegment {
    func isRenderable(context: SVGPathContext) -> Bool {
        context.path != nil
    }

    var isAbsolute: Bool {
        type.isAbsolute
    }

    func apply(context: SVGPathContext) {
        guard isRenderable(context: context) else { return }
        for arg in args {
            arg.apply(path: context.path, isAbsolute: isAbsolute, context: context)
        }
        cleanUp(context: context)
    }
}

extension PathSegment /* Equatable */ {
    static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.isAbsolute == rhs.isAbsolute,
              lhs.args.count == rhs.args.count else { return false }
        for (l, r) in zip(lhs.args, rhs.args) {
            if l != r {
                return false
            }
        }
        return true
    }
}

private enum PathSegmentCodingKeys: String, CodingKey {
    case type
    case args
}

extension PathSegment /* Encodable */ {
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: PathSegmentCodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(args, forKey: .args)
    }
}

// moveto
struct MPathSegment: PathSegment {
    let type: PathSegmentType
    let args: [MPathArgument]

    init(type: PathSegmentType, args: [MPathArgument]) {
        precondition(type == .M || type == .m)
        self.type = type
        self.args = args
    }

    func cleanUp(context: SVGPathContext) {
        context.cubicPoint = nil
        context.quadrPoint = nil
    }

    func isRenderable(context _: SVGPathContext) -> Bool {
        true
    }
}

// closepath
struct ZPathSegment: PathSegment {
    static func == (_: ZPathSegment, _: ZPathSegment) -> Bool {
        true
    }

    let type: PathSegmentType
    var args: [ZPathArgument] { [ZPathArgument()] }

    init(type: PathSegmentType, args _: [ZPathArgument]) {
        precondition(type == .Z || type == .z)
        self.type = type
    }

    func cleanUp(context: SVGPathContext) {
        context.quadrPoint = nil
        context.cubicPoint = nil
    }
}

// lineto
struct LPathSegment: PathSegment {
    static func == (_: LPathSegment, _: LPathSegment) -> Bool {
        // FIXME:
        true
    }

    let type: PathSegmentType
    let args: [LPathArgument]
    var isAbsolute: Bool {
        type.isAbsolute
    }

    init(type: PathSegmentType, args: [LPathArgument]) {
        precondition(type == .L || type == .l)
        self.type = type
        self.args = args
    }

    func cleanUp(context: SVGPathContext) {
        context.quadrPoint = nil
        context.cubicPoint = nil
    }
}

struct HPathSegment: PathSegment {
    static func == (_: HPathSegment, _: HPathSegment) -> Bool {
        true
    }

    let type: PathSegmentType
    let args: [LPathArgument]

    init(type: PathSegmentType, args: [LPathArgument]) {
        precondition(type == .H || type == .h)
        self.type = type
        self.args = args
    }

    func cleanUp(context: SVGPathContext) {
        context.cubicPoint = nil
        context.quadrPoint = nil
    }
}

struct VPathSegment: PathSegment {
    static func == (_: VPathSegment, _: VPathSegment) -> Bool {
        true
    }

    let type: PathSegmentType
    let args: [LPathArgument]

    init(type: PathSegmentType, args: [LPathArgument]) {
        precondition(type == .V || type == .v)
        self.type = type
        self.args = args
    }

    func cleanUp(context: SVGPathContext) {
        context.cubicPoint = nil
        context.quadrPoint = nil
    }
}

// cubic Bézier
struct CPathSegment: PathSegment {
    let type: PathSegmentType
    let args: [CPathArgument]

    init(type: PathSegmentType, args: [CPathArgument]) {
        precondition(type == .C || type == .c)
        self.type = type
        self.args = args
    }

    func cleanUp(context: SVGPathContext) {
        context.quadrPoint = nil
    }
}

struct SPathSegment: PathSegment {
    let type: PathSegmentType
    let args: [CPathArgument]

    init(type: PathSegmentType, args: [CPathArgument]) {
        precondition(type == .S || type == .s)
        self.type = type
        self.args = args
    }

    func cleanUp(context: SVGPathContext) {
        context.quadrPoint = nil
    }
}

// quadratic Bézier curve
struct QPathSegment: PathSegment {
    let type: PathSegmentType
    let args: [QPathArgument]

    init(type: PathSegmentType, args: [QPathArgument]) {
        precondition(type == .Q || type == .q)
        self.type = type
        self.args = args
    }

    func cleanUp(context: SVGPathContext) {
        context.cubicPoint = nil
    }
}

struct TPathSegment: PathSegment {
    let type: PathSegmentType
    let args: [QPathArgument]

    init(type: PathSegmentType, args: [QPathArgument]) {
        precondition(type == .T || type == .t)
        self.type = type
        self.args = args
    }

    func cleanUp(context: SVGPathContext) {
        context.cubicPoint = nil
    }
}

// elliptical arc curve
struct APathSegment: PathSegment {
    let type: PathSegmentType
    let args: [APathArgument]

    init(type: PathSegmentType, args: [APathArgument]) {
        precondition(type == .A || type == .a)
        self.type = type
        self.args = args
    }

    func cleanUp(context: SVGPathContext) {
        context.cubicPoint = nil
        context.quadrPoint = nil
    }
}
