struct FontSelectionRequest: Equatable {
    var weight: FontSelectionValue
    var width: FontSelectionValue
    var slope: FontSelectionValue?
    init(weight: FontSelectionValue = .zero, width: FontSelectionValue = .zero, slope: FontSelectionValue? = nil) {
        self.weight = weight
        self.width = width
        self.slope = slope
    }
}

extension FontSelectionRequest: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(weight)
        hasher.combine(width)
        hasher.combine(slope)
    }
}

class FontSelectionAlgorithm {
    struct DistanceResult {
        let distance: FontSelectionValue
        let value: FontSelectionValue
    }

    typealias DistanceFunction = (FontSelectionCapabilities) -> DistanceResult
    var request: FontSelectionRequest
    var capabilities: [FontSelectionCapabilities]
    var capabilitiesBounds: FontSelectionCapabilities

    init(request: FontSelectionRequest, capabilities: [FontSelectionCapabilities], capabilitiesBounds: FontSelectionCapabilities) {
        self.capabilities = capabilities
        self.capabilitiesBounds = capabilitiesBounds
        self.request = request
    }

    private func stretchDistance(capabilities: FontSelectionCapabilities) -> DistanceResult {
        let width = capabilities.width
        if width.contains(request.width) {
            return DistanceResult(distance: FontSelectionValue(), value: request.width)
        }
        if request.width > .normalStretchValue {
            if width.lowerBound > request.width {
                return DistanceResult(distance: width.lowerBound - request.width, value: width.lowerBound)
            }
            precondition(width.upperBound < request.width)
            let threshold = max(request.width, capabilitiesBounds.width.upperBound)
            return DistanceResult(distance: threshold - width.upperBound, value: width.upperBound)
        }
        if width.upperBound < request.width {
            return DistanceResult(distance: request.width - width.upperBound, value: width.upperBound)
        }
        precondition(width.lowerBound > request.width)
        let threshold = min(request.width, capabilitiesBounds.width.lowerBound)
        return DistanceResult(distance: width.lowerBound - threshold, value: width.lowerBound)
    }

    private func styleDistance(capabilities: FontSelectionCapabilities) -> DistanceResult {
        let slope = capabilities.slope
        let requestSlope = request.slope ?? FontSelectionValue.normalItalicValue
        if slope.contains(requestSlope) {
            return DistanceResult(distance: FontSelectionValue(), value: requestSlope)
        }
        if requestSlope >= FontSelectionValue.italicThreshold {
            if slope.lowerBound > requestSlope {
                return DistanceResult(distance: slope.lowerBound - requestSlope, value: capabilitiesBounds.slope.upperBound)
            }
            precondition(requestSlope > slope.upperBound)
            let threshold = max(requestSlope, capabilities.slope.upperBound)
            return DistanceResult(distance: threshold - slope.upperBound, value: slope.upperBound)
        }
        if requestSlope >= FontSelectionValue() {
            if slope.upperBound >= FontSelectionValue(), slope.upperBound < requestSlope {
                return DistanceResult(distance: requestSlope - slope.upperBound, value: slope.upperBound)
            }
            if slope.lowerBound > requestSlope {
                return DistanceResult(distance: slope.lowerBound, value: slope.lowerBound)
            }
            precondition(slope.lowerBound < FontSelectionValue())
            let threshold = max(requestSlope, capabilities.slope.upperBound)
            return DistanceResult(distance: threshold - slope.upperBound, value: slope.upperBound)
        }
        if requestSlope < -FontSelectionValue.italicThreshold {
            if slope.lowerBound > requestSlope, slope.lowerBound <= FontSelectionValue() {
                return DistanceResult(distance: slope.lowerBound - requestSlope, value: slope.lowerBound)
            }
            if slope.upperBound < requestSlope {
                return DistanceResult(distance: -slope.upperBound, value: slope.lowerBound)
            }
            precondition(slope.lowerBound > FontSelectionValue())
            let threshold = min(requestSlope, capabilities.slope.lowerBound)
            return DistanceResult(distance: slope.lowerBound - threshold, value: slope.lowerBound)
        }
        if slope.lowerBound < requestSlope {
            return DistanceResult(distance: requestSlope - slope.upperBound, value: slope.upperBound)
        }
        precondition(slope.lowerBound > requestSlope)
        let threshold = min(requestSlope, capabilities.slope.lowerBound)
        return DistanceResult(distance: slope.lowerBound - threshold, value: slope.lowerBound)
    }

    private func weightDistance(capabilities: FontSelectionCapabilities) -> DistanceResult {
        let weight = capabilities.weight
        let requestWeight = request.weight
        if weight.contains(request.weight) {
            return DistanceResult(distance: .zero, value: request.weight)
        }
        if requestWeight >= .lowerWeightSearchThreshold, requestWeight <= .upperWeightSearchThreshold {
            if weight.lowerBound > requestWeight, weight.lowerBound <= .upperWeightSearchThreshold {
                return DistanceResult(distance: weight.lowerBound - requestWeight, value: weight.lowerBound)
            }
            if weight.upperBound < requestWeight {
                return DistanceResult(distance: .upperWeightSearchThreshold - weight.lowerBound, value: weight.lowerBound)
            }
            precondition(weight.lowerBound > .upperWeightSearchThreshold)
            let threshold = min(requestWeight, capabilitiesBounds.weight.lowerBound)
            return DistanceResult(distance: weight.lowerBound - threshold, value: weight.lowerBound)
        }
        if requestWeight < .lowerWeightSearchThreshold {
            if weight.upperBound < requestWeight {
                return DistanceResult(distance: requestWeight - weight.upperBound, value: weight.upperBound)
            }
            precondition(weight.lowerBound > requestWeight)
            let threshold = min(requestWeight, capabilitiesBounds.weight.lowerBound)
            return DistanceResult(distance: weight.lowerBound - threshold, value: weight.lowerBound)
        }
        precondition(requestWeight >= .upperWeightSearchThreshold)
        if weight.lowerBound > requestWeight {
            return DistanceResult(distance: weight.lowerBound - requestWeight, value: weight.lowerBound)
        }
        precondition(weight.upperBound < requestWeight)
        let threshold = max(requestWeight, capabilitiesBounds.weight.upperBound)
        return DistanceResult(distance: threshold - weight.upperBound, value: weight.upperBound)
    }

    private func bestValue(eliminated: [Bool], computeDistance: DistanceFunction) -> FontSelectionValue {
        var smallestDistance: DistanceResult? = nil
        for i in 0 ..< capabilities.count {
            if eliminated[i] { continue }
            let distanceResult = computeDistance(capabilities[i])
            if smallestDistance == nil {
                smallestDistance = distanceResult
            } else if let distance = smallestDistance, distanceResult.distance < distance.distance {
                smallestDistance = distanceResult
            }
        }
        return smallestDistance!.value
    }

    private func filterCapability(eliminated: inout [Bool], computeDistance: DistanceFunction, key: KeyPath<FontSelectionCapabilities, ClosedRange<FontSelectionValue>>) {
        let value = bestValue(eliminated: eliminated, computeDistance: computeDistance)
        for i in 0 ..< capabilities.count {
            let capability = capabilities[i][keyPath: key]
            let result = capability.contains(value)
            eliminated[i] = eliminated[i] || !result
        }
    }

    func indexOfBestCapabilities() -> Int? {
        var eliminated = [Bool].init(repeating: false, count: 256)
        filterCapability(eliminated: &eliminated, computeDistance: stretchDistance(capabilities:), key: \.width)
        filterCapability(eliminated: &eliminated, computeDistance: styleDistance(capabilities:), key: \.slope)
        filterCapability(eliminated: &eliminated, computeDistance: weightDistance(capabilities:), key: \.weight)
        return eliminated.firstIndex(of: false)
    }
}

struct FontSelectionSpecifiedCapabilities: Hashable {
    var weight: ClosedRange<FontSelectionValue>?
    var width: ClosedRange<FontSelectionValue>?
    var slope: ClosedRange<FontSelectionValue>?

    init(weight: ClosedRange<FontSelectionValue>? = nil, width: ClosedRange<FontSelectionValue>? = nil, slope: ClosedRange<FontSelectionValue>? = nil) {
        self.weight = weight
        self.width = width
        self.slope = slope
    }

    var computeWeight: ClosedRange<FontSelectionValue> {
        weight ?? .init(bound: .normalWeightValue)
    }

    var computeWidth: ClosedRange<FontSelectionValue> {
        width ?? .init(bound: .normalStretchValue)
    }

    var computeSlope: ClosedRange<FontSelectionValue> {
        slope ?? .init(bound: .normalItalicValue)
    }
}
