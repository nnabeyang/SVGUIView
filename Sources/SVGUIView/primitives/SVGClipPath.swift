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
}
