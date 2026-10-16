public import SVGUIView
public import SwiftUI

/// A SwiftUI view that displays a single SVG image.
///
/// The view takes its rendering settings from
/// `EnvironmentValues.svgViewConfiguration`.
public struct SVGView: UIViewRepresentable {
  let data: Data
  let contentMode: SwiftUI.ContentMode

  /// Creates a view that displays the given SVG data.
  ///
  /// - Parameters:
  ///   - data: The SVG data to display.
  ///   - contentMode: How the image fits into the view's bounds.
  public init(data: Data, contentMode: SwiftUI.ContentMode = .fit) {
    self.data = data
    self.contentMode = contentMode
  }

  /// Creates a view that displays the SVG file at the given URL.
  ///
  /// - Parameters:
  ///   - url: The URL of an SVG file. The file is read synchronously. If it
  ///     cannot be read, the view is empty.
  ///   - contentMode: How the image fits into the view's bounds.
  public init(contentsOf url: URL, contentMode: SwiftUI.ContentMode = .fit) {
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

extension SwiftUI.ContentMode {
  /// Returns the UIKit content mode that corresponds to this content mode.
  ///
  /// `fit` becomes `UIView.ContentMode.scaleAspectFit` and `fill` becomes
  /// `UIView.ContentMode.scaleAspectFill`.
  public func asUIView() -> UIKit.UIView.ContentMode {
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

extension EnvironmentValues {
  /// The rendering settings for ``SVGView/SVGView`` instances in this
  /// environment.
  @MainActor
  public var svgViewConfiguration: SVGUIViewConfiguration {
    get { self[SVGViewConfigurationKey.self] }
    set { self[SVGViewConfigurationKey.self] = newValue }
  }
}
