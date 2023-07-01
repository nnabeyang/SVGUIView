import CoreGraphics

extension CGAffineTransform {
    init(style: CSSValue?, description: String) {
        if case let .transform(value) = style {
            self = value
            return
        }
        self = .init(description: description)
    }

    init(description: String) {
        var data = description
        let ops = data.withUTF8 {
            let bytes = BufferView(unsafeBufferPointer: $0)!
            var parser = SVGAttributeScanner(bytes: bytes)
            return parser.scanTransform()
        }
        var transform: CGAffineTransform = .identity
        for op in ops {
            op.apply(transform: &transform)
        }
        self = transform
    }
}
