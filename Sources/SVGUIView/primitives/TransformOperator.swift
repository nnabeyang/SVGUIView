import Foundation
import UIKit

enum TransformType: String {
    case translate
    case scale
    case rotate
    case skewX
    case skewY
    case matrix
}

protocol TransformOperator: CustomStringConvertible {
    var type: TransformType { get }
    func apply(transform: inout CGAffineTransform)
}

struct TranslateOperator: TransformOperator {
    var type: TransformType {
        .translate
    }

    let x: Double
    let y: Double

    func apply(transform: inout CGAffineTransform) {
        transform = transform.translatedBy(x: x, y: y)
    }
}

extension TranslateOperator: CustomStringConvertible {
    var description: String {
        "\(type.rawValue)(\(x) \(y))"
    }
}

struct ScaleOperator: TransformOperator {
    var type: TransformType {
        .scale
    }

    let x: Double
    let y: Double

    func apply(transform: inout CGAffineTransform) {
        transform = transform.scaledBy(x: x, y: y)
    }
}

extension ScaleOperator: CustomStringConvertible {
    var description: String {
        "\(type.rawValue)(\(x) \(y))"
    }
}

struct RotateOperator: TransformOperator {
    var type: TransformType {
        .rotate
    }

    let angle: Double
    let origin: CGPoint?

    func apply(transform: inout CGAffineTransform) {
        let radian = angle * .pi / 180
        origin.map {
            transform = transform.translatedBy(x: $0.x, y: $0.y)
        }
        transform = transform.rotated(by: radian)
        origin.map {
            transform = transform.translatedBy(x: -$0.x, y: -$0.y)
        }
    }
}

extension RotateOperator: CustomStringConvertible {
    var description: String {
        var argsDesciption = "\(angle)"
        origin.map {
            argsDesciption += " \($0.x) \($0.y)"
        }

        return "\(type.rawValue)(\(argsDesciption))"
    }
}

struct SkewXOperator: TransformOperator {
    var type: TransformType {
        .skewX
    }

    let angle: Double

    func apply(transform: inout CGAffineTransform) {
        let radian = angle * .pi / 180
        transform = transform.shear(shx: tan(radian), shy: 0)
    }
}

extension SkewXOperator: CustomStringConvertible {
    var description: String {
        "\(type.rawValue)(\(angle))"
    }
}

struct SkewYOperator: TransformOperator {
    var type: TransformType {
        .skewY
    }

    let angle: Double

    func apply(transform: inout CGAffineTransform) {
        let radian = angle * .pi / 180
        transform = transform.shear(shx: 0, shy: tan(radian))
    }
}

extension SkewYOperator: CustomStringConvertible {
    var description: String {
        "\(type.rawValue)(\(angle))"
    }
}

struct MatrixOperator: TransformOperator {
    var type: TransformType {
        .matrix
    }

    let a: Double
    let b: Double
    let c: Double
    let d: Double
    let tx: Double
    let ty: Double

    func apply(transform: inout CGAffineTransform) {
        let matrix = CGAffineTransform(a: a, b: b, c: c, d: d, tx: tx, ty: ty)
        transform = transform.concatenating(matrix)
    }
}

extension MatrixOperator: CustomStringConvertible {
    var description: String {
        "\(type.rawValue)(\(a) \(b) \(c) \(d) \(tx) \(ty))"
    }
}

extension CGAffineTransform {
    func shear(shx: CGFloat = 0, shy: CGFloat = 0) -> CGAffineTransform {
        CGAffineTransform(a: a + c * shy, b: b + d * shy,
                          c: a * shx + c, d: b * shx + d, tx: tx, ty: ty)
    }
}
