import CoreGraphics

enum SVGClipPathType: String {
    case none
    case url
}

enum SVGClipPath {
    case url(url: String)
    case none

    init?(description: String) {
        var data = description
        let clipPath = data.withUTF8 {
            let bytes = BufferView(unsafeBufferPointer: $0)!
            var scanner = SVGAttributeScanner(bytes: bytes)
            return scanner.scanClipPath()
        }
        guard let clipPath = clipPath else {
            return nil
        }
        self = clipPath
    }

    func clipIfNeeded(type: SVGElementName, frame: CGRect, context: SVGContext, cgContext: CGContext) async {
        if case let .url(id) = self,
           context.check(clipId: id),
           let clipPath = context.clipPaths[id]
        {
            if await clipPath.clip(type: type, frame: frame, context: context, cgContext: cgContext) {
                context.remove(clipId: id)
            }
        }
    }
}
