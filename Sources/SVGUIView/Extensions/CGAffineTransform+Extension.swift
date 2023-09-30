import CoreGraphics

extension CGAffineTransform {
    init?(style: CSSValue?, description: String) {
        if case let .transform(value) = style {
            self = value
            return
        }
        guard let transform = CGAffineTransform(description: description) else { return nil }
        self = transform
    }

    init?(style: CSSValue?) {
        if case let .transform(value) = style {
            self = value
            return
        }
        return nil
    }

    init?(description: String) {
        var data = description
        let ops = data.withUTF8 {
            let bytes = BufferView(unsafeBufferPointer: $0)!
            var parser = SVGAttributeScanner(bytes: bytes)
            return parser.scanTransform()
        }
        guard !ops.isEmpty else { return nil }
        var transform: CGAffineTransform = .identity
        for op in ops {
            op.apply(transform: &transform)
        }
        self = transform
    }

    var scale: CGAffineTransform {
        let scale = sqrt(pow(a, 2) + pow(b, 2))
        return CGAffineTransform(scaleX: scale, y: scale)
    }

    var withoutScaling: CGAffineTransform {
        concatenating(scale.inverted())
    }
}
