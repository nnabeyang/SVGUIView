import CoreGraphics

enum SVGFill {
    case inherit
    case current
    case color(color: (any SVGUIColor)?, opacity: SVGOpacity?)
    case url(url: String, opacity: SVGOpacity?)

    init?(style: SVGUIStyle) {
        let opacity: SVGOpacity? = {
            switch style[.fillOpacity] {
            case let .number(value):
                return .number(value)
            default:
                return nil
            }
        }()
        if case let .fill(value) = style[.fill] {
            switch value {
            case .inherit:
                self = .inherit
            case .current:
                self = .current
            case let .url(url):
                self = .url(url: url, opacity: opacity)
            case let .color(color):
                self = .color(color: color, opacity: opacity)
            }
            return
        }
        guard let opacity = opacity else {
            return nil
        }
        self = .color(color: nil, opacity: opacity)
    }

    init?(style: SVGUIStyle, attributes: [String: String]) {
        let opacity: SVGOpacity? = {
            switch style[.fillOpacity] {
            case let .number(value):
                return .number(value)
            default:
                return SVGOpacity(attributes["fill-opacity"])
            }
        }()
        if case let .fill(value) = style[.fill] {
            switch value {
            case .inherit:
                self = .inherit
            case .current:
                self = .current
            case let .url(url):
                self = .url(url: url, opacity: opacity)
            case let .color(color):
                self = .color(color: color, opacity: opacity)
            }
            return
        }

        var data = attributes["fill", default: ""]
        let fill = data.withUTF8 {
            let bytes = BufferView(unsafeBufferPointer: $0)!
            var scanner = SVGAttributeScanner(bytes: bytes)
            return scanner.scanFill(opacity: opacity)
        }
        guard let fill = fill else {
            guard let opacity = opacity else {
                return nil
            }
            self = .color(color: nil, opacity: opacity)
            return
        }
        self = fill
    }

    init?(description: String) {
        var data = description
        let fill = data.withUTF8 {
            let bytes = BufferView(unsafeBufferPointer: $0)!
            var scanner = SVGAttributeScanner(bytes: bytes)
            return scanner.scanFill()
        }
        guard let fill = fill else {
            return nil
        }
        self = fill
    }

    init?(attributes: [String: String]) {
        let opacity = SVGOpacity(attributes["fill-opacity"])
        var data = attributes["fill", default: ""]
        let fill = data.withUTF8 {
            let bytes = BufferView(unsafeBufferPointer: $0)!
            var scanner = SVGAttributeScanner(bytes: bytes)
            return scanner.scanFill(opacity: opacity)
        }
        guard let fill = fill else {
            return nil
        }
        self = fill
    }

    init?(lhs: SVGFill?, rhs: SVGFill?) {
        guard let rhs = rhs else {
            guard let lhs = lhs else { return nil }
            self = lhs
            return
        }
        guard let lhs = lhs else {
            self = rhs
            return
        }
        switch (lhs, rhs) {
        case let (.color(rc, lo), .url(ru, ro)):
            if rc != nil {
                self = .color(color: rc, opacity: lo ?? ro)
            } else {
                self = .url(url: ru, opacity: lo ?? ro)
            }
        case let (.url(lu, lo), .color(_, ro)),
             let (.url(lu, lo), .url(_, ro)):
            self = .url(url: lu, opacity: lo ?? ro)
        case let (.color(lc, lo), .color(rc, ro)):
            self = .color(color: lc ?? rc, opacity: lo ?? ro)
        default:
            self = lhs
        }
    }
}

extension SVGFill: Equatable {
    static func == (lhs: SVGFill, rhs: SVGFill) -> Bool {
        switch (lhs, rhs) {
        case let (.color(l, lo), .color(r, ro)):
            return l?.description == r?.description && lo == ro
        case let (.url(l, lo), .url(r, ro)):
            return l == r && lo == ro
        default:
            return false
        }
    }
}

extension SVGFill: Encodable {
    func encode(to encoder: any Encoder) throws {
        switch self {
        case .inherit:
            try "inherit".encode(to: encoder)
        case .current:
            try "currentColor".encode(to: encoder)
        case let .color(color: color, opacity: opacity):
            var container = encoder.unkeyedContainer()
            if let color = color {
                try container.encode(color)
            }
            if let opacity = opacity {
                try container.encode(opacity)
            }
        case let .url(str, _):
            try "url(\(str))".encode(to: encoder)
        }
    }
}
