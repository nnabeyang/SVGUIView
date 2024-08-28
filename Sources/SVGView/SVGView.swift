import SVGUIView
import SwiftUI

public struct SVGView: UIViewRepresentable {
    let data: Data
    let contentMode: ContentMode

    public init(data: Data, contentMode: ContentMode = .fit) {
        self.data = data
        self.contentMode = contentMode
    }

    public init(contentsOf url: URL, contentMode: ContentMode = .fit) {
        let data = (try? Data(contentsOf: url)) ?? Data()
        self.init(data: data, contentMode: contentMode)
    }

    public func makeUIView(context _: Context) -> SVGUIView {
        let uiView = SVGUIView(data: data)
        uiView.contentMode = contentMode.asUIView()
        return uiView
    }

    public func updateUIView(_: SVGUIView, context _: Context) {}
}

extension ContentMode {
    func asUIView() -> UIKit.UIView.ContentMode {
        switch self {
        case .fit:
            return .scaleAspectFit
        case .fill:
            return .scaleAspectFill
        }
    }
}
