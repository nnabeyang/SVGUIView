class FontTaggedSettings<T: Comparable & Hashable>: Hashable {
    var list = [FontTaggedSetting<T>]()
    func hash(into hasher: inout Hasher) {
        hasher.combine(list)
    }

    static func == (lhs: FontTaggedSettings<T>, rhs: FontTaggedSettings<T>) -> Bool {
        lhs.list == rhs.list
    }
}

typealias FontFeature = FontTaggedSetting<Int>
typealias FontFeatureSettings = FontTaggedSettings<Int>
typealias FontVariationSettings = FontTaggedSettings<Double>

protocol _FontTag: Equatable, Comparable, Hashable {
    init(_ storage: (UInt8, UInt8, UInt8, UInt8))
}

struct FontTag: _FontTag {
    let storage: (UInt8, UInt8, UInt8, UInt8)
    init(_ storage: (UInt8, UInt8, UInt8, UInt8)) {
        self.storage = storage
    }

    static func == (lhs: FontTag, rhs: FontTag) -> Bool {
        let lhs = lhs.storage
        let rhs = rhs.storage
        return lhs.0 == rhs.0 && lhs.1 == rhs.1 && lhs.2 == rhs.2 && lhs.3 == rhs.3
    }

    static func < (lhs: FontTag, rhs: FontTag) -> Bool {
        let lhs = lhs.storage
        let rhs = rhs.storage
        if lhs.0 != rhs.0 { return lhs.0 < rhs.0 }
        if lhs.1 != rhs.1 { return lhs.1 < rhs.1 }
        if lhs.2 != rhs.2 { return lhs.2 < rhs.2 }
        return lhs.3 < rhs.3
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(storage.0)
        hasher.combine(storage.1)
        hasher.combine(storage.2)
        hasher.combine(storage.3)
    }
}

extension FontTag: ExpressibleByStringLiteral {
    init(stringLiteral value: String) {
        precondition(value.count == 4)
        let a = [UInt8](value.utf8)
        storage = (a[0], a[1], a[2], a[3])
    }
}

extension FontTag: CustomStringConvertible {
    var description: String {
        let b: [UInt8] = [storage.0, storage.1, storage.2, storage.3]
        return String(decoding: b, as: UTF8.self)
    }
}

extension FontTag: CustomDebugStringConvertible {
    var debugDescription: String {
        let b: [UInt8] = [storage.0, storage.1, storage.2, storage.3]
        return String(decoding: b, as: UTF8.self)
    }
}

extension Dictionary where Key: _FontTag {
    subscript(key: (UInt8, UInt8, UInt8, UInt8)) -> Value? {
        get { self[Key(key)] }
        set { self[Key(key)] = newValue }
    }
}

struct FontTaggedSetting<T: Comparable & Hashable>: Comparable, Hashable {
    let tag: FontTag
    let value: T

    var enabled: Bool {
        switch value {
        case let value as Bool: return value
        case let value as any FixedWidthInteger: return value.nonzeroBitCount > 0
        case let value as any BinaryFloatingPoint: return !value.isZero
        default:
            return false
        }
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(tag)
        hasher.combine(value)
    }

    static func < (lhs: FontTaggedSetting<T>, rhs: FontTaggedSetting<T>) -> Bool {
        if lhs.tag < rhs.tag { return true }
        return lhs.value < rhs.value
    }
}
