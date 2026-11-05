public import SVGUIView
public import SwiftUI

/// A SwiftUI view that displays a single SVG image.
///
/// The view parses its SVG data off the main actor, so that a larger document
/// doesn't block the main actor. It shows the image when the data is parsed,
/// and when the data changes, it keeps showing the previous image until the new
/// data is parsed.
///
/// The view takes its rendering settings from
/// ``SwiftUICore/EnvironmentValues/svgViewConfiguration``.
public struct SVGView: UIViewRepresentable {
  /// The SVG data that the view displays, or the file that it's read from.
  enum Content: Equatable {
    case data(Data)
    case file(URL)
  }

  let content: Content
  let contentMode: SwiftUI.ContentMode

  /// Creates a view that displays the given SVG data.
  ///
  /// - Parameters:
  ///   - data: The SVG data to display.
  ///   - contentMode: How the image fits into the view's bounds.
  public init(data: Data, contentMode: SwiftUI.ContentMode = .fit) {
    content = .data(data)
    self.contentMode = contentMode
  }

  /// Creates a view that displays the SVG file at the given URL.
  ///
  /// The view reads the file off the main actor when it's shown, and reads it
  /// again only when the URL changes, also if the file changes.
  ///
  /// - Parameters:
  ///   - url: The URL of an SVG file. If it cannot be read, the view is empty.
  ///   - contentMode: How the image fits into the view's bounds.
  public init(contentsOf url: URL, contentMode: SwiftUI.ContentMode = .fit) {
    content = .file(url)
    self.contentMode = contentMode
  }

  public func makeCoordinator() -> Coordinator {
    Coordinator()
  }

  public func makeUIView(context _: Context) -> SVGUIView {
    let uiView = SVGUIView()
    return uiView
  }

  public func updateUIView(_ uiView: SVGUIView, context: Context) {
    context.coordinator.load(content, into: uiView)
    uiView.contentMode = contentMode.asUIView()
    uiView.configuration = context.environment.svgViewConfiguration
  }

  public static func dismantleUIView(_: SVGUIView, coordinator: Coordinator) {
    coordinator.cancel()
  }

  /// Loads the content of the view into its SVGUIView, off the main actor.
  @MainActor
  public final class Coordinator {
    /// The content that the coordinator loads or loaded last.
    private var content: Content?
    /// The loading in progress, which loading other content cancels.
    private(set) var task: Task<Void, Never>?

    /// Starts loading the content, unless it's the content that the coordinator already loads.
    func load(_ content: Content, into uiView: SVGUIView) {
      // The SwiftUI view is updated whenever its parent's body is, mostly with the same content.
      guard content != self.content else { return }
      self.content = content
      task?.cancel()
      task = Task { [weak uiView] in
        let data =
          switch content {
          case .data(let data): data
          case .file(let url): await Self.read(url)
          }
        guard !Task.isCancelled else { return }
        await uiView?.setData(data)
      }
    }

    /// Stops the loading in progress.
    func cancel() {
      task?.cancel()
      task = nil
    }

    /// Reads a file off the main actor, or returns empty data if it can't be read.
    @concurrent
    nonisolated private static func read(_ url: URL) async -> Data {
      (try? Data(contentsOf: url)) ?? Data()
    }
  }

  /// Takes the size that SwiftUI proposes, and the size of the document in a dimension without a proposal.
  ///
  /// Otherwise SwiftUI keeps the view at least as large as the document, whose size is the view's intrinsic
  /// content size, and the view doesn't fit in a smaller frame.
  public func sizeThatFits(_ proposal: ProposedViewSize, uiView: SVGUIView, context _: Context) -> CGSize? {
    let documentSize = uiView.intrinsicContentSize
    return CGSize(
      width: proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? documentSize.width,
      height: proposal.height.flatMap { $0.isFinite ? $0 : nil } ?? documentSize.height)
  }
}

extension SwiftUI.ContentMode {
  /// Returns the UIKit content mode that corresponds to this content mode.
  ///
  /// `fit` becomes `UIView.ContentMode.scaleAspectFit` and `fill` becomes
  /// `UIView.ContentMode.scaleAspectFill`.
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

extension EnvironmentValues {
  /// The rendering settings for ``SVGView/SVGView`` instances in this
  /// environment.
  public var svgViewConfiguration: SVGUIViewConfiguration {
    get { self[SVGViewConfigurationKey.self] }
    set { self[SVGViewConfigurationKey.self] = newValue }
  }
}
