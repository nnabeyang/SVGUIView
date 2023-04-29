import SVGView
import UIKit

extension SVGText: SVGDrawer {
    var rect: CGRect? {
        nil
    }

    var path: UIBezierPath? {
        var attributes: [CFString: Any] = [:]
        if let font = font?.toUIFont() {
            let descriptor = font.fontDescriptor as CTFontDescriptor
            let ctFont = CTFontCreateWithFontDescriptor(descriptor, 0.0, nil)
            attributes[kCTFontAttributeName] = ctFont
        }
        guard let attributedText = CFAttributedStringCreate(kCFAllocatorDefault,
                                                            text as NSString,
                                                            attributes as CFDictionary) else { return nil }
        let context = UIGraphicsGetCurrentContext()!
        context.scaleBy(x: 1.0, y: -1.0)
        let letters = CGMutablePath()
        let line = CTLineCreateWithAttributedString(attributedText)
        let runs = CTLineGetGlyphRuns(line)

        for i in 0 ..< CFArrayGetCount(runs) {
            let run = unsafeBitCast(CFArrayGetValueAtIndex(runs, i), to: CTRun.self)
            let fontPointer = CFDictionaryGetValue(CTRunGetAttributes(run), Unmanaged.passUnretained(kCTFontAttributeName).toOpaque())
            let runFont = unsafeBitCast(fontPointer, to: CTFont.self)

            for index in 0 ..< CTRunGetGlyphCount(run) {
                let range = CFRange(location: index, length: 1)
                var glyph = CGGlyph()
                var position = CGPoint()
                CTRunGetGlyphs(run, range, &glyph)
                CTRunGetPositions(run, range, &position)

                guard let letter = CTFontCreatePathForGlyph(runFont, glyph, nil) else { continue }
                letters.addPath(letter, transform: CGAffineTransform(translationX: position.x, y: position.y))
            }
        }

        let path = UIBezierPath(cgPath: letters)
        let rect = path.cgPath.boundingBoxOfPath
        if case .center = textAnchor {
            context.translateBy(x: -rect.width / 2.0, y: 0)
        }
        return path
    }
}
