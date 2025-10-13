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
        let uiView = SVGUIView()
        return uiView
    }

    public func updateUIView(_ uiView: SVGUIView, context: Context) {
        uiView.data = data
        uiView.contentMode = contentMode.asUIView()
        uiView.configuration = context.environment.svgViewConfiguration
    }
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

private struct SVGViewConfigurationKey: EnvironmentKey {
    static let defaultValue: SVGUIViewConfiguration = .init()
}

public extension EnvironmentValues {
    @MainActor
    var svgViewConfiguration: SVGUIViewConfiguration {
        get { self[SVGViewConfigurationKey.self] }
        set { self[SVGViewConfigurationKey.self] = newValue }
    }
}
