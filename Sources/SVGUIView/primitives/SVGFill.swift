enum SVGFill {
    case inherit
    case current
    case color(color: any SVGUIColor, opacity: Double)
    case url(String)

    init?(style: SVGUIStyle) {
        let opacity: Double = {
            guard case let .number(value) = style[.fillOpacity] else {
                return 1
            }
            return value
        }()
        if case let .fill(value) = style[.fill] {
            switch value {
            case .inherit:
                self = .inherit
            case .current:
                self = .current
            case let .url(url):
                self = .url(url)
            case let .color(color):
                self = .color(color: color, opacity: opacity)
            }
            return
        }
        return nil
    }

    init?(style: SVGUIStyle, attributes: [String: String]) {
        let opacity: Double = {
            guard case let .number(value) = style[.fillOpacity] else {
                return Double(attributes["fill-opacity", default: ""].trimmingCharacters(in: .whitespaces)) ?? 1
            }
            return value
        }()
        if case let .fill(value) = style[.fill] {
            switch value {
            case .inherit:
                self = .inherit
            case .current:
                self = .current
            case let .url(url):
                self = .url(url)
            case let .color(color):
                self = .color(color: color, opacity: opacity)
            }
            return
        }

        var data = attributes["fill", default: ""]
        let fill = data.withUTF8 {
            let bytes = BufferView(unsafeBufferPointer: $0)!
            var scanner = SVGColorScanner(bytes: bytes, opacity: opacity)
            return scanner.scan()
        }
        guard let fill = fill else {
            return nil
        }
        self = fill
    }

    init?(description: String) {
        var data = description
        let fill = data.withUTF8 {
            let bytes = BufferView(unsafeBufferPointer: $0)!
            var scanner = SVGColorScanner(bytes: bytes)
            return scanner.scan()
        }
        guard let fill = fill else {
            return nil
        }
        self = fill
    }

    init?(attributes: [String: String]) {
        let opacity = Double(attributes["fill-opacity", default: ""].trimmingCharacters(in: .whitespaces)) ?? 1
        var data = attributes["fill", default: ""]
        let fill = data.withUTF8 {
            let bytes = BufferView(unsafeBufferPointer: $0)!
            var scanner = SVGColorScanner(bytes: bytes, opacity: opacity)
            return scanner.scan()
        }
        guard let fill = fill else {
            return nil
        }
        self = fill
    }
}

extension SVGFill: Equatable {
    static func == (lhs: SVGFill, rhs: SVGFill) -> Bool {
        switch (lhs, rhs) {
        case let (.color(l, lo), .color(r, ro)):
            return l.description == r.description && lo == ro
        case let (.url(l), .url(r)):
            return l == r
        default:
            return false
        }
    }
}

extension SVGFill: Encodable {
    func encode(to encoder: Encoder) throws {
        switch self {
        case .inherit:
            try "inherit".encode(to: encoder)
        case .current:
            try "currentColor".encode(to: encoder)
        case let .color(color: color, _):
            try color.encode(to: encoder)
        case let .url(str):
            try "url(\(str))".encode(to: encoder)
        }
    }
}
