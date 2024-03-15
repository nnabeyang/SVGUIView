struct FontSizeAdjust: Equatable {
    enum ValueType {
        case number
        case fromFont
    }

    enum Metric: UInt8 {
        case exHeight
        case capHeight
        case chWIdth
        case icWidth
        case icHeight
    }

    let metric: Metric = .exHeight
    let type: ValueType = .number
    let value: Double? = nil

    var isFromFont: Bool {
        type == .fromFont
    }

    var isNone: Bool {
        value == nil && type == .fromFont
    }
}
