import CoreText

struct FontInterrogation {
  enum VariationType {
    case trueTypeGX
    case openType18
  }

  enum TrackingType {
    case automatic
    case manual
  }

  var variationType: VariationType?
  var trackingType: TrackingType?
  var openTypeShaping = false
  var aatShaping = false

  init(font: CTFont) {
    guard let tables = CTFontCopyAvailableTables(font, CTFontTableOptions(rawValue: 0)) else {
      return
    }
    var foundStat = false
    var foundTrak = false
    let count = CFArrayGetCount(tables)
    for i in 0..<count {
      let tableTag = unsafeBitCast(CFArrayGetValueAtIndex(tables, i), to: Int.self)
      switch Int(tableTag) {
      case kCTFontTableFvar:
        if variationType == nil {
          variationType = .trueTypeGX
        }
      case kCTFontTableSTAT:
        foundStat = true
        variationType = .openType18
      case kCTFontTableMorx, kCTFontTableMort:
        aatShaping = true
      case kCTFontTableGPOS, kCTFontTableGSUB:
        openTypeShaping = true
      case kCTFontTableTrak:
        foundTrak = true
      default:
        break
      }
    }
    if foundTrak {
      trackingType = foundStat ? .automatic : .manual
    }
  }

  static func normalizeSlope(_ value: Double) -> Double {
    value * 300
  }

  static func normalizeGXWeight(_ value: Double) -> Double {
    523.7 * value - 109.3
  }

  static func normalizeVariationWidth(_ value: Double) -> Double {
    if value <= 1.25 {
      return value * 100
    } else if value <= 1.375 {
      return value * 200 - 125
    } else {
      return value * 400 - 400
    }
  }
}
