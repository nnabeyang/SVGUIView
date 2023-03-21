import SVGView
import UIKit

public extension SVGText {
    func uiView() -> SVGTextUIView {
        SVGTextUIView(model: self)
    }
}

public class SVGTextUIView: UITextView {
    private static let defaultKern = 0.0123475
    var model: SVGText
    init(model: SVGText) {
        self.model = model
        super.init(frame: .zero, textContainer: nil)
        var attributes: [NSAttributedString.Key: Any] = [.kern: Self.defaultKern]
        if let color = self.model.fill as? SVGColor {
            attributes[.foregroundColor] = color.toUIColor
        }
        if let stroke = model.stroke {
            if let color = stroke.fill as? SVGColor {
                attributes[.strokeColor] = color.toUIColor
            } else {
                attributes[.strokeColor] = UIColor.clear
            }
            attributes[.strokeWidth] = stroke.width
        }

        attributedText = NSAttributedString(string: model.text, attributes: attributes)
        font = model.font?.toUIFont()
        textContainer.maximumNumberOfLines = 1
        textContainerInset = .zero
        textContainer.lineFragmentPadding = 0
        backgroundColor = .clear
    }

    override public func layoutSubviews() {
        frame = calcFrame()
        transform = model.transform
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func calcFrame() -> CGRect {
        guard let font = model.font?.toUIFont() else {
            return .zero
        }
        let textSize = NSString(string: model.text).size(withAttributes: attributedText.attributes(at: 0, effectiveRange: nil))
        return CGRect(origin: CGPoint(x: 0, y: -font.ascender), size: textSize)
    }
}
