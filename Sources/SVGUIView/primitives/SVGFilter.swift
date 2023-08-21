import CoreGraphics

enum SVGFilterType: String {
    case none
    case url
}

enum SVGFilter {
    case url(url: String)
    case none

    init?(description: String) {
        var data = description
        let filter = data.withUTF8 {
            let bytes = BufferView(unsafeBufferPointer: $0)!
            var scanner = SVGAttributeScanner(bytes: bytes)
            return scanner.scanFilter()
        }
        guard let filter = filter else {
            return nil
        }
        self = filter
    }

    func clipIfNeeded(frame: CGRect, context: SVGContext, cgContext: CGContext) {
        if case let .url(id) = self,
           context.check(maskId: id),
           let mask = context.masks[id]
        {
            if mask.clip(frame: frame, context: context, cgContext: cgContext) {
                context.remove(maskId: id)
            }
        }
    }
}
