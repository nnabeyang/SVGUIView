import SVGView
import UIKit

extension SVGText {
    func draw(_ trans: CGAffineTransform, rect: CGRect) {
        var attributes: [CFString: Any] = [:]

        if let color = fill as? SVGColor {
            attributes[kCTForegroundColorAttributeName] = color.toUIColor
        }

        if let stroke = stroke {
            if let color = stroke.fill as? SVGColor {
                attributes[kCTStrokeColorAttributeName] = color.toUIColor
            } else {
                attributes[kCTStrokeColorAttributeName] = UIColor.clear
            }
            attributes[kCTStrokeWidthAttributeName] = stroke.width
        }

        if let font = font?.toUIFont() {
            let descriptor = font.fontDescriptor as CTFontDescriptor
            let ctFont = CTFontCreateWithFontDescriptor(descriptor, 0.0, nil)
            attributes[kCTFontAttributeName] = ctFont
        }

        let alignment: CTTextAlignment
        switch textAnchor {
        case .center:
            alignment = .center
        case .leading:
            alignment = .left
        case .trailing:
            alignment = .right
        default:
            alignment = .left
        }

        let paragraph: CTParagraphStyle = withUnsafeBytes(of: alignment) { alignmentBytes in
            CTParagraphStyleCreate([
                CTParagraphStyleSetting(spec: .alignment, valueSize: MemoryLayout<CTTextAlignment>.size, value: alignmentBytes.baseAddress!),
            ], 1)
        }

        attributes[kCTParagraphStyleAttributeName] = paragraph

        guard let attributedText = CFAttributedStringCreate(kCFAllocatorDefault,
                                                            text as NSString,
                                                            attributes as CFDictionary) else { return }
        let context = UIGraphicsGetCurrentContext()!
        context.saveGState()
        let framesetter = CTFramesetterCreateWithAttributedString(attributedText)
        let frameSize = CTFramesetterSuggestFrameSizeWithConstraints(framesetter, CFRange(), nil, CGSize(width: CGFloat(Int32.max), height: CGFloat(Int32.max)), nil)
        guard let uiFont = font?.toUIFont() else { return }
        let combined = trans.concatenating(transform)
        let bounds = CGRect(origin: .init(x: 0, y: 0), size: .init(width: max(rect.width, frameSize.width), height: frameSize.height))
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(), CGPath(rect: bounds, transform: nil), nil)
        context.scaleBy(x: 1.0, y: -1.0)

        if case .center = textAnchor {
            context.translateBy(x: 0, y: -combined.ty - bounds.height + uiFont.ascender)
        } else {
            context.translateBy(x: combined.tx, y: -combined.ty - bounds.height + uiFont.ascender)
        }
        CTFrameDraw(frame, context)
        context.restoreGState()
    }
}