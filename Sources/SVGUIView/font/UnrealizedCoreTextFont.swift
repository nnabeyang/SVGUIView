import _SPI
import CoreText
import Foundation

class UnrealizedCoreTextFont {
    enum BaseFont {
        case font(CTFont)
        case descriptor(CTFontDescriptor)
    }

    let baseFont: BaseFont
    var weight: Double = 0
    var width: Double = 0
    var slope: Double = 0
    var size: CGFloat = 0
    var applyTraitsVariations: ApplyTraitsVariations = .yes
    var fontStyleAxis: FontStyleAxis = .slnt

    var attributes: [CFString: Any] = [:]

    init(font: CTFont) {
        baseFont = .font(font)
    }

    init(descriptor: CTFontDescriptor) {
        baseFont = .descriptor(descriptor)
    }

    func setSize(size: Double) {
        attributes[kCTFontSizeAttribute] = size
    }

    func modifyFromContext(fontDescription: FontDescription, fontCreationContext: FontCreationContext,
                           applyTraitsVariations: ApplyTraitsVariations)
    {
        precondition(applyTraitsVariations == .yes)
        if case .yes = applyTraitsVariations {
            let fontSelectionRequest = fontDescription.fontSelectionRequest
            weight = fontSelectionRequest.weight.double
            width = fontSelectionRequest.width.double
            slope = (fontSelectionRequest.slope ?? FontSelectionValue.normalItalicValue).double
            fontStyleAxis = fontDescription.fontStyleAxis
            let fontFaceCapabilities = fontCreationContext.fontFaceCapabilities
            if let weightValue = fontFaceCapabilities.weight {
                weight = max(min(weight, weightValue.upperBound.double), weightValue.lowerBound.double)
            }
            if let widthValue = fontFaceCapabilities.width {
                width = max(min(width, widthValue.upperBound.double), widthValue.lowerBound.double)
            }
            if let slopeValue = fontFaceCapabilities.slope {
                slope = max(min(slope, slopeValue.upperBound.double), slopeValue.lowerBound.double)
            }
        }
        size = getSize()

        modifyFromContext(attributes: &attributes, fontDescription: fontDescription,
                          fontCreationContext: fontCreationContext, applyTraitsVariations: applyTraitsVariations,
                          weight: weight, width: width, slope: slope, size: size)
        SystemFontDatabaseCoreText.addAttributesForInstalledFonts(attributes: &attributes,
                                                                  allowUserInstalledFonts: fontDescription.shouldAllowUserInstalledFonts)
    }

    typealias VariationsMap = [FontTag: Double]

    func modifyFromContext(attributes: inout [CFString: Any], fontDescription _: FontDescription,
                           fontCreationContext _: FontCreationContext,
                           applyTraitsVariations: ApplyTraitsVariations,
                           weight: Double, width: Double, slope: Double, size _: Double)
    {
        var variationsToBeApplied = VariationsMap()
        if applyTraitsVariations == .yes {
            variationsToBeApplied["wght"] = weight
            variationsToBeApplied["wdth"] = width
            variationsToBeApplied["slnt"] = slope
        }
        applyVariations(attributes: &attributes, variationsToBeApplied: variationsToBeApplied)
    }

    func applyVariations(attributes: inout [CFString: Any], variationsToBeApplied: VariationsMap) {
        if variationsToBeApplied.isEmpty { return }
        var variationDictionary = [CFNumber: CFNumber]()
        for (key, value) in variationsToBeApplied {
            let p = key.storage
            let tag = (Int32(p.0) << 24 | Int32(p.1) << 16 | Int32(p.2) << 8 | Int32(p.3)) as CFNumber
            let value = value as CFNumber
            variationDictionary[tag] = value
        }
        attributes[kCTFontVariationAttribute] = variationDictionary
    }

    func getSize() -> Double {
        if let sizeAttribute = attributes[kCTFontSizeAttribute] as? NSNumber {
            return sizeAttribute.doubleValue
        }

        let sizeAttribute: Double? = {
            switch baseFont {
            case let .font(font):
                guard let value = CTFontCopyAttribute(font, kCTFontSizeAttribute) as? NSNumber else { return nil }
                return value.doubleValue
            case let .descriptor(descriptor):
                guard let value = CTFontDescriptorCopyAttribute(descriptor, kCTFontSizeAttribute) as? NSNumber else { return nil }
                return value.doubleValue
            }
        }()
        return sizeAttribute ?? 0
    }

    func realize() -> CTFont? {
        let font: CTFont? = {
            switch baseFont {
            case let .font(font):
                if attributes.isEmpty { return font }
                let modification = CTFontDescriptorCreateWithAttributes(attributes as CFDictionary)
                return CTFontCreateCopyWithAttributes(font, size, nil, modification)
            case let .descriptor(descriptor):
                if attributes.isEmpty {
                    return CTFontCreateWithFontDescriptor(descriptor, CGFloat(size), nil)
                }
                let updatedFontDescriptor = CTFontDescriptorCreateCopyWithAttributes(descriptor, attributes as CFDictionary)
                return CTFontCreateWithFontDescriptor(updatedFontDescriptor, CGFloat(size), nil)
            }
        }()
        return font
    }
}
